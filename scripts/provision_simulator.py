"""Create a CI device only for the simulator SDK's installed runtime."""
import json
import subprocess
import sys

def compatible_device(runtimes, sdk):
    version = tuple(sdk.split('.')[:2])
    for runtime in runtimes['runtimes']:
        if not runtime.get('isAvailable') or tuple(runtime.get('version', '').split('.')[:2]) != version:
            continue
        for device in runtime.get('supportedDeviceTypes', []):
            if device['name'].startswith('iPhone'):
                return device['identifier'], runtime['identifier']
    raise ValueError('Downloaded runtime does not match the selected simulator SDK or has no supported iPhone type')

if __name__ == '__main__':
    device_type, runtime = compatible_device(json.load(open(sys.argv[1])), sys.argv[2])
    subprocess.run(['xcrun', 'simctl', 'create', 'iPhone GymRest CI', device_type, runtime], check=True)
