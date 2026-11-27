"""Run the real CI shell with fake Apple tools to verify fail-fast sequencing.
This tests shell orchestration and failure propagation, not iOS compilation.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CIPreflightTests(unittest.TestCase):
    def run_ci(self, failure=''):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / 'scripts').mkdir()
        (root / 'bin').mkdir()
        for name in ['ci.sh', 'build_release.sh']:
            shutil.copy2(ROOT / 'scripts' / name, root / 'scripts' / name)
        (root / 'scripts/prepare_icon.sh').write_text('exit 0\n')
        # The candidate-discovery heredoc runs with real Python. Other preparation
        # commands are recorded without depending on media fixtures or macOS.
        shim = '''import json,os,sys
from pathlib import Path
name=Path(sys.argv[0]).name
args=sys.argv[1:]
with Path(os.environ['CI_TRACE']).open('a') as trace:
    trace.write(json.dumps([name]+args)+'\\n')
if name=='python3':
    if args==['-']:
        os.execv(sys.executable,[sys.executable,'-'])
    if args and args[0]=='scripts/select_simulator.py': print('TEST-SIM Shutdown')
elif name=='xcode-select': print('/fake/Xcode.app/Contents/Developer')
elif name=='xcrun' and '--show-sdk-version' in args: print('26.2')
elif name=='xcodebuild':
    if 'build-for-testing' in args and os.environ['CI_FAIL']=='debug': sys.exit(66)
    if 'Release' in args and os.environ['CI_FAIL']=='release':
        print('Injected Release compiler failure',file=sys.stderr)
        sys.exit(65)
'''
        for name in ['python3', 'xcode-select', 'xcrun', 'xcodebuild', 'xcodegen']:
            path = root / 'bin' / name
            path.write_text('#!' + sys.executable + '\n' + shim)
            path.chmod(0o755)
        trace = root / 'trace.jsonl'
        result = subprocess.run(['bash', 'scripts/ci.sh'], cwd=root,
            env={**os.environ, 'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'],
                 'CI_TRACE': str(trace), 'CI_FAIL': failure,
                 'GYMREST_HEALTHKIT': 'true'},
            capture_output=True, text=True, timeout=30)
        events = [json.loads(line) for line in trace.read_text().splitlines()]
        return root, result, events

    def test_release_compiles_before_boot_tests_and_packaging(self):
        _, result, events = self.run_ci()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        def index(predicate):
            return next(i for i, event in enumerate(events) if predicate(event))
        debug = index(lambda e: 'build-for-testing' in e)
        release = index(lambda e: e[0] == 'xcodebuild' and 'Release' in e)
        boot = index(lambda e: e[:3] == ['xcrun', 'simctl', 'boot'])
        tests = index(lambda e: 'test-without-building' in e)
        package = index(lambda e: 'scripts/package_ipa.py' in e)
        self.assertLess(debug, release)
        self.assertLess(release, boot)
        self.assertLess(boot, tests)
        self.assertLess(tests, package)

    def test_release_error_stops_before_simulator_and_preserves_diagnostic(self):
        root, result, events = self.run_ci('release')
        self.assertEqual(result.returncode, 65, result.stdout + result.stderr)
        self.assertFalse(any(e[:3] == ['xcrun', 'simctl', 'boot'] for e in events))
        self.assertFalse(any('test-without-building' in e or 'scripts/package_ipa.py' in e for e in events))
        for name in ['build.log', 'release-build.log']:
            self.assertIn('Injected Release compiler failure', (root / 'build' / name).read_text())

    def test_debug_error_stops_before_release_and_tests(self):
        _, result, events = self.run_ci('debug')
        self.assertEqual(result.returncode, 66, result.stdout + result.stderr)
        self.assertFalse(any(e[0] == 'xcodebuild' and ('Release' in e or 'test-without-building' in e) for e in events))
