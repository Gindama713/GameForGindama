extends ColorRect

## 睡眠视野过渡的「变暗」部分（2026-09-22）。
##
## ══════════════════════════════════════════════════════════════════
## 它是一个**哑消费者** —— 这是本功能最重要的架构决定
## ══════════════════════════════════════════════════════════════════
##   本文件**不认识 `Sleep` 组件、不认识 `SleepDirector`、也不认识时间倍率**。
##   它只认识一个 `float`：`EventBus.sleep_view_changed(t)`，0 = 清醒视野，1 = 完全入睡。
##
##   为什么这样拆：视野过渡有**两个消费者**（本节点负责"变暗"、`CameraRig` 负责"推近"），
##   将来还可能有音频 / 手柄震动。如果每个消费者都自己去问 `Sleep` 的状态、
##   自己算过渡曲线，那"什么时候算睡着"这件事就有 N 份实现 —— 改一处必漏其余。
##   ⇒ **生产者只有一个**（`SleepDirector` 持有进度并广播），消费者只管"拿到 t 怎么画"。
##     这与 `ui/` 只读逻辑的纪律（§6.5）一致：本文件连"读"都不需要，只是听。
##
## ══════════════════════════════════════════════════════════════════
## 位置：UI CanvasLayer 里排在 `NightOverlay` **之后**（见 `main.tscn`）
## ══════════════════════════════════════════════════════════════════
##   沿用现有约定（`NightOverlay` 是"盖住生物、不压暗其它 UI"的第一个子节点）：
##   本节点盖在夜色之上，但**在 HUD / 面板之下** ——
##   睡眠期间玩家还要看 HUD 上的状态（"熟睡 时间 ×30"），那是唯一的确认来源。

## 锚点/尺寸在代码里设，不写进 `.tscn` —— 与 `night_overlay.gd` 同一套路。
## ⚠ `set_anchors_preset(PRESET_FULL_RECT)` 会**保留控件的原始尺寸**，
##   所以必须显式写 anchors 与 offsets，控件才真正铺满整屏（本项目实测踩过）。
func _ready() -> void:
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不吃鼠标，不挡点击
	color = Color(1, 1, 1, 1)                    # 颜色由 shader 全权决定（见下）
	EventBus.sleep_view_changed.connect(_on_view_changed)
	_apply(0.0)                                  # 确定初值，别依赖"生产者一定会先发一次"

func _on_view_changed(t: float) -> void:
	_apply(t)

## 把进度喂给 shader。
##
## ⚠ **只在真的变了才写**：`set_shader_parameter` 会触发材质更新。
##   虽然 `SleepDirector` 本身也只在变化时广播，这里再挡一层 ——
##   将来若有人改了广播策略（比如每帧无条件发），这里不会跟着每帧刷材质。
func _apply(t: float) -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return                                   # 没挂材质 = 什么都不画（静默降级，不崩）
	# ⚠ 取到的可能是 `null`（shader 参数还没被显式写过时）—— 必须判类型，
	#   直接丢给 `is_equal_approx()` 会报 "Cannot convert argument 2 from Nil to float"（实测踩过）。
	var prev: Variant = mat.get_shader_parameter("t")
	if prev is float and is_equal_approx(t, prev):
		return
	mat.set_shader_parameter("t", clampf(t, 0.0, 1.0))
