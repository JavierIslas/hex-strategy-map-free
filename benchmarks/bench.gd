class_name Bench
extends RefCounted

# Microbenchmark helper. Mide tiempos en microsegundos con Time.get_ticks_usec()
# y reporta min / p50 / p95 / mean por operación.

var results: Array[Dictionary] = []

func run(name: String, iters: int, op: Callable) -> void:
	# Warmup: 10% de iters o mínimo 5, para estabilizar JIT/cache.
	var warmup: int = max(5, iters / 10)
	for i in warmup:
		op.call()

	var samples: PackedFloat64Array = PackedFloat64Array()
	samples.resize(iters)
	for i in iters:
		var t0: int = Time.get_ticks_usec()
		op.call()
		samples[i] = float(Time.get_ticks_usec() - t0)

	samples.sort()
	var sum: float = 0.0
	for v in samples:
		sum += v
	var p50: float = samples[int(iters * 0.50)]
	var p95: float = samples[int(iters * 0.95)]
	var entry := {
		"name": name,
		"iters": iters,
		"min_us": samples[0],
		"p50_us": p50,
		"p95_us": p95,
		"mean_us": sum / iters,
		"max_us": samples[iters - 1],
	}
	results.append(entry)
	print("%-50s  min=%8.1f  p50=%8.1f  p95=%8.1f  mean=%8.1f  (n=%d)" % [
		name, entry.min_us, entry.p50_us, entry.p95_us, entry.mean_us, iters
	])

func save_json(path: String, metadata: Dictionary) -> void:
	var payload := {
		"metadata": metadata,
		"results": results,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	print("\nWrote %s (%d entries)" % [path, results.size()])
