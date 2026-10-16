# Vendored from ModCoreSettings (owner). Do not edit copies; change the source and re-vendor.
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('package_mod', ROOT / 'tools/package.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


class PackageTests(unittest.TestCase):
    def test_allowlist_checksum_and_reproducibility(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'repo'
            shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns('.git', 'dist', 'work', 'state', '__pycache__'))
            (root / 'config.ini').write_text('PERSONAL_CONFIGURATION_MUST_NOT_SHIP')
            (root / 'crash.dmp').write_bytes(b'PRIVATE_DUMP')
            (root / 'Scripts/temporary_probe.lua').write_text('TEMPORARY_PROBE')
            archive = pack.build(root, out=Path(temp) / 'dist')
            before = archive.read_bytes()
            self.assertEqual(before, pack.build(root, out=Path(temp) / 'dist').read_bytes())
            self.assertEqual(archive.with_suffix('.zip.sha256').read_text().split()[0],
                             hashlib.sha256(before).hexdigest())
            spec = json.loads((ROOT / 'release-manifest.json').read_text(encoding='utf-8'))
            self.assertEqual(spec['module'], pack.MODULE)
            with ZipFile(archive) as bundle:
                names = set(bundle.namelist())
            # Every runtime script ships; probes, tests, tools and personal files never do.
            for script in (ROOT / 'Scripts').rglob('*.lua'):
                self.assertIn(pack.MODULE + '/' + script.relative_to(ROOT).as_posix(), names)
            self.assertNotIn(pack.MODULE + '/Scripts/temporary_probe.lua', names)
            self.assertFalse(any(n.endswith(('/config.ini', '.dmp')) or '/tests/' in n
                                 or '/tools/' in n.lower() for n in names))
            # Every package ships enabled by default.
            self.assertIn(pack.MODULE + '/enabled.txt', names)
            # README and CHANGELOG at the root, where present, and Markdown documents in docs/
            # are published at the module root; the BBCode Nexus description stays in the
            # repository.
            docs = [name for name in ('README.md', 'CHANGELOG.md') if (ROOT / name).exists()]
            for doc in docs + [doc.name for doc in (ROOT / 'docs').glob('*.md')]:
                self.assertIn(pack.MODULE + '/' + doc, names)
            self.assertNotIn(pack.MODULE + '/NEXUS.bb', names)
            self.assertFalse(any('/docs/' in n for n in names))
            self.assertEqual(names, {pack.MODULE + '/' + dest for dest in spec['files']}
                             | {pack.MODULE + '/manifest.json'})

    def test_dependency_placeholders_resolve_in_the_package(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'repo'
            shutil.copytree(ROOT, root, ignore=shutil.ignore_patterns('.git', 'dist', 'work', 'state', '__pycache__'))
            manifest = json.loads((root / 'mod.json').read_text(encoding='utf-8'))
            manifest['dependencies'] = [
                {'id': 'Locked', 'version': '1.0.7.1+'},
                {'id': 'Minor', 'version': '1.2.?+'},
                {'id': 'Major', 'version': '2.?.?+'},
                {'id': 'Unversioned'},
            ]
            (root / 'mod.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
            archive = pack.build(root, out=Path(temp) / 'dist')
            with ZipFile(archive) as bundle:
                shipped = json.loads(bundle.read(pack.MODULE + '/mod.json'))
            self.assertEqual([d.get('version') for d in shipped['dependencies']],
                             ['1.0.7.1+', '1.2.0+', '2.0.0+', None])
            for bad in ('1.?.3+', '1.2.?', '?.?.?+', '1.2.??+'):
                manifest['dependencies'] = [{'id': 'Bad', 'version': bad}]
                (root / 'mod.json').write_text(json.dumps(manifest), encoding='utf-8')
                with self.assertRaises(ValueError, msg=bad):
                    pack.build(root, out=Path(temp) / 'dist')

    def test_mod_json_without_placeholders_ships_unchanged(self):
        data = b'{\n  "id": "Mod",\n  "dependencies": [{"id": "Dep", "version": "1.3.1+"}]\n}\n'
        self.assertIs(pack.package_manifest.published_mod_json(data), data)

    def test_release_version_mismatch_rejected(self):
        with self.assertRaises(ValueError):
            pack.build(expected='999.0.0')

    def test_source_version(self):
        self.assertTrue(pack.package_manifest.valid_version(pack.version()))


if __name__ == '__main__':
    unittest.main()
