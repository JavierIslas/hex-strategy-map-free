class_name HexBatchRenderer
extends RefCounted
## Renderizado batch de hexágonos vía BatchHexLayer (terreno, niebla, highlight).
##
## Alternativa al modo nodo-per-hex de HexRenderer para mapas grandes (200×200+):
## dibuja con [code]_draw()[/code] directo en lugar de instanciar un Area2D por celda.
## No soporta iconos, texturas inyectadas, overlays ni señales [code]cell_pressed[/code].
##
## Uso directo (sin HexRenderer):
## [codeblock]
## var palette := HexPalette.new()
## var batch := HexBatchRenderer.new(palette, HexGrid.HEX_SIZE)
## batch.render(container, grid)
## batch.update_fog(container, grid, 0)
## batch.track_viewport(container)  # llamar en _process
## [/codeblock]
##
## HexRenderer es nodo-per-hex únicamente — para batch mode, instanciar esta clase directo.

const _BATCH_TERRAIN := "BatchTerrain"
const _BATCH_FOG := "BatchFog"
const _BATCH_HIGHLIGHT := "BatchHighlight"

var _palette: HexPalette
var _hex_size: float
var _ignored_callables_hint: PackedStringArray
# Container guardado en render() para que el handler de palette_changed pueda
# invalidar las 3 capas sin que el consumer tenga que reenganchar manualmente.
var _container: Node2D = null

var _batch_fog_pid: int = 0
var _batch_highlighted: Dictionary = {}
var _batch_los_visible: Array[Vector2i] = []
var _batch_los_blocked: Array[Vector2i] = []


## [param ignored_callables_hint] sirve para que HexRenderer emita el warning de
## callables ignorados al delegar (cell_icon_fn, tile_visual_fn, overlay_fn).
## Cuando se instancia HexBatchRenderer directo, dejar vacío.
func _init(palette: HexPalette, hex_size: float, ignored_callables_hint: PackedStringArray = []) -> void:
	_palette = palette
	_hex_size = hex_size
	_ignored_callables_hint = ignored_callables_hint
	if _palette and not _palette.palette_changed.is_connected(_on_palette_changed):
		_palette.palette_changed.connect(_on_palette_changed)


func _on_palette_changed() -> void:
	if not _container or not is_instance_valid(_container):
		return
	for layer_name in [_BATCH_TERRAIN, _BATCH_FOG, _BATCH_HIGHLIGHT]:
		var layer: BatchHexLayer = _container.get_node_or_null(layer_name)
		if layer:
			layer.mark_dirty()


## Inicializa el modo batch: crea tres BatchHexLayer (terreno, niebla, highlight)
## en [param container] y descarta cualquier hijo anterior.
## Después de llamar este método, usar update_fog/update_*_highlight y track_viewport.
func render(container: Node2D, grid: HexGrid) -> void:
	if not _ignored_callables_hint.is_empty():
		push_warning("HexBatchRenderer.render(): los siguientes callables serán ignorados en modo batch: %s. Renderizalos en una capa separada (ver examples/large_world)." % ", ".join(_ignored_callables_hint))

	for child in container.get_children():
		child.queue_free()

	_container = container
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


## Marca la capa de niebla batch como sucia para [param player_id].
## El redraw ocurre en el próximo frame. Llamar después de FogOfWar.update_visibility().
func update_fog(_container: Node2D, _grid: HexGrid, player_id: int = 0) -> void:
	_batch_fog_pid = player_id
	_mark_dirty(_container, _BATCH_FOG)


## Actualiza el highlight batch con el set [param reachable].
## [param highlighted_hexes] es el mismo cache mutable que en HexRenderer.update_reachable_highlight().
func update_reachable_highlight(container: Node2D, _grid: HexGrid, reachable: Dictionary, highlighted_hexes: Dictionary) -> void:
	_batch_highlighted.clear()
	highlighted_hexes.clear()
	for coord in reachable:
		highlighted_hexes[coord] = true
	_batch_highlighted = highlighted_hexes.duplicate()
	_mark_dirty(container, _BATCH_HIGHLIGHT)


## Actualiza el highlight batch con LOS: azul para visibles, rojo para bloqueados.
## Limpia el reachable highlight anterior si había uno activo.
func update_los_highlight(container: Node2D,
		visible_coords: Array[Vector2i],
		blocked_coords: Array[Vector2i] = []) -> void:
	_batch_los_visible = visible_coords
	_batch_los_blocked = blocked_coords
	_batch_highlighted.clear()
	_mark_dirty(container, _BATCH_HIGHLIGHT)


## Marca la capa de terreno batch como sucia después de cambiar el terreno de [param coord].
## El grid entero se redibuja (batch no tiene granularidad por celda).
func update_cell(container: Node2D, _grid: HexGrid, _coord: Vector2i) -> void:
	_mark_dirty(container, _BATCH_TERRAIN)


## Llama check_viewport() en las tres capas batch. Invocar desde _process() del consumidor.
## Marca dirty automáticamente cuando la cámara se movió más de un hex desde el último redraw.
func track_viewport(container: Node2D) -> void:
	for layer_name in [_BATCH_TERRAIN, _BATCH_FOG, _BATCH_HIGHLIGHT]:
		var layer: BatchHexLayer = container.get_node_or_null(layer_name)
		if layer:
			layer.check_viewport()


func _mark_dirty(container: Node2D, layer_name: String) -> void:
	var layer := _get_batch_layer(container, layer_name)
	if layer:
		layer.mark_dirty()


static func _get_batch_layer(container: Node2D, layer_name: String) -> BatchHexLayer:
	var layer: BatchHexLayer = container.get_node_or_null(layer_name)
	if not layer:
		push_error("HexBatchRenderer: batch layer '%s' not found — call render() first" % layer_name)
		return null
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
			var translated := HexGrid.translated_hex_polygon(pts, pixel)
			layer.draw_colored_polygon(translated, _palette.resolve_cell_color(cell))
			layer.draw_polyline(translated, _palette.border_color, _palette.border_width)


func _draw_fog(layer: BatchHexLayer, grid: HexGrid, hex_size: float, min_coord: Vector2i, max_coord: Vector2i) -> void:
	var pts := HexGrid.hex_polygon_points(hex_size)
	for y in range(min_coord.y, max_coord.y + 1):
		for x in range(min_coord.x, max_coord.x + 1):
			var coord := Vector2i(x, y)
			var cell: HexCell = grid.get_cell(coord)
			if not cell:
				continue
			var state := cell.get_fog_state(_batch_fog_pid)
			if state == FogState.VISIBLE:
				continue
			var pixel := HexGrid.offset_to_pixel(coord, hex_size)
			var translated := HexGrid.translated_hex_polygon(pts, pixel)
			var fog_color: Color = _palette.fog_colors.get(state, HexPalette.DEFAULT_FOG_COLORS.get(state, Color.BLACK))
			layer.draw_colored_polygon(translated, fog_color)


func _draw_highlight(layer: BatchHexLayer, _grid: HexGrid, hex_size: float, min_coord: Vector2i, max_coord: Vector2i) -> void:
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
			coords_to_draw[coord] = _palette.reachable_color

	for coord_key in coords_to_draw:
		var coord: Vector2i = coord_key
		if coord.x < min_coord.x or coord.x > max_coord.x or coord.y < min_coord.y or coord.y > max_coord.y:
			continue
		var pixel := HexGrid.offset_to_pixel(coord, hex_size)
		var translated := HexGrid.translated_hex_polygon(pts, pixel)
		layer.draw_colored_polygon(translated, coords_to_draw[coord_key])
