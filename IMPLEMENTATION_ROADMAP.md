# FireRed Game-State Agent Roadmap

This project should become a deterministic FireRed player before it uses an
LLM for strategy. Build the stages in order. Do not begin a later stage until
the previous stage has a repeatable manual test.

## Target and ground rules

- **Target ROM:** your legally dumped Pokemon FireRed USA v1.0 ROM only.
- **Emulator:** BizHawk with `bizhawk/bridge.lua` loaded in Tools -> Lua
  Console.
- **Language:** Python for the host program and Lua only for BizHawk access.
- **Source of truth:** RAM state, not screenshots.
- **Safety boundary:** Python may write only validated controller inputs through
  `bridge/action.json`.

ROM memory addresses differ between regions and revisions. Do not assume an
address works until you have tested it in your own target ROM.

## Build order

| Order | Component | Goal | Do not start until |
|---|---|---|---|
| 1 | State reader | Read and verify player location from RAM | BizHawk can run the Lua bridge |
| 2 | Input controller | Move exactly one tile or report failure | Position readings are correct |
| 3 | Map model | Represent a small map's walkable tiles and exits | One-tile movement is reliable |
| 4 | Pathfinding | Find a walkable route between coordinates | A map model exists |
| 5 | Navigation | Follow a route and recover from blocks | Pathfinding has tests |
| 6 | Objectives | Choose the next deterministic task | Navigation reaches local targets |
| 7 | Menus and dialogue | Interact using verified UI state | Objective system can reach interactions |
| 8 | Battle reader and rules | Win basic encounters with deterministic logic | Menu state is reliable |
| 9 | Persistence and recovery | Resume safely after restarts and failures | At least one objective completes |
| 10 | Optional LLM planner | Choose high-level objectives only | All low-level systems work without it |

## File creation plan

Create files only when you begin their stage. Do not generate the entire tree
up front: empty modules make it harder to see what is actually implemented.

```text
pokemon_ai/
  pyproject.toml
  README.md
  IMPLEMENTATION_ROADMAP.md
  bizhawk/
    bridge.lua
  pokemon_ai/
    __init__.py
    __main__.py
    state/
      __init__.py
      models.py
      reader.py
      addresses.py
    emulator/
      __init__.py
      file_bridge.py
    control/
      __init__.py
      actions.py
      movement.py
    world/
      __init__.py
      types.py
      maps/
        pallet_town.py
      pathfinding.py
      navigation.py
    objectives/
      __init__.py
      base.py
      starter.py
    ui/
      __init__.py
      menus.py
      dialogue.py
    battle/
      __init__.py
      state.py
      strategy.py
    storage/
      __init__.py
      progress.py
    planner/
      __init__.py
      llm.py
  tests/
    fixtures/
    test_state_models.py
    test_state_reader.py
    test_movement.py
    test_pathfinding.py
    test_navigation.py
    test_objectives.py
    test_menus.py
    test_battle_strategy.py
    test_progress.py
```

The empty `__init__.py` files make Python treat each directory as a package.
Create them when first creating the directory.

### Foundation files: create first

#### `pyproject.toml`

Create this before writing application code. It defines the package metadata,
supported Python version, and test configuration. Begin with no external
dependencies:

```toml
[project]
name = "pokemon-ai"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = []
```

Use the Python standard library and `unittest` at first. Add dependencies only
when a concrete need appears.

#### `pokemon_ai/__main__.py`

Create this after the first state reader works. It is the command-line entry
point for:

```powershell
py -m pokemon_ai
```

At first, it should only:

1. locate the bridge directory;
2. wait for one observation;
3. parse it into `GameState`;
4. print the result;
5. exit.

Do not make it an endless game-playing loop until movement works.

## Files for stage 1: state reader

Create these files first, in this order.

### `bizhawk/bridge.lua`

This is the only file that knows BizHawk Lua APIs and raw emulator memory.
Keep it narrow.

It should contain:

- a `BRIDGE_DIRECTORY` constant;
- constants for the FireRed USA v1.0 SaveBlock pointers and verified offsets;
- a selected memory domain;
- small readers such as `read_u8`, `read_u16_le`, and pointer validation;
- `read_state()` that returns only verified primitive values;
- `write_observation(state)` that atomically writes JSON;
- a frame loop that publishes state.

At this stage, **do not** add party decryption, battle logic, pathfinding, or
objectives to Lua. Lua is just an adapter between the emulator and Python.

The first observation should contain only:

```json
{
  "turn": 1,
  "state": {
    "map": { "group": 3, "number": 0 },
    "player": { "x": 12, "y": 8 },
    "progress": { "badges_bitmask": 0 },
    "party": { "count": 1 }
  }
}
```

### `pokemon_ai/state/addresses.py`

This file documents the address knowledge for exactly one ROM revision. It
contains named constants, not memory reads:

```python
SAVE_BLOCK_1_POINTER = 0x0300500C
SAVE_BLOCK_2_POINTER = 0x03005010
SAVE_BLOCK_1_MAP_GROUP_OFFSET = 0x0004
```

Every constant should have a comment containing:

- the target ROM revision;
- the data type;
- whether it is a direct address, pointer, or offset;
- how you manually verified it.

Do not put unidentified magic numbers anywhere else in the project.

### `pokemon_ai/state/models.py`

This file turns primitive JSON data into meaningful, immutable Python objects.
Start with only these dataclasses:

```python
@dataclass(frozen=True)
class MapId:
    group: int
    number: int

@dataclass(frozen=True)
class Position:
    x: int
    y: int

@dataclass(frozen=True)
class PlayerState:
    position: Position

@dataclass(frozen=True)
class GameState:
    turn: int
    map_id: MapId
    player: PlayerState
    badges_bitmask: int
    party_count: int
```

Include validation in `__post_init__` where a value has clear limits. For
example, coordinates and party count must not be negative.

### `pokemon_ai/state/reader.py`

This file parses one observation JSON object into `GameState`. It should
contain one public function:

```python
def parse_observation(payload: Mapping[str, object]) -> GameState:
    ...
```

It must reject missing keys, wrong JSON types, and invalid values with clear
`ValueError` messages. It does not read files and does not communicate with
BizHawk.

### `pokemon_ai/emulator/file_bridge.py`

This file owns filesystem communication with Lua. Its responsibilities are:

- wait for a newer `observation.json`;
- load the JSON file;
- return the raw dictionary to `state.reader`;
- later, write `action.json` atomically.

Its first public interface can be:

```python
class FileBridge:
    def wait_for_observation(self, after_turn: int, timeout_seconds: float) -> dict:
        ...
```

Do not parse game-specific fields in this file.

### `tests/fixtures/observation_pallet_town.json`

Create a manually checked observation captured from your game. It gives you a
stable input for tests without starting BizHawk.

### `tests/test_state_models.py`

Test that valid state objects can be created and invalid values are rejected.
Keep tests focused on dataclasses rather than files or the emulator.

### `tests/test_state_reader.py`

Load the fixture and test that `parse_observation()` produces the expected
`GameState`. Add separate tests for missing keys, wrong types, and invalid
coordinates.

## Files for stage 2: input and one-tile movement

Create these only after stage 1 works.

### Update `bizhawk/bridge.lua`

Add the controller half of the bridge:

- read `action.json`;
- validate allowed buttons and maximum frame duration;
- remove a consumed action file;
- hold an allowed button for the requested number of frames.

The Lua script must reject malformed actions. It must never execute Lua code
received from Python.

### `pokemon_ai/control/actions.py`

Define controller-specific types:

```python
class Direction(Enum):
    UP = "UP"
    DOWN = "DOWN"
    LEFT = "LEFT"
    RIGHT = "RIGHT"

@dataclass(frozen=True)
class ControllerAction:
    button: str
    frames: int
```

Keep action serialization and validation here. Allowed button names and frame
limits should have one canonical definition.

### Update `pokemon_ai/emulator/file_bridge.py`

Add:

```python
def send_action(self, action: ControllerAction) -> None:
    ...
```

Write a temporary JSON file and rename it to `action.json` so BizHawk never
reads a partially written action.

### `pokemon_ai/control/movement.py`

This file implements movement using state feedback. It should define:

- `MoveResult` enum: `MOVED`, `BLOCKED`, `WARPED`, `TIMEOUT`;
- `move_one_tile(direction: Direction) -> MoveResult`;
- a configurable frame limit and timeout.

It reads state before and after an input. It must not assume that a fixed
number of frames always means one tile.

### `tests/test_movement.py`

Test movement decisions with a fake bridge. The fake bridge should return a
sequence of recorded states. Cover open movement, a wall, a warp, and a
timeout.

## Files for stages 3 and 4: maps and pathfinding

### `pokemon_ai/world/types.py`

Define data-only world types:

```python
@dataclass(frozen=True)
class Tile:
    x: int
    y: int

@dataclass(frozen=True)
class Warp:
    source: Tile
    destination_map: MapId
    destination: Tile

@dataclass
class MapDefinition:
    map_id: MapId
    width: int
    height: int
    walkable_tiles: set[Tile]
    warps: tuple[Warp, ...]
```

### `pokemon_ai/world/maps/pallet_town.py`

Define only the Pallet Town map. Put manually verified dimensions, walkable
tiles, and known exits here. This module should export one
`PALLET_TOWN: MapDefinition` constant.

### `pokemon_ai/world/pathfinding.py`

Implement BFS with one public function:

```python
def find_path(
    map_definition: MapDefinition,
    start: Tile,
    goal: Tile,
) -> list[Direction] | None:
    ...
```

The function knows nothing about BizHawk, actions, objectives, or LLMs.

### `tests/test_pathfinding.py`

Create small in-memory maps directly in the test. Test shortest route, blocked
goal, start equals goal, and unreachable goal. Do not need BizHawk or FireRed
for these tests.

## Files for stage 5: navigation

### `pokemon_ai/world/navigation.py`

Connect the pathfinder and movement controller. This file should:

- request a path;
- execute one direction at a time;
- compare actual and expected state after each move;
- replan after unexpected movement;
- stop with a specific failure after a limited number of replans.

Expose:

```python
def navigate_to(goal: Tile) -> NavigationResult:
    ...
```

### `tests/test_navigation.py`

Use a fake movement controller and a tiny map. Test successful arrival,
replanning after a dynamic obstacle, and failure after the replan limit.

## Files for stage 6: objectives

### `pokemon_ai/objectives/base.py`

Define the objective interface and result types:

```python
class Objective(Protocol):
    name: str

    def is_complete(self, state: GameState) -> bool:
        ...

    def next_step(self, state: GameState) -> Step:
        ...
```

`Step` should describe a desired destination or interaction, not controller
buttons.

### `pokemon_ai/objectives/starter.py`

Implement the first small objective sequence: travel from the player's house
to Professor Oak's laboratory. Keep each substep explicit and derived from
state.

### `tests/test_objectives.py`

Use state fixtures for each point in the sequence. Assert the objective chooses
the next unfinished step and recognizes completion.

## Files for stage 7: UI

### `pokemon_ai/ui/menus.py`

Add menu-state types and deterministic movement from a known selected index to
a requested index. It should not identify menus from screenshots.

### `pokemon_ai/ui/dialogue.py`

Add the smallest possible dialogue handler: it checks verified dialogue state,
waits for input readiness, and advances a known message safely.

Create `tests/test_menus.py` with recorded UI states before automating real
menus.

## Files for stage 8: battles

### `pokemon_ai/battle/state.py`

Define battle-specific dataclasses separately from overworld state:

- `MoveState`
- `CombatantState`
- `BattleState`

Do not add fields until their RAM addresses and data transformations are
verified. Pokemon party data is encrypted in Generation III, so document and
test decryption separately before using it for decisions.

### `pokemon_ai/battle/strategy.py`

Begin with transparent rules:

```python
def choose_battle_action(state: BattleState) -> BattleAction:
    ...
```

It should choose only valid battle-menu actions and return a reason useful for
debugging.

### `tests/test_battle_strategy.py`

Create manually written battle state fixtures. Test low-health behavior,
unavailable moves, no-PP cases, and a normal attacking decision.

## Files for stage 9: persistence

### `pokemon_ai/storage/progress.py`

Define a small serializable `Progress` dataclass containing:

- current objective name;
- current substep;
- last successful map and position;
- retry count;
- timestamp or turn number.

It should atomically save and load a local progress JSON file. Never store API
keys or ROM data in progress files.

### `tests/test_progress.py`

Test save/load round trips, malformed save data, and atomic replacement
behavior.

## Files for stage 10: optional LLM planner

### `pokemon_ai/planner/llm.py`

Create this only after the project can navigate and battle without it. This
file receives a compact `GameState` summary plus a Python-generated list of
valid objective names. It returns one allowed objective name.

It must not:

- receive raw RAM dumps;
- return controller buttons;
- execute tools or code;
- bypass objective, navigation, UI, or battle validation.

Add a test with a fake model response that verifies invalid objectives are
rejected.

## 1. Implement the state reader first

This is the next component to implement.

The current Lua bridge already reads these values for FireRed USA v1.0:

- map group
- map number
- player X coordinate
- player Y coordinate
- badge bitmask
- party count

### Work to do

1. Run the game and load `bizhawk/bridge.lua`.
2. Open `bridge/observation.json` while standing still.
3. Move exactly one tile in each cardinal direction.
4. Record which coordinate changes for each direction.
5. Add a Python `GameState` dataclass in `pokemon_ai/state/models.py`.
6. Parse `observation.json` into that dataclass instead of passing raw
   dictionaries around.
7. Add fixture-based tests using saved observation JSON files.

### Completion check

You can run a Python script that prints:

```text
Map: group 3, number 0
Position: (12, 8)
Badges: 0
Party members: 1
```

and the coordinates change exactly as expected after each in-game movement.

### Concepts to learn

- hexadecimal addresses and pointer dereferencing
- little-endian integers
- Python dataclasses
- JSON serialization
- unit tests with fixtures

## 2. Implement a reliable input controller

Pathfinding cannot work until input is reliable.

Create a module such as `pokemon_ai/control/movement.py` with a function like:

```python
def move_one_tile(direction: Direction) -> MoveResult:
    """Attempt one tile movement and report what happened."""
```

### Required behavior

1. Read the starting coordinates.
2. Send one short directional action.
3. Wait for the game to finish the movement animation.
4. Read the new coordinates.
5. Return one of `MOVED`, `BLOCKED`, or `TIMEOUT`.

Do not rely only on a fixed number of frames. Always inspect the resulting
state. A wall, NPC, ledge, warp, or dialogue box can prevent expected movement.

### Completion check

From a fixed save state, your program can:

- move one tile north, south, east, and west on open ground;
- report `BLOCKED` when facing a wall;
- report a special result when crossing a map warp;
- stop cleanly instead of pressing inputs forever.

### Concepts to learn

- enums and result types
- polling with timeouts
- state transitions
- defensive error handling

## 3. Build one map model

Start with Pallet Town or the first interior map. Do not try to model Kanto at
once.

Represent walkable tiles and map connections:

```python
@dataclass
class Warp:
    source: tuple[int, int]
    destination_map: tuple[int, int]
    destination: tuple[int, int]

@dataclass
class MapDefinition:
    map_id: tuple[int, int]
    width: int
    height: int
    walkable: set[tuple[int, int]]
    warps: list[Warp]
```

Hard-code this first map manually. Later, you can learn to extract collision
data from the ROM, but manual data keeps this stage understandable.

### Completion check

A test can answer whether a coordinate is in bounds, walkable, blocked, or a
warp tile without needing BizHawk.

### Concepts to learn

- coordinate systems
- graphs
- data modeling
- test-driven development

## 4. Implement pathfinding

Implement breadth-first search (BFS) before A*. In the beginning, every
movement tile has the same cost, so BFS is simple and correct.

```python
def find_path(
    map_definition: MapDefinition,
    start: tuple[int, int],
    goal: tuple[int, int],
) -> list[Direction] | None:
    ...
```

### Completion check

Given a hand-written map fixture:

- it returns the shortest valid route;
- it returns an empty route when start equals goal;
- it returns `None` for an unreachable target;
- it never returns a blocked tile.

Implement A* only after BFS works and is tested.

### Concepts to learn

- queues
- visited sets
- predecessor maps
- graph search
- Manhattan-distance heuristics

## 5. Combine paths into navigation

Navigation executes a path one direction at a time. After every move, it reads
the state again.

```python
def navigate_to(target: tuple[int, int]) -> NavigationResult:
    ...
```

When the actual position differs from the expected position, stop, inspect the
reason, and replan. Never blindly continue the old path.

### Completion check

Starting from a fixed save, the program reaches a named target tile in one map
without manual button presses.

## 6. Add objectives

Objectives select destinations or interactions. They should not issue raw
button presses.

```python
class Objective(Protocol):
    def is_complete(self, state: GameState) -> bool: ...
    def next_step(self, state: GameState) -> Step: ...
```

Start with one small objective:

```text
Walk from the player's house to Professor Oak's laboratory.
```

Then add objectives in small, independently testable pieces:

1. Leave the house.
2. Reach the lab entrance.
3. Enter the lab.
4. Advance known dialogue.
5. Obtain the starter.

### Completion check

The program can resume from any point in the objective and selects the next
unfinished step from current game state.

## 7. Read menus and dialogue

Do not automate menus by guessing button presses. First find and verify RAM
state for:

- whether a text box is visible;
- whether a menu is visible;
- the menu type;
- the selected item index;
- whether input is currently accepted.

Build a menu helper that moves from a known selected index to a desired index,
then confirms it. Test each menu type separately.

## 8. Build the battle reader and rule system

This stage is harder because Generation III Pokemon structures are encrypted.
Work incrementally:

1. Detect that a battle is active.
2. Detect whose turn it is.
3. Read active Pokemon HP and maximum HP.
4. Read enemy HP and maximum HP.
5. Read available move slots and PP.
6. Add party decoding only after the earlier fields work.

Start with transparent rules, not an LLM:

```python
if active_hp_percent < 25 and can_heal:
    return UseItem("Potion")
return UseMove(best_available_move)
```

### Completion check

The program can complete a wild battle from a fixed save without invalid menu
actions or endless input loops.

## 9. Add progress storage and recovery

Save non-secret state in an ignored local file:

- current objective;
- last successful map and position;
- retry count;
- known recovery action;
- optional BizHawk save-state reference.

Use explicit recovery behavior for timeouts, unexpected warps, blackouts, and
menus. A failed action must produce a clear error or recovery step, never a
silent fallback.

## 10. Add an LLM only after deterministic play works

An LLM should receive a compact summary and choose between safe high-level
options:

```json
{
  "objective_options": ["heal_at_center", "enter_gym", "buy_potions"],
  "state": {
    "map": "Pewter City",
    "party_hp_percent": [35, 100],
    "badges": 0
  }
}
```

It should return an objective, not controller buttons. Python should validate
that the objective is among the offered options; navigation, menus, and battle
code execute it deterministically.

## Development habit for every stage

1. Write the smallest test or manual verification case first.
2. Implement one behavior.
3. Verify it in BizHawk from a known save state.
4. Record the expected state before and after the behavior.
5. Commit only when that behavior is repeatable.

If a stage becomes unclear, reduce it to a smaller observable behavior. For
example, do not ask “how do I read battles?” Ask “which RAM value changes when
a wild battle begins?” and verify that one value first.
