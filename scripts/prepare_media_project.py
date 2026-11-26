"""Generate media resources and build spec; image fixtures belong only to the test bundle."""
from pathlib import Path
import os,shutil
from build_media_pack import build,ROOT
mode=os.environ.get('MEDIA_MODE','external');policy=os.environ.get('MEDIA_SEED_POLICY','preserve')
if mode not in ['external','bundled'] or policy not in ['preserve','updateOfficial']:raise ValueError('Invalid media configuration')
output=ROOT/'build/GymRest-Official.gymrestmedia';build(output)
resources=ROOT/'build/MediaResources';shutil.rmtree(resources,ignore_errors=True);resources.mkdir(parents=True)
if mode=='bundled':shutil.copy2(output,resources/'Official.gymrestmedia')
fixtures=ROOT/'build/TestMediaFrames';shutil.rmtree(fixtures,ignore_errors=True);shutil.copytree(ROOT/'GymRest/Resources/ExerciseFrames',fixtures)
spec=(ROOT/'project.yml').read_text().replace('GymRestMediaMode: external','GymRestMediaMode: '+mode).replace('GymRestMediaSeedPolicy: preserve','GymRestMediaSeedPolicy: '+policy)
(ROOT/'.gymrest-media.yml').write_text(spec)
print('Media mode:',mode,'seed policy:',policy)
