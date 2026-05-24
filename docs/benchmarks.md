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
| Date | 2026-05-21 (v1.5.0 — A* heuristic rewrite) |

## Results

All times in microseconds (μs), median (p50) over the iteration count.

### HexGrid

| Operation | 50×50 | 100×100 | 250×250 |
|---|---:|---:|---:|
| `generate_cells` | 6 984 | 31 634 | 202 514 |
| `get_neighbors` (static, single call) | 1 | 1 | 1 |
| `distance` (static, single call) | 1 | 1 | 1 |
| `get_visible_cells(r=8)` | 2 239 | 2 261 | 2 169 |

`get_neighbors` and `distance` are O(1) hex math — they don't depend on grid
size. `get_visible_cells` cost scales with the radius, not the map: a fog-of-war
recompute on a 250×250 grid costs the same as on a 50×50.

### PathFinder

| Operation | 50×50 | 100×100 | 250×250 |
|---|---:|---:|---:|
| `find_reachable(max_cost=10)` | 3 298 | 3 195 | 3 397 |
| `find_reachable(max_cost=30)` | 34 309 | 34 334 | 35 220 |
| `find_path_astar` (dist=10) | 432 | 434 | 445 |
| `find_path_astar` (corner→corner) | 2 642 | 5 773 | 14 780 |
| `find_path` (cached reachable, hit) | 2 887 | 4 402 | 2 976 |

`find_reachable` cost scales with the bounded frontier, not the grid — a
`max_cost=30` call is the same ~35 ms whether the map is 50×50 or 250×250.

`find_path_astar` corner→corner on 250×250 used to be the headline horror of
this table (~1.7 s in v1.4.0). The v1.5.0 heuristic rewrite — scaling `h` by
`grid.min_passable_terrain_cost()` and adding a cube-cross tiebreak — collapsed
it by **~114×** (1 684 207 μs → 14 780 μs) and made A* cost scale with **path
length** rather than the area of the equally-optimal lens. Short-distance A*
also improved by ~5× as a side effect of the same fix. See
`devlog_astar_tiebreak_followup.html` for the full debugging story.

### FlowField

| Operation | 50×50 | 100×100 | 250×250 |
|---|---:|---:|---:|
| `build(goal=center)` | 73 694 | 310 612 | 2 091 475 |
| `trace_path` (corner→center) | 15 | 32 | 93 |

`build` is a one-time O(N) Dijkstra. `trace_path` follows the gradient — about
**22 000× faster** than rebuilding on 250×250. This is why FlowField beats
A* when many units share a destination: pay the build once, trace per-unit
for free.

### FogOfWar

| Operation | 50×50 | 100×100 | 250×250 |
|---|---:|---:|---:|
| `reveal_around(r=5)` | 284 | 290 | 292 |
| `reveal_with_los(r=8)` | 2 739 | 2 698 | 2 842 |
| `update_visibility(r=5)` | 515 | 544 | 542 |
| `update_visibility_multi` (10 units, r=5) | 4 080 | 5 503 | 5 715 |
| `get_explored_count` | 875 | 4 580 | 30 276 |
| `serialize` (~25% revealed) | 116 | 467 | 3 107 |
| `deserialize` (~25% revealed) | 597 | 2 694 | 20 011 |

Reveal and update operations are bounded by the radius, not the grid — moving
a unit costs ~0.5 ms regardless of map size. `serialize` on a half-explored
250×250 grid is ~3 ms — small enough for play-by-email turns or wire format.

### FogTextureRenderer (Pro)

| Operation | 50×50 | 100×100 | 250×250 |
|---|---:|---:|---:|
| `setup` | 9 | 12 | 24 |
| `update` (full sweep) | 3 193 | 14 424 | 92 215 |
| `update_cell` (single pixel) | 1 | 1 | 1 |
| `update_cell` ×100 + `flush` | 67 | 72 | 73 |

The headline ratio: on 250×250, a full `update` costs 92 ms — a single
`update_cell` costs ~1 μs. **Incremental updates are ~92 000× faster than
the full sweep.** Connecting `FogOfWar.fog_changed` → `update_cell` keeps fog
rendering O(changed cells) per frame, not O(W·H). A batch of 100 changes
plus a flush is ~73 μs total.

## Choosing between PathFinder and FlowField

Each one wins in a different scenario. The microbenchmarks above don't tell
you which is "fastest" — they tell you the shape of each one's cost so you
can pick the right tool for the call site.

### When to use what

| Scenario | Pick | Why |
|---|---|---|
| Short on-demand move (≤ ~20 hexes) | `find_path_astar` | Heuristic prunes hard; ~440 μs regardless of map size |
| Long single-pair query on an open map | `find_path_astar` | Post-v1.5.0, scales with path length, not grid area (~15 ms on 250×250) |
| Hover preview / UI path on many cells | `find_reachable` once + `find_path(..., reachable)` | One Dijkstra (~35 ms unbounded), N cheap reconstructions (~3 ms each) |
| Many units sharing a destination | `FlowField.build` once + `trace_path` per unit | Build amortized; trace is ~93 μs on 250×250 |
| AI scoring distant targets | `find_reachable` with an explicit `max_cost` cap | Bounded Dijkstra is cheaper than running A* per candidate and reusable for multiple queries |

### FlowField vs A* break-even

For "N units to the same destination" decisions, the numbers above give a
direct break-even point on a uniform 250×250:

- `FlowField.build` = 2 091 475 μs
- `FlowField.trace_path` = 93 μs
- `find_path_astar` (corner→corner) = 14 780 μs

`build / (astar - trace)` ≈ **142 units**. Above that, FlowField wins; below
that, paying A* per unit is cheaper than amortizing the build. Adjust for
your map size — on 50×50 the break-even is around 28 units, on 100×100 around
54. The shape is the same; the inflection point moves with map area.

## Caveats

- These are microbenchmarks: pure logic, no scene tree pressure, no draw.
  Real-world frame budget will be dominated by rendering, not by these calls.
- Numbers come from a single dev machine. Run the harness on your target
  hardware before making decisions.
- A* post-v1.5.0 scales with path length on uniform maps; for many-units
  scenarios still prefer `FlowField`, and for repeated queries from the same
  origin still prefer cached `find_reachable` + `find_path`.
- Render-side performance (FPS of `render` vs `render_batch`, GPU upload cost
  of `_texture.update`) requires a visible viewport and isn't covered here.
