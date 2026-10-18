extends SceneTree
## 无头测试：godot --headless --path src --script res://tests/run_tests.gd
## 覆盖：数据完整性、规则判定、全部卡牌冒烟、AI 自对弈。

var _passed := 0
var _failed := 0
var _fail_names: Array = []
var _uid := 90000


func _initialize() -> void:
	print("=== 炉火牌局 规则测试 ===")
	_test_data()
	_test_opening()
	_test_mana()
	_test_play_minion()
	_test_taunt()
	_test_divine_shield()
	_test_charge_and_sickness()
	_test_windfury()
	_test_spell_power_aoe()
	_test_deathrattle()
	_test_fatigue()
	_test_hero_power()
	_test_polymorph()
	_test_equality()
	_test_deck_rules()
	_test_custom_cards()
	_test_deathwing()
	_test_all_cards_smoke()
	_test_ai_selfplay()
	print("--------------------------------")
	print("通过 %d / %d" % [_passed, _passed + _failed])
	if _failed > 0:
		print("失败用例: ", _fail_names)
		quit(1)
	else:
		quit(0)


# ------------------------------------------------------------------ helpers
func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_fail_names.append(name)
		print("  FAIL: ", name)


func _new_game(first_class := "MAGE", second_class := "WARRIOR", seed_value := 7) -> GameState:
	var g := GameState.new()
	g.setup(CardDB.hero(first_class), CardDB.hero(second_class), seed_value)
	g.start_game()
	g.mulligan(0, [])
	g.mulligan(1, [])
	g.take_events()
	g.phase = Enums.PHASE_PLAYING
	g.current = 0
	return g


func _add_minion(g: GameState, player: int, card_id: String, attack := -1,
		health := -1) -> CardInstance:
	_uid += 1
	var m := CardInstance.new()
	m.setup(_uid, card_id, player)
	m.zone = Enums.ZONE_BOARD
	m.summoned_turn = -5
	if attack >= 0:
		m.attack = attack
	if health >= 0:
		m.health = health
	g.players[player].board.append(m)
	return m


func _give(g: GameState, player: int, card_id: String) -> CardInstance:
	_uid += 1
	var inst := CardInstance.new()
	inst.setup(_uid, card_id, player)
	inst.zone = Enums.ZONE_HAND
	g.players[player].hand.append(inst)
	return inst


func _damage(g: GameState, target_id: int, amount: int) -> void:
	g._deal_damage(target_id, amount, null)
	g._process_deaths()


# ------------------------------------------------------------------ tests
func _test_data() -> void:
	print("[数据]")
	var cards := CardDB.all_cards()
	_check(cards.size() == 100, "主卡数量为 100")
	var ids := {}
	for c in cards:
		ids[c["id"]] = true
	_check(ids.size() == 100, "卡牌 ID 唯一")
	var counts := {"NEUTRAL": 0, "MAGE": 0, "WARRIOR": 0, "PALADIN": 0}
	for c in cards:
		counts[c["class"]] = counts.get(c["class"], 0) + 1
	_check(counts["NEUTRAL"] == 55 and counts["MAGE"] == 15
		and counts["WARRIOR"] == 15 and counts["PALADIN"] == 15, "职业分布 55/15/15/15")
	_check(CardDB.heroes().size() == 3, "三个英雄")
	for h in CardDB.heroes():
		_check(h["deck"].size() == 30, "%s 卡组 30 张" % h["title"])
		var seen := {}
		for cid in h["deck"]:
			seen[cid] = seen.get(cid, 0) + 1
			_check(CardDB.exists(cid), "%s 卡组卡牌存在: %s" % [h["title"], cid])
		for cid in seen:
			_check(seen[cid] <= 2, "%s 单卡不超过 2 张: %s" % [h["title"], cid])
	var bad_art: Array = []
	for c in cards:
		if not ResourceLoader.exists(c["art"]):
			bad_art.append(c["id"])
	_check(bad_art.is_empty(), "全部卡图存在 %s" % [bad_art])


func _test_opening() -> void:
	print("[开局]")
	var g := _new_game()
	_check(g.players[0].hand.size() == 4, "先手 4 张手牌（3+抽1）")
	_check(g.players[1].hand.size() == 5, "后手 5 张（4+抽1+硬币）")
	_check(g.players[1].hand.any(func(c): return c.card_id == "GAME_005"), "后手拿到幸运币")
	_check(g.current == 0 and g.turn == 1, "先手第一回合")
	_check(g.players[0].max_mana == 1 and g.players[0].mana == 1, "第一回合法力 1")


func _test_mana() -> void:
	print("[回合与法力]")
	var g := _new_game()
	g.end_turn()
	_check(g.current == 1, "交给对手")
	_check(g.players[1].max_mana == 1, "对手第一回合法力 1")
	g.end_turn()
	_check(g.current == 0 and g.players[0].max_mana == 2, "第二轮法力 2")
	for i in 20:
		g.end_turn()
	_check(g.players[0].max_mana == 10, "法力上限 10")


func _test_play_minion() -> void:
	print("[出牌]")
	var g := _new_game()
	g.players[0].mana = 5
	var inst := _give(g, 0, "CS2_120")
	var ok := g.play_card(g.players[0].hand.size() - 1, 0, 0)
	_check(ok, "淡水鳄可以打出")
	_check(g.players[0].board.size() == 1, "随从进入战场")
	_check(g.players[0].mana == 3, "扣除 2 点法力")
	_check(not g.players[0].hand.has(inst), "离开手牌")
	g.players[0].mana = 0
	_give(g, 0, "CS2_120")
	_check(not g.play_card(g.players[0].hand.size() - 1), "法力不足无法打出")


func _test_taunt() -> void:
	print("[嘲讽]")
	var g := _new_game()
	var atk := _add_minion(g, 0, "CS2_124", 3, 1)
	_add_minion(g, 1, "CS2_125", 3, 3)  # 嘲讽
	g.current = 0
	g.turn = 9
	atk.summoned_turn = 1
	_check(not g.can_attack(atk.instance_id, g.players[1].hero_id()), "有嘲讽时不能打英雄")
	_check(g.get_valid_attack_targets(atk.instance_id).size() == 1, "只能攻击嘲讽随从")
	var taunt_id: int = g.players[1].board[0].instance_id
	_check(g.attack(atk.instance_id, taunt_id), "可以攻击嘲讽随从")


func _test_divine_shield() -> void:
	print("[圣盾]")
	var g := _new_game()
	var shielded := _add_minion(g, 1, "EX1_008", 1, 1)
	_damage(g, shielded.instance_id, 5)
	_check(shielded.health == 1, "圣盾免疫伤害")
	_check(not shielded.has_keyword("DIVINE_SHIELD"), "圣盾被消耗")
	_damage(g, shielded.instance_id, 1)
	_check(shielded.dead, "第二次伤害击杀")


func _test_charge_and_sickness() -> void:
	print("[冲锋/召唤失调]")
	var g := _new_game()
	var charge := _add_minion(g, 0, "CS2_124", 3, 1)
	var normal := _add_minion(g, 0, "CS2_120", 2, 3)
	charge.summoned_turn = g.turn
	normal.summoned_turn = g.turn
	_check(charge.can_attack(g.turn), "冲锋当回合可攻击")
	_check(not normal.can_attack(g.turn), "普通随从当回合不能攻击")


func _test_windfury() -> void:
	print("[风怒]")
	var g := _new_game()
	var m := _add_minion(g, 0, "CS2_169", 1, 5)
	g.turn = 9
	m.summoned_turn = 1
	var enemy := _add_minion(g, 1, "CS2_231", 1, 5)
	_check(g.attack(m.instance_id, enemy.instance_id), "风怒第一次攻击")
	_check(g.attack(m.instance_id, enemy.instance_id), "风怒第二次攻击")
	_check(not g.attack(m.instance_id, enemy.instance_id), "第三次被拒绝")


func _test_spell_power_aoe() -> void:
	print("[法术伤害]")
	var g := _new_game()
	_add_minion(g, 0, "CS2_142", 2, 2)  # 法术伤害 +1
	var victim := _add_minion(g, 1, "CS2_120", 2, 3)
	g.players[0].mana = 10
	_give(g, 0, "CS2_025")  # 魔爆术 1 伤
	var idx: int = g.players[0].hand.size() - 1
	_check(g.play_card(idx), "施放魔爆术")
	_check(victim.health == 1, "魔爆术造成 1+1 伤害")


func _test_deathrattle() -> void:
	print("[亡语]")
	var g := _new_game()
	var m := _add_minion(g, 1, "EX1_556", 2, 1)
	_damage(g, m.instance_id, 3)
	_check(g.players[1].board.size() == 1, "麦田傀儡亡语召唤衍生物")
	if g.players[1].board.size() == 1:
		_check(g.players[1].board[0].card_id == "skele21", "衍生物为损坏的傀儡")


func _test_fatigue() -> void:
	print("[疲劳]")
	var g := _new_game()
	g.players[0].deck.clear()
	var before: int = g.players[0].hp
	g.draw_cards(0, 1)
	_check(g.players[0].hp == before - 1, "空牌库抽牌受到 1 点疲劳伤害")


func _test_hero_power() -> void:
	print("[英雄技能]")
	var g := _new_game()
	g.players[0].mana = 10
	var before: int = g.players[1].hp
	_check(g.use_hero_power(g.players[1].hero_id()), "法师火焰冲击")
	_check(g.players[1].hp == before - 1, "造成 1 点伤害")
	_check(not g.use_hero_power(g.players[1].hero_id()), "每回合只能使用一次")
	_check(g.players[0].mana == 8, "消耗 2 点法力")


func _test_polymorph() -> void:
	print("[变形术]")
	var g := _new_game()
	var m := _add_minion(g, 1, "CS2_125", 3, 3)
	g.players[0].mana = 10
	_give(g, 0, "CS2_022")
	_check(g.play_card(g.players[0].hand.size() - 1, m.instance_id), "变形术施放")
	var new_m = g.players[1].board[0]
	_check(new_m.card_id == "CS2_tk1" and new_m.attack == 1 and new_m.health == 1, "变成 1/1 绵羊")


func _test_equality() -> void:
	print("[生而平等]")
	var g := _new_game()
	var a := _add_minion(g, 0, "CS2_200", 6, 7)
	var b := _add_minion(g, 1, "EX1_110", 5, 5)
	g.players[0].mana = 10
	_give(g, 0, "EX1_619")
	_check(g.play_card(g.players[0].hand.size() - 1), "施放生而平等")
	_check(a.health == 1 and b.health == 1, "所有随从生命变为 1")


func _test_deathwing() -> void:
	print("[死亡之翼]")
	var g := _new_game()
	_add_minion(g, 0, "CS2_120", 2, 3)
	_add_minion(g, 1, "CS2_125", 3, 3)
	g.players[0].mana = 10
	_give(g, 0, "NEW1_030")
	var hand_before: int = g.players[0].hand.size()
	_check(g.play_card(g.players[0].hand.size() - 1), "打出死亡之翼")
	_check(g.players[0].board.size() == 1 and g.players[0].board[0].card_id == "NEW1_030", "消灭其他随从")
	_check(g.players[0].hand.size() == 0, "弃掉手牌（原 %d 张）" % hand_before)


func _test_deck_rules() -> void:
	print("[卡组规则]")
	DeckStore.write_enabled = false
	DeckStore.reset_for_test()
	DeckStore.ensure_loaded()
	_check(DeckStore.count() == 3, "默认为三个职业各建一套卡组")

	var mage := DeckStore.decks_for_class("MAGE")
	_check(mage.size() == 1, "法师有一套默认卡组")
	var deck: Dictionary = mage[0]
	_check(deck["cards"].size() == 30, "默认卡组 30 张")
	_check(DeckStore.is_legal(deck), "默认法师卡组合法")

	# 满编后拒绝加入
	var full := {"hero_class": "MAGE", "cards": deck["cards"].duplicate()}
	_check(not bool(DeckStore.add_card(full, "CS2_029")["ok"]), "卡组已满时拒绝加入")

	# 职业限制
	var empty := {"hero_class": "MAGE", "cards": []}
	_check(not bool(DeckStore.add_card(empty, "CS2_114")["ok"]), "跨职业卡被拒绝")
	_check(bool(DeckStore.add_card(empty, "CS2_029")["ok"]), "本职业卡可以加入")
	empty["cards"] = []
	_check(bool(DeckStore.add_card(empty, "CS2_120")["ok"]), "中立卡可以加入")

	# 衍生牌不能进卡组
	var probe := {"hero_class": "MAGE", "cards": []}
	_check(not bool(DeckStore.add_card(probe, "GAME_005")["ok"]), "衍生牌不能加入卡组")

	# 同名上限：普通 2 张、传说 1 张
	var two := {"hero_class": "NEUTRAL", "cards": []}
	var added := 0
	for i in 3:
		if bool(DeckStore.add_card(two, "CS2_120")["ok"]):
			added += 1
	_check(added == 2, "同名单卡最多 2 张")
	var legend := {"hero_class": "NEUTRAL", "cards": []}
	var legend_added := 0
	for i in 2:
		if bool(DeckStore.add_card(legend, "EX1_012")["ok"]):
			legend_added += 1
	_check(legend_added == 1, "传说卡最多 1 张")

	# 移除与统计
	var removable := {"hero_class": "MAGE", "cards": ["CS2_029", "CS2_029"]}
	_check(DeckStore.remove_card(removable, "CS2_029"), "可以移除卡牌")
	_check(removable["cards"].size() == 1, "移除后只剩 1 张")

	var curve := DeckStore.curve(deck)
	var total := 0
	for v in curve:
		total += int(v)
	_check(total == 30, "费用曲线合计 30")
	var groups := DeckStore.grouped(deck)
	var grouped_total := 0
	for g in groups:
		grouped_total += int(g["count"])
	_check(grouped_total == 30, "分组统计合计 30")

	# 不完整卡组判为非法
	var bad := {"hero_class": "MAGE", "cards": ["CS2_029"]}
	_check(not DeckStore.is_legal(bad), "不足 30 张判为非法")

	# 自定义牌表能进对局
	var custom_deck: Array = []
	for i in 30:
		custom_deck.append("CS2_029" if i % 2 == 0 else "CS2_120")
	var g2 := GameState.new()
	g2.setup(CardDB.hero("MAGE"), CardDB.hero("WARRIOR"), 5, custom_deck)
	_check(g2.players[0].deck.size() == 30, "自定义牌表进入牌库")


func _test_custom_cards() -> void:
	print("[自定义卡牌]")
	CustomCards.write_enabled = false
	CustomCards.reset_for_test()

	var spec := CustomCards.blank_spec("")
	spec["name"] = "测试火球"
	spec["type"] = "SPELL"
	spec["class"] = "MAGE"
	spec["cost"] = 2
	spec["target_mode"] = "any"
	spec["effects"] = [{"trigger": "spell", "do": "damage", "amount": 5, "to": "chosen"}]
	var def := CustomCards.build(spec)
	_check(str(def["name"]) == "测试火球", "自定义卡名称")
	_check(int(def["cost"]) == 2, "自定义卡费用")
	_check(str(def["type"]) == "SPELL", "自定义卡类型")
	_check(def.get("effects", []).size() == 1, "自定义卡效果条目")
	_check(str(def["effects"][0].get("target", "")) == "any", "效果带目标范围")
	_check(str(def["text"]).contains("5点伤害"), "自动生成描述: %s" % str(def["text"]))
	_check(not def.has("attack"), "法术卡没有攻击力")

	var minion_spec := CustomCards.blank_spec("")
	minion_spec["name"] = "测试野猪"
	minion_spec["race"] = "BEAST"
	minion_spec["cost"] = 3
	minion_spec["attack"] = 4
	minion_spec["health"] = 2
	minion_spec["keywords"] = ["TAUNT"]
	minion_spec["effects"] = [{"trigger": "deathrattle", "do": "draw", "count": 1, "who": "owner"}]
	var mdef := CustomCards.build(minion_spec)
	_check(int(mdef["attack"]) == 4 and int(mdef["health"]) == 2, "随从身材")
	_check(str(mdef["race"]) == "BEAST", "随从种族")
	_check(mdef.get("keywords", []).has("TAUNT"), "随从关键字")
	_check(str(mdef["text"]).contains("亡语"), "亡语描述: %s" % str(mdef["text"]))

	# 注册进 CardDB 并实际对局
	def["id"] = "CUSTOM_TEST"
	CardDB.register_cards([def])
	_check(CardDB.exists("CUSTOM_TEST"), "自定义卡进入 CardDB")
	_check(CardDB.is_custom("CUSTOM_TEST"), "is_custom 为真")
	_check(CardDB.card("CUSTOM_TEST").get("name", "") == "测试火球", "按 id 取到自定义卡")

	var g := _new_game("MAGE", "WARRIOR", 11)
	var inst := _give(g, 0, "CUSTOM_TEST")
	g.players[0].mana = 10
	var hero_id: int = g.players[1].hero_id()
	var hp_before: int = g.players[1].hp
	var ok := g.play_card(g.players[0].hand.find(inst), hero_id)
	_check(ok, "自定义法术可以打出")
	_check(g.players[1].hp == hp_before - 5, "自定义法术造成 5 点伤害")
	CardDB.unregister_card("CUSTOM_TEST")
	_check(not CardDB.exists("CUSTOM_TEST"), "注销后从 CardDB 移除")

	# 覆盖官方卡后，数值生效
	var override := CardDB.original("CS2_029").duplicate(true)
	override["cost"] = 0
	CardDB.register_cards([override])
	_check(int(CardDB.card("CS2_029").get("cost", -1)) == 0, "覆盖官方卡后取到新数值")
	var seen := 0
	for c in CardDB.all_cards():
		if str(c["id"]) == "CS2_029":
			seen += 1
	_check(seen == 1, "all_cards 不出现重复 id")
	CardDB.unregister_card("CS2_029")
	_check(int(CardDB.card("CS2_029").get("cost", -1)) == 4, "撤销覆盖后恢复原值")


func _test_all_cards_smoke() -> void:
	print("[全部卡牌冒烟]")
	for c in CardDB.all_cards():
		var g := _new_game()
		var p: PlayerState = g.players[0]
		p.mana = 10
		p.max_mana = 10
		p.board.clear()
		g.players[1].board.clear()
		# 提供各类合法目标
		var enemy_taunt := _add_minion(g, 1, "CS2_121", 2, 1)  # 2/2 嘲讽，已受伤
		enemy_taunt.summoned_turn = -5
		_add_minion(g, 1, "CS2_125", 3, 3).summoned_turn = -5
		var friendly := _add_minion(g, 0, "CS2_120", 2, 2)
		friendly.summoned_turn = -5
		var inst := _give(g, 0, c["id"])
		var idx: int = p.hand.size() - 1
		if c["type"] == "MINION":
			p.board.erase(inst)
		var check := g.can_play_card(idx, 0)
		var target := 0
		if check.get("needs_target", false):
			target = check.get("targets", [0])[0]
		var ok := g.play_card(idx, target, p.board.size())
		if not ok:
			print("  FAIL: %s (%s) 无法打出: %s" % [c["name"], c["id"], check.get("reason", "")])
		_check(ok, "卡牌可打出: %s" % c["id"])


func _test_ai_selfplay() -> void:
	print("[AI 自对弈]")
	var matchups := [["MAGE", "WARRIOR"], ["WARRIOR", "PALADIN"], ["PALADIN", "MAGE"]]
	for mu in matchups:
		for game_i in 6:
			var g := GameState.new()
			g.setup(CardDB.hero(mu[0]), CardDB.hero(mu[1]), 1000 + game_i)
			g.start_game()
			var ai0 := AIController.new(g, 0)
			var ai1 := AIController.new(g, 1)
			g.mulligan(0, ai0.choose_mulligan())
			g.mulligan(1, ai1.choose_mulligan())
			ai0.start_turn()
			g.take_events()
			var guard := 0
			var last_current := -1
			while g.phase == Enums.PHASE_PLAYING and guard < 600:
				guard += 1
				if g.current != last_current:
					last_current = g.current
					(ai0 if g.current == 0 else ai1).start_turn()
				var ai := ai0 if g.current == 0 else ai1
				var action: Dictionary = ai.take_action()
				var ok := false
				match action.get("type", "end"):
					"play":
						ok = g.play_card(int(action["index"]), int(action.get("target", 0)),
							int(action.get("position", -1)))
					"attack":
						ok = g.attack(int(action["attacker"]), int(action["target"]))
					"hero_power":
						ok = g.use_hero_power(int(action.get("target", 0)))
					_:
						g.end_turn()
						continue
				ai.notify_result(ok)
				g.take_events()
			_check(g.phase == Enums.PHASE_OVER, "%s vs %s #%d 对局结束（%d 回合）"
				% [mu[0], mu[1], game_i, g.turn])
			_check(g.turn >= 3, "%s vs %s #%d 回合数合理" % [mu[0], mu[1], game_i])
