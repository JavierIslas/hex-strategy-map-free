# Migration Guide — 1.x → 2.0

Hex Strategy Map 2.0 is a major release that liquidates accumulated technical
debt and simplifies the public API. There is **no deprecation period** — every
break is documented below with a before/after snippet.

## Summary

| Item | Type | Affects |
|------|------|---------|
| `HexRenderer.new()` signature | Breaking | All consumers of `HexRenderer` |
| `HexRenderer.render_batch()` and `update_batch_*` removed | Breaking | Batch mode users |
| `HexMapNode.terrain_data` removed | Breaking | Scenes saved with `terrain_data` field |
| `SaveManager.SAVE_DIR` alias removed | Breaking | Anyone referencing the alias |
| `HexPalette.from_legacy()` removed | Breaking | Internal helper; rarely used externally |
| `HexRenderer.DEFAULT_*` re-exports removed | Breaking | Anyone reading defaults via `HexRenderer.` |
| `MapToken.move_to(target, reachable={})` | Non-breaking (new optional arg) | Optional optimization |
| `plugin.cfg` vs `plugin_pro.cfg` clarification | Docs | Plugin packaging |

---

## 1. `HexRenderer._init` — new signature

The old constructor took up to 13 positional parameters. The new constructor
takes a `HexPalette` resource plus a single `callables` dictionary.

### Before (1.x)

```gdscript
var renderer := HexRenderer.new(
    HexRenderer.DEFAULT_TERRAIN_COLORS,
    my_icon_fn,
    HexRenderer.DEFAULT_FOG_COLORS,
    HexGrid.HEX_SIZE,
    my_texture_fn,
    my_animation_fn,
    my_tile_visual_fn,
    my_overlay_fn,
    my_color_fn,
    my_fog_material,
    Vector2(0, -10),
    14
)
```

### After (2.0)

```gdscript
var palette := HexPalette.new()
palette.terrain_colors = HexPalette.DEFAULT_TERRAIN_COLORS.duplicate()
palette.fog_colors = HexPalette.DEFAULT_FOG_COLORS.duplicate()
palette.color_fn = my_color_fn

var renderer := HexRenderer.new(palette, HexGrid.HEX_SIZE, {
    "cell_icon_fn": my_icon_fn,
    "texture_fn": my_texture_fn,
    "animation_fn": my_animation_fn,
    "tile_visual_fn": my_tile_visual_fn,
    "overlay_fn": my_overlay_fn,
    "fog_material": my_fog_material,
    "icon_offset": Vector2(0, -10),
    "icon_font_size": 14,
})
```

### Defaults via `HexPalette`

The `HexRenderer.DEFAULT_TERRAIN_COLORS`, `DEFAULT_FOG_COLORS`, `REACHABLE_COLOR`,
`BORDER_COLOR`, `BORDER_WIDTH`, and `SKIP_COLOR` re-exports are gone. They live
on `HexPalette` now:

```gdscript
# 1.x
HexRenderer.DEFAULT_TERRAIN_COLORS
HexRenderer.SKIP_COLOR

# 2.0
HexPalette.DEFAULT_TERRAIN_COLORS
HexPalette.SKIP_COLOR
```

### `HexPalette.from_legacy()` is gone

If you were using `HexPalette.from_legacy(...)` to bridge the old signature,
build the palette directly:

```gdscript
# 1.x
var palette := HexPalette.from_legacy(my_colors, my_fog_colors, my_color_fn)

# 2.0
var palette := HexPalette.new()
palette.terrain_colors = my_colors
palette.fog_colors = my_fog_colors
palette.color_fn = my_color_fn
```

---

## 2. Batch facade removed from `HexRenderer`

`HexRenderer` no longer delegates to `HexBatchRenderer`. Use `HexBatchRenderer`
directly for batch rendering.

### Before (1.x)

```gdscript
var renderer := HexRenderer.new(...)
renderer.render_batch(container, grid)
renderer.update_batch_fog(container, grid, player_id)
renderer.update_batch_reachable_highlight(container, reachable)
renderer.update_batch_los_highlight(container, visible, blocked)
renderer.update_batch_cell(container, coord, grid)
renderer.batch_track_viewport(container)
```

### After (2.0)

```gdscript
var batch := HexBatchRenderer.new(HexPalette.new(), HexGrid.HEX_SIZE)
batch.render(container, grid)
batch.update_fog(container, grid, player_id)
batch.update_reachable_highlight(container, reachable)
batch.update_los_highlight(container, visible, blocked)
batch.update_cell(container, coord, grid)
batch.track_viewport(container)
```

The two renderers are mutually exclusive: pick `HexRenderer` for node-per-hex
(small/medium maps, icons, animations, overlays) or `HexBatchRenderer` for
batch mode (200×200+ maps, terrain + fog + highlights only). They share the
same `HexPalette`, so swapping is just a constructor change.

---

## 3. `HexMapNode.terrain_data` removed

The `@export var terrain_data: Dictionary` field is gone. `cell_data` is the
single source of truth.

### Migrating an existing `.tscn`

Scenes saved with `terrain_data` populated will not auto-migrate. Run this
one-off script against your scene before opening it in 2.0:

```gdscript
# tools/migrate_v1_v2.gd — usage:
#   godot --headless --script tools/migrate_v1_v2.gd -- res://path/to/scene.tscn
@tool
extends SceneTree

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.is_empty():
        push_error("usage: migrate_v1_v2.gd -- <scene.tscn>")
        quit(1)
        return

    var path := args[0]
    var packed: PackedScene = load(path)
    var root := packed.instantiate()
    var migrated := 0

    for node in _walk(root):
        if node.get_class() != "Node2D":
            continue
        var script: GDScript = node.get_script()
        if not script or not script.resource_path.ends_with("hex_map_node.gd"):
            continue
        var old: Dictionary = node.get("terrain_data") if "terrain_data" in node else {}
        if old.is_empty():
            continue
        var new: Dictionary = node.get("cell_data")
        for key in old:
            var entry: Dictionary = new.get(key, {})
            entry["terrain"] = old[key]
            new[key] = entry
        node.set("cell_data", new)
        migrated += 1

    if migrated > 0:
        var out := PackedScene.new()
        out.pack(root)
        ResourceSaver.save(out, path)
        print("Migrated %d HexMapNode(s) in %s" % [migrated, path])
    else:
        print("Nothing to migrate in %s" % path)
    quit()


func _walk(node: Node) -> Array[Node]:
    var result: Array[Node] = [node]
    for child in node.get_children():
        result.append_array(_walk(child))
    return result
```

If you never used `terrain_data` directly (only painted via the editor on a
fresh node), there is nothing to migrate — `cell_data` was already the storage.

---

## 4. `SaveManager.SAVE_DIR` alias removed

```gdscript
# 1.x
SaveManager.SAVE_DIR

# 2.0
SaveManager.DEFAULT_SAVE_DIR
```

---

## 5. `MapToken.move_to` accepts an optional `reachable` cache

This is **non-breaking** — the new parameter has a default. Pass a precomputed
reachable dictionary to avoid recomputing `get_reachable_hexes()` inside
`move_to`. Useful when you already highlighted the reachable set in the UI.

```gdscript
# Recompute (1.x behavior, still the default)
token.move_to(target)

# Reuse a cached reachable set (recommended when available)
var reachable := grid.get_reachable_hexes(token.hex_coord, token.movement_points)
token.move_to(target, reachable)
```

---

## 6. `plugin.cfg` vs `plugin_pro.cfg` vs `plugin_free.cfg`

The addon ships three `.cfg` files for distribution:

| File | Used by | Notes |
|------|---------|-------|
| `plugin.cfg` | Development checkout | Default file Godot picks up locally. Script: `plugin.gd` (full editor features) |
| `plugin_pro.cfg` | Pro distribution build | Copied to `plugin.cfg` by `pack.sh` when building the Pro package. Script: `plugin.gd` |
| `plugin_free.cfg` | Free distribution build | Copied to `plugin.cfg` by `pack.sh` when building the Free package. Script: `plugin_free.gd` (stub — no editor features) |

If you only consume the addon, you never need to touch these files. If you
fork or repackage, `pack.sh` chooses the right one per tier.

---

## Quick checklist

- [ ] Replace every `HexRenderer.new(...)` call with the palette + dict form
- [ ] Replace `HexRenderer.DEFAULT_*` and `HexRenderer.SKIP_COLOR` with `HexPalette.*`
- [ ] Replace `renderer.render_batch(...)` with `HexBatchRenderer.new(...).render(...)`
- [ ] Run the `terrain_data` migration script on legacy `.tscn` scenes
- [ ] Replace `SaveManager.SAVE_DIR` with `SaveManager.DEFAULT_SAVE_DIR`
- [ ] Optional: pass a `reachable` cache to `MapToken.move_to`
