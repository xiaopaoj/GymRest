"""Generate an opt-in HealthKit build spec without changing the default free-signing build."""
from pathlib import Path
import plistlib
import sys
spec = Path(sys.argv[1] if len(sys.argv) > 1 else 'project.yml').read_text()
spec = spec.replace('    SWIFT_VERSION: "6.0"', '    SWIFT_VERSION: "6.0"\n    SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) GYMREST_HEALTHKIT"')
spec = spec.replace('        NSSupportsLiveActivities: true', '        NSHealthShareUsageDescription: 仅在你请求匹配时读取运动记录，并接收GymRest手表会话；手机不重复写入训练。\n        NSSupportsLiveActivities: true')
spec = spec.replace('        PRODUCT_BUNDLE_IDENTIFIER: dev.gymrest.personal\n', '        PRODUCT_BUNDLE_IDENTIFIER: dev.gymrest.personal\n        CODE_SIGN_ENTITLEMENTS: build/HealthKit.entitlements\n', 1)
Path('.gymrest-health.yml').write_text(spec)
Path('build').mkdir(exist_ok=True)
with Path('build/HealthKit.entitlements').open('wb') as f:
    plistlib.dump({'com.apple.developer.healthkit': True}, f)
