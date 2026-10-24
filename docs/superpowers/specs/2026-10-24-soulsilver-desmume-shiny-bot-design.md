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

## State Machine and Data Flow

The controller cycles through:

`MOVING -> WAITING_FOR_BATTLE -> ANALYZING -> RUNNING`

It has terminal `SHINY_FOUND` and `ERROR` states. A movement cycle alternates
left and right for configurable durations. The controller releases the
movement key before every capture and analysis.

Each capture is cropped to profile-relative regions after calibration mapping:

1. Vision classifies battle state using stable battle-UI regions across
   consecutive frames.
2. Once battle is stable, OCR reads the opposing Pokemon name and normalizes it
   against the local reference catalog.
3. Vision waits for a non-transition sprite frame, normalizes the opponent
   sprite crop, compares its color features with the named species/form's
   normal reference, and confirms a likely shiny with a second frame.
4. On a normal encounter, vision locates or validates the Run control and the
   input module presses Down, Right, then the configured A key. The controller
   waits for overworld confirmation before resuming movement.

An unknown name, low OCR confidence, ambiguous color score, missing Run
control, capture failure, lost calibrated viewport, or state timeout enters
`ERROR`. The bot never guesses an action in those cases.

## Shiny Handling and Safety

On a confirmed shiny, the controller atomically changes to `SHINY_FOUND` and
releases every held key. It does not capture the Pokemon, notify external
systems, or send any additional inputs. A global emergency stop, initially
mapped to Esc, is available during every nonterminal state. The UI visibly
reports current state and the last failure reason.

## Reference Data

The SoulSilver profile ships or is calibrated with:

- battle and overworld UI reference regions;
- relative rectangles for opponent name, opponent sprite, and Run control;
- a local catalog of normalized species/form names;
- normal sprite color references and shiny detection thresholds per
  species/form where necessary.

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
