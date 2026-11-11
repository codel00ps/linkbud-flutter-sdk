#!/usr/bin/env python3
"""Build a self-contained local candidate archive after verifying native source parity."""
import argparse
from pathlib import Path
import subprocess
import tarfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
args = parser.parse_args()
output = args.output.resolve()
if output.is_relative_to(root):
    raise SystemExit('Write the archive outside the package directory')
subprocess.run(['python3', str(root / 'tool/prepare_native.py'), '--verify'], check=True)
excluded = {'.git', '.build', '.kotlin','.dart_tool', 'build', '.gradle', '.symlinks', 'Pods', 'ephemeral', 'xcuserdata', '.swiftpm', '__pycache__', '.idea'}
local = {'local.properties', 'Generated.xcconfig', 'flutter_export_environment.sh',
         'GeneratedPluginRegistrant.java', 'GeneratedPluginRegistrant.h', 'GeneratedPluginRegistrant.m', '.flutter-plugins',
         '.flutter-plugins-dependencies', 'Local.xcconfig', '.DS_Store'}
with tarfile.open(output, 'w:gz') as archive:
    for file in sorted(root.rglob('*')):
        relative = file.relative_to(root)
        if file.is_file() and not excluded.intersection(relative.parts) and file.name not in local and not file.name.startswith('.env') and file.suffix not in {'.iml', '.log', '.jks', '.keystore'}:
            archive.add(file, arcname=str(Path('linkbud_flutter') / relative), recursive=False)
print(output)
