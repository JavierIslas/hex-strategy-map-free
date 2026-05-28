class_name HexCell
extends RefCounted
## Modelo de datos de una celda hexagonal.
##
## HexGrid crea y almacena las celdas — rara vez se instancian a mano.
## Centraliza el tipo de terreno, estado de niebla por jugador, y datos
## genéricos de juego (tag, metadata, location_type/location_data).
##
## Niebla por jugador: mark_explored/mark_visible/clear_visible y los
## predicados is_*_by reciben un player_id. Usar 0 para single-player.
## get_fog_state() combina ambos estados en un FogState ordinal.

## Tipos de terreno integrados. Son enteros — se pueden extender con
## constantes propias sin modificar el addon.
## El costo de cada terreno lo define HexGrid.terrain_cost.
enum Terrain {
	ROAD,      ## Camino (costo por defecto 1.0).
	PLAINS,    ## Llanura (costo por defecto 1.5).
	FOREST,    ## Bosque (costo por defecto 2.0).
	MOUNTAIN,  ## Montaña (costo por defecto 3.0).
	WATER,     ## Agua — intransitable por defecto (costo -1.0).
}

## Coordenada offset (x = columna, y = fila) de la celda en el HexGrid.
var coord: Vector2i = Vector2i.ZERO
## Tipo de terreno activo. Uno de Terrain.* o una constante entera propia.
var terrain: int = Terrain.PLAINS
## Tipo de locación. 0 = sin locación. Definir con constantes propias (1 = ciudad, 2 = dungeon…).
var location_type: int = 0
## Datos adjuntos a la locación. El addon no los interpreta — estructura libre de juego a juego.
var location_data: Dictionary = {}
var _explored_by: Dictionary = {}   # player_id (int) → bool
var _visible_by: Dictionary = {}    # player_id (int) → bool
## Etiqueta entera genérica (equipo, facción, dueño…). 0 = sin etiqueta.
var tag: int = 0
## Metadatos libres de juego. El addon no los lee ni escribe — estructura libre.
var metadata: Dictionary = {}
## Elevación de la celda. 0.0 = nivel del mar. Usada por LOS con elevación (HexGrid.get_line_of_sight).
var elevation: float = 0.0


## Crea la celda en [param cell_coord] con [param cell_terrain].
## HexGrid llama a este método internamente durante generate_cells().
func _init(cell_coord: Vector2i = Vector2i.ZERO, cell_terrain: int = Terrain.PLAINS) -> void:
	coord = cell_coord
	terrain = cell_terrain


## Retorna la posición pixel del centro de esta celda.
## Equivalente a HexGrid.offset_to_pixel(coord).
func get_pixel_position() -> Vector2:
	return HexGrid.offset_to_pixel(coord)


## Retorna true si location_type indica una locación válida (> 0).
func has_location() -> bool:
	return location_type > 0


## Retorna true si tag != 0 (la celda tiene una etiqueta asignada).
func has_tag() -> bool:
	return tag != 0


## Retorna true si [param player_id] exploró esta celda al menos una vez.
## Una celda explorada puede seguir en niebla (EXPLORED) si salió del rango de visión.
## Hot path: validación inline (player_id < 0) — un wrapper de helper agregaba ~0.15µs/call.
func is_explored_by(player_id: int) -> bool:
	if player_id < 0:
		return false
	return _explored_by.get(player_id, false)


## Retorna true si [param player_id] tiene visión activa sobre esta celda.
## La visión activa se pierde al llamar clear_visible() — típicamente al inicio de turno.
## Hot path: validación inline.
func is_visible_by(player_id: int) -> bool:
	if player_id < 0:
		return false
	return _visible_by.get(player_id, false)


## Marca la celda como explorada por [param player_id]. La exploración es permanente.
## También llamar mark_visible() si el jugador actualmente tiene visión sobre ella.
func mark_explored(player_id: int) -> void:
	if not _assert_valid_player_id(player_id):
		return
	_explored_by[player_id] = true


## Marca la celda como actualmente visible por [param player_id].
## No implica que esté explorada — llamar mark_explored() en paralelo si corresponde.
func mark_visible(player_id: int) -> void:
	if not _assert_valid_player_id(player_id):
		return
	_visible_by[player_id] = true


## Elimina la visión activa de [param player_id]. La celda queda EXPLORED si fue vista antes.
## Llamar al inicio de cada turno antes de recalcular la visibilidad.
func clear_visible(player_id: int) -> void:
	if not _assert_valid_player_id(player_id):
		return
	_visible_by.erase(player_id)


## Retorna el FogState consolidado para [param player_id].
## Prioridad: VISIBLE > EXPLORED > HIDDEN. Usar player_id = 0 para single-player.
## Hot path: lee los dicts directamente (saltea is_visible_by/is_explored_by) y
## valida inline. Cada wrapper agregaba ~0.15µs/call (medido) y get_fog_state se
## llama hasta N veces por frame en update_fog.
func get_fog_state(player_id: int = 0) -> int:
	if player_id < 0:
		return FogState.HIDDEN
	if _visible_by.get(player_id, false):
		return FogState.VISIBLE
	if _explored_by.get(player_id, false):
		return FogState.EXPLORED
	return FogState.HIDDEN


# Valida player_id >= 0 — emite push_error y retorna false si es inválido.
static func _assert_valid_player_id(player_id: int) -> bool:
	if player_id < 0:
		push_error("HexCell: player_id debe ser >= 0, recibido %d" % player_id)
		return false
	return true


## Serializa la celda a un Dictionary compatible con JSON.
## Reconstruir con HexCell.deserialize(data).
## Nota: _visible_by no se incluye — la visibilidad activa se recalcula al cargar.
func serialize() -> Dictionary:
	var explored_serial: Dictionary = {}
	for pid in _explored_by:
		explored_serial[str(pid)] = _explored_by[pid]
	return {
		"coord": [coord.x, coord.y],
		"terrain": terrain,
		"location_type": location_type,
		"location_data": location_data,
		"explored_by": explored_serial,
		"tag": tag,
		"metadata": metadata,
		"elevation": elevation,
	}


## Convierte un Array [x, y] a Vector2i. Retorna [param default] si el array es inválido.
static func parse_coord_array(arr, default: Vector2i = Vector2i.ZERO) -> Vector2i:
	if arr is Array and arr.size() >= 2:
		return Vector2i(int(arr[0]), int(arr[1]))
	return default


static func _parse_coord(data: Dictionary, key: String, default: Vector2i = Vector2i.ZERO) -> Vector2i:
	return parse_coord_array(data.get(key, [0, 0]), default)


## Reconstruye una HexCell desde un Dictionary generado por serialize().
static func deserialize(data: Dictionary) -> HexCell:
	var cell_coord := _parse_coord(data, "coord")
	var cell := HexCell.new(cell_coord, data.get("terrain", Terrain.PLAINS))
	cell.location_type = data.get("location_type", 0)
	cell.location_data = data.get("location_data", {})
	var explored_raw: Dictionary = data.get("explored_by", {})
	for key in explored_raw:
		cell.mark_explored(int(key))
	cell.tag = data.get("tag", 0)
	cell.metadata = data.get("metadata", {})
	cell.elevation = data.get("elevation", 0.0)
	return cell
