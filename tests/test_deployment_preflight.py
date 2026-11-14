# Vendored from ModCoreSettings (owner). Do not edit copies; change the source and re-vendor.
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('preflight', Path(__file__).resolve().parents[1] / 'tools/deployment_preflight.py')
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)

class PreflightTests(unittest.TestCase):
    def test_path_escape(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertEqual(preflight.safe_file(root, 'Scripts/main.lua'), (root / 'Scripts/main.lua').resolve())
            for path in ['../config.ini', '/absolute', 'C:/other', 'dir\\file']:
                with self.assertRaises(ValueError):
                    preflight.safe_file(root, path)

if __name__ == '__main__':
    unittest.main()
