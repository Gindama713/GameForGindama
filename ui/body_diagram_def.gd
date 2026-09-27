class_name BodyDiagramDef
extends Resource

## 全身照示意图的**版式数据**（2026-09-22 从 `ui/player_panel.gd` 抽出来）。
##
## ══════════════════════════════════════════════════════════════════
## 为什么要有这个资源类
## ══════════════════════════════════════════════════════════════════
##   在此之前，这些数据是 `player_panel.gd` 里的 5 块常量（约 90 行）：
##   `PART_LAYOUT` / `PART_TEXTURE` / `PART_FLIP` / `PORTRAIT_TEX` / `SILHOUETTE`。
##   三个后果：
##     ① **换一张立绘、加一个部位、加一个物种，都要改 UI 代码** —— 而它们全是**数据**；
##     ② UI 脚本里出现 **7 条 `res://` 硬编码路径**；
##     ③ "部位清单"在 `creature/player/data/part_*.tres` 里**已经有一份** ⇒ 同值复制。
##
##   ⇒ 数据进 `.tres`（§6.4 数据纪律），UI 只按 `id` 查表。
##     顺带修掉一个副作用：原先 `SILHOUETTE` 只能用 `var` 而不是 `const`，
##     因为 GDScript 的常量表达式求值器不接受 `PackedVector2Array([...])` 构造调用 ——
##     数据进 `.tres` 之后这个限制自然消失了。
##
## ⚠ **放 `ui/` 不放 `creature/`**：这是**表现**数据（§4 判定四问：表现 → `ui/`）。
##   而且 `creature/` 下的 `.tres` 约定**全部**是定义资源（都自带 `validate()`，
##   由 `DefValidator` 启动期扫描，扫到没有 `validate()` 的会**报错**）——
##   UI 版式不该混进那条契约里。
##
## ⚠ **为什么用 `Dictionary` 而不是 `Array[某个小 Resource]`**：
##   后者才是更"正统"的 Godot 做法（有类型），但 §6.4 明令**不许用内联子资源**，
##   于是每个部位都要单独一个 `.tres` —— 6 个部位 = 6 个文件 + 1 个容器文件，
##   为原本一块 90 行的常量付出 7 个文件的代价。**这里用字典是刻意的取舍**：
##   换来的是"加一个部位 = 在数据文件里加一行"，而调用方本来就按字符串 `id` 查表。

## 全身照（立绘）。
@export var portrait: Texture2D

## 部位 id → 在全身照里的**归一化**矩形（相对显示框，0..1）。
@export var part_layout: Dictionary = {}

## 部位 id → **特写**贴图。**未列出的部位不回退到全身照**（宁可显示"无特写"也不要误导）。
@export var part_texture: Dictionary = {}

## 部位 id → 是否水平翻转。空字典 = 都不翻。
@export var part_flip: Dictionary = {}

## 部位 id → **这个矩形是怎么来的**（实测依据）。
##
## 【为什么把注释变成字段】这些说明原本是 `player_panel.gd` 里挂在每个 `Rect2` 后面的行尾注释
##   （如「头 y0.041~0.305（实测 23..152，最宽 x206..304）」）。数据搬进 `.tres` 之后
##   **`.tres` 存不住注释**（引擎重写时会把 `;` 注释全部剥掉），于是那些实测值会永久丢失。
##   ⇒ 改成字段，让**依据跟着数据走**（§6.7：数值必须可溯源，不许出现"出处不明的数"）。
@export var part_note: Dictionary = {}

## **这份版式是怎么量出来的**（整块数据的溯源说明）。
##
## 同样是为了不让依据随注释一起消失。改这些矩形之前**先读它** ——
## 它说明了素材本身的客观限制（比如"填充剪影、没有手指缝"），
## 不知道那一条就会以为"左右臂没分开"是实现偷懒。
@export var source_note: String = ""

## 人体**轮廓多边形**（归一化坐标）—— 画成半透明辅助线，用来一眼看出"检测框贴不贴合"。
## 空数组 = 不画轮廓。
@export var silhouette: PackedVector2Array = PackedVector2Array()

# ---------------- 查询（UI 只走这几个入口，不直接碰字典）----------------

## 这个部位在全身照里的归一化矩形。没有则返回空 Rect2。
func rect_of(part_id: String) -> Rect2:
	return part_layout.get(part_id, Rect2())

## 这个部位的特写贴图。没有则返回 null（**不回退到全身照**，见字段说明）。
func texture_of(part_id: String) -> Texture2D:
	return part_texture.get(part_id)

## 这个部位要不要水平翻转。
func flip_of(part_id: String) -> bool:
	return part_flip.get(part_id, false)

## 有哪些部位（顺序 = `part_layout` 的声明顺序，UI 的绘制顺序依赖它）。
func part_ids() -> Array:
	return part_layout.keys()
