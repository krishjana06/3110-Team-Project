# Tests

## Automated suite

```sh
dune test
```

This runs everything below. No network, no server, and no packages outside the
OPAM switch are needed.

### `test/case_suite.ml` — OUnit2, 33 checks

The main suite. It covers four areas:

**Loading and validating a case file.** A correct hand-written case loads with
the expected contents and preserves the order of its rooms. Ten further checks
each load a case file carrying exactly one planted fault — a repeated clue id,
an object yielding a clue that does not exist, a solution naming a weapon that
is not in the case, and so on — and assert the full text of the error. Checking
the whole message is what establishes that validation found *that* fault rather
than objecting to something else. A truncated file, a file missing a whole
field, and a file that is not there are each refused as well.

The fixtures are in `test/fixtures/`. `minimal.json` is a correct two-room
case small enough to reason about completely; every other fixture is that same
case with one change.

**Clue gating.** An object that requires nothing is open to a player holding
nothing; an object that requires a clue stays shut until the player holds it;
and the check is insensitive to the order and repetition of the player's
clues. Also pinned: the hidden passage in the study stays shut until the
portrait in the hall has been examined, which is the hinge of the mystery.

**Interviews.** A question opens only when every clue it requires is held; a
locked, repeated, or unknown question leaves the session untouched and grants
nothing; answering records both the question and the clue it yields; and clues
are stored once each in the order they were found. The deepest chain in the
case is traced in full: confronting Mustard about the passage needs the tracks
behind the portrait, the boots from the conservatory, *and* his own earlier
account, so no amount of searching alone will open it.

**Properties of the shipped case.** These hold for any case the game ships, so
they do not break when the story is rewritten. Every catalogued clue is yielded
by some object or question; every clue used as a requirement can actually be
obtained; and — the stronger version — a player starting with an empty notebook
can reach every clue in some order, which rules out a clue reachable only
through itself. Validation checks that referenced clues *exist*; it does not
check that they can be *found*, so these are genuinely separate.

Expected answers were derived from the case file and the rules by hand, not
taken from program output.

### `test/house_suite.ml`: OUnit2, 27 checks

Exploring the house. `fixtures/house.json` is a correct four-room house drawn so
each rule shows up in exactly one place (see the comment at the top of the
suite): two hallways sharing the parlour, an attic reachable only by a
key-locked ladder, a key-locked dumbwaiter, an always-open service door
duplicating a hallway, and four events, one of which needs another's clue.

**Movement.** Hallways join every room on them; passages open only with
their clues and work both ways; a room joined by both a hallway and a passage
is reported as a hallway walk; and every refused move (already here, unknown
room, not connected, passage locked) returns the house unchanged.

**Haunted events.** Events fire on arrival, in file order, and an event's clue
counts immediately, so a chained event fires on the same visit. An event fires
once, waits in its room until its clue is held, and never fires in another
room. A passage is reported as new only the first time through.

**Validation.** Ten fixtures, each `house.json` with one fault: repeated
hallway, passage, or event ids; a hallway, passage, or event naming an absent
room; a passage or event naming an unknown clue; a passage with three ends. As
in the case suite, the full error text is checked.

**The shipped house.** Every room is reachable from the study by hallways
alone (the passage is a shortcut, not the only way to the conservatory), the
ghost walk opens with the portrait latch, and every event is in a reachable
room.

### `test/case_test.ml`

An earlier, narrower set of checks over the written case, kept because it
pins story-specific behavior the property tests deliberately avoid.

## Checking that the tests can fail

A suite that passes against broken code is worth nothing, so both kinds of
check were confirmed against deliberately broken copies of the project:

| Mutation | Result |
| --- | --- |
| Added a clue to `data/case.json` that nothing yields | `every clue in the case can be found` and `the case can be solved starting from nothing` both failed; the other 31 passed |
| `House.haunt` no longer checks whether an event already fired | `an event fires only once`, `an event waits for its clue`, and `starting-room events wait for haunt` failed; the other 24 house checks passed |
| `House.passage_open` returns `true` always | `hallways join their rooms`, `a hallway is preferred to a passage`, `refused moves change nothing`, and `the ghost walk opens with the portrait latch` failed; the other 23 passed |
| Changed `Case.unlocked` to return `true` always | `an object stays locked until every requirement is held` and `the hidden passage stays shut until the portrait is examined` both failed; the other 31 passed |

In every case exactly the tests that should have failed did, and nothing else
did.

## Manual and non-OCaml checks

These are **not** part of `dune test`. They need a running server and, for the
DOM checks, Node and a package installed outside the repository.

Start a server first:

```sh
PORT=8082 NO_BROWSER=1 dune exec bin/main.exe
```

Then, in another shell:

```sh
GAME_TEST_URL=http://127.0.0.1:8082 python3 test/playthrough.py
```

An HTTP playthrough: movement, refused walks and route hints, the ghost walk
opening and being walked both ways, each haunted event firing once, all 38
evidence entries, all six weapons, locked and
repeated actions, dialogue unlocks, journal entries, the ending, and the SVG
and PNG asset routes. It consumes the running game's state, so restart the
server before playing or before running the DOM checks.

```sh
npm install --prefix /tmp/haunted-murder-ui-check --no-audit --no-fund \
  --ignore-scripts --package-lock=false jsdom
NODE_PATH=/tmp/haunted-murder-ui-check/node_modules \
  GAME_TEST_URL=http://127.0.0.1:8082 node test/workspace_test.cjs
```

Browser application checks against a fresh server: workspace and inspector
tabs, keyboard navigation, suspect badges, clue-gated questions, evidence and
journal retention, filters, and accusation inputs. jsdom is a development
convenience only; the game itself needs no npm packages.

Neither of these verifies visual layout or focus behavior in a real browser.
Those still need a person to look.
