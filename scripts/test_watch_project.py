"""Check the companion's build wiring without treating it as an Apple SDK build."""
from pathlib import Path
import unittest,re
from watch_project import generate
ROOT=Path(__file__).resolve().parents[1]

class WatchProjectTests(unittest.TestCase):
    def spec(self):
        # The real HealthKit generator performs this replacement before Watch generation.
        base=(ROOT/'project.yml').read_text()
        return base.replace('    SWIFT_VERSION: "6.0"','    SWIFT_VERSION: "6.0"\n    SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) GYMREST_HEALTHKIT"')
    def test_phone_only_spec_has_shared_protocol_but_no_embedded_watch(self):
        base=(ROOT/'project.yml').read_text()
        self.assertIn('path: CompanionShared',base);self.assertIn('GymRestWatchEnabled: false',base)
        self.assertNotIn('- target: GymRestWatch',base)
    def test_generated_companion_has_parent_identity_privacy_and_background_mode(self):
        spec=generate(self.spec())
        self.assertIn('- target: GymRestWatch\n        embed: true',spec)
        self.assertIn('GymRestWatchEnabled: true',spec)
        self.assertIn('WKCompanionAppBundleIdentifier: dev.gymrest.personal',spec)
        self.assertIn('PRODUCT_BUNDLE_IDENTIFIER: dev.gymrest.personal.watchkitapp',spec)
        self.assertIn('WKBackgroundModes: [workout-processing]',spec)
        self.assertIn('deploymentTarget: "10.0"',spec)
        self.assertIn('NSHealthShareUsageDescription:',spec);self.assertIn('NSHealthUpdateUsageDescription:',spec)
        self.assertIn('com.apple.developer.healthkit: true',spec)
        self.assertNotIn('com.apple.developer.healthkit.background-delivery',spec)
    def test_generation_requires_healthkit_and_preserves_media_mode(self):
        with self.assertRaises(ValueError):generate((ROOT/'project.yml').read_text())
        spec=generate(self.spec().replace('GymRestMediaMode: external','GymRestMediaMode: bundled'))
        self.assertIn('GymRestMediaMode: bundled',spec)
        self.assertIn('GYMREST_HEALTHKIT GYMREST_WATCH',spec)
    def test_watch_sources_never_include_phone_timer_or_artwork_assets(self):
        spec=generate(self.spec());watch=spec.split('  GymRestWatch:\n    type: application',1)[1].split('schemes:',1)[0]
        for path in ['GymRestWatch','CompanionShared','build/WatchAssets.xcassets']:self.assertIn('path: '+path,watch)
        for path in ['path: GymRest\n','path: Shared\n','ExerciseFrames','AlarmKit']:self.assertNotIn(path,watch)
    def test_ci_and_package_check_watch_product_as_well_as_phone(self):
        ci=(ROOT/'scripts/ci.sh').read_text();pack=(ROOT/'scripts/package_ipa.py').read_text()
        self.assertIn("generic/platform=watchOS Simulator",ci)
        self.assertIn('Watch/GymRestWatch.app',pack)
        self.assertIn('WKCompanionAppBundleIdentifier',pack)
        self.assertIn('GYMREST_WATCH',ci)
