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
        self.assertTrue({f for f in referenced if f.startswith("wg-")}.issubset(recorded))
        for name in ['WorkoutGuide-LICENSE.txt', 'WorkoutGuide-LICENSE-ASSETS.txt', 'WorkoutGuide-LICENSES.txt', 'WorkoutGuide-ATTRIBUTION.txt']:
            self.assertTrue((root / 'WorkoutGuide' / name).is_file())

    def test_exact_supplementary_art_and_review_boundaries(self):
        pending = {x['id'] for x in DATA['exercises'] if x['media']['status'] == 'pending'}
        self.assertEqual(len(pending), 26)
        self.assertIn('cable-lateral', pending)
        self.assertTrue({'barbell-curl', 'dumbbell-lunge', 'dumbbell-calf'}.isdisjoint(pending))
        self.assertEqual(sum(x['id'].startswith('guide-') for x in DATA['exercises']), 255)
        self.assertTrue(all(x['media']['equipmentAsset'] is None for x in DATA['exercises']))

        items = {x['id']: x for x in DATA['exercises']}
        self.assertEqual(items['neutral-pulldown']['name'], '窄距对握高位下拉')
        self.assertIn('对握高位下拉', items['neutral-pulldown']['aliases'])
        self.assertTrue(items['neutral-pulldown']['media']['frameAssets'][0].startswith('wg-close-grip-lat-pulldown-'))
        self.assertEqual(items['guide-ez-bar-curl']['name'], '站姿 EZ 曲杆弯举')
        self.assertEqual(items['guide-walking-lunge']['name'], '哑铃行进箭步蹲')
        self.assertEqual(items['guide-seated-calf-raise']['name'], '坐姿器械提踵')

    def test_all_catalog_entries_have_chinese_names_and_keep_english_lookup(self):
        for item in DATA['exercises']:
            self.assertTrue(any('\u4e00' <= c <= '\u9fff' for c in item['name']), item['id'])
            self.assertTrue(item['englishName'])
        translations = dict(line.split('\t', 1) for line in (ROOT / 'scripts/workout_guide_zh.tsv').read_text().splitlines() if line)
        imported = [x for x in DATA['exercises'] if x['id'].startswith('guide-')]
        self.assertEqual(len(imported), len(translations))
        for item in imported:
            self.assertEqual(item['name'], translations[item['id'][6:]])

    def test_all_original_frames_have_explicit_visual_review(self):
        review = json.loads((ROOT / 'scripts/workout_guide_media_review.json').read_text())
        provenance = json.loads((ROOT / 'GymRest/Resources/WorkoutGuide/WorkoutGuideSources.json').read_text())
        self.assertEqual({x['slug'] for x in review['items']}, {x['slug'] for x in provenance['exercises']})
        self.assertEqual(len(review['items']), 302)
        self.assertEqual(sum(x['result'] == 'withheld' for x in review['items']), 25)
        for entry in review['items']:
            self.assertEqual(entry['reviewedFrames'], [1, 2, 3])
            self.assertTrue(set(entry['displayFrames']).issubset({1, 2, 3}))
            self.assertFalse(entry['allowsPlayback'])
            self.assertTrue(entry['note'])
        self.assertTrue(all(not x['media'].get('allowsPlayback', False) for x in DATA['exercises']))

    def test_supplementary_originals_are_unchanged_and_credited(self):
        root = ROOT / 'GymRest/Resources'
        source = json.loads((root / 'WorkoutGuide/EverkineticSources.json').read_text())
        self.assertEqual(source['revision'], '446bb9a3d0c3beb6b84f7c9d77dfc8af707a2ab6')
        self.assertEqual({x['catalogID'] for x in source['exercises']}, {'barbell-curl', 'dumbbell-lunge', 'dumbbell-calf'})
        for item in source['exercises']:
            self.assertEqual(len(item['frames']), 2)
            for frame in item['frames']:
                data = (root / 'ExerciseFrames' / frame['file']).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(), frame['sha256'])
                self.assertEqual(list(struct.unpack('>II', data[16:24])), frame['size'])
        self.assertTrue((root / 'WorkoutGuide/Everkinetic-LICENSE.txt').exists())

    def test_every_exercise_has_steps_mistakes_and_variant_setup(self):
        guide = json.loads((ROOT / 'GymRest/Resources/ExerciseGuides.json').read_text())
        self.assertEqual({x['catalogID'] for x in guide['items']}, {x['id'] for x in DATA['exercises']})
        self.assertEqual(len(guide['items']), len(DATA['exercises']))
        for item in guide['items']:
            self.assertGreaterEqual(len(item['steps']), 4)
            self.assertGreaterEqual(len(item['mistakes']), 3)
            self.assertIn(item['name'], item['setup'])
            self.assertTrue(item['references'])
            self.assertFalse(any('查看三帧' in step for step in item['steps']))
        items = {x['catalogID']: x for x in guide['items']}
        self.assertIn('脚跟小步', ''.join(items['guide-lying-hamstring-walkout']['steps']))
        self.assertIn('肘保持基本伸直', ''.join(items['guide-scapular-push-up']['steps']))
        self.assertIn('两侧分别完成', ''.join(items['dumbbell-calf']['steps'] + items['dumbbell-calf']['notes']))
