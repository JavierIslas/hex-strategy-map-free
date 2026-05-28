extends Node2D
## Demo FREE — Exploración con niebla de guerra y pathfinding.
## Usa solo módulos FREE: HexGrid, HexRenderer, FogOfWar, PathFinder, MapCamera.
## Click para mover el cursor por el mapa. La niebla se revela al explorar.
## L: toggle visión LOS | Der+drag: pan | Scroll: zoom

const MAP_WIDTH := 14
const MAP_HEIGHT := 12
const VISIBILITY := 3
const MOVEMENT_POINTS := 12.0
const MOVE_SPEED := 300.0

@onready var hex_container: Node2D = $HexContainer
@onready var camera: Camera2D = $Camera
@onready var info_label: Label = $UI/InfoLabel
@onready var explored_label: Label = $UI/ExploredLabel

var grid: HexGrid
var renderer: HexRenderer
var fog: FogOfWar
var camera_ctrl: MapCamera

var player_pos: Vector2i
var movement_points: float = MOVEMENT_POINTS
var highlighted: Dictionary = {}
var _reachable: Dictionary = {}
var _path_cache: Array[Vector2i] = []
var _cursor: ColorRect
var _show_los: bool = false


func _ready() -> void:
	grid = HexGrid.new(MAP_WIDTH, MAP_HEIGHT)
	grid.generate_cells()
	_scatter_terrain()

	var fog_material := HexRenderer.create_default_fog_material()
	renderer = HexRenderer.new(HexPalette.new(), HexGrid.HEX_SIZE, {
		"cell_icon_fn": _cell_icon,
		"fog_material": fog_material,
	})
	renderer.cell_pressed.connect(_on_cell_pressed)

	fog = FogOfWar.new(grid)

	player_pos = Vector2i(MAP_WIDTH / 2, MAP_HEIGHT / 2)
	_ensure_passable()

	for coord in grid.cells:
		renderer.create_hex_visual(hex_container, coord, HexGrid.offset_to_pixel(coord), grid.cells[coord])

	fog.update_visibility(0, player_pos, VISIBILITY)
	renderer.update_fog(hex_container, grid, 0)

	_create_cursor()
	camera_ctrl = MapCamera.new(camera, get_viewport())
	camera.position = HexGrid.offset_to_pixel(player_pos)
	_update_highlights()
	_update_ui()


func _process(delta: float) -> void:
	camera_ctrl.process(delta, HexGrid.offset_to_pixel(player_pos))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		_show_los = not _show_los
		if _show_los:
			_update_los_highlight()
		else:
			renderer.update_los_highlight(hex_container, [], [])
			_update_highlights()
		_update_ui()
		return
	camera_ctrl.handle_input(event)


# --- Terrain generation ---

func _scatter_terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = randi() % 9999
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


func _ensure_passable() -> void:
	if not grid.is_passable(player_pos):
		grid.set_terrain(player_pos, HexCell.Terrain.PLAINS)


func _cell_icon(cell: HexCell) -> String:
	match cell.terrain:
		HexCell.Terrain.FOREST: return "♣"
		HexCell.Terrain.MOUNTAIN: return "▲"
		HexCell.Terrain.WATER: return "~"
		_: return ""


# --- Cursor ---

func _create_cursor() -> void:
	_cursor = ColorRect.new()
	_cursor.size = Vector2(10, 10)
	_cursor.color = Color(1.0, 0.9, 0.2)
	_cursor.position = HexGrid.offset_to_pixel(player_pos) - Vector2(5, 5)
	$CursorContainer.add_child(_cursor)


# --- Interaction ---

func _on_cell_pressed(coord: Vector2i, _event: InputEvent) -> void:
	_try_move(coord)


func _try_move(coord: Vector2i) -> void:
	if not grid.is_valid(coord) or not grid.is_passable(coord):
		return

	var path := PathFinder.find_path(player_pos, coord, grid)
	if path.is_empty():
		info_label.text = tr("No hay camino hacia %s") % coord
		return

	var cost := 0.0
	for i in range(1, path.size()):
		cost += grid.get_movement_cost(path[i]) + grid.get_edge_cost(path[i - 1], path[i])

	if cost > movement_points:
		info_label.text = tr("Alcanza para llegar (necesita %.1f, tiene %.1f)") % [cost, movement_points]
		return

	movement_points -= cost
	player_pos = coord
	_cursor.position = HexGrid.offset_to_pixel(coord) - Vector2(5, 5)

	fog.update_visibility(0, coord, VISIBILITY)
	renderer.update_fog(hex_container, grid, 0)

	if _show_los:
		_update_los_highlight()
	else:
		_update_highlights()
	_update_ui()


func _reset_turn() -> void:
	movement_points = MOVEMENT_POINTS
	_update_highlights()
	_update_ui()


# --- Highlights ---

func _update_highlights() -> void:
	_reachable = PathFinder.find_reachable(player_pos, movement_points, grid)
	renderer.update_reachable_highlight(hex_container, grid, _reachable, highlighted)


func _update_los_highlight() -> void:
	var visible := grid.get_visible_cells(player_pos, VISIBILITY, [HexCell.Terrain.MOUNTAIN])
	var blocked := grid.get_blocked_cells(player_pos, VISIBILITY, [HexCell.Terrain.MOUNTAIN])
	renderer.update_los_highlight(hex_container, visible, blocked)


# --- UI ---

func _update_ui() -> void:
	var explored := fog.get_explored_count(0)
	var total := grid.cells.size()
	explored_label.text = tr("Explorado: %d/%d (%.0f%%)") % [explored, total, explored * 100.0 / total]

	var cell := grid.get_cell(player_pos)
	var terrain_name := "Llanura"
	match cell.terrain:
		HexCell.Terrain.FOREST: terrain_name = "Bosque"
		HexCell.Terrain.MOUNTAIN: terrain_name = "Montaña"
		HexCell.Terrain.WATER: terrain_name = "Agua"
		HexCell.Terrain.ROAD: terrain_name = "Camino"

	var los_text := " | L: visión" if not _show_los else " | L: reach"
	info_label.text = tr("Pos: %s | %s | Mov: %.1f/%.0f%s") % [
		player_pos, terrain_name, movement_points, MOVEMENT_POINTS, los_text
	]
