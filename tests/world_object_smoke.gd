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
	var inspector: WorldObjectInspector = field.get_node("UI/Inspector") as WorldObjectInspector
	var player: Creature = game.get("player") as Creature
	var mover: GridMover = player.get_component(GridMover) as GridMover
	var interaction: WorldObjectInteraction = field.get_node("Interaction") as WorldObjectInteraction
	var inventory: Inventory = player.get_component(Inventory) as Inventory
	var bag: PanelContainer = game.get_node("UI/Inventory") as PanelContainer
	var feed: Control = game.get_node("UI/SensationFeed") as Control
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
	if not _check_hands(player, bag):
		return
	var objects: Array[WorldObject] = field.all_objects()
	var counts: Dictionary = {}
	var blocker: WorldObject = null
	var flower: WorldObject = null
	var small_rock: WorldObject = null
	var boulder: WorldObject = null
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
		if not _require(sprite.texture == definition.texture and sprite.position == center
				and sprite.offset == definition.texture.get_size() * (Vector2(0.5, 0.5) - definition.anchor)
				and is_equal_approx(sprite.rotation_degrees, definition.rotation_degrees) and sprite.modulate == Color.WHITE and sprite.self_modulate == Color.WHITE
				and is_equal_approx(sprite.scale.y * definition.texture.get_height(), definition.height_cells * Grid.CELL_SIZE),
				"渲染改了原色、旋转、尺寸或格子中心"):
			return
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
	var replacement: WorldObject = field.add(blocker.definition, blocker.coord)
	if not _require(replacement != null and replacement.id > blocker.id and GridManager.free_count() == before
			and not GridManager.is_walkable(blocker.coord), "重新放置没有恢复阻挡或对象身份重复"):
		return
	inspector.inspect(replacement.coord)
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
			and String(entries.back()["text"]).contains(flower_item.display_name),
			"E 采花没有同步世界、物品和提示"):
		return
	if not _check_hands(player, bag):
		return
	# 点玩家脚下的石头也能拾取，不能先被生物的点击入口截走。
	if not _require(player.move_to(small_rock.coord), "无法站在小石头上"):
		return
	await _click_world(small_rock.coord, camera)
	if not _require(inventory.count(small_rock.definition.gather_item) == 1
			and field.object_at(small_rock.coord) == null and inventory.used_count() == 2,
			"左键直接点击石头未拾取，或超出双手"):
		return
	if not _check_hands(player, bag):
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
			and field.all_objects().size() == count_before and layer.has_node("Object_%d" % next_flower.id)
			and inspector.visible and (inspector.get("_hint") as Label).text.contains("空闲"),
			"满手左键拾取删掉了地物，或没有解释容量限制"):
		return
	var bag_toggle: Button = bag.get("_toggle") as Button
	bag_toggle.button_pressed = true
	var bag_list: VBoxContainer = bag.get("_list") as VBoxContainer
	await get_tree().process_frame
	if not _require(bag.visible and bag_list.visible and bag_list.get_child_count() == 2,
			"面板没有显示两只手"):
		return
	# 用面板放下石头，再点检视按钮拿第二株花；最后两手各拿一朵花。
	var drop: Button = bag_list.get_child(1).get_child(2) as Button
	TimeSystem.paused = false
	drop.pressed.emit()
	TimeSystem.paused = true
	if not _require(inventory.used_count() == 1 and inventory.count(small_rock.definition.gather_item) == 0
			and field.all_objects().size() == count_before + 1, "放下未还原世界物品或腾出手"):
		return
	if not _check_hands(player, bag):
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
			and not inventory.can_add(flower_item, 1) and field.object_at(next_flower.coord) == null,
			"两手同类物品被合并成无限堆叠，或按钮未采集"):
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
	print("world_object_smoke: PASS counts=", counts, " seed, routes, terrain, mouse/E, hand textures/mirroring/drop, component setup, rendered Y sorting")
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


func _check_hands(player: Creature, panel: PanelContainer) -> bool:
	var inventory: Inventory = player.get_component(Inventory) as Inventory
	var hands: Node2D = player.get_node("Sprite2D/Hands") as Node2D
	var views: Dictionary = hands.get("_views")
	var body_sprite: Sprite2D = player.get_node("Sprite2D") as Sprite2D
	if not _require(is_zero_approx(body_sprite.position.y + body_sprite.texture.get_height() * body_sprite.scale.y * 0.5),
			"身体缩放后没有保持脚下接地点"):
		return false
	var rows: VBoxContainer = panel.get("_list") as VBoxContainer
	var slots: Array[Dictionary] = inventory.hand_slots()
	if not _require(views.size() == slots.size() and rows.get_child_count() == slots.size(), "双手视图数量不匹配"):
		return false
	for i in slots.size():
		var part: BodyPart = slots[i]["part"] as BodyPart
		var item: ItemDef = slots[i]["item"] as ItemDef
		var expected: Texture2D = item.icon if item != null else part.def.grasp_texture
		var sprite: Sprite2D = views[part] as Sprite2D
		var icon: TextureRect = rows.get_child(i).get_child(0) as TextureRect
		var label: Label = rows.get_child(i).get_child(1) as Label
		if not _require(expected != null and sprite.texture == expected and icon.texture == expected
				and sprite.flip_h == part.def.grasp_flip_h and icon.flip_h == part.def.grasp_flip_h
				and label.text.begins_with(part.def.grasp_label)
				and sprite.position == part.def.grasp_offset * player.def.texture.get_size(), "空手/持物图片、左右朝向或名称不同步"):
			return false
	var first: BodyPart = slots[0]["part"] as BodyPart
	var second: BodyPart = slots[1]["part"] as BodyPart
	return _require(first.def.grasp_offset.x < 0 and second.def.grasp_offset.x > 0
			and first.def.grasp_flip_h != second.def.grasp_flip_h, "左右手位置或镜像相同")


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
	# 空手预览，验证两个手掌确实显示在身体两侧。
	var inventory: Inventory = player.get_component(Inventory) as Inventory
	for i in inventory.hand_slots().size():
		inventory.take_from_hand(i)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var preview_dir: String = ProjectSettings.globalize_path("res://").path_join(".godot")
	get_viewport().get_texture().get_image().save_png(preview_dir.path_join("hands-tree-front.png"))
	player.position = tree.position + Vector2(0, -Grid.CELL_SIZE * 0.5)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(preview_dir.path_join("hands-tree-behind.png"))
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
		result += "%s|%s\n" % [item.definition.id, item.coord]
	return result.sha256_text()


func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error("world_object_smoke: " + message)
		get_tree().quit(1)
	return ok
