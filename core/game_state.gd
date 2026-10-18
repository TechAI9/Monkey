class_name GameState
extends RefCounted
## 核心规则引擎：纯数据，不依赖场景树。
## 所有对外操作都返回 bool，并把发生的事写入 events 供 UI 播放动画。

const HAND_LIMIT := 10
const BOARD_LIMIT := 7
const MAX_MANA := 10

var players: Array = []
var current: int = 0
var turn: int = 0
var phase: String = "idle"
var winner: int = -1
var events: Array = []
var rng := RandomNumberGenerator.new()

var _next_id: int = 1
var _first_player: int = 0
var _mulligan_done: Array = [false, false]
var _started: bool = false


# ------------------------------------------------------------------ setup
## setup：deck_a / deck_b 为 30 张 card_id 列表；留空则用英雄预设卡组。
func setup(hero_a: Dictionary, hero_b: Dictionary, seed_value: int = 0,
		deck_a: Array = [], deck_b: Array = []) -> void:
	CardDB.ensure_loaded()
	rng.seed = seed_value
	players = [_new_player(0, hero_a), _new_player(1, hero_b)]
	_first_player = 0
	current = _first_player
	turn = 0
	phase = "idle"
	winner = -1
	events.clear()
	_next_id = 1
	_mulligan_done = [false, false]
	_started = false
	_build_deck(players[0], deck_a)
	_build_deck(players[1], deck_b)
	for p in players:
		_shuffle(p.deck)


func _new_player(index: int, hero_def: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.index = index
	p.hero_class = hero_def.get("id", "NEUTRAL")
	p.hero_name = hero_def.get("name", "")
	p.portrait = hero_def.get("portrait", "")
	p.max_hp = int(hero_def.get("hp", 30))
	p.hp = p.max_hp
	p.hero_power = hero_def.get("hero_power", {})
	p.deck = []
	p.hand = []
	p.board = []
	p.graveyard = []
	return p


func _build_deck(p: PlayerState, override: Array = []) -> void:
	var ids: Array = []
	if override.size() > 0:
		ids = override
	else:
		for h in CardDB.heroes():
			if h.get("id") == p.hero_class:
				ids = h.get("deck", [])
				break
	for card_id in ids:
		if CardDB.exists(str(card_id)):
			p.deck.append(_new_instance(str(card_id), p.index))


func _new_instance(card_id: String, owner: int) -> CardInstance:
	var inst := CardInstance.new()
	inst.setup(_next_id, card_id, owner)
	_next_id += 1
	return inst


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func start_game() -> void:
	_started = true
	phase = Enums.PHASE_MULLIGAN
	events.append({"type": "game_start"})
	draw_cards(_first_player, 3)
	draw_cards(1 - _first_player, 4)


func is_mulligan_done(player: int) -> bool:
	return _mulligan_done[player]


func mulligan(player: int, indices: Array) -> void:
	if phase != Enums.PHASE_MULLIGAN or _mulligan_done[player]:
		return
	var p: PlayerState = players[player]
	var sorted := indices.duplicate()
	sorted.sort()
	sorted.reverse()
	var replaced := 0
	for idx in sorted:
		if idx < 0 or idx >= p.hand.size():
			continue
		var inst: CardInstance = p.hand[idx]
		p.hand.remove_at(idx)
		inst.zone = Enums.ZONE_DECK
		p.deck.append(inst)
		replaced += 1
	_shuffle(p.deck)
	events.append({"type": "mulligan", "player": player, "count": replaced})
	draw_cards(player, replaced)
	_mulligan_done[player] = true
	if _mulligan_done[0] and _mulligan_done[1]:
		_finish_mulligan()


func _finish_mulligan() -> void:
	var second := 1 - _first_player
	_add_card_to_hand(second, "GAME_005")
	phase = Enums.PHASE_PLAYING
	begin_turn(_first_player)


func take_events() -> Array:
	var out := events.duplicate()
	events.clear()
	return out


# ------------------------------------------------------------------ turns
func begin_turn(player: int) -> void:
	if phase == Enums.PHASE_OVER:
		return
	current = player
	turn += 1
	var p: PlayerState = players[player]
	p.max_mana = mini(MAX_MANA, p.max_mana + 1)
	p.mana = p.max_mana
	p.hero_power_used = false
	for m in p.board:
		m.attacks_used = 0
	events.append({"type": "turn_start", "player": player, "turn": turn})
	draw_cards(player, 1)
	_run_triggers(player, "start_of_turn")
	_process_deaths()
	_check_game_over()


func end_turn() -> void:
	if phase != Enums.PHASE_PLAYING:
		return
	events.append({"type": "turn_end", "player": current})
	_run_triggers(current, "end_of_turn")
	var p: PlayerState = players[current]
	for m in p.board:
		if m.has_temp_buffs():
			m.revert_temp_buffs()
			events.append({"type": "stats", "target": m.instance_id,
				"attack": m.current_attack(), "health": m.health})
		if m.frozen:
			m.frozen = false
			events.append({"type": "thaw", "target": m.instance_id})
	_process_deaths()
	if phase == Enums.PHASE_OVER:
		return
	begin_turn(1 - current)


# ------------------------------------------------------------------ draw / mana
func draw_cards(player: int, count: int) -> void:
	for _i in count:
		_draw_one(player)


func _draw_one(player: int) -> void:
	var p: PlayerState = players[player]
	if p.deck.is_empty():
		p.fatigue += 1
		events.append({"type": "fatigue", "player": player, "amount": p.fatigue})
		_deal_damage(Enums.hero_id(player), p.fatigue, null)
		_check_game_over()
		return
	var inst: CardInstance = p.deck.pop_back()
	if p.hand.size() >= HAND_LIMIT:
		inst.zone = Enums.ZONE_GRAVE
		p.graveyard.append(inst)
		events.append({"type": "burn", "player": player, "card_id": inst.card_id})
		return
	inst.zone = Enums.ZONE_HAND
	p.hand.append(inst)
	events.append({"type": "draw", "player": player, "card": inst.instance_id,
		"card_id": inst.card_id, "index": p.hand.size() - 1})


func _add_card_to_hand(player: int, card_id: String) -> void:
	var p: PlayerState = players[player]
	var inst := _new_instance(card_id, player)
	if p.hand.size() >= HAND_LIMIT:
		inst.zone = Enums.ZONE_GRAVE
		p.graveyard.append(inst)
		events.append({"type": "burn", "player": player, "card_id": card_id})
		return
	inst.zone = Enums.ZONE_HAND
	p.hand.append(inst)
	events.append({"type": "add_card", "player": player, "card": inst.instance_id,
		"card_id": card_id, "index": p.hand.size() - 1})


func get_card_cost(inst: CardInstance, player: int) -> int:
	var cost := inst.cost()
	if inst.card_type() == "SPELL":
		var reduction := 0
		for m in players[player].board:
			if m.has_keyword("SPELL_COST_REDUCE"):
				reduction += m.cost_reduce
		cost = maxi(0, cost - reduction)
	return cost


# ------------------------------------------------------------------ play card
func get_target_spec(card_def: Dictionary) -> Dictionary:
	for e in card_def.get("effects", []):
		if e.has("target"):
			return {"target": e["target"], "filter": e.get("filter", {})}
	return {}


func hand_card(player: int, hand_index: int) -> CardInstance:
	var p: PlayerState = players[player]
	if hand_index < 0 or hand_index >= p.hand.size():
		return null
	return p.hand[hand_index]


func get_valid_targets(hand_index: int, player: int) -> Array:
	var inst := hand_card(player, hand_index)
	if inst == null:
		return []
	var spec := get_target_spec(inst.def())
	if spec.is_empty():
		return []
	return _target_ids(spec["target"], spec.get("filter", {}), null, player)


func can_play_card(hand_index: int, target_id: int = 0, position: int = -1) -> Dictionary:
	if phase != Enums.PHASE_PLAYING:
		return {"ok": false, "reason": "对局尚未开始"}
	if current < 0:
		return {"ok": false, "reason": "无效回合"}
	var inst := hand_card(current, hand_index)
	if inst == null:
		return {"ok": false, "reason": "无效的卡牌"}
	var p: PlayerState = players[current]
	var cost := get_card_cost(inst, current)
	if p.mana < cost:
		return {"ok": false, "reason": "法力值不足", "needs_target": false}
	if inst.card_type() == "MINION" and p.board.size() >= BOARD_LIMIT:
		return {"ok": false, "reason": "战场已满", "needs_target": false}
	var spec := get_target_spec(inst.def())
	var needs_target := false
	if not spec.is_empty():
		var targets := _target_ids(spec["target"], spec.get("filter", {}), null, current)
		if not targets.is_empty():
			needs_target = true
			if target_id == 0:
				return {"ok": false, "reason": "需要选择目标", "needs_target": true,
					"targets": targets}
			if not targets.has(target_id):
				return {"ok": false, "reason": "目标不合法", "needs_target": true,
					"targets": targets}
		elif inst.card_type() == "SPELL":
			return {"ok": false, "reason": "没有合法目标", "needs_target": false}
	return {"ok": true, "reason": "", "needs_target": needs_target,
		"cost": cost}


func play_card(hand_index: int, target_id: int = 0, position: int = -1) -> bool:
	var check := can_play_card(hand_index, target_id, position)
	if not check.get("ok", false):
		return false
	var p: PlayerState = players[current]
	var inst: CardInstance = p.hand[hand_index]
	var cost: int = check.get("cost", 0)
	p.mana -= cost
	p.hand.remove_at(hand_index)
	events.append({"type": "play_card", "player": current,
		"card": inst.instance_id, "card_id": inst.card_id, "cost": cost,
		"target": target_id})
	if inst.card_type() == "MINION":
		var pos := position
		if pos < 0 or pos > p.board.size():
			pos = p.board.size()
		inst.zone = Enums.ZONE_BOARD
		inst.summoned_turn = turn
		p.board.insert(pos, inst)
		events.append({"type": "summon", "player": current,
			"card": inst.instance_id, "card_id": inst.card_id, "index": pos})
		_trigger_on_summon(current, inst)
		_run_card_effects(inst, "battlecry", target_id, false)
	else:
		events.append({"type": "spell", "player": current,
			"card": inst.instance_id, "card_id": inst.card_id, "target": target_id})
		_run_card_effects(inst, "spell", target_id, true)
		_run_spell_cast_triggers(current)
		inst.zone = Enums.ZONE_GRAVE
		players[current].graveyard.append(inst)
	_process_deaths()
	_check_game_over()
	return true


func _trigger_on_summon(player: int, summoned: CardInstance) -> void:
	for m in players[player].board.duplicate():
		if m == summoned:
			continue
		_run_card_effects(m, "on_summon", 0, false)


func _run_spell_cast_triggers(player: int) -> void:
	for m in players[player].board.duplicate():
		_run_card_effects(m, "on_spell_cast", 0, false)


func _run_triggers(player: int, trigger: String) -> void:
	for m in players[player].board.duplicate():
		_run_card_effects(m, trigger, 0, false)


func _run_card_effects(inst: CardInstance, trigger: String, chosen: int, is_spell: bool) -> void:
	for e in inst.def().get("effects", []):
		if e.get("trigger") == trigger:
			_run_effect(e, inst, inst.owner, chosen, is_spell)


# ------------------------------------------------------------------ hero power
func can_use_hero_power(player: int = -1, target_id: int = 0) -> Dictionary:
	if player < 0:
		player = current
	if phase != Enums.PHASE_PLAYING or player != current:
		return {"ok": false, "reason": "现在不是你的回合"}
	var p: PlayerState = players[player]
	if p.hero_power_used:
		return {"ok": false, "reason": "本回合已经使用过英雄技能"}
	var hp: Dictionary = p.hero_power
	var cost := int(hp.get("cost", 2))
	if p.mana < cost:
		return {"ok": false, "reason": "法力值不足"}
	var spec := get_target_spec(hp)
	var needs_target := false
	if not spec.is_empty():
		var targets := _target_ids(spec["target"], spec.get("filter", {}), null, player)
		if not targets.is_empty():
			needs_target = true
			if target_id == 0:
				return {"ok": false, "reason": "需要选择目标", "needs_target": true,
					"targets": targets}
			if not targets.has(target_id):
				return {"ok": false, "reason": "目标不合法", "needs_target": true}
	return {"ok": true, "reason": "", "needs_target": needs_target, "cost": cost}


func use_hero_power(target_id: int = 0) -> bool:
	var check := can_use_hero_power(current, target_id)
	if not check.get("ok", false):
		return false
	var p: PlayerState = players[current]
	p.mana -= int(check.get("cost", 0))
	p.hero_power_used = true
	events.append({"type": "hero_power", "player": current,
		"power": p.hero_power.get("id", ""), "target": target_id})
	for e in p.hero_power.get("effects", []):
		_run_effect(e, null, current, target_id, false)
	_process_deaths()
	_check_game_over()
	return true


func get_hero_power_targets(player: int = -1) -> Array:
	if player < 0:
		player = current
	var hp: Dictionary = players[player].hero_power
	var spec := get_target_spec(hp)
	if spec.is_empty():
		return []
	return _target_ids(spec["target"], spec.get("filter", {}), null, player)


# ------------------------------------------------------------------ combat
func get_valid_attack_targets(attacker_id: int) -> Array:
	var attacker = _find_minion(attacker_id)
	if attacker == null or not attacker.can_attack(turn):
		return []
	var enemy: PlayerState = players[1 - attacker.owner]
	var taunts: Array = []
	for m in enemy.board:
		if m.has_keyword("TAUNT"):
			taunts.append(m.instance_id)
	if not taunts.is_empty():
		return taunts
	var out: Array = []
	for m in enemy.board:
		out.append(m.instance_id)
	out.append(enemy.hero_id())
	return out


func can_attack(attacker_id: int, target_id: int) -> bool:
	return get_valid_attack_targets(attacker_id).has(target_id)


func attack(attacker_id: int, target_id: int) -> bool:
	if phase != Enums.PHASE_PLAYING:
		return false
	var attacker = _find_minion(attacker_id)
	if attacker == null or attacker.owner != current:
		return false
	if not can_attack(attacker_id, target_id):
		return false
	var target = _find_minion(target_id)
	var dmg_to_target := attacker.current_attack()
	var dmg_to_attacker := 0
	if target != null:
		dmg_to_attacker = target.current_attack()
	events.append({"type": "attack", "attacker": attacker_id, "target": target_id})
	_deal_damage(target_id, dmg_to_target, attacker)
	if target != null:
		_deal_damage(attacker_id, dmg_to_attacker, target)
	attacker.attacks_used += 1
	_process_deaths()
	_check_game_over()
	return true


# ------------------------------------------------------------------ effects
func _run_effect(e: Dictionary, source: CardInstance, owner: int, chosen: int,
		is_spell: bool) -> void:
	var ctx := {
		"source": source,
		"owner": owner,
		"chosen": chosen,
		"spell": is_spell,
	}
	for a in e.get("actions", []):
		if not _condition_met(a.get("if", {}), ctx):
			continue
		_execute(a, ctx)


func _condition_met(cond: Dictionary, ctx: Dictionary) -> bool:
	if cond.is_empty():
		return true
	if cond.has("target_alive"):
		var want := bool(cond["target_alive"])
		return _is_alive(ctx["chosen"]) == want
	if cond.has("hero_hp_lte"):
		return int(players[ctx["owner"]].hp) <= int(cond["hero_hp_lte"])
	return true


func _execute(a: Dictionary, ctx: Dictionary) -> void:
	if phase == Enums.PHASE_OVER:
		return
	var kind: String = a.get("do", "")
	var owner: int = ctx["owner"]
	var spell_bonus: int = players[owner].spell_power() if ctx["spell"] else 0

	match kind:
		"damage":
			var amount := _amount_of(a, ctx, spell_bonus)
			for target in _select(a.get("to", "chosen"), ctx):
				_deal_damage(target, amount, ctx["source"])
		"heal":
			for target in _select(a.get("to", "chosen"), ctx):
				_heal(target, int(a.get("amount", 0)))
		"buff":
			var temp: bool = a.get("duration", "permanent") == "turn"
			for target in _select(a.get("to", "chosen"), ctx):
				var m = _find_minion(target)
				if m != null:
					m.add_buff(int(a.get("atk", 0)), int(a.get("hp", 0)), temp)
					events.append({"type": "stats", "target": m.instance_id,
						"attack": m.current_attack(), "health": m.health,
						"buffed": true})
		"give_keyword":
			for target in _select(a.get("to", "chosen"), ctx):
				var m = _find_minion(target)
				if m != null:
					m.add_keyword(a.get("keyword", ""))
					events.append({"type": "stats", "target": m.instance_id,
						"attack": m.current_attack(), "health": m.health})
		"set_attack":
			for target in _select(a.get("to", "chosen"), ctx):
				var m = _find_minion(target)
				if m != null:
					m.attack = int(a.get("value", 0))
					events.append({"type": "stats", "target": m.instance_id,
						"attack": m.current_attack(), "health": m.health})
		"set_health":
			for target in _select(a.get("to", "chosen"), ctx):
				var m = _find_minion(target)
				if m != null:
					m.health = mini(int(a.get("value", 1)), m.max_health)
					if m.health <= 0:
						m.dead = true
					events.append({"type": "stats", "target": m.instance_id,
						"attack": m.current_attack(), "health": m.health})
		"destroy":
			for target in _select(a.get("to", "chosen"), ctx):
				var m = _find_minion(target)
				if m != null:
					m.dead = true
					m.health = 0
		"freeze":
			for target in _select(a.get("to", "chosen"), ctx):
				_freeze(target)
		"draw":
			var who: String = a.get("who", "owner")
			if who == "owner":
				draw_cards(owner, int(a.get("count", 1)))
			elif who == "opponent":
				draw_cards(1 - owner, int(a.get("count", 1)))
			else:
				draw_cards(0, int(a.get("count", 1)))
				draw_cards(1, int(a.get("count", 1)))
		"summon":
			var who2: String = a.get("who", "owner")
			var target_player := owner if who2 == "owner" else 1 - owner
			for _i in int(a.get("count", 1)):
				_summon_token(target_player, a.get("card", ""), ctx["source"])
		"summon_until_full":
			var who3: String = a.get("who", "owner")
			var target_player2 := owner if who3 == "owner" else 1 - owner
			var guard := 0
			while players[target_player2].board.size() < BOARD_LIMIT and guard < 10:
				_summon_token(target_player2, a.get("card", ""), ctx["source"])
				guard += 1
		"armor":
			var who4: String = a.get("who", "owner")
			var target_player3 := owner if who4 == "owner" else 1 - owner
			players[target_player3].armor += int(a.get("amount", 0))
			events.append({"type": "armor", "player": target_player3,
				"amount": int(a.get("amount", 0))})
		"random_damage":
			_random_damage(a, ctx, spell_bonus)
		"damage_all":
			var amount_all := _amount_of(a, ctx, spell_bonus)
			for target in _select(a.get("pool", "all_minions"), ctx):
				_deal_damage(target, amount_all, ctx["source"])
		"discard_hand":
			var who5: String = a.get("who", "owner")
			var target_player4 := owner if who5 == "owner" else 1 - owner
			var p: PlayerState = players[target_player4]
			var n := p.hand.size()
			for inst in p.hand:
				inst.zone = Enums.ZONE_GRAVE
				p.graveyard.append(inst)
			p.hand.clear()
			events.append({"type": "discard", "player": target_player4, "count": n})
		"transform":
			for target in _select(a.get("to", "chosen"), ctx):
				_transform(target, a.get("into", ""))
		"set_hero_health":
			for target in _select(a.get("to", "chosen"), ctx):
				if Enums.is_hero(target):
					var p2: PlayerState = players[Enums.hero_owner(target)]
					p2.hp = int(a.get("value", p2.hp))
					events.append({"type": "hero_health", "player": p2.index,
						"hp": p2.hp, "armor": p2.armor})
		"gain_mana":
			players[owner].mana += int(a.get("amount", 1))
			events.append({"type": "mana", "player": owner, "mana": players[owner].mana})
		"draw_per_damaged_friendly":
			var p3: PlayerState = players[owner]
			var count := 0
			if p3.hp < p3.max_hp:
				count += 1
			for m in p3.board:
				if m.is_damaged():
					count += 1
			draw_cards(owner, count)
		"add_card":
			var who6: String = a.get("who", "owner")
			var target_player5 := owner if who6 == "owner" else 1 - owner
			_add_card_to_hand(target_player5, a.get("card", ""))
		"double_attack":
			for target in _select(a.get("to", "chosen"), ctx):
				var m2 = _find_minion(target)
				if m2 != null:
					m2.attack *= 2
					events.append({"type": "stats", "target": m2.instance_id,
						"attack": m2.current_attack(), "health": m2.health, "buffed": true})
		_:
			push_warning("未实现的效果: %s" % kind)


func _amount_of(a: Dictionary, ctx: Dictionary, spell_bonus: int) -> int:
	var amount := int(a.get("amount", 0))
	if a.has("amount_from"):
		if a["amount_from"] == "armor":
			amount = int(players[ctx["owner"]].armor)
	if a.has("bonus_if"):
		if _condition_met(a["bonus_if"], ctx):
			amount += int(a["bonus_if"].get("bonus", 0))
	return amount + spell_bonus


func _random_damage(a: Dictionary, ctx: Dictionary, spell_bonus: int) -> void:
	var count := int(a.get("count", 1))
	var amount := int(a.get("amount", 1))
	if a.get("grow_count", false):
		count += spell_bonus
	else:
		amount += spell_bonus
	var pool := _select(a.get("pool", "enemy_characters"), ctx)
	if pool.is_empty():
		return
	if a.get("distinct", false):
		_shuffle(pool)
		for i in mini(count, pool.size()):
			_deal_damage(pool[i], amount, ctx["source"])
	else:
		for _i in count:
			var alive := _alive_only(pool)
			if alive.is_empty():
				return
			var pick = alive[rng.randi_range(0, alive.size() - 1)]
			_deal_damage(pick, amount, ctx["source"])


# ------------------------------------------------------------------ targeting
func _target_ids(spec: String, filter: Dictionary, source: CardInstance,
		player: int) -> Array:
	var enemies: PlayerState = players[1 - player]
	var self_side: PlayerState = players[player]
	var candidates: Array = []
	match spec:
		"any":
			candidates.append(self_side.hero_id())
			candidates.append(enemies.hero_id())
			for m in self_side.board:
				candidates.append(m.instance_id)
			for m in enemies.board:
				candidates.append(m.instance_id)
		"any_minion":
			for m in self_side.board:
				candidates.append(m.instance_id)
			for m in enemies.board:
				candidates.append(m.instance_id)
		"any_hero":
			candidates.append(self_side.hero_id())
			candidates.append(enemies.hero_id())
		"enemy_minion":
			for m in enemies.board:
				candidates.append(m.instance_id)
		"enemy_character":
			candidates.append(enemies.hero_id())
			for m in enemies.board:
				candidates.append(m.instance_id)
		"friendly_minion":
			for m in self_side.board:
				candidates.append(m.instance_id)
		"friendly_other_minion":
			for m in self_side.board:
				if source == null or m.instance_id != source.instance_id:
					candidates.append(m.instance_id)
		_:
			push_warning("未知目标类型: %s" % spec)
	var out: Array = []
	for cid in candidates:
		if _matches_filter(cid, filter):
			out.append(cid)
	return out


func _matches_filter(target_id: int, filter: Dictionary) -> bool:
	if filter.is_empty():
		return _is_alive(target_id)
	if not _is_alive(target_id):
		return false
	var m = _find_minion(target_id)
	for key in filter.keys():
		var value = filter[key]
		match key:
			"damaged":
				if m != null:
					if m.is_damaged() != bool(value):
						return false
				elif Enums.is_hero(target_id):
					var p: PlayerState = players[Enums.hero_owner(target_id)]
					if (p.hp < p.max_hp) != bool(value):
						return false
			"attack_lte":
				if m == null or m.current_attack() > int(value):
					return false
			"attack_gte":
				if m == null or m.current_attack() < int(value):
					return false
			"keyword":
				if m == null or not m.has_keyword(str(value)):
					return false
			"minion":
				if m == null:
					return false
	return true


func _select(selector: String, ctx: Dictionary) -> Array:
	var owner: int = ctx["owner"]
	var me: PlayerState = players[owner]
	var enemy: PlayerState = players[1 - owner]
	var source: CardInstance = ctx["source"]
	var out: Array = []
	match selector:
		"chosen":
			if _is_alive(ctx["chosen"]):
				out.append(ctx["chosen"])
		"self":
			if source != null and _is_alive(source.instance_id):
				out.append(source.instance_id)
		"owner_hero":
			out.append(me.hero_id())
		"enemy_hero":
			out.append(enemy.hero_id())
		"all_minions":
			for p in players:
				for m in p.board:
					out.append(m.instance_id)
		"all_enemy_minions":
			for m in enemy.board:
				out.append(m.instance_id)
		"enemy_minions":
			for m in enemy.board:
				out.append(m.instance_id)
		"friendly_minions":
			for m in me.board:
				out.append(m.instance_id)
		"all_friendly_minions":
			for m in me.board:
				out.append(m.instance_id)
		"all_other_minions":
			for p in players:
				for m in p.board:
					if source == null or m.instance_id != source.instance_id:
						out.append(m.instance_id)
		"all_enemy_characters":
			out.append(enemy.hero_id())
			for m in enemy.board:
				out.append(m.instance_id)
		"enemy_characters":
			out.append(enemy.hero_id())
			for m in enemy.board:
				out.append(m.instance_id)
		"friendly_characters":
			out.append(me.hero_id())
			for m in me.board:
				out.append(m.instance_id)
		"all_characters":
			for p in players:
				out.append(p.hero_id())
				for m in p.board:
					out.append(m.instance_id)
		"all_other_characters":
			for p in players:
				if source == null or p.hero_id() != source.instance_id:
					out.append(p.hero_id())
				for m in p.board:
					if source == null or m.instance_id != source.instance_id:
						out.append(m.instance_id)
		"other_characters":
			for p in players:
				if source == null or p.hero_id() != source.instance_id:
					out.append(p.hero_id())
				for m in p.board:
					if source == null or m.instance_id != source.instance_id:
						out.append(m.instance_id)
		"random_enemy_minion":
			out.append_array(_random_of(_minion_ids(enemy.board)))
		"random_enemy_character":
			out.append_array(_random_of(_character_ids(enemy)))
		"random_friendly_minion":
			out.append_array(_random_of(_minion_ids(me.board)))
		"random_friendly_other_minion":
			var ids := _minion_ids(me.board)
			if source != null:
				ids.erase(source.instance_id)
			out.append_array(_random_of(ids))
		_:
			push_warning("未知选择器: %s" % selector)
	return _alive_only(out)


func _minion_ids(board: Array) -> Array:
	var ids: Array = []
	for m in board:
		ids.append(m.instance_id)
	return ids


func _character_ids(p: PlayerState) -> Array:
	var ids: Array = [p.hero_id()]
	ids.append_array(_minion_ids(p.board))
	return ids


func _random_of(ids: Array) -> Array:
	var alive := _alive_only(ids)
	if alive.is_empty():
		return []
	return [alive[rng.randi_range(0, alive.size() - 1)]]


func _alive_only(ids: Array) -> Array:
	var out: Array = []
	for cid in ids:
		if _is_alive(cid):
			out.append(cid)
	return out


# ------------------------------------------------------------------ damage / heal
func _deal_damage(target_id: int, amount: int, source: CardInstance) -> int:
	if amount <= 0 or phase == Enums.PHASE_OVER:
		return 0
	var dealt := 0
	if Enums.is_hero(target_id):
		var p: PlayerState = players[Enums.hero_owner(target_id)]
		if p.hp <= 0:
			return 0
		var absorbed := mini(p.armor, amount)
		p.armor -= absorbed
		var to_hp := amount - absorbed
		p.hp -= to_hp
		dealt = to_hp
		events.append({"type": "damage", "target": target_id, "amount": amount,
			"dealt": to_hp, "absorbed": absorbed, "hp": p.hp, "armor": p.armor})
		if source != null and source.has_keyword("FREEZE_ON_DAMAGE"):
			_freeze(target_id)
		_check_game_over()
	else:
		var m = _find_minion(target_id)
		if m == null or m.dead:
			return 0
		if m.has_keyword("DIVINE_SHIELD"):
			m.keywords.erase("DIVINE_SHIELD")
			events.append({"type": "shield", "target": target_id})
			events.append({"type": "damage", "target": target_id, "amount": 0,
				"dealt": 0, "blocked": true, "hp": m.health, "armor": 0})
			return 0
		var before: int = m.health
		m.health -= amount
		dealt = mini(amount, before)
		events.append({"type": "damage", "target": target_id, "amount": amount,
			"dealt": dealt, "absorbed": 0, "hp": m.health, "armor": 0})
		if m.health <= 0:
			m.dead = true
		_after_minion_damaged(m, source)
		if source != null and source.has_keyword("FREEZE_ON_DAMAGE"):
			_freeze(target_id)
	if source != null and source.has_keyword("LIFESTEAL") and dealt > 0:
		_heal(Enums.hero_id(source.owner), dealt)
	return dealt


func _after_minion_damaged(m: CardInstance, _source: CardInstance) -> void:
	# 受伤触发（顺序：自身 -> 友方 -> 任意随从）
	for e in m.def().get("effects", []):
		if e.get("trigger") == "on_self_damaged":
			_run_effect(e, m, m.owner, 0, false)
	var p: PlayerState = players[m.owner]
	for other in p.board.duplicate():
		for e in other.def().get("effects", []):
			if e.get("trigger") == "on_friendly_minion_damaged":
				_run_effect(e, other, other.owner, 0, false)
	for pl in players:
		for other in pl.board.duplicate():
			for e in other.def().get("effects", []):
				if e.get("trigger") == "on_any_minion_damaged":
					_run_effect(e, other, other.owner, 0, false)


func _heal(target_id: int, amount: int) -> void:
	if amount <= 0:
		return
	if Enums.is_hero(target_id):
		var p: PlayerState = players[Enums.hero_owner(target_id)]
		if p.hp <= 0:
			return
		var before := p.hp
		p.hp = mini(p.max_hp, p.hp + amount)
		events.append({"type": "heal", "target": target_id, "amount": p.hp - before,
			"hp": p.hp})
	else:
		var m = _find_minion(target_id)
		if m == null or m.dead:
			return
		var before2: int = m.health
		m.health = mini(m.max_health, m.health + amount)
		events.append({"type": "heal", "target": target_id, "amount": m.health - before2,
			"hp": m.health})
		events.append({"type": "stats", "target": m.instance_id,
			"attack": m.current_attack(), "health": m.health})


func _freeze(target_id: int) -> void:
	if Enums.is_hero(target_id):
		var p: PlayerState = players[Enums.hero_owner(target_id)]
		p.frozen = true
		events.append({"type": "freeze", "target": target_id})
		return
	var m = _find_minion(target_id)
	if m != null and not m.frozen:
		m.frozen = true
		events.append({"type": "freeze", "target": target_id})


func _transform(target_id: int, into: String) -> void:
	var m = _find_minion(target_id)
	if m == null:
		return
	var p: PlayerState = players[m.owner]
	var idx := p.board.find(m)
	if idx < 0:
		return
	var new_inst := _new_instance(into, m.owner)
	new_inst.zone = Enums.ZONE_BOARD
	new_inst.summoned_turn = turn
	p.board[idx] = new_inst
	m.zone = Enums.ZONE_GRAVE
	p.graveyard.append(m)
	events.append({"type": "transform", "old": m.instance_id,
		"card": new_inst.instance_id, "card_id": into, "index": idx})


func _summon_token(player: int, card_id: String, _source: CardInstance) -> void:
	var p: PlayerState = players[player]
	if p.board.size() >= BOARD_LIMIT or card_id == "":
		return
	var inst := _new_instance(card_id, player)
	inst.zone = Enums.ZONE_BOARD
	inst.summoned_turn = turn
	p.board.append(inst)
	events.append({"type": "summon", "player": player, "card": inst.instance_id,
		"card_id": card_id, "index": p.board.size() - 1})
	_trigger_on_summon(player, inst)


# ------------------------------------------------------------------ deaths / win
func _process_deaths() -> void:
	if phase == Enums.PHASE_OVER:
		return
	var guard := 0
	while guard < 64:
		guard += 1
		var dead_list: Array = []
		for p in players:
			for m in p.board:
				if m.dead or m.health <= 0:
					dead_list.append(m)
		if dead_list.is_empty():
			return
		for m in dead_list:
			var p: PlayerState = players[m.owner]
			if not p.board.has(m):
				continue
			var index := p.board.find(m)
			p.board.erase(m)
			m.dead = true
			m.zone = Enums.ZONE_GRAVE
			p.graveyard.append(m)
			events.append({"type": "death", "player": m.owner, "target": m.instance_id,
				"card_id": m.card_id, "index": index})
			_run_card_effects(m, "deathrattle", 0, false)
			_trigger_friendly_death(m)
		_check_game_over()
	_check_game_over()


func _trigger_friendly_death(dead: CardInstance) -> void:
	for m in players[dead.owner].board.duplicate():
		for e in m.def().get("effects", []):
			if e.get("trigger") == "on_friendly_death":
				_run_effect(e, m, m.owner, 0, false)


func _find_minion(instance_id: int) -> CardInstance:
	if instance_id <= 0:
		return null
	for p in players:
		for m in p.board:
			if m.instance_id == instance_id:
				return m
	return null


func _is_alive(target_id: int) -> bool:
	if Enums.is_hero(target_id):
		return players[Enums.hero_owner(target_id)].hp > 0
	var m = _find_minion(target_id)
	return m != null and not m.dead and m.health > 0


func _check_game_over() -> void:
	if phase == Enums.PHASE_OVER:
		return
	var dead_players: Array = []
	for p in players:
		if p.hp <= 0:
			dead_players.append(p.index)
	if dead_players.is_empty():
		return
	phase = Enums.PHASE_OVER
	if dead_players.size() >= 2:
		winner = -1
	else:
		winner = 1 - int(dead_players[0])
	events.append({"type": "game_over", "winner": winner})
