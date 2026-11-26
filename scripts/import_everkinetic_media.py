"""Copy the six unchanged Everkinetic PNGs for the three remaining movements."""
import hashlib,json,shutil,subprocess,sys
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
REVISION='446bb9a3d0c3beb6b84f7c9d77dfc8af707a2ab6'
source=Path(sys.argv[1])
assert subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()==REVISION
mapping={'barbell-curl':('0211','直杆杠铃弯举两姿势原图；下肢部分裁切，图只用于肘部与杠铃位置。'),
 'dumbbell-lunge':('0115','向前跨步后推回站姿的哑铃箭步蹲；原图腿部裁切，落脚与膝线按步骤核对。'),
 'dumbbell-calf':('0276','图为坐姿单腿哑铃提踵，两侧分别完成；不表示器械或双腿同时版本。')}
data=json.loads((ROOT/'GymRest/Resources/ExerciseCatalog.json').read_text());exercises=json.loads((source/'exercises.json').read_text())
records=[];assets=ROOT/'GymRest/Resources/ExerciseFrames'
for item in data['exercises']:
 if item['id'] not in mapping:continue
 number,note=mapping[item['id']];files=[];frames=[]
 for pose in ['relaxation','tension']:
  original=source/'dist/png'/f'{number}-{pose}.png';filename=f'ek-{number}-{pose}.png'
  shutil.copyfile(original,assets/filename);files.append(filename)
  with Image.open(original) as image:size=list(image.size)
  frames.append({'file':filename,'sourceURL':f'https://github.com/everkinetic/data/blob/{REVISION}/dist/png/{number}-{pose}.png',
   'sha256':hashlib.sha256(original.read_bytes()).hexdigest(),'size':size,'review':'逐张核对器材和动作；原图裁切范围已在UI说明。'})
 entry=next(x for x in exercises if x['id_num']==number)
 records.append({'catalogID':item['id'],'sourceName':entry['title'],'frames':frames,'sourceSteps':entry['steps'],
  'author':'Greg Priday / Everkinetic','licenseURL':'https://creativecommons.org/licenses/by-sa/4.0/'})
 item['media']={'status':'approved','frameAssets':files,'animationAsset':None,'equipmentAsset':None,'author':'Greg Priday / Everkinetic',
  'licenseURL':'https://creativecommons.org/licenses/by-sa/4.0/','sourceURL':f'https://github.com/everkinetic/data/tree/{REVISION}/dist/png',
  'allowsPlayback':False,'lightBackground':True,'reviewNote':note}
 if item['id']=='dumbbell-calf':item['cues']=['坐稳，将一只哑铃放在练习侧大腿靠近膝部，手扶稳负重。','练习侧前脚掌垫稳，缓慢抬起并还原脚跟；两侧分别完成。']
(ROOT/'GymRest/Resources/ExerciseCatalog.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
credits=ROOT/'GymRest/Resources/WorkoutGuide'
(credits/'EverkineticSources.json').write_text(json.dumps({'revision':REVISION,'author':'Greg Priday / Everkinetic','licenseURL':'https://creativecommons.org/licenses/by-sa/4.0/',
 'changes':'PNG original bytes unchanged; only bundling filename prefixed.','exercises':records},ensure_ascii=False,indent=2)+'\n')
shutil.copyfile(source/'LICENSE.md',credits/'Everkinetic-LICENSE.txt')
print('Imported 6 unchanged original PNGs for 3 existing exercise IDs')
