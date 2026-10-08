class_name HitstopService
extends Node
## 命中停顿服务。使用引擎真实时间倒计时，与受影响的游戏时间分离。
##
## 依据 docs/research/技术与动画方案.md 第 4 节：
## 命中停顿可先试验 20 至 60 ms；每秒多次命中时应合并停顿请求，避免时间几乎停止。
## 本节点设置 PROCESS_MODE_ALWAYS，因此 time_scale 降低时仍按真实时间推进。

## 单次停顿上限，防止高密度命中把时间压到接近停止。
const MAX_TOTAL_MS := 140.0
## 两次停顿之间的最小间隔，用于合并请求。
const MERGE_INTERVAL_MS := GameConfig.HITSTOP_MIN_INTERVAL_MS
## 慢动作期间的引擎时间倍率。
const SLOW_SCALE := 0.05

var _remaining_ms: float = 0.0
var _last_trigger_ms: float = -10000.0
var _normal_scale: float = 1.0
## 用户设置中的停顿强度，0 表示关闭。
var scale_setting: float = 1.0

## 是否正在停顿。
var active: bool = false
## 累计触发次数，供自检输出。
var trigger_count: int = 0
## 因合并或上限被丢弃的请求次数。
var merged_count: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_normal_scale = Engine.time_scale
	GameEvents.hitstop_requested.connect(_on_hitstop_requested)

func _on_hitstop_requested(duration_ms: float) -> void:
	request(duration_ms)

## 请求一次命中停顿。duration_ms 为 0 或负值时忽略。
func request(duration_ms: float) -> void:
	if duration_ms <= 0.0:
		return
	var scaled := duration_ms * clampf(scale_setting, 0.0, 2.0)
	if scaled <= 0.0:
		return
	var now := _now_ms()
	# 停顿期间的新请求在间隔内合并，避免时间几乎停止。
	if active and now - _last_trigger_ms < MERGE_INTERVAL_MS:
		merged_count += 1
		return
	if active and _remaining_ms > MAX_TOTAL_MS:
		merged_count += 1
		return
	_remaining_ms = minf(MAX_TOTAL_MS, _remaining_ms + scaled)
	_last_trigger_ms = now
	trigger_count += 1
	if not active:
		active = true
		Engine.time_scale = SLOW_SCALE

func _process(delta: float) -> void:
	if not active:
		return
	# 本节点按真实时间运行，delta 不受 time_scale 影响。
	var elapsed_ms := delta * 1000.0 / maxf(0.001, Engine.time_scale)
	_remaining_ms -= elapsed_ms
	if _remaining_ms <= 0.0:
		_release()

func _release() -> void:
	_remaining_ms = 0.0
	active = false
	Engine.time_scale = _normal_scale

## 立即结束停顿。场景切换与暂停时调用，避免残留低时间倍率。
func force_release() -> void:
	if active:
		_release()

func _now_ms() -> float:
	return Time.get_ticks_msec() as float

func _exit_tree() -> void:
	force_release()
