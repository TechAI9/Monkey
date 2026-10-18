class_name DeckStore
extends RefCounted
## 卡组仓库：多套 30 张卡组，存于 user://decks.json。
## 纯静态（与 CardDB 一致），无需 Autoload，无头测试可直接调用。

const PATH := "user://decks.json"
const VERSION := 1
const DECK_SIZE := 30
const MAX_COPIES := 2
const MAX_LEGENDARY := 1
const MAX_NAME_LEN := 14

static var _loaded := false
static var _decks: Array = []
static var _next_id := 1
## 无头测试时置 false，避免写入用户存档。
static var write_enabled := true


# ------------------------------------------------------------------ load / save
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	CardDB.ensure_loaded()
	if FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			for d in parsed.get("decks", []):
				var deck := _normalize(d)
				if not deck.is_empty():
					_decks.append(deck)
					_next_id = maxi(_next_id, _numeric_suffix(deck["id"]) + 1)
	if _decks.is_empty():
		_seed_defaults()


## 首次运行：每个职业拷贝一份预设卡组，保证一进游戏就能打。
static func _seed_defaults() -> void:
	for h in CardDB.heroes():
		var cards: Array = []
		for cid in h.get("deck", []):
			cards.append(str(cid))
		var deck := {
			"id": "deck_%d" % _next_id,
			"name": "%s 基础卡组" % str(h.get("title", h.get("name", "英雄"))),
			"hero_class": str(h.get("id", "NEUTRAL")),
			"cards": cards,
		}
		_next_id += 1
		_decks.append(deck)
	save_all()


static func _numeric_suffix(id: String) -> int:
	var idx := id.rfind("_")
	if idx < 0:
		return 0
	return int(id.substr(idx + 1))


static func _normalize(d: Dictionary) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	var cards: Array = []
	for c in d.get("cards", []):
		var cid := str(c)
		if CardDB.exists(cid):
			cards.append(cid)
	var cls := str(d.get("hero_class", "MAGE"))
	return {
		"id": str(d.get("id", "deck_%d" % _next_id)),
		"name": str(d.get("name", "未命名卡组")),
		"hero_class": cls,
		"cards": cards,
	}


static func save_all() -> void:
	var payload := {"version": VERSION, "decks": _decks}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("DeckStore: 无法写入 %s" % PATH)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()


# ------------------------------------------------------------------ query
static func all() -> Array:
	ensure_loaded()
	return _decks.duplicate()


static func decks_for_class(hero_class: String) -> Array:
	ensure_loaded()
	var out: Array = []
	for d in _decks:
		if d["hero_class"] == hero_class:
			out.append(d)
	return out


static func get_deck(deck_id: String) -> Dictionary:
	ensure_loaded()
	for d in _decks:
		if d["id"] == deck_id:
			return d
	return {}


static func default_for_class(hero_class: String) -> Dictionary:
	var list := decks_for_class(hero_class)
	if list.is_empty():
		return {}
	return list[0]


static func count() -> int:
	ensure_loaded()
	return _decks.size()


# ------------------------------------------------------------------ mutate
static func new_deck_id() -> String:
	ensure_loaded()
	return "deck_%d" % _next_id


static func create(name: String, hero_class: String, cards: Array = []) -> Dictionary:
	ensure_loaded()
	var deck := {
		"id": "deck_%d" % _next_id,
		"name": _clean_name(name, hero_class),
		"hero_class": hero_class,
		"cards": cards.duplicate(),
	}
	_next_id += 1
	_decks.append(deck)
	save_all()
	return deck


static func duplicate_deck(deck_id: String) -> Dictionary:
	var src := get_deck(deck_id)
	if src.is_empty():
		return {}
	var deck := {
		"id": "deck_%d" % _next_id,
		"name": _clean_name(src["name"] + " 副本", src["hero_class"]),
		"hero_class": src["hero_class"],
		"cards": src["cards"].duplicate(),
	}
	_next_id += 1
	_decks.append(deck)
	save_all()
	return deck


static func update(deck: Dictionary) -> void:
	ensure_loaded()
	for i in _decks.size():
		if _decks[i]["id"] == deck["id"]:
			_decks[i] = deck
			save_all()
			return


static func erase(deck_id: String) -> void:
	ensure_loaded()
	for i in _decks.size():
		if _decks[i]["id"] == deck_id:
			_decks.remove_at(i)
			save_all()
			return


static func rename(deck_id: String, new_name: String) -> void:
	var deck := get_deck(deck_id)
	if deck.is_empty():
		return
	deck["name"] = _clean_name(new_name, deck["hero_class"])
	update(deck)


static func _clean_name(raw: String, hero_class: String) -> String:
	var name := raw.strip_edges()
	if name == "":
		name = "%s 卡组" % CardDB.class_name_of(hero_class)
	if name.length() > MAX_NAME_LEN:
		name = name.substr(0, MAX_NAME_LEN)
	return name


# ------------------------------------------------------------------ rules
## 把一张卡加入卡组，返回 {ok, reason}。
static func add_card(deck: Dictionary, card_id: String) -> Dictionary:
	var def := CardDB.card(card_id)
	if def.is_empty():
		return {"ok": false, "reason": "卡牌不存在"}
	if CardDB.is_token(card_id):
		return {"ok": false, "reason": "衍生牌不能加入卡组"}
	if deck["cards"].size() >= DECK_SIZE:
		return {"ok": false, "reason": "卡组已满 %d 张" % DECK_SIZE}
	if not _class_allows(deck["hero_class"], def):
		return {"ok": false, "reason": "不是本职业或中立卡牌"}
	var limit := _copy_limit(def)
	if copies_of(deck, card_id) >= limit:
		return {"ok": false, "reason": "%s 最多 %d 张" % [def.get("name", ""), limit]}
	deck["cards"].append(card_id)
	return {"ok": true, "reason": ""}


static func remove_card(deck: Dictionary, card_id: String) -> bool:
	var cards: Array = deck["cards"]
	var idx: int = cards.rfind(card_id)
	if idx < 0:
		return false
	cards.remove_at(idx)
	return true


static func copies_of(deck: Dictionary, card_id: String) -> int:
	var n := 0
	for c in deck["cards"]:
		if c == card_id:
			n += 1
	return n


static func _class_allows(hero_class: String, def: Dictionary) -> bool:
	var c := str(def.get("class", "NEUTRAL"))
	return c == "NEUTRAL" or c == hero_class


static func _copy_limit(def: Dictionary) -> int:
	return MAX_LEGENDARY if str(def.get("rarity", "")) == "LEGENDARY" else MAX_COPIES


## 卡组合法性：张数、职业、同名上限。返回 {ok, errors: []}
static func validate(deck: Dictionary) -> Dictionary:
	var errors: Array = []
	var cards: Array = deck.get("cards", [])
	if cards.size() != DECK_SIZE:
		errors.append("卡组需要 %d 张，当前 %d 张" % [DECK_SIZE, cards.size()])
	var counts := {}
	for cid in cards:
		var def := CardDB.card(str(cid))
		if def.is_empty():
			errors.append("未知卡牌 %s" % str(cid))
			continue
		if not _class_allows(deck.get("hero_class", "NEUTRAL"), def):
			errors.append("%s 不属于本职业" % str(def.get("name", cid)))
		counts[cid] = int(counts.get(cid, 0)) + 1
	for cid in counts:
		var def := CardDB.card(str(cid))
		var limit := _copy_limit(def)
		if int(counts[cid]) > limit:
			errors.append("%s 超过 %d 张" % [str(def.get("name", cid)), limit])
	return {"ok": errors.is_empty(), "errors": errors}


static func is_legal(deck: Dictionary) -> bool:
	return bool(validate(deck).get("ok", false))


## 费用曲线：下标 0..7（7 表示 7 费及以上）。
static func curve(deck: Dictionary) -> Array:
	var buckets := [0, 0, 0, 0, 0, 0, 0, 0]
	for cid in deck.get("cards", []):
		var def := CardDB.card(str(cid))
		if def.is_empty():
			continue
		var cost := int(def.get("cost", 0))
		buckets[mini(cost, 7)] += 1
	return buckets


## 按 card_id 聚合：[{card_id, def, count}]
static func grouped(deck: Dictionary) -> Array:
	var order: Array = []
	var counts := {}
	for cid in deck.get("cards", []):
		var key := str(cid)
		if not counts.has(key):
			counts[key] = 0
			order.append(key)
		counts[key] = int(counts[key]) + 1
	var out: Array = []
	for key in order:
		out.append({"card_id": key, "def": CardDB.card(key), "count": counts[key]})
	out.sort_custom(func(a, b):
		var ca := int(a["def"].get("cost", 0))
		var cb := int(b["def"].get("cost", 0))
		if ca == cb:
			return str(a["def"].get("name", "")) < str(b["def"].get("name", ""))
		return ca < cb
	)
	return out


## 测试/编辑器里重置缓存用。
static func reset_for_test() -> void:
	_loaded = false
	_decks = []
	_next_id = 1
