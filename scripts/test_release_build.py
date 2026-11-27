"""Exercise the real Release shell entrypoint with a recording xcodebuild stub.
These checks verify command/diagnostic plumbing, not Apple SDK compilation.
"""
import json,os,shutil,subprocess,tempfile,unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

class ReleaseBuildTests(unittest.TestCase):
    def run_release(self,exit_code):
        temporary=tempfile.TemporaryDirectory();self.addCleanup(temporary.cleanup)
        root=Path(temporary.name);(root/'scripts').mkdir();(root/'bin').mkdir()
        shutil.copy2(ROOT/'scripts/build_release.sh',root/'scripts/build_release.sh')
        stub=root/'bin/xcodebuild'
        stub.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
Path(os.environ['FAKE_XCODE_ARGS']).write_text(json.dumps(sys.argv[1:]))
print('Release stdout captured',flush=True)
print('Release stderr captured',file=sys.stderr,flush=True)
sys.exit(int(os.environ['FAKE_XCODE_EXIT']))
''');stub.chmod(0o755)
        result=subprocess.run(['bash',str(root/'scripts/build_release.sh')],cwd=root,
            env={**os.environ,'PATH':str(root/'bin')+os.pathsep+os.environ['PATH'],
                'FAKE_XCODE_ARGS':str(root/'arguments.json'),'FAKE_XCODE_EXIT':str(exit_code)},text=True,capture_output=True)
        return root,result,json.loads((root/'arguments.json').read_text())
    def test_destination_selects_each_targets_sdk_without_global_override(self):
        _,result,args=self.run_release(0)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(args[args.index('-configuration')+1],'Release')
        self.assertEqual(args[args.index('-destination')+1],'generic/platform=iOS')
        self.assertNotIn('-sdk',args)
        self.assertFalse(any(x.startswith('SDKROOT=') for x in args))
        self.assertIn('CODE_SIGNING_ALLOWED=NO',args)
        self.assertEqual(args[-1],'build')
    def test_release_keeps_both_output_streams_and_result_bundle_path(self):
        root,result,args=self.run_release(0)
        output=(root/'build/release-build.log').read_text()
        for text in ['Release stdout captured','Release stderr captured']:
            self.assertIn(text,output);self.assertIn(text,result.stdout)
        bundle=Path(args[args.index('-resultBundlePath')+1])
        self.assertEqual(bundle.parent,Path('build'));self.assertEqual(bundle.suffix,'.xcresult')
        ci=(ROOT/'scripts/ci.sh').read_text()
        self.assertIn('bash scripts/build_release.sh',ci)
        workflow=(ROOT/'.github/workflows/ios.yml').read_text()
        self.assertIn('build/release-build.log',workflow);self.assertIn('build/*.xcresult',workflow)
    def test_xcode_failure_survives_tee_and_preserves_diagnostics(self):
        root,result,_=self.run_release(65)
        self.assertEqual(result.returncode,65)
        self.assertIn('Release stderr captured',(root/'build/release-build.log').read_text())
