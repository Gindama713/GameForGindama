extends Node


class SetupProbe extends CreatureComponent:
	var found_dependency: bool = false
	var initialized_dependency: bool = false

	func requires() -> Array:
		return [Body]

	func setup(host: Node) -> void:
		super.setup(host)
		found_dependency = creature.get_component(Body) != null

	func after_setup() -> void:
		initialized_dependency = not (creature.get_component(Body) as Body).parts.is_empty()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node2D = load("res://main.tscn").instantiate() as Node2D
	add_child(game)
	await get_tree().process_frame
	var original_window_size: Vector2i = get_window().size
	TimeSystem.paused = true
	var field: WorldObjectField = game.get_node("WorldObjects") as WorldObjectField
	var layer: Node2D = field.get_node("ObjectLayer") as Node2D
	var inspector: WorldObjectInspector = field.get_node("UI/Canvas/Inspector") as WorldObjectInspector
	var player: Creature = game.get("player") as Creature
	var mover: GridMover = player.get_component(GridMover) as GridMover
	var interaction: WorldObjectInteraction = field.get_node("Interaction") as WorldObjectInteraction
	var inventory: Inventory = player.get_component(Inventory) as Inventory
	var bag: PanelContainer = game.get_node("UI/Canvas/HandsHud") as PanelContainer
	var feed: Control = game.get_node("UI/Canvas/SensationFeed") as Control
	# 定义允许依赖组件排在后面；setup 时仍必须能查询它。
	var probe_script: Script = SetupProbe.new().get_script() as Script
	var probe: Creature = Creature.new()
	probe.def = player.def.duplicate() as CreatureDef
	probe.def.component_scripts = [probe_script, Body]
	probe.call("_build_components")
	var setup_probe: SetupProbe = probe.get_component(probe_script) as SetupProbe
	var setup_ok: bool = setup_probe.found_dependency and setup_probe.initialized_dependency
	probe.free()
	if not _require(setup_ok, "组件初始化仍依赖排列顺序"):
		return
	if not _check_hand_slots(player, bag):
		return
	if not await _check_smooth_step(player, mover):
		return
	var skills: Skills = player.get_component(Skills) as Skills
	if not _require(skills != null and player.def.skill_catalog.skills.size() == 12
			and skills.level(Sprint.SKILL_ID) == 0 and skills.experience(&"gathering") == 0.0,
			"主角没有独立的十二项初始技能"):
		return
	for definition: SkillDef in player.def.skill_catalog.skills:
		if not _require(skills.level(definition.id) == 0 and skills.experience(definition.id) == 0.0,
				"技能没有从零开始：%s" % definition.id):
			return
	skills.practice(&"knowledge", 100000.0)
	var pig_skills: Skills = (game.get_node("Creatures").get_child(0) as Creature).get_component(Skills) as Skills
	var missing_skills_def := CreatureDef.new()
	missing_skills_def.skill_catalog = player.def.skill_catalog
	if not _require(missing_skills_def.validate().has("每个生物都需要 Skills 组件"),
			"新物种漏配技能没有在定义校验中报错"):
		return
	if not _require(pig_skills != null and pig_skills.creature.def.skill_catalog == player.def.skill_catalog,
			"玩家与猪没有复用同一技能定义"):
		return
	for id: StringName in SkillDef.ATTRIBUTE_NAMES:
		if not _require(skills.attributes.has(id) and pig_skills.attributes.has(id),
				"不同生物缺少共同属性：%s" % id):
			return
	if not _require(skills.level(&"knowledge") == Skills.MAX_LEVEL
			and skills.experience(&"knowledge") == 0.0 and pig_skills.level(&"knowledge") == 0,
			"等级超过 100，或生物间共享了技能经验"):
		return
	var running_before: float = skills.experience(Sprint.SKILL_ID)
	var sprint: Sprint = player.get_component(Sprint) as Sprint
	var run_direction: Vector2i = mover.free_directions()[0]
	sprint.set("_running", true)
	var ran: bool = mover.try_step(run_direction)
	sprint.set("_running", false)
	if not _require(ran and skills.experience(Sprint.SKILL_ID) > running_before
			and mover.try_step(-run_direction), "成功跑过一格后没有增加跑步经验"):
		return
	if not _require(skills.experience_to_next(Sprint.SKILL_ID) == 10.0, "初级经验门槛错误"):
		return
	skills.practice(Sprint.SKILL_ID, 40.0)
	if not _require(skills.level(Sprint.SKILL_ID) >= 1 and skills.experience_to_next(Sprint.SKILL_ID) > 10.0,
			"跑步升级或递增经验门槛失效"):
		return
	var objects: Array[WorldObject] = field.all_objects()
	var counts: Dictionary = {}
	var blocker: WorldObject = null
	var flower: WorldObject = null
	var small_rock: WorldObject = null
	var boulder: WorldObject = null
	var mature_trees: int = 0
	var young_trees: int = 0
	if not _require(not objects.is_empty(), "没有生成地物"):
		return
	for object in objects:
		var definition: WorldObjectDef = object.definition
		counts[definition.id] = int(counts.get(definition.id, 0)) + 1
		if not _require(GridManager.feature_at(object.coord) == object and field.object_at(object.coord) == object,
				"地物注册表与格子没有引用同一对象"):
			return
		var cell: Grid.Cell = GridManager.grid.get_cell(object.coord)
		if not _require(WorldObjectGenerator.fits_land(GridManager.grid, object.coord, definition)
				and WorldObjectGenerator.fits_habitat(GridManager.grid, object.coord, definition)
				and float(definition.terrain_weights.get(cell.terrain, 0.0)) > 0.0, "地物越界、落水或忽略地形偏好"):
			return
		var sprite: Sprite2D = layer.get_node("Object_%d" % object.id) as Sprite2D
		var center: Vector2 = GridManager.grid.grid_to_world(object.coord) + Vector2.ONE * Grid.CELL_SIZE * 0.5
		if not _require(sprite.texture == object.visual_texture() and sprite.position == center
				and sprite.offset == sprite.texture.get_size() * (Vector2(0.5, 0.5) - object.visual_anchor())
				and is_equal_approx(sprite.rotation_degrees, definition.rotation_degrees) and sprite.modulate == Color.WHITE and sprite.self_modulate == Color.WHITE
				and is_equal_approx(sprite.scale.y * sprite.texture.get_height(), object.visual_height_cells() * Grid.CELL_SIZE),
				"渲染改了原色、旋转、尺寸或格子中心"):
			return
		if object.has_growth():
			if object.growth_percent() >= 60:
				mature_trees += 1
			else:
				young_trees += 1
		if object.blocks_movement() and blocker == null:
			blocker = object
		elif definition.gather_item == preload("res://items/data/wildflowers.tres") and GridManager.can_enter(object.coord) and flower == null:
			flower = object
		if definition.gather_item == preload("res://items/data/small_stone.tres") and GridManager.can_enter(object.coord):
			small_rock = object
		if definition.id == &"boulder":
			boulder = object
	for definition in field.definitions:
		if not _require(counts.has(definition.id), "某类地物未生成：%s" % definition.id):
			return

	# 树的整个外观都避开草地、花与石头；花片包含相邻的独立可采集植株。
	var flowers_together: int = 0
	for object in objects:
		if object.definition == flower.definition:
			for direction in GridMover.DIRS:
				var neighbor: WorldObject = field.object_at(object.coord + direction)
				if neighbor != null and neighbor.definition == object.definition:
					flowers_together += 1
					break
		if not object.definition.excluded_terrains.is_empty():
			var bounds: Rect2 = object.definition.bounds_at(object.coord)
			var first: Vector2i = Vector2i(bounds.position.floor())
			var last: Vector2i = Vector2i(bounds.end.ceil()) - Vector2i.ONE
			for y in range(first.y, last.y + 1):
				for x in range(first.x, last.x + 1):
					var covered: Vector2i = Vector2i(x, y)
					if not _require(not GridManager.allows_terrain(covered, Terrain.GRASS)
							and not GrassField.call("_can_colonize", covered), "草能扩散进入树冠"):
						return
			for other in objects:
				if other != object and not _require(not object.definition.bounds_at(object.coord).intersects(other.definition.bounds_at(other.coord)),
						"树冠覆盖了石头、花或其他树"):
					return
	if not _require(int(counts[&"pine_tree"]) < 500 and int(counts[&"flowers"]) > 50
			and flowers_together * 2 > int(counts[&"flowers"]), "树仍太密、花太少或没有形成花片"):
		return
	if not _require(mature_trees * 10 >= (mature_trees + young_trees) * 7 and young_trees > 0,
			"野生树没有以 60% 以上的树为主，或完全没有幼树"):
		return

	# 在没有地物的同地形副本上重跑生成器，避免把已有地物当成初始世界。
	var empty_grid: Grid = Grid.new(GridManager.grid.width, GridManager.grid.height)
	for coord: Vector2i in empty_grid.cells:
		empty_grid.get_cell(coord).terrain = GridManager.grid.get_cell(coord).terrain
	var generated: Array[WorldObjectGenerator.Placement] = WorldObjectGenerator.generate(empty_grid, WorldSeed.value, field.definitions, field.region_noise)
	var repeated: Array[WorldObjectGenerator.Placement] = WorldObjectGenerator.generate(empty_grid, WorldSeed.value, field.definitions, field.region_noise)
	var changed: Array[WorldObjectGenerator.Placement] = WorldObjectGenerator.generate(empty_grid, WorldSeed.value + 1, field.definitions, field.region_noise)
	if not _require(_signature(generated) == _signature(repeated) and _signature(generated) != _signature(changed),
			"种子不可复现或换种子没有改变世界"):
		return
	if not _require(generated.size() == objects.size(), "生成结果没有全部落入世界"):
		return
	for i in generated.size():
		if not _require(generated[i].coord == objects[i].coord and generated[i].definition == objects[i].definition,
				"真实地物与同种子生成结果不一致"):
			return
	# 整片区域的密度曲线为零时，任何局部噪声都不能另行生成地物。
	var absent: Array[WorldObjectDef] = []
	for definition in field.definitions:
		var copy: WorldObjectDef = definition.duplicate() as WorldObjectDef
		copy.region_density = Curve.new()
		copy.region_density.add_point(Vector2.ZERO)
		copy.region_density.add_point(Vector2(1, 0))
		absent.append(copy)
	if not _require(WorldObjectGenerator.generate(empty_grid, WorldSeed.value, absent, field.region_noise).is_empty(),
			"生成器忽略共享区域密度"):
		return
	if not _require(small_rock != null and not small_rock.blocks_movement() and boulder != null and boulder.blocks_movement(),
			"小石头与岩石通行规则没有区分"):
		return
	if not _require(_routes_exist(player.coord), "玩家无法到达可食草或湖岸"):
		return
	if not _require(blocker != null and flower != null, "缺少阻挡物或可穿过的花"):
		return
	layer.hide()
	if not _require(not player.can_place_at(blocker.coord) and not mover.is_cell_free(blocker.coord)
			and not mover.try_step(blocker.coord - player.coord)
			and not GridManager.occupy(blocker.coord, player) and field.object_at(blocker.coord) == blocker,
			"隐藏渲染后阻挡或世界状态消失"):
		return
	layer.show()
	var original_coord: Vector2i = player.coord
	if not _require(player.move_to(flower.coord), "主角无法进入花所在格"):
		return
	var shared_cell: Grid.Cell = GridManager.grid.get_cell(flower.coord)
	if not _require(shared_cell.content == player and shared_cell.feature == flower and field.object_at(flower.coord) == flower,
			"花与生物没有独立占格"):
		return
	if not _require(player.move_to(original_coord), "无法恢复主角位置"):
		return

	# 走真实鼠标事件入口，在镜头中心点击阻挡物；UI 应查询逻辑对象。
	var camera: Camera2D = game.get_node("Camera2D") as Camera2D
	camera.set("target", null)
	camera.position = GridManager.grid.grid_to_world(blocker.coord) + Vector2.ONE * Grid.CELL_SIZE * 0.5
	camera.force_update_scroll()
	await get_tree().process_frame
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = get_viewport().canvas_transform * camera.position
	get_viewport().push_input(mouse, true)
	await get_tree().process_frame
	if not _require(inspector.visible and inspector.get("_selected") == blocker, "鼠标点击没有检视真实地物"):
		return
	var before: int = GridManager.free_count()
	if not _require(field.damage(blocker.coord, 1) and blocker.integrity == blocker.definition.max_integrity - 1,
			"受损没有更新对象状态"):
		return
	var details: Label = inspector.get("_details") as Label
	if not _require(details.text.contains("完整度 %d /" % blocker.integrity), "检视面板没有同步受损"):
		return
	if not _require(field.damage(blocker.coord, blocker.integrity) and field.object_at(blocker.coord) == null
			and GridManager.feature_at(blocker.coord) == null and GridManager.can_enter(blocker.coord)
			and GridManager.free_count() == before + 1 and not inspector.visible
			and not layer.has_node("Object_%d" % blocker.id), "移除后状态、通行、空格缓存或渲染没有同步"):
		return
	var replacement: WorldObject = field.plant(blocker.definition, blocker.coord)
	if not _require(replacement != null and replacement.id > blocker.id and GridManager.free_count() == before
			and not GridManager.is_walkable(blocker.coord) and replacement.growth_percent() == 0
			and field.object_at_world_position(GridManager.grid.grid_to_world(blocker.coord) + Vector2.ONE * Grid.CELL_SIZE * 0.5) == replacement
			and field.plant(blocker.definition, blocker.coord) == null, "种下橡子没有占格、可见、阻挡或防止重叠"):
		return
	inspector.inspect(replacement.coord)
	var growth_bar: ProgressBar = inspector.get("_growth_bar") as ProgressBar
	var seed_sprite: Sprite2D = layer.get_node("Object_%d" % replacement.id) as Sprite2D
	if not _require((inspector.get("_growth_row") as HBoxContainer).visible and growth_bar.value == 0.0
			and seed_sprite.texture == blocker.definition.seed_texture, "种植时没有显示橡子和 0% 生长线"):
		return
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/tree-seed-preview.png"))
	if not _require(replacement.growth_percent() == 0, "暂停时树仍然生长"):
		return
	var original_time: float = TimeSystem.elapsed
	TimeSystem.elapsed += TimeSystem.MINUTES_PER_DAY
	field.call("_on_tick", float(TimeSystem.MINUTES_PER_DAY))
	if not _require(replacement.growth_percent() == 5 and growth_bar.value == 5.0
			and seed_sprite.texture == blocker.definition.texture and seed_sprite.position == GridManager.grid.grid_to_world(replacement.coord) + Vector2.ONE * Grid.CELL_SIZE * 0.5,
			"生长一天后没有从橡子变成固定根部的幼树"):
		return
	if OS.get_cmdline_user_args().has("--capture"):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/tree-sapling-preview.png"))
	TimeSystem.elapsed += blocker.definition.growth_duration_minutes - TimeSystem.MINUTES_PER_DAY
	field.call("_on_tick", blocker.definition.growth_duration_minutes)
	if not _require(replacement.growth_percent() == 100 and growth_bar.value == 100.0
			and is_equal_approx(seed_sprite.scale.y * seed_sprite.texture.get_height(), blocker.definition.height_cells * Grid.CELL_SIZE),
			"树未按游戏时间长到 100%，或画面尺寸未同步"):
		return
	TimeSystem.elapsed = original_time
	await get_tree().process_frame
	for size_value: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540)]:
		get_window().size = size_value
		await get_tree().process_frame
		await get_tree().process_frame
		var rect: Rect2 = inspector.get_global_rect()
		var bag_rect: Rect2 = bag.get_global_rect()
		if not _require(rect.size.x > 0.0 and rect.size.y > 0.0
				and Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(rect)
				and Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(bag_rect),
				"检视或物品面板在窗口中越界"):
			return
	inspector.hide()
	get_window().size = original_window_size
	camera.position = player.position
	camera.force_update_scroll()
	await get_tree().process_frame
	await get_tree().process_frame
	# 两件就是两件；同类物品也不能靠堆叠绕过双手。
	var entries: Array = feed.get("_entries")
	var flower_item: ItemDef = flower.definition.gather_item
	if not _require(inventory.hand_slots().size() == 2 and inventory.free_hands() == 2
			and not inventory.can_add(flower_item, 3), "携带量没有来自两只抓握肢体"):
		return
	if not _require(not interaction.gather(flower.coord) and inventory.used_count() == 0
			and field.object_at(flower.coord) == flower, "暂停采集改变了物品或世界"):
		return
	TimeSystem.paused = false
	if not _require(not interaction.gather(flower.coord) and inventory.used_count() == 0, "远距离采集成功"):
		return
	if not _require(player.move_to(flower.coord), "无法进入待采集花所在格"):
		return
	var sleep: Sleep = player.get_component(Sleep) as Sleep
	sleep.set("_state", Sleep.State.ASLEEP)
	if not _require(not interaction.gather(flower.coord) and field.object_at(flower.coord) == flower, "睡着时仍能采集"):
		return
	sleep.set("_state", Sleep.State.AWAKE)
	var body: Body = player.get_component(Body) as Body
	var original_hp: Dictionary = {}
	for part in body.parts:
		if part.def.has_limb_type("grasp"):
			original_hp[part] = part.hp
			part.hp = 0
	if not _require(not interaction.gather(flower.coord) and inventory.free_hands() == 0, "失去抓握能力仍能采集"):
		return
	if not _require(skills.experience(&"gathering") == 0.0, "失败采集产生了经验"):
		return
	for part: BodyPart in original_hp:
		part.hp = original_hp[part]
	var hand: BodyPart = inventory.hand_slots()[0]["part"] as BodyPart
	hand.hp = 0
	if not _require(inventory.free_hands() == 1 and inventory.can_add(flower_item, 1)
			and not inventory.add(flower_item, 2) and inventory.used_count() == 0,
			"失去一只手仍能拿两件，或批量拿取失败后留下半件状态"):
		return
	hand.hp = original_hp[hand]
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	get_viewport().push_input(key, true)
	TimeSystem.paused = true
	if not _require(field.object_at(flower.coord) == null and GridManager.feature_at(flower.coord) == null
			and not layer.has_node("Object_%d" % flower.id)
			and inventory.count(flower_item) == 1
			and skills.experience(&"gathering") > 0.0
			and String(entries.back()["text"]).contains(flower_item.display_name),
			"E 采花没有同步世界、物品和提示"):
		return
	if not _check_hand_slots(player, bag):
		return
	# 点玩家脚下的石头也能拾取，不能先被生物的点击入口截走。
	if not _require(player.move_to(small_rock.coord), "无法站在小石头上"):
		return
	await _click_world(small_rock.coord, camera)
	var gathering_after_flower: float = skills.experience(&"gathering")
	if not _require(inventory.count(small_rock.definition.gather_item) == 1
			and field.object_at(small_rock.coord) == null and inventory.used_count() == 2,
			"左键直接点击石头未拾取，或超出双手"):
		return
	if not _require(skills.experience(&"gathering") == gathering_after_flower,
			"拾取石头错误地增加了采集经验"):
		return
	if not _check_hand_slots(player, bag):
		return
	var next_flower: WorldObject = null
	for object in field.all_objects():
		if object.definition == flower.definition and GridManager.can_enter(object.coord):
			next_flower = object
			break
	if not _require(next_flower != null and player.move_to(next_flower.coord), "找不到下一株花"):
		return
	var count_before: int = field.all_objects().size()
	await _click_world(next_flower.coord, camera)
	if not _require(inventory.used_count() == 2 and field.object_at(next_flower.coord) == next_flower
			and skills.experience(&"gathering") == gathering_after_flower
			and field.all_objects().size() == count_before and layer.has_node("Object_%d" % next_flower.id)
			and inspector.visible and (inspector.get("_hint") as Label).text.contains("空闲"),
			"满手左键拾取删掉了地物，或没有解释容量限制"):
		return
	var bag_list: VBoxContainer = bag.get("_list") as VBoxContainer
	await get_tree().process_frame
	if not _require(bag.visible and bag_list.get_child_count() == 2,
			"面板没有显示两只手"):
		return
	var backpack := (game.get_node("UI/Canvas/PlayerPanel") as Control).get("_backpack_view") as BackpackView
	var transfer_events: Array[String] = []
	inventory.item_added.connect(func(_item: ItemDef, _amount: int) -> void: transfer_events.append("added"))
	inventory.item_removed.connect(func(_item: ItemDef, _amount: int) -> void: transfer_events.append("removed"))
	(game.get_node("UI/Canvas/PlayerPanel") as Control).call("_toggle_drawer", 1)
	await get_tree().process_frame
	var hand_rows := backpack.get("_hands") as VBoxContainer
	var bag_rows := backpack.get("_bag") as VBoxContainer
	(hand_rows.get_child(1).get_child(2) as Button).pressed.emit()
	if not _require(inventory.used_count() == 1 and inventory.bag_used_count() == 1
			and inventory.free_hands() == 1 and inventory.count(small_rock.definition.gather_item) == 1
			and transfer_events.is_empty(), "收进背包没有腾出手，或触发了拾取/丢弃事件"):
		return
	(bag_rows.get_child(0).get_child(2) as Button).pressed.emit()
	if not _require(inventory.used_count() == 2 and inventory.bag_used_count() == 0
			and transfer_events.is_empty(), "从背包取出没有回到手中"):
		return
	# 用面板放下石头，再点检视按钮拿第二株花；最后两手各拿一朵花。
	var drop: Button = bag_list.get_child(1).get_child(0).get_child(2) as Button
	var frame := bag_list.get_child(1) as Control
	var click := _left_click()
	click.position = frame.get_global_transform_with_canvas() * (frame.size * 0.5)
	get_viewport().push_input(click, true)
	click.pressed = false
	get_viewport().push_input(click, true)
	await get_tree().process_frame
	if not _require(drop.visible, "鼠标点击手持框没有打开操作"):
		return
	TimeSystem.paused = false
	drop.pressed.emit()
	TimeSystem.paused = true
	if not _require(inventory.used_count() == 1 and inventory.count(small_rock.definition.gather_item) == 0
			and field.all_objects().size() == count_before + 1, "放下未还原世界物品或腾出手"):
		return
	if not _check_hand_slots(player, bag):
		return
	var dropped: WorldObject = null
	for object in field.all_objects():
		if object.definition == small_rock.definition and absi(object.coord.x - player.coord.x) + absi(object.coord.y - player.coord.y) <= 1:
			dropped = object
			break
	if not _require(dropped != null and GridManager.feature_at(dropped.coord) == dropped
			and String(entries.back()["text"]).contains("放下"), "放下没有建立真实地物和提示"):
		return
	TimeSystem.paused = false
	inspector.inspect(next_flower.coord)
	inspector.call("_refresh_action")
	var action: Button = inspector.get("_action") as Button
	if not _require(not action.disabled, "腾出手后仍不能采集"):
		return
	action.pressed.emit()
	if not _require(inventory.used_count() == 2 and inventory.count(flower_item) == 2
			and skills.experience(&"gathering") > gathering_after_flower
			and not inventory.can_add(flower_item, 1) and field.object_at(next_flower.coord) == null,
			"两手同类物品被合并成无限堆叠，或按钮未采集"):
		return
	var gathered_experience: float = skills.experience(&"gathering")
	interaction.drop_hand(0)
	var dropped_flower: WorldObject = null
	for object in field.all_objects():
		if (object.definition == flower.definition and object.dropped_by_creature
				and absi(object.coord.x - player.coord.x) + absi(object.coord.y - player.coord.y) <= 1):
			dropped_flower = object
			break
	if not _require(dropped_flower != null and interaction.gather(dropped_flower.coord)
			and skills.experience(&"gathering") == gathered_experience,
			"放下再捡起野花刷出了采集经验"):
		return
	var denied_count: int = field.all_objects().size()
	key.pressed = true
	get_viewport().push_input(key, true)
	TimeSystem.paused = true
	if not _require(inventory.count(flower_item) == 2 and field.all_objects().size() == denied_count,
			"满手仍能按 E 拿第三件"):
		return
	if not _require(player.move_to(original_coord), "采集检查后无法恢复主角"):
		return
	camera.position = player.position
	camera.force_update_scroll()
	await get_tree().process_frame
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--capture"):
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var path: String = ProjectSettings.globalize_path("res://").path_join(".godot/world-objects-preview.png")
		if not _require(get_viewport().get_texture().get_image().save_png(path) == OK, "无法保存预览"):
			return
		for object in field.all_objects():
			if object.definition == flower.definition:
				flower = object
				break
		camera.position = GridManager.grid.grid_to_world(flower.coord) + Vector2.ONE * Grid.CELL_SIZE * 0.5
		camera.force_update_scroll()
		inspector.inspect(flower.coord)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var flower_path: String = ProjectSettings.globalize_path("res://").path_join(".godot/flowers-preview.png")
		if not _require(get_viewport().get_texture().get_image().save_png(flower_path) == OK, "无法保存野花预览"):
			return
		if not await _check_occlusion(game, player, layer, camera):
			return
	field.clear()
	if not _require((GridManager.get("_terrain_exclusions") as Dictionary).is_empty(), "地物清除后仍然禁止草扩散"):
		return
	print("world_object_smoke: PASS counts=", counts, " trees 60+ = ", mature_trees, "/", mature_trees + young_trees,
			" seed, growth, routes, terrain, mouse/E, inventory hands/drop, smooth steps, rendered Y sorting")
	get_tree().quit()


func _click_world(coord: Vector2i, camera: Camera2D) -> void:
	camera.position = GridManager.grid.grid_to_world(coord) + Vector2.ONE * Grid.CELL_SIZE * 0.5
	camera.force_update_scroll()
	await get_tree().process_frame
	await get_tree().process_frame
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = get_viewport().canvas_transform * camera.position
	TimeSystem.paused = false
	get_viewport().push_input(mouse, true)
	mouse.pressed = false
	get_viewport().push_input(mouse, true)
	TimeSystem.paused = true


func _check_hand_slots(player: Creature, panel: PanelContainer) -> bool:
	var inventory: Inventory = player.get_component(Inventory) as Inventory
	var body_sprite: Sprite2D = player.get_node("Sprite2D") as Sprite2D
	if not _require(is_zero_approx(body_sprite.position.y + body_sprite.texture.get_height() * body_sprite.scale.y * 0.5),
			"身体缩放后没有保持脚下接地点"):
		return false
	var rows: VBoxContainer = panel.get("_list") as VBoxContainer
	var slots: Array[Dictionary] = inventory.hand_slots()
	if not _require(not body_sprite.has_node("Hands") and rows.get_child_count() == slots.size(), "角色仍有多余的手部精灵，或物品栏缺少双手格"):
		return false
	for i in slots.size():
		var part: BodyPart = slots[i]["part"] as BodyPart
		var item: ItemDef = slots[i]["item"] as ItemDef
		var expected: Texture2D = item.icon if item != null else part.def.grasp_texture
		var column := rows.get_child(i).get_child(0)
		var icon: TextureRect = column.get_child(0) as TextureRect
		var label: Label = column.get_child(1) as Label
		var drop: Button = column.get_child(2) as Button
		if not _require(expected != null and icon.texture == expected
				and icon.flip_h == part.def.grasp_flip_h
				and label.text.begins_with(part.def.grasp_label) and drop.visible == (item != null and i == int(panel.get("_selected_hand"))),
				"物品栏空手/持物图片、左右朝向、名称或放下状态不同步"):
			return false
	var first: BodyPart = slots[0]["part"] as BodyPart
	var second: BodyPart = slots[1]["part"] as BodyPart
	return _require(first.def.grasp_label != second.def.grasp_label
			and first.def.grasp_flip_h != second.def.grasp_flip_h, "物品栏左右手名称或镜像相同")


func _left_click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


func _check_smooth_step(player: Creature, mover: GridMover) -> bool:
	var origin: Vector2i = player.coord
	var visual_origin: Vector2 = player.position
	var initial_time: float = TimeSystem.elapsed
	var directions: Array[Vector2i] = mover.free_directions()
	if not _require(not directions.is_empty() and not mover.try_step(Vector2i.ONE), "无可走格，或允许斜向跨格"):
		return false
	var direction: Vector2i = directions[0]
	if not _require(mover.try_step(direction) and player.coord == origin + direction
			and player.position == visual_origin and GridManager.cell_at(player.coord.x, player.coord.y).content == player
			and GridManager.cell_at(origin.x, origin.y).content == null, "迈步时逻辑占格与画面位置没有分离"):
		return false
	await get_tree().process_frame
	if not _require(player.position == visual_origin, "暂停时画面仍在移动"):
		return false
	var body_sprite: Sprite2D = player.get_node("Sprite2D") as Sprite2D
	var visual_grid: Vector2i = GridManager.grid.world_to_grid(body_sprite.global_position)
	var selection: Array[Node] = []
	EventBus.creature_clicked.connect(func(target: Node) -> void: selection.append(target), CONNECT_ONE_SHOT)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = get_viewport().canvas_transform * body_sprite.global_position
	player._unhandled_input(click)
	if not _require(visual_grid != player.coord and selection == [player], "移动中点击仍依据新逻辑格，未命中画面中的生物"):
		return false
	var first_duration: float = float(player.get("_visual_duration"))
	TimeSystem.elapsed += first_duration * 0.5
	player.call("_process", 0.0)
	var halfway: Vector2 = player.position
	var destination: Vector2 = GridManager.grid.grid_to_world(player.coord) + Vector2(0.5, 1.0) * Grid.CELL_SIZE
	if not _require(halfway.distance_to(visual_origin.lerp(destination, 0.5)) < 0.01, "移动没有平滑经过半格"):
		return false
	# 下一步来得更快时从当前位置接续，不能弹回上一格或瞬移到新格。
	if not _require(mover.try_step(-direction) and player.position == halfway and player.coord == origin
			and float(player.get("_visual_duration")) <= first_duration * 0.5 + 0.001,
			"快速反向迈步发生画面跳变，或动画没有跟上实际步频"):
		return false
	TimeSystem.elapsed += float(player.get("_visual_duration"))
	player.call("_process", 0.0)
	if not _require(player.position == visual_origin and not player.is_processing(), "动画结束后没有回到目标格或停止逐帧处理"):
		return false
	TimeSystem.elapsed = initial_time
	print("smooth grid step: occupied destination immediately, paused, halfway, reversed without a snap")
	return true


func _check_occlusion(game: Node2D, player: Creature, layer: Node2D, camera: Camera2D) -> bool:
	TimeSystem.paused = true
	var tree: Sprite2D = null
	for child: Sprite2D in layer.get_children():
		child.hide()
		if child.texture == preload("res://world/objects/data/pine_tree.tres").texture:
			tree = child
	if not _require(tree != null, "缺少遮挡检查用树"):
		return false
	(game.get_node("UI") as CanvasLayer).hide()
	(game.get_node("WorldObjects/UI") as CanvasLayer).hide()
	var body_sprite: Sprite2D = player.get_node("Sprite2D") as Sprite2D
	body_sprite.show()
	camera.zoom = Vector2.ONE * 4
	camera.position = tree.position + Vector2(0, -Grid.CELL_SIZE)
	camera.force_update_scroll()
	var original_position: Vector2 = player.position
	# 测试色只用于区分玩家与白色树，恢复后保存原色预览。
	player.modulate = Color.MAGENTA
	var measurements: Array[int] = []
	for offset in [-Grid.CELL_SIZE * 0.5, Grid.CELL_SIZE * 0.25]:
		player.position = tree.position + Vector2(0, offset)
		tree.hide()
		var uncovered: int = await _player_pixels()
		tree.show()
		var covered: int = await _player_pixels()
		measurements.append_array([uncovered, covered])
	if not _require(measurements[0] > 0 and measurements[1] < measurements[0] * 0.8
			and measurements[2] > 0 and measurements[3] >= measurements[2] * 0.98, "树后没有遮挡、或树前仍被遮挡：%s" % [measurements]):
		return false
	player.modulate = Color.WHITE
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var preview_dir: String = ProjectSettings.globalize_path("res://").path_join(".godot")
	get_viewport().get_texture().get_image().save_png(preview_dir.path_join("creature-tree-front.png"))
	player.position = tree.position + Vector2(0, -Grid.CELL_SIZE * 0.5)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(preview_dir.path_join("creature-tree-behind.png"))
	player.position = original_position
	print("rendered Y sorting: uncovered/covered behind, front = ", measurements)
	return true


func _player_pixels() -> int:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var count: int = 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r > 0.5 and pixel.b > 0.5 and pixel.g < 0.2:
				count += 1
	return count


func _routes_exist(start: Vector2i) -> bool:
	var queue: Array[Vector2i] = [start]
	var seen: Dictionary = {start: true}
	var cursor: int = 0
	var food: bool = false
	var bank: bool = false
	while cursor < queue.size():
		var coord: Vector2i = queue[cursor]
		cursor += 1
		food = food or GrassField.is_edible(coord)
		for direction in GridMover.DIRS:
			var next: Vector2i = coord + direction
			var cell: Grid.Cell = GridManager.grid.get_cell(next)
			bank = bank or (cell != null and cell.terrain == Terrain.WATER)
			if not seen.has(next) and GridManager.is_walkable(next):
				seen[next] = true
				queue.append(next)
		if food and bank:
			return true
	return false


func _signature(items: Array[WorldObjectGenerator.Placement]) -> String:
	var result: String = ""
	for item in items:
		result += "%s|%s|%.3f\n" % [item.definition.id, item.coord, item.initial_growth]
	return result.sha256_text()


func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error("world_object_smoke: " + message)
		get_tree().quit(1)
	return ok
