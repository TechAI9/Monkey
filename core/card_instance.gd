class_name CardInstance
extends RefCounted
## 卡牌运行时实例：手牌、牌库、战场共用。静态定义永远从 CardDB 读取。

var instance_id: int = 0
var card_id: String = ""
var owner: int = 0
var zone: String = Enums.ZONE_DECK

var attack: int = 0
var health: int = 0
var max_health: int = 0
var cost_override: int = -1

var keywords: Dictionary = {}
var spell_damage: int = 0
var enrage_attack: int = 0
var enrage_windfury: bool = false
var cost_reduce: int = 0

var attacks_used: int = 0
var summoned_turn: int = -1
var frozen: bool = false
var dead: bool = false

var _temp_buffs: Array = []


func setup(p_instance_id: int, p_card_id: String, p_owner: int) -> void:
	instance_id = p_instance_id
	card_id = p_card_id
	owner = p_owner
	var d := CardDB.card(card_id)
	attack = int(d.get("attack", 0))
	health = int(d.get("health", 1))
	max_health = health
	spell_damage = int(d.get("spell_damage", 0))
	cost_reduce = int(d.get("cost_reduce", 0))
	var enrage: Dictionary = d.get("enrage", {})
	enrage_attack = int(enrage.get("attack", 0))
	enrage_windfury = bool(enrage.get("windfury", false))
	for k in d.get("keywords", []):
		keywords[k] = true


func def() -> Dictionary:
	return CardDB.card(card_id)


func name() -> String:
	return def().get("name", card_id)


func card_type() -> String:
	return def().get("type", "MINION")


func cost() -> int:
	if cost_override >= 0:
		return cost_override
	return int(def().get("cost", 0))


func has_keyword(word: String) -> bool:
	if keywords.has(word):
		return true
	if word == "WINDFURY" and enrage_windfury and is_damaged():
		return true
	return false


func is_damaged() -> bool:
	return health < max_health


func current_attack() -> int:
	var value := attack
	if enrage_attack > 0 and is_damaged():
		value += enrage_attack
	return max(0, value)


func max_attacks_per_turn() -> int:
	return 2 if has_keyword("WINDFURY") else 1


func can_attack(turn_number: int) -> bool:
	if dead or frozen or zone != Enums.ZONE_BOARD:
		return false
	if has_keyword("CANNOT_ATTACK"):
		return false
	if current_attack() <= 0:
		return false
	if attacks_used >= max_attacks_per_turn():
		return false
	if summoned_turn == turn_number and not has_keyword("CHARGE"):
		return false
	return true


func add_keyword(word: String) -> void:
	keywords[word] = true


func add_buff(atk_delta: int, hp_delta: int, temporary := false) -> void:
	attack += atk_delta
	if hp_delta != 0:
		max_health += hp_delta
		health += hp_delta
	if temporary:
		_temp_buffs.append({"atk": atk_delta, "hp": hp_delta})


func revert_temp_buffs() -> void:
	for b in _temp_buffs:
		attack -= int(b["atk"])
		max_health -= int(b["hp"])
		health -= int(b["hp"])
	_temp_buffs.clear()


func has_temp_buffs() -> bool:
	return not _temp_buffs.is_empty()


func snapshot() -> Dictionary:
	return {
		"id": instance_id,
		"card_id": card_id,
		"owner": owner,
		"attack": current_attack(),
		"health": health,
		"max_health": max_health,
	}
