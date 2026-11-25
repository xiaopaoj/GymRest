"""Validate the shipped offline catalog and the manually maintainable media manifest."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = json.loads((ROOT / 'GymRest/Resources/ExerciseCatalog.json').read_text())


class CatalogDataTests(unittest.TestCase):
    def test_offline_catalog_has_unique_valid_prescriptions_and_sources(self):
        entries = DATA['exercises']
        self.assertGreaterEqual(len(entries), 40)
        self.assertLessEqual(len(entries), 60)
        self.assertEqual(len({entry['id'] for entry in entries}), len(entries))
        for entry in entries:
            with self.subTest(entry=entry['id']):
                self.assertTrue(entry['primary'])
                self.assertTrue(entry['equipment'])
                self.assertTrue(entry['sourceAuthor'])
                self.assertTrue(entry['sourceURL'].startswith('https://wger.de/api/v2/exerciseinfo/'))
                self.assertTrue(entry['licenseURL'].startswith('https://creativecommons.org/'))
                self.assertTrue(1 <= entry['sets'] <= 100)
                self.assertTrue(1 <= entry['repetitions'] <= 1000)
                self.assertTrue(1 <= entry['restSeconds'] <= 86400)
                self.assertTrue(0 <= entry['transitionRestSeconds'] <= 86400)
                self.assertTrue(entry['cues'])

    def test_template_references_resolve_in_catalog(self):
        # Only template slot arrays are parsed; this catches data/code drift without
        # duplicating the template prescription or ordering implementation.
        source = (ROOT / 'GymRest/Services/Catalog/TrainingTemplates.swift').read_text()
        ids = {item['id'] for item in DATA['exercises']}
        slots = re.findall(r'slots: \[("[^\]]+)\]', source)
        self.assertEqual(len(slots), 8)
        for values in slots:
            for identifier in re.findall(r'"([a-z0-9-]+)"', values):
                self.assertIn(identifier, ids)

    def test_approved_media_requires_credit_and_real_bundled_files(self):
        for item in DATA['exercises']:
            media = item['media']
            self.assertIn(media['status'], ['pending', 'approved'])
            if media['status'] == 'pending':
                self.assertIsNone(media['animationAsset'])
                self.assertIsNone(media['equipmentAsset'])
                continue
            for key in ['author', 'sourceURL', 'licenseURL']:
                self.assertTrue(media[key], (item['id'], key))
            for key in ['animationAsset', 'equipmentAsset']:
                filename = media[key]
                if filename:
                    self.assertEqual(Path(filename).name, filename)
                    self.assertTrue(list((ROOT / 'GymRest/Resources').rglob(filename)), filename)

    def test_muscle_tags_distinguish_shoulder_heads(self):
        entries = {entry['id']: entry for entry in DATA['exercises']}
        self.assertEqual(entries['dumbbell-lateral']['primary'], ['sideDelts'])
        self.assertEqual(entries['dumbbell-rear']['primary'], ['rearDelts'])
        self.assertEqual(entries['dumbbell-press']['primary'], ['frontDelts'])
        self.assertNotEqual(entries['dumbbell-lateral']['pattern'], entries['dumbbell-press']['pattern'])
