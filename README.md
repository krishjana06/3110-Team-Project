# 3110-Team-Project

This is an initial murder mystery prototype in OCaml. The browser view has a
Clue-inspired estate map, a six-character roster, and a placeholder dialogue
flow. Room descriptions, character dialogue, and clues are starter content to
replace with the game's final story.

## Structure

- `dialogue.ml` / `dialogue.mli`: six character definitions, dialogue data types,
  and the interview state machine. Asking a topic can add a clue; topics can
  require clues found during earlier conversations (`lib/`).
- `main.ml`: the Lwt server, static asset routes, and JSON endpoints for case
  state and dialogue actions (`bin/`).
- `dialogue_cli.ml`: terminal input/output. It lists suspects, shows available
  questions, prints responses, and returns to the suspect list (`bin/`).
- `web/index.html`, `web/style.css`, and `web/app.js`: page structure, visual
  styling, and browser interactions.
- `test/`: place for future Dune tests.

The dialogue state is immutable: `Dialogue.ask` returns a new session and a
result. This keeps the rules separate from the browser and console interfaces.

To connect the prototype to the game, update `Dialogue.suspects` and use shared
clue IDs in `clue` and `requires`. The sample cross-suspect chain is:
question Miss Scarlet about whereabouts to find `timeline`, then ask Colonel Mustard
about a corroborating timeline. The sample evidence question becomes available
after discovering `motive` from Colonel Mustard.

## Build and run

From the repository root:

```sh
dune build
dune exec bin/main.exe
```

The Lwt HTTP server listens on `http://127.0.0.1:8080` and opens that address in
your default browser automatically. If the browser cannot be launched, open the
address manually. The server serves files from `web/` and provides `/api/state`
and `/api/ask` for the browser client. The original terminal interface remains
available with `dune exec bin/dialogue_cli.exe`.

Run future test targets with `dune runtest`.

Project team: Krish Jana (kj364), Connor Mark (cgm223), Suchit Basineni
(ssb278), Sachin Chhaya (sc3482), and Vikram Davey (vsd24).
