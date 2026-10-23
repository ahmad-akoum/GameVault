"""Read-only eligibility experiment. Never invokes Steam or any UI control.

Input is an observation supplied by a separate inspector, not trusted proof.
A positive result means eligible for further controlled testing, NOT initiation.
There is deliberately no execution option or product integration.
"""
import argparse
import json
from pathlib import Path


def assess(app_id, observation):
    reasons = []
    if type(app_id) is not int or app_id <= 0:
        reasons.append('invalid_app_id')
    if observation.get('steam_window_verified') is not True:
        reasons.append('steam_window_unverified')
    selected = observation.get('selected_app_id')
    if type(selected) is not int or selected != app_id:
        reasons.append('selected_app_id_unverified')
    age = observation.get('age_seconds')
    if type(age) not in (int, float) or not 0 <= age <= 2:
        reasons.append('stale_or_invalid_observation')
    if observation.get('manifest_state') != 'available' or observation.get('ui_state') != 'available':
        reasons.append('not_unambiguously_available')
    buttons = observation.get('buttons', [])
    if not isinstance(buttons, list):
        buttons = []
    candidates = [b for b in buttons if isinstance(b, dict)
                  and b.get('label') == 'UPDATE'
                  and all(b.get(k) is True for k in ('visible', 'enabled', 'invokable'))]
    if len(candidates) != 1:
        reasons.append('update_control_not_unique')
    return {'eligible_for_controlled_test': not reasons,
            'request_sent': False, 'download_verified': False,
            'reasons': reasons}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-id', type=int, required=True)
    parser.add_argument('--observation', type=Path, required=True)
    args = parser.parse_args()
    observed = json.loads(args.observation.read_text(encoding='utf-8'))
    if not isinstance(observed, dict):
        parser.error('Observation must be a JSON object')
    print(json.dumps(assess(args.app_id, observed)))


if __name__ == '__main__':
    main()
