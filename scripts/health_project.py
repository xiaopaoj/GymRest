"""Generate an opt-in HealthKit build spec without changing the default free-signing build."""
from pathlib import Path
import plistlib
import sys
spec = Path(sys.argv[1] if len(sys.argv) > 1 else 'project.yml').read_text()
spec = spec.replace('    SWIFT_VERSION: "6.0"', '    SWIFT_VERSION: "6.0"\n    SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) GYMREST_HEALTHKIT"')
spec = spec.replace('        NSSupportsLiveActivities: true', '        NSHealthShareUsageDescription: 在你允许后读取近期锻炼分钟数辅助判断运动迹象，并按你的选择匹配已保存的运动记录；不会写入健康数据。\n        NSSupportsLiveActivities: true')
spec = spec.replace('        PRODUCT_BUNDLE_IDENTIFIER: dev.gymrest.personal\n', '        PRODUCT_BUNDLE_IDENTIFIER: dev.gymrest.personal\n        CODE_SIGN_ENTITLEMENTS: build/HealthKit.entitlements\n', 1)
Path('.gymrest-health.yml').write_text(spec)
Path('build').mkdir(exist_ok=True)
with Path('build/HealthKit.entitlements').open('wb') as f:
    plistlib.dump({'com.apple.developer.healthkit': True}, f)
