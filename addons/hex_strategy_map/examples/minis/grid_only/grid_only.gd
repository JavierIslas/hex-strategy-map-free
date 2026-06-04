extends Node2D
## Demo: HexGrid + HexRenderer.
## Muestra un grid de 10x10 con terrenos mixtos.
## Click en un hex muestra info de la celda en el label (via cell_pressed signal).

var grid: HexGrid
var renderer: HexRenderer
var camera_ctrl: MapCamera

@onready var hex_container: Node2D = $HexContainer
@onready var camera: Camera2D = $Camera
@onready var info_label: Label = $UI/InfoLabel


func _ready() -> void:
	grid = HexGrid.new(10, 10)
	grid.generate_cells()
	_scatter_terrain()

	renderer = HexRenderer.new()
	renderer.cell_pressed.connect(_on_cell_pressed)
	for coord in grid.cells:
		renderer.create_hex_visual(hex_container, coord, HexGrid.offset_to_pixel(coord), grid.cells[coord])
	_hide_fog_overlays()

	camera_ctrl = MapCamera.new(camera, get_viewport())
	camera.position = HexGrid.offset_to_pixel(Vector2i(5, 5))


func _process(delta: float) -> void:
	camera_ctrl.process(delta, camera.position)


func _input(event: InputEvent) -> void:
	camera_ctrl.handle_input(event)


func _on_cell_pressed(coord: Vector2i, event: InputEvent) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		_show_cell_info(coord)


func _hide_fog_overlays() -> void:
	for coord in grid.cells:
		var fog := HexRenderer.get_visual_part(hex_container, coord, "Fog")
		if fog:
			fog.visible = false


func _scatter_terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	for coord in grid.cells:
		var roll := rng.randf()
		if roll < 0.10:
			grid.set_terrain(coord, HexCell.Terrain.WATER)
		elif roll < 0.25:
			grid.set_terrain(coord, HexCell.Terrain.MOUNTAIN)
		elif roll < 0.45:
			grid.set_terrain(coord, HexCell.Terrain.FOREST)
		elif roll < 0.55:
			grid.set_terrain(coord, HexCell.Terrain.ROAD)
		else:
			grid.set_terrain(coord, HexCell.Terrain.PLAINS)


func _show_cell_info(coord: Vector2i) -> void:
	if not grid.is_valid(coord):
		return
	var cell := grid.get_cell(coord)
	var cost := grid.get_movement_cost(coord)
	var terrain_name := _terrain_name(cell.terrain)
	info_label.text = tr("Coord: (%d, %d) | Terreno: %s | Costo: %.1f") % [coord.x, coord.y, terrain_name, cost]


func _terrain_name(t: int) -> String:
	match t:
		HexCell.Terrain.ROAD: return tr("Camino")
		HexCell.Terrain.PLAINS: return tr("Llanura")
		HexCell.Terrain.FOREST: return tr("Bosque")
		HexCell.Terrain.MOUNTAIN: return tr("Montaña")
		HexCell.Terrain.WATER: return tr("Agua")
		_: return tr("???")
