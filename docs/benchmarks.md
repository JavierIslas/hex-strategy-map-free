# Benchmarks

Microbenchmarks of the core modules. Numbers are indicative — run them on your
own hardware before quoting them. The harness is in `benchmarks/`.

## How to run

```bash
godot --headless --script benchmarks/run_benchmarks.gd
```

Results land in `benchmarks/results.json` and stdout. Each operation is warmed
up (10% of iters, min 5) before timing min / p50 / p95 / mean in microseconds.

## Reference hardware

| Field | Value |
|---|---|
| CPU | Intel i5-1135G7 @ 2.40 GHz (Tiger Lake, 4C/8T) |
| RAM | 16 GB |
| OS | Linux |
| Godot | 4.6 stable (official) |
| Date | 2026-05-18 |

## Results

All times in microseconds (μs), median (p50) over the iteration count.

### HexGrid

| Operation | 50×50 | 100×100 | 250×250 |
|---|---:|---:|---:|
| `generate_cells` | 6 094 | 30 820 | 199 479 |
| `get_neighbors` (static, single call) | 1 | 1 | 1 |
| `distance` (static, single call) | 1 | 1 | 1 |
| `get_visible_cells(r=8)` | 3 461 | 3 493 | 3 465 |

`get_neighbors` and `distance` are O(1) hex math — they don't depend on grid
size. `get_visible_cells` cost scales with the radius, not the map: a fog-of-war
recompute on a 250×250 grid costs the same as on a 50×50.

### PathFinder

| Operation | 50×50 | 100×100 | 250×250 |
|---|---:|---:|---:|
| `find_reachable(max_cost=10)` | 2 863 | 3 170 | 3 133 |
| `find_reachable(max_cost=30)` | 31 858 | 36 162 | 33 286 |
| `find_path_astar` (dist=10) | 2 216 | 2 425 | 2 304 |
| `find_path_astar` (corner→corner) | 63 451 | 270 521 | 1 684 207 |
| `find_path` (cached reachable, hit) | 2 825 | 4 216 | 2 714 |

`find_reachable` and short-distance A* are bounded by the explored frontier,
not the map size. Worst-case A* (corner→corner on 250×250) is ~1.7 s — that's
the case to avoid; cache `find_reachable` once per turn and reuse it for target
selection (the "cached" row is ~1000× faster than uncached corner-corner A*).

### FlowField

| Operation | 50×50 | 100×100 | 250×250 |
|---|---:|---:|---:|
| `build(goal=center)` | 67 479 | 273 672 | 1 874 251 |
| `trace_path` (corner→center) | 15 | 33 | 85 |

`build` is a one-time O(N) Dijkstra. `trace_path` follows the gradient — about
**22 000× faster** than rebuilding on 250×250. This is why FlowField beats
A* when many units share a destination: pay the build once, trace per-unit
for free.

### FogOfWar

| Operation | 50×50 | 100×100 | 250×250 |
|---|---:|---:|---:|
| `reveal_around(r=5)` | 259 | 262 | 265 |
| `reveal_with_los(r=8)` | 3 985 | 3 952 | 3 986 |
| `update_visibility(r=5)` | 481 | 485 | 485 |
| `update_visibility_multi` (10 units, r=5) | 3 859 | 5 049 | 4 956 |
| `get_explored_count` | 765 | 4 377 | 28 425 |
| `serialize` (~25% revealed) | 105 | 425 | 3 107 |
| `deserialize` (~25% revealed) | 504 | 2 398 | 17 713 |

Reveal and update operations are bounded by the radius, not the grid — moving
a unit costs ~0.5 ms regardless of map size. `serialize` on a half-explored
250×250 grid is ~3 ms — small enough for play-by-email turns or wire format.

### FogTextureRenderer (Pro)

| Operation | 50×50 | 100×100 | 250×250 |
|---|---:|---:|---:|
| `setup` | 9 | 10 | 25 |
| `update` (full sweep) | 2 900 | 13 041 | 84 011 |
| `update_cell` (single pixel) | 1 | 1 | 1 |
| `update_cell` ×100 + `flush` | 66 | 66 | 74 |

The headline ratio: on 250×250, a full `update` costs 84 ms — a single
`update_cell` costs ~1 μs. **Incremental updates are ~84 000× faster than
the full sweep.** Connecting `FogOfWar.fog_changed` → `update_cell` keeps fog
rendering O(changed cells) per frame, not O(W·H). A batch of 100 changes
plus a flush is ~73 μs total.

## Choosing between PathFinder and FlowField

The worst-case A* row (corner→corner on 250×250 ≈ 1.7 s) tends to surprise
people who expect A* to always beat Dijkstra. It's worth unpacking, because
the choice of pathfinder matters more than the numbers themselves.

### Why corner→corner A* is so slow on a uniform grid

A* is faster than Dijkstra **when the heuristic can prune the search**. That
requires either obstacles, varied terrain costs, or a goal that's close
enough that most of the map is irrelevant. None of those hold in this
benchmark: the grid is flat PLAINS, uniform cost 1.0, and the endpoints are
in opposite corners.

When that happens, every monotonically-advancing path from origin to goal
has the **same total cost**. A* has no basis to prefer one over another and
ends up expanding a giant rhombus between the two points — roughly half the
map. On 250×250 that's ~31 000 hexes through the priority queue.

Note the same function on the same map with `dist=10` runs in ~2.3 ms.
A* cost scales with *distance traveled*, not grid size. For typical
"move this unit 6 hexes" calls it's the right tool.

### When to use what

| Scenario | Pick | Why |
|---|---|---|
| Short on-demand move (≤ ~20 hexes) | `find_path_astar` | Heuristic prunes, exploration is small |
| Hover preview / UI path on many cells | `find_reachable` once + `find_path(..., reachable)` | One Dijkstra, N cheap reconstructions (~1000× faster than uncached A*) |
| Many units sharing a destination | `FlowField.build` once + `trace_path` per unit | Build is amortized; trace is ~85 μs even on 250×250 |
| AI scoring distant targets | `find_reachable` with an explicit `max_cost` cap | Bounded Dijkstra is cheaper than long-range A* and reusable for multiple queries |

The addon ships all three because each one wins in a different scenario.
The microbenchmarks above don't tell you which is "fastest" — they tell you
the shape of each one's cost so you can pick the right tool for the call
site.

## Caveats

- These are microbenchmarks: pure logic, no scene tree pressure, no draw.
  Real-world frame budget will be dominated by rendering, not by these calls.
- Numbers come from a single dev machine. Run the harness on your target
  hardware before making decisions.
- A* worst-case on large grids is expensive — use bounded `find_reachable`
  or `FlowField` for movement on big maps.
- Render-side performance (FPS of `render` vs `render_batch`, GPU upload cost
  of `_texture.update`) requires a visible viewport and isn't covered here.
