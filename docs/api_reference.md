# API Reference — Hex Strategy Map (Free)

Complete reference for all free tier classes.

_Hex coordinate algorithms informed by [Red Blob Games — Hexagonal Grids](https://www.redblobgames.com/grids/hexagons/) by Amit Patel._

---

## HexGrid

```
class_name HexGrid
extends RefCounted
```

The data model for the hex map. Holds all cells, edges, terrain costs, and provides
coordinate conversion, neighbor queries, and pathfinding helpers.

### Constructor

```gdscript
HexGrid.new(
    map_width:       int        = 15,
    map_height:      int        = 15,
    cost_table:      Dictionary = {},   # int terrain → float cost (-1 = impassable)
    size:            float      = 0.0,  # hex radius in pixels; 0 = use HEX_SIZE (32)
    edge_cost_table: Dictionary = {}    # int EdgeType → float delta cost
) -> HexGrid
```

### Enums

#### `Terrain`

| Value | Int | Default cost |
|-------|-----|-------------|
| `ROAD` | 0 | 1.0 |
| `PLAINS` | 1 | 1.5 |
| `FOREST` | 2 | 2.0 |
| `MOUNTAIN` | 3 | 3.0 |
| `WATER` | 4 | −1.0 (impassable) |

You can extend terrain by using any integer value ≥ 5 and registering it in
`cost_table`. The enum values are only defaults.

#### `EdgeType`

| Value | Int | Default delta cost |
|-------|-----|-------------------|
| `NONE` | 0 | 0.0 |
| `RIVER` | 1 | +2.0 |
| `ROAD` | 2 | −0.5 |
| `WALL` | 3 | −1.0 (makes crossing impassable) |
| `CUSTOM` | 4 | 0.0 (set via `properties["cost"]`) |

### Constants

| Name | Type | Value | Description |
|------|------|-------|-------------|
| `HEX_SIZE` | `float` | `32.0` | Default hex radius in pixels |
| `HEX_SQRT3` | `float` | `1.732…` | √3, precomputed for pixel conversions |
| `TERRAIN_COST` | `Dictionary` | see Terrain enum | Default cost table |
| `EDGE_COST` | `Dictionary` | see EdgeType enum | Default edge cost table |

### Properties

| Name | Type | Description |
|------|------|-------------|
| `width` | `int` | Number of columns |
| `height` | `int` | Number of rows |
| `cells` | `Dictionary` | `Vector2i → HexCell`; all cells in the grid |
| `edges` | `Dictionary` | `String → Dictionary`; all edges, keyed by `edge_key()` |
| `terrain_cost` | `Dictionary` | `int → float`; active cost table |
| `edge_cost` | `Dictionary` | `int → float`; active edge cost table |
| `hex_size` | `float` | Hex radius in pixels used for pixel conversions |

### Cell methods

#### `generate_cells(default_terrain: int = Terrain.PLAINS) → void`
Clears and repopulates `cells` with one `HexCell` per grid coordinate.
Call once after creating the grid.

#### `get_cell(coord: Vector2i) → HexCell`
Returns the cell at `coord`, or `null` if the coordinate is outside the grid.

#### `get_all_cells() → Dictionary`
Returns the full `cells` dictionary. Equivalent to reading `grid.cells` directly.

#### `set_terrain(coord: Vector2i, terrain: int) → void`
Sets `cell.terrain` for the cell at `coord`. Does nothing if the coord is invalid.

#### `is_valid(coord: Vector2i) → bool`
Returns `true` if `coord` exists in `cells`.

#### `is_passable(coord: Vector2i) → bool`
Returns `true` if the cell exists and its terrain cost is > 0.

#### `get_movement_cost(coord: Vector2i) → float`
Returns the terrain cost at `coord`, or `−1.0` if the coord is invalid.

### Edge methods

#### `set_edge(a: Vector2i, b: Vector2i, edge_type: int, properties: Dictionary = {}) → void`
Creates or replaces the edge between adjacent hexes `a` and `b`.
`properties` may contain a `"cost"` key to override the default cost for the edge type.

```gdscript
# River slows movement by 2.0 (default for RIVER)
grid.set_edge(Vector2i(3, 2), Vector2i(4, 2), HexGrid.EdgeType.RIVER)

# Custom cost override
grid.set_edge(Vector2i(5, 5), Vector2i(6, 5), HexGrid.EdgeType.CUSTOM, {"cost": 1.0})
```

#### `get_edge(a: Vector2i, b: Vector2i) → Dictionary`
Returns the edge dictionary for the pair, or an empty Dictionary if no edge exists.
The dictionary always contains `"type": int` and `"cost": float`.

#### `has_edge(a: Vector2i, b: Vector2i) → bool`
Returns `true` if an edge exists between `a` and `b`.

#### `remove_edge(a: Vector2i, b: Vector2i) → void`
Removes the edge between `a` and `b`, if any.

#### `get_edges_for(coord: Vector2i) → Array[Dictionary]`
Returns all edges connected to `coord`.

#### `get_edge_cost(from: Vector2i, to: Vector2i) → float`
Returns the delta cost for crossing the edge from `from` to `to`, or `0.0` if no
edge exists. Negative values reduce the effective movement cost.

#### `static edge_key(a: Vector2i, b: Vector2i) → String`
Returns the canonical string key used to store an edge in `edges`.
The key is order-independent: `edge_key(a, b) == edge_key(b, a)`.

### Navigation methods

#### `get_reachable_hexes(origin: Vector2i, movement_points: float) → Dictionary`
Convenience wrapper around `PathFinder.find_reachable`.
Returns `Dictionary[Vector2i, float]` — coord → accumulated cost.

#### `get_ring(center: Vector2i, radius: int) → Array[Vector2i]`
Returns all valid grid coordinates exactly `radius` hexes away from `center`.
Returns `[center]` when `radius == 0`.

#### `get_line_of_sight(from: Vector2i, to: Vector2i, blocking_terrains: Array[int] = []) → bool`
Returns `true` if there is an unobstructed line from `from` to `to`.
Intermediate hexes (not `from` or `to`) are checked against `blocking_terrains`.
An empty `blocking_terrains` means nothing blocks — always returns `true` for valid coords.

```gdscript
# Mountains and forests block sight
var can_see := grid.get_line_of_sight(
    Vector2i(2, 2), Vector2i(8, 6),
    [HexGrid.Terrain.MOUNTAIN, HexGrid.Terrain.FOREST]
)
```

#### `get_zone_of_control(unit_coords: Array[Vector2i]) → Array[Vector2i]`
Returns all valid grid hexes adjacent to any hex in `unit_coords`, excluding the
unit hexes themselves. Useful for ZoC mechanics in tactical games.

### Static coordinate methods

#### `static offset_to_pixel(coord: Vector2i, size: float = HEX_SIZE) → Vector2`
Converts offset coord to world pixel position (pointy-top, odd-r layout).

#### `static pixel_to_offset(pixel: Vector2, size: float = HEX_SIZE) → Vector2i`
Converts world pixel to the nearest offset coordinate.

#### `static offset_to_cube(coord: Vector2i) → Vector3i`
Converts offset coord to cube coordinates `(x, y, z)` where `x + y + z = 0`.

#### `static distance(a: Vector2i, b: Vector2i) → int`
Returns the hex distance between two offset coordinates.

#### `static get_neighbors(coord: Vector2i) → Array[Vector2i]`
Returns all 6 adjacent hex coordinates (may include out-of-grid coords).
Use `is_valid()` to filter if needed.

### Serialization

#### `serialize() → Dictionary`
Returns a JSON-serializable dictionary representing the full grid state including
all cells, edges, terrain costs, and hex_size.

#### `static deserialize(data: Dictionary) → HexGrid`
Reconstructs a `HexGrid` from a previously serialized dictionary.
Handles the JSON int-key-as-string conversion automatically.

---

## HexCell

```
class_name HexCell
extends RefCounted
```

Lightweight data object for a single hex. Holds terrain, gameplay tags, per-player
fog state, and arbitrary metadata.

### Constructor

```gdscript
HexCell.new(
    cell_coord:   Vector2i = Vector2i.ZERO,
    cell_terrain: int      = HexGrid.Terrain.PLAINS
) -> HexCell
```

### Properties

| Name | Type | Description |
|------|------|-------------|
| `coord` | `Vector2i` | Grid coordinate of this cell |
| `terrain` | `int` | Terrain type (any int from HexGrid.Terrain or custom) |
| `tag` | `int` | Generic game tag (0 = unset). Use for location types, city IDs, etc. |
| `metadata` | `Dictionary` | Arbitrary key-value store for game-specific data |
| `explored_by` | `Dictionary` | `player_id (int) → bool`; which players have explored this cell |
| `visible_by` | `Dictionary` | `player_id (int) → bool`; which players currently see this cell |
| `location_type` | `int` | Legacy alias for `tag`. Prefer `tag` in new code. |
| `location_data` | `Dictionary` | Legacy alias for `metadata`. Prefer `metadata` in new code. |

### Methods

#### `get_pixel_position() → Vector2`
Returns the world pixel position of this cell using the default `HexGrid.HEX_SIZE`.
For custom hex sizes, call `HexGrid.offset_to_pixel(coord, your_size)` instead.

#### `has_tag() → bool`
Returns `true` if `tag != 0`.

#### `has_location() → bool`
Returns `true` if `location_type != 0` (legacy method, equivalent to `has_tag()`).

#### `is_explored_by(player_id: int) → bool`
Returns `true` if this cell has been visited by the given player.

#### `is_visible_by(player_id: int) → bool`
Returns `true` if this cell is currently in the given player's visible range.

#### `get_fog_state(player_id: int = 0) → int`
Returns the fog state as a `FogOfWar.FogState` int:
- `0` = `HIDDEN` — never explored
- `1` = `EXPLORED` — visited but not currently visible
- `2` = `VISIBLE` — currently in sight range

Available in the free tier; use `FogOfWar` (also free) to update the state automatically.

### Serialization

#### `serialize() → Dictionary`
Returns a JSON-serializable dictionary with all cell data.

#### `static deserialize(data: Dictionary) → HexCell`
Reconstructs a cell from a serialized dictionary.

---

## TerrainVisualEntry

```
class_name TerrainVisualEntry
extends Resource
```

A single terrain-to-texture mapping used by `TerrainVisualSet`. Create entries in
the Inspector or programmatically.

### Properties

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `terrain_id` | `int` | `0` | Terrain type (matches `HexCell.Terrain.*` or custom values) |
| `texture` | `Texture2D` | `null` | The texture to render for this terrain |
| `offset` | `Vector2` | `Vector2.ZERO` | Pixel offset from hex center |
| `auto_scale` | `bool` | `true` | Automatically scale texture to fit hex height |

---

## TerrainVisualSet

```
class_name TerrainVisualSet
extends Resource
```

Maps terrain types to textures with auto-scaling. Assign to `HexMapNode.terrain_visuals`
for Inspector-driven terrain visuals, or use `make_tile_visual_fn()` to generate a
Callable for `HexRenderer`.

When not assigned, all rendering falls back to colored polygons.

### Properties

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `entries` | `Array[TerrainVisualEntry]` | `[]` | One entry per terrain type |
| `filter_nearest` | `bool` | `true` | Use nearest-neighbor filtering (for pixel art) |

### Methods

#### `get_texture(terrain_id: int) → Texture2D`
Returns the texture for the given terrain, or `null` if not configured.

#### `get_scale_for(terrain_id: int, hex_size: float) → Vector2`
Returns the scale vector for the terrain's texture. When `auto_scale` is `true`,
computes `(hex_size * 2.0) / texture_height` to fit the hex vertically.
Returns `Vector2.ONE` when auto-scaling is disabled or the terrain has no texture.

#### `get_offset_for(terrain_id: int) → Vector2`
Returns the configured pixel offset for the terrain, or `Vector2.ZERO`.

#### `make_tile_visual_fn(hex_size: float) → Callable`
Returns a `(HexCell) → Node2D` Callable suitable for `HexRenderer`'s `tile_visual_fn`
parameter. Creates a `Sprite2D` with the correct texture, scale, offset, and filtering
for each cell's terrain.

```gdscript
var renderer := HexRenderer.new(
    {}, Callable(), {}, HexGrid.HEX_SIZE,
    terrain_visuals.make_tile_visual_fn(HexGrid.HEX_SIZE)
)
```

---

## PathFinder

```
class_name PathFinder
extends RefCounted
```

Static pathfinding utilities. All methods are `static` — no instantiation needed.

### Methods

#### `static find_reachable(origin: Vector2i, max_cost: float, grid: HexGrid) → Dictionary`
Dijkstra flood-fill from `origin` up to `max_cost` movement points.
Returns `Dictionary[Vector2i, float]` — every reachable coord mapped to its
accumulated cost. The origin is always included with cost `0.0`.

Impassable cells (cost ≤ 0) are skipped. Edge costs are included.

```gdscript
var reachable := PathFinder.find_reachable(Vector2i(3, 3), 6.0, grid)
print(reachable.has(Vector2i(5, 3)))  # true if reachable within 6 points
```

#### `static find_path(from: Vector2i, to: Vector2i, reachable: Dictionary, grid: HexGrid) → Array[Vector2i]`
Dijkstra shortest path from `from` to `to`, constrained to hexes in `reachable`.
Returns the path **excluding** `from` and **including** `to`.
Returns an empty array if `to` is not in `reachable` or no path exists.

**Typical usage:** call `find_reachable` first, show the movement range, then call
`find_path` when the player clicks a destination.

```gdscript
var reachable := PathFinder.find_reachable(origin, movement_pts, grid)
var path     := PathFinder.find_path(origin, destination, reachable, grid)
```

#### `static find_path_unlimited(from: Vector2i, to: Vector2i, grid: HexGrid) → Array[Vector2i]`
Dijkstra shortest path with no movement limit. Useful for showing the route to a
distant destination regardless of how many turns it will take.
Returns empty array if `to` is impassable or unreachable.

#### `static find_path_astar(from: Vector2i, to: Vector2i, grid: HexGrid) → Array[Vector2i]`
A\* shortest path using cube distance as the heuristic. Typically faster than
`find_path_unlimited` on large open maps; produces optimal results when the minimum
terrain cost in the grid is ≥ 1.0.

### Choosing between pathfinding methods

| Method | Movement limit | Speed | Use when |
|--------|---------------|-------|----------|
| `find_reachable` + `find_path` | Yes | Fast | Turn-based unit movement |
| `find_path_unlimited` | No | Medium | Route preview, AI planning |
| `find_path_astar` | No | Fastest | Large maps, frequent queries |

### Inner class — MinHeap

`PathFinder.MinHeap` is a binary min-heap used internally. It is also used by
`FlowField`. You rarely need to use it directly.

```gdscript
var heap := PathFinder.MinHeap.new()
heap.push([cost: float, coord: Vector2i])
var item: Array = heap.pop()   # [cost, coord]
heap.is_empty() -> bool
```

---

## FogOfWar

```
class_name FogOfWar
extends RefCounted
```

3-state per-player fog of war. Manages `HexCell.explored_by` and
`HexCell.visible_by` dictionaries; all state is stored in the cells themselves.

### Enum — FogState

| Value | Int | Meaning |
|-------|-----|---------|
| `HIDDEN` | 0 | Cell never explored by this player |
| `EXPLORED` | 1 | Cell visited in a previous turn; not currently visible |
| `VISIBLE` | 2 | Cell currently in the player's sight range |

### Signals

| Signal | Payload | Emitted when |
|--------|---------|-------------|
| `fog_changed` | `(player_id: int, coord: Vector2i, old_state: int, new_state: int)` | A cell transitions between FogState values |

`fog_changed` is only emitted when the state actually changes — not on redundant
reveals of already-visible cells.

### Constructor

```gdscript
FogOfWar.new(
    hex_grid:       HexGrid,
    visibility_fn:  Callable = Callable()   # (unit_level: int) → int
) -> FogOfWar
```

`visibility_fn` computes the visibility radius for a given unit level.
Default formula: `min(1 + (level - 1) / 2, 3)` — level 1 → radius 1, level 3 → 2, level 5+ → 3.

### Methods

#### `static get_state(cell: HexCell, player_id: int = 0) → int`
Returns the `FogState` for `cell` from the perspective of `player_id`.
Does not require a `FogOfWar` instance — can be called as `FogOfWar.get_state(cell, 0)`.

#### `get_visibility_radius(unit_level: int) → int`
Returns the sight radius for a unit at the given level, using the injected
`visibility_fn` or the default formula if none was provided.

#### `reveal_around(player_id: int, center: Vector2i, radius: int) → void`
Marks all cells within `radius` hexes of `center` as explored and visible for
`player_id`. Does not clear the previous visible set.

Use this for one-time reveals (e.g. scouting abilities, starting positions).

#### `update_visibility(player_id: int, unit_pos: Vector2i, radius: int) → void`
Clears the current visible set for `player_id`, then reveals from `unit_pos`.
Previously explored cells remain in `EXPLORED` state.

```gdscript
fog.update_visibility(0, coord, 3)
renderer.update_fog(hex_container, grid, 0)
```

#### `update_visibility_multi(player_id: int, positions: Array[Vector2i], radius_fn: Callable) → void`
Clears visible set for `player_id`, then reveals from each position in `positions`.
`radius_fn` has signature `(pos: Vector2i) → int`.

#### `reveal_with_los(player_id: int, center: Vector2i, radius: int, blocking_terrains: Array[int] = [], elevation_fn: Callable = Callable()) → void`
Reveals cells within `radius` that have clear line of sight from `center`.
`blocking_terrains` specifies which terrains block LOS. `elevation_fn` is a
`Callable` with signature `(coord: Vector2i) → float` that returns elevation;
higher cells can see over lower ones.

#### `get_explored_count(player_id: int = 0) → int`
Returns the number of cells that `player_id` has explored (state EXPLORED or VISIBLE).

### Serialization

#### `serialize() → Dictionary`
Returns a JSON-serializable dictionary with the visible-by-player data.

#### `static deserialize(data: Dictionary, hex_grid: HexGrid) → FogOfWar`
Reconstructs a `FogOfWar` instance from serialized data and a pre-restored grid.

---

## FogTextureRenderer

> **⭐ Pro tier only.** This class lives in the Pro distribution. The free tier still provides full Fog of War via `FogOfWar` (data model) and per-hex fog rendering via `HexRenderer.fog_material`. `FogTextureRenderer` is the recommended path for large maps (200×200+) and continuous bilinear-smoothed fog.

```
class_name FogTextureRenderer
extends RefCounted
```

Alternative fog of war renderer that draws a **single `Polygon2D`** covering the
whole map, backed by a visibility texture (one texel per hex). Unlike `HexRenderer`'s
per-hex fog (which renders one shader instance per cell), this approach scales to
grids of tens of thousands of hexes and produces a **continuous bilinear-smoothed
fog** that flows between cells, matching the look of Civilization/StarCraft.

Compatible with any terrain renderer (`HexRenderer.render()`, `HexBatchRenderer.render()`,
or a custom one). Reads the same `FogOfWar` + `HexCell` model — it is a render alternative,
not a model replacement. Recommended for use alongside `HexBatchRenderer.render()` since the
batch path's built-in fog is flat color only.

### Constants

| Name | Type | Value | Description |
|------|------|-------|-------------|
| `VIS_HIDDEN` | `float` | `0.0` | Texel value for `FogState.HIDDEN` |
| `VIS_EXPLORED` | `float` | `0.5` | Texel value for `FogState.EXPLORED` |
| `VIS_VISIBLE` | `float` | `1.0` | Texel value for `FogState.VISIBLE` |

### Methods

#### `setup(parent: Node2D, grid: HexGrid, hex_size: float = 0.0) → Polygon2D`
Creates the fog quad as a child of `parent`, covering the AABB of the grid.
When `hex_size` is 0, uses `grid.hex_size`. Returns the created `Polygon2D` (named
`"FogTextureQuad"`, `z_index = 100`). Must be called once before any update method.

```gdscript
var fog_tex := FogTextureRenderer.new()
fog_tex.setup(plane_container, grid)
```

#### `update(fog: FogOfWar, player_id: int = 0) → void`
Full sweep: re-reads `HexCell.get_fog_state(player_id)` for every cell in the grid
and uploads the texture immediately. O(width × height). Use when initializing or
after a large state change. For per-cell updates triggered by gameplay events,
prefer `connect_to()` or `update_cell()`.

#### `connect_to(fog: FogOfWar, player_id: int = 0) → void`
Subscribes to `fog.fog_changed`. Each emitted change updates one texel in the
internal image and schedules a deferred GPU upload. Multiple `fog_changed` emits
in the same frame coalesce into a **single** texture upload (via `call_deferred`).
Calls `update()` once internally to paint the initial state. Only updates for the
matching `player_id` are processed.

```gdscript
fog_tex.setup(plane_container, grid)
fog_tex.connect_to(fog, PLAYER_ID)
# From now on, every fog.update_visibility(...) auto-syncs the texture.
```

#### `update_cell(coord: Vector2i, fog_state: int) → void`
Writes one texel and marks the texture dirty. The flush happens at the end of the
frame via `call_deferred`. Out-of-bounds coords are silently ignored.

#### `flush() → void`
Forces the GPU upload of any pending texel writes. Called automatically by
`update_cell` via `call_deferred`; expose for manual control when needed (e.g. tests
that don't run the deferred queue).

#### `set_animated(enabled: bool) → void`
Toggles the shader's animated value noise on the fog. Default: `true`.

#### `set_hidden_color(color: Color) → void`
Sets the color used for `HIDDEN` cells (`vis = 0.0`). Alpha controls opacity.
Default: `Color(0, 0, 0, 0.92)`.

#### `set_explored_color(color: Color) → void`
Sets the color used for `EXPLORED` cells (`vis = 0.5`). Default: `Color(0, 0, 0, 0.50)`.

#### `set_debug_visibility(enabled: bool) → void`
When `true`, the shader skips fog colors and paints raw visibility:
red = `HIDDEN`, yellow = `EXPLORED`, green = `VISIBLE`. Useful to verify that
the visibility texture is being updated correctly.

#### `get_visibility_image() → Image`
Returns the internal `Image` used as the visibility texture's CPU backing. Useful
for tests, debugging, or serializing the fog state to disk.

### Notes & caveats

- The internal image format is `Image.FORMAT_RGBA8` (the visibility value is
  replicated into R, G, B; alpha is always 1). RGBA was chosen over R8 to avoid
  driver-specific quirks observed during development.
- On each `flush()`, the `ImageTexture` is **recreated** (`ImageTexture.create_from_image`)
  and reassigned to the polygon. This bypasses an `ImageTexture.update()` propagation
  issue observed with Intel Iris Xe + Vulkan. Cost: one ~250 KB upload per flush at
  250×250 grid size — negligible at typical scales.
- UV mapping is linear across the grid; the half-hex offset of odd rows is not
  compensated. At usual scales (hex_size ≥ 16 px) the artifact is imperceptible
  thanks to bilinear filtering.
- `connect_to()` filters by `player_id` — only the connected player's events update
  the texture. For multi-viewport or split-screen scenarios, use one
  `FogTextureRenderer` per player.

### Shader uniforms

The fog quad's `ShaderMaterial` exposes these uniforms (via `set_shader_parameter`
or the dedicated setters above):

| Uniform | Type | Default | Description |
|---------|------|---------|-------------|
| `hidden_color` | `vec4` | `(0, 0, 0, 0.92)` | Color for HIDDEN cells |
| `explored_color` | `vec4` | `(0, 0, 0, 0.50)` | Color for EXPLORED cells |
| `animated` | `bool` | `true` | Enable animated noise |
| `noise_scale` | `float` | `6.0` | Spatial frequency of noise |
| `noise_speed` | `float` | `0.15` | Animation speed (TIME multiplier) |
| `noise_strength` | `float` | `0.18` | Alpha variation amplitude |
| `debug_show_visibility` | `bool` | `false` | Debug mode (visibility as RGB) |

---

## HexRenderer

```
class_name HexRenderer
extends RefCounted
```

Turns `HexCell` data into Godot `Node2D` subtrees. All rendering is done via
standard Godot nodes — no custom shaders or imports required.

### Constructor

```gdscript
HexRenderer.new(
    terrain_colors:  Dictionary = DEFAULT_TERRAIN_COLORS,
    cell_icon_fn:    Callable   = Callable(),   # (HexCell) → String
    fog_colors:      Dictionary = {},           # {FogState: Color}; empty = defaults
    hex_size:        float      = HexGrid.HEX_SIZE,
    tile_visual_fn:  Callable   = Callable(),   # (HexCell) → Node2D
    texture_fn:      Callable   = Callable(),   # (HexCell) → Texture2D
    animation_fn:    Callable   = Callable(),   # (HexCell) → SpriteFrames
    overlay_fn:      Callable   = Callable(),   # (HexCell) → Array[Node2D]
    reachable_color: Color      = REACHABLE_COLOR,
    border_color:    Color      = BORDER_COLOR,
    border_width:    float      = BORDER_WIDTH,
    color_fn:        Callable   = Callable(),   # (HexCell) → Color
) -> HexRenderer
```

All parameters are optional — `terrain_colors` and `color_fn` are the most commonly overridden.

#### Callable signatures

| Parameter | Signature | Return | Fallback if omitted |
|-----------|-----------|--------|---------------------|
| `cell_icon_fn` | `(cell: HexCell) → String` | Icon text for a Label; `""` = no icon | No icon |
| `tile_visual_fn` | `(cell: HexCell) → Node2D` | Fully custom background node | Polygon2D |
| `texture_fn` | `(cell: HexCell) → Texture2D` | Texture for a Sprite2D | Polygon2D |
| `animation_fn` | `(cell: HexCell) → SpriteFrames` | Frames for AnimatedSprite2D | Polygon2D |
| `overlay_fn` | `(cell: HexCell) → Array[Node2D]` | Extra nodes added on top | None |
| `color_fn` | `(cell: HexCell) → Color` | Per-cell color; return `SKIP_COLOR` to fall back to `terrain_colors` | `terrain_colors` lookup |

Only one of `tile_visual_fn`, `texture_fn`, `animation_fn` is used per cell;
`tile_visual_fn` takes priority, then `animation_fn`, then `texture_fn`.

> **Batch mode caveat**: `HexBatchRenderer` is a separate class with its own
> narrower API. It draws terrain color + fog + highlight only — no icons,
> textures, animations, custom tile visuals, or overlays. For continuous
> global fog on a batch grid, pair it with `FogTextureRenderer`.

### Constants

| Name | Type | Description |
|------|------|-------------|
| `DEFAULT_ICON_OFFSET` | `Vector2` | Default icon label offset from hex center (`-6, -6`). Override via `icon_offset` callable key in `_init`. |
| `DEFAULT_ICON_FONT_SIZE` | `int` | Default icon label font size (`12`). Override via `icon_font_size` callable key in `_init`. |

Color defaults (`DEFAULT_TERRAIN_COLORS`, `DEFAULT_FOG_COLORS`, `REACHABLE_COLOR`,
`BORDER_COLOR`, `BORDER_WIDTH`, `SKIP_COLOR`) live on `HexPalette` — see the
`HexPalette` section.

### Signals

| Signal | Payload | Emitted when |
|--------|---------|-------------|
| `cell_pressed` | `(coord: Vector2i, event: InputEvent)` | Mouse button or touch press over a hex |
| `cell_released` | `(coord: Vector2i, event: InputEvent)` | Mouse button or touch release over a hex |

Both signals fire via `Area2D.input_event` for any mouse button and touch events.
Filter `event.button_index == MOUSE_BUTTON_LEFT` in your handler if needed.
Not emitted by `HexBatchRenderer`.

### Hex node structure

After `create_hex_visual()`, each hex in the container has this node tree:

```
Area2D  (name: "Hex_X_Y")
├── CollisionPolygon2D
├── Bg              ← Polygon2D, Sprite2D, AnimatedSprite2D, or custom Node2D
├── Border          ← Line2D
├── CellIcon        ← Label (only if cell_icon_fn returns non-empty string)
├── Highlight       ← Polygon2D (invisible by default; used for reachable/selection)
├── Fog             ← Polygon2D (invisible by default; activated by update_fog)
└── [overlays]      ← zero or more nodes from overlay_fn
```

### Methods

#### `create_hex_visual(hex_container: Node2D, coord: Vector2i, pixel: Vector2, cell: HexCell) → void`
Creates the full node subtree for one hex and adds it to `hex_container`.
Call once per cell during map initialization.

```gdscript
for coord in grid.cells:
    var pixel := HexGrid.offset_to_pixel(coord, renderer._hex_size)
    renderer.create_hex_visual(hex_container, coord, pixel, grid.cells[coord])
```

#### `static get_visual_for(container: Node2D, coord: Vector2i) → Node2D`
Returns the `Area2D` node for the hex at `coord`, or `null` if it does not exist.
Preferred over `container.get_node("Hex_X_Y")` — the internal name format is an implementation detail.

```gdscript
var hex := HexRenderer.get_visual_for(hex_container, Vector2i(3, 2))
if hex:
    hex.modulate = Color(1.0, 0.8, 0.8)
```

#### `static get_visual_part(container: Node2D, coord: Vector2i, part_name: String) → CanvasItem`
Returns a named child of the hex `Area2D` as a `CanvasItem`, or `null` if the hex or
the part does not exist. Standard part names: `"Bg"`, `"Border"`, `"Highlight"`, `"Fog"`,
`"CellIcon"`. All extend `CanvasItem`, giving access to `.visible`, `.modulate`, `.material`.

```gdscript
var hl: CanvasItem = HexRenderer.get_visual_part(hex_container, coord, "Highlight")
if hl:
    hl.visible = false
```

#### `render_edges(edge_container: Node2D, grid: HexGrid, edge_color: Color = Color(0.2, 0.5, 0.8, 0.8), edge_width: float = 2.0, mode: HexRenderer.EdgeRenderMode = HexRenderer.EdgeRenderMode.CENTERS) → void`
Clears `edge_container` and draws `Line2D` nodes for every edge in `grid.edges`.
Call after setting up edges, and again if edges change at runtime.

The `mode` parameter controls segment geometry:
- `EdgeRenderMode.CENTERS` (default) — each line goes from the center of one
  hex to the center of the other, crossing both. Best for **roads, bridges,
  navigable rivers** or any connection that *runs through* the cells.
- `EdgeRenderMode.SHARED_BORDER` — each segment is centered on the midpoint
  between the two cells, perpendicular to the center-to-center line, with
  length equal to `HexGrid.HEX_SIZE` (the hexagon side length). Best for
  **walls, fences, river barriers, terrain boundaries** — anything that
  *separates* two cells without covering them.

```gdscript
# Default — roads / navigable rivers
renderer.render_edges(edge_container, grid, Color(0.30, 0.55, 0.85), 3.0)

# Walls / barriers — segment sits on the shared border
renderer.render_edges(edge_container, grid, Color(0.85, 0.30, 0.30), 4.0,
    HexRenderer.EdgeRenderMode.SHARED_BORDER)
```

#### `update_reachable_highlight(hex_container: Node2D, grid: HexGrid, reachable: Dictionary, highlighted_hexes: Dictionary) → void`
Shows the `Highlight` overlay on all hexes in `reachable` and hides it on any
previously highlighted hexes not in the new set.

`highlighted_hexes` is an output/tracking dictionary you own; pass the same one
each call so the renderer knows what to clear.

```gdscript
var highlighted: Dictionary = {}

# Show movement range
var reachable := PathFinder.find_reachable(origin, points, grid)
renderer.update_reachable_highlight(hex_container, grid, reachable, highlighted)

# Clear highlights
renderer.update_reachable_highlight(hex_container, grid, {}, highlighted)
```

#### `update_fog(hex_container: Node2D, grid: HexGrid, player_id: int = 0) → void`
Updates the `Fog` overlay on every hex based on the current fog state in each
`HexCell`. Requires `explored_by` / `visible_by` to be populated — set these manually
or let `FogOfWar` (also free) manage them automatically.

| Fog state | Bg | Border | CellIcon | Fog overlay |
|-----------|-----|--------|----------|-------------|
| VISIBLE | shown | shown | shown | hidden |
| EXPLORED | shown | shown | hidden | shown (semi-transparent) |
| HIDDEN | hidden | hidden | hidden | shown (opaque) |

#### `update_cell_visual(hex_container: Node2D, coord: Vector2i, cell: HexCell) → void`
Replaces the `Bg` node of a single hex with a freshly generated one.
Use when a cell's terrain changes at runtime and the visual needs to update.

```gdscript
grid.set_terrain(Vector2i(5, 3), HexGrid.Terrain.FOREST)
renderer.update_cell_visual(hex_container, Vector2i(5, 3), grid.cells[Vector2i(5, 3)])
```

#### `refresh_cell_color(hex_container: Node2D, coord: Vector2i, cell: HexCell) → void`
Fast-path color update. Sets `.color` on `Polygon2D` backgrounds or `.modulate` on
`Sprite2D` / `AnimatedSprite2D` without recreating the `Bg` node.

Use instead of `update_cell_visual` when only the color changes (e.g. ownership indicators,
gem types, state highlights) and node reallocation would be wasteful.

```gdscript
# After updating cell.tag:
cell.tag = new_gem_type
renderer.refresh_cell_color(hex_container, coord, cell)
```

#### `update_los_highlight(hex_container: Node2D, visible_coords: Array[Vector2i], blocked_coords: Array[Vector2i] = [], visible_color: Color = Color(0.3, 0.7, 1.0, 0.25), blocked_color: Color = Color(1.0, 0.2, 0.2, 0.15)) → void`
Shows the `Highlight` overlay with different colors for visible and blocked LOS hexes.
Uses the same `Highlight` node as `update_reachable_highlight` — call one or the other, not both.

```gdscript
var visible := grid.get_visible_cells(origin, 5, blocking_terrains)
var blocked := grid.get_blocked_cells(origin, 5, blocking_terrains)
renderer.update_los_highlight(hex_container, visible, blocked)
```

### Batch rendering (for large maps) — `HexBatchRenderer`

`HexBatchRenderer` is a separate class for batch rendering. It uses `_draw()`
directly instead of creating one `Area2D` per hex, avoiding scene tree overhead
and enabling viewport AABB culling — suitable for maps of 200×200+ hexes (40K+
cells).

**Limitations:** renders terrain color + fog + highlights only. No icons,
textures, animations, custom tile visuals, or overlays — those are exclusive to
node-per-hex `HexRenderer`. Click detection uses `HexGrid.pixel_to_offset()`
math — no `Area2D` nodes needed.

**Recommended pattern for large maps**: combine `HexBatchRenderer.render()` for
terrain with a separate `Node2D` layer of game entities (units, buildings)
positioned via `HexGrid.offset_to_pixel`, plus `FogTextureRenderer` for the fog
overlay. Entities decide their own visibility by reading
`HexCell.get_fog_state(player_id)`.

```gdscript
var batch := HexBatchRenderer.new(HexPalette.new(), HexGrid.HEX_SIZE)
batch.render(hex_container, grid)
batch.update_fog(hex_container, grid, 0)

# In _process, track camera movement to trigger viewport redraws:
batch.track_viewport(hex_container)
```

#### `_init(palette: HexPalette, hex_size: float = HexGrid.HEX_SIZE) → void`
Constructs a batch renderer with the given palette and hex size.

#### `render(container: Node2D, grid: HexGrid) → void`
Clears `container` and creates three `BatchHexLayer` children: terrain, fog, and highlight.
Call once during initialization.

#### `update_fog(container: Node2D, grid: HexGrid, player_id: int = 0) → void`
Marks the fog layer as dirty. Redraws on the next frame with fog state for `player_id`.

#### `update_reachable_highlight(container: Node2D, grid: HexGrid, reachable: Dictionary, highlighted_hexes: Dictionary) → void`
Marks the highlight layer as dirty with reachable hex data.

#### `update_los_highlight(container: Node2D, visible_coords: Array[Vector2i], blocked_coords: Array[Vector2i] = []) → void`
Marks the highlight layer as dirty with LOS data. Replaces reachable highlight.

#### `update_cell(container: Node2D, grid: HexGrid, coord: Vector2i) → void`
Marks the terrain layer as dirty after a cell changes. Redraws all visible terrain
(the layer does not track individual cells).

#### `track_viewport(container: Node2D) → void`
Checks camera movement on all three batch layers. If the camera moved more than
1.5 hex sizes since the last draw, triggers a redraw. Call each frame in `_process`.

---

## MapCamera

```
class_name MapCamera
extends RefCounted
```

Controls a Godot `Camera2D` with follow mode, right-click drag pan, scroll-wheel
zoom, and mouse edge-scroll.

### Constructor

```gdscript
MapCamera.new(
    p_camera:   Camera2D,
    p_viewport: Viewport
) -> MapCamera
```

`p_viewport` is typically `get_viewport()` called from the scene script.

### Constants

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `LERP_SPEED` | `float` | `8.0` | Follow smoothing speed |
| `EDGE_MARGIN` | `float` | `30.0` | Pixels from screen edge that trigger edge-scroll |
| `EDGE_SPEED` | `float` | `500.0` | Edge-scroll speed in pixels/second |
| `ZOOM_MIN` | `float` | `0.6` | Minimum zoom level |
| `ZOOM_MAX` | `float` | `3.0` | Maximum zoom level |
| `ZOOM_STEP` | `float` | `0.15` | Zoom increment per scroll tick |

### Properties

| Name | Type | Description |
|------|------|-------------|
| `camera` | `Camera2D` | The Godot Camera2D being controlled |
| `viewport` | `Viewport` | The viewport used for edge detection and coordinate conversion |
| `follow_target` | `bool` | `true` = camera follows target position; `false` = free-look |

### Methods

#### `process(delta: float, target_position: Vector2) → void`
Call every frame from `_process`. When `follow_target` is `true`, lerps the camera
toward `target_position`. When `false`, applies edge-scroll if the mouse is near
a screen edge.

```gdscript
func _process(delta: float) -> void:
    var target := HexGrid.offset_to_pixel(selected_unit_coord)
    cam_ctrl.process(delta, target)
```

#### `handle_input(event: InputEvent) → void`
Call from `_unhandled_input` or `_input`. Handles:
- **Right mouse button pressed** — starts drag, disables follow mode
- **Right mouse button released** — ends drag
- **Mouse motion** — pans camera while dragging
- **Scroll up/down** — adjusts `camera.zoom`
- **Space key** — re-enables follow mode

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    cam_ctrl.handle_input(event)
```

#### `screen_to_world(screen_pixel: Vector2) → Vector2`
Converts a screen-space pixel (e.g. `event.position` from a mouse click) to
world-space coordinates, accounting for camera position and zoom.

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    cam_ctrl.handle_input(event)
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var world_pos := cam_ctrl.screen_to_world(event.position)
        var coord := HexGrid.pixel_to_offset(world_pos)
        if grid.is_valid(coord):
            _on_hex_clicked(coord)
```

---

## Signals

| Class | Signal | Payload |
|-------|--------|---------|
| `HexRenderer` | `cell_pressed` | `(coord: Vector2i, event: InputEvent)` |
| `HexRenderer` | `cell_released` | `(coord: Vector2i, event: InputEvent)` |
| `FogOfWar` | `fog_changed` | `(player_id: int, coord: Vector2i, old_state: int, new_state: int)` |

Other signals (`moved_to`, `player_turn_started`, etc.) belong to Pro modules;
see `pro_api_reference.md`.

---

## BatchHexLayer

```
class_name BatchHexLayer
extends Node2D
```

A single rendering layer for batch mode. Uses `_draw()` to render hexes directly
without creating individual `Area2D` nodes. Performs viewport AABB culling to
draw only visible hexes.

Created automatically by `HexBatchRenderer.render()` — you rarely instantiate
this class directly.

### Constructor

```gdscript
BatchHexLayer.new(
    grid:     HexGrid,
    hex_size: float,
    draw_fn:  Callable    # (layer, grid, hex_size, min_coord, max_coord) → void
)
```

`draw_fn` is called during `_draw()` with the visible coordinate range.
The layer calls `draw_colored_polygon()` and `draw_polyline()` on itself.

### Methods

#### `mark_dirty() → void`
Sets the dirty flag and calls `queue_redraw()`. The layer redraws on the next
frame only when dirty.

#### `check_viewport() → void`
Compares the current camera position with the last drawn position. If the camera
moved more than 1.5 hex sizes, calls `mark_dirty()`. Call each frame in `_process`
(via `HexBatchRenderer.track_viewport()`).

### How viewport culling works

1. `_draw()` reads `get_viewport().canvas_transform` to get the visible rect
2. Converts screen bounds to hex coordinates (min/max)
3. Clamps to grid boundaries
4. Passes the visible range to `draw_fn`
5. Only hexes within the visible range are drawn

---

## Error conventions

- Methods that return a node or object return `null` on failure (e.g. `get_cell` for
  an out-of-bounds coordinate).
- Methods that return an `Array` return an empty array on failure.
- `PathFinder` methods return an empty array if no path exists.
- Invalid operations are reported via `push_error` or `push_warning` and do not throw.
