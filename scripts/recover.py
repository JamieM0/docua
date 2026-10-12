#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
import argparse
import datetime
import json
from pathlib import Path
import re
import shutil
import subprocess

parser = argparse.ArgumentParser(description='Restore the appearance value saved by the interface extension.')
parser.add_argument('--profile',required=True,type=Path)
parser.add_argument('--apply',action='store_true')
args = parser.parse_args()
user = args.profile.expanduser().resolve()/'user'
journal = user/'docua-backup.json'
saved = json.loads(journal.read_text())
original = saved['originalApplicationAppearance']
if original not in (0,1,2): raise SystemExit('The appearance journal contains an unsupported value.')
if not saved.get('active'): raise SystemExit('The appearance journal already records a completed restoration.')
print('Original application appearance:',original)
if not args.apply:
    raise SystemExit('Preview only. Quit LibreOffice and add --apply to restore this value.')
processes = subprocess.run(['/usr/bin/pgrep','-f','/Contents/MacOS/soffice'],capture_output=True,text=True)
if processes.returncode==0: raise SystemExit('Quit every LibreOffice app before applying recovery.')
registry = user/'registrymodifications.xcu'
text = registry.read_text()
pattern = r'(<item\s+oor:path="/org\.openoffice\.Office\.Common/Appearance"[^>]*>)(.*?)(</item>)'
property_pattern = r'(<prop\s+oor:name="ApplicationAppearance"[^>]*>\s*<value[^>]*>)[^<]*(</value>\s*</prop>)'
replaced = False
def update(match):
    global replaced
    body,count = re.subn(property_pattern,lambda p:p[1]+str(original)+p[2],match[2],count=1)
    if count: replaced = True
    return match[1]+body+match[3]
text = re.sub(pattern,update,text,flags=re.S)
if not replaced:
    item = '<item oor:path="/org.openoffice.Office.Common/Appearance"><prop oor:name="ApplicationAppearance" oor:op="fuse"><value>'+str(original)+'</value></prop></item>'
    if '</oor:items>' not in text: raise SystemExit('The profile XML has an unexpected root element.')
    text = text.replace('</oor:items>',item+'</oor:items>')
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup = user/('docua-recovery-'+stamp)
backup.mkdir()
shutil.copy2(registry,backup/registry.name)
shutil.copy2(journal,backup/journal.name)
temporary = registry.with_name(registry.name+'.docua-new')
temporary.write_text(text)
temporary.replace(registry)
saved['active'] = False
journal.write_text(json.dumps(saved,indent=2)+'\n')
print('Restored appearance. Backup:',backup)
