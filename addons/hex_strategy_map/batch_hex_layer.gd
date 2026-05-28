class_name BatchHexLayer
extends Node2D
## Capa de renderizado batch para hexágonos. Usa _draw() directo en vez de nodos.
## Soporta viewport culling: solo dibuja hexes dentro del área visible de la cámara.
##
## HexBatchRenderer crea tres instancias: BatchTerrain, BatchFog, BatchHighlight.
## No instanciar directamente — usar HexBatchRenderer.render().
##
## draw_fn recibe (layer, grid, hex_size, min_coord, max_coord) y llama a los
## métodos draw_* de CanvasItem (draw_colored_polygon, draw_polyline, etc.)
## sobre el propio layer. El culling limita min/max_coord al viewport + margen.
##
## Para actualizar el contenido: llamar mark_dirty() — encola un queue_redraw().
## Para seguir la cámara: llamar check_viewport() desde _process() del consumidor.

var _grid: HexGrid
var _hex_size: float
## Callable inyectado por HexRenderer. Firma: (layer, grid, hex_size, min_coord, max_coord) → void.
var _draw_fn: Callable
var _viewport_origin: Vector2 = Vector2.INF
var _dirty: bool = true


## Crea la capa batch vinculada a [param grid] con el [param hex_size] dado.
## [param draw_fn] es el callable que implementa el dibujo — provisto por HexRenderer.
func _init(grid: HexGrid, hex_size: float, draw_fn: Callable) -> void:
	_grid = grid
	_hex_size = hex_size
	_draw_fn = draw_fn


## Calcula el AABB del viewport con margen de un hex y llama a _draw_fn
## solo para las coordenadas dentro del área visible. Evita dibujar hexes fuera de pantalla.
func _draw() -> void:
	if not _draw_fn.is_valid() or not _grid:
		return
	var viewport := get_viewport()
	if not viewport:
		return

	var canvas := viewport.canvas_transform
	var zoom := canvas.get_scale()
	if zoom.x == 0.0 or zoom.y == 0.0:
		return
	var screen_size := viewport.get_visible_rect().size
	var visible := Rect2(-canvas.origin / zoom, screen_size / zoom)
	visible = visible.grow(_hex_size * 2.0)

	var min_coord := HexGrid.pixel_to_offset(visible.position, _hex_size)
	var max_coord := HexGrid.pixel_to_offset(visible.end, _hex_size)
	min_coord = Vector2i(maxi(min_coord.x - 1, 0), maxi(min_coord.y - 1, 0))
	max_coord = Vector2i(mini(max_coord.x + 1, _grid.width - 1), mini(max_coord.y + 1, _grid.height - 1))

	_draw_fn.call(self, _grid, _hex_size, min_coord, max_coord)
	_dirty = false


## Marca la capa como sucia y encola un redraw en el próximo frame.
func mark_dirty() -> void:
	_dirty = true
	queue_redraw()


## Llamar en _process() del consumidor. Solo marca dirty si la cámara se movió
## más de 1 hex desde el último redraw.
func check_viewport() -> void:
	var viewport := get_viewport()
	if not viewport:
		return
	var origin := viewport.canvas_transform.origin
	if _viewport_origin == Vector2.INF:
		_viewport_origin = origin
		return
	var delta := (origin - _viewport_origin).abs()
	var threshold := _hex_size * 1.5
	if delta.x > threshold or delta.y > threshold:
		_viewport_origin = origin
		mark_dirty()
