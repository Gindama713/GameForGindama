extends CanvasLayer

@onready var canvas: Control = $Canvas


func _ready() -> void:
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	DisplaySettings.changed.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	if get_viewport() == null:
		return
	scale = Vector2.ONE * DisplaySettings.ui_scale
	canvas.size = get_viewport().get_visible_rect().size / DisplaySettings.ui_scale
