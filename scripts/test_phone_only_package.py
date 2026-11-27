"""Execute the production IPA packager on fixture products; no Apple SDK needed."""
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
import os

ROOT = Path(__file__).resolve().parents[1]

class PhoneOnlyPackageTests(unittest.TestCase):
    def fixture(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / 'scripts').mkdir()
        shutil.copy2(ROOT / 'scripts/package_ipa.py', root / 'scripts/package_ipa.py')
        shutil.copy2(ROOT / 'project.yml', root / 'project.yml')
        spec = (root / 'project.yml').read_text()
        version = re.search(r'MARKETING_VERSION: "([^"]+)"', spec)[1]
        build = re.search(r'CURRENT_PROJECT_VERSION: "([^"]+)"', spec)[1]
        app = root / 'DerivedData/Build/Products/Release-iphoneos/GymRest.app'
        extension = app / 'PlugIns/GymRestWidgets.appex'
        extension.mkdir(parents=True)
        for bundle, identifier in [(app, 'dev.gymrest.personal'), (extension, 'dev.gymrest.personal.widgets')]:
            info = {'CFBundleIdentifier': identifier, 'CFBundleShortVersionString': version,
                    'CFBundleVersion': build, 'CFBundleExecutable': 'Executable', 'MinimumOSVersion': '26.0',
                    'NSAlarmKitUsageDescription': 'Rest reminder', 'GymRestMediaMode': 'external',
                    'GymRestMediaSeedPolicy': 'preserve',
                    'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'}}
            (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
            (bundle / 'Executable').write_bytes(b'fixture-not-a-real-binary')
        names = ['ExerciseCatalog.json', 'ExerciseGuides.json', 'WorkoutGuideSources.json',
                 'EverkineticSources.json', 'WorkoutGuideMediaReview.json', 'Everkinetic-LICENSE.txt',
                 'WorkoutGuide-LICENSE.txt', 'WorkoutGuide-LICENSE-ASSETS.txt', 'WorkoutGuide-LICENSES.txt', 'WorkoutGuide-ATTRIBUTION.txt']
        for name in names:
            source = next((ROOT / 'GymRest/Resources').rglob(name))
            shutil.copy2(source, app / name)
        return root, app

    def run_package(self, root):
        return subprocess.run([sys.executable, 'scripts/package_ipa.py'], cwd=root,
            env={**os.environ, 'MEDIA_MODE': 'external', 'MEDIA_SEED_POLICY': 'preserve'}, capture_output=True, text=True)

    def test_phone_and_widget_are_packaged_without_watch(self):
        root, _ = self.fixture()
        result = self.run_package(root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with zipfile.ZipFile(root / 'build/GymRest-unsigned.ipa') as archive:
            self.assertIn('Payload/GymRest.app/PlugIns/GymRestWidgets.appex/Info.plist', archive.namelist())
            self.assertFalse(any('/Watch/' in name for name in archive.namelist()))

    def test_stale_watch_payload_is_rejected_even_without_a_build_flag(self):
        root, app = self.fixture()
        (app / 'Watch/GymRestWatch.app').mkdir(parents=True)
        result = self.run_package(root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('must not contain a stale Watch bundle', result.stderr)
        self.assertFalse((root / 'build/GymRest-unsigned.ipa').exists())
