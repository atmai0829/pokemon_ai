# SoulSilver DeSmuME Shiny Bot Design

## Scope

The first release is a Windows desktop Python application that automates wild
encounters in Pokemon SoulSilver running in DeSmuME. It sends keyboard inputs
mapped in the emulator, walks back and forth in tall grass, identifies normal
encounters, runs from them, and stops all input when it detects a likely shiny.

The application is intentionally profile-driven. This release provides one
`SoulSilverDeSmuMEProfile`; later games require their own profile and reference
assets rather than changes to the automation engine.

## Architecture

The bot is divided into focused modules:

- **Calibration:** Lets the user draw the game viewport with the mouse and
  persists its screen rectangle. Profile regions are stored relative to that
  rectangle, accommodating window movement and viewport scaling.
- **Capture:** Captures only the calibrated viewport and reports capture
  failures explicitly.
- **Profile:** Defines SoulSilver/DeSmuME-relative regions, configured
  keyboard bindings, navigation sequence, thresholds, and reference assets.
- **Vision:** Classifies overworld versus battle UI, reads and normalizes the
  opponent name, selects stable sprite frames, and scores the sprite against
  normal and shiny references.
- **Input:** Sends short, reversible keyboard actions and always releases held
  keys when stopped or when an error occurs.
- **Controller:** Owns the finite state machine, timeouts, cancellation, and
  visible status.

The profile is a versioned JSON document containing viewport-relative
rectangles, default input bindings, timing values, confidence thresholds, and
paths to reference assets. Local user configuration may override only the
profile's default keyboard bindings and viewport rectangle. On startup, every
configured key is validated as a supported keyboard key and the saved profile
version must match the active profile.

Capture returns `CaptureResult { status: "ok", image, viewport }` or
`CaptureResult { status: "error", reason }`, where `viewport` is the
screen-coordinate rectangle used for the capture. Vision consumes that result
and returns `VisionResult { status: "match" | "unknown" | "error", confidence,
speciesForm?, reason? }`; confidence is a number from 0.0 through 1.0.
All profile and vision rectangles are integer pixel coordinates relative to
the captured viewport's top-left corner. Input exposes
`tap(key, duration)`, `hold(key)`, and `release_all()`; it never decides which
game action to take. Before every input, it verifies DeSmuME is the foreground
window. Focus loss releases every key and enters `ERROR`. The controller is
the only module permitted to select actions or move between states.

## State Machine and Data Flow

The controller cycles through:

`MOVING -> WAITING_FOR_BATTLE -> ANALYZING -> RUNNING -> MOVING`

It has terminal `SHINY_FOUND` and `ERROR` states. `MOVING` alternates left and
right for configurable durations, initially 750 milliseconds each, and enters
`WAITING_FOR_BATTLE` after one battle-UI classification. It releases the
movement key immediately on that transition. `WAITING_FOR_BATTLE` samples
every 100 milliseconds and requires three consecutive battle classifications
to enter `ANALYZING`; an overworld classification returns it to `MOVING`.
`WAITING_FOR_BATTLE`, `ANALYZING`, and `RUNNING` each time out after 10
seconds. These defaults are profile fields and can be calibrated without code
changes.

Each capture is cropped to profile-relative regions after calibration mapping:

1. Vision classifies battle state using stable battle-UI regions across
   consecutive frames.
2. Once battle is stable, OCR reads the opposing Pokemon name and normalizes it
   against the local reference catalog.
3. Vision waits for a non-transition sprite frame, normalizes the opponent
   sprite crop, compares its color features with the named species/form's
   normal reference, and confirms a likely shiny with a second frame.
4. On a normal encounter, vision validates that the Run label is present in
   the profile-defined Run region; it does not dynamically choose a menu item.
   The input module then presses Down, Right, then the configured A key. The
   controller waits for three consecutive overworld classifications before
   returning to `MOVING`; otherwise the `RUNNING` timeout enters `ERROR`. Each
   Run key is tapped for 75 milliseconds with a 100-millisecond delay before
   the next key.

An unknown name, low OCR confidence, ambiguous color score, missing Run
control, capture failure, lost calibrated viewport, or state timeout enters
`ERROR`. The bot never guesses an action in those cases.

## Shiny Handling and Safety

On a confirmed shiny, the controller atomically changes to `SHINY_FOUND` and
releases every held key. It does not capture the Pokemon, notify external
systems, or send any additional inputs. A global emergency stop, initially
mapped to Esc, is registered while the application is running and is not sent
to DeSmuME. If global registration is unavailable, startup fails with an
explicit error rather than presenting a working bot without an emergency stop.
The stop callback serializes with state transitions: it first prevents new
input, then releases all keys, then sets the terminal state. The UI visibly
reports current state and the last failure reason.

## Reference Data

The SoulSilver profile ships or is calibrated with:

- battle and overworld UI reference regions;
- relative rectangles for opponent name, opponent sprite, and Run control;
- a local catalog of normalized species/form names;
- normal sprite color references and shiny detection thresholds per
  species/form where necessary.

Assets are local PNG images and JSON metadata stored beneath the profile's
asset directory. Each metadata record has a stable asset ID, PNG filename,
species/form, source screenshot SHA-256 hash, viewport dimensions, profile
version, and capture timestamp. Initial assets are created from user-provided
screenshots of the unfiltered DeSmuME viewport during calibration. The
calibration UI presents each asset's crop and metadata for explicit approval,
then writes an enabled record; unapproved assets cannot be used. Calibration
persists the selected viewport, keyboard overrides, and active profile version
in a local user configuration file, separate from the versioned profile.

The bot does not infer shininess from a generic color database alone; reference
data is tied to the game rendering, profile, and the identified species/form.

## Validation

Automated tests use recorded SoulSilver/DeSmuME screenshots to cover:

- overworld and battle classification;
- opponent-name OCR and catalog normalization;
- normal and shiny color decisions, including low-confidence cases;
- scaling and viewport-relative coordinate mapping;
- Run navigation sequencing;
- controller transitions, timeouts, errors, emergency stop, and the guarantee
  that no keyboard input occurs after `SHINY_FOUND` or `ERROR`.

Manual validation verifies mouse viewport selection, keyboard mapping, safe
walking, normal-battle escape, and the hard stop behavior using known
screenshots or controlled encounters.
