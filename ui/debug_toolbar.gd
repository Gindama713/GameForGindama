extends Control

## 调试工具栏：刷猪 / 清屏。挂在 CanvasLayer 左上角。
## 刷猪委托给 Main.spawn_pig_random()，工具栏自身不持有任何生成逻辑。

func _ready() -> void:
	anchor_left = 0.0; anchor_top = 0.0; anchor_right = 0.0; anchor_bottom = 0.0
	offset_left = PAD(); offset_top = PAD(); offset_right = PAD() + 200; offset_bottom = PAD() + 72
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6); add_child(vb)
	var spawn := Button.new(); spawn.text = "刷猪"; spawn.pressed.connect(_on_spawn); vb.add_child(spawn)
	var clear := Button.new(); clear.text = "清屏（猪）"; clear.pressed.connect(_on_clear); vb.add_child(clear)

func PAD() -> int:
	return 8

func _on_spawn() -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("spawn_pig_random"):
		main.spawn_pig_random()

## 清屏：委托 Main.clear_creatures()。
## 工具栏**不自己遍历节点树** —— 「生物装在哪个节点下」是 Main 的知识；
## 以前它遍历 Main 的直接子节点再按 `is Creature` 过滤，一旦生物挪进容器就静默失效。
func _on_clear() -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("clear_creatures"):
		main.clear_creatures()
