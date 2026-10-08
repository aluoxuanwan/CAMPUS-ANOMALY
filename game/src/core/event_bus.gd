extends Node
## 事件总线：表现层与规则层之间的唯一接口。
##
## 设计依据见 docs/research/技术与动画方案.md 第 3 节。
## 规则层只发出事实事件，表现层只消费事件，双方不互相读取内部状态。
## 这样可以让暂停、慢动作与动画结束回调无法改变冷却与战斗结果。

# --- 战斗事实 ---

## 一次攻击真正命中目标。source_id 用于触发链去重与深度限制。
signal attack_landed(attack_id: int, attacker: Node, target: Node, damage: int, is_crit: bool, source_id: String)
## 目标受到伤害，已扣除护盾与减伤。
signal damage_applied(target: Node, amount: int, remaining_hp: int)
## 目标死亡。
signal entity_died(entity: Node, is_boss: bool)
## 攻击进入前摇、有效窗口、后摇。
signal attack_phase_changed(attacker: Node, attack_id: int, phase: int)
## 请求命中停顿。多个请求在短时间内会合并。
signal hitstop_requested(duration_ms: float)
## 请求震屏。
signal camera_shake_requested(strength: float)

# --- 玩家与局内状态 ---

signal player_damaged(amount: int, remaining_hp: int)
signal player_dashed(direction: Vector2)
signal player_weapon_swapped(weapon_id: String)
signal player_ability_used(ability_id: String, remaining_slots: int)
## 局内货币变化。
signal insight_changed(value: int)
## 一项奖励被选中。
signal reward_chosen(reward_id: String, kind: String)

# --- 房间与流程 ---

signal room_entered(room_index: int, template_id: String, kind: String)
signal room_cleared(room_index: int)
signal room_wave_spawned(room_index: int, wave: int, enemy_count: int)
## 铃声阶段切换。phase 为 GameConfig.BellPhase。
signal bell_phase_changed(phase: int, seconds_left: float)
signal bell_countdown(seconds_left: float)
signal run_started(seed_value: int)
signal run_failed(rooms_cleared: int, elapsed_seconds: float)
signal run_victory(rooms_cleared: int, elapsed_seconds: float)
signal run_reward_granted(club_points: int, total: int)

# --- 表现请求 ---

signal floating_text_requested(world_position: Vector2, text: String, color: Color)
signal sfx_requested(cue: String, world_position: Vector2)
signal screen_flash_requested(color: Color, duration: float)

# --- 自检 ---

## 自检过程中的结构化日志。
signal diagnostic(message: String)
## 自检结束。ok 为假时由 Diagnostics 以非零码退出。
signal self_test_finished(ok: bool, summary: Dictionary)
