class_name HexGrid
extends RefCounted
## Grid hexagonal con coordenadas offset (odd-r, pointy-top).
##
## Fuente de verdad del mapa: almacena celdas, costos de terreno y edges.
## No sabe nada del árbol de escena — solo datos. HexRenderer consume este objeto
## para crear los nodos visuales.
##
## Coordenadas: offset (Vector2i) en la API pública; cube internamente para
## distancias, vecinos y LOS. Convertir con offset_to_cube() si hace falta.
##
## Terreno extensible: terrain_cost acepta cualquier int como clave — definir
## constantes propias junto a los Terrain.* de HexCell para ampliar el sistema.

enum EdgeType {
	NONE,
	RIVER,
	ROAD,
	WALL,
	CUSTOM,
}

const TERRAIN_COST: Dictionary = {
	HexCell.Terrain.ROAD: 1.0,
	HexCell.Terrain.PLAINS: 1.5,
	HexCell.Terrain.FOREST: 2.0,
	HexCell.Terrain.MOUNTAIN: 3.0,
	HexCell.Terrain.WATER: -1.0,
}

const EDGE_COST: Dictionary = {
	EdgeType.RIVER: 2.0,
	EdgeType.WALL: -1.0,
	EdgeType.ROAD: -0.5,
}

## Tamaño del hex en pixels (radio del circunscripto, pointy-top odd-r).
const HEX_SIZE: float = 32.0
## sqrt(3) precalculado para la fórmula de conversión offset↔pixel (pointy-top hexes).
const HEX_SQRT3: float = 1.7320508075688772

var width: int = 0
var height: int = 0
var cells: Dictionary = {}  # Vector2i → HexCell
var edges: Dictionary = {}  # String (edge_key) → Dictionary { type: int, cost: float, ... }
var terrain_cost: Dictionary = {}
var edge_cost: Dictionary = {}
var hex_size: float = 32.0
# Mínimo costo entre los terrenos PRESENTES en cells. Lazy: se calcula
# al primer pedido y se invalida en set_terrain/generate_cells. Computar sobre
# terrain_cost (el dict completo) daría un mínimo más bajo que el real cuando
# el grid sólo usa un subconjunto de terrenos, lo que mantiene la heurística
# admisible pero floja — exactamente lo que find_path_astar quiere evitar.
var _min_passable_terrain_cost_cache: float = -1.0


## Crea el grid con las dimensiones y tablas de costos indicadas.
## [param cost_table]: int → float con el costo de cada terreno. -1.0 = intransitable.
##   Si está vacío, usa TERRAIN_COST por defecto.
## [param size]: radio del hex en píxeles. 0.0 → usa HEX_SIZE (32 px).
## [param edge_cost_table]: int → float con el costo adicional de cada EdgeType.
##   Si está vacío, usa EDGE_COST por defecto.
func _init(map_width: int = 15, map_height: int = 15, cost_table: Dictionary = {}, size: float = 0.0, edge_cost_table: Dictionary = {}) -> void:
	if map_width <= 0 or map_height <= 0:
		push_error("HexGrid: dimensiones inválidas (%d x %d), se usará 15x15" % [map_width, map_height])
		map_width = 15
		map_height = 15
	width = map_width
	height = map_height
	terrain_cost = cost_table if cost_table else TERRAIN_COST
	edge_cost = edge_cost_table if edge_cost_table else EDGE_COST
	hex_size = size if size > 0.0 else HEX_SIZE


## Genera las celdas del grid con [param default_terrain] en todas las posiciones.
## Limpia cualquier celda anterior. Llamar una vez después de _init().
func generate_cells(default_terrain: int = HexCell.Terrain.PLAINS) -> void:
	cells.clear()
	for y in height:
		for x in width:
			var coord := Vector2i(x, y)
			cells[coord] = HexCell.new(coord, default_terrain)
	_min_passable_terrain_cost_cache = -1.0


## Retorna la HexCell en [param coord], o null si la coordenada no existe.
func get_cell(coord: Vector2i) -> HexCell:
	return cells.get(coord, null)


## Retorna el diccionario completo de celdas (Vector2i → HexCell). Solo lectura.
func get_all_cells() -> Dictionary:
	return cells


## Asigna el terreno de la celda en [param coord]. Sin efecto si la coordenada no existe.
func set_terrain(coord: Vector2i, terrain: int) -> void:
	var cell := get_cell(coord)
	if cell:
		cell.terrain = terrain
		_min_passable_terrain_cost_cache = -1.0


## Retorna true si [param coord] existe en el grid (fue generado por generate_cells).
func is_valid(coord: Vector2i) -> bool:
	return cells.has(coord)


## Retorna true si la celda existe y su costo de terreno > 0 (no intransitable).
func is_passable(coord: Vector2i) -> bool:
	return _get_terrain_cost(coord) > 0


## Retorna el costo de movimiento de entrar a [param coord].
## Retorna -1.0 si la celda no existe o el terreno es intransitable.
func get_movement_cost(coord: Vector2i) -> float:
	return _get_terrain_cost(coord)


## Mínimo costo entre los terrenos efectivamente PRESENTES en cells.
## Lazy: se calcula al primer pedido y se invalida cuando cambia el terreno.
## Retorna 1.0 si el grid está vacío o no tiene terrenos pasables.
## PathFinder.find_path_astar lo usa como factor de la heurística para mantener
## admisibilidad sin sacrificar tightness en mapas con un único terreno.
func min_passable_terrain_cost() -> float:
	if _min_passable_terrain_cost_cache < 0.0:
		var min_cost := INF
		for cell: HexCell in cells.values():
			var c: float = terrain_cost.get(cell.terrain, -1.0)
			if c > 0.0 and c < min_cost:
				min_cost = c
		_min_passable_terrain_cost_cache = 1.0 if min_cost == INF else min_cost
	return _min_passable_terrain_cost_cache


## Costo de terreno para [param coord]. -1.0 si la celda no existe o terreno no mapeado.
func _get_terrain_cost(coord: Vector2i) -> float:
	var cell := get_cell(coord)
	if not cell:
		return -1.0
	return terrain_cost.get(cell.terrain, -1.0)


## Retorna el costo adicional del edge entre [param from] y [param to].
## 0.0 si no hay edge definido entre esas celdas.
func get_edge_cost(from: Vector2i, to: Vector2i) -> float:
	var edge := get_edge(from, to)
	return edge.get("cost", 0.0) if not edge.is_empty() else 0.0


# --- Edges ---

## Genera la clave canónica para un edge entre [param a] y [param b].
## La clave es simétrica: edge_key(a, b) == edge_key(b, a).
static func edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


## Define un edge entre [param a] y [param b] del tipo [param edge_type].
## [param properties] puede incluir "cost" para sobreescribir el costo por defecto del EdgeType.
## Si ya existe un edge entre esas celdas, lo reemplaza.
func set_edge(a: Vector2i, b: Vector2i, edge_type: int, properties: Dictionary = {}) -> void:
	var key := edge_key(a, b)
	properties["type"] = edge_type
	if not properties.has("cost"):
		properties["cost"] = _default_edge_cost(edge_type)
	edges[key] = properties


## Retorna el Dictionary del edge entre [param a] y [param b], o {} si no existe.
## El Dictionary incluye al menos "type" (int) y "cost" (float).
func get_edge(a: Vector2i, b: Vector2i) -> Dictionary:
	return edges.get(edge_key(a, b), {})


## Retorna true si hay un edge definido entre [param a] y [param b].
func has_edge(a: Vector2i, b: Vector2i) -> bool:
	return edges.has(edge_key(a, b))


## Elimina el edge entre [param a] y [param b] si existe.
func remove_edge(a: Vector2i, b: Vector2i) -> void:
	edges.erase(edge_key(a, b))


## Retorna todos los edges que tienen a [param coord] como extremo.
## Cada elemento es un Dictionary con "type", "cost", y propiedades extras.
func get_edges_for(coord: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for neighbor in get_neighbors(coord):
		var edge := get_edge(coord, neighbor)
		if not edge.is_empty():
			result.append(edge)
	return result


func _default_edge_cost(edge_type: int) -> float:
	return edge_cost.get(edge_type, 0.0)


## Serializa el grid completo (dimensiones, costos, celdas, edges) a Dictionary JSON.
## Reconstruir con HexGrid.deserialize(data).
func serialize() -> Dictionary:
	var cells_data: Array = []
	for coord in cells:
		cells_data.append(cells[coord].serialize())
	var edges_data: Dictionary = {}
	for key in edges:
		edges_data[key] = edges[key].duplicate()
	return {
		"width": width,
		"height": height,
		"terrain_cost": terrain_cost.duplicate(),
		"edge_cost": edge_cost.duplicate(),
		"hex_size": hex_size,
		"cells": cells_data,
		"edges": edges_data,
	}


## NOTA: JSON serializa int keys como strings. Se reconvierten a int aquí.
static func deserialize(data: Dictionary) -> HexGrid:
	var parsed_terrain_cost: Dictionary = {}
	for key in data.get("terrain_cost", {}):
		parsed_terrain_cost[int(key)] = data["terrain_cost"][key]
	var parsed_edge_cost: Dictionary = {}
	for key in data.get("edge_cost", {}):
		parsed_edge_cost[int(key)] = data["edge_cost"][key]
	var grid := HexGrid.new(data.get("width", 15), data.get("height", 15), parsed_terrain_cost, data.get("hex_size", HEX_SIZE), parsed_edge_cost)
	grid.cells.clear()
	var cells_data: Array = data.get("cells", [])
	for cell_data in cells_data:
		var cell := HexCell.deserialize(cell_data)
		grid.cells[cell.coord] = cell
	var edges_data: Dictionary = data.get("edges", {})
	for key in edges_data:
		var entry = edges_data[key]
		if not entry is Dictionary or not entry.has("type") or not entry.has("cost"):
			push_warning("HexGrid.deserialize: edge inválido '%s' descartado (falta type/cost)" % key)
			continue
		grid.edges[key] = entry
	return grid


# --- Coordenadas ---

## Offset odd-r a pixel (pointy-top hexes).
static func offset_to_pixel(coord: Vector2i, size: float = HEX_SIZE) -> Vector2:
	var x := size * HEX_SQRT3 * (coord.x + 0.5 * (coord.y & 1))
	var y := size * 1.5 * coord.y
	return Vector2(x, y)


## Pixel a offset odd-r más cercano.
static func pixel_to_offset(pixel: Vector2, size: float = HEX_SIZE) -> Vector2i:
	var q: float = (HEX_SQRT3 / 3.0 * pixel.x - 1.0 / 3.0 * pixel.y) / size
	var r: float = (2.0 / 3.0 * pixel.y) / size
	return _cube_to_offset(cube_round(q, r))


## Offset a cube coordinates (para distancia y dirección).
static func offset_to_cube(coord: Vector2i) -> Vector3i:
	var x := coord.x - ((coord.y - (coord.y & 1)) / 2)
	var z := coord.y
	var y := -x - z
	return Vector3i(x, y, z)


## Distancia hex entre dos coordenadas offset.
static func distance(a: Vector2i, b: Vector2i) -> int:
	var ca := offset_to_cube(a)
	var cb := offset_to_cube(b)
	return maxi(absi(ca.x - cb.x), maxi(absi(ca.y - cb.y), absi(ca.z - cb.z)))


## Retorna los 6 vértices de un hexágono pointy-top centrado en (0,0).
## scale_factor < 1.0 encoge el polígono (útil para separación visual).
static func hex_polygon_points(size: float, scale_factor: float = 0.95) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var angle := PI / 3.0 * i - PI / 6.0
		pts.append(Vector2(cos(angle), sin(angle)) * size * scale_factor)
	return pts


## Traslada los puntos de un polígono hex a una posición pixel concreta.
## Helper extraído para evitar el patrón duplicado de `for p in pts: translated.append(p + pixel)`
## en HexRenderer (batch), HexMiniMap, HexMapNode y FogTextureRenderer.
static func translated_hex_polygon(points: PackedVector2Array, pixel: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	for i in points.size():
		result[i] = points[i] + pixel
	return result


## Vecinos de un hex (6 direcciones, odd-r offset).
static func get_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var parity := coord.y & 1
	var dirs: Array[Vector2i]
	if parity == 0:
		dirs = [
			Vector2i(coord.x - 1, coord.y - 1),
			Vector2i(coord.x, coord.y - 1),
			Vector2i(coord.x - 1, coord.y),
			Vector2i(coord.x + 1, coord.y),
			Vector2i(coord.x - 1, coord.y + 1),
			Vector2i(coord.x, coord.y + 1),
		]
	else:
		dirs = [
			Vector2i(coord.x, coord.y - 1),
			Vector2i(coord.x + 1, coord.y - 1),
			Vector2i(coord.x - 1, coord.y),
			Vector2i(coord.x + 1, coord.y),
			Vector2i(coord.x, coord.y + 1),
			Vector2i(coord.x + 1, coord.y + 1),
		]
	return dirs


## Hexes alcanzables con una cantidad de puntos de movimiento (Dijkstra).
## Atajo a PathFinder.find_reachable(). Retorna Dictionary[Vector2i, float]
## con los hexes alcanzables desde [param origin] con [param movement_points].
func get_reachable_hexes(origin: Vector2i, movement_points: float) -> Dictionary:
	return PathFinder.find_reachable(origin, movement_points, self)


## Línea de hexes entre dos coordenadas (interpolación cube). Uso interno para line-of-sight.
static func _hex_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := distance(a, b)
	var result: Array[Vector2i] = []
	if n == 0:
		result.append(a)
		return result
	var ca := _cube_to_float(offset_to_cube(a))
	var cb := _cube_to_float(offset_to_cube(b))
	for i in range(n + 1):
		var t := float(i) / float(n)
		var lerped := Vector3(
			ca.x + (cb.x - ca.x) * t,
			ca.y + (cb.y - ca.y) * t,
			ca.z + (cb.z - ca.z) * t,
		)
		result.append(_cube_to_offset(cube_round(lerped.x, lerped.z)))
	return result


# --- Internos ---

static func cube_round(q: float, r: float) -> Vector3i:
	var s: float = -q - r
	var rq: float = roundf(q)
	var rr: float = roundf(r)
	var rs: float = roundf(s)
	var q_diff: float = absf(rq - q)
	var r_diff: float = absf(rr - r)
	var s_diff: float = absf(rs - s)
	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs
	return Vector3i(int(rq), int(-rq - rr), int(rr))


static func _cube_to_float(c: Vector3i) -> Vector3:
	return Vector3(float(c.x), float(c.y), float(c.z))


## Anillo de hexes a distancia N del origen.
func get_ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius == 0:
		return [center]
	var result: Array[Vector2i] = []
	var cube := offset_to_cube(center)
	var directions := [
		Vector3i(1, -1, 0), Vector3i(1, 0, -1), Vector3i(0, 1, -1),
		Vector3i(-1, 1, 0), Vector3i(-1, 0, 1), Vector3i(0, -1, 1),
	]
	# Start at center + direction[4] * radius
	var hex := Vector3i(
		cube.x + directions[4].x * radius,
		cube.y + directions[4].y * radius,
		cube.z + directions[4].z * radius,
	)
	for i in 6:
		for j in radius:
			var offset := _cube_to_offset(Vector3i(hex.x, hex.y, hex.z))
			if is_valid(offset):
				result.append(offset)
			hex = Vector3i(
				hex.x + directions[i].x,
				hex.y + directions[i].y,
				hex.z + directions[i].z,
			)
	return result


static func _cube_to_offset(cube: Vector3i) -> Vector2i:
	var col := cube.x + ((cube.z - (cube.z & 1)) / 2)
	var row := cube.z
	return Vector2i(col, row)


## blocking_terrains vacío → ningún terreno bloquea (retorna true siempre salvo celdas inválidas).
## [param elevation_fn]: (coord: Vector2i) → float. Si se proporciona, bloquea LOS cuando
## un hex intermedio tiene elevación mayor a la línea de visión interpolada entre from y to.
## Callable vacío = sin check de elevación (backward compat).
func get_line_of_sight(from: Vector2i, to: Vector2i, blocking_terrains: Array[int] = [], elevation_fn: Callable = Callable()) -> bool:
	if from == to:
		return true
	var line := _hex_line(from, to)
	var has_elevation := elevation_fn.is_valid()
	var from_elev: float = 0.0
	var to_elev: float = 0.0
	if has_elevation:
		from_elev = float(elevation_fn.call(from))
		to_elev = float(elevation_fn.call(to))
	var count := line.size()
	for i in range(count):
		var coord: Vector2i = line[i]
		if coord == from or coord == to:
			continue
		var cell := get_cell(coord)
		if cell and cell.terrain in blocking_terrains:
			return false
		if has_elevation:
			var cell_elev: float = float(elevation_fn.call(coord))
			var t: float = float(i) / float(count - 1)
			var line_height := from_elev + (to_elev - from_elev) * t
			if cell_elev > line_height:
				return false
	return true


## Retorna los hexes dentro de [param radius] desde [param origin] con línea de visión libre.
## [param blocking_terrains]: terrenos que interrumpen la LOS (ej. MOUNTAIN, FOREST).
## [param elevation_fn]: ver get_line_of_sight(). El propio [param origin] siempre se incluye.
func get_visible_cells(origin: Vector2i, radius: int, blocking_terrains: Array[int] = [], elevation_fn: Callable = Callable()) -> Array[Vector2i]:
	var result: Array[Vector2i] = [origin]
	result.append_array(_get_ring_filtered(origin, radius,
		func(coord: Vector2i) -> bool:
			return get_line_of_sight(origin, coord, blocking_terrains, elevation_fn)))
	return result


## Retorna los hexes dentro de [param radius] que NO tienen LOS desde [param origin].
## Complemento de get_visible_cells(). Útil para resaltar zonas en sombra.
func get_blocked_cells(origin: Vector2i, radius: int, blocking_terrains: Array[int] = [], elevation_fn: Callable = Callable()) -> Array[Vector2i]:
	var visible := {}
	for c in get_visible_cells(origin, radius, blocking_terrains, elevation_fn):
		visible[c] = true
	return _get_ring_filtered(origin, radius,
		func(coord: Vector2i) -> bool: return not visible.has(coord))


## Itera los rings 1..radius desde [param origin] y retorna coords que pasan [param include].
func _get_ring_filtered(origin: Vector2i, radius: int, include: Callable) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for r in range(1, radius + 1):
		for coord in get_ring(origin, r):
			if include.call(coord):
				result.append(coord)
	return result


## Retorna todos los hexes adyacentes a las unidades en [param unit_coords]
## que no están ocupados por ninguna unidad. Útil para zona de control táctica.
func get_zone_of_control(unit_coords: Array[Vector2i]) -> Array[Vector2i]:
	var zoc: Dictionary = {}
	var unit_set: Dictionary = {}
	for coord in unit_coords:
		unit_set[coord] = true
	for coord in unit_coords:
		for neighbor in get_neighbors(coord):
			if not zoc.has(neighbor) and not unit_set.has(neighbor):
				if is_valid(neighbor):
					zoc[neighbor] = true
	var result: Array[Vector2i] = []
	for coord in zoc:
		result.append(coord)
	return result
