class_name CameraRig
extends Camera2D

## 可平移（可选放大）的观察相机。
##
## 【用户拍板 2026-09-19】地图虽然扩到 100×100，**视野要和以前一样**：
##   - 默认 `zoom = 1.0` → 一屏仍是原来的 40×24 格（1280×768 px），**不是**自适应全图；
##   - **不许缩小**（`MIN_ZOOM = 1.0`）：一缩小就等于"看得比原来更多"，即"相机变大"，用户不要；
##   - 滚轮仍可**放大**（想看细节时用，`MAX_ZOOM = 4.0`）。
##   中键拖动 = 平移；WASD / 方向键 = 平移。
##
## 【为什么放 world/】它是"看世界"的镜头；UI 在 CanvasLayer 里，不受它影响。
## 【点击选取不受影响】Creature 用 `get_canvas_transform().affine_inverse()` 反算世界坐标，
##   相机正是 canvas transform 的一部分 -> 平移/放大后点选依旧对得上。

const PAN_SPEED := 900.0     # 键盘平移速度（世界像素/秒）
const ZOOM_STEP := 1.12      # 每次滚轮放大倍率
const MIN_ZOOM := 1.0        # 与"以前的一屏"一样大 —— 不允许更小
const MAX_ZOOM := 4.0

var _dragging := false

func _ready() -> void:
	make_current()
	zoom = Vector2.ONE                 # 视野与地图变大之前一致
	position = _world_size() * 0.5     # 摆在地图中心 —— 也正是高草区所在
	if get_viewport() != null:
		get_viewport().size_changed.connect(_clamp_position)

## 地图在世界里的像素尺寸（100×100 × 32 = 3200×3200）。
func _world_size() -> Vector2:
	if GridManager == null or GridManager.grid == null:
		return Vector2(1280.0, 768.0)
	return Vector2(GridManager.grid.width, GridManager.grid.height) * float(Grid.CELL_SIZE)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at_mouse(ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at_mouse(1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		# 屏幕位移 ÷ 放大倍率 = 世界位移
		position -= (event as InputEventMouseMotion).relative / zoom
		_clamp_position()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir == Vector2.ZERO:
		return
	position += dir.normalized() * PAN_SPEED * delta / zoom.x
	_clamp_position()

## 以鼠标为中心放大：缩放前后让「鼠标下的那个世界点」保持不动。
func _zoom_at_mouse(factor: float) -> void:
	var before := get_global_mouse_position()
	var z: float = clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	position += before - get_global_mouse_position()
	_clamp_position()

## 不让相机漂得离地图太远。
func _clamp_position() -> void:
	var ws := _world_size()
	position.x = clampf(position.x, 0.0, ws.x)
	position.y = clampf(position.y, 0.0, ws.y)
