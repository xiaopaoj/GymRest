"""Build deterministic ZIP_STORED runtime media and optional unchanged source archive."""
from pathlib import Path
import hashlib,json,zipfile,argparse
ROOT=Path(__file__).resolve().parents[1]
RESOURCE=ROOT/'GymRest/Resources'
PACK_ID='org.gymrest.workout-guide'
REVISION=2026112601

def write_zip(output, files):
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_STORED,allowZip64=False) as archive:
        for path,data in sorted(files.items()):
            item=zipfile.ZipInfo(path,(2026,11,26,0,0,0));item.compress_type=zipfile.ZIP_STORED
            item.external_attr=(0o100644<<16);archive.writestr(item,data)

def build(output):
    catalog=json.loads((RESOURCE/'ExerciseCatalog.json').read_text())
    names={name for item in catalog['exercises'] for name in item['media'].get('frameAssets',[]) or []}
    files={'frames/'+name:(RESOURCE/'ExerciseFrames'/name).read_bytes() for name in names}
    credits=RESOURCE/'WorkoutGuide'
    files['credits/LICENSE.txt']='\n\n'.join(p.read_text() for p in sorted(credits.glob('*.txt'))).encode()
    files['credits/Sources.json']=json.dumps({p.stem:json.loads(p.read_text()) for p in [credits/'WorkoutGuideSources.json',credits/'EverkineticSources.json']},ensure_ascii=False,indent=2).encode()
    files['credits/Review.json']=(credits/'WorkoutGuideMediaReview.json').read_bytes()
    manifest={'format':'GymRestMedia','schemaVersion':1,'packID':PACK_ID,'revision':REVISION,'minimumAppBuild':8,'title':'GymRest 动作分帧素材',
        'files':[{'path':path,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()} for path,data in sorted(files.items())],
        'artwork':[{'catalogID':x['id'],'name':x['name'],'media':x['media']} for x in catalog['exercises']]}
    files['manifest.json']=json.dumps(manifest,ensure_ascii=False,indent=2).encode()
    write_zip(output,files)
    return manifest

def source_archive(output):
    files={'ExerciseFrames/'+p.name:p.read_bytes() for p in sorted((RESOURCE/'ExerciseFrames').glob('*.png'))}
    files.update({'WorkoutGuide/'+p.name:p.read_bytes() for p in sorted((RESOURCE/'WorkoutGuide').iterdir()) if p.is_file()})
    write_zip(output,files)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=ROOT/'build/GymRest-Official.gymrestmedia');parser.add_argument('--source-archive',type=Path)
    args=parser.parse_args();manifest=build(args.output)
    if args.source_archive:source_archive(args.source_archive)
    print(f"Media revision {manifest['revision']}: {len(manifest['artwork'])} mappings, {len(manifest['files'])} resources -> {args.output}")
