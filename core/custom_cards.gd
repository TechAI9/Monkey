class_name CustomCards
extends RefCounted
## 自定义卡牌仓库：存于 user://custom_cards.json，启动时注册进 CardDB。
## 纯静态，无头测试可直接调用。

const PATH := "user://custom_cards.json"
const ART_DIR := "user://custom_art"
const VERSION := 1
const ID_PREFIX := "CUSTOM_"
const MAX_NAME_LEN := 12

static var _loaded := false
static var _defs: Array = []
static var _next_id := 1
## 无头测试时置 false，避免写入用户存档。
static var write_enabled := true


# ------------------------------------------------------------------ 词表
## 触发时机：值的第一个元素是 JSON 里的 trigger，第二个是界面文案。
const TRIGGERS := [
	["battlecry", "战吼"],
	["deathrattle", "亡语"],
	["spell", "法术效果"],
	["end_of_turn", "回合结束时"],
	["on_summon", "召唤时"],
	["on_self_damaged", "自身受伤时"],
]

## 目标范围（整张卡共用，对应 GameState.get_target_spec）。
const TARGET_MODES := [
	["", "不需要选择目标"],
	["any", "任意角色"],
	["any_minion", "任意随从"],
	["enemy_minion", "敌方随从"],
	["enemy_character", "敌方角色"],
	["friendly_minion", "友方随从"],
	["friendly_other_minion", "其他友方随从"],
]

## 动作级作用对象（对应 GameState._select）。
const TARGETS := [
	["chosen", "选择的目标"],
	["enemy_hero", "敌方英雄"],
	["owner_hero", "我方英雄"],
	["self", "自身"],
	["enemy_characters", "敌方英雄与随从"],
	["enemy_minions", "所有敌方随从"],
	["friendly_minions", "所有友方随从"],
	["all_minions", "所有随从"],
	["all_other_minions", "其他随从"],
	["random_enemy_character", "随机敌方角色"],
]

## 伤害池（对应 _select 的批量选择器）。
const POOLS := [
	["enemy_characters", "敌方英雄与随从"],
	["enemy_minions", "所有敌方随从"],
	["all_minions", "所有随从"],
	["all_characters", "所有角色"],
	["friendly_minions", "所有友方随从"],
]

## 动作目录：每个动作声明自己的参数字段，界面据此生成控件。
const ACTIONS := [
	{"id": "damage", "name": "造成伤害", "fields": ["amount", "to"], "text": "对%s造成%d点伤害"},
	{"id": "heal", "name": "恢复生命", "fields": ["amount", "to"], "text": "为%s恢复%d点生命"},
	{"id": "buff", "name": "获得属性", "fields": ["atk", "hp", "to"], "text": "%s获得+%d/+%d"},
	{"id": "draw", "name": "抽牌", "fields": ["count", "who"], "text": "%s抽%d张牌"},
	{"id": "armor", "name": "获得护甲", "fields": ["amount", "who"], "text": "%s获得%d点护甲"},
	{"id": "summon", "name": "召唤随从", "fields": ["token", "count"], "text": "召唤%d个%s"},
	{"id": "destroy", "name": "消灭随从", "fields": ["to"], "text": "消灭%s"},
	{"id": "freeze", "name": "冻结", "fields": ["to"], "text": "冻结%s"},
	{"id": "damage_all", "name": "群体伤害", "fields": ["amount", "pool"], "text": "对%s造成%d点伤害"},
	{"id": "random_damage", "name": "随机伤害", "fields": ["amount", "count", "pool"],
		"text": "随机对%s造成%d点伤害，共%d次"},
	{"id": "give_keyword", "name": "获得关键字", "fields": ["keyword", "to"], "text": "%s获得%s"},
	{"id": "set_attack", "name": "设定攻击力", "fields": ["amount", "to"], "text": "将%s的攻击力变为%d"},
	{"id": "set_health", "name": "设定生命值", "fields": ["amount", "to"], "text": "将%s的生命值变为%d"},
	{"id": "gain_mana", "name": "获得法力水晶", "fields": ["amount"], "text": "本回合获得%d个法力水晶"},
]

const KEYWORDS := [
	["TAUNT", "嘲讽"],
	["CHARGE", "冲锋"],
	["DIVINE_SHIELD", "圣盾"],
	["WINDFURY", "风怒"],
	["LIFESTEAL", "吸血"],
	["FREEZE_ON_DAMAGE", "冰冻"],
	["CANNOT_ATTACK", "无法攻击"],
]


# ------------------------------------------------------------------ load / save
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	CardDB.ensure_loaded()
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for d in parsed.get("cards", []):
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var def := _normalize(d)
		if def.is_empty():
			continue
		_defs.append(def)
		_next_id = maxi(_next_id, _numeric_suffix(def["id"]) + 1)
	CardDB.register_cards(_defs)


static func _numeric_suffix(id: String) -> int:
	var idx := id.rfind("_")
	if idx < 0:
		return 0
	return int(id.substr(idx + 1))


static func _normalize(d: Dictionary) -> Dictionary:
	var cid := str(d.get("id", ""))
	if cid == "":
		cid = "%s%d" % [ID_PREFIX, _next_id]
	var out := d.duplicate(true)
	out["id"] = cid
	out["set"] = "CUSTOM"
	return out


static func save_all() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("CustomCards: 无法写入 %s" % PATH)
		return
	f.store_string(JSON.stringify({"version": VERSION, "cards": _defs}, "\t"))
	f.close()
	CardDB.register_cards(_defs)


# ------------------------------------------------------------------ query
static func all_defs() -> Array:
	ensure_loaded()
	return _defs.duplicate()


static func def_of(card_id: String) -> Dictionary:
	ensure_loaded()
	for d in _defs:
		if d["id"] == card_id:
			return d
	return {}


static func count() -> int:
	ensure_loaded()
	return _defs.size()


static func new_card_id() -> String:
	ensure_loaded()
	return "%s%d" % [ID_PREFIX, _next_id]


# ------------------------------------------------------------------ mutate
## 保存一张卡（新增或覆盖），返回落库后的定义。
static func upsert(def: Dictionary) -> Dictionary:
	ensure_loaded()
	var stored := _normalize(def)
	if def.get("id", "") == "":
		stored["id"] = "%s%d" % [ID_PREFIX, _next_id]
		_next_id += 1
	for i in _defs.size():
		if _defs[i]["id"] == stored["id"]:
			_defs[i] = stored
			save_all()
			return stored
	_defs.append(stored)
	_next_id = maxi(_next_id, _numeric_suffix(stored["id"]) + 1)
	save_all()
	return stored


static func erase(card_id: String) -> void:
	ensure_loaded()
	for i in _defs.size():
		if _defs[i]["id"] == card_id:
			_defs.remove_at(i)
			CardDB.unregister_card(card_id)
			save_all()
			return


static func reset_for_test() -> void:
	_loaded = false
	_defs = []
	_next_id = 1


# ------------------------------------------------------------------ 美术
## 把用户选的本地图片复制到 user://custom_art/，返回可用的 user:// 路径。
static func import_art(source_path: String) -> String:
	if source_path == "":
		return ""
	DirAccess.make_dir_recursive_absolute(ART_DIR)
	var ext := source_path.get_extension().to_lower()
	if ext == "":
		ext = "png"
	if not (ext in ["png", "jpg", "jpeg", "webp", "bmp"]):
		return ""
	var target := "%s/art_%d.%s" % [ART_DIR, Time.get_ticks_usec(), ext]
	var bytes := FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty():
		return ""
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(bytes)
	f.close()
	CardDB.texture(target) # 预热缓存
	return target


## 内置美术库（res://assets/art/ 下的全部卡图）。
static func builtin_arts() -> Array:
	var dir := DirAccess.open("res://assets/art")
	if dir == null:
		return []
	var out: Array = []
	for f in dir.get_files():
		if f.ends_with(".import"):
			continue
		var e := f.get_extension().to_lower()
		if e in ["webp", "png", "jpg", "jpeg"]:
			out.append("res://assets/art/" + f)
	out.sort()
	return out


# ------------------------------------------------------------------ 构建
## 编辑器表单 -> 卡牌定义（可直接交给 CardView / 对局使用）。
static func build(spec: Dictionary) -> Dictionary:
	var is_minion := str(spec.get("type", "MINION")) == "MINION"
	var def := {
		"id": str(spec.get("id", "")),
		"name": str(spec.get("name", "")).strip_edges(),
		"cost": clampi(int(spec.get("cost", 1)), 0, 10),
		"type": "MINION" if is_minion else "SPELL",
		"class": str(spec.get("class", "NEUTRAL")),
		"rarity": str(spec.get("rarity", "COMMON")),
		"set": "CUSTOM",
		"text": str(spec.get("text", "")),
		"art": str(spec.get("art", "")),
		"race": str(spec.get("race", "")),
	}
	if def["name"] == "":
		def["name"] = "未命名卡牌"
	if def["name"].length() > MAX_NAME_LEN:
		def["name"] = def["name"].substr(0, MAX_NAME_LEN)
	if is_minion:
		def["attack"] = clampi(int(spec.get("attack", 1)), 0, 30)
		def["health"] = clampi(int(spec.get("health", 1)), 1, 30)
	var words: Array = []
	for k in spec.get("keywords", []):
		words.append(str(k))
	if not words.is_empty():
		def["keywords"] = words
	var effects := _build_effects(spec, is_minion)
	if not effects.is_empty():
		def["effects"] = effects
	if def["text"] == "":
		def["text"] = describe(effects, words, def["race"])
	return def


static func _build_effects(spec: Dictionary, is_spell: bool) -> Array:
	var target_mode := str(spec.get("target_mode", ""))
	var by_trigger := {}
	var order: Array = []
	for row in spec.get("effects", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var trig := str(row.get("trigger", "spell" if is_spell else "battlecry"))
		var action := _build_action(row)
		if action.is_empty():
			continue
		if not by_trigger.has(trig):
			by_trigger[trig] = []
			order.append(trig)
		by_trigger[trig].append(action)
	var out: Array = []
	var target_assigned := false
	for trig in order:
		var effect := {"trigger": trig, "actions": by_trigger[trig]}
		if target_mode != "" and not target_assigned:
			effect["target"] = target_mode
			effect["filter"] = {}
			target_assigned = true
		out.append(effect)
	return out


static func _build_action(row: Dictionary) -> Dictionary:
	var kind := str(row.get("do", ""))
	match kind:
		"damage", "damage_all":
			var a := {"do": kind, "amount": maxi(1, int(row.get("amount", 1)))}
			if kind == "damage":
				a["to"] = str(row.get("to", "chosen"))
				a["spell"] = true
			else:
				a["pool"] = str(row.get("pool", "all_minions"))
			return a
		"random_damage":
			return {
				"do": "random_damage",
				"amount": maxi(1, int(row.get("amount", 1))),
				"count": maxi(1, int(row.get("count", 1))),
				"pool": str(row.get("pool", "enemy_characters")),
			}
		"heal":
			return {"do": "heal", "amount": maxi(0, int(row.get("amount", 1))),
				"to": str(row.get("to", "chosen"))}
		"buff":
			return {"do": "buff", "atk": int(row.get("atk", 0)), "hp": int(row.get("hp", 0)),
				"to": str(row.get("to", "chosen"))}
		"draw":
			return {"do": "draw", "count": maxi(1, int(row.get("count", 1))),
				"who": str(row.get("who", "owner"))}
		"armor":
			return {"do": "armor", "amount": maxi(1, int(row.get("amount", 1))),
				"who": str(row.get("who", "owner"))}
		"summon":
			var token := str(row.get("token", ""))
			if token == "" or not CardDB.exists(token):
				return {}
			return {"do": "summon", "card": token, "count": maxi(1, int(row.get("count", 1))),
				"who": "owner"}
		"destroy", "freeze":
			return {"do": kind, "to": str(row.get("to", "chosen"))}
		"give_keyword":
			var kw := str(row.get("keyword", "TAUNT"))
			if kw == "":
				return {}
			return {"do": "give_keyword", "keyword": kw, "to": str(row.get("to", "chosen"))}
		"set_attack", "set_health":
			return {"do": kind, "value": maxi(0, int(row.get("amount", 1))),
				"to": str(row.get("to", "chosen"))}
		"gain_mana":
			return {"do": "gain_mana", "amount": maxi(1, int(row.get("amount", 1)))}
	return {}


# ------------------------------------------------------------------ 描述生成
static func _trigger_prefix(trigger: String) -> String:
	match trigger:
		"battlecry": return "战吼："
		"deathrattle": return "亡语："
		"end_of_turn": return "回合结束时，"
		"on_summon": return "召唤时，"
		"on_self_damaged": return "受伤时，"
	return ""


static func _target_name(sel: String) -> String:
	if sel == "chosen":
		return "目标"
	for t in TARGETS:
		if t[0] == sel:
			return t[1]
	return "目标"


static func _pool_name(sel: String) -> String:
	for t in POOLS:
		if t[0] == sel:
			return t[1]
	return "所有角色"


static func _who_name(who: String) -> String:
	match who:
		"opponent": return "对手"
		"both": return "双方"
	return "你"


static func _keyword_name(kw: String) -> String:
	for k in KEYWORDS:
		if k[0] == kw:
			return k[1]
	return kw


## 根据效果拼一段中文描述（用户没手写描述时使用）。
static func describe(effects: Array, keywords: Array, race: String) -> String:
	var parts: Array = []
	if race != "" and CardDB.race_name(race) != "":
		pass
	for kw in keywords:
		parts.append("【%s】" % _keyword_name(str(kw)))
	for e in effects:
		var chunk := ""
		for a in e.get("actions", []):
			chunk += _action_text(a)
		if chunk == "":
			continue
		parts.append(_trigger_prefix(str(e.get("trigger", ""))) + chunk)
	return "".join(parts)


static func _action_text(a: Dictionary) -> String:
	var kind := str(a.get("do", ""))
	match kind:
		"damage":
			return "对%s造成%d点伤害。" % [_target_name(str(a.get("to", "chosen"))),
				int(a.get("amount", 0))]
		"heal":
			return "为%s恢复%d点生命。" % [_target_name(str(a.get("to", "chosen"))),
				int(a.get("amount", 0))]
		"buff":
			return "%s获得+%d/+%d。" % [_target_name(str(a.get("to", "chosen"))),
				int(a.get("atk", 0)), int(a.get("hp", 0))]
		"draw":
			return "%s抽%d张牌。" % [_who_name(str(a.get("who", "owner"))),
				int(a.get("count", 1))]
		"armor":
			return "%s获得%d点护甲。" % [_who_name(str(a.get("who", "owner"))),
				int(a.get("amount", 0))]
		"summon":
			var tname := str(CardDB.card(str(a.get("card", ""))).get("name", "随从"))
			return "召唤%d个%s。" % [int(a.get("count", 1)), tname]
		"destroy":
			return "消灭%s。" % _target_name(str(a.get("to", "chosen")))
		"freeze":
			return "冻结%s。" % _target_name(str(a.get("to", "chosen")))
		"damage_all":
			return "对%s造成%d点伤害。" % [_pool_name(str(a.get("pool", "all_minions"))),
				int(a.get("amount", 0))]
		"random_damage":
			return "随机对%s造成%d点伤害，共%d次。" % [
				_pool_name(str(a.get("pool", "enemy_characters"))),
				int(a.get("amount", 0)), int(a.get("count", 1))]
		"give_keyword":
			return "%s获得%s。" % [_target_name(str(a.get("to", "chosen"))),
				_keyword_name(str(a.get("keyword", "")))]
		"set_attack":
			return "将%s的攻击力变为%d。" % [_target_name(str(a.get("to", "chosen"))),
				int(a.get("value", 0))]
		"set_health":
			return "将%s的生命值变为%d。" % [_target_name(str(a.get("to", "chosen"))),
				int(a.get("value", 0))]
		"gain_mana":
			return "本回合获得%d个法力水晶。" % int(a.get("amount", 1))
	return ""


# ------------------------------------------------------------------ 表单
static func blank_spec(art := "") -> Dictionary:
	return {
		"id": "",
		"name": "",
		"type": "MINION",
		"class": "NEUTRAL",
		"rarity": "COMMON",
		"race": "",
		"cost": 2,
		"attack": 2,
		"health": 2,
		"keywords": [],
		"effects": [],
		"target_mode": "",
		"art": art,
		"text": "",
	}


## 卡牌定义 -> 编辑器表单（编辑存量卡时用）。
static func to_spec(def: Dictionary) -> Dictionary:
	var spec := blank_spec(str(def.get("art", "")))
	spec["id"] = str(def.get("id", ""))
	spec["name"] = str(def.get("name", ""))
	spec["type"] = str(def.get("type", "MINION"))
	spec["class"] = str(def.get("class", "NEUTRAL"))
	spec["rarity"] = str(def.get("rarity", "COMMON"))
	spec["race"] = str(def.get("race", ""))
	spec["cost"] = int(def.get("cost", 0))
	spec["attack"] = int(def.get("attack", 0))
	spec["health"] = int(def.get("health", 1))
	spec["text"] = str(def.get("text", ""))
	spec["keywords"] = def.get("keywords", []).duplicate()
	spec["target_mode"] = str(def.get("target_mode", ""))
	var rows: Array = []
	for e in def.get("effects", []):
		if e.has("target") and spec["target_mode"] == "":
			spec["target_mode"] = str(e["target"])
		for a in e.get("actions", []):
			var row := {
				"trigger": str(e.get("trigger", "")),
				"do": str(a.get("do", "")),
				"amount": int(a.get("amount", a.get("value", 1))),
				"atk": int(a.get("atk", 0)),
				"hp": int(a.get("hp", 0)),
				"count": int(a.get("count", 1)),
				"to": str(a.get("to", "chosen")),
				"who": str(a.get("who", "owner")),
				"pool": str(a.get("pool", "enemy_characters")),
				"keyword": str(a.get("keyword", "TAUNT")),
				"token": str(a.get("card", "")),
			}
			rows.append(row)
	spec["effects"] = rows
	return spec


static func blank_effect_row(is_spell: bool) -> Dictionary:
	return {
		"trigger": "spell" if is_spell else "battlecry",
		"do": "damage",
		"amount": 2,
		"atk": 1,
		"hp": 1,
		"count": 1,
		"to": "chosen",
		"who": "owner",
		"pool": "enemy_characters",
		"keyword": "TAUNT",
		"token": "",
	}
