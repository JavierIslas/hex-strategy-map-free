class_name FogOfWar
extends RefCounted
## Sistema de niebla de guerra. Gestiona qué hexes están explorados y visibles por jugador.

signal fog_changed(player_id: int, coord: Vector2i, old_state: int, new_state: int)

var grid: HexGrid = null
var _visible_by_player: Dictionary = {}  # player_id (int) → Dictionary (Vector2i → true)
var _visibility_radius_fn: Callable


func _init(hex_grid: HexGrid, visibility_fn: Callable = Callable()) -> void:
	grid = hex_grid
	_visibility_radius_fn = visibility_fn


static func get_state(cell: HexCell, player_id: int = 0) -> int:
	if cell == null:
		return FogState.HIDDEN
	if cell.is_visible_by(player_id):
		return FogState.VISIBLE
	if cell.is_explored_by(player_id):
		return FogState.EXPLORED
	return FogState.HIDDEN


func get_visibility_radius(unit_level: int) -> int:
	if _visibility_radius_fn.is_valid():
		return _visibility_radius_fn.call(unit_level)
	return _default_visibility_radius(unit_level)


func reveal_around(player_id: int, center: Vector2i, radius: int) -> void:
	if grid == null:
		return
	_reveal_coord(player_id, center)
	for r in range(1, radius + 1):
		var ring := grid.get_ring(center, r)
		for coord in ring:
			_reveal_coord(player_id, coord)


func reveal_with_los(player_id: int, center: Vector2i, radius: int,
		blocking_terrains: Array[int] = []) -> void:
	if grid == null:
		return
	var visible := grid.get_visible_cells(center, radius, blocking_terrains)
	for coord in visible:
		_reveal_coord(player_id, coord)


func update_visibility(player_id: int, unit_pos: Vector2i, radius: int) -> void:
	update_visibility_multi(player_id, [unit_pos], func(_pos: Vector2i) -> int: return radius)


func update_visibility_multi(player_id: int, positions: Array[Vector2i], radius_fn: Callable) -> void:
	if grid == null:
		return
	_clear_visible(player_id)
	for pos in positions:
		var radius: int = radius_fn.call(pos)
		reveal_around(player_id, pos, radius)


func get_explored_count(player_id: int = 0) -> int:
	if grid == null:
		return 0
	var count := 0
	var all_cells := grid.get_all_cells()
	for coord in all_cells:
		var cell: HexCell = all_cells[coord]
		if cell.is_explored_by(player_id):
			count += 1
	return count


func serialize() -> Dictionary:
	var visible_data: Array = []
	for player_id in _visible_by_player:
		var coords: Dictionary = _visible_by_player[player_id]
		var coord_list: Array = []
		for coord in coords.keys():
			coord_list.append([coord.x, coord.y])
		visible_data.append({"player_id": player_id, "coords": coord_list})
	return {"visible_by_player": visible_data}


static func _parse_coord_pair(pair) -> Vector2i:
	if pair is Array and pair.size() >= 2:
		return Vector2i(int(pair[0]), int(pair[1]))
	return Vector2i.ZERO


static func deserialize(data: Dictionary, hex_grid: HexGrid) -> FogOfWar:
	var fog := FogOfWar.new(hex_grid)
	var visible_data: Array = data.get("visible_by_player", [])
	for entry in visible_data:
		var player_id: int = int(entry.get("player_id", 0))
		var coord_pairs: Array = entry.get("coords", [])
		fog._visible_by_player[player_id] = {}
		for pair in coord_pairs:
			var coord := _parse_coord_pair(pair)
			fog._visible_by_player[player_id][coord] = true
			var cell := hex_grid.get_cell(coord)
			if cell:
				cell.mark_explored(player_id)
				cell.mark_visible(player_id)
	return fog


static func _default_visibility_radius(unit_level: int) -> int:
	return mini(1 + floori(float(unit_level - 1) / 2.0), 3)


func _emit_state_change(cell: HexCell, player_id: int, coord: Vector2i, mutate: Callable) -> void:
	var old_state := get_state(cell, player_id)
	mutate.call()
	var new_state := get_state(cell, player_id)
	if old_state != new_state:
		fog_changed.emit(player_id, coord, old_state, new_state)


func _reveal_coord(player_id: int, coord: Vector2i) -> void:
	var cell := grid.get_cell(coord)
	if not cell:
		return
	_emit_state_change(cell, player_id, coord, func() -> void:
		cell.mark_explored(player_id)
		cell.mark_visible(player_id)
	)
	if not _visible_by_player.has(player_id):
		_visible_by_player[player_id] = {}
	_visible_by_player[player_id][coord] = true


func _clear_visible(player_id: int) -> void:
	if not _visible_by_player.has(player_id):
		return
	for coord in _visible_by_player[player_id]:
		var cell := grid.get_cell(coord)
		if cell:
			_emit_state_change(cell, player_id, coord, func() -> void:
				cell.clear_visible(player_id)
			)
	_visible_by_player[player_id] = {}
