# FireRed BizHawk Shiny Hunter Design

## Intent

Turn the existing FireRed BizHawk bridge into a narrowly scoped, reliable
shiny-hunting tool. The tool automates two repetitive hunt styles:

- walking in grass until a wild encounter occurs; and
- soft-resetting until a configured FireRed starter is selected.

The hunt stops immediately and visibly when it detects a shiny. It must never
submit an input after a positive shiny detection. The first supported target is
a legally dumped Pokemon FireRed USA v1.0 ROM in BizHawk 2.11.1. The design should
leave game-specific knowledge isolated so that Pokemon Emerald can be added
later without duplicating hunt control.

## Goals

- Run entirely from a BizHawk Lua script; no Python host process is required to
  start or sustain a hunt.
- Use verified RAM state, not screenshots, to recognize battle state and a
  shiny wild Pokemon.
- Support `grass` and `soft_reset` hunt modes selected in a Lua configuration
  table.
- Use a configurable, bounded input script for overworld walking and for the
  post-reset sequence.
- Automatically flee non-shiny grass encounters only after the wild battle is
  positively recognized.
- Automatically reset non-shiny soft-reset starter selections only after the
  configured starter's party record is positively recognized.
- Freeze emulation and provide an unmistakable visual and audible alert when a
  shiny is detected.
- Send one best-effort phone notification when a shiny is found, without
  delaying or weakening the local freeze-and-alert safety behavior.
- Present an on-screen status panel with hunt mode, state, encounter count,
  reset count, and the latest detector result.
- Fail closed: unknown ROM state, invalid pointers, unverified addresses, and
  input timeouts halt the hunt with an error instead of making further inputs.

## Non-goals

- Catching or battling a shiny.
- Full navigation, route selection, map parsing, or automatic travel to a
  hunting location.
- Supporting physical hardware, ROMs other than FireRed USA v1.0, a different
  emulator, or a different BizHawk version in the first release.
- Guaranteeing that the game save or chosen encounter can produce a shiny.
- Implementing a Python control loop, LLM behavior, or a general gameplay AI.
- Requiring a notification account, credentials, or any network access for a
  hunt to run safely.

## User workflow

1. The user opens their legally dumped FireRed USA v1.0 ROM in BizHawk,
   positions the player at a safe hunting location, and saves if appropriate.
2. The user edits the configuration table at the top of the Lua script:
   - selects `grass` or `soft_reset`;
   - sets the per-step overworld input sequence for grass mode; or
   - sets the reset-button chord and frame-accurate post-reset input sequence
     that reaches and selects the target starter;
   - sets conservative frame timeouts for expected game states.
3. The user opens the script in BizHawk's Lua Console and starts it.
4. For grass hunts, the script waits for a verified wild-battle state and
   reads the enemy Pokemon's encrypted party data. For reset hunts, it waits
   until the configured starter appears in the player's party, then reads that
   party record. It determines shininess from the record's personality value
   and original trainer ID values.
5. For a non-shiny, the script follows the configured mode's recovery action.
   For a shiny, it clears controller input, pauses the emulator, renders a
   high-contrast alert overlay, plays a sound if BizHawk exposes an audio alert
   API, and stops its loop.
6. If configured, a separate local Python watcher sees `SHINY_FOUND` in the
   bridge observation and posts one notification to an ntfy topic. The user
   subscribes to that topic in the ntfy phone app.

The user resumes manually after a shiny alert. No capture, flee, reset, or
other game input is generated after that point.

## Architecture

### Lua script layout

Replace the current thin `bizhawk/bridge.lua` frame loop with a modular,
single-file Lua implementation suitable for BizHawk's Lua Console. It keeps
the current low-level address readers and adds:

- `config`: mode, input macros, delays, and timeouts;
- `rom`: FireRed USA v1.0 constants, encrypted Pokemon field offsets, and
  verification helpers;
- `state`: safe readers for game callback state, battle flags, enemy party
  data, and player party data;
- `shiny`: personality/OT-ID check after decrypting only the fields required
  for the check;
- `input`: applies one controller action for an exact frame count and always
  clears it before state waits;
- `hunt`: a finite-state machine implementing grass and reset workflows;
- `ui`: status overlay and terminal error/shiny alerts;
- `bridge`: preserves the existing optional observation writer for compatible
  Python status consumers, extended only with safe hunt status fields.
- `notifier`: an optional Python process that observes terminal hunt status and
  submits a single HTTPS request to the configured ntfy topic.

The initial implementation may split these components into Lua files only if
BizHawk can load them using paths relative to `bridge.lua`. Otherwise it stays
in `bridge.lua` with clearly delimited local modules to preserve the existing
single-file launch workflow.

### Phone notification

The Python notifier is an optional `python -m pokemon_ai.notifier` command
using only the standard library. It polls the existing atomic
`bridge/observation.json` file, records the last notified hunt terminal event,
and POSTs a text alert to `https://ntfy.sh/<topic>` when it first observes
`hunt.state == "SHINY_FOUND"`. The topic is supplied through the
`POKEMON_AI_NTFY_TOPIC` environment variable and is never stored in Lua,
source code, observation files, or Git.

The Lua hunt creates a `run_id` at startup from its session start frame and
monotonically increasing local sequence, and includes it in every hunt status
observation. The notifier persists the last delivered `run_id` in
`bridge/notifier-state.json`; it does not deliver the same `run_id` twice,
including after a notifier restart. A new Lua run has a new `run_id` and can
therefore notify even if an older observation file remains.

The notifier is best effort. It starts only after validating the topic as a
single URL path component, uses a short HTTP timeout, reports malformed
observations and HTTP failures visibly, and may retry a failed notification
with bounded backoff. It must never control BizHawk or mutate the hunt status.
Local freezing and the on-screen alert happen before the notifier observes
status and remain complete if the notifier is not started, ntfy is unavailable,
or the phone has no network.

### Verified memory model

All raw addresses and offsets are scoped to FireRed USA v1.0 and named in one
constants section. Before enabling a hunt, startup self-checks must validate:

- the SaveBlock pointers and current player state using the existing checks;
- the main callback or battle flags against a manually observed overworld and
  wild-battle transition;
- the enemy-party base pointer and slot structure against a manually observed
  wild encounter;
- the player-party base pointer and slot structure after a manually observed
  starter selection;
- the party record decryption and shiny calculation using at least one known
  shiny and one known non-shiny test state.

The shiny test is:

`(personality_low16 XOR personality_high16 XOR original_trainer_id_low16 XOR original_trainer_id_high16) < 8`

For grass mode, the detector reads the wild opponent's original trainer IDs.
For reset mode, it reads the selected starter's original trainer IDs in the
player party record. It may only return `shiny` or `not_shiny` after the
expected record is verified; otherwise it returns `unknown` and the hunt
halts.

### Hunt state machine

`STARTUP` validates configuration and memory, then waits for a stable
overworld. `GRASS_STEP` submits exactly one configured direction/action and
waits for either a stable overworld or a battle transition. `RESET_SEQUENCE`
submits the configured soft-reset chord, waits for the configured boot state,
then replays each configured post-reset action through starter selection.
`INSPECT_WILD_ENCOUNTER` accepts only a verified wild battle;
`INSPECT_STARTER` accepts only the configured starter species in the player
party. Each invokes the detector with its validated record.

On `not_shiny`, grass mode enters `FLEE`, which submits the configured menu
action sequence and waits for overworld confirmation before the next step.
Reset mode enters `RESET_SEQUENCE` directly. On `shiny`, both modes enter
terminal `SHINY_FOUND`. Any unexpected menu, wrong starter species, trainer
battle, timeout, invalid pointer, or detector `unknown` enters terminal
`ERROR`.

The reset count increments only after `INSPECT_STARTER` validates the expected
starter and determines it is not shiny. Failed startup, reset, and selection
sequences do not contribute to the count.

The first implementation supplies no assumptions about the move that runs from
battle. Grass configuration contains the menu action sequence used for the
user's save and language state. This avoids accidentally selecting a move or
item in an unexpected menu.

## Configuration contract

The script exposes one Lua table, `HUNT_CONFIG`, with:

- `mode`: `"grass"` or `"soft_reset"`;
- `grass_inputs`: a non-empty repeating list of `{ buttons, frames }` values;
- `flee_inputs`: an explicit sequence of `{ buttons, frames }` values;
- `reset_inputs`: a reset chord and its duration;
- `post_reset_inputs`: an explicit ordered list of `{ buttons, frames }`
  values that reaches and selects the starter;
- `starter_species`: the expected FireRed starter species identifier;
- `timeouts`: frame budgets for overworld, battle start, flee completion, ROM
  reset, and target encounter;
- `pause_on_startup_error`: always `true` in the first release.

All lists and timeouts are validated before controller input is enabled.
Directions and buttons are restricted to BizHawk GBA controller names in an
allowlist. A script cannot run with an empty macro, a non-positive frame
duration, an unknown button, or missing timeout.

## Emerald extension boundary

Game-specific values are represented as a `GAME_PROFILE`. The first profile is
`firered_usa_v1_0`; a later `emerald_usa_v1_0` profile supplies its own memory
addresses, callback/battle-state predicates, encrypted-party layout
validation, and reset timing defaults. Hunt state-machine, configuration
validation, input handling, terminal safeguards, overlay, and shiny formula
remain shared.

Emerald is not enabled merely by adding its profile constants: it requires the
same manual validation suite against Emerald before its profile is selectable.

## Validation

Automated Lua tests will run outside BizHawk with mocked memory, input,
emulator, GUI, and sound APIs. They will cover configuration validation,
encrypted-record decryption helpers, the shiny threshold for known values,
state-machine transitions, terminal input clearing, and timeout errors.

Automated Python tests will mock the observation reader and HTTPS client to
verify notification topic validation, exactly-once `SHINY_FOUND` delivery,
bounded retry behavior, and no request for non-terminal or error states.

Manual BizHawk checks on the target ROM are required before live hunting:

1. Confirm the startup self-check passes in overworld and refuses a wrong ROM
   revision.
2. Confirm grass input repeats without opening unintended menus at the chosen
   location.
3. Confirm a normal wild encounter increments the count and uses only the
   configured flee sequence.
4. Confirm a normal starter selection increments the reset count, validates the
   configured starter species, and replays the configured post-reset sequence.
5. Load user-supplied BizHawk savestates with one known-shiny and one known
   non-shiny wild encounter, and equivalent starter-selection savestates if
   available. Verify the emulator pauses with the alert before any flee/reset
   input for a shiny; repeat with a controlled non-shiny state and verify
   normal recovery.
6. With a temporary ntfy topic subscribed in the phone app, load the known
   shiny savestate and verify exactly one phone alert arrives after the local
   freeze. Disconnect the notifier or network and repeat to verify the local
   alert remains immediate and complete.

## Implementation calls

- Retain RAM as the source of truth, following the existing roadmap, rather
  than adding screenshot recognition.
- Keep the hunter Lua-first because the user selected BizHawk Lua scripting;
  Python observation compatibility and the optional phone notifier remain
  secondary.
- Use the ntfy phone app and its HTTPS publish endpoint, configured by
  `POKEMON_AI_NTFY_TOPIC`, as the default notification service. This is an
  implementation call because the user delegated service selection.
- Require explicit input macros instead of attempting generic navigation or
  button-menu inference in the first release.
- Freeze and alert only after a shiny, as requested; automatic capture is
  deliberately excluded.
