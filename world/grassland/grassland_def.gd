class_name GrasslandDef
extends Resource

## 一种「草原」的静态定义（**性质 = 数据**）。加/改一种草原 = 配一份 .tres，逻辑一行不改。
##
## 【分工：性质 vs 变化】与 `LakeDef` 同一套口径：
##   - **本资源**说的是"草原是什么"：一局放几片、落在多大的环上、允许长到多大、
##     轮廓的噪声构成。这些是**刻意选定**的，不随种子漂。
##   - **世界种子**说的是"这一局它长什么样"：每片落在扇区里的哪个方位角、多大、
##     多扁、朝哪个方向、轮廓的每一个凹凸。这些**每次都不同**。
##
## 【为什么数量也进数据】2026-09-20 用户拍板"一个世界不止一片草原"：数量与"彼此分散"
##   的规则是**世界布局**的一部分，属于"性质"，所以放在这里而不是散在 .gd 的常量里。
##
## 【仿 GrassDef / LakeDef / LifeDef】只放数值 + 一个 `validate()`；推进逻辑在
##   `GrasslandGenerator`。DefValidator 启动期按目录扫描（`res://world/grassland`），
##   配错了当场报错（而不是运行期静默生成一半就没了）。
##
## ⚠ 命名别混：`world/grass/`（`GrassDef` / `GrassField`）管的是**地上活着的草量**
##   （耐久 / 再生 / 扩散 / 能啃几口）；本文件管的是**地貌**（哪一格是草原、哪一格是高草）。

@export var display_name: String = "草原"

# ---------------- 数量 ----------------
## 一局放几片（种子在区间内抽）。**彼此分散**由生成器按扇区均分保证，与数量无关。
@export var count_min: int = 2
@export var count_max: int = 3

# ---------------- 落位 ----------------
## 落在"以地图正中为圆心"的环上。默认抄世界统一的环半径（`world_layout.gd`）；
## **.tres 里不写这一项** = 跟随世界基准。
@export var ring_radius: float = WorldLayout.RING_RADIUS
@export var ring_jitter: float = 0.0            # 环半径再抖 ±这么多格 -> 不摆在一个正圆上
## 方位角抖动 = 扇区角 × 该比例。**必须 < 0.5**：
##   最小方位间隔 = 扇区角 ×(1 − 2×该值)，取 0.5 时相邻两片会贴在一起。
@export var angle_jitter_frac: float = 0.25
@export var edge_margin: float = 1.0            # 整片草原离地图边界至少留几格（含噪声外伸）

# ---------------- 尺寸 ----------------
## 长半轴 = 可用最大长半轴 × [major_frac_min, 1]。**可用上限由生成器按几何算死**
##   （环之外还剩多少 ÷ 噪声余量），保证"整片草原恒落在图内"。
##   所以这里的比例只决定"用多大"，不决定"会不会出图"。
@export var major_frac_min: float = 0.55
@export var ratio_min: float = 0.50             # 短半轴/长半轴 的下限（=1 即正圆，越小越扁）
@export var tall_inner_ratio: float = 0.45      # 高草半轴 = 草原半轴 × 该值（跟随外层同一朝向）

# ---------------- 形状：边界 = 归一化椭圆 + 噪声扰动 ----------------
@export var noise_amp: float = 0.30             # 扰动幅度：最多把半径撑到 (1+amp) 倍
@export var noise_freq: float = 0.125           # 噪声频率（每格）：≈每 8 格起伏一次

## 定义校验（空数组 = 通过）。与 GrassDef / LakeDef.validate() 同构，由 DefValidator 启动期扫描。
func validate() -> Array[String]:
	var errs: Array[String] = []
	if display_name.strip_edges().is_empty():
		errs.append("display_name 为空")
	if count_min < 1:
		errs.append("count_min 至少 1（当前 %d）" % count_min)
	if count_max < count_min:
		errs.append("count_max(%d) 不能小于 count_min(%d)" % [count_max, count_min])
	if ring_radius <= 0.0:
		errs.append("ring_radius 必须 > 0（否则草原全挤在正中）")
	if ring_jitter < 0.0:
		errs.append("ring_jitter 不能为负")
	if angle_jitter_frac < 0.0 or angle_jitter_frac >= 0.5:
		# 不是洁癖：≥0.5 时最小方位间隔归零，相邻两片草原会重叠成一片。
		errs.append("angle_jitter_frac 需落在 [0, 0.5)（当前 %.2f）" % angle_jitter_frac)
	if edge_margin < 0.0:
		errs.append("edge_margin 不能为负")
	if major_frac_min <= 0.0 or major_frac_min > 1.0:
		errs.append("major_frac_min 需落在 (0, 1]（当前 %.2f）" % major_frac_min)
	if ratio_min <= 0.0 or ratio_min > 1.0:
		errs.append("ratio_min 需落在 (0, 1]（当前 %.2f）" % ratio_min)
	if tall_inner_ratio <= 0.0 or tall_inner_ratio > 1.0:
		errs.append("tall_inner_ratio 需落在 (0, 1]（当前 %.2f）" % tall_inner_ratio)
	if noise_amp < 0.0:
		errs.append("noise_amp 不能为负")
	if noise_freq <= 0.0:
		errs.append("noise_freq 必须 > 0")
	return errs
