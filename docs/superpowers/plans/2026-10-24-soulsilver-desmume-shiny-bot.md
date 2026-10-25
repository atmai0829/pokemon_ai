# SoulSilver DeSmuME Shiny Bot Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Windows desktop Python bot that walks for wild Pokemon in SoulSilver on DeSmuME, runs from normal encounters, and stops all input on a confirmed shiny.

**Architecture:** A profile-driven engine maps stable, viewport-relative regions into the user-calibrated emulator viewport. A controller owns a safe finite state machine, while capture, vision, keyboard input, configuration, and the calibration UI remain independently testable. The first profile is SoulSilver/DeSmuME; adding games must require only a new profile and reference assets.

**Tech Stack:** Python 3.12, Tkinter, Pillow, OpenCV, NumPy, pytesseract, keyboard, pytest.

---

## File structure

| Path | Responsibility |
|---|---|
| `general_shiny_hunting_bot/pyproject.toml` | Package metadata, runtime dependencies, pytest configuration. |
| `general_shiny_hunting_bot/src/shiny_bot/models.py` | Immutable rectangles, typed result objects, states, and profile/config data models. |
| `general_shiny_hunting_bot/src/shiny_bot/profile.py` | Load and validate the versioned SoulSilver profile and local user configuration. |
| `general_shiny_hunting_bot/src/shiny_bot/capture.py` | Capture the calibrated screen rectangle and return typed results. |
| `general_shiny_hunting_bot/src/shiny_bot/vision.py` | UI classification, name OCR/normalization, Run validation, and two-frame color comparison. |
| `general_shiny_hunting_bot/src/shiny_bot/input.py` | Foreground-safe keyboard actions and emergency-stop registration. |
| `general_shiny_hunting_bot/src/shiny_bot/controller.py` | State transitions, timing, cancellation, and all game-action decisions. |
| `general_shiny_hunting_bot/src/shiny_bot/calibration.py` | Mouse-selected viewport and explicit reference-asset approval workflow. |
| `general_shiny_hunting_bot/src/shiny_bot/app.py` | Tkinter status window and dependency wiring. |
| `general_shiny_hunting_bot/profiles/soulsilver_desmume/profile.json` | First game profile: regions, timing, thresholds, default keys, assets. |
| `general_shiny_hunting_bot/tests/` | Unit tests using fakes and fixture PNGs; no real keyboard events or emulator required. |

## Chunk 1: Foundation and safe input

### Task 1: Create the package and typed models

**Files:**
- Create: `general_shiny_hunting_bot/pyproject.toml`
- Create: `general_shiny_hunting_bot/src/shiny_bot/__init__.py`
- Create: `general_shiny_hunting_bot/src/shiny_bot/models.py`
- Create: `general_shiny_hunting_bot/tests/conftest.py`
- Create: `general_shiny_hunting_bot/tests/test_models.py`

- [ ] **Step 1: Write failing model tests**

```python
import pytest
from shiny_bot.models import CaptureResult, Profile, Rect, StartupError, UserConfig, VisionResult


def test_rect_converts_relative_coordinates_to_screen_coordinates():
    assert Rect(10, 20, 30, 40).translate(Rect(100, 200, 640, 480)) == Rect(110, 220, 30, 40)


def test_capture_and_vision_results_require_explicit_statuses():
    assert CaptureResult.error("capture failed").status == "error"
    assert VisionResult.unknown("unreadable name").confidence == 0.0


def test_models_reject_invalid_invariants():
    with pytest.raises(ValueError):
        Rect(0, 0, 0, 1)
    with pytest.raises(ValueError):
        VisionResult(status="match", confidence=1.1)
    with pytest.raises(ValueError):
        CaptureResult(status="ok", image=None, viewport=None, reason=None)


def test_profile_config_and_startup_error_are_typed():
    assert Profile.__dataclass_fields__
    assert UserConfig.__dataclass_fields__
    assert issubclass(StartupError, RuntimeError)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_models.py -q`  
Expected: FAIL because the package and models do not exist.

- [ ] **Step 3: Add project metadata and minimal typed models**

Create a `src`-layout package targeting Python 3.12. Add runtime dependencies
`Pillow`, `opencv-python`, `numpy`, `pytesseract`, and `keyboard`; add pytest
as a test dependency, and set `tool.pytest.ini_options.pythonpath = ["src"]`
in `pyproject.toml` so every listed test command resolves imports. Implement frozen `Rect`, `CaptureResult`, and
`VisionResult` dataclasses. Enforce valid result statuses, confidence in
`[0.0, 1.0]`, positive rectangle dimensions, and optional species/form only
for a `match`. Also define `State` (`MOVING`, `WAITING_FOR_BATTLE`,
`ANALYZING`, `RUNNING`, `SHINY_FOUND`, `ERROR`), `Profile`, `UserConfig`, and
`StartupError`. `CaptureResult.ok(image, viewport)` and `.error(reason)` have
fields `status`, `image`, `viewport`, and `reason`; `VisionResult.match`,
`.unknown`, and `.error` have `status`, `confidence`, `species_form`, and
`reason`. Enforce that an `ok` capture has an image and viewport but no reason,
while an error has only a reason. Enforce that a vision match has
`species_form` and no reason, while unknown/error have a reason and no species.
These are the only result/status types used by later modules.

- [ ] **Step 4: Run the model tests**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_models.py -q`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add general_shiny_hunting_bot/pyproject.toml general_shiny_hunting_bot/src general_shiny_hunting_bot/tests/conftest.py general_shiny_hunting_bot/tests/test_models.py
git commit -m "feat: add shiny bot domain models"
```

### Task 2: Load a validated SoulSilver profile and local settings

**Files:**
- Create: `general_shiny_hunting_bot/src/shiny_bot/profile.py`
- Create: `general_shiny_hunting_bot/profiles/soulsilver_desmume/profile.json`
- Modify: `general_shiny_hunting_bot/tests/conftest.py`
- Create: `general_shiny_hunting_bot/tests/test_profile.py`

- [ ] **Step 1: Write failing profile tests**

```python
import pytest
from pathlib import Path
from shiny_bot.profile import load_profile

PROFILE_PATH = Path(__file__).parents[1] / "profiles" / "soulsilver_desmume" / "profile.json"


def test_local_keyboard_override_wins_over_profile_default(tmp_path):
    config = tmp_path / "user-config.json"
    config.write_text('{"profile_version": 1, "keys": {"a": "z"}}')
    profile = load_profile(PROFILE_PATH, config)
    assert profile.keys["a"] == "z"


def test_mismatched_config_profile_version_is_rejected(tmp_path):
    config = tmp_path / "user-config.json"
    config.write_text('{"profile_version": 999, "keys": {}}')
    with pytest.raises(ValueError, match="profile version"):
        load_profile(PROFILE_PATH, config)


@pytest.mark.parametrize("mutation", ["zero-width-region", "bad-threshold", "unsupported-key", "missing-asset"])
def test_invalid_profile_is_rejected(profile_copy, mutation):
    mutate_profile(profile_copy, mutation)
    with pytest.raises(ValueError):
        load_profile(profile_copy / "profile.json", None)


@pytest.mark.parametrize("config", [
    '{"profile_version": 1, "keys": {"invalid": "z"}}',
    '{"profile_version": 1, "viewport": {"width": 0}}',
    '{"profile_version": 1, "ui_match_threshold": 0.1}',
])
def test_config_rejects_invalid_or_forbidden_overrides(tmp_path, config):
    path = tmp_path / "user-config.json"
    path.write_text(config)
    with pytest.raises(ValueError):
        load_profile(PROFILE_PATH, path)
```

Define `profile_copy` and `mutate_profile` in `tests/conftest.py`; the former
copies the profile directory and the latter modifies exactly one JSON field for
each named mutation.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_profile.py -q`  
Expected: FAIL because `load_profile` is absent.

- [ ] **Step 3: Implement profile/config parsing**

Define JSON fields for `version`, viewport-relative `battle`, `name`,
`opponent_sprite`, and `run` rectangles; default keyboard bindings; movement
and Run timings; confidence thresholds; and asset paths. Reject unsupported
keys, malformed rectangles, missing assets, and invalid thresholds. Load local
configuration only when its version matches; permit it to override only keys
and viewport, never regions or detection thresholds.

Create only `assets/catalog.json` in the versioned profile; it contains at
least normalized `zubat`. The profile starts with an empty asset manifest:
runtime template and sprite assets are created and explicitly approved through
calibration. `profile_copy` copies this base directory into `tmp_path`, and
`mutate_profile(path, mutation)` edits its JSON to make each named invalid
case reproducible; `missing-asset` adds a manifest item with a nonexistent
filename, rather than mutating the intentionally empty manifest.
Use defaults `ui_match_threshold: 0.90`, `stable_sprite_threshold: 0.85`,
`shiny_distance_threshold: 18.0`, and `frame_agreement_delta: 3.0`.

- [ ] **Step 4: Run the profile tests**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_profile.py -q`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add general_shiny_hunting_bot/src/shiny_bot/profile.py general_shiny_hunting_bot/profiles general_shiny_hunting_bot/tests/conftest.py general_shiny_hunting_bot/tests/test_profile.py
git commit -m "feat: load validated SoulSilver profile"
```

### Task 3: Implement foreground-safe keyboard input

**Files:**
- Create: `general_shiny_hunting_bot/src/shiny_bot/input.py`
- Create: `general_shiny_hunting_bot/tests/test_input.py`

- [ ] **Step 1: Write failing input safety tests**

```python
import pytest
from shiny_bot.input import InputDriver
from conftest import FakeBackend

@pytest.fixture
def fake_backend():
    return FakeBackend(foreground_title="DeSmuME 0.9.13")


def test_tap_refuses_input_and_releases_keys_when_desmume_loses_focus(fake_backend):
    driver = InputDriver(fake_backend, expected_window_title="DeSmuME")
    fake_backend.foreground_title = "Browser"
    assert driver.tap("z", 0.075) is False
    assert fake_backend.released_all is True


def test_emergency_stop_prevents_future_input(fake_backend):
    driver = InputDriver(fake_backend, expected_window_title="DeSmuME")
    driver.stop()
    assert driver.tap("z", 0.075) is False
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_input.py -q`  
Expected: FAIL because the input driver is absent.

- [ ] **Step 3: Implement the input boundary**

Inject a backend wrapper for foreground-window lookup and keyboard events so
tests never emit actual input. `tap` and `hold` must verify the foreground
title before each action. On focus loss or emergency stop, atomically block
new actions and release every held key. Register Esc as a global hotkey during
startup; surface registration failure as `StartupError` and unregister it at
shutdown. Define the fake backend protocol in `tests/conftest.py` with
`foreground_title`, `tap`, `hold`, `release_all`, `register_hotkey`, and
`unregister_hotkey` call recording. Add tests for unsupported keys, hotkey
registration failure, and focus loss while a key is held.

- [ ] **Step 4: Run the input tests**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_input.py -q`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add general_shiny_hunting_bot/src/shiny_bot/input.py general_shiny_hunting_bot/tests/conftest.py general_shiny_hunting_bot/tests/test_input.py
git commit -m "feat: add safe emulator keyboard input"
```

## Chunk 2: Capture, vision, and calibration

### Task 4: Capture the calibrated viewport

**Files:**
- Create: `general_shiny_hunting_bot/src/shiny_bot/capture.py`
- Create: `general_shiny_hunting_bot/tests/test_capture.py`

- [ ] **Step 1: Write failing capture tests**

```python
def test_capture_returns_image_and_screen_viewport(fake_grabber):
    result = ScreenCapture(fake_grabber).capture(Rect(100, 200, 640, 480))
    assert result.status == "ok"
    assert result.viewport == Rect(100, 200, 640, 480)


def test_capture_turns_backend_exception_into_error(fake_grabber):
    fake_grabber.raise_error = OSError("display unavailable")
    result = ScreenCapture(fake_grabber).capture(Rect(100, 200, 640, 480))
    assert result.status == "error"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_capture.py -q`  
Expected: FAIL because `ScreenCapture` is absent.

- [ ] **Step 3: Implement viewport-only capture**

Use an injected image-grabber interface backed by Pillow at runtime. Reject
invalid viewport dimensions before capture. Return `CaptureResult.error` with
the original failure reason; never substitute a stale image.

- [ ] **Step 4: Run the capture tests**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_capture.py -q`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add general_shiny_hunting_bot/src/shiny_bot/capture.py general_shiny_hunting_bot/tests/test_capture.py
git commit -m "feat: capture calibrated game viewport"
```

### Task 5: Implement deterministic vision decisions

**Files:**
- Create: `general_shiny_hunting_bot/src/shiny_bot/vision.py`
- Create: `general_shiny_hunting_bot/tests/test_vision_classification.py`
- Create: `general_shiny_hunting_bot/tests/test_vision_ocr.py`
- Create: `general_shiny_hunting_bot/tests/test_vision_shiny.py`
- Create: `general_shiny_hunting_bot/tests/fixtures/README.md`
- Create: `general_shiny_hunting_bot/tests/fixtures/*.png`

- [ ] **Step 1: Add failing fixture-based vision tests**

```python
def test_classifier_distinguishes_overworld_and_battle(battle_image, overworld_image, profile):
    vision = VisionEngine(profile, fake_ocr)
    assert vision.classify_battle(battle_image).status == "match"
    assert vision.classify_battle(overworld_image).status == "unknown"


def test_shiny_decision_requires_two_matching_frames(shiny_frames, profile):
    vision = VisionEngine(profile, fake_ocr)
    assert vision.detect_shiny(*shiny_frames, "zubat").status == "match"


def test_low_confidence_name_or_color_is_unknown(profile):
    assert VisionEngine(profile, fake_ocr).identify_opponent(AMBIGUOUS).status == "unknown"


def test_run_label_must_match_profile_region(battle_image, profile):
    assert VisionEngine(profile, fake_ocr).validate_run(battle_image).status == "match"


def test_missing_species_asset_returns_unknown(profile):
    assert VisionEngine(profile, fake_ocr).detect_shiny(FRAME, FRAME, "missingno").status == "unknown"


def test_ocr_normalization_and_unlisted_names(profile):
    assert VisionEngine(profile, fake_ocr_returning("ZUBAT?")).identify_opponent(NAME_IMAGE).species_form == "zubat"
    assert VisionEngine(profile, fake_ocr_returning("UNLISTED")).identify_opponent(NAME_IMAGE).status == "unknown"


def test_normal_transition_scaled_and_unapproved_assets_are_unknown(profile):
    engine = VisionEngine(profile, fake_ocr)
    assert engine.detect_shiny(NORMAL, NORMAL, "zubat").status == "unknown"
    assert engine.detect_shiny(TRANSITION, TRANSITION, "zubat").status == "unknown"
    assert engine.detect_shiny(SCALED_SHINY_1, SCALED_SHINY_2, "zubat").status == "match"
    profile.assets["zubat"].enabled = False
    assert engine.detect_shiny(FRAME, FRAME, "zubat").status == "unknown"


def test_tampered_source_or_asset_hash_is_rejected(profile):
    for field in ("source_sha256", "asset_sha256"):
        profile.assets["zubat"].metadata[field] = "0" * 64
        assert VisionEngine(profile, fake_ocr).detect_shiny(FRAME, FRAME, "zubat").status == "unknown"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_vision_classification.py tests/test_vision_ocr.py tests/test_vision_shiny.py -q`  
Expected: FAIL because the vision engine is absent.

- [ ] **Step 3: Implement profile-relative visual analysis**

Crop profile regions from the captured viewport; do not use absolute display
coordinates. Resize each crop to the asset's recorded viewport-relative
dimensions before analysis. Use normalized grayscale template correlation:
`>= profile.ui_match_threshold` is a UI match and lower values are unknown.
Send only the name crop to pytesseract, normalize punctuation and case, and
match only exact normalized catalog entries. Run validation uses the same
threshold against `run_label.png`. For sprite comparison, convert both crops
to CIE Lab, compute the mean absolute distance from the species/form normal
asset, and classify a frame shiny only when its score is
`>= profile.shiny_distance_threshold`; if either frame is below the threshold
or their scores differ by more than `profile.frame_agreement_delta`, return
unknown. A frame with template correlation below
`profile.stable_sprite_threshold` is a transition frame and returns unknown.
Keep OCR and image operations injectable for unit tests. Vision uses only
enabled metadata records whose profile version equals the active profile and
whose referenced PNG SHA-256 matches `asset_sha256`; missing, stale, or
tampered records return unknown without input. `source_sha256` remains the
hash of the full source screenshot used during calibration.

Store full, recorded unfiltered SoulSilver/DeSmuME source screenshots under
`tests/fixtures/sources/`; create `manifest.json` listing each source filename,
SHA-256, viewport dimensions, and crop rectangle. Derive fixture PNGs from
those manifest records: `battle.png`, `overworld.png`, `run.png`, `normal-zubat.png`,
`shiny-zubat-frame-1.png`, `shiny-zubat-frame-2.png`, and `transition.png`.
Record each source screenshot hash, crop coordinates, capture resolution, and
expected outcome in the fixture README; verify those values in tests. The
failing tests cover nonzero viewport translation, 2x scaling, exact OCR
normalization, normal and transition frames, Run mismatch, and tampered
metadata.

- [ ] **Step 4: Run the vision tests**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_vision_classification.py tests/test_vision_ocr.py tests/test_vision_shiny.py -q`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add general_shiny_hunting_bot/src/shiny_bot/vision.py general_shiny_hunting_bot/tests/test_vision_classification.py general_shiny_hunting_bot/tests/test_vision_ocr.py general_shiny_hunting_bot/tests/test_vision_shiny.py general_shiny_hunting_bot/tests/fixtures
git commit -m "feat: detect SoulSilver battle and shiny states"
```

### Task 6: Add calibration and asset approval

**Files:**
- Create: `general_shiny_hunting_bot/src/shiny_bot/calibration.py`
- Create: `general_shiny_hunting_bot/tests/test_calibration.py`

- [ ] **Step 1: Write failing calibration tests**

```python
def test_calibration_persists_viewport_key_overrides_and_profile_version(tmp_path):
    save_calibration(tmp_path / "config.json", Rect(1, 2, 3, 4), {"a": "z"}, 1)
    assert load_config(tmp_path / "config.json").viewport == Rect(1, 2, 3, 4)


def test_asset_cannot_be_used_before_explicit_approval(tmp_path):
    record = create_asset_record(SCREENSHOT, crop, "zubat", 1)
    assert record.enabled is False


def test_approval_writes_enabled_png_and_complete_metadata(tmp_path):
    record = approve_asset(SCREENSHOT, crop, "zubat", profile, tmp_path)
    assert record.enabled is True
    assert (tmp_path / record.filename).is_file()
    assert {"asset_id", "source_sha256", "asset_sha256", "viewport_size", "profile_version", "timestamp"} <= record.metadata.keys()


def test_declined_asset_is_not_enabled(tmp_path):
    assert approve_asset(SCREENSHOT, crop, "zubat", profile, tmp_path, confirm=False) is None
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_calibration.py -q`  
Expected: FAIL because calibration functions are absent.

- [ ] **Step 3: Implement calibration persistence and asset provenance**

Provide a mouse-drag rectangle selector in Tkinter. Persist the viewport,
keyboard overrides, and active profile version to the local config file.
Generate PNG crops plus JSON metadata containing an asset ID, filename,
`kind` (`battle_ui`, `run_label`, or `normal_sprite`), species/form for normal
sprites, source screenshot SHA-256, asset PNG SHA-256, viewport dimensions,
profile version, timestamp, and `enabled: false`. Vision may use a sprite
baseline only from an enabled `normal_sprite` record with the recognized
species/form. Enable assets
only after the UI presents the crop and user confirms it. Write the PNG and
metadata below the active profile's `assets/` directory; use a stable filename
derived from the asset ID. Test both declined confirmation (no enabled record)
and approved confirmation (PNG plus all metadata fields and `enabled: true`).
Assert `source_sha256` against the full source screenshot bytes and
`asset_sha256` against the saved PNG bytes; test that vision rejects a mismatch
of either hash.

- [ ] **Step 4: Run the calibration tests**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_calibration.py -q`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add general_shiny_hunting_bot/src/shiny_bot/calibration.py general_shiny_hunting_bot/tests/test_calibration.py
git commit -m "feat: add viewport and asset calibration"
```

## Chunk 3: Controller and desktop application

### Task 7: Build and test the safe automation controller

**Files:**
- Create: `general_shiny_hunting_bot/src/shiny_bot/controller.py`
- Create: `general_shiny_hunting_bot/tests/test_controller.py`

- [ ] **Step 1: Write failing state-machine tests**

```python
def test_three_battle_frames_enter_analysis(controller, fake_capture, battle_frame):
    fake_capture.queue([battle_frame, battle_frame, battle_frame])
    controller.tick()
    controller.tick()
    controller.tick()
    assert controller.state is State.ANALYZING


def test_confirmed_shiny_releases_keys_and_never_runs(controller, fake_vision, fake_input):
    fake_vision.shiny_result = VisionResult.match("zubat", 0.99)
    controller.tick()
    assert controller.state is State.SHINY_FOUND
    assert fake_input.released_all
    assert fake_input.actions == []


@pytest.mark.parametrize("failure", ["capture", "vision-unknown", "vision-error", "focus", "timeout", "escape"])
def test_failures_release_keys_and_become_terminal(controller, failure, fake_input):
    arrange_failure(controller, failure)
    controller.tick()
    assert controller.state in {State.ERROR, State.SHINY_FOUND}
    assert fake_input.released_all


def test_normal_encounter_runs_and_returns_after_three_overworld_frames(controller, fake_capture, fake_input):
    arrange_normal_battle_then_overworld(controller, fake_capture)
    drive_until_moving(controller)
    assert fake_input.actions == [("tap", "down", 0.075), ("tap", "right", 0.075), ("tap", "a", 0.075)]


def test_terminal_states_never_emit_input(controller, fake_input):
    controller.state = State.SHINY_FOUND
    controller.tick()
    controller.state = State.ERROR
    controller.tick()
    assert fake_input.actions == []
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_controller.py -q`  
Expected: FAIL because `BotController` is absent.

- [ ] **Step 3: Implement the state machine**

Use a monotonic injected clock. Read movement duration, sample interval,
stability count, timeout, tap duration, and inter-key delay from `Profile`;
the initial profile supplies 750 ms, 100 ms, 3, 10 s, 75 ms, and 100 ms.
Trace each transition explicitly: one battle classification moves `MOVING` to
`WAITING_FOR_BATTLE` and releases movement; three battle frames enter
`ANALYZING`; a confirmed shiny enters `SHINY_FOUND`; a normal result with a
valid Run label produces `[Down, Right, A]` and enters `RUNNING`; three
overworld frames return to `MOVING`. An overworld result in `WAITING_FOR_BATTLE`
returns to `MOVING`. In `ANALYZING`, only a confident named normal result with
a valid Run label advances to `RUNNING`; `VisionResult.unknown` and
`VisionResult.error` enter `ERROR` without input. Any capture, vision, focus,
timeout, or stop failure
calls `release_all()` before setting the terminal state.

- [ ] **Step 4: Run the controller tests**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_controller.py -q`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add general_shiny_hunting_bot/src/shiny_bot/controller.py general_shiny_hunting_bot/tests/test_controller.py
git commit -m "feat: automate SoulSilver shiny hunt loop"
```

### Task 8: Wire the Tkinter application and validate the suite

**Files:**
- Create: `general_shiny_hunting_bot/src/shiny_bot/app.py`
- Create: `general_shiny_hunting_bot/src/shiny_bot/__main__.py`
- Create: `general_shiny_hunting_bot/tests/test_app.py`
- Modify: `general_shiny_hunting_bot/README.md`

- [ ] **Step 1: Write failing application wiring tests**

```python
def test_app_displays_controller_state_and_last_reason(fake_controller):
    app = create_app(fake_controller)
    fake_controller.state = State.ERROR
    fake_controller.reason = "DeSmuME focus lost"
    app.refresh()
    assert app.status_text.get() == "ERROR: DeSmuME focus lost"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd general_shiny_hunting_bot; python -m pytest tests/test_app.py -q`  
Expected: FAIL because the application is absent.

- [ ] **Step 3: Implement the minimal desktop shell and usage documentation**

Create a status-only Tkinter window with Calibrate, Start, and Stop controls.
Wire startup validation for the profile, enabled assets, Tesseract availability,
and Esc registration; show actionable errors without starting the controller.
Update the bot README with installation, required DeSmuME key mapping,
calibration, known limitations, emergency-stop behavior, and a statement that
an ambiguous result stops rather than acts.

- [ ] **Step 3a: Perform manual validation with DeSmuME**

With a non-save emulator session, verify that the mouse overlay stores the
selected viewport, the configured emulator receives only mapped keys while it
has focus, a normal battle produces the configured Run sequence, switching
focus stops/release keys, and Esc immediately stops/release keys. Exercise a
recorded or controlled shiny fixture and confirm the app enters
`SHINY_FOUND` with no subsequent keyboard events. Record any environment
limitations in the README.

- [ ] **Step 4: Run targeted and full validation**

Run: `cd general_shiny_hunting_bot; python -m pytest -q`  
Expected: PASS.

Run: `cd general_shiny_hunting_bot; python -m compileall src`  
Expected: all Python modules compile without errors.

- [ ] **Step 5: Commit**

```bash
git add general_shiny_hunting_bot/src/shiny_bot/app.py general_shiny_hunting_bot/src/shiny_bot/__main__.py general_shiny_hunting_bot/tests/test_app.py general_shiny_hunting_bot/README.md
git commit -m "feat: add shiny bot desktop controls"
```
