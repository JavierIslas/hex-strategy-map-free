class_name HexRenderer
extends RefCounted
## Renderizado visual de hexágonos: creación de nodos, highlighting y niebla.
##
## Nodo-per-hex: cada hex es un Area2D con hijos Bg/Border/Highlight/Fog.
## Soporta iconos, texturas, animaciones, overlays y señales cell_pressed/cell_released.
## Para mapas grandes (200×200+) sin iconos/texturas, usar [HexBatchRenderer] directo.
##
## Visuals del nodo-per-hex — hijos del Area2D "Hex_X_Y":
##   "Bg"        → fondo de terreno (Polygon2D, Sprite2D o AnimatedSprite2D).
##   "Border"    → borde Line2D.
##   "Highlight" → overlay de alcance/selección (oculto por defecto).
##   "Fog"       → overlay de niebla (visible por defecto — llamar update_fog() para actualizar).
##   "CellIcon"  → Label opcional si cell_icon_fn está inyectado.
##
## Todos los Callables son opcionales — omitir los que no se necesitan.

## Emitidas por hex en modo nodo-per-hex (no batch). El consumidor filtra
## por botón (event.button_index == MOUSE_BUTTON_LEFT) si necesita restringir.
## Acepta mouse y touch (InputEventScreenTouch).
## Si el usuario presiona dentro del hex y suelta fuera, cell_released puede no
## emitirse desde ese hex (comportamiento estándar de Area2D.input_event).
## No asumir que cada cell_pressed tiene su cell_released pareado en el mismo coord.
signal cell_pressed(coord: Vector2i, event: InputEvent)
signal cell_released(coord: Vector2i, event: InputEvent)

const DEFAULT_ICON_OFFSET := Vector2(-6, -6)
const DEFAULT_ICON_FONT_SIZE := 12

## Estrategia de dibujo usada por render_edges().
##   CENTERS — Line2D del centro de un hex al centro del otro (default, backward-compat).
##             Útil para "caminos", "ríos navegables" o conexiones que cruzan ambos hex.
##   SHARED_BORDER — Segmento centrado en el borde compartido, perpendicular a la línea
##                   centro-a-centro y de longitud HEX_SIZE. Útil para "muros", "fronteras"
##                   u obstáculos que separan dos hex sin cubrir ninguno.
enum EdgeRenderMode { CENTERS, SHARED_BORDER }

var _palette: HexPalette
var _cell_icon_fn: Callable
var _hex_size: float
var _tile_visual_fn: Callable
var _texture_fn: Callable
var _animation_fn: Callable
var _overlay_fn: Callable
var _fog_material: ShaderMaterial
var icon_offset: Vector2 = DEFAULT_ICON_OFFSET
var icon_font_size: int = DEFAULT_ICON_FONT_SIZE


## [param palette]: paleta de colores y resolver. Si null, usa [code]HexPalette.new()[/code] (defaults).
## [param hex_size]: tamaño del hex en pixels (radio circunscripto).
## [param callables]: dict opcional con keys: cell_icon_fn, tile_visual_fn, texture_fn,
## animation_fn, overlay_fn, fog_material, icon_offset, icon_font_size.
func _init(
		palette: HexPalette = null,
		hex_size: float = HexGrid.HEX_SIZE,
		callables: Dictionary = {}) -> void:
	_palette = palette if palette != null else HexPalette.new()
	_hex_size = hex_size
	_cell_icon_fn = callables.get("cell_icon_fn", Callable())
	_tile_visual_fn = callables.get("tile_visual_fn", Callable())
	_texture_fn = callables.get("texture_fn", Callable())
	_animation_fn = callables.get("animation_fn", Callable())
	_overlay_fn = callables.get("overlay_fn", Callable())
	_fog_material = callables.get("fog_material", null)
	icon_offset = callables.get("icon_offset", DEFAULT_ICON_OFFSET)
	icon_font_size = callables.get("icon_font_size", DEFAULT_ICON_FONT_SIZE)


static func _hex_node_name(coord: Vector2i) -> String:
	return "Hex_%d_%d" % [coord.x, coord.y]


static func get_visual_for(container: Node2D, coord: Vector2i) -> Node2D:
	return container.get_node_or_null(_hex_node_name(coord))


static func get_visual_part(container: Node2D, coord: Vector2i, part_name: String) -> CanvasItem:
	var hex := get_visual_for(container, coord)
	if not hex:
		return null
	var node := hex.get_node_or_null(part_name)
	if node == null:
		return null
	var result := node as CanvasItem
	if result == null:
		push_warning("HexRenderer.get_visual_part: '%s' existe pero no es CanvasItem (%s)" % [part_name, node.get_class()])
	return result


## Crea el Area2D visual para [param cell] en [param pixel] y lo agrega a [param hex_container].
## El nodo se nombra "Hex_X_Y" y contiene Bg, Border, Highlight, Fog y opcionalmente CellIcon.
## Conecta Area2D.input_event → cell_pressed / cell_released.
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
	hex_area.input_event.connect(_on_hex_input.bind(coord))
	hex_container.add_child(hex_area)


func _on_hex_input(_viewport: Node, event: InputEvent, _shape_idx: int, coord: Vector2i) -> void:
	var pressed: bool
	if event is InputEventMouseButton:
		pressed = event.pressed
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	else:
		return
	if pressed:
		cell_pressed.emit(coord, event)
	else:
		cell_released.emit(coord, event)


func _create_collision(points: PackedVector2Array) -> CollisionPolygon2D:
	var collision := CollisionPolygon2D.new()
	collision.polygon = points
	return collision


func _make_terrain_polygon(cell: HexCell, points: PackedVector2Array) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = _palette.resolve_cell_color(cell)
	return poly


func _create_border(points: PackedVector2Array) -> Line2D:
	var border := Line2D.new()
	border.points = points
	border.add_point(points[0])
	border.width = _palette.border_width
	border.default_color = _palette.border_color
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
	icon.position = icon_offset
	icon.add_theme_font_size_override("font_size", icon_font_size)
	hex_area.add_child(icon)


func _create_highlight(points: PackedVector2Array) -> Polygon2D:
	var highlight := Polygon2D.new()
	highlight.polygon = points
	highlight.color = _palette.reachable_color
	highlight.name = "Highlight"
	highlight.visible = false
	return highlight


func _create_fog_overlay(points: PackedVector2Array) -> Polygon2D:
	var fog_overlay := Polygon2D.new()
	fog_overlay.polygon = points
	fog_overlay.name = "Fog"
	var hidden_color: Color = _palette.fog_colors.get(FogState.HIDDEN, HexPalette.DEFAULT_FOG_COLORS[FogState.HIDDEN])
	if _fog_material:
		var mat: ShaderMaterial = _fog_material.duplicate()
		mat.set_shader_parameter("hex_radius", _hex_size)
		mat.set_shader_parameter("fog_color", hidden_color)
		fog_overlay.material = mat
	else:
		fog_overlay.color = hidden_color
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


## Muestra el overlay Highlight en los hexes del set [param reachable] y oculta el resto.
## [param highlighted_hexes] se usa como cache mutable — pasar el mismo Dictionary entre llamadas.
func update_reachable_highlight(hex_container: Node2D, grid: HexGrid, reachable: Dictionary, highlighted_hexes: Dictionary) -> void:
	_clear_highlights(hex_container, highlighted_hexes)

	for coord in reachable:
		highlighted_hexes[coord] = true
		var node := get_visual_for(hex_container, coord)
		if node:
			var highlight: Polygon2D = node.get_node_or_null("Highlight")
			if highlight:
				highlight.visible = true


func _clear_highlights(hex_container: Node2D, highlighted_hexes: Dictionary) -> void:
	for coord in highlighted_hexes:
		var node := get_visual_for(hex_container, coord)
		if node:
			var highlight: Polygon2D = node.get_node_or_null("Highlight")
			if highlight:
				highlight.visible = false


## Colorea el overlay Highlight según LOS: azul para visibles, rojo para bloqueados.
## [param visible_color] y [param blocked_color] son opcionales — usar los defaults para UI estándar.
func update_los_highlight(hex_container: Node2D,
		visible_coords: Array[Vector2i],
		blocked_coords: Array[Vector2i] = [],
		visible_color: Color = Color(0.3, 0.7, 1.0, 0.25),
		blocked_color: Color = Color(1.0, 0.2, 0.2, 0.15)) -> void:
	_apply_los_color(hex_container, visible_coords, visible_color)
	_apply_los_color(hex_container, blocked_coords, blocked_color)


func _apply_los_color(hex_container: Node2D, coords: Array[Vector2i], color: Color) -> void:
	for coord in coords:
		var node := get_visual_for(hex_container, coord)
		if not node:
			continue
		var h: Polygon2D = node.get_node_or_null("Highlight")
		if h:
			h.color = color
			h.visible = true


## Actualiza el overlay Fog de todos los hexes según el estado de niebla de [param player_id].
## Recorre todo el grid — llamar solo cuando el estado cambia (no cada frame).
## Para actualizaciones incrementales, conectar FogOfWar.fog_changed y llamar
## [method update_cell_fog] solo para las celdas modificadas (O(1) por celda).
func update_fog(hex_container: Node2D, grid: HexGrid, player_id: int = 0) -> void:
	var all_cells := grid.get_all_cells()
	for coord in all_cells:
		update_cell_fog(hex_container, coord, all_cells[coord], player_id)


## Actualiza overlay Fog/Bg/Border/CellIcon de una sola celda según su FogState.
## Pensado para ser invocado desde un handler de FogOfWar.fog_changed (O(1)),
## evitando el barrido O(N) de [method update_fog].
func update_cell_fog(hex_container: Node2D, coord: Vector2i, cell: HexCell, player_id: int = 0) -> void:
	var node := get_visual_for(hex_container, coord)
	if not node:
		return

	var state := cell.get_fog_state(player_id)
	var fog_overlay: Polygon2D = node.get_node_or_null("Fog")
	var bg: CanvasItem = node.get_node_or_null("Bg")
	var border: Line2D = node.get_node_or_null("Border")
	var icon: Label = node.get_node_or_null("CellIcon")

	match state:
		FogState.VISIBLE:
			_set_node_visibility(fog_overlay, false, Color())
			_set_node_visibility(bg, true, Color())
			_set_node_visibility(border, true, Color())
			_set_node_visibility(icon, true, Color())

		FogState.EXPLORED:
			_set_node_visibility(fog_overlay, true, _palette.fog_colors.get(FogState.EXPLORED, HexPalette.DEFAULT_FOG_COLORS[FogState.EXPLORED]))
			_set_node_visibility(bg, true, Color())
			_set_node_visibility(border, true, Color())
			_set_node_visibility(icon, false, Color())

		FogState.HIDDEN:
			_set_node_visibility(fog_overlay, true, _palette.fog_colors.get(FogState.HIDDEN, HexPalette.DEFAULT_FOG_COLORS[FogState.HIDDEN]))
			_set_node_visibility(bg, false, Color())
			_set_node_visibility(border, false, Color())
			_set_node_visibility(icon, false, Color())


func _set_node_visibility(node: CanvasItem, visible: bool, color: Color) -> void:
	if not node:
		return
	node.visible = visible
	if color == Color():
		return
	var poly := node as Polygon2D
	if not poly:
		return
	var mat := poly.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fog_color", color)
	else:
		poly.color = color


## Reemplaza el nodo Bg de la celda en [param coord] con uno nuevo basado en [param cell].
## Más costoso que refresh_cell_color() — usar cuando el tipo de visual cambia
## (ej. terreno que pasa de Polygon2D a Sprite2D). Para solo cambiar color, usar refresh_cell_color().
func update_cell_visual(hex_container: Node2D, coord: Vector2i, cell: HexCell) -> void:
	var node := get_visual_for(hex_container, coord)
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


## Fast-path para repintado de color sin recrear el nodo Bg.
## Usa color_fn si está inyectado, sino terrain_colors. Polygon2D recibe
## .color directo; Sprite2D/AnimatedSprite2D reciben .modulate.
func refresh_cell_color(hex_container: Node2D, coord: Vector2i, cell: HexCell) -> void:
	var bg := get_visual_part(hex_container, coord, "Bg")
	if not bg:
		return
	var color := _palette.resolve_cell_color(cell)
	if bg is Polygon2D:
		bg.color = color
	else:
		bg.modulate = color


## Dibuja todos los edges del grid como Line2D en [param edge_container].
## Limpia los hijos anteriores antes de dibujar — llamar después de set_edge() si cambiaron.
## [param mode] controla la geometría del segmento: CENTERS (default) o SHARED_BORDER.
func render_edges(edge_container: Node2D, grid: HexGrid, edge_color: Color = Color(0.2, 0.5, 0.8, 0.8), edge_width: float = 2.0, mode: EdgeRenderMode = EdgeRenderMode.CENTERS) -> void:
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

		var endpoints := _compute_edge_endpoints(a, b, mode)
		var line := Line2D.new()
		line.add_point(endpoints[0])
		line.add_point(endpoints[1])
		line.width = edge_width
		line.default_color = edge_color
		line.name = "Edge_%s_%s" % [str(a), str(b)]
		edge_container.add_child(line)


# Endpoints del Line2D según modo. SHARED_BORDER usa el midpoint del par de centros
# y el vector perpendicular al segmento centro-a-centro; la longitud (_hex_size) corresponde
# al lado del hex regular pointy-top (que coincide con el radio centro→vértice).
func _compute_edge_endpoints(a: Vector2i, b: Vector2i, mode: EdgeRenderMode) -> Array:
	var pixel_a := HexGrid.offset_to_pixel(a, _hex_size)
	var pixel_b := HexGrid.offset_to_pixel(b, _hex_size)
	if mode == EdgeRenderMode.SHARED_BORDER:
		var midpoint := (pixel_a + pixel_b) * 0.5
		var direction := (pixel_b - pixel_a).normalized()
		var perpendicular := Vector2(-direction.y, direction.x)
		var half := perpendicular * (_hex_size * 0.5)
		return [midpoint - half, midpoint + half]
	return [pixel_a, pixel_b]



## Crea un ShaderMaterial con el shader de fog incluido en el addon.
## Útil como punto de partida — el consumidor puede modificar los uniforms antes de pasarlo al renderer.
## Retorna null si el shader no se encuentra (ej. addon instalado en ruta no estándar).
static func create_default_fog_material() -> ShaderMaterial:
	var shader := load("res://addons/hex_strategy_map/fog_overlay.gdshader")
	if not shader:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat
