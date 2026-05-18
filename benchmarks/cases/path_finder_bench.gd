extends RefCounted

# Microbenchmarks de PathFinder: find_reachable, find_path_astar, find_path
# (con reachable cacheado). Mapas planos sin obstáculos en este pase — medimos
# el algoritmo, no la topología.

const SIZES: Array[int] = [50, 100, 250]

static func run_all(bench) -> void:
	for size in SIZES:
		var grid := HexGrid.new(size, size)
		grid.generate_cells()
		_bench_reachable(bench, grid, size, 10.0)
		_bench_reachable(bench, grid, size, 30.0)
		_bench_astar_short(bench, grid, size)
		_bench_astar_corner(bench, grid, size)
		_bench_path_cached(bench, grid, size)

static func _bench_reachable(bench, grid: HexGrid, size: int, max_cost: float) -> void:
	var origin := Vector2i(size / 2, size / 2)
	var iters: int = _scale_iters(size, 200, 100, 30)
	bench.run("PathFinder.find_reachable     %dx%d (max_cost=%.0f)" % [size, size, max_cost], iters, func():
		PathFinder.find_reachable(origin, max_cost, grid)
	)

static func _bench_astar_short(bench, grid: HexGrid, size: int) -> void:
	var from := Vector2i(size / 2, size / 2)
	var to := Vector2i(size / 2 + 8, size / 2 + 6)
	var iters: int = _scale_iters(size, 500, 500, 200)
	bench.run("PathFinder.find_path_astar    %dx%d (dist=10)" % [size, size], iters, func():
		PathFinder.find_path_astar(from, to, grid)
	)

static func _bench_astar_corner(bench, grid: HexGrid, size: int) -> void:
	var from := Vector2i(1, 1)
	var to := Vector2i(size - 2, size - 2)
	var iters: int = _scale_iters(size, 100, 50, 10)
	bench.run("PathFinder.find_path_astar    %dx%d (corner→corner)" % [size, size], iters, func():
		PathFinder.find_path_astar(from, to, grid)
	)

static func _bench_path_cached(bench, grid: HexGrid, size: int) -> void:
	var origin := Vector2i(size / 2, size / 2)
	var reachable := PathFinder.find_reachable(origin, 20.0, grid)
	var dest := Vector2i(size / 2 + 5, size / 2 + 5)
	var iters: int = _scale_iters(size, 2000, 1000, 500)
	bench.run("PathFinder.find_path (cached) %dx%d (reachable hit)" % [size, size], iters, func():
		PathFinder.find_path(origin, dest, grid, reachable)
	)

static func _scale_iters(size: int, small: int, mid: int, large: int) -> int:
	if size <= 50:
		return small
	if size <= 100:
		return mid
	return large
