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
	return location_type != 0 and location_type >= 0


## Retorna true si tag != 0 (la celda tiene una etiqueta asignada).
func has_tag() -> bool:
	return tag != 0


## Retorna true si [param player_id] exploró esta celda al menos una vez.
## Una celda explorada puede seguir en niebla (EXPLORED) si salió del rango de visión.
func is_explored_by(player_id: int) -> bool:
	return _explored_by.get(player_id, false)


## Retorna true si [param player_id] tiene visión activa sobre esta celda.
## La visión activa se pierde al llamar clear_visible() — típicamente al inicio de turno.
func is_visible_by(player_id: int) -> bool:
	return _visible_by.get(player_id, false)


## Marca la celda como explorada por [param player_id]. La exploración es permanente.
## También llamar mark_visible() si el jugador actualmente tiene visión sobre ella.
func mark_explored(player_id: int) -> void:
	_explored_by[player_id] = true


## Marca la celda como actualmente visible por [param player_id].
## No implica que esté explorada — llamar mark_explored() en paralelo si corresponde.
func mark_visible(player_id: int) -> void:
	_visible_by[player_id] = true


## Elimina la visión activa de [param player_id]. La celda queda EXPLORED si fue vista antes.
## Llamar al inicio de cada turno antes de recalcular la visibilidad.
func clear_visible(player_id: int) -> void:
	_visible_by.erase(player_id)


## Retorna el FogState consolidado para [param player_id].
## Prioridad: VISIBLE > EXPLORED > HIDDEN. Usar player_id = 0 para single-player.
func get_fog_state(player_id: int = 0) -> int:
	if is_visible_by(player_id):
		return FogState.VISIBLE
	if is_explored_by(player_id):
		return FogState.EXPLORED
	return FogState.HIDDEN


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
	}


static func _parse_coord(data: Dictionary, key: String, default: Vector2i = Vector2i.ZERO) -> Vector2i:
	var raw = data.get(key, [0, 0])
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return default


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
	return cell
