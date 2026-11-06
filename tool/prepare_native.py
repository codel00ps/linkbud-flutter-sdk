#!/usr/bin/env python3
"""Stage exact native SDK sources; never maintain a second referral implementation."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--verify', action='store_true', help='Verify bundled snapshots without native repositories')
parser.add_argument('--android-sdk', type=Path, default=root.parent / 'linkbud-android-sdk')
parser.add_argument('--ios-sdk', type=Path, default=root.parent / 'linkbud-ios-sdk')
parser.add_argument('--check', action='store_true', help='Fail if staged sources differ')
args = parser.parse_args()
pairs = [
    (args.android_sdk / 'sdk/src/main/kotlin/dev/linkbud/sdk', root / 'android/src/main/kotlin/dev/linkbud/sdk', '*.kt'),
    (args.ios_sdk / 'Sources/LinkBud', root / 'ios/linkbud_flutter/Sources/linkbud_flutter/Native', '*.swift'),
]
if args.verify:
    manifest = json.loads((root / 'native-sources.json').read_text())
    actual = {str(file.relative_to(root)): hashlib.sha256(file.read_bytes()).hexdigest()
              for _, target, _ in pairs for file in target.rglob('*') if file.is_file()}
    if not actual or actual != manifest:
        raise SystemExit('Bundled native sources do not match manifest')
    print(f'Bundled native sources verified: {len(actual)} files')
    raise SystemExit(0)
manifest = {}
for source, target, pattern in pairs:
    files = sorted(source.rglob(pattern))
    if not files:
        raise SystemExit(f'Native source not found: {source}')
    expected = {file.relative_to(source) for file in files}
    if args.check:
        actual = {file.relative_to(target) for file in target.rglob('*') if file.is_file()}
        if actual != expected:
            raise SystemExit(f'Stale native source set: {target}')
    elif target.exists():
        shutil.rmtree(target)
    for file in files:
        output = target / file.relative_to(source)
        if args.check:
            if not output.exists() or output.read_bytes() != file.read_bytes():
                raise SystemExit(f'Stale native source: {output}')
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(file, output)
        manifest[str(output.relative_to(root))] = hashlib.sha256(file.read_bytes()).hexdigest()
manifest_path = root / 'native-sources.json'
content = json.dumps(manifest, indent=2, sort_keys=True) + '\n'
if args.check:
    if not manifest_path.exists() or manifest_path.read_text() != content:
        raise SystemExit('Stale native source manifest')
else:
    manifest_path.write_text(content)
print(f'Native source parity verified: {len(manifest)} files')
