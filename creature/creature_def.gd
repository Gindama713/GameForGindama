class_name CreatureDef
extends Resource

## 物种数据（全局共享的 Resource）。
## 加一只新动物 = 新建一份这个 + 一个场景，不改任何系统代码。
## 只放「数值 + 挂哪些组件」；具体逻辑都在组件脚本里。

@export var display_name: String = "生物"
@export var texture: Texture2D                       # 图标（可空 = 不渲染，纯逻辑生物）
@export var map_color: Color = Color(1, 1, 1, 1)     # 地图/小地图上的色块颜色（约定：黑=陆地，生物各配色）
@export var component_scripts: Array[Script] = []    # 声明式组合：这只生物挂哪些组件
@export var body_parts: Array[BodyPartDef] = []      # 部位清单（数据驱动；空 = 无身体系统）
@export var active_needs: Array[NeedDef] = []        # 激活的需求（数据驱动；空 = 无需求系统）
@export var personality: PersonalityDef              # 物种脾气分布（数据驱动；空 = 性格全取中性 0.5）
@export var move_interval: float = 1.0               # 大脑决策间隔基数（秒），物种级（占位值，待调）

## 定义校验（CDDA 四阶段加载里 check_all 的最小落地）。
## 返回问题清单；空数组 = 通过。
##
## 为什么必须有：这些错以前**全是静默的** ——
##   忘了配 is_vital 的物种天生不死；部位/需求 id 重复会悄悄顶掉前一个；
##   组件依赖缺失只 push_warning，然后运行期静默罢工（Brain 拿不到 GridMover 就什么都不干）。
## 数据错了必须在启动时就大声喊出来。
func validate() -> Array[String]:
	var errs: Array[String] = []

	if display_name.strip_edges().is_empty():
		errs.append("display_name 为空")

	_validate_parts(errs)
	_validate_needs(errs)
	_validate_components(errs)
	if move_interval <= 0.0:
		errs.append("move_interval 必须 > 0（当前 %.2f；否则大脑每帧都在决策）" % move_interval)

	return errs

func _validate_parts(errs: Array[String]) -> void:
	if body_parts.is_empty():
		return                      # 没有身体系统是合法配置（如纯逻辑生物）
	var seen := {}
	var vital_count := 0
	for i in body_parts.size():
		var p := body_parts[i]
		if p == null:
			errs.append("body_parts[%d] 是空引用" % i)
			continue
		if p.id.strip_edges().is_empty():
			errs.append("body_parts[%d] 缺 id" % i)
		elif seen.has(p.id):
			errs.append("部位 id 重复：%s" % p.id)
		else:
			seen[p.id] = true
		if p.max_hp <= 0.0:
			errs.append("部位 %s 的 max_hp 必须 > 0（当前 %.1f，会让血量比例算成 NaN）" % [p.id, p.max_hp])
		if p.is_vital:
			vital_count += 1
	# 注意：这里**不检查**「有没有 stance 肢体」—— 鱼/蛇本来就没有腿，
	# 无 stance 肢体是合法配置（can_locomote() 对这类物种直接放行）。
	if vital_count == 0:
		errs.append("没有任何 is_vital 部位 → 这个物种永远不会死")

func _validate_needs(errs: Array[String]) -> void:
	if active_needs.is_empty():
		return                      # 没有需求系统是合法配置（如鱼不需要口渴）
	var seen := {}
	for i in active_needs.size():
		var n := active_needs[i]
		if n == null:
			errs.append("active_needs[%d] 是空引用" % i)
			continue
		if n.id.strip_edges().is_empty():
			errs.append("active_needs[%d] 缺 id" % i)
		elif seen.has(n.id):
			errs.append("需求 id 重复：%s" % n.id)
		else:
			seen[n.id] = true
		if n.max_value <= 0.0:
			errs.append("需求 %s 的 max_value 必须 > 0（当前 %.1f，会让比例算成 NaN）" % [n.id, n.max_value])
		if n.drain_rate < 0.0:
			errs.append("需求 %s 的 drain_rate 不能为负（当前 %.1f）" % [n.id, n.drain_rate])

func _validate_components(errs: Array[String]) -> void:
	# 第一遍：先收齐所有组件路径。
	# 必须分两遍 —— 否则「依赖方写在被依赖方前面」会误报（顺序不该成为约束）。
	var paths := {}
	for i in component_scripts.size():
		var s := component_scripts[i]
		if s == null:
			errs.append("component_scripts[%d] 是空引用" % i)
			continue
		if s.resource_path.is_empty():
			errs.append("component_scripts[%d] 没有资源路径（要拖 .gd 脚本本体，不能是内联脚本）" % i)
			continue
		if paths.has(s.resource_path):
			errs.append("组件重复挂载：%s" % s.resource_path.get_file())
			continue
		paths[s.resource_path] = true

	# 第二遍：校验依赖（requires() 声明的是硬依赖，缺了就是配置错误）
	for s in component_scripts:
		if s == null or s.resource_path.is_empty():
			continue
		var probe: Variant = s.new()
		if probe == null:
			errs.append("组件 %s 实例化失败（脚本可能有语法错误）" % s.resource_path.get_file())
			continue
		if not (probe is CreatureComponent):
			errs.append("组件 %s 不是 CreatureComponent" % s.resource_path.get_file())
			continue
		var comp := probe as CreatureComponent
		for dep in comp.requires():
			if dep == null or dep.resource_path.is_empty():
				errs.append("组件 %s 的 requires() 里有无效项" % s.resource_path.get_file())
			elif not paths.has(dep.resource_path):
				errs.append("组件 %s 依赖 %s，但本物种没挂它" % [s.resource_path.get_file(), dep.resource_path.get_file()])
