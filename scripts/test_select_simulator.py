import unittest
from select_simulator import select
from provision_simulator import compatible_device

GOOD = '6478AFFB-AE17-412A-A1E5-51BCFFD300B6'
OTHER = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'

class SelectionTests(unittest.TestCase):
    def devices(self):
        return {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [
            {'udid': GOOD, 'name': 'iPhone 17 Pro', 'isAvailable': True, 'state': 'Shutdown'}]}}
    def test_simctl_available_but_xcode_ineligible_is_rejected(self):
        log = 'Ineligible destinations for the "GymRest" scheme:\n{platform:iOS, id:' + GOOD + ', error:iOS 26.0 is not installed}'
        with self.assertRaises(ValueError): select(self.devices(), log)
    def test_only_xcode_accepted_destination_can_be_selected(self):
        devices = self.devices()
        devices['devices']['com.apple.CoreSimulator.SimRuntime.iOS-26-1'] = [
            {'udid': OTHER, 'name': 'iPhone 17', 'isAvailable': True, 'state': 'Booted'}]
        self.assertEqual(select(devices, '{platform:iOS Simulator, id:' + GOOD + ', name:iPhone 17 Pro}'), (GOOD, 'Shutdown'))
    def test_unavailable_device_is_rejected(self):
        devices = self.devices(); devices['devices']['com.apple.CoreSimulator.SimRuntime.iOS-26-0'][0]['isAvailable'] = False
        with self.assertRaises(ValueError): select(devices, '{id:' + GOOD + '}')
    def test_no_destination_does_not_fabricate_a_device(self):
        with self.assertRaises(ValueError): select(self.devices(), '')

class RuntimeTests(unittest.TestCase):
    def test_runtime_must_match_selected_sdk(self):
        data = {'runtimes': [{'isAvailable': True, 'version': '26.1', 'identifier': 'newer', 'supportedDeviceTypes': [{'name': 'iPhone 17', 'identifier': 'iphone'}]}]}
        with self.assertRaises(ValueError): compatible_device(data, '26.0')
        self.assertEqual(compatible_device(data, '26.1'), ('iphone', 'newer'))
    def test_unavailable_runtime_never_used(self):
        with self.assertRaises(ValueError): compatible_device({'runtimes': [{'isAvailable': False, 'version': '26.0'}]}, '26.0')

if __name__ == '__main__': unittest.main()
