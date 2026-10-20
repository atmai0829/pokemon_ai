# FireRed BizHawk Shiny Hunter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a BizHawk Lua shiny hunter for Pokemon FireRed USA v1.0 that automates grass encounters and starter soft resets, freezing immediately and sending one optional phone alert when it detects a shiny.

**Architecture:** Extend the existing `bizhawk/bridge.lua` into a Lua-first state machine with isolated FireRed memory/profile logic, validated input macros, and terminal fail-closed behavior. The Lua bridge remains the sole emulator controller and keeps writing compatible observation JSON; an optional standard-library Python watcher publishes `SHINY_FOUND` once to the configured ntfy phone topic.

**Tech Stack:** BizHawk 2.11.1 GBA Lua APIs, Lua 5.x test harness with mocked emulator APIs, Python 3.11 standard library, ntfy HTTPS API, Pokemon FireRed USA v1.0 RAM, existing Python file bridge.

**Spec:** `docs/superpowers/specs/2026-10-20-firered-shiny-hunter-design.md`

## Global Constraints

- Support only a legally dumped Pokemon FireRed USA v1.0 ROM in BizHawk 2.11.1.
- Use verified RAM state, not screenshots, as the source of truth.
- Run entirely from a BizHawk Lua script; the Python host is optional.
- Do not make controller input unless configuration and memory validation have passed.
- Stop all controller input, pause BizHawk, and render a visible alert before returning from a positive shiny result.
- Treat invalid pointers, unknown game states, unexpected menus, wrong starter species, and timeouts as terminal errors.
- Keep all raw addresses and offsets in the FireRed USA v1.0 profile and require manual verification before enabling a live hunt.
- Restrict configured inputs to allowlisted BizHawk GBA controller names and positive frame counts.
- Make phone notification optional, configured only by `POKEMON_AI_NTFY_TOPIC`; never write its topic to source control, Lua, or bridge observations.
- The notifier may observe observation JSON only; it must never control BizHawk or mutate hunt status.

## Review Focus

- A malformed macro with an unknown button, empty action list, or zero frames must be rejected before any controller call; cover in Task 1.
- A valid-looking enemy record outside a confirmed wild battle must yield `unknown`, not `not_shiny`; cover in Task 2.
- A shiny result on the final inspected frame must clear input and pause before any recovery action can be queued; cover in Task 3.
- A non-shiny grass encounter must use only the configured flee macro and must not resume walking until overworld state returns; cover in Task 4.
- A reset sequence which produces a party member other than `starter_species` must stop with an error rather than reset again; cover in Task 5.
- A notifier restart or retry must not duplicate a delivered `run_id`, while a new Lua run must be eligible to notify; cover in Task 6.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `bizhawk/bridge.lua` | BizHawk entry point, FireRed profile, memory readers, validated inputs, hunt state machine, overlay, and compatible observations. |
| `bizhawk/test_bridge.lua` | Existing bridge test; update mocks and assertions only where the public bridge interface changes. |
| `bizhawk/test_hunt.lua` | Isolated Lua unit tests with mocked memory, controller, emulator, GUI, and sound APIs. |
| `pokemon_ai/notifier.py` | Optional ntfy watcher that validates configuration, deduplicates terminal observations, and publishes phone alerts. |
| `tests/test_notifier.py` | Unit tests for notifier configuration, observation parsing, persistence, HTTP delivery, and bounded retry. |
| `README.md` | Setup, configuration, safety boundaries, and manual validation instructions for the hunter. |

### Task 1: Configuration and bounded input primitives

**Files:**
- Modify: `bizhawk/bridge.lua`
- Create: `bizhawk/test_hunt.lua`

**Interfaces:**
- Produces: `validate_hunt_config(config) -> boolean, string|nil`
- Produces: `submit_input(action) -> nil`, where `action` is `{ buttons: string[], frames: integer }`
- Produces: `clear_input() -> nil`
- Produces: `HUNT_CONFIG` with `mode`, `grass_inputs`, `flee_inputs`, `reset_inputs`, `post_reset_inputs`, `starter_species`, and `timeouts`.

- [ ] **Step 1: Write failing configuration and input tests in `bizhawk/test_hunt.lua`**

```lua
assert_false(validate_hunt_config({ mode = "grass", grass_inputs = {} }))
assert_false(validate_hunt_config(valid_config_with_unknown_button))
assert_false(validate_hunt_config(valid_config_with_zero_frames))
assert_true(validate_hunt_config(valid_grass_config))
```

Also assert that `submit_input` invokes only allowlisted controller keys for the requested positive frame count and that `clear_input` clears every pressed key.

- [ ] **Step 2: Run the Lua test harness to verify the tests fail**

Run: `BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_hunt.lua"`

Expected: FAIL because the validation and input functions do not exist.

- [ ] **Step 3: Add `HUNT_CONFIG`, `validate_hunt_config`, `submit_input`, and `clear_input` to `bizhawk/bridge.lua`**

Keep the button allowlist next to the configuration schema. Reject invalid configuration before the frame loop can issue input. Implement frame-duration input through the hunt state machine rather than a blocking loop so memory is inspected every frame.

- [ ] **Step 4: Run the focused Lua test harness**

Run: `BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_hunt.lua"`

Expected: PASS.

- [ ] **Step 5: Commit the configuration and input foundation**

```bash
git add bizhawk/bridge.lua bizhawk/test_hunt.lua
git commit -m "feat: add validated BizHawk hunt inputs"
```

### Task 2: Verified FireRed Pokemon record and shiny detector

**Files:**
- Modify: `bizhawk/bridge.lua`
- Modify: `bizhawk/test_hunt.lua`

**Interfaces:**
- Consumes: `read_u8(address)`, `read_u16_le(address)`, `read_u32_le(address)`.
- Produces: `read_wild_pokemon() -> PokemonRecord|nil`
- Produces: `read_starter_pokemon(expected_species: integer) -> PokemonRecord|nil`
- Produces: `is_shiny(record: PokemonRecord) -> boolean`
- Produces: `inspect_encounter(kind: "wild"|"starter") -> "shiny"|"not_shiny"|"unknown"`

- [ ] **Step 1: Write failing record/decryption/detector tests in `bizhawk/test_hunt.lua`**

Use mocked encrypted FireRed party bytes for one known shiny and one known non-shiny record. Assert the formula is true precisely when:

```lua
bit.bxor(pid_low, pid_high, ot_id_low, ot_id_high) < 8
```

Also assert `inspect_encounter("wild") == "unknown"` when the wild-battle predicate is false, and assert a player-party record with any species other than the configured starter is rejected.

- [ ] **Step 2: Run the focused tests to verify failure**

Run: `BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_hunt.lua"`

Expected: FAIL because the Pokemon record readers and detector do not exist.

- [ ] **Step 3: Implement the FireRed USA v1.0 profile and detector in `bizhawk/bridge.lua`**

Add named constants for callback/battle predicates, wild and player party bases, party-record layout, and encrypted substructure offsets. Make each reader return `nil` unless pointer ranges, party bounds, expected state, checksum/decryption, and expected species checks pass. Document each constant with the FireRed USA v1.0 verification source and retain no raw magic offsets outside the profile.

- [ ] **Step 4: Run record/detector unit tests**

Run: `BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_hunt.lua"`

Expected: PASS.

- [ ] **Step 5: Commit verified record detection**

```bash
git add bizhawk/bridge.lua bizhawk/test_hunt.lua
git commit -m "feat: detect FireRed shiny Pokemon records"
```

### Task 3: Terminal status, alert, and observation compatibility

**Files:**
- Modify: `bizhawk/bridge.lua`
- Modify: `bizhawk/test_bridge.lua`
- Modify: `bizhawk/test_hunt.lua`

**Interfaces:**
- Consumes: `clear_input()`, `inspect_encounter(kind)`.
- Produces: `set_terminal_status(status: "SHINY_FOUND"|"ERROR", message: string) -> nil`
- Produces: `hunt_status` observation fields: `mode`, `state`, `encounters`, `resets`, `detector_result`, and `message`.

- [ ] **Step 1: Write failing terminal-state tests**

Test that `set_terminal_status("SHINY_FOUND", ...)` clears controller input, pauses the emulator, renders a high-contrast overlay, and prevents every subsequent `submit_input` call. Test that `ERROR` performs the same input clearing and pause. Extend `test_bridge.lua` to prove the existing top-level observation keys remain unchanged when hunt status fields are appended.

- [ ] **Step 2: Run terminal and bridge tests to verify failure**

Run: `BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_hunt.lua"; BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_bridge.lua"`

Expected: FAIL because terminal status and extended observations are absent.

- [ ] **Step 3: Implement terminal status and observation serialization**

Add a terminal guard checked by all input paths. Use BizHawk GUI APIs for the overlay and an available audio API only behind an existence check; the visible paused alert is mandatory even when sound is unavailable. Append a `hunt` object to observations without renaming or changing existing state fields.

- [ ] **Step 4: Run terminal and bridge tests**

Run: `BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_hunt.lua"; BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_bridge.lua"`

Expected: PASS.

- [ ] **Step 5: Commit terminal safety behavior**

```bash
git add bizhawk/bridge.lua bizhawk/test_bridge.lua bizhawk/test_hunt.lua
git commit -m "feat: stop and alert on shiny detection"
```

### Task 4: Grass encounter state machine

**Files:**
- Modify: `bizhawk/bridge.lua`
- Modify: `bizhawk/test_hunt.lua`

**Interfaces:**
- Consumes: `validate_hunt_config`, `submit_input`, `clear_input`, `inspect_encounter`, and `set_terminal_status`.
- Produces: `advance_grass_hunt() -> nil`
- Produces: state transitions `STARTUP -> GRASS_STEP -> INSPECT_WILD_ENCOUNTER -> FLEE -> GRASS_STEP`.

- [ ] **Step 1: Write failing grass workflow tests**

Mock a sequence of stable overworld frames, a confirmed wild battle with a non-shiny record, configured flee inputs, and stable overworld again. Assert encounter count increments once, only configured grass/flee actions occur, and walking resumes only after overworld confirmation. Add a timeout case that enters `ERROR`.

- [ ] **Step 2: Run grass workflow tests to verify failure**

Run: `BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_hunt.lua"`

Expected: FAIL because `advance_grass_hunt` does not exist.

- [ ] **Step 3: Implement `advance_grass_hunt` in `bizhawk/bridge.lua`**

Represent frame waits as explicit state plus deadline counters. Accept only the verified wild battle predicate before inspecting; send the configured flee macro only for `not_shiny`. Route a positive detector result and every unknown/timeout/unexpected state to the corresponding terminal state.

- [ ] **Step 4: Run grass workflow tests**

Run: `BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_hunt.lua"`

Expected: PASS.

- [ ] **Step 5: Commit grass hunting**

```bash
git add bizhawk/bridge.lua bizhawk/test_hunt.lua
git commit -m "feat: automate FireRed grass shiny hunts"
```

### Task 5: FireRed starter soft-reset state machine and operator documentation

**Files:**
- Modify: `bizhawk/bridge.lua`
- Modify: `bizhawk/test_hunt.lua`
- Modify: `README.md`

**Interfaces:**
- Consumes: `HUNT_CONFIG.post_reset_inputs`, `HUNT_CONFIG.starter_species`, `read_starter_pokemon`, `inspect_encounter`, and `set_terminal_status`.
- Produces: `advance_reset_hunt() -> nil`
- Produces: state transitions `STARTUP -> RESET_SEQUENCE -> INSPECT_STARTER -> RESET_SEQUENCE`.

- [ ] **Step 1: Write failing reset workflow tests**

Mock the reset chord, boot completion, configured starter-selection macro, a non-shiny valid starter party record, and then a known-shiny record. Assert reset count increments only after a valid expected starter; assert the non-shiny path restarts; assert the shiny path stops before a second reset; assert a wrong species enters `ERROR`.

- [ ] **Step 2: Run reset workflow tests to verify failure**

Run: `BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_hunt.lua"`

Expected: FAIL because `advance_reset_hunt` does not exist.

- [ ] **Step 3: Implement `advance_reset_hunt` and mode dispatch in `bizhawk/bridge.lua`**

Use the configured reset chord and post-reset actions exactly as supplied, with individual configured state deadlines. Select `advance_grass_hunt` or `advance_reset_hunt` only after startup validation. Do not issue reset input after `SHINY_FOUND`, `ERROR`, or an unknown/wrong starter record.

- [ ] **Step 4: Document setup and manual validation in `README.md`**

Document the FireRed USA v1.0-only requirement; loading the Lua script in BizHawk; every `HUNT_CONFIG` field; how to create grass and starter-selection macros; the mandatory startup self-check; how to load known shiny/non-shiny BizHawk savestates; and the fact that a positive shiny alert freezes without capturing.

- [ ] **Step 5: Run all Lua tests and perform the documented manual savestate checks**

Run: `BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_hunt.lua"; BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_bridge.lua"`

Expected: PASS. In BizHawk, the known-shiny savestate pauses and alerts without recovery input; the known non-shiny savestate follows the configured recovery path.

- [ ] **Step 6: Commit reset hunting and documentation**

```bash
git add bizhawk/bridge.lua bizhawk/test_hunt.lua README.md
git commit -m "feat: automate FireRed starter reset hunts"
```

### Task 6: Optional ntfy phone notifier

**Files:**
- Create: `pokemon_ai/__init__.py`
- Create: `pokemon_ai/notifier.py`
- Create: `tests/test_notifier.py`
- Modify: `bizhawk/bridge.lua`
- Modify: `bizhawk/test_hunt.lua`
- Modify: `README.md`

**Interfaces:**
- Consumes: observation JSON with `hunt.run_id`, `hunt.state`, and optional
  `hunt.message`.
- Produces: `validate_topic(topic: str) -> str`
- Produces: `Notifier.run() -> None`
- Produces: persisted `bridge/notifier-state.json` containing the delivered
  `run_id`.

- [ ] **Step 1: Write failing notifier tests in `tests/test_notifier.py`**

```python
def test_notifies_once_for_a_new_shiny_run(tmp_path, monkeypatch):
    write_observation(tmp_path, run_id="run-42", state="SHINY_FOUND")
    notifier = Notifier(topic="private-topic", bridge_dir=tmp_path)
    notifier.poll_once()
    notifier.poll_once()
    assert posted_messages == [("private-topic", "Shiny found")]
```

Add tests that reject empty, slash-containing, and URL-like topics; ignore
`ERROR` and non-terminal states; preserve a delivered run ID across a new
`Notifier` instance; allow a different run ID; and stop retries after the
configured bounded attempt count.

- [ ] **Step 2: Run the notifier tests to verify failure**

Run: `py -m unittest tests.test_notifier -v`

Expected: FAIL because the `pokemon_ai.notifier` module does not exist.

- [ ] **Step 3: Add hunt run identity to `bizhawk/bridge.lua`**

Generate `hunt.run_id` when Lua starts from the BizHawk session start frame
plus a monotonic local sequence. Include it in every extended hunt observation
without changing existing observation fields. Add mock assertions in
`bizhawk/test_hunt.lua` that a run ID remains stable within one hunt.

- [ ] **Step 4: Implement `pokemon_ai/notifier.py`**

Use only `json`, `os`, `pathlib`, `time`, `urllib`, and related standard-library
modules. Read `POKEMON_AI_NTFY_TOPIC`; validate it as one non-empty URL path
component; atomically persist only the successfully delivered `run_id`; POST
the alert to `https://ntfy.sh/<topic>` with a short timeout; surface malformed
observations and final HTTP errors on stderr. Bound retry attempts and delay;
do not retry malformed configuration or non-shiny states.

- [ ] **Step 5: Run Python and Lua notifier tests**

Run: `py -m unittest tests.test_notifier -v; BizHawk.exe --lua="C:\Users\maibi\GIT\pokemon_ai\bizhawk\test_hunt.lua"`

Expected: PASS.

- [ ] **Step 6: Document phone setup and manual notification validation**

Add to `README.md`: installing the ntfy app, choosing and subscribing to a
private topic, setting `POKEMON_AI_NTFY_TOPIC` only in the shell environment,
launching `py -m pokemon_ai.notifier`, and validating exactly one alert with
a known-shiny BizHawk savestate. State that the Lua freeze works even when the
notifier or network is unavailable.

- [ ] **Step 7: Commit the notifier**

```bash
git add pokemon_ai/notifier.py pokemon_ai/__init__.py tests/test_notifier.py bizhawk/bridge.lua bizhawk/test_hunt.lua README.md
git commit -m "feat: notify phone when a shiny is found"
```

## Self-Review

**Spec coverage:** Tasks 1-6 cover every stated behavior: Lua-only hunt execution, validated configuration, verified RAM reads, grass hunting, starter resets, terminal alerts, observation compatibility, optional phone notification, FireRed-only profile boundaries, and automated/manual validation. Emerald remains intentionally deferred behind a future validated profile.

**Step scan:** Every implementation step names the exact file, public interface, test assertion, and verification command. No task prescribes private algorithm bodies beyond the encrypted-record validation and frame-state requirement that the spec makes essential.

**Type consistency:** `inspect_encounter`, `set_terminal_status`, `submit_input`, and the mode-specific `advance_*_hunt` functions are defined before they are consumed. Both workflows use the same terminal guard and observation status object, whose `run_id` is consumed read-only by `Notifier`.

**Review Focus:** All five listed high-risk inputs have an owning task and an explicit test step.

**Proportion:** The plan adds five independently testable delivery slices without duplicating the full design or implementation.
