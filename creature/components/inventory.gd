class_name Inventory
extends CreatureComponent

signal changed
signal item_added(item: ItemDef, amount: int)
signal item_removed(item: ItemDef, amount: int)

var _held: Dictionary = {}  # 抓握肢体 -> 单件物品；没有背包和堆叠。


func requires() -> Array:
	return [Body]


func hand_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var body: Body = creature.get_component(Body) as Body
	for part in body.parts:
		if part.def.has_limb_type("grasp"):
			result.append({"part": part, "item": _held.get(part)})
	return result


func used_count() -> int:
	return _held.size()


func free_hands() -> int:
	var free: int = 0
	for slot in hand_slots():
		var part: BodyPart = slot["part"] as BodyPart
		if part.function_ok() and slot["item"] == null:
			free += 1
	return free


func can_add(item: ItemDef, amount: int) -> bool:
	return item != null and amount > 0 and item.validate().is_empty() and amount <= free_hands()


func add(item: ItemDef, amount: int) -> bool:
	if not can_add(item, amount):
		return false
	var remaining: int = amount
	for slot in hand_slots():
		var part: BodyPart = slot["part"] as BodyPart
		if part.function_ok() and slot["item"] == null:
			_held[part] = item
			remaining -= 1
			if remaining == 0:
				break
	changed.emit()
	item_added.emit(item, amount)
	return true


func count(item: ItemDef) -> int:
	return _held.values().count(item) if item != null else 0


func take_from_hand(hand_index: int) -> ItemDef:
	var slots: Array[Dictionary] = hand_slots()
	if hand_index < 0 or hand_index >= slots.size():
		return null
	var slot: Dictionary = slots[hand_index]
	var item: ItemDef = slot["item"] as ItemDef
	if item == null:
		return null
	_held.erase(slot["part"])
	changed.emit()
	item_removed.emit(item, 1)
	return item
