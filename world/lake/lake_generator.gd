class_name LakeGenerator
extends RefCounted

## 水体生成器 —— 按 `LakeDef`（**性质**）在**锚点旁边**造出水，形状由**世界种子**（**变化**）决定。
##
## 【本轮的落位规则（2026-09-20 用户拍板：贴着草原，但不要靠太近）】
##   每片水绑定一个 `Anchor`（世界格坐标上的一个圆：中心 + 半径）。水的圆心放在
##   `锚点半径 + def.anchor_gap + 水自身外伸` 的圆上 —— 于是
##   **"锚点边缘 ↔ 水边缘" 恒等于 `def.anchor_gap`**：既不会糊在一起，也不会远到走不到。
##
## 【为什么要改】旧版按 `ring_radius` 把水撒在"岛周边环"上，某片湖离最近的草原有 65~90 格。
##   而猪一次决策只走 1 格、"休息"占它六成时间 -> **走不完这段通勤**（实测不是饿死就是渴死）。
##
## 【降低耦合 · 三条】
##   1. 本文件**不认识**草原 / 猪 / 渲染层：它只收到一串 `Anchor`（圆心 + 半径）。
##      谁是锚点、为什么贴着它，由组装根（main）决定 —— 两个生成器彼此不必认识。
##   2. 产出的每片水是一个 `ShoreSampler`（见 `world/shore_sampler.gd`），
##      渲染层只认那个协议 -> **换生成器不用改渲染层**。
##   3. 没有 `static var last_field`（渲染层直接抓生成器的静态变量）——那就是硬绑。
##
## 【不硬编码】数量 / 间隙 / 尺寸 / 胖瘦 / 噪声 / 扫几个方位全部读 `def.*`。
##
## 【可复现】随机源只有传入的种子：每片水的方位 / 半径 / 胖瘦 / 朝向 / 三层噪声 seed
##   按固定顺序从同一个 `rng` 抽 -> 同种子 = 同一批水。
##
## 【只写 terrain】只改 `Cell.terrain`，不碰 `content` / `corpse`。

## 一片水的"锚点"：**别人已经占了的圆区**（世界格坐标）。
## 调用方用它告诉生成器"在这块圆区旁边放水，边缘至少隔 `anchor_gap`"。
## （本器不知道它是什么地貌 —— 草原 / 树林 / 岩场都行。）
class Anchor extends RefCounted:
	var center := Vector2.ZERO
	var radius := 0.0

	func _init(c: Vector2 = Vector2.ZERO, r: float = 0.0) -> void:
		center = c
		radius = r

## 一片水的采样器实现 —— 只负责"回答水在哪"，别的什么都不管。
class LakeSampler extends ShoreSampler:
	var cx := 0.0          # 湖心（格坐标）
	var cy := 0.0
	var rx := 1.0          # 长半轴（格）
	var ry := 1.0          # 短半轴（格）
	var ca := 1.0          # 朝向：cos / sin
	var sa := 0.0
	var amp := 0.0
	var w1 := 1.0          # 三层噪声权重（其和 ≤ 1，见 LakeDef.validate）
	var w2 := 0.0
	var w3 := 0.0
	var n1: FastNoiseLite = null
	var n2: FastNoiseLite = null
	var n3: FastNoiseLite = null
	var reach := 0.0       # 含噪声的最大外伸半径（格）—— 避让与"是否出图"都靠它

	func e(wx: float, wy: float) -> float:
		var dx := wx - cx
		var dy := wy - cy
		var ex := dx * ca + dy * sa
		var ey := -dx * sa + dy * ca
		var base := sqrt((ex / rx) * (ex / rx) + (ey / ry) * (ey / ry))
		var wob := n1.get_noise_2d(wx, wy) * w1 \
			+ n2.get_noise_2d(wx, wy) * w2 \
			+ n3.get_noise_2d(wx, wy) * w3
		return base - 1.0 - wob * amp

	func bounds() -> Rect2:
		var r := reach + 1.0
		return Rect2(Vector2(cx - r, cy - r), Vector2(r * 2.0, r * 2.0))

## 按锚点生成水体。返回
## {water, count, samplers, centers, reaches, anchor_index, ate_grass, missed}。
## `anchors`：锚点列表（本器不认识它们是什么，只知道"贴着它放"）。
static func generate(grid: Grid, seed_value: int, def: LakeDef, anchors: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var gw := float(grid.width)
	var gh := float(grid.height)
	var half := float(mini(grid.width, grid.height)) * 0.5

	# 锚点（传进来的东西不对就在这里炸，而不是悄悄放行）
	var anchor_list: Array[Anchor] = []
	for a in anchors:
		anchor_list.append(a as Anchor)

	var lakes: Array[LakeSampler] = []
	var owner: Array[int] = []      # 每片水贴的是第几个锚点（供组装根用）
	var missed := 0                 # 有锚点却没放成水 -> 那片草原旁边就没水（必须报出来）
	if anchor_list.is_empty():
		push_warning("[湖泊生成] 没有锚点 —— 锚点式落位下不会产出任何水（是不是忘了传 anchors？）")
	for ai in anchor_list.size():
		var a: Anchor = anchor_list[ai]
		var per := maxi(rng.randi_range(def.per_anchor_min, def.per_anchor_max), 1)
		for _j in per:
			var sam := _place_around(def, rng, a, anchor_list, lakes, half, gw, gh)
			if sam == null:
				missed += 1
			else:
				lakes.append(sam)
				owner.append(ai)

	# —— 写地形：把每片水盖住的格标成 WATER ——
	var water := 0
	var ate_grass := 0
	for y in grid.height:
		for x in grid.width:
			var cell := grid.get_cell(Vector2(x, y))
			if cell == null:
				continue
			var fx := float(x) + 0.5
			var fy := float(y) + 0.5
			var wet := false
			for s: LakeSampler in lakes:
				var dx := fx - s.cx
				var dy := fy - s.cy
				if dx * dx + dy * dy > s.reach * s.reach:
					continue                 # 便宜剪枝：连最大外伸都够不着，省 3 次噪声
				if s.e(fx, fy) <= 0.0:
					wet = true
					break
			if not wet:
				continue
			if cell.terrain == Terrain.GRASS or cell.terrain == Terrain.TALL_GRASS:
				# 不该发生：clearance 就是为它准备的。真发生说明参数被调坏了 -> 报出来（不静默啃掉草原）
				ate_grass += 1
				continue
			cell.terrain = Terrain.WATER
			water += 1

	# —— 自检 ——
	var centers: Array[Vector2i] = []
	var reaches: Array[float] = []
	var off_map := 0
	for s: LakeSampler in lakes:
		centers.append(Vector2i(round(s.cx), round(s.cy)))
		reaches.append(s.reach)
		var d_edge := minf(minf(s.cx, s.cy), minf(gw - s.cx, gh - s.cy))
		if s.reach > d_edge + 0.001:
			off_map += 1

	print("[湖泊生成] 种子=%d 定义=%s 锚点=%d 片数=%d 水域=%d 格 边缘间隙=%.1f 误吃草原=%d 出图=%d" % [
		seed_value, def.display_name, anchor_list.size(), lakes.size(), water, def.anchor_gap, ate_grass, off_map])
	for i in lakes.size():
		var s: LakeSampler = lakes[i]
		print("  %s#%d 贴锚点#%d 心=(%.1f,%.1f) 长=%.1f 短=%.1f 外伸=%.1f" % [
			def.display_name, i + 1, owner[i] + 1, s.cx, s.cy, s.rx, s.ry, s.reach])
	if ate_grass > 0:
		push_warning("[湖泊生成] 有 %d 格草原被水盖住 —— 避让参数（clearance/anchor_gap）需要调" % ate_grass)
	if off_map > 0:
		push_error("[湖泊生成] 有 %d 片水伸出图外 —— 几何检查失效，请检查 noise_amp 与权重和" % off_map)
	if missed > 0:
		push_warning("[湖泊生成] 有 %d 片水没放成（锚点周围找不到合法位置）—— 那片草原旁边会没有水" % missed)

	var samplers: Array[ShoreSampler] = []
	for s: LakeSampler in lakes:
		samplers.append(s)

	return {
		"water": water,
		"count": lakes.size(),
		"samplers": samplers,     # 交给表现层（它只认 ShoreSampler 这个协议）
		"centers": centers,
		"reaches": reaches,
		"anchor_index": owner,    # 第 i 片水贴的是第几个锚点（供组装根排布其它东西）
		"ate_grass": ate_grass,
		"missed": missed,
	}

## 在锚点周围放**一片**水，成功返回采样器、失败返回 null。
## 扫法是**系统性**的（绕锚点均分 placement_sweep 个方位逐个试），所以只要存在合法方位就一定找得到。
static func _place_around(def: LakeDef, rng: RandomNumberGenerator, anchor: Anchor,
		anchors: Array[Anchor], lakes: Array[LakeSampler],
		half: float, gw: float, gh: float) -> LakeSampler:
	var slack := 1.0 + def.noise_amp
	# 尺寸先抽；抽到的太大就重抽（最多 4 次），仍放不下就认输（missed）。
	for _size_try in 4:
		var rmaj := half * rng.randf_range(def.radius_frac_min, def.radius_frac_max)
		if rmaj < def.min_radius:
			continue
		var rmin := maxf(rmaj * rng.randf_range(def.ratio_min, 1.0), def.min_radius)
		var reach := maxf(rmaj, rmin) * slack
		# 圆心距：让"锚点外伸 -> 水外伸"这段正好等于 anchor_gap（边缘到边缘）
		var dist := anchor.radius + def.anchor_gap + reach
		var base := rng.randf_range(0.0, TAU)        # 起始方位随种子 -> 每次贴的方向不同
		var steps := maxi(def.placement_sweep, 8)
		for t in steps:
			var ang := base + TAU * float(t) / float(steps)
			var lx := anchor.center.x + dist * cos(ang)
			var ly := anchor.center.y + dist * sin(ang)
			# ① 整片必须在图内（含噪声外伸）
			var d_edge := minf(minf(lx, ly), minf(gw - lx, gh - ly))
			if d_edge < reach + def.edge_margin:
				continue
			var pos := Vector2(lx, ly)
			# ② 不能压到任何锚点（含自己贴的那片草原）—— 否则就不是"贴着"而是"吃掉"了
			var clash := false
			for other: Anchor in anchors:
				if pos.distance_to(other.center) < reach + other.radius + def.clearance:
					clash = true
					break
			if clash:
				continue
			# ③ 不能和已经放下的水重叠
			for s: LakeSampler in lakes:
				if pos.distance_to(Vector2(s.cx, s.cy)) < reach + s.reach + def.clearance:
					clash = true
					break
			if clash:
				continue
			# —— 成形 ——
			var sam := LakeSampler.new()
			sam.cx = lx
			sam.cy = ly
			sam.rx = rmaj
			sam.ry = rmin
			var oa := rng.randf_range(0.0, TAU)      # 椭圆自身朝向（与落位方位独立）
			sam.ca = cos(oa)
			sam.sa = sin(oa)
			sam.amp = def.noise_amp
			sam.w1 = def.noise_weight_1
			sam.w2 = def.noise_weight_2
			sam.w3 = def.noise_weight_3
			# 三层噪声的 seed 各抽一次 —— 若共用种子，每片水的噪声图案会**互相同构**（只是平移了）
			sam.n1 = _mk_noise(rng.randi(), def.noise_freq_1)
			sam.n2 = _mk_noise(rng.randi(), def.noise_freq_2)
			sam.n3 = _mk_noise(rng.randi(), def.noise_freq_3)
			sam.reach = reach
			return sam
	return null

static func _mk_noise(s: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	return n
