extends Node
## 音效总线（Autoload: Sfx）：懒加载 + 播放器池 + 静音开关。
## 音效素材见 assets/audio/CREDITS.md（全部 CC0）。

const DIR := "res://assets/audio/"
const POOL_SIZE := 16
const SETTINGS_PATH := "user://settings.cfg"

const FILES := {
	"draw": "sfx_draw.wav",
	"play": "sfx_play.wav",
	"land": "sfx_land.ogg",
	"hover": "sfx_hover.ogg",
	"click": "sfx_click.wav",
	"error": "sfx_error.wav",
	"turn": "sfx_turn.wav",
	"swing": "sfx_swing.ogg",
	"impact_a": "sfx_impact_a.ogg",
	"impact_b": "sfx_impact_b.ogg",
	"impact_c": "sfx_impact_c.ogg",
	"hurt": "sfx_hurt.ogg",
	"death": "sfx_death.ogg",
	"spell": "sfx_spell.ogg",
	"spell_fire": "sfx_spell_fire.ogg",
	"heal": "sfx_heal.ogg",
	"freeze": "sfx_freeze.ogg",
	"shield": "sfx_shield.ogg",
	"armor": "sfx_armor.ogg",
}

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _muted := false
var _master_db := -2.0
var _last_played: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.volume_db = _master_db
		add_child(p)
		_players.append(p)


func _stream(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	if not FILES.has(key):
		return null
	var path: String = DIR + str(FILES[key])
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
	_cache[key] = stream
	return stream


func play(key: String, volume_db := 0.0, pitch := 1.0) -> void:
	if _muted or _players.is_empty():
		return
	var stream := _stream(key)
	if stream == null:
		return
	# 同一音效 30ms 内只响一次，避免多段伤害叠成噪音
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(key, -9999)) < 30:
		return
	_last_played[key] = now
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = _master_db + volume_db
	p.pitch_scale = pitch
	p.play()


# ------------------------------------------------------------------ 语义化接口
func ui_click() -> void:
	play("click", -8.0, randf_range(0.97, 1.04))


func ui_hover() -> void:
	play("hover", -18.0, randf_range(1.0, 1.08))


func card_draw() -> void:
	play("draw", -6.0, randf_range(0.96, 1.05))


func card_play() -> void:
	play("play", -4.0, randf_range(0.97, 1.04))


func card_land() -> void:
	play("land", -6.0, randf_range(0.92, 1.02))


func swing() -> void:
	play("swing", -6.0, randf_range(0.92, 1.06))


func impact(strength := 1.0) -> void:
	var key: String = ["impact_a", "impact_b", "impact_c"][randi() % 3]
	play(key, -3.0 + clampf(strength, 0.0, 1.0) * 1.0, randf_range(0.9, 1.08))


func hurt() -> void:
	play("hurt", -9.0, randf_range(0.88, 1.02))


func death() -> void:
	play("death", -5.0, randf_range(0.9, 1.04))


func spell(fire := false) -> void:
	play("spell_fire" if fire else "spell", -6.0, randf_range(0.96, 1.05))


func heal() -> void:
	play("heal", -8.0, randf_range(0.98, 1.06))


func freeze() -> void:
	play("freeze", -7.0, randf_range(0.95, 1.05))


func shield() -> void:
	play("shield", -6.0, randf_range(0.96, 1.05))


func armor() -> void:
	play("armor", -7.0, randf_range(0.95, 1.05))


func turn() -> void:
	play("turn", -5.0, randf_range(0.98, 1.03))


func error() -> void:
	play("error", -8.0)


# ------------------------------------------------------------------ 静音开关
func is_muted() -> bool:
	return _muted


func set_muted(value: bool) -> void:
	_muted = value
	if _muted:
		for p in _players:
			p.stop()
	_save_settings()


func toggle_mute() -> bool:
	set_muted(not _muted)
	return _muted


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_muted = bool(cfg.get_value("audio", "muted", false))
		_master_db = float(cfg.get_value("audio", "master_db", -2.0))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "muted", _muted)
	cfg.set_value("audio", "master_db", _master_db)
	cfg.save(SETTINGS_PATH)
