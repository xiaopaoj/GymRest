"""Package only the unsigned iPhoneOS release product, preserving symlinks."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
app = root / "DerivedData/Build/Products/Release-iphoneos/GymRest.app"
extension = app / "PlugIns/GymRestWidgets.appex"
for bundle, expected in [(app, "dev.gymrest.personal"), (extension, "dev.gymrest.personal.widgets")]:
    with (bundle / "Info.plist").open("rb") as f:
        info = plistlib.load(f)
    assert info["CFBundleIdentifier"] == expected
    assert (bundle / info["CFBundleExecutable"]).is_file()
    assert info["MinimumOSVersion"].startswith("26.")
with (app / "Info.plist").open("rb") as f:
    assert plistlib.load(f)["NSAlarmKitUsageDescription"]
with (extension / "Info.plist").open("rb") as f:
    assert plistlib.load(f)["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
staging = root / "build/ipa-staging"
if staging.exists(): shutil.rmtree(staging)
(staging / "Payload").mkdir(parents=True)
shutil.copytree(app, staging / "Payload/GymRest.app", symlinks=True)
out = root / "build/GymRest-unsigned.ipa"
out.unlink(missing_ok=True)
subprocess.run(["zip", "-qry", "-y", str(out), "Payload"], cwd=staging, check=True)
with zipfile.ZipFile(out) as archive:
    assert "Payload/GymRest.app/Info.plist" in archive.namelist()
print(out)
