class_name PlayerState
extends RefCounted
## 单方玩家状态。只存数据与原语操作，规则判定集中在 GameState。

var index: int = 0
var hero_class: String = "NEUTRAL"
var hero_name: String = ""
var portrait: String = ""
var hp: int = 30
var max_hp: int = 30
var armor: int = 0
var mana: int = 0
var max_mana: int = 0
var deck: Array = []
var hand: Array = []
var board: Array = []
var graveyard: Array = []
var fatigue: int = 0
var hero_power: Dictionary = {}
var hero_power_used: bool = false
var frozen: bool = false


func hero_id() -> int:
	return Enums.hero_id(index)


func taunt_minions() -> Array:
	var out: Array = []
	for m in board:
		if m.has_keyword("TAUNT"):
			out.append(m)
	return out


func spell_power() -> int:
	var total := 0
	for m in board:
		total += m.spell_damage
	return total


func find_minion(instance_id: int):
	for m in board:
		if m.instance_id == instance_id:
			return m
	return null


func board_value() -> float:
	var value := 0.0
	for m in board:
		value += m.current_attack() * 1.1 + m.health * 1.15
		if m.has_keyword("TAUNT"):
			value += 1.0
		if m.has_keyword("DIVINE_SHIELD"):
			value += 2.0
		if m.has_keyword("WINDFURY"):
			value += m.current_attack() * 0.7
		value += m.spell_damage * 1.5
	return value
