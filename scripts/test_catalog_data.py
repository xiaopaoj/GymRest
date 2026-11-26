"""Validate the shipped offline catalog and the manually maintainable media manifest."""
import hashlib
import struct
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = json.loads((ROOT / 'GymRest/Resources/ExerciseCatalog.json').read_text())


class CatalogDataTests(unittest.TestCase):
    def test_offline_catalog_has_unique_valid_prescriptions_and_sources(self):
        entries = DATA['exercises']
        self.assertGreaterEqual(len(entries), 300)
        self.assertEqual(len({entry['id'] for entry in entries}), len(entries))
        for entry in entries:
            with self.subTest(entry=entry['id']):
                self.assertTrue(entry['primary'])
                self.assertTrue(entry['equipment'])
                self.assertTrue(entry['sourceAuthor'])
                self.assertTrue(entry['sourceURL'].startswith(('https://wger.de/api/v2/exerciseinfo/', 'https://github.com/bryllim/workout-guide/')))
                self.assertTrue(entry['licenseURL'].startswith('https://creativecommons.org/'))
                self.assertTrue(1 <= entry['sets'] <= 100)
                self.assertTrue(entry['repetitions'] is None or 1 <= entry['repetitions'] <= 1000)
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
            files = [media.get(key) for key in ['animationAsset', 'equipmentAsset']] + media.get('frameAssets', [])
            for filename in files:
                if filename:
                    self.assertEqual(Path(filename).name, filename)
                    self.assertTrue(list((ROOT / 'GymRest/Resources').rglob(filename)), filename)

    def test_muscle_tags_distinguish_shoulder_heads(self):
        entries = {entry['id']: entry for entry in DATA['exercises']}
        self.assertEqual(entries['dumbbell-lateral']['primary'], ['sideDelts'])
        self.assertEqual(entries['dumbbell-rear']['primary'], ['rearDelts'])
        self.assertEqual(entries['dumbbell-press']['primary'], ['frontDelts'])
        self.assertNotEqual(entries['dumbbell-lateral']['pattern'], entries['dumbbell-press']['pattern'])

    def test_workout_guide_frames_match_pinned_provenance(self):
        root = ROOT / 'GymRest/Resources'
        provenance = json.loads((root / 'WorkoutGuide/WorkoutGuideSources.json').read_text())
        self.assertEqual(len(provenance['exercises']), 302)
        self.assertEqual(provenance['revision'], 'aac599224bb9780305239607ef98540b7e0ce389')
        recorded = set()
        for exercise in provenance['exercises']:
            self.assertEqual(len(exercise['frames']), 3)
            for frame in exercise['frames']:
                path = root / 'ExerciseFrames' / frame['file']
                data = path.read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), frame['sha256'])
                self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
                self.assertEqual(struct.unpack('>II', data[16:24]), (512, 512))
                self.assertEqual(frame['attribution']['license'], 'CC BY-SA 4.0')
                recorded.add(frame['file'])
        self.assertEqual(len(recorded), 906)
        referenced = {f for x in DATA['exercises'] for f in x['media'].get('frameAssets', [])}
        self.assertEqual(recorded, referenced)
        for name in ['WorkoutGuide-LICENSE.txt', 'WorkoutGuide-LICENSE-ASSETS.txt', 'WorkoutGuide-LICENSES.txt', 'WorkoutGuide-ATTRIBUTION.txt']:
            self.assertTrue((root / 'WorkoutGuide' / name).is_file())

    def test_original_variants_without_exact_artwork_stay_unmatched(self):
        pending = {x['id'] for x in DATA['exercises'] if x['media']['status'] == 'pending'}
        self.assertEqual(pending, {'barbell-curl', 'dumbbell-lunge', 'dumbbell-calf'})
        self.assertEqual(sum(x['id'].startswith('guide-') for x in DATA['exercises']), 254)
        self.assertTrue(all(x['media']['equipmentAsset'] is None for x in DATA['exercises']))

        items = {x['id']: x for x in DATA['exercises']}
        self.assertEqual(items['neutral-pulldown']['name'], '窄距对握高位下拉')
        self.assertIn('对握高位下拉', items['neutral-pulldown']['aliases'])
        self.assertTrue(items['neutral-pulldown']['media']['frameAssets'][0].startswith('wg-close-grip-lat-pulldown-'))
        self.assertEqual(items['guide-ez-bar-curl']['name'], '站姿 EZ 曲杆弯举')
        self.assertEqual(items['guide-walking-lunge']['name'], '哑铃行进箭步蹲')
        self.assertEqual(items['guide-seated-calf-raise']['name'], '坐姿器械提踵')
