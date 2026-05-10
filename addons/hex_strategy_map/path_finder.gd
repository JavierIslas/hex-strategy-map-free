class_name PathFinder
extends RefCounted
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


## Núcleo Dijkstra/A* unificado. Retorna cost_so_far: Dictionary[Vector2i, float].
## Todos los métodos públicos delegan aquí con distintos callables.
##
## [param neighbor_filter]: (coord, neighbor) → bool — si incluir el vecino.
## [param on_better_path]: (neighbor, from_coord, new_cost) → void — callback al relajar un nodo.
## [param should_exit]: (coord) → bool — terminar temprano (útil para A* con destino fijo).
## [param priority_fn]: (coord, g_cost) → float — g_cost para Dijkstra, g+h para A*.
## [param cost_fn]: (from, to) → float — opcional; por defecto usa terrain_cost + edge_cost del grid.
static func _search(
	start: Vector2i,
	grid: HexGrid,
	neighbor_filter: Callable,
	on_better_path: Callable,
	should_exit: Callable,
	priority_fn: Callable,
	max_cost: float = INF,
	cost_fn: Callable = Callable(),
) -> Dictionary:
	var _resolve_cost := cost_fn if cost_fn.is_valid() else func(from: Vector2i, to: Vector2i) -> float:
		return grid.get_movement_cost(to) + grid.get_edge_cost(from, to)

	var cost_so_far: Dictionary = {}
	var queue := MinHeap.new()
	cost_so_far[start] = 0.0
	on_better_path.call(start, start, 0.0)
	queue.push([priority_fn.call(start, 0.0), start])

	while not queue.is_empty():
		var current: Array = queue.pop()
		var coord: Vector2i = current[1]

		if should_exit.call(coord):
			break

		if current[0] > priority_fn.call(coord, cost_so_far.get(coord, INF)):
			continue

		for neighbor: Vector2i in HexGrid.get_neighbors(coord):
			if not neighbor_filter.call(coord, neighbor):
				continue
			var new_cost: float = cost_so_far[coord] + _resolve_cost.call(coord, neighbor)
			if new_cost > max_cost:
				continue
			if not cost_so_far.has(neighbor) or new_cost < cost_so_far[neighbor]:
				cost_so_far[neighbor] = new_cost
				on_better_path.call(neighbor, coord, new_cost)
				queue.push([priority_fn.call(neighbor, new_cost), neighbor])

	return cost_so_far


## Retorna Dictionary[Vector2i, float] con cada hex alcanzable y su costo acumulado.
## Hexes con costo > [param max_cost] quedan fuera del resultado.
## Pasar el resultado a find_path() para trazar el camino a un destino específico.
static func find_reachable(origin: Vector2i, max_cost: float, grid: HexGrid) -> Dictionary:
	if grid == null or not grid.is_valid(origin) or max_cost < 0.0:
		return {}
	return _search(
		origin, grid,
		_default_neighbor_filter(grid),
		func(_n: Vector2i, _c: Vector2i, _cost: float) -> void: pass,
		func(_c: Vector2i) -> bool: return false,
		func(_c: Vector2i, g: float) -> float: return g,
		max_cost,
	)


## Encuentra el camino más corto entre [param from] y [param to] usando Dijkstra.
## Si [param reachable] se proporciona, expande solo dentro del set alcanzable.
## Si [param reachable] está vacío, expande todo el grid pasable (sin límite de costo).
## Retorna Array[Vector2i] sin incluir [param from]. Retorna [] si no hay camino.
static func find_path(from: Vector2i, to: Vector2i, grid: HexGrid, reachable: Dictionary = {}) -> Array[Vector2i]:
	if not _validate_path_args(from, to, grid, reachable.is_empty()):
		return []

	var came_from: Dictionary = {}
	var neighbor_filter: Callable
	if reachable.is_empty():
		neighbor_filter = _default_neighbor_filter(grid)
	else:
		neighbor_filter = func(_c: Vector2i, n: Vector2i) -> bool:
			return reachable.has(n)

	_search(
		from, grid,
		neighbor_filter,
		func(n: Vector2i, c: Vector2i, _cost: float) -> void: came_from[n] = c,
		func(c: Vector2i) -> bool: return c == to,
		func(_c: Vector2i, g: float) -> float: return g,
	)

	return _reconstruct_path(came_from, from, to)


## Camino óptimo con heurística cube distance (A*). Más rápido que find_path() sin reachable
## en mapas grandes porque descarta zonas alejadas del destino.
## Produce paths óptimos cuando el costo mínimo de terreno >= 1.0 (heurística admisible).
## Retorna [] si no hay camino.
static func find_path_astar(from: Vector2i, to: Vector2i, grid: HexGrid) -> Array[Vector2i]:
	if not _validate_path_args(from, to, grid, true):
		return []

	var came_from: Dictionary = {}
	_search(
		from, grid,
		_default_neighbor_filter(grid),
		func(n: Vector2i, c: Vector2i, _cost: float) -> void: came_from[n] = c,
		func(c: Vector2i) -> bool: return c == to,
		func(c: Vector2i, g: float) -> float: return g + float(HexGrid.distance(c, to)),
	)

	return _reconstruct_path(came_from, from, to)


## Filtro de vecinos por defecto: el vecino debe ser válido en el grid y pasable.
static func _default_neighbor_filter(grid: HexGrid) -> Callable:
	return func(_c: Vector2i, n: Vector2i) -> bool:
		return grid.is_valid(n) and grid.is_passable(n)


## Valida precondiciones comunes: grid no nulo, from válido, from != to.
## Si check_to_passable = true, también verifica que to sea válido y pasable.
static func _validate_path_args(from: Vector2i, to: Vector2i, grid: HexGrid, check_to_passable: bool) -> bool:
	if grid == null or not grid.is_valid(from):
		return false
	if from == to:
		return false
	if check_to_passable and (not grid.is_valid(to) or not grid.is_passable(to)):
		return false
	return true


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
