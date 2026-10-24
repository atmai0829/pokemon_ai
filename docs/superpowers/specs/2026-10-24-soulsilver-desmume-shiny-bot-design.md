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

The profile is a versioned JSON document containing its viewport-relative
rectangles, fixed input bindings, timing values, confidence thresholds, and
paths to reference assets. Capture returns either an image or a typed capture
error. Vision consumes an image and returns a typed result with a confidence,
recognized species/form when available, and a reason when it cannot decide.
Input exposes `tap(key, duration)`, `hold(key)`, and `release_all()`; it never
decides which game action to take. The controller is the only module permitted
to select actions or move between states.

## State Machine and Data Flow

The controller cycles through:

`MOVING -> WAITING_FOR_BATTLE -> ANALYZING -> RUNNING`

It has terminal `SHINY_FOUND` and `ERROR` states. A movement cycle alternates
left and right for configurable durations, initially 750 milliseconds each.
The controller releases the movement key before every capture and analysis.
It samples the screen every 100 milliseconds and requires three consecutive
battle classifications to enter `ANALYZING`. A state may run for at most 10
seconds, except `MOVING`, which ends upon a confirmed battle. These defaults
are profile fields and can be calibrated without code changes.

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
   controller waits for overworld confirmation before resuming movement.

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
The UI visibly reports current state and the last failure reason.

## Reference Data

The SoulSilver profile ships or is calibrated with:

- battle and overworld UI reference regions;
- relative rectangles for opponent name, opponent sprite, and Run control;
- a local catalog of normalized species/form names;
- normal sprite color references and shiny detection thresholds per
  species/form where necessary.

Assets are local PNG images and JSON metadata stored beneath the profile's
asset directory. Initial assets are created from user-provided screenshots of
the unfiltered DeSmuME viewport during calibration and are reviewed before
being enabled. Calibration persists the selected viewport and keyboard mapping
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
