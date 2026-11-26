#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
assets=build/Assets.xcassets
mkdir -p "$assets/AppIcon.appiconset"
sips -z 1024 1024 GymRest/Resources/Artwork/AppIcon-source.png --out "$assets/AppIcon.appiconset/AppIcon.png" >/dev/null
python3 - <<'PY'
import json
from pathlib import Path
root = Path('build/Assets.xcassets')
(root/'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
(root/'AppIcon.appiconset/Contents.json').write_text(json.dumps({'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}], 'info': {'author': 'xcode', 'version': 1}}))
PY
# A complete classic watch icon set also works with the modern single-target app.
python3 - <<'PY'
import json,subprocess
from pathlib import Path
root=Path('build/WatchAssets.xcassets');icons=root/'AppIcon.appiconset';icons.mkdir(parents=True,exist_ok=True)
images=[]
entries=[('24x24','2x','notificationCenter','38mm'),('27.5x27.5','2x','notificationCenter','42mm'),
 ('29x29','2x','companionSettings',None),('29x29','3x','companionSettings',None),
 ('40x40','2x','appLauncher','38mm'),('44x44','2x','appLauncher','40mm'),('46x46','2x','appLauncher','41mm'),
 ('50x50','2x','appLauncher','44mm'),('51x51','2x','appLauncher','45mm'),('54x54','2x','appLauncher','49mm'),
 ('86x86','2x','quickLook','38mm'),('98x98','2x','quickLook','42mm'),('108x108','2x','quickLook','44mm')]
for index,(size,scale,role,subtype) in enumerate(entries):
 pixels=round(float(size.split('x')[0])*int(scale[0]));name=f'WatchIcon-{index}.png'
 subprocess.run(['sips','-z',str(pixels),str(pixels),'GymRest/Resources/Artwork/AppIcon-source.png','--out',str(icons/name)],check=True,stdout=subprocess.DEVNULL)
 item={'filename':name,'idiom':'watch','size':size,'scale':scale,'role':role}
 if subtype:item['subtype']=subtype
 images.append(item)
subprocess.run(['sips','-z','1024','1024','GymRest/Resources/Artwork/AppIcon-source.png','--out',str(icons/'Marketing.png')],check=True,stdout=subprocess.DEVNULL)
images.append({'filename':'Marketing.png','idiom':'watch-marketing','size':'1024x1024','scale':'1x'})
(icons/'Contents.json').write_text(json.dumps({'images':images,'info':{'author':'xcode','version':1}}))
(root/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
PY
