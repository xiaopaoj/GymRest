"""Choose only a simulator accepted by xcodebuild for this scheme."""
import json
import re
import sys

def select(devices, destinations):
    eligible = destinations.split('Ineligible destinations', 1)[0]
    ids = set(re.findall(r'id:\s*([0-9A-Fa-f-]{36})', eligible))
    for runtime, entries in sorted(devices['devices'].items(), reverse=True):
        if 'iOS-26-' not in runtime:
            continue
        for device in entries:
            if device.get('isAvailable') and device['udid'] in ids and device['name'].startswith('iPhone'):
                return device['udid'], device['state']
    raise ValueError('No iOS 26 iPhone simulator eligible for the selected Xcode and GymRest scheme')

if __name__ == '__main__':
    try:
        print(*select(json.load(open(sys.argv[1])), open(sys.argv[2]).read()))
    except ValueError as error:
        sys.exit(str(error))
