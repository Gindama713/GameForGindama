extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game: Node2D = scene.instantiate() as Node2D
	add_child(game)
	var mother: Creature = null
	var father: Creature = null
	var victim: Creature = null
	for node in game.get_node("Creatures").get_children():
		var c := node as Creature
		if c == null or c.is_in_group(Groups.PLAYER):
			continue
		var lineage := c.get_component(Lineage) as Lineage
		var aging := c.get_component(Aging) as Aging
		if lineage == null or aging == null or not aging.is_fertile_age():
			continue
		if lineage.is_female() and mother == null:
			mother = c
		elif lineage.is_male() and father == null:
			father = c
		elif victim == null:
			victim = c
	if not _require(mother != null and father != null and victim != null, "缺少可用于测试的成年猪"):
		return
	var life: LifeDef = mother.def.life
	var registry: Node = get_node("/root/FamilyRegistry")
	var before: int = registry.call("living_count", mother.def)
	life.litter_min = 3
	life.litter_max = 3
	life.max_population = before + 2
	if not _require(int(game.call("_spawn_offspring", mother, game.get("player"))) == 0, "跨物种繁殖未被拒绝"):
		return
	if not _require(int(game.call("_spawn_offspring", mother, father)) == 2, "每胎数量或种群上限错误"):
		return
	if not _require(int(registry.call("living_count", mother.def)) == before + 2, "同物种活体计数错误"):
		return
	victim.die()
	if not _require(int(registry.call("living_count", mother.def)) == before + 1, "尸体被计入活体"):
		return
	life.litter_min = 1
	life.litter_max = 1
	if not _require(int(game.call("_spawn_offspring", mother, father)) == 1, "死亡后空出的名额不可用"):
		return
	if not _require(int(registry.call("living_count", mother.def)) == before + 2, "补生后的活体计数错误"):
		return
	var player: Creature = game.get("player") as Creature
	if not _require(player != null, "缺少主角"):
		return
	if not _require(int(game.call("_spawn_offspring", player, player)) == 1, "出生仍被写死为猪场景"):
		return
	var child: Creature = game.get_node("Creatures").get_children().back() as Creature
	if not _require(child != null and child.def == player.def and child.scene_file_path == player.scene_file_path, "后代物种未继承母体场景"):
		return
	print("reproduction_smoke: PASS")
	get_tree().quit()


func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error("reproduction_smoke: " + message)
		get_tree().quit(1)
	return ok
