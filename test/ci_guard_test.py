import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('ci_guard', Path(__file__).resolve().parents[1] / 'tool/ci_guard.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class PrivacyGuardTests(unittest.TestCase):
    def test_private_filenames_and_allowed_runtime(self):
        for name in ['vault_data/vault.json', 'development_artifacts/report.json', 'previous_versions/app.exe', '.env.local', 'backup.db-wal', 'credentials/key.dpapi', '../outside.txt']:
            self.assertTrue(guard.private_name(name), name)
        for name in ['lib/models/game.dart', '.env.example', 'windows/runner/resources/app_icon.ico']:
            self.assertFalse(guard.private_name(name), name)
        self.assertFalse(guard.private_name('gamevault.exe', runtime=True))
        self.assertTrue(guard.private_name('gamevault.pdb', runtime=True))

    def test_credentials_are_flagged_without_logging_values(self):
        self.assertTrue(guard.sensitive(('ghp_' + 'x' * 36).encode()))
        self.assertTrue(guard.sensitive(b'C:' + b'\\Users\\Example\\secret.txt'))
        self.assertFalse(guard.sensitive(b'const token = "fixture-token";'))

    def test_removed_secret_remains_detectable_in_history(self):
        with tempfile.TemporaryDirectory(prefix='gamevault_guard_') as temp:
            root = Path(temp)
            def git(*args):
                subprocess.run(['git', '-C', str(root), *args], check=True, capture_output=True)
            git('init', '-q')
            git('config', 'user.name', 'Synthetic fixture')
            git('config', 'user.email', 'fixture@example.invalid')
            source = root / 'sample.txt'
            source.write_text('ghp_' + 'x' * 36)
            git('add', 'sample.txt')
            git('commit', '-qm', 'Synthetic leaked fixture')
            source.write_text('safe fixture')
            git('add', 'sample.txt')
            git('commit', '-qm', 'Synthetic removal')
            command = [sys.executable, str(Path(guard.__file__).resolve()), '--history']
            result = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('ghp_' + 'x' * 36, result.stderr)


if __name__ == '__main__':
    unittest.main()
