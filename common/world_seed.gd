extends Node
## 世界种子 —— 单一事实来源（Autoload）。
## 此前 "20260918" 分散写死在 Main.WORLD_SEED 与 Creature._world_seed 两处（见 事实文档 §5.1b/§8）。
## 现统一到这一处：草原生成、草场扩散 RNG、生物个体 RNG 都从这里取值 → 换一處即全链可复现。
## 注：开局猪落点仍走全局 randi_range（[已知问题] 不可复现），本次不改（守最小改动）。

var value: int = 20260918
