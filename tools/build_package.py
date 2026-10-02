#!/usr/bin/env python3
"""Build exclusively from the sanitized public package, with MIT notice."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path
import zipfile
from check_public_tree import check

root = Path(__file__).resolve().parents[1]
if check(root / 'package'):
    raise SystemExit('Package security gate failed')
output = root / 'dist'
output.mkdir(exist_ok=True)
target = output / 'Codex-Token-Monitor-1.0.0.plasmoid'
with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    archive.write(root / 'LICENSE', 'LICENSE')
    for path in sorted((root / 'package').rglob('*')):
        if path.is_file():
            archive.write(path, path.relative_to(root / 'package'))
print('Created:', target)
