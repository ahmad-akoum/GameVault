import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('node'), 'Node is unavailable for isolated JS probe')
class QueueContextProbeTests(unittest.TestCase):
    def test_mock_safety_contract(self):
        result = subprocess.run(['node', str(ROOT / 'test/queue_context_probe_test.cjs')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('no method invoked', result.stdout)

    def test_real_external_context_is_unbound_and_never_requests(self):
        result = subprocess.run(['node', str(ROOT / 'tool/queue_context_probe.cjs'), '42'], check=True, capture_output=True, text=True)
        data = json.loads(result.stdout)
        self.assertFalse(data['bindingPresent'])
        self.assertFalse(data['requestSent'])
        self.assertFalse(data['canRequestUpdate'])

    def test_cli_refuses_non_appid_text(self):
        for arg in ['42/launch', '1;command', '-1', '1.5', '4294967296']:
            result = subprocess.run(['node', str(ROOT / 'tool/queue_context_probe.cjs'), arg], check=True, capture_output=True, text=True)
            self.assertFalse(json.loads(result.stdout)['validAppId'])


if __name__ == '__main__':
    unittest.main()
