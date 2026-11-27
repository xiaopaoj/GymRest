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
