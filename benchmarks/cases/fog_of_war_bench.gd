extends RefCounted

# Microbenchmarks de FogOfWar: reveal (sin LOS y con LOS), update_visibility
# (single y multi), get_explored_count, serialize/deserialize. El serialize
# vende el "JSON-friendly for save/load and PBEM".

const SIZES: Array[int] = [50, 100, 250]

static func run_all(bench) -> void:
	for size in SIZES:
		var grid := HexGrid.new(size, size)
		grid.generate_cells()
		_bench_reveal_around(bench, grid, size)
		_bench_reveal_with_los(bench, grid, size)
		_bench_update_visibility(bench, grid, size)
		_bench_update_visibility_multi(bench, grid, size)
		_bench_get_explored_count(bench, grid, size)
		_bench_serialize(bench, grid, size)
		_bench_deserialize(bench, grid, size)

static func _bench_reveal_around(bench, grid: HexGrid, size: int) -> void:
	var center := Vector2i(size / 2, size / 2)
	var iters: int = _scale_iters(size, 1000, 500, 200)
	bench.run("FogOfWar.reveal_around       %dx%d (r=5)" % [size, size], iters, func():
		var fog := FogOfWar.new(grid)
		fog.reveal_around(0, center, 5)
	)

static func _bench_reveal_with_los(bench, grid: HexGrid, size: int) -> void:
	var center := Vector2i(size / 2, size / 2)
	var iters: int = _scale_iters(size, 200, 100, 50)
	bench.run("FogOfWar.reveal_with_los     %dx%d (r=8, no blockers)" % [size, size], iters, func():
		var fog := FogOfWar.new(grid)
		fog.reveal_with_los(0, center, 8)
	)

static func _bench_update_visibility(bench, grid: HexGrid, size: int) -> void:
	var fog := FogOfWar.new(grid)
	var pos := Vector2i(size / 2, size / 2)
	fog.reveal_around(0, pos, 5)
	var iters: int = _scale_iters(size, 500, 200, 100)
	bench.run("FogOfWar.update_visibility   %dx%d (r=5, re-reveal)" % [size, size], iters, func():
		fog.update_visibility(0, pos, 5)
	)

static func _bench_update_visibility_multi(bench, grid: HexGrid, size: int) -> void:
	var fog := FogOfWar.new(grid)
	var positions: Array[Vector2i] = []
	for i in 10:
		positions.append(Vector2i((size / 11) * (i + 1), size / 2))
	var radius_fn := func(_p: Vector2i) -> int: return 5
	var iters: int = _scale_iters(size, 100, 50, 20)
	bench.run("FogOfWar.update_visibility_multi %dx%d (10 units, r=5)" % [size, size], iters, func():
		fog.update_visibility_multi(0, positions, radius_fn)
	)

static func _bench_get_explored_count(bench, grid: HexGrid, size: int) -> void:
	var fog := FogOfWar.new(grid)
	fog.reveal_around(0, Vector2i(size / 2, size / 2), size / 4)
	var iters: int = _scale_iters(size, 1000, 500, 200)
	bench.run("FogOfWar.get_explored_count  %dx%d" % [size, size], iters, func():
		fog.get_explored_count(0)
	)

static func _bench_serialize(bench, grid: HexGrid, size: int) -> void:
	var fog := FogOfWar.new(grid)
	fog.reveal_around(0, Vector2i(size / 2, size / 2), size / 4)
	var iters: int = _scale_iters(size, 200, 100, 50)
	bench.run("FogOfWar.serialize           %dx%d (~25%% revealed)" % [size, size], iters, func():
		fog.serialize()
	)

static func _bench_deserialize(bench, grid: HexGrid, size: int) -> void:
	var fog := FogOfWar.new(grid)
	fog.reveal_around(0, Vector2i(size / 2, size / 2), size / 4)
	var data := fog.serialize()
	var iters: int = _scale_iters(size, 200, 100, 50)
	bench.run("FogOfWar.deserialize         %dx%d (~25%% revealed)" % [size, size], iters, func():
		FogOfWar.deserialize(data, grid)
	)

static func _scale_iters(size: int, small: int, mid: int, large: int) -> int:
	if size <= 50:
		return small
	if size <= 100:
		return mid
	return large
