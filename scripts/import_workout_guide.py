"""Import unchanged PNG frames and catalog metadata from a pinned Workout Guide checkout.
Usage: python3 scripts/import_workout_guide.py /path/to/workout-guide
No source scripts or npm packages are executed. Existing exercise IDs/configuration stay intact.
"""
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = 'aac599224bb9780305239607ef98540b7e0ce389'
REPO = 'https://github.com/bryllim/workout-guide'
LICENSE = 'https://creativecommons.org/licenses/by-sa/4.0/'
# Explicit equivalents reviewed by name and equipment, not fuzzy substring matches.
MATCHES = dict(pair.split('=') for pair in '''barbell-bench=bench-press
dumbbell-bench=dumbbell-bench-press
incline-barbell=incline-bench-press
incline-dumbbell=incline-dumbbell-press
machine-chest=machine-chest-press
push-up=push-up
cable-fly=cable-fly
dumbbell-fly=dumbbell-fly
pec-deck=pec-deck
barbell-press=overhead-press
dumbbell-press=seated-dumbbell-press
machine-press=machine-shoulder-press
pike-push-up=pike-push-up
dumbbell-lateral=lateral-raise
cable-lateral=cable-lateral-raise
machine-lateral=machine-lateral-raise
dumbbell-rear=bent-over-rear-delt-raise
cable-rear=cable-rear-delt-fly
machine-rear=reverse-pec-deck
barbell-row=barbell-row
dumbbell-row=one-arm-dumbbell-row
cable-row=seated-row
machine-row=machine-row
lat-pulldown=wide-grip-lat-pulldown
neutral-pulldown=close-grip-lat-pulldown
pull-up=pull-up
assisted-pull-up=assisted-pull-up
dumbbell-curl=bicep-curl
cable-curl=cable-curl
hammer-curl=hammer-curl
triceps-pushdown=tricep-pushdown
dumbbell-triceps=dumbbell-overhead-tricep-extension
barbell-triceps=skull-crusher
back-squat=squat
goblet-squat=goblet-squat
leg-press=leg-press
bodyweight-squat=bodyweight-squat
barbell-rdl=romanian-deadlift
dumbbell-rdl=dumbbell-romanian-deadlift
barbell-hip-thrust=hip-thrust
dumbbell-hip-thrust=dumbbell-hip-thrust
seated-leg-curl=seated-leg-curl
lying-leg-curl=lying-leg-curl
leg-extension=leg-extension
bodyweight-lunge=forward-lunge
standing-calf=calf-raise
crunch=crunch
cable-crunch=cable-crunch'''.splitlines())
# Names checked against all three source frames; keep English names for lookup.
DISPLAY_NAMES = {'neutral-pulldown': '窄距对握高位下拉'}
LOCALIZED_NAMES = {'ez-bar-curl': '站姿 EZ 曲杆弯举', 'walking-lunge': '哑铃行进箭步蹲', 'seated-calf-raise': '坐姿器械提踵'}
MUSCLES = {'Chest':'chest','Core':'core','Glutes':'glutes','Quads':'quads','Shoulders':'shoulders','Back':'back',
 'Triceps':'triceps','Hamstrings':'hamstrings','Lats':'lats','Legs':'legs','Biceps':'biceps','Upper Back':'upperBack',
 'Calves':'calves','Forearms':'forearms','Rear Delts':'rearDelts','Posterior Chain':'posteriorChain','Mobility':'mobility',
 'Lower Back':'lowerBack','Adductors':'adductors','Hips':'hips','Cardio':'cardio','Grip':'grip','Groin':'adductors'}
EQUIPMENT = {'Barbell':'barbell','Bench':'bench','Bodyweight':'bodyweight','Box':'box','Cable':'cable','Cardio':'cardio',
 'Chair':'chair','Doorway':'doorway','Dumbbell':'dumbbell','Kettlebell':'kettlebell','Machine':'genericMachine','Plate':'plate',
 'Pull-up Bar':'pullupBar','Resistance Band':'band','Stability Ball':'stabilityBall','Towel':'towel','Wall':'wall'}


def main(source):
    source = Path(source)
    actual = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != REVISION:
        raise ValueError('Source revision differs from reviewed revision: ' + actual)
    manifest = json.loads((source / 'packages/workout-guide/manifest.json').read_text())
    by_slug = {x['slug']: x for x in manifest}
    assert len(by_slug) == 302
    path = ROOT / 'GymRest/Resources/ExerciseCatalog.json'
    catalog = json.loads(path.read_text())
    existing = [x for x in catalog['exercises'] if not x['id'].startswith('guide-')]
    assert set(MATCHES).issubset({x['id'] for x in existing})
    assets = ROOT / 'GymRest/Resources/ExerciseFrames'
    assets.mkdir(exist_ok=True)
    provenance = {'repository': REPO, 'revision': REVISION, 'licenseURL': LICENSE,
                  'changes': 'PNG artwork unchanged; filenames prefixed for bundling. App optionally sequences frames.', 'exercises': []}
    media = {}
    for item in manifest:
        slug = item['slug']; files = []
        for frame in item['frames']:
            original = source / 'packages/workout-guide' / Path(frame['path']).with_suffix('.png')
            filename = f'wg-{slug}-{frame["index"]}.png'
            data = original.read_bytes()
            assert data.startswith(b'\x89PNG\r\n\x1a\n')
            shutil.copyfile(original, assets / filename)
            files.append(filename)
        assert len(files) == 3
        media[slug] = {'status':'approved', 'animationAsset':None, 'equipmentAsset':None, 'frameAssets': files,
                       'author':'Bryl Lim；Everkinetic（部分原始姿势）', 'licenseURL':LICENSE,
                       'sourceURL': f'{REPO}/tree/{REVISION}/packages/workout-guide/assets/{slug}'}
        provenance['exercises'].append({'slug':slug,'name':item['name'],'attribution':item['attribution'],
            'frames':[{'file':filename,'sha256':hashlib.sha256((assets / filename).read_bytes()).hexdigest(),
                       'attribution':frame['attribution']} for filename, frame in zip(files, item['frames'])]})
    for item in existing:
        if slug := MATCHES.get(item['id']):
            item['media'] = media[slug]
            item['aliases'] = sorted(set(item.get('aliases', []) + [item['name'], by_slug[slug]['name'], slug] + {'barbell-bench':['卧推'], 'dumbbell-bench':['哑铃推胸'], 'cable-row':['坐姿划船'], 'barbell-row':['杠铃俯身划船'], 'back-squat':['杠铃蹲'], 'barbell-rdl':['杠铃罗马尼亚硬举'], 'neutral-pulldown':['窄握高位下拉']}.get(item['id'], [])))
        if item['id'] in DISPLAY_NAMES:
            item['name'] = DISPLAY_NAMES[item['id']]
    matched = set(MATCHES.values())
    additions = []
    for item in manifest:
        slug = item['slug']
        if slug in matched:
            continue
        timed = item['exerciseType'] in ['duration', 'distance_duration'] or item['isStretch']
        bodyweight = item['equipment'] in ['Bodyweight','Wall','Chair','Doorway','Pull-up Bar','Towel','Box','Stability Ball']
        kind = 'added' if slug.startswith('weighted-') else 'assistance' if item['exerciseType'] == 'assisted_bodyweight' else 'bodyweight' if bodyweight else 'perHand' if item['equipment']=='Dumbbell' else 'machine' if item['equipment'] in ['Machine','Cable','Cardio','Resistance Band'] else 'total'
        additions.append({'id':'guide-'+slug, 'name':LOCALIZED_NAMES.get(slug, item['name']), 'englishName':item['name'], 'aliases':[slug] + {'ez-bar-curl':['站姿EZ曲杆弯举','EZ杆弯举','EZ曲杆弯举','曲杆弯举'], 'walking-lunge':['哑铃行走箭步蹲'], 'seated-calf-raise':['器械坐姿提踵']}.get(slug, []),
          'primary':[MUSCLES[item['primaryMuscle']]], 'secondary':list(dict.fromkeys(MUSCLES[m] for m in item['secondaryMuscles'] if m != item['primaryMuscle'])),
          # No invented precise movement classification or ordering advice for new source-only entries.
          'pattern':'guide:'+slug, 'supportsOrderAdvice':False,
          'equipment':[EQUIPMENT[item['equipment']]], 'loadKind':kind, 'compound':False,
          'sets':1 if timed else 3, 'repetitions':None if timed else 10,
          'restSeconds':60, 'transitionRestSeconds':90,
          'cues':['查看三帧姿势示意，按自身能力控制动作范围与负荷。',
                  '此动作按时长或距离练习；当前App仅支持手动完成组数，不记录动作持续时间或距离。' if timed else '组数与次数为App起始设置，可自行调整；分帧图片不代替完整动作指导。'],
          'sourceURL':f'{REPO}/blob/{REVISION}/packages/workout-guide/manifest.json',
          'sourceAuthor':'Bryl Lim', 'licenseURL':LICENSE, 'media':media[slug]})
    catalog['exercises'] = existing + additions
    catalog['attribution'] = '原动作数据来源wger（各条目保留作者及许可）；新增动作元数据与分帧素材来自Workout Guide / Bryl Lim，部分姿势源自Everkinetic。素材CC BY-SA 4.0；完整来源见App内素材许可。新增动作保留源英文名称与粗粒度肌群，不推测肩束分类。'
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n')
    credits = ROOT / 'GymRest/Resources/WorkoutGuide'
    credits.mkdir(exist_ok=True)
    (credits / 'WorkoutGuideSources.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2)+'\n')
    for name in ['LICENSE','LICENSE-ASSETS','LICENSES.md','ATTRIBUTION.md']:
        shutil.copyfile(source / name, credits / ('WorkoutGuide-'+name.replace('.md','.txt')+'.txt' if not name.endswith('.md') else 'WorkoutGuide-'+name.replace('.md','.txt')))
    print(f'Matched {len(MATCHES)} existing; added {len(additions)}; catalog {len(catalog["exercises"])}; copied {len(manifest)*3} PNGs')

if __name__ == '__main__':
    main(sys.argv[1])
