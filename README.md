# Hex Strategy Map

Hexagonal grid toolkit for Godot 4.6+ with coordinates, pathfinding, fog of war, rendering, and camera controls. The foundation for any hex-based strategy game, tactical RPG, hex-and-counter wargame, hex crawl, or roguelike.

## Why this tier

- **Deterministic, JSON-serializable simulation.** Logic runs on coordinates and data, with no rendering or hidden randomness — suitable for play-by-email, lockstep multiplayer, headless servers, replays, and AI/ML training environments.
- **One toolkit for the hex fundamentals.** Coordinates, pathfinding (Dijkstra + A*), 3-state fog of war with LOS, rendering, batch mode for large maps, and camera — packaged together.

## Not for

- Square or isometric grids — use Godot's built-in `TileMap`.
- Free-form 3D movement on meshes — use `NavigationServer3D`.
- Real-time action games — designed around turn-based and step-based simulation.

## Logic vs rendering

The simulation layer is **render-agnostic**: `HexGrid`, `HexCell`, `PathFinder`
and `FogOfWar` operate on coordinates and data — no rendering dependency.
Drive them from a 3D scene, a headless server, or any custom renderer.

The bundled `HexRenderer`, `BatchHexLayer` and `MapCamera` are the **2D
rendering layer** (Polygon2D / Sprite2D / Node2D under Camera2D). Examples
ship as 2D scenes; replace those modules if you target 3D.

## Features

- **HexGrid** — Offset and cube coordinates, neighbors, distances, terrain costs, edge costs, LOS
- **HexCell** — Cell model with terrain, tag, metadata, per-player fog state, locations
- **PathFinder** — Dijkstra and A* pathfinding, reachable hex calculation (O((V+E) log V))
- **FogOfWar** — 3-state per-player fog (Hidden/Explored/Visible), LOS-based reveal
- **HexRenderer** — Node-per-hex rendering with `HexPalette` for colors, fog overlays, highlights, edges
- **HexBatchRenderer** — Standalone batch renderer for large maps (terrain + fog + highlights with viewport culling)
- **HexPalette** — Shared `Resource` with terrain/fog colors and injectable `color_fn`
- **MapCamera** — Follow target, drag, zoom, edge-scroll

## Installation

1. Copy `addons/hex_strategy_map/` into your project's `addons/` folder
2. Enable the plugin in Project → Project Settings → Plugins

## Quick Start

```gdscript
# Create a hex grid
var grid := HexGrid.new(12, 12)
grid.generate_cells()

# Render hexes (node-per-hex)
var palette := HexPalette.new()
var renderer := HexRenderer.new(palette, HexGrid.HEX_SIZE)
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
var batch := HexBatchRenderer.new(HexPalette.new(), HexGrid.HEX_SIZE)
batch.render(hex_container, grid)

# Camera
var camera_ctrl := MapCamera.new(camera_node)
camera_ctrl.follow(target_node)
camera_ctrl.enable_drag()
```

## Customization

Everything is injectable via constructor parameters and callables:

- **Terrain costs**: `HexGrid.new(15, 15, custom_cost_table)`
- **Edge costs**: `HexGrid.new(15, 15, {}, 0.0, edge_cost_table)`
- **Palette**: assign `palette.terrain_colors`, `palette.fog_colors`, `palette.color_fn` and pass to the renderer
- **Renderer callables**: `HexRenderer.new(palette, hex_size, {"cell_icon_fn": fn, "texture_fn": fn, "animation_fn": fn, "tile_visual_fn": fn, "overlay_fn": fn, "fog_material": mat})`
- **Batch rendering**: `HexBatchRenderer.new(palette, hex_size)` for large maps with viewport culling

## Classes

| Class | Base | Description |
|-------|------|-------------|
| `HexGrid` | `RefCounted` | Grid, coordinates, neighbors, terrain costs, edge costs, LOS |
| `HexCell` | `RefCounted` | Cell with terrain, tag, metadata, fog state, locations |
| `PathFinder` | `RefCounted` | Dijkstra + A* pathfinding, reachable hex calculation |
| `FogOfWar` | `RefCounted` | 3-state per-player fog with LOS reveal |
| `HexRenderer` | `RefCounted` | Node-per-hex rendering, fog overlays, highlights, edges |
| `HexBatchRenderer` | `RefCounted` | Batch rendering for large maps |
| `HexPalette` | `Resource` | Shared color palette with `terrain_colors`, `fog_colors`, `color_fn` |
| `BatchHexLayer` | `Node2D` | Internal batch layer with viewport AABB culling |
| `MapCamera` | `RefCounted` | Camera follow, drag, zoom, edge-scroll |

## Examples

| Mini | Description |
|------|-------------|
| `grid_only/` | HexGrid + HexRenderer basics |
| `pathfinding/` | PathFinder — Dijkstra vs A* vs Flow Field comparison |
| `texture_tiles/` | HexRenderer with texture/atlas/animated sprite support |

## Benchmarks

Microbenchmarks for the free-tier modules live in `benchmarks/`. Run with `godot --headless --script benchmarks/run_benchmarks.gd`. See [`docs/benchmarks.md`](docs/benchmarks.md) for reference results and a guide on picking between A*, cached Dijkstra and FlowField.

## Testing

~360 automated tests (gdUnit4), free-tier slice:

HexGrid(98) · HexCell(29) · PathFinder(36) · HexRenderer(77) · HexBatchRenderer(22) · HexPalette(17) · BatchHexLayer(12) · MapCamera(14) · FogOfWar(49)

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
