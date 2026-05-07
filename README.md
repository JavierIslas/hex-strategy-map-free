# Hex Strategy Map

Hexagonal grid toolkit for Godot 4.6+ with coordinates, pathfinding, flow fields, rendering, camera controls, and save management. The foundation for any hex-based game.

## Features

- **HexGrid** — Offset and cube coordinates, neighbors, distances, terrain costs, edge costs, LOS
- **HexCell** — Cell model with terrain, tag, metadata, per-player fog state, locations
- **PathFinder** — Dijkstra and A* pathfinding, reachable hex calculation (O((V+E) log V))
- **FlowField** — Flow field for efficient group movement (one computation serves N units)
- **HexRenderer** — Visual rendering with injectable terrain colors, highlights, edges. Batch mode for large maps
- **MapCamera** — Follow target, drag, zoom, edge-scroll
- **SaveManager** — JSON-based save/load slot management

## Installation

1. Copy `addons/hex_strategy_map/` into your project's `addons/` folder
2. Enable the plugin in Project → Project Settings → Plugins

## Quick Start

```gdscript
# Create a hex grid
var grid := HexGrid.new(12, 12)
grid.generate_cells()

# Render hexes
var renderer := HexRenderer.new(HexRenderer.DEFAULT_TERRAIN_COLORS, func(_cell): return "")
for coord in grid.cells:
    renderer.create_hex_visual(hex_container, coord, HexGrid.offset_to_pixel(coord), grid.cells[coord])
renderer.render_edges(edge_container, grid)

# Pathfinding (Dijkstra, A*, and flow fields)
var reachable := PathFinder.find_reachable(grid, Vector2i(2, 2), 4.0)
var path := PathFinder.find_path(grid, Vector2i(2, 2), Vector2i(8, 8))
var astar_path := PathFinder.find_path_astar(Vector2i(2, 2), Vector2i(8, 8), grid)

var field := FlowField.build(grid, Vector2i(8, 8))
var unit_path := FlowField.trace_path(field, Vector2i(2, 2))

# Batch mode for large maps (200x200+)
renderer.render_batch(hex_container, grid)

# Save / Load
var save_mgr := SaveManager.new()
save_mgr.save(0, grid.serialize())
var data := save_mgr.load(0)

# Camera
var camera_ctrl := MapCamera.new(camera_node)
camera_ctrl.follow(target_node)
camera_ctrl.enable_drag()
```

## Customization

Everything is injectable via constructor parameters and callables:

- **Terrain costs**: `HexGrid.new(15, 15, custom_cost_table)`
- **Edge costs**: `HexGrid.new(15, 15, {}, 0.0, edge_cost_table)`
- **Terrain colors**: `HexRenderer.new(my_colors, my_icon_callback)`
- **Textures**: `HexRenderer.new(colors, icon_fn, fog_colors, texture_fn)`
- **Animations**: `HexRenderer.new(colors, icon_fn, fog_colors, null, animation_fn)`
- **Batch rendering**: `renderer.render_batch(container, grid)` for large maps with viewport culling

## Classes

| Class | Base | Description |
|-------|------|-------------|
| `HexGrid` | `RefCounted` | Grid, coordinates, neighbors, terrain costs, edge costs, LOS |
| `HexCell` | `RefCounted` | Cell with terrain, tag, metadata, fog state, locations |
| `PathFinder` | `RefCounted` | Dijkstra + A* pathfinding, reachable hex calculation |
| `FlowField` | `RefCounted` | Flow field for group movement: build + trace_path |
| `HexRenderer` | `RefCounted` | Visual rendering, highlights, edges, batch mode |
| `MapCamera` | `RefCounted` | Camera follow, drag, zoom, edge-scroll |
| `SaveManager` | `RefCounted` | JSON-based save/load slot management |

## Examples

| Mini | Description |
|------|-------------|
| `grid_only/` | HexGrid + HexRenderer basics |
| `pathfinding/` | PathFinder — Dijkstra vs A* vs Flow Field comparison |
| `texture_tiles/` | HexRenderer with texture/atlas/animated sprite support |

## Testing

257 automated tests (gdUnit4):

HexGrid(92) · HexCell(24) · PathFinder(36) · FlowField(15) · HexRenderer(39) · BatchHexLayer(20) · MapCamera(14) · SaveManager(17)

## Go Pro

Need fog of war, unit movement, turn management, procedural generation, combat, or a minimap?

**[Hex Strategy Map Pro](https://godotfoundry.com)** adds:

- **FogOfWar** — 3-state fog per player (Hidden/Explored/Visible) with LOS-based reveal
- **MapToken** — Unit movement with configurable points, path following, signals
- **TurnManager** — Turn cycle with player phases and configurable interval hooks
- **MapGenerator** — Procedural terrain, rivers, scatterable locations
- **UnitRegistry** — Unit tracking by owner, coordinate index, auto-sync, stacking
- **CombatResolver** — Pluggable combat with injectable damage, terrain bonus, flanking
- **HexMiniMap** — Minimap rendering with fog per player and token markers
- **TiledImporter** — Import Tiled Map Editor JSON maps

Includes visual map editor (`@tool` HexMapNode) for in-editor terrain painting and full skirmish demo with 2 players, combat, city capture, fog of war, and victory conditions.

## License

MIT — use freely in commercial and non-commercial projects.
