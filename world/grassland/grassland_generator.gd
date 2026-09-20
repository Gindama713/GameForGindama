class_name GrasslandGenerator
extends RefCounted

## 草原生成器 —— 世界默认铺 `unknown`（黑·占位），按 `GrasslandDef` 造出 **N 片草原**（`grass`），
## 每片中心再套一小块高草（`tall_grass`）。两层边界都用噪声扰动成不规则形状。
##
## 【2026-09-20 用户拍板：一个世界不止一片草原，而且不许挤在一块】
##   片数与"分散"的规则来自 `GrasslandDef`：把 360° **均分成 n 个扇区**，每片只在自己
##   那个扇区里抖一下（`angle_jitter_frac < 0.5`）-> 最小方位间隔 = 半个扇区，
##   于是"彼此分散"是**几何保证**，不是靠碰撞重试碰运气。
##
## 【不硬编码】数量 / 环半径 / 环抖动 / 角度抖动 / 尺寸比例 / 胖瘦 / 朝向 / 噪声参数
##   全部读 `def.*`；本文件只有**一条**几何约束写死：整片必须落在图内（`max_major` 由它反解）。
##
## 【可复现】随机源 = 传入的世界种子。同种子 = 同一批草原（中心/大小/朝向/毛刺全一致）。
##
## 【只写 terrain】不碰 content / corpse —— 本器只改 `Cell.terrain` 这一个事实。
##
## 【回传】`centers` / `reaches` / `majors` / `ring_angles` 四个**等长**数组，
##   供组装根（main）用来"在草原旁边放湖 / 放猪"。生成器**不认识**它们是谁 ——
##   这就是"降低耦合"的落点：它只产数据，接线在 main。
##
## 判定（把格心绕草心转 -rot 进椭圆自身坐标系，再套归一化椭圆方程）：
##   外层（草原）：e_out = |(ex/major, ey/minor)|，e_out <= 1 + noise(x,y)*amp
##   内层（高草）：e_in  = |(ex/tx,     ey/ty) |，e_in  <= 1 + noise(x+off,y+off)*amp

## 内层噪声采样偏移：内外边界**去相关**（否则高草会是草原的等比缩样，呆板）。
const INNER_OFFSET := Vector2(731.0, 577.0)

## 生成世界地貌并返回统计 + 每片草原的落位/外伸（total / unknown / grass / tall_grass /
## count / centers / reaches / majors / ring_angles）。
static func generate(grid: Grid, seed_value: int, def: GrasslandDef) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var mcx := float(grid.width) * 0.5      # 地图正中
	var mcy := float(grid.height) * 0.5
	var half_map := float(mini(grid.width, grid.height)) * 0.5   # 中心到边（=65 @130）

	# —— 数量 + 分散：360° 均分扇区，每片在自己的扇区里抖一下 ——
	var n := maxi(rng.randi_range(def.count_min, def.count_max), 1)
	var sector := TAU / float(n)
	var jf := clampf(def.angle_jitter_frac, 0.0, 0.49)
	var noise_slack := 1.0 + def.noise_amp
	# 可用最大长半轴：环（含抖动）之外还剩多少，再除以噪声余量 -> 整片恒落在图内。
	# 代价：环半径越大，可用草原越小（与湖泊同一套算法）。
	var max_major := maxf((half_map - def.ring_radius - def.ring_jitter - def.edge_margin) / noise_slack, 2.0)

	var gs: Array[Dictionary] = []
	for k in n:
		var ring_angle := sector * float(k) + rng.randf_range(-jf, jf) * sector
		var rad := maxf(def.ring_radius + rng.randf_range(-def.ring_jitter, def.ring_jitter), 0.0)
		var major := maxf(max_major * rng.randf_range(def.major_frac_min, 1.0), 1.0)
		var minor := maxf(major * rng.randf_range(def.ratio_min, 1.0), 1.0)
		var rot := rng.randf_range(0.0, TAU)     # 椭圆自身朝向（与所在扇区方位独立）
		gs.append({
			"cx": mcx + rad * cos(ring_angle),
			"cy": mcy + rad * sin(ring_angle),
			"major": major,
			"minor": minor,
			"ca": cos(rot),
			"sa": sin(rot),
			"ring_angle": ring_angle,
			"reach": maxf(major, minor) * noise_slack,   # 含噪声的最大外伸半径（格）
		})

	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = def.noise_freq

	var grass := 0
	var tall := 0
	for y in grid.height:
		for x in grid.width:
			var cell := grid.get_cell(Vector2(x, y))
			if cell == null:
				continue
			var fx := float(x)
			var fy := float(y)
			# 噪声只与"格"有关、与属于哪片草原无关 -> 每格只采样两次（省一半）
			var n_out := noise.get_noise_2d(fx, fy) * def.noise_amp
			var n_in := noise.get_noise_2d(fx + INNER_OFFSET.x, fy + INNER_OFFSET.y) * def.noise_amp

			var in_outer := false
			var in_inner := false
			for g: Dictionary in gs:
				var dx := fx - float(g["cx"])
				var dy := fy - float(g["cy"])
				var ca := float(g["ca"])
				var sa := float(g["sa"])
				# 把格心绕草心转 -rot，进椭圆自身坐标系（轴对齐后再比归一化半径）
				var ex := dx * ca + dy * sa
				var ey := -dx * sa + dy * ca
				var major := float(g["major"])
				var minor := float(g["minor"])
				if sqrt((ex / major) * (ex / major) + (ey / minor) * (ey / minor)) > 1.0 + n_out:
					continue                      # 不在这片的草原里 -> 试下一片
				in_outer = true
				var tx := maxf(major * def.tall_inner_ratio, 1.0)
				var ty := maxf(minor * def.tall_inner_ratio, 1.0)
				if sqrt((ex / tx) * (ex / tx) + (ey / ty) * (ey / ty)) <= 1.0 + n_in:
					in_inner = true
					break                         # 已是高草，无需再看别的片
			if in_inner:
				cell.terrain = Terrain.TALL_GRASS
				tall += 1
			elif in_outer:
				cell.terrain = Terrain.GRASS
				grass += 1
			else:
				cell.terrain = Terrain.UNKNOWN    # 草原之外 = 未知黑（占位）

	# —— 自检：每片是否整片落在图内（含噪声撑到 (1+amp) 倍）——
	var centers: Array[Vector2i] = []
	var reaches: Array[float] = []
	var majors: Array[float] = []
	var ring_angles: Array[float] = []
	var off_map := 0
	for g: Dictionary in gs:
		var cx := float(g["cx"])
		var cy := float(g["cy"])
		var reach := float(g["reach"])
		centers.append(Vector2i(round(cx), round(cy)))
		reaches.append(reach)
		majors.append(float(g["major"]))
		ring_angles.append(float(g["ring_angle"]))
		var d_edge := minf(minf(cx, cy), minf(float(grid.width) - cx, float(grid.height) - cy))
		if reach > d_edge + 0.001:
			off_map += 1

	print("[草原生成] 种子=%d 片数=%d 草原=%d 格 高草=%d 格 出图=%d" % [
		seed_value, gs.size(), grass, tall, off_map])
	for i in gs.size():
		var g: Dictionary = gs[i]
		print("  %s#%d 心=(%.0f,%.0f) 环角=%.0f° 长=%.1f 短=%.1f 外伸=%.1f" % [
			def.display_name, i + 1, float(g["cx"]), float(g["cy"]),
			float(g["ring_angle"]) * rad_to_deg(1.0), float(g["major"]), float(g["minor"]), float(g["reach"])])
	if off_map > 0:
		push_error("[草原生成] 有 %d 片草原伸出图外 —— 几何封顶失效，请检查 noise_amp 与 ring_radius" % off_map)

	var total := grid.width * grid.height
	return {
		"total": total,
		"unknown": total - grass - tall,
		"grass": grass,
		"tall_grass": tall,
		"count": gs.size(),
		"centers": centers,          # 每片草原的中心（格坐标）—— 供 main 在旁边放水/放猪
		"reaches": reaches,          # 每片草原含噪声的最大外伸半径 —— 供别人避让 / 定间隙
		"majors": majors,            # 每片草原的长半轴
		"ring_angles": ring_angles,  # 每片草原所在的方位角（调试/断言用）
	}
