class_name HexPalette
extends Resource
## Paleta de colores y resolver de color por celda compartida por HexRenderer y HexBatchRenderer.
##
## Centraliza la configuración visual que antes vivía dispersa en HexRenderer.
## Permite que ambos renderers reciban la misma fuente de verdad sin duplicar parámetros.
##
## Properties exportadas (border_color/width, reachable_color): configurables en .tres.
## Properties no exportadas (terrain_colors, fog_colors, color_fn): asignables en código —
## Dictionary y Callable no son serializables como exports de forma confiable.

const DEFAULT_TERRAIN_COLORS: Dictionary = {
	HexCell.Terrain.ROAD: Color(0.36, 0.25, 0.20),
	HexCell.Terrain.PLAINS: Color(0.18, 0.35, 0.22),
	HexCell.Terrain.FOREST: Color(0.10, 0.22, 0.12),
	HexCell.Terrain.MOUNTAIN: Color(0.40, 0.38, 0.35),
	HexCell.Terrain.WATER: Color(0.12, 0.22, 0.42),
}

const DEFAULT_FOG_COLORS: Dictionary = {
	FogState.HIDDEN: Color(0.02, 0.02, 0.04, 1.0),
	FogState.EXPLORED: Color(0.05, 0.05, 0.08, 0.5),
}

const REACHABLE_COLOR := Color(0.9, 0.85, 0.3, 0.3)
const BORDER_COLOR := Color(0.2, 0.2, 0.2, 0.5)
const BORDER_WIDTH := 1.0

## Sentinel que un color_fn puede retornar para indicar "no opino, usá terrain_colors".
## RGBA negativo no es un color válido — no choca con ningún color real.
const SKIP_COLOR := Color(-1, -1, -1, -1)

## Emitida cuando terrain_colors o fog_colors cambian vía setter. Permite a renderers
## batch invalidar su cache visual sin que el consumer tenga que llamar mark_dirty manualmente.
signal palette_changed()

@export var border_color: Color = BORDER_COLOR
@export var border_width: float = BORDER_WIDTH
@export var reachable_color: Color = REACHABLE_COLOR

var terrain_colors: Dictionary = DEFAULT_TERRAIN_COLORS.duplicate():
	set(value):
		terrain_colors = value
		palette_changed.emit()
var fog_colors: Dictionary = DEFAULT_FOG_COLORS.duplicate():
	set(value):
		fog_colors = value
		palette_changed.emit()
## Callable opcional `(HexCell) → Color`. Retornar [constant SKIP_COLOR] para
## delegar al lookup en [member terrain_colors].
var color_fn: Callable = Callable()


## Resuelve el color de [param cell]. Si [member color_fn] está asignado y no devuelve
## [constant SKIP_COLOR], usa ese valor. Si no, busca en [member terrain_colors] por
## terrain id; fallback a [code]Color.GRAY[/code] si no está mapeado.
func resolve_cell_color(cell: HexCell) -> Color:
	if color_fn.is_valid():
		var c: Color = color_fn.call(cell)
		if c != SKIP_COLOR:
			return c
	return terrain_colors.get(cell.terrain, Color.GRAY)


## Crea una paleta con todos los defaults. Equivalente a [code]HexPalette.new()[/code]
## pero más explícita en intención cuando se usa como factory.
static func create_default() -> HexPalette:
	return HexPalette.new()
