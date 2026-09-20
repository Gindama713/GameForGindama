extends Node

## 全局事件总线：系统 / UI 间解耦的信号中转。
## 连接不持引用，发射方 / 接收方释放后连接自动断（Godot 信号机制）。
## 点击猪 -> 发出 creature_clicked -> 检视面板接收，互不持有引用。

signal creature_clicked(creature: Node)
signal creature_spawned(creature: Node)   # main._spawn_pig() 生成成功即发（Minimap 重画）
signal creature_moved(creature: Node)     # Creature.move_to() 成功即发（Minimap 重画；将来脚印/噪音也听它）
signal creature_died(creature: Node)      # Creature.die()（Inspector 切尸体视图 / Minimap 重画）
signal creature_removed(creature: Node)   # DebugToolbar 清屏等"非死亡移除"（Inspector 关面板 / Minimap 重画）
signal terrain_changed()                  # 地形批量变化（如草原生成完）—— MapRenderer / Minimap 重画
signal shorelines_changed(samplers: Array, edge_width_px: int, edge_color: Color)
                                          # 岸线描述就绪 —— 生成器产数据(ShoreSampler)、WaterLayer 只负责画。
                                          # 走总线是为了让**两边互不认识**：换生成器不用改渲染层。

# —— 草场（GrassField）事件：带格坐标，供表现层局部重画 ——
signal grass_established(coord: Vector2i) # 扩散定殖出一格新草
signal grass_depleted(coord: Vector2i)    # 一格被啃到不可食（耐久 < edible_min）
signal grass_matured(coord: Vector2i)     # 一格再生到满耐久（成熟）
signal grass_changed(coord: Vector2i)     # 任意耐久变化（啃食/再生），MapRenderer / Minimap 重画该格

# —— 生命 / 家族 ——
signal birth_requested(mother: Node, father: Node)  # Reproduction 请求生育；Main 执行真造娃
signal creature_grew(creature: Node)                # 跨生命阶段（幼→成→老），供将来效果/日志
