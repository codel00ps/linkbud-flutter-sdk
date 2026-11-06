import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2]


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / 'standalone-flutter'
        self.root.mkdir()
        shutil.copytree(SOURCE / 'tool', self.root / 'tool', ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copyfile(SOURCE / 'native-sources.json', self.root / 'native-sources.json')
        for name in json.loads((SOURCE / 'native-sources.json').read_text()):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SOURCE / name, target)

    def tearDown(self):
        self.temp.cleanup()

    def run_tool(self, name, *args):
        return subprocess.run(['python3', str(self.root / 'tool' / name), *args], capture_output=True)

    def test_independent_checkout_verifies_without_native_repositories(self):
        self.assertEqual(self.run_tool('prepare_native.py', '--verify').returncode, 0)

    def test_modified_and_extra_native_sources_fail_verification(self):
        native = self.root / next(iter(json.loads((self.root / 'native-sources.json').read_text())))
        original = native.read_bytes()
        native.write_bytes(original + b'\n')
        self.assertNotEqual(self.run_tool('prepare_native.py', '--verify').returncode, 0)
        native.write_bytes(original)
        (native.parent / 'Unexpected.kt').write_text('unexpected')
        self.assertNotEqual(self.run_tool('prepare_native.py', '--verify').returncode, 0)

    def test_archive_excludes_git_and_local_secrets(self):
        for name in ('.git/config', '.env', 'signing.jks', 'android/local.properties'):
            file = self.root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('private fixture')
        output = Path(self.temp.name) / 'preview.tar.gz'
        self.assertEqual(self.run_tool('package_preview.py', str(output)).returncode, 0)
        with tarfile.open(output) as archive:
            names = archive.getnames()
        self.assertTrue(any(name.endswith('native-sources.json') for name in names))
        self.assertFalse(any('.git/' in name or name.endswith(('.env', '.jks', 'local.properties')) for name in names))


if __name__ == '__main__':
    unittest.main()
