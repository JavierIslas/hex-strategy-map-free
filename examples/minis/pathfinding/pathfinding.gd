extends Node2D
## Demo: PathFinder visual — Dijkstra y A*.
## Click para seleccionar origen (verde), click para seleccionar destino (rojo).
## El camino se dibuja como highlight amarillo. Label muestra costo total.
## Tab: cambiar entre modos.

enum Mode { DIJKSTRA_LIMITED, ASTAR, DIJKSTRA_UNLIMITED }

var grid: HexGrid
var renderer: HexRenderer
var camera_ctrl: MapCamera

var origin: Vector2i = Vector2i(-1, -1)
var dest: Vector2i = Vector2i(-1, -1)
var mode: int = Mode.DIJKSTRA_LIMITED

@onready var hex_container: Node2D = $HexContainer
@onready var camera: Camera2D = $Camera
@onready var info_label: Label = $UI/InfoLabel
@onready var mode_label: Label = $UI/ModeLabel


func _ready() -> void:
	grid = HexGrid.new(12, 12)
	grid.generate_cells()
	_scatter_terrain()

	renderer = HexRenderer.new()
	renderer.cell_pressed.connect(_on_cell_pressed)
	for coord in grid.cells:
		renderer.create_hex_visual(hex_container, coord, HexGrid.offset_to_pixel(coord), grid.cells[coord])
	_hide_fog_overlays()

	camera_ctrl = MapCamera.new(camera, get_viewport())
	camera.position = HexGrid.offset_to_pixel(Vector2i(6, 6))
	_update_mode_label()


func _process(delta: float) -> void:
	camera_ctrl.process(delta, camera.position)


func _input(event: InputEvent) -> void:
	camera_ctrl.handle_input(event)

	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		mode = (mode + 1) % 3
		_update_mode_label()
		_refresh_path()


func _on_cell_pressed(coord: Vector2i, event: InputEvent) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not grid.is_valid(coord):
		return
	if not grid.is_passable(coord):
		info_label.text = tr("Ese hex no es pasable (%s)") % coord
		return

	if origin == Vector2i(-1, -1):
		origin = coord
		dest = Vector2i(-1, -1)
		renderer.refresh_cell_color(hex_container, coord, grid.get_cell(coord))
		var bg := HexRenderer.get_visual_part(hex_container, coord, "Bg")
		if bg:
			bg.color = Color(0.2, 0.8, 0.2, 0.5)
		info_label.text = tr("Origen: %s — ahora click destino") % coord
	else:
		dest = coord
		_refresh_path()


func _refresh_path() -> void:
	_reset_all_colors()

	if origin == Vector2i(-1, -1) or dest == Vector2i(-1, -1):
		return

	var path: Array[Vector2i]
	var algo_name: String

	match mode:
		Mode.DIJKSTRA_LIMITED:
			algo_name = "Dijkstra"
			var reachable := PathFinder.find_reachable(origin, 15.0, grid)
			if not reachable.has(dest):
				info_label.text = tr("Destino fuera de alcance (max 15 pts)")
				_set_temp_color(origin, Color(0.2, 0.8, 0.2, 0.5))
				_set_temp_color(dest, Color(0.8, 0.2, 0.2, 0.5))
				return
			path = PathFinder.find_path(origin, dest, grid, reachable)

		Mode.ASTAR:
			algo_name = "A*"
			path = PathFinder.find_path_astar(origin, dest, grid)

		Mode.DIJKSTRA_UNLIMITED:
			algo_name = "Dijkstra Unlimited"
			path = PathFinder.find_path(origin, dest, grid)

	if path.is_empty():
		info_label.text = tr("No hay camino entre %s y %s") % [origin, dest]
		_set_temp_color(origin, Color(0.2, 0.8, 0.2, 0.5))
		_set_temp_color(dest, Color(0.8, 0.2, 0.2, 0.5))
		return

	var total_cost := 0.0
	for i in path.size():
		var step_cost := grid.get_movement_cost(path[i])
		if i > 0:
			step_cost += grid.get_edge_cost(path[i - 1], path[i])
			total_cost += step_cost
		if path[i] == origin:
			_set_temp_color(path[i], Color(0.2, 0.8, 0.2, 0.5))
		elif path[i] == dest:
			_set_temp_color(path[i], Color(0.8, 0.2, 0.2, 0.5))
		else:
			_set_temp_color(path[i], Color(0.9, 0.85, 0.3, 0.4))

	info_label.text = tr("%s: %d pasos | Costo: %.1f | %s → %s") % [
		algo_name, path.size(), total_cost, origin, dest
	]


func _scatter_terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for coord in grid.cells:
		var roll := rng.randf()
		if roll < 0.08:
			grid.set_terrain(coord, HexCell.Terrain.WATER)
		elif roll < 0.20:
			grid.set_terrain(coord, HexCell.Terrain.MOUNTAIN)
		elif roll < 0.40:
			grid.set_terrain(coord, HexCell.Terrain.FOREST)
		elif roll < 0.50:
			grid.set_terrain(coord, HexCell.Terrain.ROAD)
		else:
			grid.set_terrain(coord, HexCell.Terrain.PLAINS)


func _reset_all_colors() -> void:
	for coord in grid.cells:
		renderer.refresh_cell_color(hex_container, coord, grid.get_cell(coord))


func _set_temp_color(coord: Vector2i, color: Color) -> void:
	var bg := HexRenderer.get_visual_part(hex_container, coord, "Bg")
	if bg:
		bg.color = color


func _hide_fog_overlays() -> void:
	for coord in grid.cells:
		var fog := HexRenderer.get_visual_part(hex_container, coord, "Fog")
		if fog:
			fog.visible = false


func _update_mode_label() -> void:
	var names := ["Dijkstra (max 15 pts)", "A*", "Dijkstra Unlimited"]
	mode_label.text = tr("Modo: %s (Tab para cambiar)") % tr(names[mode])
