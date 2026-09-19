class_name GrasslandGenerator
extends RefCounted

## 草原生成器 —— 世界默认铺 `unknown`（黑·占位），**一块椭圆草原**（`grass`），
## 草原中心再套一小块高草（`tall_grass`）。两层边界都用噪声扰动成不规则形状。
##
## 【用户拍板 2026-09-19】
##   1. 世界不该"全是草"：草原只占世界**一小块**，其余是 `unknown`（先占位，将来再填海 / 森林）。
##   2. **草原不再钉死地图正中**：其中心落在「以地图正中为圆心、半径 RING_RADIUS(=50) 的圆周」上，
##      随机取一点（角度由种子派生）。→ 换种子 = 草原甩到圆周不同方位（方案 B：位置也随机）。
##   3. 草原的**大小 / 胖瘦 / 朝向**同样由种子派生的 RNG 抽签 → 每片形状都不一样。
##
## 【为什么不甩出图外】地图已扩到 130×130（中心到边 = 65）。草块放在离中心 50 的环上，
##   自身还要占一圈，故把长半轴上限按几何算死：`max_major = (半图 - 环半径) / 噪声余量`
##   = (65 - 50)/1.3 ≈ 11.5 格，于是 (环 50 + 草块 11.5×1.3) ≤ 65 —— **整片草原恒落在图内**。
##   代价：环半径越大，可用草块越小；50 这个环上的草块注定是个 ≤11.5 的小椭圆（尺寸在此上限内仍随机）。
##   ⚠ 相机不跟随（用户定），开局那一屏（地图正中 40×24）看不到草原，需平移相机去找。
##
## 【可复现】随机源 = 传入的世界种子（形状 RNG 与 FastNoiseLite 同源）
##   -> 同种子 = 同一张图（中心/形状/朝向/毛刺全一致）。
## 【只写 terrain】不碰 content / corpse —— 本器只改 Cell.terrain 这一个事实。
## 【回传】除统计外，返回 center(草心格坐标) / major(长半轴) / ring_angle，供 main 在"草周围"放猪。
##
## 判定（把格心绕草心转 -angle 进椭圆自身坐标系，再套归一化椭圆方程）：
##   外层（草原）：e_out = |(ex/major, ey/minor)|，e_out <= 1 + noise(x,y)*NOISE_AMP -> grass，否则 unknown
##   内层（高草）：e_in  = |(ex/tx,     ey/ty) |，e_in  <= 1 + noise(x+off,y+off)*NOISE_AMP -> tall_grass
##   内层采样点平移一个偏移 -> 内外边界去相关（否则高草会是草原的等比缩样，呆板）。

const RING_RADIUS := 50.0        # 草原中心离地图正中的距离（格）—— 圆周半径
const GRASS_MAJOR_FRAC_MIN := 0.55   # 长半轴下限 = 该环可用最大长半轴 × 0.55
const GRASS_MAJOR_FRAC_MAX := 1.00   # 长半轴上限 = 可用最大（再大会甩出图，故封顶）
const GRASS_RATIO_MIN := 0.50    # 短/长 比下限（越小越扁）
const GRASS_RATIO_MAX := 1.00    # =1 即正圆
const TALL_INNER_RATIO := 0.45   # 高草半轴 = 草原半轴 × 0.45（跟随外层同一朝向）
const NOISE_AMP := 0.30          # 边界扰动幅度（相对归一化半径 1.0）：最多撑到 1.3 倍
const NOISE_FREQ := 0.125        # 噪声频率（每格）：≈每 8 格起伏一次
const INNER_OFFSET := Vector2(731.0, 577.0)   # 内层噪声采样偏移（去相关）
const NOISE_SLACK := 1.0 + NOISE_AMP   # 噪声最多把边界撑到 1.3 倍 → 预算要除它留余量

## 生成世界地貌并返回统计 + 草心信息（total / unknown / grass / tall_grass / center / major / ring_angle）。
static func generate(grid: Grid, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var mcx := float(grid.width) * 0.5      # 地图正中
	var mcy := float(grid.height) * 0.5
	var half_map := float(mini(grid.width, grid.height)) * 0.5   # 中心到边（=65 @130）

	# —— 草心：以地图正中为圆心、半径 RING_RADIUS 的圆周上随机取点 ——
	var ring_angle := rng.randf_range(0.0, TAU)
	var gcx := mcx + RING_RADIUS * cos(ring_angle)
	var gcy := mcy + RING_RADIUS * sin(ring_angle)

	# —— 大小 / 胖瘦 / 朝向：封顶在"整片仍在图内"的最大长半轴之内 ——
	var max_major := maxf((half_map - RING_RADIUS) / NOISE_SLACK, 2.0)
	var major := max_major * rng.randf_range(GRASS_MAJOR_FRAC_MIN, GRASS_MAJOR_FRAC_MAX)
	var ratio := rng.randf_range(GRASS_RATIO_MIN, GRASS_RATIO_MAX)
	var minor := maxf(major * ratio, 1.0)
	major = maxf(major, 1.0)
	var angle := rng.randf_range(0.0, TAU)     # 椭圆自身朝向（与草心方位独立）

	var ca := cos(angle)
	var sa := sin(angle)
	var tx := maxf(major * TALL_INNER_RATIO, 1.0)
	var ty := maxf(minor * TALL_INNER_RATIO, 1.0)

	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = NOISE_FREQ

	var grass := 0
	var tall := 0
	for y in grid.height:
		for x in grid.width:
			var cell := grid.get_cell(Vector2(x, y))
			if cell == null:
				continue
			var fx := float(x)
			var fy := float(y)
			# 把格心绕草心旋转 -angle，进椭圆自身坐标系（轴对齐后再比归一化半径）
			var dx := fx - gcx
			var dy := fy - gcy
			var ex :=  dx * ca + dy * sa
			var ey := -dx * sa + dy * ca
			var e_out := sqrt(pow(ex / major, 2) + pow(ey / minor, 2))
			if e_out > 1.0 + noise.get_noise_2d(fx, fy) * NOISE_AMP:
				cell.terrain = Terrain.UNKNOWN      # 草原之外 = 未知黑（占位）
				continue
			var e_in := sqrt(pow(ex / tx, 2) + pow(ey / ty, 2))
			var n_inner := noise.get_noise_2d(fx + INNER_OFFSET.x, fy + INNER_OFFSET.y)
			if e_in <= 1.0 + n_inner * NOISE_AMP:
				cell.terrain = Terrain.TALL_GRASS
				tall += 1
			else:
				cell.terrain = Terrain.GRASS
				grass += 1

	# —— 自检：草心 + 形状 + 是否整片落在图内（含噪声撑到 1.3 倍）——
	var on_map := (RING_RADIUS + major * NOISE_SLACK <= half_map + 0.001)
	print("[草原生成] 种子=%d 环角=%.0f° 草心=(%.0f,%.0f) 长=%.1f 短=%.1f 形向=%.0f° 落在130图内=%s" % [
		seed_value, ring_angle * rad_to_deg(1.0), gcx, gcy, major, minor,
		angle * rad_to_deg(1.0), "是" if on_map else "否(出图!)"])

	var total := grid.width * grid.height
	return {
		"total": total,
		"unknown": total - grass - tall,
		"grass": grass,
		"tall_grass": tall,
		"center": Vector2i(round(gcx), round(gcy)),   # 草心格坐标，供 main 在草周围放猪
		"major": major,                                # 长半轴（环带内径参考）
		"ring_angle": ring_angle,
	}
