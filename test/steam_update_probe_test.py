import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('probe', Path(__file__).resolve().parents[1] / 'tool/steam_update_probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def fixture():
    return {'steam_window_verified': True, 'selected_app_id': 42,
            'age_seconds': 0.5, 'manifest_state': 'available', 'ui_state': 'available',
            'buttons': [{'label': 'UPDATE', 'visible': True, 'enabled': True, 'invokable': True}]}


class UpdateProbeTests(unittest.TestCase):
    def test_positive_is_only_eligibility_never_execution(self):
        observed = fixture()
        before = copy.deepcopy(observed)
        result = probe.assess(42, observed)
        self.assertTrue(result['eligible_for_controlled_test'])
        self.assertFalse(result['request_sent'])
        self.assertFalse(result['download_verified'])
        self.assertEqual(observed, before)

    def test_every_non_available_state_refuses(self):
        for state in ['queued', 'paused', 'downloading', 'updating', 'unknown', 'complete']:
            for field in ['ui_state', 'manifest_state']:
                with self.subTest(state=state, field=field):
                    o = fixture(); o[field] = state
                    self.assertIn('not_unambiguously_available', probe.assess(42, o)['reasons'])

    def test_wrong_missing_or_fake_identity_and_closed_steam(self):
        for selected in [None, 43, '42', True]:
            o = fixture(); o['selected_app_id'] = selected
            self.assertFalse(probe.assess(42, o)['eligible_for_controlled_test'])
        o = fixture(); o['steam_window_verified'] = False
        self.assertFalse(probe.assess(42, o)['eligible_for_controlled_test'])
        for app in [-1, 0, True, '42']:
            self.assertFalse(probe.assess(app, fixture())['eligible_for_controlled_test'])

    def test_control_ambiguity_and_localization_refuse(self):
        for controls in [[], fixture()['buttons'] * 2, [{'label': 'PLAY'}], [{'label': 'UPDATE'}], None]:
            o = fixture(); o['buttons'] = controls
            self.assertFalse(probe.assess(42, o)['eligible_for_controlled_test'])

    def test_stale_or_nonfinite_observations_refuse(self):
        for age in [-1, 3, float('nan'), float('inf'), None, '0', True]:
            o = fixture(); o['age_seconds'] = age
            self.assertFalse(probe.assess(42, o)['eligible_for_controlled_test'])

    def test_visible_duplicate_can_only_be_filtered_with_explicit_evidence(self):
        o = fixture(); hidden = copy.deepcopy(o['buttons'][0]); hidden['visible'] = False
        o['buttons'].append(hidden)
        self.assertTrue(probe.assess(42, o)['eligible_for_controlled_test'])
        hidden['visible'] = True
        self.assertFalse(probe.assess(42, o)['eligible_for_controlled_test'])


if __name__ == '__main__':
    unittest.main()
