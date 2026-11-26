"""Add a modern single-target watchOS companion to a HealthKit-enabled spec."""
from pathlib import Path
import sys,plistlib

def generate(spec):
    if 'GYMREST_HEALTHKIT' not in spec:raise ValueError('Watch companion requires the HealthKit build')
    spec=spec.replace('    SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) GYMREST_HEALTHKIT"','    SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) GYMREST_HEALTHKIT GYMREST_WATCH"',1)
    spec=spec.replace('        GymRestWatchEnabled: false','        GymRestWatchEnabled: true',1)
    spec=spec.replace('    dependencies:\n      - target: GymRestWidgets','    dependencies:\n      - target: GymRestWatch\n        embed: true\n      - target: GymRestWidgets',1)
    spec=spec.replace('schemes:\n','''  GymRestWatch:
    type: application
    platform: watchOS
    deploymentTarget: "10.0"
    sources:
      - path: GymRestWatch
      - path: CompanionShared
      - path: build/WatchAssets.xcassets
    entitlements:
      path: build/GymRestWatch.entitlements
      properties:
        com.apple.developer.healthkit: true
    info:
      path: build/plists/GymRestWatch-Info.plist
      properties:
        CFBundleDisplayName: GymRest
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        WKApplication: true
        WKWatchOnly: false
        WKRunsIndependentlyOfCompanionApp: false
        WKCompanionAppBundleIdentifier: dev.gymrest.personal
        WKBackgroundModes: [workout-processing]
        NSHealthShareUsageDescription: 在你开启GymRest手表训练后读取心率、能量与本App已保存记录，用于显示训练状态和避免重复保存。
        NSHealthUpdateUsageDescription: 仅在你确认开启GymRest手表记录后保存训练与活动能量；手机不重复写入同一份训练。
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.gymrest.personal.watchkitapp
        TARGETED_DEVICE_FAMILY: "4"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        SKIP_INSTALL: YES
schemes:
  GymRestWatch:
    build:
      targets:
        GymRestWatch: all
''',1)
    return spec

if __name__=='__main__':
    source=Path(sys.argv[1] if len(sys.argv)>1 else '.gymrest-health.yml')
    Path('.gymrest-watch.yml').write_text(generate(source.read_text()))
    Path('build').mkdir(exist_ok=True)
    with Path('build/GymRestWatch.entitlements').open('wb') as f:plistlib.dump({'com.apple.developer.healthkit':True},f)
