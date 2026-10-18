class_name AIController
extends RefCounted
## 启发式 AI：斩杀检测 -> 出牌/换怪/英雄技能评分 -> 选择最优动作。
## 不做多步搜索，保证响应速度；对局节奏由 BattleScreen 控制。

var state: GameState
var player: int
var _blacklist: Dictionary = {}
var _last_key: String = ""


func _init(p_state: GameState, p_player: int) -> void:
	state = p_state
	player = p_player


func start_turn() -> void:
	_blacklist.clear()


func notify_result(ok: bool) -> void:
	if not ok and _last_key != "":
		_blacklist[_last_key] = true


func choose_mulligan() -> Array:
	var p: PlayerState = state.players[player]
	var out: Array = []
	for i in p.hand.size():
		var c: CardInstance = p.hand[i]
		if c.cost() >= 5:
			out.append(i)
		elif c.cost() >= 4 and i == p.hand.size() - 1:
			out.append(i)
	return out


func take_action() -> Dictionary:
	if state.phase != Enums.PHASE_PLAYING or state.current != player:
		return {"type": "end"}
	if _has_lethal():
		var lethal := _lethal_action()
		if not lethal.is_empty():
			return _remember(lethal)

	var p: PlayerState = state.players[player]
	var best := {"type": "end", "score": 0.0}

	# 1) 手牌
	for i in p.hand.size():
		var c: CardInstance = p.hand[i]
		var check := state.can_play_card(i, 0)
		if not check.get("ok", false) and not check.get("needs_target", false):
			continue
		var targets: Array = [0]
		if check.get("needs_target", false):
			targets = check.get("targets", [])
		for t in targets:
			var key := "play:%d:%d" % [i, t]
			if _blacklist.has(key):
				continue
			if t != 0 and not state.can_play_card(i, t).get("ok", false):
				continue
			var s := _score_play(i, t)
			if s > best.get("score", 0.0):
				best = {"type": "play", "index": i, "target": t,
					"position": p.board.size(), "score": s, "_key": key}

	# 2) 随从攻击
	for m in p.board:
		for t in state.get_valid_attack_targets(m.instance_id):
			var key := "attack:%d:%d" % [m.instance_id, t]
			if _blacklist.has(key):
				continue
			var s := _score_attack(m, t)
			if s > best.get("score", 0.0):
				best = {"type": "attack", "attacker": m.instance_id, "target": t,
					"score": s, "_key": key}

	# 3) 英雄技能
	var power := state.can_use_hero_power(player, 0)
	if power.get("ok", false) or power.get("needs_target", false):
		var pts: Array = [0]
		if power.get("needs_target", false):
			pts = power.get("targets", [])
		for t in pts:
			var key := "power:%d" % t
			if _blacklist.has(key):
				continue
			var s := _score_hero_power(t)
			if s > best.get("score", 0.0):
				best = {"type": "hero_power", "target": t, "score": s, "_key": key}

	if best.get("score", 0.0) < 0.5:
		return {"type": "end"}
	return _remember(best)


func _remember(action: Dictionary) -> Dictionary:
	_last_key = action.get("_key", "")
	action.erase("_key")
	return action


# ------------------------------------------------------------------ lethal
func _has_lethal() -> bool:
	var enemy: PlayerState = state.players[1 - player]
	var total := 0
	if enemy.taunt_minions().is_empty():
		for m in state.players[player].board:
			if m.can_attack(state.turn):
				total += m.current_attack() * m.max_attacks_per_turn()
	for c in state.players[player].hand:
		if state.get_card_cost(c, player) <= state.players[player].mana:
			total += _face_damage(c)
	var hp: Dictionary = state.players[player].hero_power
	if state.players[player].mana >= int(hp.get("cost", 2)) \
			and not state.players[player].hero_power_used:
		total += _hero_power_face_damage()
	return total >= enemy.hp + enemy.armor


func _lethal_action() -> Dictionary:
	var p: PlayerState = state.players[player]
	var enemy: PlayerState = state.players[1 - player]
	var best := {}
	var best_dmg := 0

	if enemy.taunt_minions().is_empty():
		for m in p.board:
			if m.can_attack(state.turn):
				var key := "attack:%d:%d" % [m.instance_id, enemy.hero_id()]
				if _blacklist.has(key):
					continue
				if m.current_attack() > best_dmg:
					best_dmg = m.current_attack()
					best = {"type": "attack", "attacker": m.instance_id,
						"target": enemy.hero_id(), "_key": key}

	for i in p.hand.size():
		var c: CardInstance = p.hand[i]
		if state.get_card_cost(c, player) > p.mana:
			continue
		var dmg := _face_damage(c)
		if dmg > best_dmg:
			var check := state.can_play_card(i, enemy.hero_id())
			if check.get("ok", false):
				best_dmg = dmg
				best = {"type": "play", "index": i, "target": enemy.hero_id(),
					"position": p.board.size(), "_key": "play:%d:%d" % [i, enemy.hero_id()]}

	if best.is_empty() and _hero_power_face_damage() > 0:
		if state.can_use_hero_power(player, enemy.hero_id()).get("ok", false):
			best = {"type": "hero_power", "target": enemy.hero_id(),
				"_key": "power:%d" % enemy.hero_id()}
	return best


func _face_damage(c: CardInstance) -> int:
	var d := c.def()
	if d.get("type", "") != "SPELL":
		return 0
	var spec_allows_hero := false
	for e in d.get("effects", []):
		var target: String = e.get("target", "")
		if target in ["any", "enemy_character", "any_hero"]:
			spec_allows_hero = true
	if not spec_allows_hero:
		return 0
	var total := 0
	var power: int = state.players[player].spell_power()
	for e in d.get("effects", []):
		for a in e.get("actions", []):
			if a.get("do") == "damage" and a.get("to", "") == "chosen":
				total += int(a.get("amount", 0)) + power
	return total


func _hero_power_face_damage() -> int:
	var hp: Dictionary = state.players[player].hero_power
	var total := 0
	for e in hp.get("effects", []):
		for a in e.get("actions", []):
			if a.get("do") == "damage" and a.get("to", "") == "chosen":
				total += int(a.get("amount", 0))
	return total


# ------------------------------------------------------------------ scoring
func _score_play(index: int, target: int) -> float:
	var p: PlayerState = state.players[player]
	var c: CardInstance = p.hand[index]
	var d := c.def()
	var cost := state.get_card_cost(c, player)
	var score := -cost * 0.55
	if d.get("type", "") == "MINION":
		score += _minion_value_def(d)
		score += 0.6 * (state.turn / 4.0)
	for e in d.get("effects", []):
		var trigger: String = e.get("trigger", "")
		if trigger == "battlecry" or trigger == "spell":
			score += _score_effect(e, c, target)
	return score


func _score_effect(e: Dictionary, c: CardInstance, target: int) -> float:
	var score := 0.0
	for a in e.get("actions", []):
		score += _score_action(a, c, target)
	return score


func _action_amount(a: Dictionary, card_def: Dictionary) -> int:
	var amount := int(a.get("amount", 0))
	if a.get("amount_from", "") == "armor":
		amount = state.players[player].armor
	if a.has("bonus_if"):
		var cond: Dictionary = a["bonus_if"]
		if cond.has("hero_hp_lte") and state.players[player].hp <= int(cond["hero_hp_lte"]):
			amount += int(cond.get("bonus", 0))
	if card_def.get("type", "") == "SPELL":
		amount += state.players[player].spell_power()
	return amount


func _score_action(a: Dictionary, c: CardInstance, target: int) -> float:
	var d := c.def()
	var kind: String = a.get("do", "")
	var me: PlayerState = state.players[player]
	var enemy: PlayerState = state.players[1 - player]
	var to: String = a.get("to", "chosen")
	match kind:
		"damage":
			var amount := _action_amount(a, d)
			if to == "chosen":
				return _damage_value(target, amount)
			if to in ["all_enemy_minions", "enemy_minions"]:
				var s := 0.0
				for m in enemy.board:
					s += _damage_value(m.instance_id, amount)
				return s
			if to in ["all_enemy_characters", "enemy_characters"]:
				var s2 := _damage_value(enemy.hero_id(), amount)
				for m in enemy.board:
					s2 += _damage_value(m.instance_id, amount)
				return s2
			if to in ["all_minions", "all_characters", "all_other_minions",
					"all_other_characters", "other_characters"]:
				var s3 := 0.0
				if to in ["all_characters", "all_other_characters", "other_characters"]:
					s3 += _damage_value(enemy.hero_id(), amount) * 0.8
					s3 += _damage_value(me.hero_id(), amount)
				for m in enemy.board:
					s3 += _damage_value(m.instance_id, amount)
				for m in me.board:
					if c.card_type() == "MINION" and m.instance_id == c.instance_id:
						continue
					s3 += _damage_value(m.instance_id, amount)
				return s3
			return amount * 0.5
		"damage_all":
			var amount2 := _action_amount(a, d)
			var pool: String = a.get("pool", "all_minions")
			var s4 := 0.0
			if pool in ["enemy_minions", "all_enemy_minions"]:
				for m in enemy.board:
					s4 += _damage_value(m.instance_id, amount2)
			elif pool in ["enemy_characters", "all_enemy_characters"]:
				s4 += _damage_value(enemy.hero_id(), amount2)
				for m in enemy.board:
					s4 += _damage_value(m.instance_id, amount2)
			else:
				for m in enemy.board:
					s4 += _damage_value(m.instance_id, amount2)
				for m in me.board:
					if m.instance_id != c.instance_id:
						s4 += _damage_value(m.instance_id, amount2)
				if pool == "all_characters":
					s4 += _damage_value(enemy.hero_id(), amount2) * 0.7
					s4 += _damage_value(me.hero_id(), amount2)
			return s4
		"random_damage":
			var amount3 := _action_amount(a, d)
			var count := int(a.get("count", 1))
			if a.get("grow_count", false):
				count += state.players[player].spell_power()
			var divisor := 2.0
			if state.players[1 - player].board.is_empty():
				divisor = 1.1
			return amount3 * count / divisor
		"heal":
			var amount4 := int(a.get("amount", 0))
			var who: String = a.get("to", "chosen")
			if who == "owner_hero":
				return _heal_value(me.hero_id(), amount4)
			if who == "chosen":
				return _heal_value(target, amount4)
			return amount4 * 0.4
		"buff":
			var atk := int(a.get("atk", 0))
			var hp := int(a.get("hp", 0))
			var value := atk * 1.15 + hp * 1.25
			if a.get("duration", "") == "permanent":
				value *= 1.0
			else:
				value *= 1.15
			if to == "chosen":
				return value if _is_friendly(target) else -value * 0.6
			if to in ["all_friendly_minions", "friendly_minions"]:
				return value * me.board.size()
			return value * 0.5
		"give_keyword":
			if to == "chosen":
				return 1.6 if _is_friendly(target) else -1.0
			return 1.2
		"set_attack":
			if to == "chosen":
				if _is_friendly(target):
					return 0.0
				var m = state._find_minion(target)
				if m != null:
					return (m.current_attack() - int(a.get("value", 0))) * 0.9
			return 0.0
		"set_health":
			return 0.0
		"destroy":
			if to == "chosen":
				if _is_friendly(target):
					return -3.0
				var m2 = state._find_minion(target)
				if m2 != null:
					return _minion_value(m2) + 1.0
				return 0.0
			if to == "all_other_minions":
				var s5 := 0.0
				for m in enemy.board:
					s5 += _minion_value(m)
				return s5
			return 0.0
		"freeze":
			if to == "chosen":
				return 1.2 if not _is_friendly(target) else 0.0
			if to == "all_enemy_minions":
				return 1.2 * enemy.board.size()
			return 0.0
		"draw":
			return 1.6 * int(a.get("count", 1))
		"draw_per_damaged_friendly":
			var n := 0
			if me.hp < me.max_hp:
				n += 1
			for m in me.board:
				if m.is_damaged():
					n += 1
			return 1.5 * n
		"summon":
			var token_value := _minion_value_def(CardDB.card(a.get("card", "")))
			return token_value * int(a.get("count", 1))
		"summon_until_full":
			var token_value2 := _minion_value_def(CardDB.card(a.get("card", "")))
			return token_value2 * (7 - me.board.size())
		"armor":
			return 0.8 * int(a.get("amount", 0))
		"transform":
			if to == "chosen" and not _is_friendly(target):
				var m3 = state._find_minion(target)
				if m3 != null:
					return maxf(0.0, _minion_value(m3) - 1.2)
			return 0.0
		"add_card":
			return 2.0
		"double_attack":
			if to == "chosen" and _is_friendly(target):
				var m4 = state._find_minion(target)
				if m4 != null:
					return m4.current_attack() * 0.9
			return 0.0
		"discard_hand":
			return -me.hand.size() * 1.2
		"gain_mana":
			return 1.0
		"set_hero_health":
			if to == "chosen":
				if _is_friendly(target):
					return maxf(0.0, 15 - me.hp) * 0.7
				return maxf(0.0, enemy.hp - 15) * 1.2
			return 0.0
	return 0.0


func _damage_value(target_id: int, amount: int) -> float:
	if amount <= 0:
		return 0.0
	if Enums.is_hero(target_id):
		if Enums.hero_owner(target_id) == player:
			return -amount * 0.9
		return amount * 1.0
	var m = state._find_minion(target_id)
	if m == null:
		return 0.0
	if m.owner == player:
		return -mini(amount, m.health) * 0.85
	var effective := amount
	if m.has_keyword("DIVINE_SHIELD"):
		effective = 0
	var dealt := mini(effective, m.health)
	var value := dealt * 1.15
	if effective >= m.health:
		value += 1.8 + m.current_attack() * 0.25
	return value


func _heal_value(target_id: int, amount: int) -> float:
	if Enums.is_hero(target_id):
		if Enums.hero_owner(target_id) != player:
			return -amount * 0.3
		var p: PlayerState = state.players[player]
		return mini(amount, p.max_hp - p.hp) * 0.75
	var m = state._find_minion(target_id)
	if m == null or m.owner != player:
		return 0.0
	return mini(amount, m.max_health - m.health) * 0.8


func _is_friendly(target_id: int) -> bool:
	if Enums.is_hero(target_id):
		return Enums.hero_owner(target_id) == player
	var m = state._find_minion(target_id)
	return m != null and m.owner == player


func _minion_value(m: CardInstance) -> float:
	var value := m.current_attack() * 1.1 + m.health * 1.2
	if m.has_keyword("TAUNT"):
		value += 1.4
	if m.has_keyword("DIVINE_SHIELD"):
		value += 2.2
	if m.has_keyword("WINDFURY"):
		value += m.current_attack() * 0.75
	if m.has_keyword("LIFESTEAL"):
		value += 1.0
	if m.has_keyword("CANNOT_ATTACK"):
		value -= 2.0
	value += m.spell_damage * 2.0
	if m.frozen:
		value -= 1.2
	return maxf(0.5, value)


func _minion_value_def(d: Dictionary) -> float:
	var value := float(d.get("attack", 0)) * 1.1 + float(d.get("health", 1)) * 1.2
	for k in d.get("keywords", []):
		match k:
			"TAUNT": value += 1.4
			"DIVINE_SHIELD": value += 2.2
			"WINDFURY": value += float(d.get("attack", 0)) * 0.75
			"LIFESTEAL": value += 1.0
			"CHARGE": value += float(d.get("attack", 0)) * 0.6
			"CANNOT_ATTACK": value -= 2.0
	value += float(d.get("spell_damage", 0)) * 2.0
	return maxf(0.5, value)


func _score_attack(attacker: CardInstance, target_id: int) -> float:
	var enemy: PlayerState = state.players[1 - player]
	if Enums.is_hero(target_id):
		var dmg := attacker.current_attack()
		var score := dmg * 1.0
		if dmg >= enemy.hp + enemy.armor:
			score += 6.0
		if attacker.has_keyword("LIFESTEAL"):
			score += dmg * 0.3
		return score
	var target = state._find_minion(target_id)
	if target == null:
		return 0.0
	var atk := attacker.current_attack()
	var kills: bool = atk >= target.health
	if target.has_keyword("DIVINE_SHIELD") and not target.has_keyword("TAUNT"):
		kills = false
	var dies := false
	if not attacker.has_keyword("DIVINE_SHIELD"):
		dies = target.current_attack() >= attacker.health
	var score := 0.0
	if kills:
		score += _minion_value(target) + 1.0
	else:
		score += mini(atk, target.health) * 0.75
	if dies:
		score -= _minion_value(attacker) * 0.9
	if target.has_keyword("TAUNT"):
		score += 0.8
	if attacker.has_keyword("LIFESTEAL") and target.owner != player:
		score += mini(atk, target.health) * 0.25
	return score


func _score_hero_power(target_id: int) -> float:
	var hp: Dictionary = state.players[player].hero_power
	var score := 0.0
	var card_def := hp.duplicate()
	card_def["type"] = "HERO_POWER"
	for e in hp.get("effects", []):
		for a in e.get("actions", []):
			score += _score_action(a, CardInstance.new(), target_id)
	# 英雄技能费用 2 的基准折价
	return score - 1.0
