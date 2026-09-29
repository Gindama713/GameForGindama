class_name ItemDef
extends Resource

@export var id: StringName
@export var display_name: String
@export var icon: Texture2D


func validate() -> Array[String]:
	var errors: Array[String] = []
	if id == &"" or display_name.strip_edges().is_empty() or icon == null:
		errors.append("物品需要 id、display_name 和 icon")
	return errors
