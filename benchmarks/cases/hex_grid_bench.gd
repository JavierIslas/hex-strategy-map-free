extends RefCounted

# Microbenchmarks de HexGrid: generate_cells, get_neighbors, distance,
# get_visible_cells (LOS). Tamaños: 50, 100, 250.

const SIZES: Array[int] = [50, 100, 250]

static func run_all(bench) -> void:
	for size in SIZES:
		_bench_generate(bench, size)
		_bench_neighbors(bench, size)
		_bench_distance(bench, size)
		_bench_los(bench, size)

static func _bench_generate(bench, size: int) -> void:
	bench.run("HexGrid.generate_cells  %dx%d" % [size, size], 20, func():
		var g := HexGrid.new(size, size)
		g.generate_cells()
	)

static func _bench_neighbors(bench, size: int) -> void:
	var center := Vector2i(size / 2, size / 2)
	# get_neighbors es estático y no depende del grid; medimos solo la llamada.
	var iters: int = 5000 if size <= 100 else 2000
	bench.run("HexGrid.get_neighbors    %dx%d (center)" % [size, size], iters, func():
		HexGrid.get_neighbors(center)
	)

static func _bench_distance(bench, size: int) -> void:
	var a := Vector2i(1, 1)
	var b := Vector2i(size - 2, size - 2)
	var iters: int = 5000 if size <= 100 else 2000
	bench.run("HexGrid.distance         %dx%d (corner→corner)" % [size, size], iters, func():
		HexGrid.distance(a, b)
	)

static func _bench_los(bench, size: int) -> void:
	var g := HexGrid.new(size, size)
	g.generate_cells()
	var origin := Vector2i(size / 2, size / 2)
	var radius: int = 8
	var iters: int = 200 if size <= 100 else 50
	bench.run("HexGrid.get_visible_cells %dx%d (r=%d)" % [size, size, radius], iters, func():
		g.get_visible_cells(origin, radius)
	)
