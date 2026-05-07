class_name MapCamera
extends RefCounted
## Controla la cámara del mapa: follow, drag, zoom, edge-scroll.

var camera: Camera2D = null
var viewport: Viewport = null
var follow_target: bool = true

var lerp_speed: float = 8.0
var edge_margin: float = 30.0
var edge_speed: float = 500.0
var zoom_min: float = 0.6
var zoom_max: float = 3.0
var zoom_step: float = 0.15

var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _camera_drag_start: Vector2 = Vector2.ZERO


func _init(p_camera: Camera2D, p_viewport: Viewport, p_params: Dictionary = {}) -> void:
	camera = p_camera
	viewport = p_viewport
	lerp_speed = p_params.get("lerp_speed", lerp_speed)
	edge_margin = p_params.get("edge_margin", edge_margin)
	edge_speed = p_params.get("edge_speed", edge_speed)
	zoom_min = p_params.get("zoom_min", zoom_min)
	zoom_max = p_params.get("zoom_max", zoom_max)
	zoom_step = p_params.get("zoom_step", zoom_step)


func process(delta: float, target_position: Vector2) -> void:
	if follow_target:
		camera.position = camera.position.lerp(target_position, lerp_speed * delta)
	elif not _is_dragging:
		_edge_scroll(delta)


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


func screen_to_world(screen_pixel: Vector2) -> Vector2:
	if camera.zoom.x == 0.0:
		return Vector2.ZERO
	return screen_pixel / camera.zoom + camera.global_position - viewport.get_visible_rect().size / camera.zoom / 2.0


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
