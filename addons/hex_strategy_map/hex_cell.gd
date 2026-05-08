class_name HexCell
extends RefCounted
## Celda individual del grid hexagonal.

enum Terrain {
	ROAD,
	PLAINS,
	FOREST,
	MOUNTAIN,
	WATER,
}

var coord: Vector2i = Vector2i.ZERO
var terrain: int = Terrain.PLAINS
var location_type: int = 0  # 0 = sin locación. Valor genérico, reemplazable por tag/metadata.
var location_data: Dictionary = {}
var _explored_by: Dictionary = {}   # player_id (int) → bool
var _visible_by: Dictionary = {}    # player_id (int) → bool
var tag: int = 0
var metadata: Dictionary = {}


func _init(cell_coord: Vector2i = Vector2i.ZERO, cell_terrain: int = Terrain.PLAINS) -> void:
	coord = cell_coord
	terrain = cell_terrain


func get_pixel_position() -> Vector2:
	return HexGrid.offset_to_pixel(coord)


func has_location() -> bool:
	return location_type != 0 and location_type >= 0


func has_tag() -> bool:
	return tag != 0


func is_explored_by(player_id: int) -> bool:
	return _explored_by.get(player_id, false)


func is_visible_by(player_id: int) -> bool:
	return _visible_by.get(player_id, false)


func mark_explored(player_id: int) -> void:
	_explored_by[player_id] = true


func mark_visible(player_id: int) -> void:
	_visible_by[player_id] = true


func clear_visible(player_id: int) -> void:
	_visible_by.erase(player_id)


func get_fog_state(player_id: int = 0) -> int:
	if is_visible_by(player_id):
		return FogState.VISIBLE
	if is_explored_by(player_id):
		return FogState.EXPLORED
	return FogState.HIDDEN


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
