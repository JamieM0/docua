#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import zipfile

SCRIPT = Path(__file__).resolve()
BASE = SCRIPT.parent.parent
EXTENSION = BASE/'extension' if (BASE/'extension').exists() else BASE
UI = BASE/'ui'
BRIDGE = BASE/'native/bridge.mm' if (BASE/'native/bridge.mm').exists() else BASE/'source/bridge.mm'
RECOVERY = BASE/'scripts/recover.py' if (BASE/'scripts/recover.py').exists() else BASE/'recover.py'
import xml.etree.ElementTree as ET
VERSION = ET.parse(EXTENSION/'description.xml').getroot().find('{http://openoffice.org/extensions/description/2006}version').get('value')
temporary = tempfile.TemporaryDirectory(prefix='.oxt-build-',dir=BASE)
STAGE = Path(temporary.name)
for name in ['adapter.py','Jobs.xcu','description.xml','description.txt']:
    shutil.copy2(EXTENSION/name, STAGE/name)
shutil.copytree(EXTENSION/'META-INF',STAGE/'META-INF',dirs_exist_ok=True)
resources = STAGE/'ui'
resources.mkdir(exist_ok=True)
for source in sorted(UI.iterdir()):
    if source.suffix in ['.html','.css','.js']:
        if source.suffix == '.html':
            policy = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; font-src 'self' data:; img-src 'self' data:; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'\">"
            html = source.read_text()
            if 'http-equiv="Content-Security-Policy"' not in html:
                html = html.replace('<meta charset="utf-8">','<meta charset="utf-8">'+policy,1)
            (resources/source.name).write_text(html)
        else:
            shutil.copy2(source,resources/source.name)
shutil.copytree(UI/'icons',resources/'icons',dirs_exist_ok=True)
(STAGE/'source').mkdir(exist_ok=True)
shutil.copy2(BRIDGE,STAGE/'source/bridge.mm')
shutil.copy2(SCRIPT,STAGE/'source/build.py')
subprocess.run(['/usr/bin/clang++','-dynamiclib','-std=c++17','-arch','arm64','-framework','Cocoa','-framework','WebKit','-Wl,-install_name,@rpath/lo365-web-ribbon.dylib',str(BRIDGE),'-o',str(resources/'lo365-web-ribbon.dylib')],check=True)
subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(resources/'lo365-web-ribbon.dylib')],check=True)
shutil.copy2(BASE/'LICENSE',STAGE/'LICENSE')
shutil.copy2(RECOVERY,STAGE/'recover.py')
shutil.copytree(BASE/'docs',STAGE/'docs')
for name in ['README.md','NOTICE.txt']:
    if (BASE/name).exists(): shutil.copy2(BASE/name,STAGE/name)
record = {'version':VERSION,'platform':'macOS-arm64','libreofficeSourcePatches':False,'files':{str(p.relative_to(STAGE)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(STAGE.rglob('*')) if p.is_file() and p.name!='build-record.json'}}
(STAGE/'build-record.json').write_text(json.dumps(record,indent=2)+'\n')
output = BASE/'dist' if EXTENSION != BASE else BASE
output.mkdir(exist_ok=True)
destination = output/('docua-'+VERSION+'-macos-arm64.oxt')
with zipfile.ZipFile(destination.with_suffix('.oxt.new'),'w',compression=zipfile.ZIP_DEFLATED) as archive:
    for source in sorted(STAGE.rglob('*')):
        if not source.is_file(): continue
        info = zipfile.ZipInfo(str(source.relative_to(STAGE)),(2026,10,12,0,0,0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        archive.writestr(info,source.read_bytes())
os.replace(destination.with_suffix('.oxt.new'),destination)
package = BASE/'.build/package'
previous = BASE/'.build/package-previous'
package.parent.mkdir(exist_ok=True)
if previous.exists(): shutil.rmtree(previous)
if package.exists(): package.rename(previous)
shutil.copytree(STAGE,package)
temporary.cleanup()
destination.with_suffix('.oxt.sha256').write_text(hashlib.sha256(destination.read_bytes()).hexdigest()+'  '+destination.name+'\n')
print(destination)
