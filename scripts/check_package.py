#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Validate the package's registration and self-contained source resources."""
from pathlib import Path
import hashlib
import json
import sys
import zipfile
import xml.etree.ElementTree as ET

package = Path(sys.argv[1])
with zipfile.ZipFile(package) as archive:
    assert archive.testzip() is None, 'Corrupt ZIP entry'
    names = set(archive.namelist())
    required = {'adapter.py','Jobs.xcu','description.xml','description.txt','META-INF/manifest.xml','ui/ribbon.html','ui/settings.html','ui/lo365-web-ribbon.dylib','source/build.py','source/bridge.mm','recover.py','LICENSE','NOTICE.txt','README.md','docs/installation.md','build-record.json'}
    assert required <= names, 'Missing resources: '+str(required-names)
    assert all(not n.startswith('/') and '..' not in Path(n).parts for n in names), 'Unsafe archive path'
    assert not any(Path(n).suffix.lower() in ['.ttf','.otf','.ttc'] for n in names), 'Unexpected bundled fonts'
    ns='{http://openoffice.org/extensions/description/2006}'
    metadata=ET.fromstring(archive.read('description.xml'))
    assert metadata.find(ns+'identifier').get('value')=='org.docua.extension'
    assert metadata.find(ns+'platform').get('value')=='macosx_aarch64'
    manifest=ET.fromstring(archive.read('META-INF/manifest.xml'))
    entries={e.get('{http://openoffice.org/2001/manifest}full-path') for e in manifest}
    assert {'adapter.py','Jobs.xcu'} <= entries
    adapter=archive.read('adapter.py').decode()
    assert "IDENTIFIER = 'org.docua.extension'" in adapter
    assert 'org.docua.StartupJob' in archive.read('Jobs.xcu').decode()
    record=json.loads(archive.read('build-record.json'))
    for name,digest in record['files'].items():
        assert hashlib.sha256(archive.read(name)).hexdigest()==digest, 'Hash mismatch: '+name
    for name in names:
        if name.endswith('.html'):
            assert 'Content-Security-Policy' in archive.read(name).decode(), 'Missing CSP: '+name
print('PASS: registration, archive integrity, resource hashes, source inclusion, and font exclusion')
print(hashlib.sha256(package.read_bytes()).hexdigest())
