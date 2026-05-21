class_name FogOfWar
extends RefCounted
## Sistema de niebla de guerra multi-jugador con tres estados.
##
## Gestiona qué hexes están HIDDEN, EXPLORED o VISIBLE para cada jugador.
## Los estados se almacenan en las HexCell del grid (mark_explored/mark_visible),
## y en _visible_by_player para poder limpiar la visión activa al inicio de turno.
##
## Flujo típico por turno:
##   fog.update_visibility(player_id, unit_pos, radius)
##   renderer.update_fog(hex_container, grid, player_id)
##
## Para múltiples unidades en el mismo turno, usar update_visibility_multi()
## que hace un solo pase de limpieza antes de revelar todas las posiciones.
##
## LOS (line-of-sight): reveal_with_los() usa HexGrid.get_visible_cells()
## para bloquear la visión detrás de terrenos específicos.

## Emitida cuando el estado de niebla de una celda cambia para un jugador.
## Útil para actualizar el renderer de forma incremental sin recorrer todo el grid.
signal fog_changed(player_id: int, coord: Vector2i, old_state: int, new_state: int)

## Grid hexagonal asociado. No cambia después de _init.
## Todos los métodos públicos hacen guard "if grid == null: return" — invariante de clase.
var grid: HexGrid = null
var _visible_by_player: Dictionary = {}  # player_id (int) → Dictionary (Vector2i → true)
var _visibility_radius_fn: Callable


## Crea el sistema de niebla vinculado a [param hex_grid].
## [param visibility_fn]: (unit_level: int) → int — radio de visión según nivel.
## Si se omite, usa _default_visibility_radius (escala logarítmica, máx 3).
func _init(hex_grid: HexGrid, visibility_fn: Callable = Callable()) -> void:
	grid = hex_grid
	_visibility_radius_fn = visibility_fn


## Retorna el estado de niebla de [param cell] para [param player_id] sin instanciar FogOfWar.
## Útil cuando solo se necesita leer el estado sin gestionar revelado.
static func get_state(cell: HexCell, player_id: int = 0) -> int:
	if cell == null:
		return FogState.HIDDEN
	if cell.is_visible_by(player_id):
		return FogState.VISIBLE
	if cell.is_explored_by(player_id):
		return FogState.EXPLORED
	return FogState.HIDDEN


## Retorna el radio de visión para [param unit_level] usando la función inyectada,
## o _default_visibility_radius si no se proporcionó ninguna.
func get_visibility_radius(unit_level: int) -> int:
	if _visibility_radius_fn.is_valid():
		return _visibility_radius_fn.call(unit_level)
	return _default_visibility_radius(unit_level)


## Revela un área circular de [param radius] hexes alrededor de [param center]
## para [param player_id]. No considera LOS — todos los hexes del anillo quedan VISIBLE.
## Para LOS, usar reveal_with_los().
func reveal_around(player_id: int, center: Vector2i, radius: int) -> void:
	if grid == null:
		return
	_reveal_coord(player_id, center)
	for r in range(1, radius + 1):
		var ring := grid.get_ring(center, r)
		for coord in ring:
			_reveal_coord(player_id, coord)


## Revela los hexes visibles desde [param center] con radio [param radius] y LOS.
## [param blocking_terrains]: terrenos que bloquean la visión (ej. MOUNTAIN, FOREST).
## [param elevation_fn]: (coord: Vector2i) → float — elevación por celda para LOS con altura.
## Hexes bloqueados por terreno no quedan VISIBLE (sí pueden quedar EXPLORED de antes).
func reveal_with_los(player_id: int, center: Vector2i, radius: int,
		blocking_terrains: Array[int] = [], elevation_fn: Callable = Callable()) -> void:
	if grid == null:
		return
	var visible := grid.get_visible_cells(center, radius, blocking_terrains, elevation_fn)
	for coord in visible:
		_reveal_coord(player_id, coord)


## Limpia la visión activa de [param player_id] y revela alrededor de una sola unidad.
## Para múltiples unidades en el mismo turno, preferir update_visibility_multi().
func update_visibility(player_id: int, unit_pos: Vector2i, radius: int) -> void:
	update_visibility_multi(player_id, [unit_pos], func(_pos: Vector2i) -> int: return radius)


## Limpia la visión activa de [param player_id] y revela alrededor de múltiples posiciones.
## [param radius_fn]: (pos: Vector2i) → int — radio por posición (permite radios variables).
## Hace un solo pase de limpieza, más eficiente que llamar update_visibility() N veces.
func update_visibility_multi(player_id: int, positions: Array[Vector2i], radius_fn: Callable) -> void:
	if grid == null:
		return
	_clear_visible(player_id)
	for pos in positions:
		var radius: int = radius_fn.call(pos)
		reveal_around(player_id, pos, radius)


## Retorna cuántas celdas del grid exploró [param player_id] (incluyendo las actualmente visibles).
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


## Serializa el estado de niebla a Dictionary compatible con JSON.
## Solo se guarda _visible_by_player — los explored_by viven en las HexCell
## y se serializan con HexGrid.serialize().
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
	return HexCell.parse_coord_array(pair)


## Reconstruye un FogOfWar desde un Dictionary generado por serialize().
## [param hex_grid] debe ser el mismo grid (ya deserializado con HexGrid.deserialize()).
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


## Radio por defecto según nivel: escala lentamente (máx 3). Nivel 1 → 1, nivel 3 → 2, nivel 5 → 3.
static func _default_visibility_radius(unit_level: int) -> int:
	return mini(1 + floori(float(unit_level - 1) / 2.0), 3)


## Captura el estado antes y después de mutar, y emite fog_changed solo si cambió.
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
