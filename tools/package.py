# Vendored from ModCoreSettings (owner). Do not edit copies; change the source and re-vendor.
"""Package the reviewed runtime allowlist, never arbitrary Scripts files."""
import argparse
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import package_manifest
ROOT = Path(__file__).resolve().parents[1]
MODULE = package_manifest.definition(ROOT)['module']
def version(root=ROOT):
    return package_manifest.version(root)
def build(root=ROOT, out=None, expected=None):
    return package_manifest.build(root, out, expected)
if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected-version')
    args = parser.parse_args()
    print(build(expected=args.expected_version))
