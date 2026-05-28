# Getting Started — Hex Strategy Map (Free)

This guide walks you through the core classes included in the free tier:
**HexGrid**, **HexCell**, **PathFinder**, **HexRenderer**,
**BatchHexLayer**, **MapCamera**, and **FogOfWar**.

By the end you will have a rendered hex map with pathfinding, fog of war, and a working camera.

> **2D rendering, render-agnostic logic.** This guide uses the bundled
> `HexRenderer` and `BatchHexLayer`, which draw with `Polygon2D` / `Sprite2D`
> under a `Node2D` and a `Camera2D`. The simulation classes (`HexGrid`,
> `HexCell`, `PathFinder`, `FogOfWar`) have **no rendering dependency** — if
> you target 3D or a custom renderer, ignore the renderer/camera sections and
> call the logic API directly from your own nodes.

---

## Installation

1. Copy the `addons/hex_strategy_map/` folder into your project's `addons/` directory.
2. Open **Project → Project Settings → Plugins** and enable **Hex Strategy Map**.

No additional dependencies required.

---

## Scene setup

Create a `Node2D` scene with this structure:

```
MyMapScene (Node2D)  ← attach your script here
├── Camera2D
├── HexContainer (Node2D)   ← hex visuals go here
└── EdgeContainer (Node2D)  ← edge visuals go here
```

---

## Step 1 — Create and populate the grid

`HexGrid` is the data model. It holds all cells and knows nothing about visuals.

```gdscript
extends Node2D

var grid: HexGrid

func _ready() -> void:
    # 15 columns, 10 rows, default terrain costs, hex radius 32 px
    grid = HexGrid.new(15, 10)
    grid.generate_cells()   # fills grid.cells with HexCell objects
```

Every cell starts as `HexGrid.Terrain.PLAINS`. You can change individual cells:

```gdscript
grid.set_terrain(Vector2i(0, 0), HexGrid.Terrain.WATER)
grid.set_terrain(Vector2i(7, 5), HexGrid.Terrain.MOUNTAIN)
```

Or paint a whole region in a loop:

```gdscript
for y in grid.height:
    for x in range(0, 3):
        grid.set_terrain(Vector2i(x, y), HexGrid.Terrain.WATER)
```

---

## Step 2 — Render the grid

`HexRenderer` turns cell data into `Area2D` nodes inside your `HexContainer`.

```gdscript
@onready var hex_container: Node2D = $HexContainer
@onready var edge_container: Node2D = $EdgeContainer

var renderer: HexRenderer

func _ready() -> void:
    grid = HexGrid.new(15, 10)
    grid.generate_cells()

    renderer = HexRenderer.new()   # uses default terrain colors

    for coord in grid.cells:
        var cell: HexCell = grid.cells[coord]
        var pixel: Vector2 = HexGrid.offset_to_pixel(coord)
        renderer.create_hex_visual(hex_container, coord, pixel, cell)

    renderer.render_edges(edge_container, grid)
```

Each hex becomes an `Area2D` named `Hex_X_Y` containing:
- `Bg` — terrain background (Polygon2D, Sprite2D, or custom node)
- `Border` — Line2D outline
- `Highlight` — reachable/selection overlay (hidden by default)
- `Fog` — fog of war overlay (hidden by default in free tier)
- `CellIcon` — optional label (via `cell_icon_fn`)

### Texture tiles from the Inspector

For a no-code approach, assign a `TerrainVisualSet` to `HexMapNode.terrain_visuals`
in the Inspector. Drag textures per terrain type and the editor preview shows them
automatically. At runtime, use `hex_map_node.make_tile_visual_fn()` to get a Callable
for `HexRenderer`. See the [Customization Guide](customization.md) for details.

### Large maps (200x200+)

For maps with 40K+ hexes, the node-per-hex approach creates too many scene tree
nodes. Use `HexBatchRenderer` instead:

```gdscript
# Replaces the for loop above — no Area2D nodes, just _draw()
var batch := HexBatchRenderer.new(HexPalette.new(), HexGrid.HEX_SIZE)
batch.render(hex_container, grid)

# In _process, track camera to trigger viewport redraws:
batch.track_viewport(hex_container)
```

`HexBatchRenderer` renders terrain + fog + highlights with viewport AABB culling.
It does not support icons, textures, or custom tile visuals. Click detection still
works via `HexGrid.pixel_to_offset()`.

---

## Step 3 — Custom terrain colors

Pass a `Dictionary[int, Color]` to override the defaults:

```gdscript
var my_colors := {
    HexGrid.Terrain.ROAD:     Color(0.5, 0.4, 0.3),
    HexGrid.Terrain.PLAINS:   Color(0.3, 0.6, 0.2),
    HexGrid.Terrain.FOREST:   Color(0.1, 0.3, 0.1),
    HexGrid.Terrain.MOUNTAIN: Color(0.5, 0.5, 0.5),
    HexGrid.Terrain.WATER:    Color(0.1, 0.3, 0.7),
}
renderer = HexRenderer.new(my_colors)
```

---

## Step 4 — Custom terrain types

The five built-in terrain values (`ROAD`, `PLAINS`, etc.) are just integers. You can
define as many terrain types as you need using plain constants:

```gdscript
const DESERT  := 10
const SWAMP   := 11
const GLACIER := 12

var cost_table := {
    HexGrid.Terrain.PLAINS: 1.5,
    HexGrid.Terrain.FOREST: 2.0,
    DESERT:  2.5,
    SWAMP:   3.5,
    GLACIER: 4.0,
    HexGrid.Terrain.WATER: -1.0,   # -1 = impassable
}

var color_table := {
    HexGrid.Terrain.PLAINS: Color(0.3, 0.6, 0.2),
    DESERT:  Color(0.8, 0.7, 0.3),
    SWAMP:   Color(0.2, 0.4, 0.2),
    GLACIER: Color(0.8, 0.9, 1.0),
    HexGrid.Terrain.WATER: Color(0.1, 0.3, 0.7),
}

grid = HexGrid.new(15, 10, cost_table)
renderer = HexRenderer.new(color_table)
```

Set custom terrain values on cells the same way:

```gdscript
grid.set_terrain(Vector2i(5, 3), DESERT)
```

---

## Step 5 — Pathfinding

`PathFinder` has four static methods. All take a `HexGrid` and return paths as
`Array[Vector2i]`.

### Find reachable hexes (movement range)

```gdscript
var origin := Vector2i(2, 2)
var movement_points := 5.0

# Returns Dictionary[Vector2i, float] — coord → accumulated cost
var reachable := PathFinder.find_reachable(origin, movement_points, grid)

# Highlight the reachable area
var highlighted: Dictionary = {}
renderer.update_reachable_highlight(hex_container, grid, reachable, highlighted)
```

### Find shortest path (within movement range)

```gdscript
var path := PathFinder.find_path(origin, Vector2i(5, 4), reachable, grid)
# path: [Vector2i(3,2), Vector2i(4,3), Vector2i(5,4)]
# Empty if destination is not in reachable
```

### Find path without movement limit (Dijkstra)

```gdscript
var path := PathFinder.find_path_unlimited(origin, Vector2i(12, 8), grid)
```

### Find path with A\* (faster on large maps)

```gdscript
var path := PathFinder.find_path_astar(origin, Vector2i(12, 8), grid)
# Optimal when minimum terrain cost >= 1.0
```

All methods return an empty array if no path exists.

---

## Step 6 — Fog of war

`FogOfWar` tracks per-player visibility in three states: Hidden, Explored, Visible.
It operates on `HexCell.explored_by` and `HexCell.visible_by`.

```gdscript
var fog := FogOfWar.new(grid)

# Reveal a 3-hex radius around a starting position
fog.reveal_around(0, Vector2i(5, 5), 3)

# Apply fog visuals after rendering the grid
renderer.update_fog(hex_container, grid, 0)   # player_id = 0
```

### Fog states

| State | Meaning | Visual |
|-------|---------|--------|
| `HIDDEN` (0) | Cell never explored | Full fog overlay |
| `EXPLORED` (1) | Cell visited but not currently visible | Semi-transparent fog |
| `VISIBLE` (2) | Cell currently in sight range | No fog overlay |

### Moving the vision source

Call `update_visibility` each time a unit moves. It clears the previous visible set
and re-reveals from the new position.

```gdscript
fog.update_visibility(0, new_coord, 3)
renderer.update_fog(hex_container, grid, 0)
```

### Custom visibility radius

Inject a callable to define a custom radius formula (e.g. based on unit level):

```gdscript
var fog := FogOfWar.new(grid, func(level: int) -> int:
    return 2 + level / 3
)
```

### Reacting to fog changes

Connect to `fog_changed` to respond when a cell's state transitions:

```gdscript
fog.fog_changed.connect(func(player_id, coord, old_state, new_state):
    if new_state == FogOfWar.FogState.VISIBLE:
        print("Cell %s revealed for player %d" % [coord, player_id])
)
```

---

## Step 7 — Edges

Edges model connections between adjacent hexes: rivers slow movement, roads speed
it up, walls block passage entirely.

```gdscript
# Add a river between two adjacent hexes (doubles movement cost by default)
grid.set_edge(Vector2i(4, 3), Vector2i(5, 3), HexGrid.EdgeType.RIVER)

# Add a road (reduces movement cost by 0.5)
grid.set_edge(Vector2i(1, 1), Vector2i(2, 1), HexGrid.EdgeType.ROAD)

# Add a wall (impassable, cost = -1)
grid.set_edge(Vector2i(7, 5), Vector2i(7, 6), HexGrid.EdgeType.WALL)

# Custom edge with explicit cost
grid.set_edge(Vector2i(3, 2), Vector2i(3, 3), HexGrid.EdgeType.CUSTOM, {"cost": 1.5})

# Render edge visuals — default mode (CENTERS) draws lines that cross both hexes,
# good for roads or navigable rivers.
renderer.render_edges(edge_container, grid)

# For walls/barriers, use SHARED_BORDER — segments sit on the shared border between cells.
renderer.render_edges(edge_container, grid, Color(0.85, 0.30, 0.30), 4.0,
    HexRenderer.EdgeRenderMode.SHARED_BORDER)

# Query edges
var edge: Dictionary = grid.get_edge(Vector2i(4, 3), Vector2i(5, 3))
# {"type": HexGrid.EdgeType.RIVER, "cost": 2.0}
```

PathFinder automatically accounts for edge costs.

---

## Step 8 — Line of sight

```gdscript
# Returns true if there is a clear line from 'from' to 'to'
var can_see := grid.get_line_of_sight(Vector2i(2, 2), Vector2i(8, 6))

# Specify which terrains block LOS (e.g. mountains and forests)
var blocking := [HexGrid.Terrain.MOUNTAIN, HexGrid.Terrain.FOREST]
var can_see_blocked := grid.get_line_of_sight(Vector2i(2, 2), Vector2i(8, 6), blocking)
```

`get_line_of_sight` uses cube coordinate interpolation (Bresenham-style). Source and
destination cells are never considered blocking regardless of terrain.

---

## Step 9 — Camera

`MapCamera` wraps a Godot `Camera2D` and adds follow, drag, zoom, and edge-scroll.

```gdscript
@onready var camera: Camera2D = $Camera2D
var cam_ctrl: MapCamera

func _ready() -> void:
    cam_ctrl = MapCamera.new(camera, get_viewport())

func _process(delta: float) -> void:
    # Pass the world position you want the camera to follow
    var target_pos: Vector2 = HexGrid.offset_to_pixel(Vector2i(7, 5))
    cam_ctrl.process(delta, target_pos)

func _unhandled_input(event: InputEvent) -> void:
    cam_ctrl.handle_input(event)
```

Default controls:
- **Right-click drag** — pan the map
- **Scroll wheel** — zoom in/out
- **Space** — re-enable follow mode after dragging

To convert a screen click to a hex coordinate:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    cam_ctrl.handle_input(event)
    if event is InputEventMouseButton and event.pressed:
        var world_pos := cam_ctrl.screen_to_world(event.position)
        var coord := HexGrid.pixel_to_offset(world_pos)
        if grid.is_valid(coord):
            print("Clicked hex: ", coord)
```

Alternatively, connect to `renderer.cell_pressed` — no coordinate math needed and
touch input is handled automatically:

```gdscript
renderer.cell_pressed.connect(func(coord: Vector2i, event: InputEvent):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        print("Clicked hex: ", coord)
)
```

This signal is only available in node-per-hex mode (not batch).

---

## Coordinate reference

The plugin uses **offset coordinates (odd-r, pointy-top)** for all public APIs.
Internally, cube coordinates are used for distance and neighbor calculations.

```gdscript
# Offset ↔ pixel
var pixel: Vector2 = HexGrid.offset_to_pixel(Vector2i(3, 2))
var coord: Vector2i = HexGrid.pixel_to_offset(pixel)

# Offset ↔ cube
var cube: Vector3i = HexGrid.offset_to_cube(Vector2i(3, 2))

# Distance between two hexes
var d: int = HexGrid.distance(Vector2i(0, 0), Vector2i(5, 3))

# All 6 neighbors
var neighbors: Array[Vector2i] = HexGrid.get_neighbors(Vector2i(3, 2))

# Ring of hexes at distance N
var ring: Array[Vector2i] = grid.get_ring(Vector2i(5, 5), 3)
```

---

## Next steps

- See `examples/minis/grid_only/` for a minimal rendered grid.
- See `examples/minis/pathfinding/` for an interactive path visualization.
- See `examples/minis/texture_tiles/` for texture and animated sprite support.
- See `examples/explorer_map/` for a complete map with fog of war, camera, and pathfinding.
- For unit movement, turns, combat, minimap, flow fields, save/load, and procedural generation → **Hex Strategy Map Pro**.
