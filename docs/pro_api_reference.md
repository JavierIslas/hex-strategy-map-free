# API Reference — Hex Strategy Map Pro

Complete reference for all Pro modules. Core classes
(`HexGrid`, `HexCell`, `PathFinder`, `HexRenderer`, `MapCamera`, `FogOfWar`,
`BatchHexLayer`) are documented in `api_reference.md`.

---

## FlowField

```
class_name FlowField
extends RefCounted
```

Flow field pathfinding for group movement. Computes one reverse-Dijkstra from a
goal; the result can be queried by any number of units heading to that goal.
More efficient than N individual A\* calls when many units share the same destination.

### Methods

#### `static build(grid: HexGrid, goal: Vector2i) → Dictionary`
Builds a flow field from `goal` outward across all reachable hexes.
Returns `Dictionary[Vector2i, FlowField.FieldCell]`.
Returns an empty dictionary if `goal` is invalid or impassable.

```gdscript
var field := FlowField.build(grid, Vector2i(10, 8))
```

#### `static trace_path(field: Dictionary, origin: Vector2i) → Array[Vector2i]`
Follows the precomputed field from `origin` to the goal.
Returns the path **excluding** `origin` and **including** the goal.
Returns empty if `origin` is not in the field (i.e. unreachable from goal).

```gdscript
var path_a := FlowField.trace_path(field, Vector2i(1, 1))
var path_b := FlowField.trace_path(field, Vector2i(4, 3))
```

### Inner class — FieldCell

```gdscript
class FieldCell:
    var cost: float       # accumulated cost from this cell to goal
    var next_step: Vector2i  # adjacent hex one step closer to goal
```

---

## GroupMover

```
class_name GroupMover
extends RefCounted
```

Dispatches a group of `MapToken`s to a shared goal using a single `FlowField`.
Each unit receives its own path computed from the shared field — far cheaper
than N independent A\* calls when many units head to the same destination.

`GroupMover` is animation-agnostic: it sets each token's state (via
`MapToken.start_path`) and returns the assigned paths. The consumer decides
how to animate (sequential, e.g. turn-based; or concurrent Tweens, e.g. RTS).

### Methods

#### `static dispatch(units: Array[MapToken], goal: Vector2i, grid: HexGrid) → Dictionary`
Builds a `FlowField` from `goal` and assigns a path to each unit via
`token.start_path()`. Returns `Dictionary[MapToken, Array[Vector2i]]` mapping
each token that received a path to its trace.

Units are silently skipped when:
- `token` is `null` or already moving (`is_currently_moving()` is true)
- `token.hex_coord == goal` (already at destination)
- The goal is unreachable from the token's position
- The goal is invalid or impassable (returns `{}`)

```gdscript
var paths := GroupMover.dispatch(selected_units, target_coord, grid)
# Sequential (turn-based): drive a single Tween across paths.
# Concurrent (RTS): create a Tween per token.
for token in paths:
    var tween := create_tween()
    var marker := unit_markers[token.get_instance_id()]
    for step in paths[token]:
        var pixel := HexGrid.offset_to_pixel(step)
        tween.tween_property(marker, "global_position", pixel, 0.15)
        tween.tween_callback(token.confirm_step.bind(step))
    tween.tween_callback(token.finish_movement)
```

---

## UnitSelector

```
class_name UnitSelector
extends Node2D
```

Rubber-band selection in world-space. Draws a rectangle while the user drags
the left mouse button and emits the set of units inside it on release. The
command/movement step is deliberately left out — combine with `GroupMover` (or
any custom logic) on the `selection_changed` signal.

Add as a child of your scene; the rect is drawn in world coordinates so it
scales with the camera zoom.

### Signals

| Signal | Payload | Emitted when |
|--------|---------|-------------|
| `selection_changed` | `(units: Array[MapToken])` | A drag completes (above `min_drag_distance`) or `select_in_rect()` is called |

### Exported properties

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `min_drag_distance` | `float` | `4.0` | Minimum drag distance in pixels to trigger selection (filters accidental clicks) |
| `rect_color` | `Color` | `Color(0.4, 0.8, 1.0, 0.2)` | Fill color of the selection rectangle |
| `rect_border_color` | `Color` | `Color(0.4, 0.8, 1.0, 0.9)` | Border color of the selection rectangle |

### Methods

#### `setup(hex_grid: HexGrid, tokens_provider: Callable, selectable_fn: Callable = Callable()) → void`
Wires the selector to a grid and a source of selectable units.

`tokens_provider` has signature `() → Array[MapToken]` — called on each drag
release to pull the current candidate set (typically the active player's units).

`selectable_fn` has signature `(token: MapToken) → bool` — optional secondary
filter (e.g. `t.movement_points > 0`). Omit to accept all candidates.

```gdscript
selector.setup(
    grid,
    func(): return registry.get_units(turn_manager.current_player_id),
    func(t): return t.movement_points > 0.0
)
selector.selection_changed.connect(func(units):
    print("%d units selected" % units.size()))
```

#### `select_in_rect(rect_world: Rect2) → void`
Applies the selection to all units whose `hex_coord` (converted via
`HexGrid.offset_to_pixel`) falls inside `rect_world`. Emits `selection_changed`.
Useful when driving selection from a custom input system (e.g. a touch UI).

#### `get_selection() → Array[MapToken]`
Returns the current selection without re-running the AABB test.

#### `clear_selection() → void`
Empties the selection. Does **not** emit `selection_changed`.

---

## SaveManager

```
class_name SaveManager
extends RefCounted
```

JSON-based slot save system. Stores files in `user://saves/save_N.json`.
Does not know about game objects — serialization is the caller's responsibility.

### Methods

#### `save(slot: int, data: Dictionary) → void`
Serializes `data` to JSON and writes it to slot `slot`. Creates the `saves/`
directory if it doesn't exist. Logs an error if the slot is negative or the file
cannot be opened.

#### `load(slot: int) → Dictionary`
Reads and parses the JSON from slot `slot`. Returns an empty dictionary if the
slot does not exist or the file is malformed.

#### `delete_slot(slot: int) → void`
Deletes the file for `slot`. No-op if the slot doesn't exist or is negative.

#### `slot_exists(slot: int) → bool`
Returns `true` if the save file for `slot` exists.

#### `list_slots() → Array[int]`
Returns a sorted array of all existing slot numbers.

### Typical usage

```gdscript
var save_mgr := SaveManager.new()

# Save all game state
save_mgr.save(0, {
    "grid":  grid.serialize(),
    "fog":   fog.serialize(),
    "turns": turns.serialize(),
    "units": registry.serialize(),
})

# Load and restore
var data := save_mgr.load(0)
if data.is_empty():
    return
var grid := HexGrid.deserialize(data["grid"])
```

---

## MapToken

```
class_name MapToken
extends Node
```

A movable unit on the hex grid. Handles movement point tracking, pathfinding, and
path following. Visual animation is left to the caller.

**Important:** `MapToken` is a `Node`, not a `RefCounted`. Add it as a child of
your scene with `add_child(token)`.

### Signals

| Signal | Payload | Emitted when |
|--------|---------|-------------|
| `moved_to` | `(coord: Vector2i)` | `confirm_step()` is called — token logically moved to `coord` |
| `movement_started` | — | `move_to()` or `start_path()` successfully accepts a path |
| `movement_exhausted` | — | `finish_movement()` is called with ≤ 0.01 movement points remaining |

### Constants

| Name | Type | Value |
|------|------|-------|
| `DEFAULT_MOVEMENT_POINTS` | `float` | `6.0` |
| `MOVEMENT_EXHAUSTED_THRESHOLD` | `float` | `0.01` |

### Properties

| Name | Type | Description |
|------|------|-------------|
| `id` | `String` | Unique identifier for this token (game-defined, e.g. `"knight_1"`) |
| `hex_coord` | `Vector2i` | Current logical position on the grid |
| `grid` | `HexGrid` | The grid this token navigates |
| `movement_points` | `float` | Remaining movement points this turn |
| `max_movement_points` | `float` | Full movement allowance (reset by `reset_movement()`) |
| `level` | `int` | Token level; passed to `movement_fn` to compute `max_movement_points` |
| `owner_id` | `int` | Player ID that owns this token |
| `unit_type` | `String` | Free-form type string (e.g. `"knight"`, `"scout"`) |
| `metadata` | `Dictionary` | Arbitrary game data (attack, defense, etc.) |

### Methods

#### `setup(start_coord: Vector2i, hex_grid: HexGrid, movement_fn: Callable = Callable()) → void`
Initializes the token at `start_coord` on `hex_grid`. Must be called before any
movement methods.

`movement_fn` has signature `(level: int) → float`. Omit for the default (6.0).

```gdscript
token.setup(Vector2i(2, 3), grid, func(lvl): return 4.0 + lvl)
```

#### `move_to(target: Vector2i) → Array[Vector2i]`
Computes the shortest path from `hex_coord` to `target` within the token's
remaining `movement_points`.

Returns the path (excluding origin, including destination), or an empty array if:
- The token is already moving (`is_currently_moving()` is true)
- `target` is out of reach
- No valid path exists

Emits `movement_started` on success.

#### `start_path(path: Array[Vector2i]) → bool`
Accepts a pre-computed path (e.g. from `FlowField` or `GroupMover`) without
re-running A\*. Same semantics as `move_to()` but the caller supplies the path.

Returns `true` if the path was accepted. Returns `false` if the token is already
moving, the path is empty, or `setup()` has not been called.

Emits `movement_started` on success.

```gdscript
var path: Array[Vector2i] = FlowField.trace_path(field, token.hex_coord)
token.start_path(path)
```

#### `confirm_step(coord: Vector2i) → void`
Advances the token's logical position to `coord` and deducts the movement cost.
Call this once per step as the visual animation progresses.
Emits `moved_to(coord)`.

#### `finish_movement() → void`
Clears the active path and resets the moving state.
Emits `movement_exhausted` if movement points are ≤ `MOVEMENT_EXHAUSTED_THRESHOLD`.

#### `is_currently_moving() → bool`
Returns `true` while a `move_to` is in progress (between `movement_started` and
`finish_movement`).

#### `get_reachable_coords() → Dictionary`
Returns `Dictionary[Vector2i, float]` of all hexes reachable with the token's
current `movement_points`. Delegates to `PathFinder.find_reachable`.

#### `reset_movement() → void`
Resets `movement_points` to `max_movement_points`. Call at the start of each turn.

### Serialization

#### `serialize() → Dictionary`
Captures: `id`, `coord`, `owner_id`, `unit_type`, `movement_points`,
`max_movement_points`, `level`, `metadata`.

Does not capture the `grid` reference or signal connections — those must be
re-established after deserialization.

#### `static deserialize(data: Dictionary) → MapToken`
Reconstructs a `MapToken` from serialized data. Call `setup()` afterward to
connect it to a grid.

---

## TurnManager

```
class_name TurnManager
extends RefCounted
```

Manages the round/player/phase cycle. Fully decoupled — does not reference
`HexGrid`, `MapToken`, or any other plugin class.

### Signals

| Signal | Payload | Emitted when |
|--------|---------|-------------|
| `player_turn_started` | `(player_id: int)` | A player's turn begins |
| `player_turn_ended` | `(player_id: int)` | A player's turn ends |
| `round_ended` | `(round: int)` | All players have taken a turn |
| `phase_started` | `(player_id: int, phase: String)` | A phase begins within a turn |
| `phase_ended` | `(player_id: int, phase: String)` | A phase ends within a turn |

### Properties

| Name | Type | Description |
|------|------|-------------|
| `current_round` | `int` | Current round number (starts at 1) |
| `turns_played` | `int` | Total number of individual player turns completed |
| `player_ids` | `Array[int]` | Ordered list of player IDs |
| `current_player_index` | `int` | Index into `player_ids` for the active player |
| `phases` | `Array[String]` | Phase names for the current turn structure |
| `current_phase_index` | `int` | Index of the active phase |
| `current_player_id` | `int` | *(computed)* ID of the currently active player; −1 if no players |
| `current_phase` | `String` | *(computed)* Name of the current phase; `""` if no phases configured |

### Methods

#### `setup(ids: Array[int]) → void`
Sets the player list and resets to the first player. Call before the first turn.

```gdscript
turns.setup([0, 1, 2])   # three players; turn order: 0 → 1 → 2 → 0 → …
```

#### `setup_phases(phase_names: Array[String]) → void`
Configures phases that each player completes before passing to the next.
Optional — call `end_player_turn()` directly if you don't need phases.

```gdscript
turns.setup_phases(["movement", "combat", "income"])
```

#### `add_interval_hook(interval: int, callback: Callable) → void`
Registers a callable to fire every `interval` rounds, at the end of the last
player's turn. One hook per interval value — registering a second hook for the
same interval replaces the first.

`callback` has signature `(round_number: int) → void`.

```gdscript
turns.add_interval_hook(5, func(round): _apply_weather(round))
```

#### `end_phase() → void`
Advances to the next phase. If the last phase is completed, calls `end_player_turn()`
automatically. No-op if no phases are configured — call `end_player_turn()` directly.

Emits `phase_ended` for the current phase, then either `phase_started` for the next
phase or `player_turn_ended` if all phases are done.

#### `end_player_turn() → void`
Ends the current player's turn. Advances to the next player; if all players have
gone, increments `current_round`, evaluates interval hooks, and emits `round_ended`.

Emits: `player_turn_ended` → (advance) → `player_turn_started`.

### Serialization

#### `serialize() → Dictionary`
Captures: `current_round`, `turns_played`, `player_ids`, `current_player_index`,
`phases`, `current_phase_index`.

#### `static deserialize(data: Dictionary) → TurnManager`
Reconstructs a `TurnManager`. Interval hooks are not serialized — re-register
them after loading.

---

## MapGenerator

```
class_name MapGenerator
extends RefCounted
```

Static procedural generation methods. All methods are `static` — no instantiation.

### Methods

#### `static generate_noise_terrain(map_width: int, map_height: int, params: Dictionary = {}) → HexGrid`
Generates a `HexGrid` with terrain assigned by `FastNoiseLite` noise.
Returns an empty grid (0×0) if `map_width` or `map_height` ≤ 0.

**`params` keys:**

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `seed` | `int` | `0` | Noise seed |
| `noise_type` | `int` | `TYPE_SIMPLEX_SMOOTH` | `FastNoiseLite.NoiseType` constant |
| `frequency` | `float` | `0.08` | Feature scale; higher = noisier terrain |
| `water_level` | `float` | `−0.2` | Noise threshold below which cells become WATER |
| `mountain_level` | `float` | `0.4` | Noise threshold above which cells become MOUNTAIN |
| `forest_level` | `float` | `0.1` | Threshold between `forest_level` and `mountain_level` → FOREST |
| `cost_table` | `Dictionary` | `HexGrid.TERRAIN_COST` | Terrain cost table for the grid |
| `hex_size` | `float` | `HexGrid.HEX_SIZE` | Hex radius in pixels |
| `edge_cost` | `Dictionary` | `HexGrid.EDGE_COST` | Edge cost table |

Values between `water_level` and `forest_level` become PLAINS or ROAD (split at 0.0).

#### `static generate_rivers(grid: HexGrid, river_count: int = 3) → void`
Adds `RIVER` edges to `grid` by performing random walks across the map.
Rivers avoid already-visited hexes and have 4–10 steps each.
Uses a deterministic seed based on the grid's current edge count.

Modifies `grid` in place. Call after `generate_noise_terrain`.

#### `static scatter_locations(grid: HexGrid, count: int, terrain_filter: Array[int] = [], location_type: int = 1) → void`
Places `count` location markers on random passable cells, optionally restricted to
`terrain_filter` terrains. Sets `cell.location_type` to `location_type`.

To use `tag` instead, set `cell.tag` after calling this, or use this result as a
starting point and modify cells directly.

---

## UnitRegistry

```
class_name UnitRegistry
extends RefCounted
```

Centralized unit store with O(1) coordinate lookups. Automatically syncs the
coordinate index when tokens emit `moved_to`.

**Invariant:** Do not modify `token.hex_coord` directly after registering a token.
Always let the token update its coordinate via `confirm_step()` → `moved_to` signal.
Bypassing this desynchronizes the internal index.

### Constructor

```gdscript
UnitRegistry.new(
    stacking_fn: Callable = Callable()   # (existing: Array[MapToken], incoming: MapToken) → bool
) -> UnitRegistry
```

`stacking_fn` is called by `can_stack_at()` to decide whether `incoming` may share
a hex with the `existing` tokens. Omit to allow unlimited stacking.

### Methods

#### `register(token: MapToken) → void`
Adds `token` to the registry, indexes it at its current `hex_coord`, and connects
`token.moved_to` for automatic index updates. Idempotent — registering the same
token twice has no effect.

#### `remove(token: MapToken) → void`
Removes `token` from the registry, disconnects its signal, and clears its index
entry. The token itself is not freed — call `queue_free()` if needed.

#### `get_units(owner_id: int) → Array`
Returns all tokens owned by `owner_id`. Returns an empty array if none.

#### `get_all_units() → Array`
Returns all registered tokens regardless of owner.

#### `get_unit_at(coord: Vector2i) → MapToken`
Returns the first token at `coord`, or `null` if the hex is empty.

#### `get_units_at(coord: Vector2i) → Array`
Returns all tokens at `coord` (for stacking scenarios).

#### `has_units_at(coord: Vector2i) → bool`
Returns `true` if at least one token occupies `coord`.

#### `get_unmoved_units(owner_id: int) → Array`
Returns all tokens owned by `owner_id` that still have `movement_points > 0`.
Useful for "end of turn" checks.

#### `can_stack_at(coord: Vector2i, incoming: MapToken) → bool`
Calls the injected `stacking_fn` with the current occupants and `incoming`.
Returns `true` (allow stacking) if no `stacking_fn` was provided.

### Serialization

#### `serialize() → Array`
Returns an array of serialized token dictionaries (calls `token.serialize()` on each).

#### `static deserialize(data: Array, stacking_fn: Callable = Callable()) → UnitRegistry`
Reconstructs a `UnitRegistry` and all its tokens. Tokens are reconstructed via
`MapToken.deserialize()` — call `token.setup(coord, grid)` on each afterward to
reconnect them to a grid.

---

## CombatResolver

```
class_name CombatResolver
extends RefCounted
```

Stateless combat calculator. Computes a result dictionary without modifying any
tokens. All four calculation steps are individually replaceable via callables.

### Signal

| Signal | Payload | Emitted when |
|--------|---------|-------------|
| `combat_resolved` | `(attacker: MapToken, defender: MapToken, result: Dictionary)` | After each `resolve()` call |

### Constructor

```gdscript
CombatResolver.new(
    damage_fn:       Callable = Callable(),   # (atk: MapToken, def: MapToken) → float
    terrain_bonus_fn: Callable = Callable(),  # (token: MapToken, cell: HexCell) → float
    flanking_fn:     Callable = Callable(),   # (atk_coord: Vector2i, def_coord: Vector2i, grid: HexGrid) → float
    outcome_fn:      Callable = Callable()    # (atk_power: float, def_power: float) → Dictionary
) -> CombatResolver
```

All callables are optional. Omitting one uses the corresponding default behavior.

**Default damage:** `token.metadata.get("strength", 1.0)`.
**Default terrain bonus:** 0.0 (no terrain effect).
**Default flanking:** 0.0 (no flanking bonus).
**Default outcome:** winner is the token with higher total power; tie → `winner: null`.

### Methods

#### `resolve(attacker: MapToken, defender: MapToken, grid: HexGrid) → Dictionary`
Computes the full combat calculation and returns the result dictionary.
Emits `combat_resolved` after calculating.

**Default result keys:**

| Key | Type | Description |
|-----|------|-------------|
| `attacker_damage` | `float` | Total combat power of the attacker |
| `defender_damage` | `float` | Total combat power of the defender |
| `winner` | `MapToken` or `null` | Winning token, or `null` on a tie |

If you inject `outcome_fn`, the dictionary may contain additional keys.

### Calculation pipeline

```
attacker power = damage_fn(atk, def)  +  terrain_bonus_fn(atk, atk_cell)  +  flanking_fn(atk_coord, def_coord, grid)
defender power = damage_fn(def, atk)  +  terrain_bonus_fn(def, def_cell)

result = outcome_fn(atk_power, def_power)  or  default_outcome(...)
```

---

## HexMiniMap

```
class_name HexMiniMap
extends Node2D
```

Renders a scaled-down overview of the hex map with terrain colors, fog of war,
and token markers. Uses `_draw()` for direct canvas rendering — no child nodes.

### Methods

#### `setup(grid: HexGrid, display_size: Vector2 = Vector2(200, 150), fog: FogOfWar = null, player_id: int = 0, params: Dictionary = {}) → void`
Initializes the minimap. Must be called before the first frame.

**Parameters:**
- `grid` — The hex grid to render
- `display_size` — Size of the minimap in pixels
- `fog` — Optional `FogOfWar` instance. If provided, auto-connects `fog_changed`
  to refresh the minimap when visibility changes
- `player_id` — Which player's fog perspective to display
- `params` — Optional overrides:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `dot_radius` | `float` | `2.0` | Radius for terrain dots |
| `token_radius` | `float` | `3.0` | Radius for token markers |
| `color_hidden` | `Color` | `Color(0.05, 0.05, 0.08)` | Color for hidden cells |
| `terrain_colors` | `Dictionary` | `HexPalette.DEFAULT_TERRAIN_COLORS` | Terrain → color mapping |

```gdscript
var minimap := HexMiniMap.new()
minimap.setup(grid, Vector2(200, 150), fog, 0)
add_child(minimap)
```

#### `set_token_fn(fn: Callable) → void`
Sets the callable used to determine token marker colors.

**Signature:** `(coord: Vector2i) → Color`
Return `Color.TRANSPARENT` to skip drawing at that coordinate.

```gdscript
minimap.set_token_fn(func(coord: Vector2i) -> Color:
    var unit := registry.get_unit_at(coord)
    if unit == null:
        return Color.TRANSPARENT
    return Color.RED if unit.owner_id == 0 else Color.BLUE
)
```

#### `refresh() → void`
Forces a complete redraw. Call after changing terrain, tokens, or fog state
manually (if not using the auto-fog connection).

---

## TiledImporter

```
class_name TiledImporter
extends RefCounted
```

Static utility to import maps from [Tiled Map Editor](https://www.mapeditor.org/) JSON exports.
Converts tile layers to terrain and object layers to tags and metadata.

### Methods

#### `static from_file(path: String, terrain_fn: Callable, cost_table: Dictionary = {}) → HexGrid`
Loads a Tiled JSON file and returns a populated `HexGrid`.

**Parameters:**
- `path` — File path to the Tiled JSON (e.g. `"res://maps/level_01.json"`)
- `terrain_fn` — Callable `(gid: int) → int` that converts a Tiled tile GID to a
  `HexCell.Terrain` value (or custom terrain int)
- `cost_table` — Optional terrain cost table for the resulting grid

Returns a `HexGrid` with terrain set from tile layers and tags/metadata from
object layers. Returns `null` and logs an error if the file cannot be read.

```gdscript
var terrain_fn := func(gid: int) -> int:
    match gid:
        1: return HexCell.Terrain.PLAINS
        2: return HexCell.Terrain.FOREST
        3: return HexCell.Terrain.MOUNTAIN
        4: return HexCell.Terrain.WATER
        _: return HexCell.Terrain.PLAINS

var grid := TiledImporter.from_file("res://maps/level_01.json", terrain_fn)
```

#### `static from_json(json_text: String, terrain_fn: Callable, cost_table: Dictionary = {}) → HexGrid`
Same as `from_file` but takes a JSON string directly.

Expects Tiled maps configured with staggeraxis="y" and staggerindex="odd"
(pointy-top, odd-r offset — matching the plugin's coordinate system).

`hex_size` is derived from `tileheight / 2.0` in the Tiled map.

#### `static get_unique_gids(json_text: String) → Array[int]`
Returns all unique tile GIDs found in tile layers. Useful for building a
`terrain_fn` mapping before importing.

```gdscript
var json := FileAccess.open("res://map.json", FileAccess.READ).get_as_text()
var gids := TiledImporter.get_unique_gids(json)
# gids = [1, 2, 3, 5, 8] — use these to build your terrain_fn
```

### Tiled map requirements

- Export as **JSON** (not TMX)
- Use **hexagonal** orientation with **staggeraxis=y**, **staggerindex=odd**
- **Tile layers** → terrain (via `terrain_fn`)
- **Object layers** → `cell.tag` (from object "tag" property or type) and
  `cell.metadata` (from all custom properties)

---

## Visual Map Editor

The editor tools are `@tool` classes that run inside the Godot editor. They are
intended for use during level design, not at runtime (though `HexMapNode` works in
both contexts).

---

### HexMapNode

```
@tool
class_name HexMapNode
extends Node2D
```

A serializable map node. Stores cell data in its exported properties (saved with
the scene), renders a preview in the editor viewport, and converts to a `HexGrid`
at runtime.

#### Exported properties (visible in Inspector)

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `width` | `int` | `15` | Number of columns |
| `height` | `int` | `15` | Number of rows |
| `hex_size` | `float` | `32.0` | Hex radius in pixels |
| `cell_data` | `Dictionary` | `{}` | Per-cell data: `"x,y" → {terrain, elevation, tag, metadata, location_type, location_data}` |
| `terrain_visuals` | `TerrainVisualSet` | `null` | Optional textures for editor preview |

All dimension properties trigger an immediate visual refresh via `queue_redraw()`.
`cell_data` is the single source of truth — terrain, elevation, tag, and metadata
all live there per cell, enabling elevation-aware rendering with tinted colors.

#### Signals

| Signal | Payload | Emitted when |
|--------|---------|-------------|
| `terrain_painted` | `(coord: Vector2i, terrain: int)` | A cell's terrain changes (via editor paint or `set_terrain_at()`) |
| `cell_data_changed` | `(coord: Vector2i)` | Cell data (elevation, tag, metadata) changes |

#### Methods

##### `get_grid() → HexGrid`
Creates and returns a `HexGrid` populated with the current `cell_data`.
The grid uses `{} ` as the cost table (defaults) and `hex_size`.
Call this in `_ready()` to obtain the runtime grid.

```gdscript
@onready var map_node: HexMapNode = $HexMapNode

func _ready() -> void:
    var grid: HexGrid = map_node.get_grid()
```

##### `set_terrain_at(coord: Vector2i, terrain: int) → void`
Sets the terrain at `coord`. Emits `terrain_painted` and redraws. No-op if
`coord` is out of bounds or the terrain is already the same value.

##### `coord_at_pixel(pixel: Vector2) → Vector2i`
Converts a local-space pixel to the nearest hex coordinate.

---

### TerrainPalette

```
@tool
class_name TerrainPalette
extends HBoxContainer
```

Editor toolbar with terrain and elevation tabs. Managed automatically
by the plugin — you rarely need to interact with it directly.

**Limitation:** Only shows the five built-in terrain types. Custom terrain integers
registered via `cost_table` in `HexGrid` are not shown in the palette.

#### Signals

| Signal | Payload | Emitted when |
|--------|---------|-------------|
| `terrain_selected` | `(terrain: int)` | The user clicks a terrain button |
| `tool_selected` | `(tool: int)` | The user selects an editor tool (terrain/elevation) |
| `elevation_step_changed` | `(step: float)` | The elevation brush step changes |
| `target_elevation_changed` | `(target: float)` | The target elevation for SET mode changes |

#### Properties

| Name | Type | Description |
|------|------|-------------|
| `current_terrain` | `int` | The currently selected terrain int |

#### Methods

##### `set_terrain(terrain: int) → void`
Programmatically selects a terrain button. Emits `terrain_selected` if the value
changed.

---

### HexMapEditor

```
@tool
class_name HexMapEditor
extends RefCounted
```

Paint logic for the editor. Delegated to by `plugin.gd` to keep the plugin class
clean. Handles mouse input, hover preview, elevation painting, and undo/redo integration.

Supports terrain painting and elevation brush modes: RAISE, LOWER, and SET.

#### Properties

| Name | Type | Description |
|------|------|-------------|
| `active_node` | `HexMapNode` | The map node currently being edited |
| `current_terrain` | `int` | Terrain to paint on click/drag |
| `hovered_coord` | `Vector2i` | Hex under the mouse cursor; `Vector2i(-1, -1)` if none |
| `is_painting` | `bool` | `true` while left mouse button is held |
| `undo_redo_fn` | `Callable` | `() → EditorUndoRedoManager`; enables Ctrl+Z support |
| `elevation_step` | `float` | Amount to raise/lower elevation per click |
| `target_elevation` | `float` | Target elevation for SET mode |

#### Signal

| Signal | Emitted when |
|--------|-------------|
| `repaint_needed` | The hover overlay changed and the viewport must redraw |

#### Methods

##### `handle_input(event: InputEvent, viewport: Viewport) → bool`
Processes a single input event. Returns `true` if the event was consumed.
- **Left mouse press:** begins painting at the clicked hex
- **Left mouse drag:** continues painting across hovered hexes
- **Mouse move:** updates `hovered_coord` and emits `repaint_needed`

##### `draw_overlays(overlay: Control) → void`
Draws the hover preview (a semi-transparent colored polygon) using Godot's
`CanvasItem` drawing API. Call from `_draw()` or `_forward_canvas_draw_over_viewport()`.

---

## Signals — complete reference

| Class | Signal | Payload |
|-------|--------|---------|
| `MapToken` | `moved_to` | `(coord: Vector2i)` |
| `MapToken` | `movement_started` | — |
| `MapToken` | `movement_exhausted` | — |
| `TurnManager` | `player_turn_started` | `(player_id: int)` |
| `TurnManager` | `player_turn_ended` | `(player_id: int)` |
| `TurnManager` | `round_ended` | `(round: int)` |
| `TurnManager` | `phase_started` | `(player_id: int, phase: String)` |
| `TurnManager` | `phase_ended` | `(player_id: int, phase: String)` |
| `CombatResolver` | `combat_resolved` | `(attacker: MapToken, defender: MapToken, result: Dictionary)` |
| `HexMapNode` | `terrain_painted` | `(coord: Vector2i, terrain: int)` |
| `HexMapNode` | `cell_data_changed` | `(coord: Vector2i)` |
| `TerrainPalette` | `terrain_selected` | `(terrain: int)` |
| `TerrainPalette` | `tool_selected` | `(tool: int)` |
| `TerrainPalette` | `elevation_step_changed` | `(step: float)` |
| `TerrainPalette` | `target_elevation_changed` | `(target: float)` |
| `HexMapEditor` | `repaint_needed` | — |
| `UnitSelector` | `selection_changed` | `(units: Array[MapToken])` |

## Callables — complete reference

| Callable | Injected into | Signature | Default behavior |
|----------|--------------|-----------|-----------------|
| `movement_fn` | `MapToken.setup` | `(level: int) → float` | `6.0` |
| `stacking_fn` | `UnitRegistry._init` | `(existing: Array, incoming: MapToken) → bool` | Always `true` |
| `damage_fn` | `CombatResolver._init` | `(atk: MapToken, def: MapToken) → float` | `metadata["strength"]` or `1.0` |
| `terrain_bonus_fn` | `CombatResolver._init` | `(token: MapToken, cell: HexCell) → float` | `0.0` |
| `flanking_fn` | `CombatResolver._init` | `(atk_coord: Vector2i, def_coord: Vector2i, grid: HexGrid) → float` | `0.0` |
| `outcome_fn` | `CombatResolver._init` | `(atk_power: float, def_power: float) → Dictionary` | Higher power wins |
| `undo_redo_fn` | `HexMapEditor` | `() → EditorUndoRedoManager` | Paint without undo history |
| `terrain_fn` | `TiledImporter.from_file/from_json` | `(gid: int) → int` | Required — no default |
| `token_fn` | `HexMiniMap.set_token_fn` | `(coord: Vector2i) → Color` | No token markers |
| `tokens_provider` | `UnitSelector.setup` | `() → Array[MapToken]` | Required — no default |
| `selectable_fn` | `UnitSelector.setup` | `(token: MapToken) → bool` | All candidates accepted |
