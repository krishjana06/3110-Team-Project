# Authors and assistance

Project team: Krish Jana (kj364), Connor Mark (cgm223), Suchit Basineni
(ssb278), Sachin Chhaya (sc3482), Vikram Davey (vsd24).

## AI assistance — November 19, 2026

OpenAI Codex (GPT-6) helped draft the Ashcroft case storyline, suspect dialogue,
room objects, and evidence catalogue; implement the case loader, browser searches,
evidence collection, journal, clue-gated questions, and accusation flow; and
write automated case and HTTP playthrough checks and documentation.

The storyline was based on the team's supplied MS1 proposal and MS2 report.
Team review of these additions remains pending. This acknowledgement does not
claim that a teammate has reviewed or approved AI-assisted changes.

## Visual redesign — November 19, 2026

OpenAI Codex (GPT-6) helped implement a simple architectural floor plan,
suspect portraits, a charcoal UI with one copper accent, responsive layouts,
and a compact evidence notebook. The built-in OpenAI imagegen tool created
`web/assets/suspect-portraits.png`. Its full prompt and atlas mapping are recorded
in `web/assets/ARTWORK.md`. The SVG floor plan is authored as project-native code.

Codex also added an alternate local server port and fixed SIGPIPE handling so
an interrupted artwork download cannot terminate the game server.

## Investigation workspace — November 19, 2026

OpenAI Codex (GPT-6) helped rename the browser game to Haunted Murder and
restructure it around viewport-sized workspace tabs, a persistent suspect shelf,
a contextual room/interview inspector, status badges, and case-note styling.
It also helped write DOM integration checks for navigation, evidence retention,
interview progression, keyboard controls, and accusation inputs.

## Interfaces and automated tests — November 2026

Vikram Davey (vsd24) owns the interface and testing area. Claude (Opus 4.5)
helped draft `lib/case.mli`, the OCamldoc in `lib/dialogue.mli`, the OUnit2
suite in `test/case_suite.ml`, and the fixture cases in `test/fixtures/`.
Expected results were derived from `data/case.json` and the game's rules rather
than from program output, and the suite was confirmed to fail against
deliberately broken copies of the case data and of `Case.unlocked`.
