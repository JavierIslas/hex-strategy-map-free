# Customization Guide — Hex Strategy Map

The plugin is designed around one principle: **inject behavior, don't subclass**.
Every game-specific rule is passed as a `Callable` or a `Dictionary` at construction
time. The plugin provides sensible defaults; you replace only what your game needs.

This guide covers all customization points in one place.

---

## Custom terrain types

The five built-in terrain values (`ROAD`, `PLAINS`, `FOREST`, `MOUNTAIN`, `WATER`)
are just integers. You can define as many terrain types as your game needs.

```gdscript
# Define your own terrain constants (any int not used by HexGrid.Terrain)
const DESERT  := 10
const SWAMP   := 11
const VOLCANO := 12
const GLACIER := 13
const TUNDRA  := 14
```

Register them with a cost table when creating the grid:

```gdscript
var cost_table := {
    HexGrid.Terrain.ROAD:     1.0,
    HexGrid.Terrain.PLAINS:   1.5,
    HexGrid.Terrain.FOREST:   2.0,
    HexGrid.Terrain.MOUNTAIN: 3.0,
    HexGrid.Terrain.WATER:   -1.0,   # -1 = impassable
    DESERT:   2.5,
    SWAMP:    3.5,
    VOLCANO: -1.0,   # impassable
    GLACIER:  4.0,
    TUNDRA:   2.0,
}

var grid := HexGrid.new(20, 16, cost_table)
```

Set terrain on cells as usual:

```gdscript
grid.set_terrain(Vector2i(5, 3), DESERT)
grid.set_terrain(Vector2i(9, 7), SWAMP)
```

---

## Custom terrain colors

Pass a `Dictionary[int, Color]` to `HexRenderer`. You only need to include the
terrains you actually use — unknown terrain values render as `Color.GRAY`.

```gdscript
var colors := {
    HexGrid.Terrain.ROAD:     Color(0.55, 0.45, 0.30),
    HexGrid.Terrain.PLAINS:   Color(0.35, 0.60, 0.25),
    HexGrid.Terrain.FOREST:   Color(0.10, 0.28, 0.12),
    HexGrid.Terrain.MOUNTAIN: Color(0.50, 0.48, 0.44),
    HexGrid.Terrain.WATER:    Color(0.12, 0.25, 0.55),
    DESERT:   Color(0.85, 0.75, 0.40),
    SWAMP:    Color(0.25, 0.40, 0.22),
    GLACIER:  Color(0.82, 0.90, 1.00),
    TUNDRA:   Color(0.60, 0.68, 0.58),
}

var palette := HexPalette.new()
palette.terrain_colors = colors
var renderer := HexRenderer.new(palette, HexGrid.HEX_SIZE)
```

You can also use `HexPalette.DEFAULT_TERRAIN_COLORS` as a starting point:

```gdscript
var palette := HexPalette.new()
palette.terrain_colors = HexPalette.DEFAULT_TERRAIN_COLORS.duplicate()
palette.terrain_colors[DESERT] = Color(0.85, 0.75, 0.40)
var renderer := HexRenderer.new(palette, HexGrid.HEX_SIZE)
```

---

## Custom edge costs

Edges modify the movement cost of crossing from one hex to an adjacent one.

```gdscript
var edge_cost_table := {
    HexGrid.EdgeType.RIVER: 2.0,    # crossing river costs 2 extra
    HexGrid.EdgeType.ROAD:  -0.5,   # road reduces cost by 0.5
    HexGrid.EdgeType.WALL:  -1.0,   # wall makes crossing impassable
}

var grid := HexGrid.new(20, 16, cost_table, 0.0, edge_cost_table)
```

Add edges to specific hex pairs:

```gdscript
# River runs between two hexes
grid.set_edge(Vector2i(4, 3), Vector2i(5, 3), HexGrid.EdgeType.RIVER)

# Road speeds travel
grid.set_edge(Vector2i(1, 0), Vector2i(2, 0), HexGrid.EdgeType.ROAD)

# Wall blocks a mountain pass
grid.set_edge(Vector2i(8, 5), Vector2i(8, 6), HexGrid.EdgeType.WALL)

# Custom edge with explicit cost (EdgeType.CUSTOM + "cost" key)
grid.set_edge(Vector2i(3, 2), Vector2i(3, 3), HexGrid.EdgeType.CUSTOM, {"cost": 1.5})
```

PathFinder accounts for edge costs automatically.

---

## Custom movement formula (MapToken)

By default, every token has 6.0 movement points regardless of level. Inject a
`movement_fn` to make points depend on level, type, equipment, or any game rule.

```gdscript
# Signature: (level: int) → float
var movement_fn := func(level: int) -> float:
    return 4.0 + level * 0.5   # level 1 → 4.5, level 10 → 9.0

token.setup(start_coord, grid, movement_fn)
```

Different unit types can use different formulas:

```gdscript
func _movement_for(unit_type: String) -> Callable:
    match unit_type:
        "cavalry": return func(_lvl): return 9.0
        "archer":  return func(_lvl): return 5.0
        "mage":    return func(lvl):  return 3.0 + lvl * 0.3
        _:         return func(_lvl): return 6.0

token.unit_type = "cavalry"
token.setup(coord, grid, _movement_for(token.unit_type))
```

`reset_movement()` re-evaluates the formula each turn, so permanent level changes
are picked up automatically at the start of the next turn.

---

## Custom visibility formula (FogOfWar)

The default formula gives `min(1 + (level-1)/2, 3)` — range 1 at level 1, capping
at 3 by level 5. Replace it with any function of unit level.

```gdscript
# Signature: (unit_level: int) → int
var visibility_fn := func(level: int) -> int:
    return 2 + level / 4   # more gradual growth

var fog := FogOfWar.new(grid, visibility_fn)
```

For position-based or type-based visibility, use `update_visibility_multi` with a
radius callable instead:

```gdscript
fog.update_visibility_multi(
    player_id,
    all_unit_positions,
    func(pos: Vector2i) -> int:
        var unit := registry.get_unit_at(pos)
        if unit == null:
            return 2
        match unit.unit_type:
            "scout":    return 5
            "fortress": return 4
            _:          return 2
)
```

---

## Terrain visuals from the inspector (TerrainVisualSet)

The easiest way to assign textures to terrain types — no code required at runtime.
Create a `TerrainVisualSet` resource in the Inspector, assign textures per terrain,
and the editor preview, palette buttons, and runtime rendering all use them automatically.

### Creating a TerrainVisualSet

1. Select a `HexMapNode` in your scene
2. In the Inspector, find **Terrain Visuals** and click **New TerrainVisualSet**
3. In the **Entries** array, add one element per terrain type
4. For each entry, set `terrain_id` to the terrain value and drag a `Texture2D`

```gdscript
# Or create programmatically:
var visuals := TerrainVisualSet.new()
var entry := TerrainVisualEntry.new()
entry.terrain_id = HexCell.Terrain.PLAINS
entry.texture = preload("res://assets/grass.png")
visuals.entries = [entry]
```

### Auto-scaling

By default, each entry has `auto_scale = true`, which scales the texture to fit the
hex based on `(hex_size * 2) / texture_height`. For pointy-top hexes with `HEX_SIZE=32`,
a 140px tall tile scales to ~0.457. Disable `auto_scale` to use the texture's native size.

The `filter_nearest` flag on `TerrainVisualSet` defaults to `true` for pixel-art assets.
Set it to `false` for high-resolution textures that need bilinear filtering.

### Runtime rendering

Use `make_tile_visual_fn()` to get a Callable ready for `HexRenderer`:

```gdscript
var grid := hex_map_node.get_grid()
var renderer := HexRenderer.new(
    {},                                          # terrain_colors (not needed with textures)
    Callable(),                                  # cell_icon_fn
    {},                                          # fog_colors
    hex_map_node.hex_size,                       # hex_size
    hex_map_node.terrain_visuals.make_tile_visual_fn(hex_map_node.hex_size)
)

for coord in grid.cells:
    renderer.create_hex_visual(hex_container, coord, HexGrid.offset_to_pixel(coord), grid.cells[coord])
```

Or use the convenience method:

```gdscript
var tile_fn := hex_map_node.make_tile_visual_fn()
var renderer := HexRenderer.new({}, Callable(), {}, hex_map_node.hex_size, tile_fn)
```

### When to use TerrainVisualSet vs. code Callables

| Scenario | TerrainVisualSet | Code Callable |
|----------|-----------------|---------------|
| One texture per terrain, configurable in Inspector | ✓ | |
| Multiple texture variants per terrain (random) | | ✓ tile_visual_fn |
| Animated textures (SpriteFrames) | | ✓ animation_fn |
| Complex node subtrees (particles, lights) | | ✓ tile_visual_fn |
| Non-programmer team members | ✓ | |

---

## Custom hex visuals (HexRenderer)

`HexRenderer` accepts several callables that control how each hex looks. They are
evaluated once per cell during `create_hex_visual()`.

### Cell icons

Draws a text label centered on the hex. Useful for debug overlays, location names,
or resource amounts.

```gdscript
# Signature: (cell: HexCell) → String; "" = no icon
var icon_fn := func(cell: HexCell) -> String:
    if cell.tag == CITY:   return "C"
    if cell.tag == MINE:   return "M"
    if cell.has_tag():     return str(cell.tag)
    return ""

var renderer := HexRenderer.new(colors, icon_fn)
```

### Texture tiles (Sprite2D)

Replace the color polygon with a `Texture2D`. Good for simple sprite-based tilesets.

```gdscript
# Preload textures
var tex := {
    HexGrid.Terrain.PLAINS:   preload("res://art/plains.png"),
    HexGrid.Terrain.FOREST:   preload("res://art/forest.png"),
    HexGrid.Terrain.MOUNTAIN: preload("res://art/mountain.png"),
    HexGrid.Terrain.WATER:    preload("res://art/water.png"),
}

# Signature: (cell: HexCell) → Texture2D; null = fall back to Polygon2D
var texture_fn := func(cell: HexCell) -> Texture2D:
    return tex.get(cell.terrain, null)

var renderer := HexRenderer.new(colors, Callable(), {}, HexGrid.HEX_SIZE, Callable(), texture_fn)
```

### Animated tiles (AnimatedSprite2D)

Use `SpriteFrames` for water shimmer, fire, or any animated terrain.

```gdscript
# Signature: (cell: HexCell) → SpriteFrames; null = fall back
var animation_fn := func(cell: HexCell) -> SpriteFrames:
    if cell.terrain == HexGrid.Terrain.WATER:
        return preload("res://art/water_frames.tres")
    return null

var renderer := HexRenderer.new(
    colors, Callable(), {}, HexGrid.HEX_SIZE,
    Callable(), Callable(), animation_fn
)
```

### Fully custom nodes (tile_visual_fn)

Build any `Node2D` subtree per cell. Takes priority over `texture_fn` and
`animation_fn`.

```gdscript
# Signature: (cell: HexCell) → Node2D; null = fall back to Polygon2D
var tile_fn := func(cell: HexCell) -> Node2D:
    if cell.terrain != VOLCANO:
        return null
    var container := Node2D.new()
    var fire := AnimatedSprite2D.new()
    fire.sprite_frames = preload("res://art/fire.tres")
    fire.play("burn")
    container.add_child(fire)
    var glow := PointLight2D.new()
    glow.color = Color(1.0, 0.3, 0.0, 0.4)
    container.add_child(glow)
    return container

var renderer := HexRenderer.new(colors, Callable(), {}, HexGrid.HEX_SIZE, tile_fn)
```

### Extra overlay nodes (overlay_fn)

Add zero or more `Node2D` children on top of the hex (e.g. resource icons, flags,
damage indicators). Called after all other children are added.

```gdscript
# Signature: (cell: HexCell) → Array[Node2D]
var overlay_fn := func(cell: HexCell) -> Array[Node2D]:
    var result: Array[Node2D] = []
    if cell.tag == GOLD_MINE:
        var icon := Sprite2D.new()
        icon.texture = preload("res://art/gold_icon.png")
        icon.position = Vector2(8, -8)
        icon.scale = Vector2(0.4, 0.4)
        result.append(icon)
    return result

var renderer := HexRenderer.new(
    colors, Callable(), {}, HexGrid.HEX_SIZE,
    Callable(), Callable(), Callable(), overlay_fn
)
```

### Custom fog colors

Override the fog overlay colors per state:

```gdscript
var fog_colors := {
    FogOfWar.FogState.HIDDEN:   Color(0.00, 0.00, 0.00, 1.00),   # full black
    FogOfWar.FogState.EXPLORED: Color(0.10, 0.10, 0.15, 0.60),   # dark blue tint
}

var renderer := HexRenderer.new(colors, Callable(), fog_colors)
```

### Dynamic color resolver (`color_fn`)

Override the hex background color based on any cell property — not just terrain.
Use this when your game colors hexes by tag, ownership, or any runtime state that is
independent of terrain.

```gdscript
# Gems game: color by tag, not terrain
var color_fn := func(cell: HexCell) -> Color:
    return GEM_COLORS.get(cell.tag, Color.DARK_GRAY)

var palette := HexPalette.new()
palette.color_fn = color_fn
var renderer := HexRenderer.new(palette, HexGrid.HEX_SIZE)
```

Color is applied during `create_hex_visual()`. To repaint a single cell at runtime
without recreating the node, use `refresh_cell_color()`:

```gdscript
cell.tag = new_gem_type
renderer.refresh_cell_color(hex_container, coord, cell)
```

Return `HexPalette.SKIP_COLOR` to fall back to `terrain_colors` for specific cells:

```gdscript
var color_fn := func(cell: HexCell) -> Color:
    if cell.metadata.get("use_terrain", false):
        return HexPalette.SKIP_COLOR   # defer to terrain_colors
    return OWNER_COLORS.get(cell.metadata.get("owner_id", -1), Color.GRAY)
```

---

## Click detection via signals

In node-per-hex mode, `HexRenderer` emits `cell_pressed` and `cell_released` when a
hex is clicked or touched. Connect to these instead of implementing `_unhandled_input`
and coordinate conversion by hand.

```gdscript
renderer.cell_pressed.connect(func(coord: Vector2i, event: InputEvent):
    if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
        return
    _on_hex_clicked(coord)
)
```

Both signals accept mouse (`InputEventMouseButton`) and touch (`InputEventScreenTouch`)
input. Filter by button or event type in the handler.

`cell_released` is useful for drag-select or hold-to-inspect interactions:

```gdscript
renderer.cell_released.connect(func(coord: Vector2i, _event: InputEvent):
    _finish_selection(coord)
)
```

**Limitation:** Signals are not emitted in batch mode. Use `HexGrid.pixel_to_offset()`
to convert mouse coordinates to hex coordinates manually when using batch rendering.

---

## Custom stacking rules (UnitRegistry)

By default, any number of units can share a hex. Use `stacking_fn` to enforce your
game's rules.

```gdscript
# Signature: (existing: Array[MapToken], incoming: MapToken) → bool
# Return true = allow, false = deny

# Only one unit per hex
var no_stack := func(existing: Array, _incoming: MapToken) -> bool:
    return existing.is_empty()

# Units may stack only with allies
var ally_stack := func(existing: Array, incoming: MapToken) -> bool:
    for unit in existing:
        if unit.owner_id != incoming.owner_id:
            return false
    return true

# Cap at 3 units per hex, allies only
var capped_stack := func(existing: Array, incoming: MapToken) -> bool:
    if existing.size() >= 3:
        return false
    for unit in existing:
        if unit.owner_id != incoming.owner_id:
            return false
    return true

var registry := UnitRegistry.new(capped_stack)
```

Call `registry.can_stack_at(coord, token)` before moving a token to check whether
the destination is available.

---

## Custom combat (CombatResolver)

All four stages of combat are independently replaceable.

### Stage 1 — Base damage

```gdscript
# Signature: (attacker: MapToken, defender: MapToken) → float
var damage_fn := func(atk: MapToken, def: MapToken) -> float:
    var attack:  float = atk.metadata.get("attack", 1.0)
    var armor:   float = def.metadata.get("armor", 0.0)
    return maxf(attack - armor * 0.5, 0.1)
```

### Stage 2 — Terrain bonus

```gdscript
# Signature: (token: MapToken, cell: HexCell) → float
var terrain_fn := func(token: MapToken, cell: HexCell) -> float:
    match cell.terrain:
        HexGrid.Terrain.MOUNTAIN: return 2.0    # defender on mountain
        HexGrid.Terrain.FOREST:   return 1.0    # forest cover
        HexGrid.Terrain.ROAD:     return -0.5   # road = no natural cover
        _:                        return 0.0
```

### Stage 3 — Flanking bonus

```gdscript
# Signature: (atk_coord: Vector2i, def_coord: Vector2i, grid: HexGrid) → float
var flanking_fn := func(atk: Vector2i, def: Vector2i, g: HexGrid) -> float:
    # Flanking if attacker is behind the defender relative to the map center
    var center := Vector2i(g.width / 2, g.height / 2)
    var flank := HexGrid.distance(def, center) < HexGrid.distance(atk, center)
    return 1.5 if flank else 0.0
```

### Stage 4 — Outcome

Replace the entire resolution if the three-stage model doesn't fit your game:

```gdscript
# Signature: (atk_power: float, def_power: float) → Dictionary
# The dictionary is passed directly to the combat_resolved signal.
var outcome_fn := func(atk_power: float, def_power: float) -> Dictionary:
    var ratio := atk_power / maxf(def_power, 0.01)
    return {
        "attacker_damage": atk_power,
        "defender_damage": def_power,
        "winner": null if ratio < 1.2 else ("attacker" if ratio >= 1.2 else "defender"),
        "decisive": ratio >= 2.0,
        "pyrrhic":  ratio >= 1.0 and ratio < 1.2,
    }
```

Compose only the stages you need:

```gdscript
var combat := CombatResolver.new(damage_fn, terrain_fn, Callable(), outcome_fn)
```

---

## Using cell metadata

`HexCell.tag` and `HexCell.metadata` store game-specific data without coupling the
plugin to your game's types.

```gdscript
# Tag: a single int (city type, region ID, resource type, etc.)
cell.tag = CITY_ID

# Metadata: arbitrary key-value pairs
cell.metadata["name"]       = "Ironhold"
cell.metadata["population"] = 4200
cell.metadata["owner_id"]   = 1
cell.metadata["fortified"]  = true
```

Query in callables:

```gdscript
var terrain_bonus_fn := func(token: MapToken, cell: HexCell) -> float:
    return 2.0 if cell.metadata.get("fortified", false) else 0.0
```

`metadata` is serialized and restored by `HexCell.serialize()` / `deserialize()`.

---

## Choosing between Callable and a custom class

| Scenario | Callable | Custom class |
|----------|----------|-------------|
| One rule that varies by unit type | ✓ match statement |  |
| Rule needs access to game state (other nodes, signals) | ✓ captures closure | ✓ inject reference |
| Rule is complex (10+ lines) | | ✓ cleaner |
| You want to swap rules at runtime (difficulty settings) | ✓ reassign callable | needs rebuild |
| You need the rule to be serializable | | ✓ encode in metadata |

For most games, closures that capture a reference to the game scene cover all cases.

---

## Importing Tiled maps (TiledImporter)

`TiledImporter` converts Tiled Map Editor JSON exports into `HexGrid` instances.
The key customization point is `terrain_fn`, which maps Tiled tile GIDs to your
terrain type integers.

### terrain_fn — tile GID to terrain

```gdscript
# Signature: (gid: int) → int
var terrain_fn := func(gid: int) -> int:
    match gid:
        1, 5:   return HexCell.Terrain.PLAINS    # two tile IDs → same terrain
        2, 6:   return HexCell.Terrain.FOREST
        3:      return HexCell.Terrain.MOUNTAIN
        4, 7:   return HexCell.Terrain.WATER
        10:     return DESERT                      # custom terrain
        _:      return HexCell.Terrain.PLAINS      # fallback
```

### Discovering tile IDs

Not sure what GIDs your map uses? Inspect before importing:

```gdscript
var json := FileAccess.open("res://maps/level.json", FileAccess.READ).get_as_text()
for gid in TiledImporter.get_unique_gids(json):
    print("Tile GID: %d" % gid)
```

### Object layers → tag and metadata

Tiled objects are converted to cell data automatically:
- Object `"tag"` property (or object type) → `cell.tag`
- All other custom properties → `cell.metadata` dictionary

```gdscript
# In Tiled, create an object with properties:
#   tag: 5
#   name: "Ironhold"
#   population: 4200
#
# After import:
var cell := grid.get_cell(Vector2i(10, 7))
print(cell.tag)               # 5
print(cell.metadata["name"])  # "Ironhold"
```

### Multiple tile layers

If the Tiled map has multiple tile layers, the last layer wins for each cell.
This lets you paint a base terrain layer and overlay details.

---

## Minimap token markers (HexMiniMap)

The minimap renders terrain as colored dots and can show unit positions via an
injectable `token_fn` callable.

### token_fn — custom marker colors

```gdscript
# Signature: (coord: Vector2i) → Color; Color.TRANSPARENT = skip
minimap.set_token_fn(func(coord: Vector2i) -> Color:
    var units := registry.get_units_at(coord)
    if units.is_empty():
        return Color.TRANSPARENT
    var unit: MapToken = units[0]
    match unit.unit_type:
        "king":    return Color.GOLD
        "knight":  return Color.RED if unit.owner_id == 0 else Color.BLUE
        "scout":   return Color.GREEN
        _:         return Color.WHITE
)
minimap.refresh()
```

### Multiple units per hex

When stacking, decide which unit to highlight:

```gdscript
minimap.set_token_fn(func(coord: Vector2i) -> Color:
    var units := registry.get_units_at(coord)
    if units.is_empty():
        return Color.TRANSPARENT
    # Highlight the highest-priority unit
    var best: MapToken = units[0]
    for u in units:
        if u.level > best.level:
            best = u
    return PLAYER_COLORS[best.owner_id]
)
```

### Fog of war integration

Pass a `FogOfWar` instance to `setup()` to auto-refresh on fog changes:

```gdscript
minimap.setup(grid, Vector2(200, 150), fog, current_player_id)
# Auto-refreshes when fog.reveal_around() or fog.update_visibility() is called
```

Hidden cells render as a dark color (configurable via `params.color_hidden`).
Explored cells show terrain but dimmed. Visible cells show full terrain color.

---

## Batch rendering for large maps

The default rendering mode creates one `Area2D` subtree per hex (~7 nodes each).
For maps up to ~100×100 (10K hexes), this works well. For 200×200+ (40K+ hexes),
the scene tree overhead causes performance issues.

### When to use batch mode

| Map size | Hexes | Recommended mode |
|----------|-------|-----------------|
| < 50×50 | < 2.5K | Node-per-hex (default) |
| 50–100×100 | 2.5K–10K | Either (test both) |
| > 100×100 | > 10K | Batch mode |

### Switching to batch mode

`HexBatchRenderer` is a separate class — don't reuse the `HexRenderer` instance.
Both share `HexPalette`, so swap one for the other:

```gdscript
# Instead of:
# var renderer := HexRenderer.new(palette, HexGrid.HEX_SIZE)
# for coord in grid.cells:
#     renderer.create_hex_visual(hex_container, coord, ...)

# Use:
var batch := HexBatchRenderer.new(palette, HexGrid.HEX_SIZE)
batch.render(hex_container, grid)
batch.update_fog(hex_container, grid, player_id)
```

Then call `track_viewport` each frame to trigger redraws when the camera moves:

```gdscript
func _process(delta: float) -> void:
    cam_ctrl.process(delta, target_position)
    batch.track_viewport(hex_container)
```

### Batch mode API mapping

| `HexRenderer` (node-per-hex) | `HexBatchRenderer` (batch) |
|-------------------------------|----------------------------|
| `create_hex_visual()` loop | `render()` |
| `update_fog()` | `update_fog()` |
| `update_reachable_highlight()` | `update_reachable_highlight()` |
| `update_los_highlight()` | `update_los_highlight()` |
| `update_cell_visual()` | `update_cell()` |
| `refresh_cell_color()` | `update_cell()` (full layer redraw) |
| `get_visual_for()` / `get_visual_part()` | — (no individual nodes in batch) |
| `cell_pressed` / `cell_released` signals | — (use `HexGrid.pixel_to_offset()`) |
| — | `track_viewport()` (required in `_process`) |

### What batch mode does NOT render

Batch mode draws terrain color + borders, fog overlays, and highlight overlays.
It does **not** support:
- Cell icons (`cell_icon_fn`)
- Textures (`texture_fn`)
- Animations (`animation_fn`)
- Custom tile visuals (`tile_visual_fn`)
- Overlay nodes (`overlay_fn`)

If you need these features, use the node-per-hex mode or combine both (node-per-hex
for a visible area, batch for background).

### How viewport culling works

`BatchHexLayer._draw()` reads the canvas transform to calculate which hexes are
visible in the current viewport. Only those hexes are drawn. When the camera moves
more than 1.5 hex sizes, the layer redraws with the new visible set. This means
redraw cost is proportional to screen size, not map size.
