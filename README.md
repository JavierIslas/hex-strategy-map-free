# Hex Strategy Map

Hexagonal grid toolkit for Godot 4.6+ with coordinates, pathfinding, fog of war, rendering, and camera controls. The foundation for any hex-based strategy game.

## Features

- **HexGrid** — Offset and cube coordinates, neighbors, distances, terrain costs, edge costs, LOS
- **HexCell** — Cell model with terrain, tag, metadata, per-player fog state, locations
- **PathFinder** — Dijkstra and A* pathfinding, reachable hex calculation (O((V+E) log V))
- **FogOfWar** — 3-state per-player fog (Hidden/Explored/Visible), LOS-based reveal
- **HexRenderer** — Visual rendering with injectable terrain colors, fog overlays, highlights, edges. Batch mode for large maps
- **MapCamera** — Follow target, drag, zoom, edge-scroll

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

# Pathfinding (Dijkstra and A*)
var reachable := PathFinder.find_reachable(grid, Vector2i(2, 2), 4.0)
var path := PathFinder.find_path(grid, Vector2i(2, 2), Vector2i(8, 8))
var astar_path := PathFinder.find_path_astar(Vector2i(2, 2), Vector2i(8, 8), grid)

# Fog of war (3 states: HIDDEN, EXPLORED, VISIBLE) per player
var fog := FogOfWar.new(grid)
fog.reveal_around(0, Vector2i(2, 2), 3)
renderer.update_fog(hex_container, grid, 0)

# Batch mode for large maps (200x200+)
renderer.render_batch(hex_container, grid)

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
| `FogOfWar` | `RefCounted` | 3-state per-player fog with LOS reveal |
| `HexRenderer` | `RefCounted` | Visual rendering, fog overlays, highlights, edges, batch mode |
| `BatchHexLayer` | `Node2D` | Batch rendering layer with viewport AABB culling |
| `MapCamera` | `RefCounted` | Camera follow, drag, zoom, edge-scroll |

## Examples

| Mini | Description |
|------|-------------|
| `grid_only/` | HexGrid + HexRenderer basics |
| `pathfinding/` | PathFinder — Dijkstra vs A* vs Flow Field comparison |
| `texture_tiles/` | HexRenderer with texture/atlas/animated sprite support |

## Testing

269 automated tests (gdUnit4):

HexGrid(92) · HexCell(24) · PathFinder(36) · HexRenderer(39) · BatchHexLayer(20) · MapCamera(14) · FogOfWar(44)

## Go Pro

Need unit movement, turn management, flow fields, procedural generation, combat, save/load, or a minimap?

**[Hex Strategy Map Pro](https://dimcairion.itch.io/hex-strategy-map)** adds:

- **FlowField** — Flow field for efficient group movement (one computation serves N units)
- **MapToken** — Unit movement with configurable points, path following, signals
- **TurnManager** — Turn cycle with player phases and configurable interval hooks
- **MapGenerator** — Procedural terrain, rivers, scatterable locations
- **UnitRegistry** — Unit tracking by owner, coordinate index, auto-sync, stacking
- **CombatResolver** — Pluggable combat with injectable damage, terrain bonus, flanking
- **SaveManager** — JSON-based save/load slot management
- **HexMiniMap** — Minimap rendering with fog per player and token markers
- **TiledImporter** — Import Tiled Map Editor JSON maps

Includes visual map editor (`@tool` HexMapNode) for in-editor terrain painting and full skirmish demo with 2 players, combat, city capture, fog of war, and victory conditions.

## License

MIT — use freely in commercial and non-commercial projects.
