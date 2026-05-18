extends SceneTree

# Entry point para microbenchmarks. Correr con:
#   godot --headless --script benchmarks/run_benchmarks.gd
#
# Carga los cases condicionalmente para soportar empaquetado por tier:
# en el ZIP free solo existen los 3 cases libres; en el ZIP pro están los 5.
# Resultados: stdout + benchmarks/results.json

const BENCH_SCRIPT := "res://benchmarks/bench.gd"

const FREE_CASES: Array[String] = [
	"res://benchmarks/cases/hex_grid_bench.gd",
	"res://benchmarks/cases/path_finder_bench.gd",
	"res://benchmarks/cases/fog_of_war_bench.gd",
]

const PRO_CASES: Array[String] = [
	"res://benchmarks/cases/flow_field_bench.gd",
	"res://benchmarks/cases/fog_texture_renderer_bench.gd",
]

# Cases que requieren un Node parent (SceneTree.root) para crear hijos.
const CASES_NEEDING_ROOT: Array[String] = [
	"res://benchmarks/cases/fog_texture_renderer_bench.gd",
]

func _initialize() -> void:
	print("=== hex-strategy-map microbenchmarks ===")
	print("Godot %s  |  %s" % [
		Engine.get_version_info().get("string", "?"),
		OS.get_name(),
	])
	print("")

	var bench_script := load(BENCH_SCRIPT)
	var bench = bench_script.new()

	for path in FREE_CASES + PRO_CASES:
		if not FileAccess.file_exists(path):
			continue
		var case_script := load(path)
		if path in CASES_NEEDING_ROOT:
			case_script.run_all(bench, root)
		else:
			case_script.run_all(bench)

	bench.save_json("res://benchmarks/results.json", {
		"godot_version": Engine.get_version_info().get("string", "?"),
		"os": OS.get_name(),
		"timestamp_unix": int(Time.get_unix_time_from_system()),
	})
	quit()
