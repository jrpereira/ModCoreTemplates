"""Ensure release notes cannot accidentally include another version's history."""
import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release_notes', ROOT / 'tools/release_notes.py')
release_notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_notes)
extract_notes = release_notes.extract_notes


class ReleaseNotesTests(unittest.TestCase):
    def test_exact_version_and_subsections(self):
        text = '# Changelog\n\n## v1.0.10\n\nNewer.\n\n## v1.0.1\n\n### Changes\n\nChosen.\n\n## v1.0.0\n\nOlder.\n'
        self.assertEqual(extract_notes(text, 'v1.0.1'), '### Changes\n\nChosen.\n')

    def test_reject_missing_duplicate_empty_and_invalid_tag(self):
        for text, tag in [
            ('## v1.0.10\nOther', 'v1.0.1'),
            ('## v1.0.1\nOne\n## v1.0.1\nTwo', 'v1.0.1'),
            ('## v1.0.1\n\n## v1.0.0\nOlder', 'v1.0.1'),
            ('## latest\nNotes', 'latest'),
        ]:
            with self.subTest(text=text, tag=tag), self.assertRaises(ValueError):
                extract_notes(text, tag)

    def test_current_version_has_release_notes(self):
        # The release workflow publishes the section named after VERSION.
        version = re.match(r'\s*(\S+)', (ROOT / 'VERSION').read_text(encoding='utf-8'))[1]
        text = (ROOT / 'docs/CHANGELOG.md').read_text(encoding='utf-8')
        self.assertTrue(extract_notes(text, 'v' + version).strip())


if __name__ == '__main__':
    unittest.main()
