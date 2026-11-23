# Haunted Murder

A Clue-inspired mystery with an OCaml game server and an interactive browser
interface. A storm traps six guests at Ashcroft's estate after their host is
found dead. Search nine rooms, inspect objects, question suspects, and work out
the suspect, weapon, and room.

## Build and play

From the repository root:

```sh
dune build
dune exec bin/main.exe
```

Open **http://127.0.0.1:8080** if the browser does not launch automatically.
Use `NO_BROWSER=1 dune exec bin/main.exe` to skip automatic browser launch.
If port 8080 is already in use, run `PORT=8081 dune exec bin/main.exe` and open
`http://127.0.0.1:8081`. Restart a running server after backend changes so the
new artwork routes are available.

- Use **The house**, **Your evidence**, and **Make accusation** to switch
  workspace tabs. The suspect strip stays available above every view.
- You start in the study. Select a room on the floor plan, or a button under
  **Ways out**, to walk there. The north corridor joins the top and middle rows
  and the south corridor joins the middle and bottom rows, so reaching the
  bottom row from the top means passing through a middle room. Rooms you
  cannot reach in one move are marked "No direct way", and the game suggests a
  route. You can only search the room you are standing in. The brass
  map-header button opens the accusation form.
- The house is haunted, or seems to be. Some rooms have events that happen once,
  the first time you are there with the right evidence, and some of them leave
  a clue. They are recorded in the journal under "The house".
- Select a suspect to switch that same inspector to an interview. Use the
  inspector tabs to return to the room without losing your selected suspect.
  Portrait badges distinguish the active interview and previously questioned guests.
- Each guest has an original portrait and distinct appearance. Selecting a
  portrait opens their interview; the same portrait appears beside their account.
- Find the candlestick, dagger, lead pipe, revolver, rope, and wrench, along
  with documents, traces, and timeline evidence. Some are red herrings.
- Select any suspect to interview them. Physical evidence and earlier answers
  unlock follow-up questions. Each question can be asked once per suspect.
- Every new discovery and useful witness statement goes straight into the
  evidence collection with a description and source. Filter the collection by
  evidence type, or switch to the investigation journal within **Your evidence**
  to reread full answers.
- Investigate the knocking in the hall to unlock the hidden passage. Once
  open, the ghost walk joins the study and conservatory directly, appears as a
  dashed line on the plan, and can be walked in either direction.
- Submit a suspect, weapon, and room in the accusation form. An incorrect
  accusation allows further investigation; solving the case reveals the explanation.

Progress is shared by browsers connected to this local server and remains in
memory until the server stops. Refreshing preserves it; restarting begins a new
case. Disk saving and separate player sessions are not implemented.

The existing terminal interview interface remains available:

```sh
dune exec bin/dialogue_cli.exe
```

It uses the same dialogue and shared clue IDs, but room searches, the journal,
and accusations are part of the browser game.

## Structure and story editing

- `data/case.json`: storyline, room descriptions, searchable objects, all six
  suspects' dialogue, evidence catalogue, weapons, and fixed solution. The
  `solution` field is a spoiler for maintainers.
- `lib/case.ml`: loads the case and validates duplicate IDs, clue references,
  and solution references. Object `requires` lists gate searches. The optional
  `hallways`, `passages`, and `events` sections describe the house's layout,
  its hidden passage, and its haunted events.
- `lib/house.ml` / `.mli`: immutable exploration state: where the player is,
  which rooms they can reach (hallways, plus passages whose clues they hold),
  rooms visited, passages used, and which haunted events have fired.
- `lib/dialogue.ml` / `.mli`: immutable interview state machine. Topic `requires`
  lists use the same clue IDs as object discoveries; `clue` records a new
  witness statement when the question is answered.
- `bin/main.ml`: local Lwt HTTP server, shared investigation state, searchable
  objects, journal, and accusation handling.
- `web/assets/`: a code-native SVG floor plan and an original generated portrait
  atlas, with the portrait prompt and provenance in `ARTWORK.md`. Room hotspots
  in `web/app.js` align with the SVG plan.
- `web/index.html`, `web/style.css`, `web/app.js`: viewport-sized workspace,
  accessible tabs, contextual search/interview inspector, notebook, and accusations.
- `test/workspace_test.cjs`: browser-DOM integration checks against a fresh
  server (requires a temporary jsdom installation; see `test/README.md`).
- `test/case_test.ml`: case validation and interview progression checks.
- `test/playthrough.py`: complete HTTP playthrough, including repeat discoveries,
  locked searches, cross-suspect evidence, six weapons, and the ending.

Story changes can be made in `data/case.json` without changing OCaml or
JavaScript. Restart the server to load them. Unknown clue IDs fail with a
specific error at startup. Keep object and dialogue IDs stable while editing.

The API serves `/api/state`, `/api/move`, `/api/ask`, `/api/inspect`, and
`/api/accuse`. The player's location is kept by the server; `/api/inspect`
refuses objects in any other room.
Evidence descriptions and interview transcripts are returned in the case state;
the solution is returned only after a correct accusation.

## Validation

```sh
dune build
dune runtest
node --check web/app.js
```

For the HTTP integration test, start a **fresh** server in one terminal, then
run in another:

```sh
python3 test/playthrough.py
```

This plays through the case and changes the running server's progress. Restart
the server afterward to play from the beginning.

Project team: Krish Jana (kj364), Connor Mark (cgm223), Suchit Basineni
(ssb278), Sachin Chhaya (sc3482), and Vikram Davey (vsd24).
