class_name HexRenderer
extends RefCounted
## Renderizado visual de hexágonos: creación, highlighting, niebla.
## Extraído de MapScene para separar presentación de orquestación.

const DEFAULT_TERRAIN_COLORS: Dictionary = {
	HexCell.Terrain.ROAD: Color(0.36, 0.25, 0.20),
	HexCell.Terrain.PLAINS: Color(0.18, 0.35, 0.22),
	HexCell.Terrain.FOREST: Color(0.10, 0.22, 0.12),
	HexCell.Terrain.MOUNTAIN: Color(0.40, 0.38, 0.35),
	HexCell.Terrain.WATER: Color(0.12, 0.22, 0.42),
}

const DEFAULT_FOG_COLORS: Dictionary = {
	FogOfWar.FogState.HIDDEN: Color(0.02, 0.02, 0.04, 1.0),
	FogOfWar.FogState.EXPLORED: Color(0.05, 0.05, 0.08, 0.5),
}

const REACHABLE_COLOR := Color(0.9, 0.85, 0.3, 0.3)
const BORDER_COLOR := Color(0.2, 0.2, 0.2, 0.5)
const BORDER_WIDTH := 1.0
const ICON_OFFSET := Vector2(-6, -6)
const ICON_FONT_SIZE := 12

var _terrain_colors: Dictionary
var _cell_icon_fn: Callable
var _fog_colors: Dictionary
var _hex_size: float
var _tile_visual_fn: Callable
var _texture_fn: Callable
var _animation_fn: Callable
var _overlay_fn: Callable
var _reachable_color: Color
var _border_color: Color
var _border_width: float

var _batch_fog_pid: int = 0
var _batch_highlighted: Dictionary = {}
var _batch_los_visible: Array[Vector2i] = []
var _batch_los_blocked: Array[Vector2i] = []


func _init(
	terrain_colors: Dictionary = DEFAULT_TERRAIN_COLORS,
	cell_icon_fn: Callable = Callable(),
	fog_colors: Dictionary = {},
	hex_size: float = HexGrid.HEX_SIZE,
	tile_visual_fn: Callable = Callable(),
	texture_fn: Callable = Callable(),
	animation_fn: Callable = Callable(),
	overlay_fn: Callable = Callable(),
	reachable_color: Color = REACHABLE_COLOR,
	border_color: Color = BORDER_COLOR,
	border_width: float = BORDER_WIDTH,
) -> void:
	_terrain_colors = terrain_colors
	_cell_icon_fn = cell_icon_fn
	_fog_colors = fog_colors if fog_colors else DEFAULT_FOG_COLORS
	_hex_size = hex_size
	_tile_visual_fn = tile_visual_fn
	_texture_fn = texture_fn
	_animation_fn = animation_fn
	_overlay_fn = overlay_fn
	_reachable_color = reachable_color
	_border_color = border_color
	_border_width = border_width


static func _hex_node_name(coord: Vector2i) -> String:
	return "Hex_%d_%d" % [coord.x, coord.y]


static func _find_hex_node(container: Node2D, coord: Vector2i) -> Node2D:
	return container.get_node_or_null(_hex_node_name(coord))


func create_hex_visual(hex_container: Node2D, coord: Vector2i, pixel: Vector2, cell: HexCell) -> void:
	var hex_area := Area2D.new()
	hex_area.position = pixel
	hex_area.name = _hex_node_name(coord)

	var points := HexGrid.hex_polygon_points(_hex_size)
	hex_area.add_child(_create_collision(points))
	hex_area.add_child(_create_bg_node(cell, _make_terrain_polygon(cell, points)))
	hex_area.add_child(_create_border(points))
	_add_icon(hex_area, cell)
	hex_area.add_child(_create_highlight(points))
	hex_area.add_child(_create_fog_overlay(points))
	_add_overlays(hex_area, cell)
	hex_container.add_child(hex_area)


func _create_collision(points: PackedVector2Array) -> CollisionPolygon2D:
	var collision := CollisionPolygon2D.new()
	collision.polygon = points
	return collision


func _make_terrain_polygon(cell: HexCell, points: PackedVector2Array) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = _terrain_colors.get(cell.terrain, Color.GRAY)
	return poly


func _create_border(points: PackedVector2Array) -> Line2D:
	var border := Line2D.new()
	border.points = points
	border.add_point(points[0])
	border.width = _border_width
	border.default_color = _border_color
	border.name = "Border"
	return border


func _add_icon(hex_area: Area2D, cell: HexCell) -> void:
	if not _cell_icon_fn.is_valid():
		return
	var icon_text: String = _cell_icon_fn.call(cell)
	if icon_text == "":
		return
	var icon := Label.new()
	icon.name = "CellIcon"
	icon.text = icon_text
	icon.position = ICON_OFFSET
	icon.add_theme_font_size_override("font_size", ICON_FONT_SIZE)
	hex_area.add_child(icon)


func _create_highlight(points: PackedVector2Array) -> Polygon2D:
	var highlight := Polygon2D.new()
	highlight.polygon = points
	highlight.color = _reachable_color
	highlight.name = "Highlight"
	highlight.visible = false
	return highlight


func _create_fog_overlay(points: PackedVector2Array) -> Polygon2D:
	var fog_overlay := Polygon2D.new()
	fog_overlay.polygon = points
	fog_overlay.color = _fog_colors.get(FogOfWar.FogState.HIDDEN, DEFAULT_FOG_COLORS[FogOfWar.FogState.HIDDEN])
	fog_overlay.name = "Fog"
	return fog_overlay


func _add_overlays(hex_area: Area2D, cell: HexCell) -> void:
	if not _overlay_fn.is_valid():
		return
	var overlays: Array[Node2D] = []
	overlays.assign(_overlay_fn.call(cell))
	for overlay_node in overlays:
		if overlay_node is Node2D:
			hex_area.add_child(overlay_node)


func _create_bg_node(cell: HexCell, fallback: Polygon2D) -> Node2D:
	var result := _try_custom_visual(cell)
	if result:
		return result
	result = _try_animation_bg(cell)
	if result:
		return result
	result = _try_texture_bg(cell)
	if result:
		return result
	return _as_bg(fallback)


func _try_custom_visual(cell: HexCell) -> Node2D:
	if not _tile_visual_fn.is_valid():
		return null
	var visual: Node2D = _tile_visual_fn.call(cell)
	if visual:
		visual.name = "Bg"
		return visual
	return null


func _try_animation_bg(cell: HexCell) -> Node2D:
	if not _animation_fn.is_valid():
		return null
	var frames: SpriteFrames = _animation_fn.call(cell)
	if not frames:
		return null
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = frames
	anim.name = "Bg"
	if frames.has_animation("idle"):
		anim.play("idle")
	elif frames.get_animation_names().size() > 0:
		anim.play(frames.get_animation_names()[0])
	return anim


func _try_texture_bg(cell: HexCell) -> Node2D:
	if not _texture_fn.is_valid():
		return null
	var tex: Texture2D = _texture_fn.call(cell)
	if not tex:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.name = "Bg"
	return sprite


func _as_bg(fallback: Polygon2D) -> Node2D:
	fallback.name = "Bg"
	return fallback


func update_reachable_highlight(hex_container: Node2D, grid: HexGrid, reachable: Dictionary, highlighted_hexes: Dictionary) -> void:
	_clear_highlights(hex_container, highlighted_hexes)

	for coord in reachable:
		highlighted_hexes[coord] = true
		var node := _find_hex_node(hex_container, coord)
		if node:
			var highlight: Polygon2D = node.get_node_or_null("Highlight")
			if highlight:
				highlight.visible = true


func _clear_highlights(hex_container: Node2D, highlighted_hexes: Dictionary) -> void:
	for coord in highlighted_hexes:
		var node := _find_hex_node(hex_container, coord)
		if node:
			var highlight: Polygon2D = node.get_node_or_null("Highlight")
			if highlight:
				highlight.visible = false


func update_los_highlight(hex_container: Node2D,
		visible_coords: Array[Vector2i],
		blocked_coords: Array[Vector2i] = [],
		visible_color: Color = Color(0.3, 0.7, 1.0, 0.25),
		blocked_color: Color = Color(1.0, 0.2, 0.2, 0.15)) -> void:
	for coord in visible_coords:
		var node := _find_hex_node(hex_container, coord)
		if node:
			var h: Polygon2D = node.get_node_or_null("Highlight")
			if h:
				h.color = visible_color
				h.visible = true
	for coord in blocked_coords:
		var node := _find_hex_node(hex_container, coord)
		if node:
			var h: Polygon2D = node.get_node_or_null("Highlight")
			if h:
				h.color = blocked_color
				h.visible = true


func update_fog(hex_container: Node2D, grid: HexGrid, player_id: int = 0) -> void:
	var all_cells := grid.get_all_cells()
	for coord in all_cells:
		var cell: HexCell = all_cells[coord]
		var node := _find_hex_node(hex_container, coord)
		if not node:
			continue

		var state := cell.get_fog_state(player_id)
		var fog_overlay: Polygon2D = node.get_node_or_null("Fog")
		var bg: CanvasItem = node.get_node_or_null("Bg")
		var border: Line2D = node.get_node_or_null("Border")
		var icon: Label = node.get_node_or_null("CellIcon")

		match state:
			FogOfWar.FogState.VISIBLE:
				_set_node_visibility(fog_overlay, false, Color())
				_set_node_visibility(bg, true, Color())
				_set_node_visibility(border, true, Color())
				_set_node_visibility(icon, true, Color())

			FogOfWar.FogState.EXPLORED:
				_set_node_visibility(fog_overlay, true, _fog_colors.get(FogOfWar.FogState.EXPLORED, DEFAULT_FOG_COLORS[FogOfWar.FogState.EXPLORED]))
				_set_node_visibility(bg, true, Color())
				_set_node_visibility(border, true, Color())
				_set_node_visibility(icon, false, Color())

			FogOfWar.FogState.HIDDEN:
				_set_node_visibility(fog_overlay, true, _fog_colors.get(FogOfWar.FogState.HIDDEN, DEFAULT_FOG_COLORS[FogOfWar.FogState.HIDDEN]))
				_set_node_visibility(bg, false, Color())
				_set_node_visibility(border, false, Color())
				_set_node_visibility(icon, false, Color())


func _set_node_visibility(node: CanvasItem, visible: bool, color: Color) -> void:
	if not node:
		return
	node.visible = visible
	if color != Color() and node is Polygon2D:
		node.color = color


func update_cell_visual(hex_container: Node2D, coord: Vector2i, cell: HexCell) -> void:
	var node := _find_hex_node(hex_container, coord)
	if not node:
		return
	var old_bg := node.get_node_or_null("Bg")
	if old_bg:
		node.remove_child(old_bg)
		old_bg.queue_free()

	var points := HexGrid.hex_polygon_points(_hex_size)
	var new_bg := _create_bg_node(cell, _make_terrain_polygon(cell, points))
	node.add_child(new_bg)
	node.move_child(new_bg, 0)


func render_edges(edge_container: Node2D, grid: HexGrid, edge_color: Color = Color(0.2, 0.5, 0.8, 0.8), edge_width: float = 2.0) -> void:
	for child in edge_container.get_children():
		child.queue_free()

	var drawn: Dictionary = {}
	for key in grid.edges:
		var parts = key.split("|")
		if parts.size() != 2:
			continue
		var pa = parts[0].split(",")
		var pb = parts[1].split(",")
		if pa.size() != 2 or pb.size() != 2:
			continue
		var a := Vector2i(int(pa[0]), int(pa[1]))
		var b := Vector2i(int(pb[0]), int(pb[1]))

		var pair_key := str(a) + "|" + str(b)
		if drawn.has(pair_key):
			continue
		drawn[pair_key] = true

		var pixel_a := HexGrid.offset_to_pixel(a, _hex_size)
		var pixel_b := HexGrid.offset_to_pixel(b, _hex_size)
		var line := Line2D.new()
		line.add_point(pixel_a)
		line.add_point(pixel_b)
		line.width = edge_width
		line.default_color = edge_color
		line.name = "Edge_%s_%s" % [str(a), str(b)]
		edge_container.add_child(line)


# === Batch mode ===

const _BATCH_TERRAIN := "BatchTerrain"
const _BATCH_FOG := "BatchFog"
const _BATCH_HIGHLIGHT := "BatchHighlight"


func render_batch(container: Node2D, grid: HexGrid) -> void:
	for child in container.get_children():
		child.queue_free()

	_batch_highlighted.clear()
	_batch_los_visible.clear()
	_batch_los_blocked.clear()

	var terrain := BatchHexLayer.new(grid, _hex_size, _draw_terrain)
	terrain.name = _BATCH_TERRAIN
	container.add_child(terrain)

	var fog := BatchHexLayer.new(grid, _hex_size, _draw_fog)
	fog.name = _BATCH_FOG
	container.add_child(fog)

	var highlight := BatchHexLayer.new(grid, _hex_size, _draw_highlight)
	highlight.name = _BATCH_HIGHLIGHT
	container.add_child(highlight)


func update_batch_fog(container: Node2D, grid: HexGrid, player_id: int = 0) -> void:
	_batch_fog_pid = player_id
	_get_batch_layer(container, _BATCH_FOG).mark_dirty()


func update_batch_reachable_highlight(container: Node2D, grid: HexGrid, reachable: Dictionary, highlighted_hexes: Dictionary) -> void:
	_batch_highlighted.clear()
	for coord in highlighted_hexes:
		highlighted_hexes.erase(coord)
	for coord in reachable:
		highlighted_hexes[coord] = true
	_batch_highlighted = highlighted_hexes.duplicate()
	_get_batch_layer(container, _BATCH_HIGHLIGHT).mark_dirty()


func update_batch_los_highlight(container: Node2D,
		visible_coords: Array[Vector2i],
		blocked_coords: Array[Vector2i] = []) -> void:
	_batch_los_visible = visible_coords
	_batch_los_blocked = blocked_coords
	_batch_highlighted.clear()
	_get_batch_layer(container, _BATCH_HIGHLIGHT).mark_dirty()


func update_batch_cell(container: Node2D, grid: HexGrid, coord: Vector2i) -> void:
	_get_batch_layer(container, _BATCH_TERRAIN).mark_dirty()


func batch_track_viewport(container: Node2D) -> void:
	for name in [_BATCH_TERRAIN, _BATCH_FOG, _BATCH_HIGHLIGHT]:
		var layer: BatchHexLayer = container.get_node_or_null(name)
		if layer:
			layer.check_viewport()


static func _get_batch_layer(container: Node2D, name: String) -> BatchHexLayer:
	var layer: BatchHexLayer = container.get_node_or_null(name)
	if not layer:
		push_error("HexRenderer: batch layer '%s' not found — call render_batch() first" % name)
	return layer


func _draw_terrain(layer: BatchHexLayer, grid: HexGrid, hex_size: float, min_coord: Vector2i, max_coord: Vector2i) -> void:
	var pts := HexGrid.hex_polygon_points(hex_size)
	for y in range(min_coord.y, max_coord.y + 1):
		for x in range(min_coord.x, max_coord.x + 1):
			var coord := Vector2i(x, y)
			var cell: HexCell = grid.get_cell(coord)
			if not cell:
				continue
			var pixel := HexGrid.offset_to_pixel(coord, hex_size)
			var translated := PackedVector2Array()
			for p in pts:
				translated.append(p + pixel)
			var color: Color = _terrain_colors.get(cell.terrain, Color.GRAY)
			layer.draw_colored_polygon(translated, color)
			layer.draw_polyline(translated, _border_color, _border_width)


func _draw_fog(layer: BatchHexLayer, grid: HexGrid, hex_size: float, min_coord: Vector2i, max_coord: Vector2i) -> void:
	var pts := HexGrid.hex_polygon_points(hex_size)
	for y in range(min_coord.y, max_coord.y + 1):
		for x in range(min_coord.x, max_coord.x + 1):
			var coord := Vector2i(x, y)
			var cell: HexCell = grid.get_cell(coord)
			if not cell:
				continue
			var state := cell.get_fog_state(_batch_fog_pid)
			if state == FogOfWar.FogState.VISIBLE:
				continue
			var pixel := HexGrid.offset_to_pixel(coord, hex_size)
			var translated := PackedVector2Array()
			for p in pts:
				translated.append(p + pixel)
			var fog_color: Color = _fog_colors.get(state, DEFAULT_FOG_COLORS.get(state, Color.BLACK))
			layer.draw_colored_polygon(translated, fog_color)


func _draw_highlight(layer: BatchHexLayer, grid: HexGrid, hex_size: float, min_coord: Vector2i, max_coord: Vector2i) -> void:
	var pts := HexGrid.hex_polygon_points(hex_size)
	var has_los := _batch_los_visible.size() > 0 or _batch_los_blocked.size() > 0
	var coords_to_draw: Dictionary = {}
	if has_los:
		for coord in _batch_los_visible:
			coords_to_draw[coord] = Color(0.3, 0.7, 1.0, 0.25)
		for coord in _batch_los_blocked:
			coords_to_draw[coord] = Color(1.0, 0.2, 0.2, 0.15)
	else:
		for coord in _batch_highlighted:
			coords_to_draw[coord] = _reachable_color

	for coord_key in coords_to_draw:
		var coord: Vector2i = coord_key
		if coord.x < min_coord.x or coord.x > max_coord.x or coord.y < min_coord.y or coord.y > max_coord.y:
			continue
		var pixel := HexGrid.offset_to_pixel(coord, hex_size)
		var translated := PackedVector2Array()
		for p in pts:
			translated.append(p + pixel)
		layer.draw_colored_polygon(translated, coords_to_draw[coord_key])
