class_name LakeDef
extends Resource

## 一种「水体」的静态定义（**性质 = 数据**）。加一种水体 = 配一份 .tres，逻辑一行不改。
##
## 【分工：性质 vs 变化】
##   - **本资源**说的是"它是什么"：一片湖 / 一口池塘 / 一片沼泽 —— 每片草原配几片、
##     贴得多近、尺寸量级、轮廓的噪声构成、岸线怎么画。这些是**刻意选定**的，不随种子漂。
##   - **世界种子**说的是"这一局它长什么样"：每片落在锚点周围哪个方位、多大、
##     多扁、朝哪、轮廓的每一个凹凸。这些**每次都不同**。
##   ⇒ 想做"小池塘"：复制本文件、把 radius_frac / anchor_gap 改小即可，一行代码都不用动。
##
## 【2026-09-20 用户拍板：水贴着草原放，但**留出间隙**】
##   旧版把水撒在"岛周边环"上（`ring_radius`），结果某片湖离最近的草原有 65~90 格 ——
##   猪一次决策只走 1 格、而休息占它六成时间，**走不完这段通勤**（实测：不是饿死就是渴死）。
##   现在改为**锚点式**：每片水绑定一个锚点（草原），圆心距 = 锚点外伸 + `anchor_gap` + 水外伸
##   ⇒ "草原边缘 ↔ 水边缘"**恒等于 `anchor_gap`**，既不贴脸也不远得走不到。
##
## 【仿 GrassDef / LifeDef】只放数值 + 外观 + 一个 validate()；推进逻辑在 LakeGenerator。
##   DefValidator 启动期按目录扫描（`res://world/lake`），配错了当场报错。

@export var display_name: String = "湖"

# ---------------- 数量 ----------------
## **每个锚点（草原）旁边放几片**（种子在区间内抽）。默认 1 = 一片草原配一片水。
@export var per_anchor_min: int = 1
@export var per_anchor_max: int = 1

# ---------------- 落位（贴着锚点，但留间隙）----------------
@export var anchor_gap: float = 10.0       # 锚点边缘 ↔ 水边缘 的间隙（格）—— "不要靠太近"
## 绕锚点扫多少个候选方位。扫描是**系统性**的（不是随机重试），所以只要存在合法方位就一定能找到；
## 越大越不容易漏掉"窄窗口"（锚点离地图边近时合法方位会变窄）。
@export var placement_sweep: int = 48
@export var edge_margin: float = 1.0       # 整片水离地图边界至少留几格（含噪声外伸）
@export var clearance: float = 3.0         # 两片水之间 / 与其它锚点之间至少隔几格（防贴脸）
@export var min_radius: float = 4.0        # 长半轴小于此值的候选直接丢弃（不要碎水坑）

# ---------------- 尺寸：长半轴 = 半图 × 该比例（种子在区间内抽）----------------
@export var radius_frac_min: float = 0.115
@export var radius_frac_max: float = 0.155
@export var ratio_min: float = 0.62        # 短半轴 / 长半轴 的下限（=1 即正圆，越小越扁）

# ---------------- 形状：轮廓 = 归一化椭圆 + 三层噪声 ----------------
## 三层的分工（这就是"要不要规矩"的开关）：
##   1 低频 -> 整体拉长压扁；2 超低频 -> 整片走形（不再是椭圆的样子）；
##   3 中频 -> **海湾 / 半岛**（跟水体本身同尺度，所以能啃出真正的凹凸）。
## 只留前两层时轮廓是个"光滑的团"，看着仍然规矩；少了第三层就没有"不规矩"。
@export var noise_amp: float = 0.42        # 边界扰动幅度：最多把半径撑到 (1+amp) 倍
@export var noise_freq_1: float = 0.030
@export var noise_freq_2: float = 0.011
@export var noise_freq_3: float = 0.085
@export var noise_weight_1: float = 0.45
@export var noise_weight_2: float = 0.18
@export var noise_weight_3: float = 0.37

# ---------------- 岸线表现（交给 WaterLayer，本资源只管"是什么样"，不管怎么画）----------------
@export var edge_width_px: int = 1         # 岸线宽（像素，硬边）
@export var edge_color: Color = Color(1, 1, 1, 1)   # 岸线色；默认白 = 项目"纯黑白"里的"无色"

## 定义校验（空数组 = 通过）。与 GrassDef.validate() 同构，由 DefValidator 启动期扫描。
func validate() -> Array[String]:
	var errs: Array[String] = []
	if display_name.strip_edges().is_empty():
		errs.append("display_name 为空")
	if per_anchor_min < 1:
		errs.append("per_anchor_min 至少 1（当前 %d）" % per_anchor_min)
	if per_anchor_max < per_anchor_min:
		errs.append("per_anchor_max(%d) 不能小于 per_anchor_min(%d)" % [per_anchor_max, per_anchor_min])
	if anchor_gap < 0.0:
		errs.append("anchor_gap 不能为负（当前 %.1f）" % anchor_gap)
	if placement_sweep < 8:
		# 扫得太稀 -> 锚点贴近地图边时（合法方位窗口很窄）会找不到位置，那片草原就没水。
		errs.append("placement_sweep 至少 8（当前 %d）" % placement_sweep)
	if edge_margin < 0.0:
		errs.append("edge_margin 不能为负")
	if clearance < 0.0:
		errs.append("clearance 不能为负")
	if radius_frac_min <= 0.0 or radius_frac_min > 1.0:
		errs.append("radius_frac_min 需落在 (0, 1]（当前 %.3f）" % radius_frac_min)
	if radius_frac_max < radius_frac_min or radius_frac_max > 1.0:
		errs.append("radius_frac_max(%.3f) 需落在 [min, 1]" % radius_frac_max)
	if ratio_min <= 0.0 or ratio_min > 1.0:
		errs.append("ratio_min 需落在 (0, 1]（当前 %.2f）" % ratio_min)
	if min_radius <= 0.0:
		errs.append("min_radius 必须 > 0")
	if noise_amp < 0.0:
		errs.append("noise_amp 不能为负")
	if noise_freq_1 <= 0.0 or noise_freq_2 <= 0.0 or noise_freq_3 <= 0.0:
		errs.append("三层噪声频率都必须 > 0")
	var wsum := noise_weight_1 + noise_weight_2 + noise_weight_3
	if wsum <= 0.0:
		errs.append("三层噪声权重之和必须 > 0")
	elif wsum > 1.0 + 0.0001:
		# 这条不是洁癖：生成器用 rmaj×(1+noise_amp) 当作"含噪声的最大外伸半径"来保证
		# "整片留在图内"。权重和 > 1 时这个上界就不成立了 -> 水会被裁到图外。
		errs.append("三层噪声权重之和 = %.3f 不能 > 1（否则\"含噪声外伸半径\"的上界失效，水会出图）" % wsum)
	if edge_width_px < 1:
		errs.append("edge_width_px 至少 1")
	if edge_color.a <= 0.0:
		errs.append("edge_color 全透明 = 画了也看不见")
	return errs
