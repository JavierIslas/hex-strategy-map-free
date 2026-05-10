class_name MapCamera
extends RefCounted
## Controlador de cámara para mapas hexagonales.
##
## Envuelve un Camera2D de Godot y agrega follow, drag con botón derecho,
## zoom con scroll, y edge-scroll (la cámara se mueve cuando el mouse
## llega al borde de la pantalla).
##
## Uso típico:
##   cam_ctrl = MapCamera.new(camera, get_viewport())
##   # en _process:   cam_ctrl.process(delta, target_pos)
##   # en _unhandled_input: cam_ctrl.handle_input(event)
##
## Follow vs libre: follow_target = true hace lerp hacia target_position.
## Se desactiva automáticamente al hacer drag. Reactivar con Space o
## asignando follow_target = true desde código.

## Referencia al Camera2D que se controla.
var camera: Camera2D = null
## Viewport asociado (necesario para edge-scroll y screen_to_world).
var viewport: Viewport = null
## true → la cámara sigue el target_position pasado a process().
## false → la cámara se controla con drag / edge-scroll.
var follow_target: bool = true

## Velocidad de interpolación del follow (lerp). Valores típicos: 4–12.
var lerp_speed: float = 8.0
## Ancho en píxeles del borde de pantalla que activa el edge-scroll.
var edge_margin: float = 30.0
## Velocidad del edge-scroll en píxeles por segundo.
var edge_speed: float = 500.0
## Zoom mínimo permitido (alejado). Valores < 1.0 alejan la cámara.
var zoom_min: float = 0.6
## Zoom máximo permitido (acercado). Valores > 1.0 acercan la cámara.
var zoom_max: float = 3.0
## Incremento de zoom por cada tick de scroll wheel.
var zoom_step: float = 0.15

var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _camera_drag_start: Vector2 = Vector2.ZERO


## Inicializa el controlador con la cámara y viewport del nodo raíz.
## [param p_params] sobreescribe cualquier parámetro por su nombre:
##   lerp_speed, edge_margin, edge_speed, zoom_min, zoom_max, zoom_step.
func _init(p_camera: Camera2D, p_viewport: Viewport, p_params: Dictionary = {}) -> void:
	camera = p_camera
	viewport = p_viewport
	lerp_speed = p_params.get("lerp_speed", lerp_speed)
	edge_margin = p_params.get("edge_margin", edge_margin)
	edge_speed = p_params.get("edge_speed", edge_speed)
	zoom_min = p_params.get("zoom_min", zoom_min)
	zoom_max = p_params.get("zoom_max", zoom_max)
	zoom_step = p_params.get("zoom_step", zoom_step)


## Actualiza la cámara. Llamar desde _process() con el delta del frame.
## [param target_position] es la posición mundo hacia la que lerpa cuando follow_target = true.
## Si follow_target = false y no hay drag activo, activa el edge-scroll.
func process(delta: float, target_position: Vector2) -> void:
	if follow_target:
		camera.position = camera.position.lerp(target_position, lerp_speed * delta)
	elif not _is_dragging:
		_edge_scroll(delta)


## Procesa eventos de input. Llamar desde _unhandled_input().
## Controles por defecto:
##   Botón derecho drag → pan libre (desactiva follow).
##   Scroll wheel       → zoom dentro de [zoom_min, zoom_max].
##   Space              → reactiva follow_target.
func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_is_dragging = true
		_drag_start = event.global_position
		_camera_drag_start = camera.position
		follow_target = false

	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_is_dragging = false

	if event is InputEventMouseMotion and _is_dragging:
		if camera.zoom.x == 0.0:
			return
		var drag_delta: Vector2 = (event.global_position - _drag_start) / camera.zoom.x
		camera.position = _camera_drag_start - drag_delta

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = Vector2.ONE * clampf(camera.zoom.x + zoom_step, zoom_min, zoom_max)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = Vector2.ONE * clampf(camera.zoom.x - zoom_step, zoom_min, zoom_max)

	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		follow_target = true


## Convierte una posición de pantalla (píxeles) a coordenadas mundo.
## Útil para transformar InputEventMouseButton.position al espacio del mapa.
## Retorna Vector2.ZERO si el zoom es cero (situación inválida).
func screen_to_world(screen_pixel: Vector2) -> Vector2:
	if camera.zoom.x == 0.0:
		return Vector2.ZERO
	return screen_pixel / camera.zoom + camera.global_position - viewport.get_visible_rect().size / camera.zoom / 2.0


## Desplaza la cámara según la posición del mouse cerca de los bordes.
## Solo actúa si el mouse está dentro del margen definido por edge_margin.
func _edge_scroll(delta: float) -> void:
	var mouse_pos := viewport.get_mouse_position()
	var screen_size := viewport.get_visible_rect().size
	var pan := Vector2.ZERO

	if mouse_pos.x < edge_margin:
		pan.x -= 1.0
	elif mouse_pos.x > screen_size.x - edge_margin:
		pan.x += 1.0

	if mouse_pos.y < edge_margin:
		pan.y -= 1.0
	elif mouse_pos.y > screen_size.y - edge_margin:
		pan.y += 1.0

	if pan != Vector2.ZERO:
		follow_target = false
		camera.position += pan.normalized() * edge_speed * delta
