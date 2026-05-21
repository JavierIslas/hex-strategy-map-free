class_name PathFinder
extends RefCounted

# find_path_astar combina dos correcciones que solo funcionan juntas. Sacar
# cualquiera de las dos regresa por uno o dos órdenes de magnitud en mapas
# uniform-cost. El devlog docs/devlog_astar_tiebreak_followup.html explica el
# proceso de debugging completo.
#
# 1) La heurística base devuelve distancia en HEXES (1 unidad por paso) y se
#    escala por grid.min_passable_terrain_cost(). Esto la deja tight en mapas
#    con un único terreno (f del lens = f del goal) y la mantiene admisible
#    en terreno mixto (escalamos por el mínimo). Sin esto el lens entero
#    queda con f < f_goal y A* lo recorre completo (~55k pops en 250x250).
#
# 2) Cube-cross tiebreak. Con la heurística tight todas las celdas óptimas
#    empatan en f y A* aún expande el lens (~14k celdas). Sumar el producto
#    cruzado en coords cube — |Δq_cn·Δr_sg − Δq_sg·Δr_cn| — perturba la
#    prioridad para preferir celdas alineadas con la diagonal start→goal y
#    colapsa la búsqueda a una banda angosta (~370 pops para path de 370).
#    ε debe quedar muy por debajo del costo mínimo de un paso para no
#    romper admisibilidad en mapas chicos.
const ASTAR_TIEBREAK_CROSS := 0.001
## Pathfinding unificado para mapas hexagonales.
## Dijkstra + A* con heap binario para O((V+E) log V).
##
## Todos los métodos públicos son estáticos — no instanciar PathFinder.
## Los costos se leen de HexGrid.terrain_cost y de los edges (HexGrid.edges).
##
## Métodos principales:
##   find_reachable()     → hexes alcanzables con N puntos de movimiento (Dijkstra).
##   find_path()          → camino óptimo dentro de un reachable set (Dijkstra).
##   find_path_astar()    → camino óptimo sin límite de costo (A*, más rápido en mapas grandes).
##
## Para movimiento de grupos hacia un mismo destino, usar FlowField en lugar
## de llamar find_path_astar() N veces — es equivalente pero hace un solo pase Dijkstra.


class MinHeap:
	## Heap binario mínimo. Items: [cost: float, coord: Vector2i].
	## Usado internamente por _search para la cola de prioridad.
	var _data: Array = []

	## Inserta [param item] manteniendo la propiedad de heap mínimo.
	func push(item: Array) -> void:
		_data.append(item)
		_bubble_up(_data.size() - 1)

	## Extrae y retorna el item con menor costo. Retorna [] si está vacío.
	func pop() -> Array:
		if _data.is_empty():
			return []
		if _data.size() == 1:
			return _data.pop_back()
		var root: Array = _data[0]
		_data[0] = _data.pop_back()
		_sink_down(0)
		return root

	## Retorna true si el heap no tiene elementos.
	func is_empty() -> bool:
		return _data.is_empty()

	func _bubble_up(idx: int) -> void:
		while idx > 0:
			var parent := (idx - 1) / 2
			if _data[idx][0] >= _data[parent][0]:
				break
			var tmp = _data[idx]
			_data[idx] = _data[parent]
			_data[parent] = tmp
			idx = parent

	func _sink_down(idx: int) -> void:
		var size := _data.size()
		while true:
			var smallest := idx
			var left := 2 * idx + 1
			var right := 2 * idx + 2
			if left < size and _data[left][0] < _data[smallest][0]:
				smallest = left
			if right < size and _data[right][0] < _data[smallest][0]:
				smallest = right
			if smallest == idx:
				break
			var tmp = _data[idx]
			_data[idx] = _data[smallest]
			_data[smallest] = tmp
			idx = smallest


## Configuración para _search(). Agrupa los Callables del algoritmo para evitar
## firma posicional frágil. Construir con SearchConfig.new() y rellenar campos.
class SearchConfig:
	## (coord, neighbor) → bool — si incluir el vecino en la expansión.
	var neighbor_filter: Callable
	## (neighbor, from_coord, new_cost) → void — callback al relajar un nodo.
	var on_better_path: Callable
	## (coord) → bool — terminar temprano; útil para A* con destino fijo.
	var should_exit: Callable
	## (coord, g_cost) → float — g_cost para Dijkstra, g+h para A*.
	var priority_fn: Callable
	## Costo máximo; hexes más caros quedan fuera. INF = sin límite.
	var max_cost: float = INF
	## (from, to) → float — opcional; por defecto usa terrain_cost + edge_cost del grid.
	var cost_fn: Callable = Callable()


## Núcleo Dijkstra/A* unificado. Retorna cost_so_far: Dictionary[Vector2i, float].
## Todos los métodos públicos delegan aquí vía SearchConfig.
static func _search(
	start: Vector2i,
	grid: HexGrid,
	cfg: SearchConfig,
) -> Dictionary:
	var _resolve_cost := cfg.cost_fn if cfg.cost_fn.is_valid() else func(from: Vector2i, to: Vector2i) -> float:
		return grid.get_movement_cost(to) + grid.get_edge_cost(from, to)

	var cost_so_far: Dictionary = {}
	var queue := MinHeap.new()
	cost_so_far[start] = 0.0
	cfg.on_better_path.call(start, start, 0.0)
	queue.push([cfg.priority_fn.call(start, 0.0), start])

	while not queue.is_empty():
		var current: Array = queue.pop()
		var coord: Vector2i = current[1]

		if cfg.should_exit.call(coord):
			break

		if current[0] > cfg.priority_fn.call(coord, cost_so_far.get(coord, INF)):
			continue

		for neighbor: Vector2i in HexGrid.get_neighbors(coord):
			if not cfg.neighbor_filter.call(coord, neighbor):
				continue
			var new_cost: float = cost_so_far[coord] + _resolve_cost.call(coord, neighbor)
			if new_cost > cfg.max_cost:
				continue
			if not cost_so_far.has(neighbor) or new_cost < cost_so_far[neighbor]:
				cost_so_far[neighbor] = new_cost
				cfg.on_better_path.call(neighbor, coord, new_cost)
				queue.push([cfg.priority_fn.call(neighbor, new_cost), neighbor])

	return cost_so_far


## Retorna Dictionary[Vector2i, float] con cada hex alcanzable y su costo acumulado.
## Hexes con costo > [param max_cost] quedan fuera del resultado.
## Pasar el resultado a find_path() para trazar el camino a un destino específico.
static func find_reachable(origin: Vector2i, max_cost: float, grid: HexGrid) -> Dictionary:
	if grid == null or not grid.is_valid(origin) or max_cost < 0.0:
		return {}
	var cfg := SearchConfig.new()
	cfg.neighbor_filter = _default_neighbor_filter(grid)
	cfg.on_better_path = func(_n: Vector2i, _c: Vector2i, _cost: float) -> void: pass
	cfg.should_exit = func(_c: Vector2i) -> bool: return false
	cfg.priority_fn = func(_c: Vector2i, g: float) -> float: return g
	cfg.max_cost = max_cost
	return _search(origin, grid, cfg)


## Encuentra el camino más corto entre [param from] y [param to] usando Dijkstra.
## Si [param reachable] se proporciona, expande solo dentro del set alcanzable.
## Si [param reachable] está vacío, expande todo el grid pasable (sin límite de costo).
## Retorna Array[Vector2i] sin incluir [param from]. Retorna [] si no hay camino.
static func find_path(from: Vector2i, to: Vector2i, grid: HexGrid, reachable: Dictionary = {}) -> Array[Vector2i]:
	var valid := _validate_path_args_strict(from, to, grid) if reachable.is_empty() else \
		_validate_path_args_basic(from, to, grid)
	if not valid:
		return []
	var neighbor_filter := _default_neighbor_filter(grid) if reachable.is_empty() else \
		func(_c: Vector2i, n: Vector2i) -> bool: return reachable.has(n)
	return _find_path_impl(from, to, grid, neighbor_filter,
		func(_c: Vector2i, g: float) -> float: return g)


## Camino óptimo con A* (heurística hex-distance escalada por el costo mínimo
## de terreno del grid + cube-cross tiebreak). Ver el bloque de comentarios
## sobre ASTAR_TIEBREAK_CROSS para detalles del diseño.
## Más rápido que find_path() sin reachable en mapas grandes; en mapas
## uniform-cost colapsa a ~O(longitud del path).
## Requiere el cube-cross tiebreak definido en ASTAR_TIEBREAK_CROSS para
## colapsar en mapas uniformes; sacarlo regresa por un orden de magnitud.
## Heurística admisible siempre que terrain_cost no se modifique a posteriori
## (el escalado se cachea en grid.min_passable_terrain_cost()).
## Retorna [] si no hay camino.
static func find_path_astar(from: Vector2i, to: Vector2i, grid: HexGrid) -> Array[Vector2i]:
	if not _validate_path_args_strict(from, to, grid):
		return []
	var h_scale := grid.min_passable_terrain_cost()
	var cube_to := HexGrid.offset_to_cube(to)
	var cube_from := HexGrid.offset_to_cube(from)
	var dq_sg := cube_from.x - cube_to.x
	var dr_sg := cube_from.z - cube_to.z
	return _find_path_impl(from, to, grid, _default_neighbor_filter(grid),
		func(c: Vector2i, g: float) -> float:
			var h := float(HexGrid.distance(c, to)) * h_scale
			var cn := HexGrid.offset_to_cube(c)
			var dq_cg := cn.x - cube_to.x
			var dr_cg := cn.z - cube_to.z
			var cross: float = absf(float(dq_cg) * dr_sg - dq_sg * float(dr_cg))
			return g + h + cross * ASTAR_TIEBREAK_CROSS)


## Núcleo compartido de find_path y find_path_astar. Solo difieren en neighbor_filter y priority_fn.
static func _find_path_impl(from: Vector2i, to: Vector2i, grid: HexGrid, neighbor_filter: Callable, priority_fn: Callable) -> Array[Vector2i]:
	var came_from: Dictionary = {}
	var cfg := SearchConfig.new()
	cfg.neighbor_filter = neighbor_filter
	cfg.on_better_path = func(n: Vector2i, c: Vector2i, _cost: float) -> void: came_from[n] = c
	cfg.should_exit = func(c: Vector2i) -> bool: return c == to
	cfg.priority_fn = priority_fn
	_search(from, grid, cfg)
	return _reconstruct_path(came_from, from, to)


## Filtro de vecinos por defecto: el vecino debe ser válido en el grid y pasable.
static func _default_neighbor_filter(grid: HexGrid) -> Callable:
	return func(_c: Vector2i, n: Vector2i) -> bool:
		return grid.is_valid(n) and grid.is_passable(n)


## Valida args básicos: grid no nulo, from válido, from != to.
static func _validate_path_args_basic(from: Vector2i, to: Vector2i, grid: HexGrid) -> bool:
	return grid != null and grid.is_valid(from) and from != to


## Valida args para búsqueda sin reachable: incluye verificación de pasabilidad de to.
static func _validate_path_args_strict(from: Vector2i, to: Vector2i, grid: HexGrid) -> bool:
	return _validate_path_args_basic(from, to, grid) \
		and grid.is_valid(to) and grid.is_passable(to)


## Reconstruye el camino desde el diccionario came_from recorriendo hacia atrás desde to.
## Retorna [] si to no fue alcanzado (no está en came_from).
static func _reconstruct_path(came_from: Dictionary, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not came_from.has(to):
		return []
	var path: Array[Vector2i] = []
	var step := to
	while step != from:
		path.append(step)
		step = came_from[step]
	path.reverse()
	return path
