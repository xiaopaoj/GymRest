"""Check the actual distributable archive with Python's independent ZIP reader."""
import hashlib,json,tempfile,unittest,zipfile
from pathlib import Path
from build_media_pack import build,ROOT

class MediaPackBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory();cls.path=Path(cls.temp.name)/'official.gymrestmedia';cls.manifest=build(cls.path)
    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()
    def test_archive_matches_manifest_and_original_image_bytes(self):
        with zipfile.ZipFile(self.path) as archive:
            manifest=json.loads(archive.read('manifest.json'))
            self.assertEqual(set(archive.namelist()),{'manifest.json'}|{x['path'] for x in manifest['files']})
            for item in manifest['files']:
                data=archive.read(item['path'])
                self.assertEqual(len(data),item['bytes']);self.assertEqual(hashlib.sha256(data).hexdigest(),item['sha256'])
                if item['path'].startswith('frames/'):
                    self.assertEqual(data,(ROOT/'GymRest/Resources/ExerciseFrames'/Path(item['path']).name).read_bytes())
    def test_archive_uses_only_bounded_stored_regular_entries(self):
        with zipfile.ZipFile(self.path) as archive:
            self.assertLessEqual(len(archive.infolist()),3000);self.assertFalse(archive.comment)
            for info in archive.infolist():
                self.assertEqual(info.compress_type,zipfile.ZIP_STORED);self.assertEqual(info.file_size,info.compress_size)
                self.assertLessEqual(info.file_size,10*1024*1024);self.assertFalse(info.extra);self.assertFalse(info.comment)
                self.assertEqual(info.external_attr>>16 & 0xf000,0x8000)
            self.assertLess(self.path.stat().st_size,100*1024*1024)
    def test_only_reviewed_frames_are_shipped_and_all_withheld_mappings_remain(self):
        catalog=json.loads((ROOT/'GymRest/Resources/ExerciseCatalog.json').read_text())['exercises']
        expected={name for x in catalog for name in x['media'].get('frameAssets',[]) or []}
        actual={Path(x['path']).name for x in self.manifest['files'] if x['path'].startswith('frames/')}
        self.assertEqual(actual,expected);self.assertEqual(len(actual),775)
        self.assertNotIn('wg-close-grip-bench-press-2.png',actual)
        self.assertEqual({x['catalogID']:x['media'] for x in self.manifest['artwork']},{x['id']:x['media'] for x in catalog})
    def test_reproducible_pack_and_credits(self):
        other=Path(self.temp.name)/'second.gymrestmedia';build(other)
        self.assertEqual(hashlib.sha256(self.path.read_bytes()).digest(),hashlib.sha256(other.read_bytes()).digest())
        with zipfile.ZipFile(self.path) as archive:
            self.assertIn('CC BY-SA',archive.read('credits/LICENSE.txt').decode())
            source=json.loads(archive.read('credits/Sources.json'))
            self.assertEqual(sum(len(x['frames']) for key in source.values() for x in key['exercises']),912)
    def test_explicit_execution_defaults_survive_catalog_pipeline(self):
        defaults=json.loads((ROOT/'scripts/exercise_execution_defaults.json').read_text())
        catalog={x['id']:x for x in json.loads((ROOT/'GymRest/Resources/ExerciseCatalog.json').read_text())['exercises']}
        for key,fields in defaults.items():
            for field,value in fields.items():self.assertEqual(catalog[key][field],value)
            self.assertIn(fields.get('sideCount',1),[1,2])
            if 'durationSeconds' in fields:
                self.assertIsNone(catalog[key]['repetitions']);self.assertTrue(1<=fields['durationSeconds']<=86400)
        self.assertEqual(defaults['guide-side-plank'],{'durationSeconds':40,'sideCount':2})
        self.assertEqual(defaults['guide-plank'],{'durationSeconds':40})
