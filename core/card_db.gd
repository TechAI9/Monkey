class_name CardDB
extends RefCounted
## 卡牌数据仓库（纯静态，无 Autoload 依赖，便于无头测试）。
## 数据来源：tools/build_cards.py 由 public/data + tools/cardspecs.py 生成。

const CARDS_PATH := "res://data/cards.json"
const HEROES_PATH := "res://data/heroes.json"

const KEYWORD_NAMES := {
	"TAUNT": "嘲讽",
	"CHARGE": "冲锋",
	"DIVINE_SHIELD": "圣盾",
	"WINDFURY": "风怒",
	"LIFESTEAL": "吸血",
	"FREEZE_ON_DAMAGE": "冰冻",
	"CANNOT_ATTACK": "无法攻击",
	"SPELL_COST_REDUCE": "法术减费",
}

const KEYWORD_TIPS := {
	"TAUNT": "敌方必须优先攻击具有嘲讽的随从。",
	"CHARGE": "召唤当回合即可攻击。",
	"DIVINE_SHIELD": "免疫下一次受到的伤害。",
	"WINDFURY": "每回合可以攻击两次。",
	"LIFESTEAL": "造成伤害时为你的英雄恢复等量生命。",
	"FREEZE_ON_DAMAGE": "受到其伤害的角色会被冻结。",
	"CANNOT_ATTACK": "无法进行攻击。",
	"SPELL_COST_REDUCE": "你的法术牌法力值消耗减少。",
}

const CLASS_COLORS := {
	"MAGE": Color("3f9fd8"),
	"WARRIOR": Color("bb4a3c"),
	"PALADIN": Color("d8a92a"),
	"NEUTRAL": Color("8d939e"),
}

const CLASS_NAMES := {
	"MAGE": "法师",
	"WARRIOR": "战士",
	"PALADIN": "圣骑士",
	"NEUTRAL": "中立",
}

## 种族：只做卡面标签与筛选，不参与规则判定。
const RACE_NAMES := {
	"": "",
	"BEAST": "野兽",
	"DRAGON": "龙",
	"MURLOC": "鱼人",
	"DEMON": "恶魔",
	"MECH": "机械",
	"PIRATE": "海盗",
	"TOTEM": "图腾",
	"ELEMENTAL": "元素",
	"UNDEAD": "亡灵",
}

const RARITY_NAMES := {
	"FREE": "免费",
	"COMMON": "普通",
	"RARE": "稀有",
	"EPIC": "史诗",
	"LEGENDARY": "传说",
}

const RARITY_COLORS := {
	"FREE": Color("d9d4c8"),
	"COMMON": Color("d9d4c8"),
	"RARE": Color("4a9ee8"),
	"EPIC": Color("b168e8"),
	"LEGENDARY": Color("f0b23c"),
}

static var _loaded := false
static var _cards: Dictionary = {}
static var _tokens: Dictionary = {}
static var _extras: Dictionary = {}
static var _heroes: Array = []
static var _hero_by_id: Dictionary = {}
static var _art_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}
static var _load_error := ""


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var raw := _read_json(CARDS_PATH)
	if raw.is_empty():
		push_error("CardDB: 无法读取 %s" % CARDS_PATH)
		return
	for c in raw.get("cards", []):
		_cards[c["id"]] = c
	for t in raw.get("tokens", []):
		_tokens[t["id"]] = t
	var hero_raw := _read_json(HEROES_PATH)
	for h in hero_raw.get("heroes", []):
		_heroes.append(h)
		_hero_by_id[h["id"]] = h


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_load_error = "missing " + path
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_error = "invalid json " + path
		return {}
	return parsed


static func load_error() -> String:
	ensure_loaded()
	return _load_error


## 注册外部卡牌（自定义卡）。会覆盖同 id 的条目，并清空贴图缓存。
static func register_cards(list: Array) -> void:
	ensure_loaded()
	for c in list:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cid := str(c.get("id", ""))
		if cid == "":
			continue
		_extras[cid] = c
	_art_cache.clear()
	_tex_cache.clear()


static func unregister_card(card_id: String) -> void:
	if _extras.erase(card_id):
		_art_cache.erase(card_id)
		_tex_cache.clear()


## 自定义（用户编辑）卡牌，按 id 排序。
static func extra_cards() -> Array:
	ensure_loaded()
	var out: Array = _extras.values()
	out.sort_custom(func(a, b): return str(a.get("name", "")) < str(b.get("name", "")))
	return out


static func is_custom(card_id: String) -> bool:
	ensure_loaded()
	return _extras.has(card_id)


static func card(card_id: String) -> Dictionary:
	ensure_loaded()
	# 自定义/覆盖优先，其次官方卡，最后衍生 token
	if _extras.has(card_id):
		return _extras[card_id]
	if _cards.has(card_id):
		return _cards[card_id]
	return _tokens.get(card_id, {})


static func exists(card_id: String) -> bool:
	ensure_loaded()
	return _cards.has(card_id) or _extras.has(card_id) or _tokens.has(card_id)


static func is_token(card_id: String) -> bool:
	ensure_loaded()
	return _tokens.has(card_id)


## 衍生牌（召唤物）列表，供自定义卡「召唤」动作挑选。
static func tokens() -> Array:
	ensure_loaded()
	var out: Array = _tokens.values()
	out.sort_custom(func(a, b): return int(a.get("cost", 0)) < int(b.get("cost", 0)))
	return out


## 可收藏卡牌（不含衍生 token），含自定义卡；被覆盖的官方卡只保留覆盖版本。
static func all_cards() -> Array:
	ensure_loaded()
	var out: Array = []
	for cid in _cards:
		if not _extras.has(cid):
			out.append(_cards[cid])
	out.append_array(_extras.values())
	return out


## 官方原始卡牌定义（不含覆盖），用于「恢复默认」。
static func original(card_id: String) -> Dictionary:
	ensure_loaded()
	if _cards.has(card_id):
		return _cards[card_id]
	return _tokens.get(card_id, {})


static func heroes() -> Array:
	ensure_loaded()
	return _heroes


static func hero(hero_id: String) -> Dictionary:
	ensure_loaded()
	return _hero_by_id.get(hero_id, {})


static func class_color(card_class: String) -> Color:
	return CLASS_COLORS.get(card_class, CLASS_COLORS["NEUTRAL"])


static func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS["COMMON"])


static func keyword_name(word: String) -> String:
	return KEYWORD_NAMES.get(word, word)


static func art(card_id: String) -> Texture2D:
	ensure_loaded()
	if _art_cache.has(card_id):
		return _art_cache[card_id]
	var def := card(card_id)
	var tex := texture(str(def.get("art", "")))
	_art_cache[card_id] = tex
	return tex


## 按 res:// 路径直接取贴图（英雄立绘、图标等非卡牌资源）。
## 也支持 user:// 下的用户导入图片（运行时生成 ImageTexture，不走资源导入）。
static func texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if path.begins_with("user://"):
		if FileAccess.file_exists(path):
			var img := Image.new()
			if img.load(path) == OK:
				tex = ImageTexture.create_from_image(img)
	else:
		if ResourceLoader.exists(path):
			tex = load(path)
	_tex_cache[path] = tex
	return tex


static func class_name_of(card_class: String) -> String:
	return CLASS_NAMES.get(card_class, card_class)


static func race_name(race: String) -> String:
	return RACE_NAMES.get(race, "")


static func rarity_name(rarity: String) -> String:
	return RARITY_NAMES.get(rarity, rarity)


## 把卡牌描述转成 RichTextLabel 可用的 BBCode，关键字高亮金色。
static func format_text(card_def: Dictionary) -> String:
	var text: String = card_def.get("text", "")
	if text == "":
		return ""
	# 先转义 BBCode 可能误伤的中括号
	text = text.replace("[", "［").replace("]", "］")
	var words := ["嘲讽", "冲锋", "圣盾", "风怒", "吸血", "冻结", "战吼", "亡语",
		"法术伤害", "无法攻击", "激怒", "潜行", "剧毒"]
	for w in words:
		text = text.replace(w, "[color=#e8c37a][b]%s[/b][/color]" % w)
	return text
