extends Node
## 原型合成音效，无外部音频素材。
var tones: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var _last_hit := 0

func _ready() -> void:
	for cue in ["weapon_fire", "hit", "dash", "bell", "cover_break", "empty", "enemy_windup", "reward"]:
		tones[cue] = _tone(cue)
	for index in range(10):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -13.0
		add_child(voice)
		voices.append(voice)
	GameEvents.sfx_requested.connect(func(cue, _position): play(cue))
	GameEvents.player_dashed.connect(func(_direction): play("dash"))
	GameEvents.reward_chosen.connect(func(_id, _kind): play("reward"))
	GameEvents.attack_landed.connect(func(_id, _source, _target, _amount, _crit, _group):
		if Time.get_ticks_msec() - _last_hit > 45:
			_last_hit = Time.get_ticks_msec()
			play("hit"))

func play(cue: String) -> void:
	if GameFlow.self_test_mode or not tones.has(cue):
		return
	for voice in voices:
		if not voice.playing:
			voice.stream = tones[cue]
			voice.play()
			return

func _tone(cue: String) -> AudioStreamWAV:
	var length := 0.10
	var frequency := 580.0
	if cue == "bell":
		length = 1.0
		frequency = 880.0
	elif cue == "reward":
		length = 0.35
		frequency = 660.0
	elif cue == "dash":
		length = 0.17
		frequency = 210.0
	elif cue == "hit" or cue == "cover_break":
		frequency = 140.0
	elif cue == "empty":
		frequency = 90.0
	var rate := 22050
	var samples := int(rate * length)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	for index in range(samples):
		var t := float(index) / rate
		var phase := TAU * frequency * t
		var envelope := minf(1.0, t / 0.008) * pow(1.0 - t / length, 2.0)
		var wave := sin(phase + (t * 300.0 if cue == "weapon_fire" else 0.0))
		if cue == "bell":
			wave = sin(phase) * 0.65 + sin(phase * 1.5) * 0.2 + sin(phase * 2.07) * 0.15
		var sample := int(wave * envelope * 15000)
		bytes.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream

