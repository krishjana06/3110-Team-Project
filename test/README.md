# Tests

Run `dune runtest` from the repository root for case validation, clue gating,
repeat-question behavior, deduplication, passage unlocking, and accusation rules.

Run `python3 test/playthrough.py` against a freshly started local server for a
complete HTTP playthrough. It checks all 36 evidence entries, all six weapons,
locked and repeated actions, dialogue unlocks, journal entries, and the ending.
The test consumes the running game's state; restart the server before playing.

The HTTP test also verifies the SVG floor plan and PNG portrait routes and checks that cancelling
an image download does not stop the server. To test another port, set
`GAME_TEST_URL=http://127.0.0.1:8082` before the Python command.

## Workspace DOM integration checks

These checks exercise the actual browser application against a fresh server:
workspace/inspector tabs, keyboard navigation, suspect badges, clue-gated
questions, evidence and journal retention, filters, and accusation inputs.
They use jsdom only for development verification; the game needs no npm packages.
Install it outside the repository and run:

```sh
npm install --prefix /tmp/haunted-murder-ui-check --no-audit --no-fund --ignore-scripts --package-lock=false jsdom
NODE_PATH=/tmp/haunted-murder-ui-check/node_modules GAME_TEST_URL=http://127.0.0.1:8082 node test/workspace_test.cjs
```

Start a fresh server with `PORT=8082 NO_BROWSER=1 dune exec bin/main.exe` before
this test. Restart it between the DOM test and the HTTP playthrough, since each
test discovers evidence. DOM checks do not verify visual layout or native dialog
focus trapping; those require a real browser.
