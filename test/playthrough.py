"""HTTP integration checks for a fresh local game server (standard library only)."""
import json
import os
from urllib.parse import urlencode
from urllib.request import urlopen

BASE = os.environ.get('GAME_TEST_URL', 'http://127.0.0.1:8080')

def request(path, **params):
    with urlopen(f'{BASE}{path}?{urlencode(params)}') as response:
        assert response.status == 200
        return json.load(response)

def inspect(room, object_id, **params):
    return request('/api/inspect', room=room, object=object_id, **params)

def ask(suspect, topic):
    return request('/api/ask', suspect=suspect, topic=topic)

state = request('/api/state')
assert not state['evidence'], 'Restart the server before running this playthrough.'
assert len(state['rooms']) == 9 and len(state['characters']) == 6
assert len(state['weapons']) == 6
assert 'solution' not in state
state = inspect('study', 'panel')
assert not state['evidence'] and 'locked' in state['notice']
state = ask('mustard', 'cufflink')
assert not state['evidence'], 'Locked interview should not grant evidence'
state = inspect('study', 'desk', suspect='mustard')
assert state['newEvidence'] == ['cufflink']
assert any(q['id'] == 'cufflink' for q in state['selectedCharacter']['questions'])
assert state['evidence'][0]['title'] == 'Regimental cufflink'
assert state['evidence'][0]['source'] == 'Study · writing desk'
state = inspect('study', 'desk')
assert len(state['evidence']) == 1 and not state['newEvidence']
assert len(state['history']) == 1, 'Repeat inspections should not duplicate journal entries'
state = ask('mustard', 'cufflink')
assert state['newEvidence'] == ['cufflink_response']
state = ask('mustard', 'cufflink')
assert len(state['evidence']) == 2 and 'already' in state['notice']
state = inspect('kitchen', 'desk')
assert len(state['evidence']) == 2, 'An object cannot be inspected from the wrong room'
inspect('hall', 'portrait')
state = inspect('study', 'panel')
assert 'passage_tracks' in state['clues']
inspect('conservatory', 'boots')
ask('mustard', 'whereabouts')
state = ask('mustard', 'passage')
assert 'passage_admission' in state['clues']
assert 'never entered' not in state['notice']
# Every room object is reachable once the portrait latch is found.
for room in request('/api/state')['rooms']:
    for object_ in room['objects']:
        state = inspect(room['id'], object_['id'])
        assert object_['inspected'] or state['notice']
for weapon in ('candlestick', 'dagger', 'lead_pipe', 'revolver', 'rope', 'wrench'):
    assert weapon in state['clues']
assert len([c for c in state['evidence'] if c['kind'] == 'Weapon']) == 6
# Follow the other testimony chains, using manually specified case expectations.
for suspect, topics in {
    'scarlet': ['whereabouts', 'victim', 'movement'],
    'mustard': ['victim', 'fund'],
    'white': ['whereabouts', 'victim', 'candlestick', 'haunting'],
    'green': ['whereabouts', 'debt', 'jacket'],
    'peacock': ['whereabouts', 'victim', 'sound'],
    'plum': ['whereabouts', 'victim', 'injury', 'fiber'],
}.items():
    for topic in topics:
        state = ask(suspect, topic)
        assert not any(word in state['notice'].lower() for word in ('unavailable', 'not have enough', 'placeholder'))
assert 'fiber_comparison' in state['clues'] and 'thud' in state['clues']
assert len(state['clues']) == len(set(state['clues']))
# Nineteen searchable objects and seventeen testimony discoveries.
assert len(state['evidence']) == 36
# Invalid and wrong accusations do not reveal the answer or remove evidence.
count = len(state['evidence'])
state = request('/api/accuse', accused='unknown', weapon='dagger', location='study')
assert state['ending'] is None and len(state['evidence']) == count
state = request('/api/accuse', accused='plum', weapon='dagger', location='kitchen')
assert state['ending'] is None and 'does not fit' in state['notice']
state = request('/api/accuse', accused='mustard', weapon='candlestick', location='study')
assert 'Colonel Mustard killed' in state['ending']
assert len(state['evidence']) == count
# Refreshing the browser preserves discoveries for the running server.
assert len(request('/api/state')['evidence']) == count
print(f'HTTP playthrough passed: {count} unique evidence entries, 6 weapons, all dialogue chains, and the correct ending.')

# The plan and portrait routes must serve their actual file types.
with urlopen(f'{BASE}/assets/estate-plan.svg') as response:
    assert response.headers['Content-Type'].startswith('image/svg+xml')
    assert b'Haunted Murder ground floor' in response.read()
with urlopen(f'{BASE}/assets/suspect-portraits.png') as response:
    assert response.headers['Content-Type'] == 'image/png'
    assert response.read().startswith(b'\x89PNG\r\n\x1a\n')
# Cancelling a portrait download must not terminate the game server.
with urlopen(f'{BASE}/assets/suspect-portraits.png') as response:
    assert response.read(8) == b'\x89PNG\r\n\x1a\n'
assert len(request('/api/state')['evidence']) == count
print('Floor plan, portrait, and interrupted image download checks passed.')
