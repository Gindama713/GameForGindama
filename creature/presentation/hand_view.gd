extends Node2D

## 身体 Sprite 的子节点：继承成长、隐蔽与死亡外观，只订阅物品变化。
@export_range(0.1, 0.5) var height_fraction: float = 0.28

var _actor: Creature
var _inventory: Inventory
var _views: Dictionary[BodyPart, Sprite2D] = {}


func _ready() -> void:
	_bind.call_deferred()


func _bind() -> void:
	_actor = owner as Creature
	if _actor == null or _actor.def == null or _actor.def.texture == null:
		return
	_inventory = _actor.get_component(Inventory) as Inventory
	if _inventory == null:
		return
	_inventory.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for slot in _inventory.hand_slots():
		var part: BodyPart = slot["part"] as BodyPart
		var item: ItemDef = slot["item"] as ItemDef
		var sprite: Sprite2D = _views.get(part)
		if sprite == null:
			sprite = Sprite2D.new()
			_views[part] = sprite
			add_child(sprite)
		sprite.texture = item.icon if item != null else part.def.grasp_texture
		sprite.flip_h = part.def.grasp_flip_h
		sprite.position = part.def.grasp_offset * _actor.def.texture.get_size()
		if sprite.texture != null:
			sprite.scale = Vector2.ONE * _actor.def.texture.get_height() * height_fraction / sprite.texture.get_height()
