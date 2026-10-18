class_name BattleScreen
extends Control
## 对战界面：布局、拖拽交互、动画与 AI 回合驱动。
## 规则全部委托给 GameState，本文件只负责"呈现 + 收集输入"。

signal navigate(target: String, data: Variant)

const SLOT_W := 150.0
const BOARD_CENTER_X := 800.0
const ROW_ENEMY_Y := 168.0
const ROW_PLAYER_Y := 388.0
const HAND_Y := 596.0
const HAND_SPAN := 760.0
const HAND_SPACING_MAX := 178.0
const TABLE_RECT := Rect2(236, 112, 1128, 512)

var hero_class := "MAGE"
var deck_cards: Array = []
var shot_dir := ""

var state: GameState
var ai: AIController
var ai_class := ""

var _board_layer: Control
var _hand_layer: Control
var _fx_layer: Control
var _overlay_layer: Control
var _shake_root: Control
var _hurt_flash: ColorRect
var _arrow: TargetArrow
var _table: Control
var _mana_bar: Control
var _enemy_mana_bar: Control

var _hand_views: Dictionary = {}
var _hand_base: Dictionary = {}
var _minion_views: Dictionary = {}
var _hero_views: Dictionary = {}
var _hero_powers: Dictionary = {}
var _enemy_hand_views: Array = []

var _mana_label: Label
var _deck_label: Label
var _enemy_deck_label: Label
var _turn_label: Label
var _end_turn_btn: Button
var _log_label: RichTextLabel
var _log_lines: Array = []
var _turn_banner: Label
var _toast_label: Label
var _hint_label: Label
var _tooltip: CardView

var _drag_card: CardView
var _drag_minion: MinionView
var _valid_targets: Array = []
var _pending_power := false
var _busy := true
var _mulligan_overlay: Control
var _mulligan_selected: Dictionary = {}
var _mulligan_cards: Dictionary = {}
var _game_over_overlay: Control
var _menu_overlay: Control
var _game_over_shown := false
var _shot_flight_done := false


# ================================================================== setup
func _ready() -> void:
	CardDB.ensure_loaded()
	_build_state()
	_build_ui()
	_sync_all()
	_begin_mulligan()


func _build_state() -> void:
	CardDB.ensure_loaded()
	CustomCards.ensure_loaded()
	var heroes := CardDB.heroes()
	var choices: Array = []
	for h in heroes:
		if h["id"] != hero_class:
			choices.append(h["id"])
	ai_class = choices[randi() % choices.size()]
	state = GameState.new()
	state.setup(CardDB.hero(hero_class), CardDB.hero(ai_class), Time.get_ticks_usec(),
		deck_cards)
	ai = AIController.new(state, 1)
	state.start_game()
	state.mulligan(1, ai.choose_mulligan())
	state.take_events()


func _build_ui() -> void:
	# 震动根节点：牌桌 / 战场 / 手牌 / 特效一起晃，弹窗不晃
	_shake_root = Control.new()
	_shake_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shake_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shake_root)

	_table = Control.new()
	_table.position = Vector2.ZERO
	_table.size = Vector2(1600, 900)
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table.draw.connect(_draw_table)
	_shake_root.add_child(_table)

	_board_layer = _layer(_shake_root)
	_hand_layer = _layer(_shake_root)
	_fx_layer = _layer(_shake_root)
	_overlay_layer = _layer(self)
	_hand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 分层明确：牌桌 < 战场 < 手牌 < 特效 < 弹窗
	_table.z_index = -10
	_board_layer.z_index = 0
	_hand_layer.z_index = 20
	_fx_layer.z_index = 100
	_overlay_layer.z_index = 200

	# 英雄：玩家右下、对手右上，与实体牌桌的朝向一致
	for side in 2:
		var hv := HeroView.new()
		hv.setup(state.players[side], side == 0)
		hv.position = Vector2(1222, 634) if side == 0 else Vector2(962, 4)
		hv.z_index = 5
		_board_layer.add_child(hv)
		_hero_views[side] = hv

		var hp := HeroPowerButton.new()
		hp.setup(state.players[side].hero_power)
		hp.position = Vector2(1430, 660) if side == 0 else Vector2(1170, 14)
		hp.z_index = 6
		hp.pressed.connect(_on_hero_power_pressed)
		_board_layer.add_child(hp)
		_hero_powers[side] = hp

	# 法力水晶：玩家右下、对手右上
	_mana_bar = Control.new()
	_mana_bar.position = Vector2(1222, 842)
	_mana_bar.size = Vector2(220, 26)
	_mana_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mana_bar.draw.connect(_draw_mana.bind(0))
	_board_layer.add_child(_mana_bar)

	_enemy_mana_bar = Control.new()
	_enemy_mana_bar.position = Vector2(1170, 146)
	_enemy_mana_bar.size = Vector2(182, 20)
	_enemy_mana_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_mana_bar.draw.connect(_draw_mana.bind(1))
	_board_layer.add_child(_enemy_mana_bar)

	_mana_label = UITheme.ink("", 13, Color("4a3b2a"), 3)
	_mana_label.position = Vector2(1222, 816)
	_mana_label.size = Vector2(220, 22)
	_mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_board_layer.add_child(_mana_label)

	_deck_label = UITheme.ink("", 12, Color("5c4b36"), 3)
	_deck_label.position = Vector2(1452, 844)
	_deck_label.size = Vector2(140, 22)
	_board_layer.add_child(_deck_label)

	_enemy_deck_label = UITheme.ink("", 12, Color("5c4b36"), 3)
	_enemy_deck_label.position = Vector2(24, 68)
	_enemy_deck_label.size = Vector2(420, 22)
	_board_layer.add_child(_enemy_deck_label)

	_turn_label = UITheme.ink("", 17, Color("7a5a1e"), 4)
	_turn_label.position = Vector2(24, 14)
	_turn_label.size = Vector2(480, 28)
	_board_layer.add_child(_turn_label)

	_hint_label = UITheme.ink("拖拽手牌出牌 · 拖拽随从攻击", 13, Color("6a5942"), 3)
	_hint_label.position = Vector2(24, 42)
	_hint_label.size = Vector2(480, 22)
	_board_layer.add_child(_hint_label)

	# 结束回合：右侧中部的大按钮（原版位置）
	_end_turn_btn = Button.new()
	_end_turn_btn.text = "结束回合"
	_end_turn_btn.position = Vector2(1436, 386)
	_end_turn_btn.size = Vector2(146, 100)
	_end_turn_btn.add_theme_font_size_override("font_size", 21)
	_end_turn_btn.pressed.connect(_on_end_turn)
	_board_layer.add_child(_end_turn_btn)
	_style_end_turn(false)

	var menu_btn := Button.new()
	menu_btn.text = "菜单"
	menu_btn.position = Vector2(1478, 10)
	menu_btn.size = Vector2(104, 36)
	menu_btn.add_theme_font_size_override("font_size", 15)
	menu_btn.pressed.connect(_open_menu)
	_board_layer.add_child(menu_btn)

	var mute_btn := Button.new()
	mute_btn.text = "音效"
	mute_btn.position = Vector2(1366, 10)
	mute_btn.size = Vector2(104, 36)
	mute_btn.add_theme_font_size_override("font_size", 15)
	mute_btn.pressed.connect(func():
		var muted := Sfx.toggle_mute()
		mute_btn.text = "音效 关" if muted else "音效 开"
	)
	mute_btn.text = "音效 关" if Sfx.is_muted() else "音效 开"
	_board_layer.add_child(mute_btn)

	# 战报（左侧边栏，不挡牌桌）
	var log_title := UITheme.ink("战  报", 14, Color("5a4318"), 4)
	log_title.position = Vector2(24, 214)
	log_title.size = Vector2(200, 22)
	_board_layer.add_child(log_title)

	var log_panel := Panel.new()
	log_panel.position = Vector2(16, 238)
	log_panel.size = Vector2(208, 322)
	log_panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(1.0, 0.98, 0.93, 0.88), Color("b08a4e"), 2, 10, 8))
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_layer.add_child(log_panel)

	_log_label = RichTextLabel.new()
	_log_label.position = Vector2(26, 248)
	_log_label.size = Vector2(188, 302)
	_log_label.bbcode_enabled = true
	_log_label.scroll_active = true
	_log_label.scroll_following = true
	_log_label.add_theme_font_size_override("normal_font_size", 12)
	_log_label.add_theme_constant_override("line_separation", 2)
	_log_label.add_theme_color_override("default_color", Color("3a2f22"))
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_layer.add_child(_log_label)
	# 滚动条隐藏，否则会压住最后几个字
	var vs := _log_label.get_v_scroll_bar()
	if vs != null:
		var empty := StyleBoxEmpty.new()
		vs.add_theme_stylebox_override("scroll", empty)
		vs.add_theme_stylebox_override("grabber", empty)
		vs.add_theme_stylebox_override("grabber_highlight", empty)
		vs.add_theme_stylebox_override("grabber_pressed", empty)

	_arrow = TargetArrow.new()
	_fx_layer.add_child(_arrow)
	_arrow.stop()

	_turn_banner = UITheme.ink("", 46, Color("6b4a12"), 10)
	_turn_banner.position = Vector2(0, 386)
	_turn_banner.size = Vector2(1600, 74)
	_turn_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_banner.modulate = Color(1, 1, 1, 0)
	_fx_layer.add_child(_turn_banner)

	_toast_label = UITheme.ink("", 20, Color("7a3a12"), 5)
	_toast_label.position = Vector2(500, 560)
	_toast_label.size = Vector2(600, 40)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate = Color(1, 1, 1, 0)
	_fx_layer.add_child(_toast_label)

	# 玩家英雄受击红屏
	_hurt_flash = ColorRect.new()
	_hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.color = Color(0.75, 0.05, 0.05, 0.0)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt_flash.z_index = 150
	add_child(_hurt_flash)

	_tooltip = null
	_log_line("对局开始。", Color("6a5942"))


func _layer(parent: Control) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


func _draw_table() -> void:
	var rect := TABLE_RECT

	# ---------------------------------------------------------------- 全屏底：浅色亚麻桌面
	var bands := 30
	for i in bands:
		var t: float = float(i) / float(bands - 1)
		var c := Color("f3ead8").lerp(Color("ddcdb2"), t)
		_table.draw_rect(Rect2(0, t * 900.0, 1600, 900.0 / float(bands) + 1.5), c)

	# 竖向褶纹，让底面不是一块死平的颜色
	for i in 27:
		var x: float = float(i) * 61.0 + 10.0
		var wob: float = sin(i * 7.13) * 9.0
		_table.draw_line(Vector2(x + wob, 0), Vector2(x + wob, 900),
			Color(1, 1, 1, 0.13), 2.0)
		_table.draw_line(Vector2(x + wob + 2.5, 0), Vector2(x + wob + 2.5, 900),
			Color(0.42, 0.32, 0.20, 0.05), 2.0)

	# 四角暗角
	for corner in [Vector2(-40, -40), Vector2(1640, -40), Vector2(-40, 940), Vector2(1640, 940)]:
		for k in 7:
			_table.draw_circle(corner, 300.0 - float(k) * 34.0, Color(0.20, 0.13, 0.07, 0.014))

	# ---------------------------------------------------------------- 桌体投影
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0.12, 0.08, 0.05, 0.30)
	shadow.set_corner_radius_all(30)
	shadow.shadow_color = Color(0.14, 0.09, 0.05, 0.42)
	shadow.shadow_size = 26
	shadow.shadow_offset = Vector2(0, 10)
	_table.draw_style_box(shadow, Rect2(rect.position + Vector2(0, 8), rect.size))

	# ---------------------------------------------------------------- 木框（暖胡桃木 + 金线）
	var wood := StyleBoxFlat.new()
	wood.bg_color = Color("6b4a33")
	wood.set_corner_radius_all(30)
	wood.border_color = Color("3a2418")
	wood.set_border_width_all(2)
	_table.draw_style_box(wood, rect)

	# 木纹：水平方向细线
	for i in 14:
		var y: float = rect.position.y + 6.0 + float(i) * (rect.size.y - 12.0) / 13.0
		var a: float = 0.05 + 0.03 * float(i % 3)
		_table.draw_line(Vector2(rect.position.x + 16, y), Vector2(rect.end.x - 16, y),
			Color(0.28, 0.17, 0.09, a), 1.5)

	# 外圈亮金压边
	var gold_outer := StyleBoxFlat.new()
	gold_outer.bg_color = Color(0, 0, 0, 0)
	gold_outer.set_corner_radius_all(30)
	gold_outer.border_color = Color("d9b463")
	gold_outer.set_border_width_all(3)
	_table.draw_style_box(gold_outer, rect)

	# ---------------------------------------------------------------- 石面（米色）
	var inner_rect := Rect2(rect.position + Vector2(22, 22), rect.size - Vector2(44, 44))
	var stone := StyleBoxFlat.new()
	stone.bg_color = Color("ded1b4")
	stone.set_corner_radius_all(20)
	stone.border_color = Color("a98f63")
	stone.set_border_width_all(3)
	_table.draw_style_box(stone, inner_rect)

	# 木框内侧暗压线，做出凹槽
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(0, 0, 0, 0)
	groove.set_corner_radius_all(24)
	groove.border_color = Color(0.22, 0.13, 0.07, 0.55)
	groove.set_border_width_all(3)
	_table.draw_style_box(groove, Rect2(rect.position + Vector2(17, 17),
		rect.size - Vector2(34, 34)))

	# 石面内圈高光
	var stone_in := StyleBoxFlat.new()
	stone_in.bg_color = Color(0, 0, 0, 0)
	stone_in.set_corner_radius_all(17)
	stone_in.border_color = Color(1.0, 0.97, 0.88, 0.55)
	stone_in.set_border_width_all(2)
	_table.draw_style_box(stone_in, Rect2(inner_rect.position + Vector2(4, 4),
		inner_rect.size - Vector2(8, 8)))

	# 石面孔隙与细纹
	for k in 120:
		var rx: float = sin(k * 78.233) * 43758.5453
		var ry: float = sin(k * 12.9898 + 3.7) * 43758.5453
		var px: float = inner_rect.position.x + 18.0 + fmod(abs(rx), inner_rect.size.x - 36.0)
		var py: float = inner_rect.position.y + 16.0 + fmod(abs(ry), inner_rect.size.y - 32.0)
		var dark: bool = k % 3 == 0
		_table.draw_circle(Vector2(px, py), 0.9,
			Color(0.45, 0.38, 0.26, 0.10) if dark else Color(1, 1, 1, 0.16))

	# ---------------------------------------------------------------- 中央椭圆纹章（参考原版石心）
	var center := Vector2(BOARD_CENTER_X, (inner_rect.position.y + inner_rect.end.y) * 0.5)
	var oval := PackedVector2Array()
	for i in 96:
		var a := TAU * float(i) / 96.0
		oval.append(center + Vector2(cos(a) * 322.0, sin(a) * 168.0))
	_table.draw_colored_polygon(oval, Color(0.94, 0.89, 0.78, 0.55))
	var ring := oval.duplicate()
	ring.append(oval[0])
	_table.draw_polyline(ring, Color("b99a63"), 2.0, true)

	var inner_oval := PackedVector2Array()
	for i in 96:
		var a := TAU * float(i) / 96.0
		inner_oval.append(center + Vector2(cos(a) * 296.0, sin(a) * 152.0))
	var ring2 := inner_oval.duplicate()
	ring2.append(inner_oval[0])
	_table.draw_polyline(ring2, Color(1, 1, 1, 0.35), 1.2, true)

	# ---------------------------------------------------------------- 中线
	var mid_y := center.y
	_table.draw_line(Vector2(inner_rect.position.x + 22, mid_y),
		Vector2(inner_rect.end.x - 22, mid_y), Color("b99a63"), 1.5)
	_table.draw_line(Vector2(inner_rect.position.x + 22, mid_y + 2),
		Vector2(inner_rect.end.x - 22, mid_y + 2), Color(1, 1, 1, 0.35), 1.0)

	# 中央菱形扣
	var diamond := PackedVector2Array([
		center + Vector2(0, -26), center + Vector2(34, 0),
		center + Vector2(0, 26), center + Vector2(-34, 0),
	])
	_table.draw_colored_polygon(diamond, Color("c9ab74"))
	var dline := diamond.duplicate()
	dline.append(diamond[0])
	_table.draw_polyline(dline, Color("8a6a3a"), 1.6, true)
	_table.draw_circle(center, 12.0, Color("e8d9b8"))
	_table.draw_arc(center, 12.0, 0, TAU, 32, Color("8a6a3a"), 1.6, true)
	_table.draw_circle(center, 4.0, Color("a8843f"))

	# ---------------------------------------------------------------- 四角金饰 + 上下拱饰
	for corner in [inner_rect.position + Vector2(30, 30),
			Vector2(inner_rect.end.x - 30, inner_rect.position.y + 30),
			Vector2(inner_rect.position.x + 30, inner_rect.end.y - 30),
			inner_rect.end - Vector2(30, 30)]:
		_table.draw_arc(corner, 17.0, 0, TAU, 32, Color("c2a061"), 2.0, true)
		_table.draw_arc(corner, 11.0, 0, TAU, 28, Color("c2a061"), 1.2, true)
		_table.draw_circle(corner, 3.4, Color("8a6a3a"))

	for cx in [inner_rect.position.x + inner_rect.size.x * 0.5]:
		# 上拱
		_table.draw_arc(Vector2(cx, inner_rect.position.y + 4), 46.0, PI, TAU, 36,
			Color("c2a061"), 2.4, true)
		_table.draw_arc(Vector2(cx, inner_rect.position.y + 4), 38.0, PI, TAU, 36,
			Color(1, 1, 1, 0.45), 1.2, true)
		# 下拱
		_table.draw_arc(Vector2(cx, inner_rect.end.y - 4), 46.0, 0, PI, 36,
			Color("c2a061"), 2.4, true)
		_table.draw_arc(Vector2(cx, inner_rect.end.y - 4), 38.0, 0, PI, 36,
			Color(1, 1, 1, 0.45), 1.2, true)


func _draw_mana(side: int) -> void:
	var bar: Control = _mana_bar if side == 0 else _enemy_mana_bar
	var p: PlayerState = state.players[side]
	var step := 24.0 if side == 0 else 17.4
	var radius := 9.6 if side == 0 else 6.6
	var start := (bar.size.x - step * 10.0) * 0.5 + step * 0.5
	var cy := bar.size.y * 0.5
	for i in 10:
		var c := Vector2(start + i * step, cy)
		var pts := UITheme.crystal_points(c, radius)
		if i < p.mana:
			bar.draw_circle(c, radius * 1.7, Color(0.2, 0.6, 0.95, 0.10))
			bar.draw_colored_polygon(pts, Color("1a4d76"))
			bar.draw_colored_polygon(UITheme.crystal_points(c, radius - 2.6), Color("49a8e0"))
			bar.draw_colored_polygon(UITheme.crystal_points(c - Vector2(0, radius * 0.32), radius * 0.42),
				Color(1, 1, 1, 0.22))
			var o := pts.duplicate()
			o.append(pts[0])
			bar.draw_polyline(o, Color("bfe8ff"), 1.3, true)
		elif i < p.max_mana:
			bar.draw_colored_polygon(pts, Color("101d27"))
			var o2 := pts.duplicate()
			o2.append(pts[0])
			bar.draw_polyline(o2, Color("35586e"), 1.2, true)
		else:
			var o3 := pts.duplicate()
			o3.append(pts[0])
			bar.draw_polyline(o3, Color("2a3138"), 1.0, true)


# ================================================================== sync
func _sync_all() -> void:
	_sync_heroes()
	_sync_board()
	_sync_hand()
	_sync_enemy_hand()
	_sync_meta()
	_update_interaction()


func _sync_heroes() -> void:
	for side in 2:
		var hv: HeroView = _hero_views[side]
		hv.refresh()


func _sync_board() -> void:
	for side in 2:
		var p: PlayerState = state.players[side]
		for m in p.board:
			if not _minion_views.has(m.instance_id):
				_create_minion_view(m)
			else:
				var v: MinionView = _minion_views[m.instance_id]
				v.instance = m
				v.refresh()
	# 移除已死亡的视图
	for id in _minion_views.keys():
		if not _on_board(id):
			var v: MinionView = _minion_views[id]
			_minion_views.erase(id)
			_fade_out(v)
	_layout_board(true)


func _on_board(instance_id: int) -> bool:
	for p in state.players:
		for m in p.board:
			if m.instance_id == instance_id:
				return true
	return false


func _create_minion_view(m: CardInstance) -> void:
	var v := MinionView.new()
	v.setup(m)
	v.position = _slot_pos(m.owner, _index_of(m), state.players[m.owner].board.size())
	v.scale = Vector2(0.2, 0.2)
	v.modulate = Color(1, 1, 1, 0)
	_board_layer.add_child(v)
	_minion_views[m.instance_id] = v
	_connect_minion(v)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(v, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "modulate:a", 1.0, 0.18)


func _connect_minion(v: MinionView) -> void:
	v.drag_started.connect(_on_minion_drag_started)
	v.drag_moved.connect(_on_minion_drag_moved)
	v.drag_ended.connect(_on_minion_drag_ended)
	v.hover_changed.connect(_on_minion_hover)


func _index_of(m: CardInstance) -> int:
	var p: PlayerState = state.players[m.owner]
	return p.board.find(m)


func _slot_pos(side: int, index: int, count: int) -> Vector2:
	var total := count * SLOT_W
	var start := BOARD_CENTER_X - total * 0.5 + SLOT_W * 0.5
	var y := ROW_ENEMY_Y if side == 1 else ROW_PLAYER_Y
	var center := Vector2(start + index * SLOT_W, y + MinionView.VIEW_SIZE.y * 0.5)
	return center - MinionView.VIEW_SIZE * 0.5


func _layout_board(animate: bool) -> void:
	for side in 2:
		var p: PlayerState = state.players[side]
		for i in p.board.size():
			var m: CardInstance = p.board[i]
			if not _minion_views.has(m.instance_id):
				continue
			var v: MinionView = _minion_views[m.instance_id]
			var target := _slot_pos(side, i, p.board.size())
			if animate and not v.dragging:
				v.z_index = 10 + i
				create_tween().tween_property(v, "position", target, 0.16) \
					.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			else:
				v.position = target
				v.z_index = 10 + i


func _sync_hand() -> void:
	var p: PlayerState = state.players[0]
	var alive := {}
	for card in p.hand:
		alive[card.instance_id] = true
		var v: CardView
		if _hand_views.has(card.instance_id):
			v = _hand_views[card.instance_id]
			v.card = card
			v.refresh()
		else:
			v = CardView.new()
			v.setup(card, true)
			_connect_card(v)
			_hand_layer.add_child(v)
			_hand_views[card.instance_id] = v
			# 新抽到的牌从牌库方向滑入
			v.position = Vector2(1430, 770)
			v.rotation = 0.26
			v.scale = Vector2(0.82, 0.82)
			v.modulate = Color(1, 1, 1, 0)
			var tw := create_tween().set_parallel(true)
			tw.tween_property(v, "scale", Vector2.ONE, 0.22)
			tw.tween_property(v, "modulate:a", 1.0, 0.18)
		v.set_cost(state.get_card_cost(card, 0))
	for id in _hand_views.keys():
		if not alive.has(id):
			var v2: CardView = _hand_views[id]
			_hand_views.erase(id)
			_hand_base.erase(id)
			if v2.dragging:
				v2.cancel_drag(Vector2.ZERO)
			_fade_out(v2)
	_layout_hand()


func _connect_card(v: CardView) -> void:
	v.drag_started.connect(_on_card_drag_started)
	v.drag_moved.connect(_on_card_drag_moved)
	v.drag_ended.connect(_on_card_drag_ended)
	v.hover_changed.connect(_on_card_hover)


func _layout_hand() -> void:
	var p: PlayerState = state.players[0]
	var n := p.hand.size()
	if n == 0:
		return
	var spacing := HAND_SPACING_MAX
	if n > 1:
		spacing = clampf(HAND_SPAN / float(n - 1), 84.0, HAND_SPACING_MAX)
	for i in n:
		var card: CardInstance = p.hand[i]
		if not _hand_views.has(card.instance_id):
			continue
		var v: CardView = _hand_views[card.instance_id]
		if v.dragging:
			continue
		var off := i - (n - 1) * 0.5
		var bulge := pow(absf(off) / maxf((n - 1) * 0.5, 1.0), 2.0) * 12.0
		var pos := Vector2(730 + off * spacing - CardView.CARD_SIZE.x * 0.5, HAND_Y + bulge)
		_hand_base[card.instance_id] = pos
		v.z_index = 10 + i
		v.rotation = clampf(off * 0.016, -0.085, 0.085)
		create_tween().tween_property(v, "position", pos, 0.26) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _sync_enemy_hand() -> void:
	var n: int = state.players[1].hand.size()
	while _enemy_hand_views.size() < n:
		var cb := CardBackView.new()
		cb.setup()
		cb.scale = Vector2(0.78, 0.78)
		_board_layer.add_child(cb)
		_enemy_hand_views.append(cb)
	while _enemy_hand_views.size() > n:
		var cb2: CardBackView = _enemy_hand_views.pop_back()
		cb2.queue_free()
	var spacing := 38.0
	if n > 1:
		spacing = minf(38.0, 420.0 / float(n - 1))
	for i in _enemy_hand_views.size():
		var v: CardBackView = _enemy_hand_views[i]
		var off := i - (n - 1) * 0.5
		var x := 770 + off * spacing - CardBackView.VIEW_SIZE.x * 0.5
		v.position = Vector2(x, -24 + absf(off) * 2.0)
		v.rotation = off * 0.022
		v.z_index = 2


func _sync_meta() -> void:
	var p: PlayerState = state.players[0]
	var e: PlayerState = state.players[1]
	_mana_label.text = "%d / %d 法力" % [p.mana, p.max_mana]
	_deck_label.text = "牌库 %d" % p.deck.size()
	_enemy_deck_label.text = "对手   牌库 %d   手牌 %d" % [e.deck.size(), e.hand.size()]
	_mana_bar.queue_redraw()
	_enemy_mana_bar.queue_redraw()
	var turn_text := "第 %d 回合" % maxi(1, state.turn)
	if state.phase == Enums.PHASE_MULLIGAN:
		turn_text += "  ·  换牌阶段"
	elif state.current == 0:
		turn_text += "  ·  你的回合"
	else:
		turn_text += "  ·  对手的回合"
	_turn_label.text = turn_text


func _update_interaction() -> void:
	var can_act := _can_player_act()
	var p: PlayerState = state.players[0]
	for card in p.hand:
		var v: CardView = _hand_views.get(card.instance_id)
		if v == null:
			continue
		var idx: int = p.hand.find(card)
		var check := state.can_play_card(idx, 0)
		v.set_playable(can_act and (check.get("ok", false)
			or check.get("needs_target", false)))
	for id in _minion_views:
		var mv: MinionView = _minion_views[id]
		mv.set_draggable(can_act and state.get_valid_attack_targets(id).size() > 0)
	var hp_available: bool = can_act and bool(state.can_use_hero_power(0, 0).get("ok", false))
	if not hp_available and can_act:
		hp_available = bool(state.can_use_hero_power(0, 0).get("needs_target", false))
	_hero_powers[0].refresh_state(hp_available, p.hero_power_used)
	_hero_powers[1].refresh_state(false, state.players[1].hero_power_used)
	_end_turn_btn.disabled = not can_act
	_end_turn_btn.text = "结束回合" if can_act else ("对手回合…" if state.phase == Enums.PHASE_PLAYING else "结束回合")
	_style_end_turn(can_act)


## 结束回合按钮：轮到自己时是原版那种绿色高亮，否则压暗。
func _style_end_turn(can_act: bool) -> void:
	var bg := Color("1e3a25") if can_act else Color("171c22")
	var border := Color("7fd08a") if can_act else Color("3a4149")
	_end_turn_btn.add_theme_stylebox_override("normal",
		UITheme.panel_style(bg, border, 2, 16, 8))
	_end_turn_btn.add_theme_stylebox_override("hover",
		UITheme.panel_style(bg.lightened(0.08), Color("a8efb0"), 2, 16, 10))
	_end_turn_btn.add_theme_stylebox_override("pressed",
		UITheme.panel_style(bg.darkened(0.25), border, 2, 16, 4))
	_end_turn_btn.add_theme_stylebox_override("disabled",
		UITheme.panel_style(Color("14181d"), Color("333a42"), 1, 16, 0))
	_end_turn_btn.add_theme_color_override("font_color", Color("d8f5da") if can_act else Color("7d858f"))
	_end_turn_btn.add_theme_color_override("font_disabled_color", Color("6d747c"))


func _can_player_act() -> bool:
	return not _busy and state.phase == Enums.PHASE_PLAYING and state.current == 0 \
		and _mulligan_overlay == null and _game_over_overlay == null and _menu_overlay == null


# ================================================================== player actions
func _on_card_drag_started(view: CardView) -> void:
	if not _can_player_act():
		view.cancel_drag(Vector2.ZERO)
		return
	Sfx.play("hover", -12.0, 0.85)
	_drag_card = view
	_hint_label.visible = false
	var idx: int = state.players[0].hand.find(view.card)
	if idx < 0:
		return
	_valid_targets = state.get_valid_targets(idx, 0)
	_highlight_targets(_valid_targets)
	var start: Vector2 = view.get_global_rect().get_center()
	_arrow.begin(start)
	_arrow.update_to(get_global_mouse_position())


func _on_card_drag_moved(view: CardView) -> void:
	if _drag_card == null:
		return
	var mouse := get_global_mouse_position()
	_arrow.update_to(mouse)
	if not _valid_targets.is_empty():
		var target := _target_at(mouse)
		_arrow.valid = _valid_targets.has(target)


func _on_card_drag_ended(view: CardView, drop_position: Vector2) -> void:
	if _drag_card == null:
		return
	var card := view.card
	var idx: int = state.players[0].hand.find(card)
	var valid := _valid_targets.duplicate()
	_drag_card = null
	_stop_targeting()
	if idx < 0:
		return
	var spec := state.get_target_spec(card.def())
	var target := 0
	var position := -1
	if not spec.is_empty() and not valid.is_empty():
		target = _target_at(drop_position)
		if not valid.has(target):
			_reject(view, "请把卡牌拖到高亮的目标上")
			return
	if card.card_type() == "MINION":
		if target == 0 and (drop_position.y < 190.0 or drop_position.y > 600.0):
			_reject(view, "请把随从拖到战场上")
			return
		position = _board_insert_index(drop_position.x)
	elif spec.is_empty():
		if drop_position.y > 600.0:
			_reject(view, "请把法术拖到战场上")
			return
	var check := state.can_play_card(idx, target, position)
	if not check.get("ok", false):
		_reject(view, str(check.get("reason", "无法打出")))
		return
	view.cancel_drag(Vector2.ZERO)
	_do_player_play(idx, target, position)


func _do_player_play(index: int, target: int, position: int) -> void:
	_busy = true
	_update_interaction()
	var inst: CardInstance = state.players[0].hand[index]
	var view: CardView = _hand_views.get(inst.instance_id)
	var flight := _detach_for_flight(view)
	if not state.play_card(index, target, position):
		if not flight.is_empty() and is_instance_valid(view):
			view.queue_free()
		_busy = false
		_sync_all()
		return
	var is_minion := inst.card_type() == "MINION"
	var dest := Vector2(800, 366)
	if is_minion:
		var pos := position
		if pos < 0 or pos > state.players[0].board.size() - 1:
			pos = state.players[0].board.size() - 1
		var slot := _slot_pos(0, pos, state.players[0].board.size())
		dest = slot + MinionView.VIEW_SIZE * 0.5
	elif target != 0:
		dest = _target_center(target)
	Sfx.play("play", -5.0, randf_range(0.97, 1.05))
	_sync_hand()
	if not flight.is_empty():
		await _fly_card(view, flight, dest, is_minion,
			str(inst.def().get("text", "")).contains("伤害"))
	await _play_events(state.take_events())
	_sync_all()
	_busy = false
	_update_interaction()
	_after_action()


## 把卡从手牌层摘出来交给特效层，返回飞行起点。
func _detach_for_flight(view: CardView) -> Dictionary:
	if view == null or not is_instance_valid(view):
		return {}
	var data := {"pos": view.global_position, "rot": view.rotation}
	_hand_views.erase(view.card.instance_id)
	_hand_base.erase(view.card.instance_id)
	view.get_parent().remove_child(view)
	_fx_layer.add_child(view)
	view.top_level = true
	view.global_position = data["pos"]
	view.rotation = data["rot"]
	view.z_index = 500
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return data


## 出牌：卡牌沿弧线飞向目标点，落点爆开。
func _fly_card(view: CardView, data: Dictionary, dest: Vector2, is_minion: bool,
		fire: bool) -> void:
	var start: Vector2 = data["pos"]
	var start_rot: float = data["rot"]
	var end := dest - CardView.CARD_SIZE * 0.5
	var ctrl := (start + end) * 0.5 + Vector2(0, -150)
	var class_color := CardDB.class_color(str(view.card.def().get("class", "NEUTRAL")))

	var trail := CPUParticles2D.new()
	trail.amount = 26
	trail.lifetime = 0.42
	trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 26.0
	trail.direction = Vector2(0, -1)
	trail.spread = 180.0
	trail.gravity = Vector2(0, -20)
	trail.initial_velocity_min = 8.0
	trail.initial_velocity_max = 42.0
	trail.scale_amount_min = 0.3
	trail.scale_amount_max = 0.9
	trail.color = Color(class_color.lightened(0.35), 0.8)
	trail.position = CardView.CARD_SIZE * 0.5
	trail.emitting = true
	var dot := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var d := Vector2(x - 3.5, y - 3.5).length()
			dot.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d / 3.5, 0.0, 1.0)))
	trail.texture = ImageTexture.create_from_image(dot)
	view.add_child(trail)

	var tw := create_tween()
	tw.tween_method(_update_flight.bind(view, start, ctrl, end, start_rot), 0.0, 1.0, 0.36) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if shot_dir != "" and not _shot_flight_done:
		_shot_flight_done = true
		get_tree().create_timer(0.2).timeout.connect(func() -> void: _capture("03b_flight"))
	await tw.finished
	trail.emitting = false
	view.scale = Vector2(0.82, 0.82)

	if is_minion:
		Sfx.card_land()
		_spawn_burst(dest, Color(0.88, 0.74, 0.5), 20, 130)
		_impact_ring(dest, Color(1, 0.9, 0.62), 8.0, 52.0, 0.32)
		_screen_shake(2.5)
	else:
		Sfx.spell(fire)
		_spawn_burst(dest, class_color, 26, 170)
		_impact_ring(dest, class_color.lightened(0.25), 18.0, 110.0, 0.38)
		_screen_flash(class_color.lightened(0.35), 0.12)
		_screen_shake(4.0)

	var out := create_tween().set_parallel(true)
	out.tween_property(view, "scale", Vector2(0.45, 0.45), 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	out.tween_property(view, "modulate:a", 0.0, 0.2)
	out.chain().tween_callback(view.queue_free)
	await get_tree().create_timer(0.12).timeout


func _update_flight(v: float, view: CardView, start: Vector2, ctrl: Vector2,
		end: Vector2, rot: float) -> void:
	if view == null or not is_instance_valid(view):
		return
	var u := 1.0 - v
	view.global_position = start * (u * u) + ctrl * (2.0 * u * v) + end * (v * v)
	view.rotation = lerp(rot, 0.0, minf(1.0, v * 1.7))
	view.scale = Vector2.ONE * lerp(1.0, 0.82, v)


func _reject(view: CardView, reason: String) -> void:
	view.cancel_drag(Vector2.ZERO)
	_layout_hand()
	Sfx.error()
	_toast(reason)


func _board_insert_index(x: float) -> int:
	var n: int = state.players[0].board.size()
	var total := n * SLOT_W
	var start := BOARD_CENTER_X - total * 0.5
	var idx := int(round((x - start) / SLOT_W))
	return clampi(idx, 0, n)


func _on_minion_drag_started(view: MinionView) -> void:
	if not _can_player_act() or not view.draggable:
		view.cancel_drag()
		return
	Sfx.play("hover", -12.0, 0.9)
	_drag_minion = view
	_valid_targets = state.get_valid_attack_targets(view.instance.instance_id)
	_highlight_targets(_valid_targets)
	_arrow.begin(view.get_global_rect().get_center())
	_arrow.update_to(get_global_mouse_position())


func _on_minion_drag_moved(view: MinionView) -> void:
	var mouse := get_global_mouse_position()
	_arrow.update_to(mouse)
	_arrow.valid = _valid_targets.has(_target_at(mouse))


func _on_minion_drag_ended(view: MinionView, drop_position: Vector2) -> void:
	if _drag_minion == null:
		return
	var attacker_id: int = view.instance.instance_id
	var valid := _valid_targets.duplicate()
	_drag_minion = null
	_stop_targeting()
	var target := _target_at(drop_position)
	if not valid.has(target):
		view.cancel_drag()
		_toast("只能攻击高亮的目标")
		return
	_busy = true
	_update_interaction()
	if not state.attack(attacker_id, target):
		_busy = false
		_sync_all()
		return
	await _play_events(state.take_events())
	_sync_all()
	_busy = false
	_update_interaction()
	_after_action()


func _after_action() -> void:
	if state.phase == Enums.PHASE_OVER:
		_finish_game()


func _on_hero_power_pressed() -> void:
	if not _can_player_act():
		return
	Sfx.ui_click()
	_stop_targeting()
	var check := state.can_use_hero_power(0, 0)
	if not check.get("ok", false):
		if check.get("needs_target", false):
			_pending_power = true
			_valid_targets = state.get_hero_power_targets(0)
			_highlight_targets(_valid_targets)
			_arrow.begin(_hero_powers[0].get_global_rect().get_center())
			_arrow.update_to(get_global_mouse_position())
			_hint_label.text = "点击高亮目标释放英雄技能，右键取消"
			_hint_label.visible = true
			return
		_toast(str(check.get("reason", "无法使用英雄技能")))
		return
	_use_power(0)


func _use_power(target: int) -> void:
	_busy = true
	_stop_targeting()
	_update_interaction()
	if not state.use_hero_power(target):
		_busy = false
		_sync_all()
		return
	await _play_events(state.take_events())
	_sync_all()
	_busy = false
	_update_interaction()
	_after_action()
	_hint_label.text = "拖拽手牌出牌 · 拖拽随从攻击"
	_hint_label.visible = true


func _on_end_turn() -> void:
	if not _can_player_act():
		return
	Sfx.ui_click()
	_busy = true
	_stop_targeting()
	_update_interaction()
	state.end_turn()
	await _play_events(state.take_events())
	_sync_all()
	if state.phase == Enums.PHASE_OVER:
		_busy = false
		_finish_game()
		return
	await _run_ai_turn()


# ================================================================== AI
func _run_ai_turn() -> void:
	_busy = true
	_update_interaction()
	await get_tree().create_timer(0.55).timeout
	ai.start_turn()
	var guard := 0
	while state.phase == Enums.PHASE_PLAYING and state.current == 1 and guard < 60:
		guard += 1
		var action: Dictionary = ai.take_action()
		if action.get("type", "end") == "end":
			break
		var ok := _apply_ai_action(action)
		ai.notify_result(ok)
		await _play_events(state.take_events())
		if state.phase == Enums.PHASE_OVER:
			break
		await get_tree().create_timer(0.3).timeout
	if state.phase == Enums.PHASE_PLAYING and state.current == 1:
		state.end_turn()
		await _play_events(state.take_events())
	_sync_all()
	_busy = false
	_update_interaction()
	if state.phase == Enums.PHASE_OVER:
		_finish_game()
	else:
		_hint_label.text = "拖拽手牌出牌 · 拖拽随从攻击"
		_hint_label.visible = true


func _apply_ai_action(action: Dictionary) -> bool:
	match action.get("type", ""):
		"play":
			var idx: int = int(action.get("index", -1))
			var target: int = int(action.get("target", 0))
			var pos: int = int(action.get("position", -1))
			# 战报由 _play_events 统一记录，避免重复
			return state.play_card(idx, target, pos)
		"attack":
			return state.attack(int(action.get("attacker", 0)), int(action.get("target", 0)))
		"hero_power":
			return state.use_hero_power(int(action.get("target", 0)))
	return false


# ================================================================== targeting
func _target_at(pos: Vector2) -> int:
	for side in 2:
		var hv: HeroView = _hero_views[side]
		if hv.get_global_rect().has_point(pos):
			return state.players[side].hero_id()
	for id in _minion_views:
		var v: MinionView = _minion_views[id]
		if v.get_global_rect().has_point(pos):
			return id
	return 0


func _highlight_targets(ids: Array) -> void:
	for id in _minion_views:
		var v: MinionView = _minion_views[id]
		v.set_target_glow(ids.has(id))
	for side in 2:
		var hv: HeroView = _hero_views[side]
		hv.set_target_glow(ids.has(state.players[side].hero_id()))


func _stop_targeting() -> void:
	_pending_power = false
	_arrow.stop()
	_valid_targets = []
	for id in _minion_views:
		var v: MinionView = _minion_views[id]
		v.set_target_glow(false)
	for side in 2:
		var hv: HeroView = _hero_views[side]
		hv.set_target_glow(false)
	if _drag_minion != null:
		_drag_minion.cancel_drag()
		_drag_minion = null
	_hint_label.text = "拖拽手牌出牌 · 拖拽随从攻击"


func _input(event: InputEvent) -> void:
	if _pending_power:
		if event is InputEventMouseMotion:
			_arrow.update_to(get_global_mouse_position())
			_arrow.valid = _valid_targets.has(_target_at(get_global_mouse_position()))
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_stop_targeting()
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				var target := _target_at(get_global_mouse_position())
				if _valid_targets.has(target):
					_use_power(target)
				else:
					_stop_targeting()
				get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _pending_power:
				_stop_targeting()
			elif _menu_overlay != null:
				_close_menu()
			elif _game_over_overlay == null and _mulligan_overlay == null:
				_open_menu()
			get_viewport().set_input_as_handled()


# ================================================================== events / animation
func _play_events(events: Array) -> void:
	if events.is_empty():
		return
	_ensure_board_views()
	for e in events:
		var kind: String = e.get("type", "")
		match kind:
			"play_card":
				var side: int = int(e.get("player", 0))
				var name := _card_name(str(e.get("card_id", "")))
				_log_line("%s 打出 %s" % ["你" if side == 0 else "对手", name],
					UITheme.GOLD if side == 0 else UITheme.MUTED)
				if side == 1:
					Sfx.card_play()
					_ai_play_fx()
			"draw":
				Sfx.card_draw()
			"summon":
				pass
			"attack":
				await _anim_attack(e)
			"damage":
				_anim_damage(e)
				await get_tree().create_timer(0.06).timeout
			"heal":
				Sfx.heal()
				_anim_float(e, "+%d" % int(e.get("amount", 0)), UITheme.GREEN)
			"shield":
				Sfx.shield()
				_anim_flash(e, Color(1.0, 0.9, 0.55))
				_anim_float(e, "圣盾", UITheme.GOLD)
			"freeze":
				Sfx.freeze()
				_anim_flash(e, Color(0.45, 0.75, 1.0))
				_anim_float(e, "冻结", Color("8fd0ff"))
			"death":
				_anim_death(e)
			"transform":
				Sfx.spell(false)
				_anim_flash({"target": e.get("card", 0)}, Color(0.8, 0.6, 1.0))
				_anim_float({"target": e.get("card", 0)}, "变形", UITheme.PURPLE)
			"armor":
				Sfx.armor()
				var side2: int = int(e.get("player", 0))
				_anim_float({"target": state.players[side2].hero_id()},
					"+%d 护甲" % int(e.get("amount", 0)), Color("b9c3d1"))
			"fatigue":
				Sfx.hurt()
				_log_line("%s 牌库耗尽，受到 %d 点疲劳伤害" % [
					"你" if int(e.get("player", 0)) == 0 else "对手",
					int(e.get("amount", 0))], UITheme.RED)
			"burn":
				Sfx.error()
				_log_line("手牌已满，%s 被烧掉" % _card_name(str(e.get("card_id", ""))),
					UITheme.MUTED)
			"turn_start":
				await _anim_turn_banner(int(e.get("player", 0)))
			"hero_power":
				var side_p: int = int(e.get("player", 0))
				_log_line("%s 使用英雄技能" % ["你" if side_p == 0 else "对手"],
					UITheme.GOLD if side_p == 0 else UITheme.MUTED)
				_anim_flash({"target": state.players[side_p].hero_id()}, UITheme.GOLD)
				var hero_center := _target_center(state.players[side_p].hero_id())
				_impact_ring(hero_center, UITheme.GOLD, 14.0, 82.0, 0.4)
				Sfx.spell(false)
			"game_over":
				pass
			"spell":
				if int(e.get("player", 0)) == 1:
					var fire2 := str(CardDB.card(str(e.get("card_id", ""))).get("text", "")).contains("伤害")
					Sfx.spell(fire2)
			"mulligan":
				pass
	await get_tree().create_timer(0.08).timeout
	_sync_all()


## 对手出牌的轻量表现：一张卡背从对方手牌飞向牌桌。
func _ai_play_fx() -> void:
	var cb := CardBackView.new()
	cb.setup()
	cb.scale = Vector2(0.66, 0.66)
	_fx_layer.add_child(cb)
	cb.top_level = true
	cb.global_position = Vector2(770, -26)
	var tw := create_tween()
	tw.tween_property(cb, "global_position", Vector2(742, 236), 0.26) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cb, "rotation", -0.22, 0.26)
	tw.parallel().tween_property(cb, "scale", Vector2(0.86, 0.86), 0.26)
	await tw.finished
	Sfx.card_land()
	_spawn_burst(Vector2(800, 300), Color(0.88, 0.8, 0.62), 16, 130)
	_impact_ring(Vector2(800, 300), Color(0.9, 0.85, 0.7), 6.0, 54.0, 0.26)
	var out := create_tween().set_parallel(true)
	out.tween_property(cb, "modulate:a", 0.0, 0.16)
	out.tween_property(cb, "scale", Vector2(0.5, 0.5), 0.16)
	out.chain().tween_callback(cb.queue_free)


func _ensure_board_views() -> void:
	for side in 2:
		var p: PlayerState = state.players[side]
		for i in p.board.size():
			var m: CardInstance = p.board[i]
			if not _minion_views.has(m.instance_id):
				_create_minion_view(m)


func _anim_attack(e: Dictionary) -> void:
	var aid: int = int(e.get("attacker", 0))
	var tid: int = int(e.get("target", 0))
	var av: MinionView = _minion_views.get(aid)
	var target_pos := _target_center(tid)
	if av == null:
		return
	var origin := av.position
	var dir := (target_pos - av.get_global_rect().get_center()).normalized()
	Sfx.swing()

	# 预备：微微后撤、压低
	var windup := create_tween().set_parallel(true)
	windup.tween_property(av, "position", origin - dir * 14.0, 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	windup.tween_property(av, "scale", Vector2(1.06, 0.96), 0.07)
	await get_tree().create_timer(0.08).timeout

	# 冲锋
	var lunge := create_tween().set_parallel(true)
	lunge.tween_property(av, "position", origin + dir * 66.0, 0.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	lunge.tween_property(av, "scale", Vector2(0.97, 1.05), 0.1)
	await get_tree().create_timer(0.1).timeout

	# 命中：冲击环 + 火星 + 震屏 + 后仰
	_impact_ring(target_pos, Color(1.0, 0.86, 0.55), 8.0, 74.0, 0.28)
	_spawn_burst(target_pos, Color(1.0, 0.82, 0.5), 18, 160)
	_screen_shake(5.0)
	Sfx.impact(0.9)
	_screen_flash(Color(1, 0.92, 0.72), 0.10)
	_knockback(tid, dir)
	_anim_flash({"target": tid}, Color(1, 0.72, 0.55))

	# 收招
	var back := create_tween().set_parallel(true)
	back.tween_property(av, "position", origin, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	back.tween_property(av, "scale", Vector2.ONE, 0.2)
	await get_tree().create_timer(0.12).timeout


## 被击退一小步。
func _knockback(target_id: int, dir: Vector2) -> void:
	if Enums.is_hero(target_id):
		var hv: HeroView = _hero_views[Enums.hero_owner(target_id)]
		var base := hv.position
		var tw := create_tween()
		tw.tween_property(hv, "position", base + dir * 9.0, 0.06)
		tw.tween_property(hv, "position", base, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		var v: MinionView = _minion_views.get(target_id)
		if v == null:
			return
		var base2 := v.position
		var tw2 := create_tween()
		tw2.tween_property(v, "position", base2 + dir * 12.0, 0.06)
		tw2.parallel().tween_property(v, "rotation", dir.x * 0.12, 0.06)
		tw2.tween_property(v, "position", base2, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.parallel().tween_property(v, "rotation", 0.0, 0.2)


func _anim_damage(e: Dictionary) -> void:
	var target: int = int(e.get("target", 0))
	var dealt: int = int(e.get("dealt", 0))
	var blocked := bool(e.get("blocked", false))
	var absorbed: int = int(e.get("absorbed", 0))
	var pos := _target_center(target)
	if blocked:
		_anim_float(e, "免疫", UITheme.GOLD)
		_impact_ring(pos, Color(1, 0.9, 0.55), 12.0, 58.0, 0.3)
		Sfx.shield()
		return

	var text := "-%d" % dealt
	if absorbed > 0 and dealt > 0:
		text = "-%d" % (absorbed + dealt)
	elif absorbed > 0:
		text = "-%d" % absorbed
	_anim_float(e, text, Color("ff8168") if absorbed == 0 else Color("b9c3d1"))

	var v: MinionView = _minion_views.get(target)
	if v != null:
		_anim_flash(e, Color(1, 0.55, 0.45))
		_shake(v)
		Sfx.hurt()
	elif target < 0:
		var hv2: HeroView = _hero_views[Enums.hero_owner(target)]
		hv2.flash(Color(1, 0.45, 0.4))
		if Enums.hero_owner(target) == 0:
			_hurt_pulse()
			_screen_shake(6.0)
		else:
			_screen_shake(3.0)

	_impact_ring(pos, Color(1, 0.6, 0.4), 5.0, 42.0 + dealt * 3.0, 0.26)
	_spawn_burst(pos, Color(1, 0.62, 0.42), 8 + mini(dealt * 2, 14), 90.0 + dealt * 8.0)
	Sfx.impact(0.5)
	await get_tree().create_timer(0.05).timeout


func _anim_float(e: Dictionary, text: String, color: Color) -> void:
	var target: int = int(e.get("target", 0))
	var pos := _target_center(target) + Vector2(0, -44)
	var big := text.length() > 3
	var size := 28 if big else 24
	var l := UITheme.outline_label(text, size, color, 7)
	l.position = pos - Vector2(80, 20)
	l.size = Vector2(160, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.pivot_offset = Vector2(80, 20)
	l.scale = Vector2(0.55, 0.55)
	_fx_layer.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2(1.18, 1.18), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", pos.y - 26, 0.55) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.45)
	tw.tween_property(l, "scale", Vector2.ONE, 0.12)
	tw.parallel().tween_property(l, "position:y", pos.y - 62, 0.4)
	tw.chain().tween_callback(l.queue_free)


func _anim_flash(e: Dictionary, color: Color) -> void:
	var target: int = int(e.get("target", 0))
	var v: MinionView = _minion_views.get(target)
	if v != null:
		v.modulate = color
		create_tween().tween_property(v, "modulate", Color.WHITE, 0.3)
	elif target < 0:
		var hv: HeroView = _hero_views[Enums.hero_owner(target)]
		hv.flash(color)


func _shake(v: MinionView) -> void:
	var base := v.position
	var tw := create_tween()
	tw.tween_property(v, "position", base + Vector2(-4, 1), 0.04)
	tw.tween_property(v, "position", base + Vector2(4, -1), 0.05)
	tw.tween_property(v, "position", base + Vector2(-2, 0), 0.05)
	tw.tween_property(v, "position", base, 0.06)


func _anim_death(e: Dictionary) -> void:
	var target: int = int(e.get("target", 0))
	var pos := _target_center(target)
	_spawn_burst(pos, Color(1.0, 0.78, 0.42), 30, 210)
	_impact_ring(pos, Color(1.0, 0.7, 0.38), 12.0, 100.0, 0.42)
	_screen_shake(3.5)
	Sfx.death()
	var v: MinionView = _minion_views.get(target)
	if v != null and not v.is_queued_for_deletion():
		_shatter_out(v)
		_minion_views.erase(target)
	_log_line("%s 被消灭" % _card_name(str(e.get("card_id", ""))), UITheme.MUTED)


## 随从死亡：先鼓一下再碎散消失。
func _shatter_out(v: MinionView) -> void:
	v.z_index = 0
	v.pivot_offset = MinionView.VIEW_SIZE * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(v, "scale", Vector2(1.12, 1.12), 0.09)
	tw.tween_property(v, "rotation", randf_range(-0.2, 0.2), 0.32)
	tw.tween_property(v, "modulate:a", 0.0, 0.3).set_delay(0.08)
	tw.tween_property(v, "scale", Vector2(0.35, 0.35), 0.32).set_delay(0.09)
	tw.chain().tween_callback(v.queue_free)


func _spawn_burst(pos: Vector2, color: Color, amount := 18, speed := 120.0) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.5
	p.explosiveness = 0.96
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.25
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 180)
	p.scale_amount_min = 0.35
	p.scale_amount_max = 1.15
	p.damping_min = 20.0
	p.damping_max = 60.0
	p.color = color
	p.position = pos
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	for y in 10:
		for x in 10:
			var d := Vector2(x - 4.5, y - 4.5).length()
			var a := clampf(1.0 - d / 4.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	p.texture = ImageTexture.create_from_image(img)
	_fx_layer.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## 命中冲击环：快速扩散并淡出。
func _impact_ring(pos: Vector2, color: Color, r0: float, r1: float, dur: float) -> void:
	var ring := Control.new()
	var pad := r1 + 10.0
	ring.position = pos - Vector2(pad, pad)
	ring.size = Vector2(pad * 2, pad * 2)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := {"r": r0, "a": 0.9}
	var cc := ring.size * 0.5
	ring.draw.connect(func() -> void:
		ring.draw_arc(cc, st.r, 0, TAU, 48, Color(color, st.a), 3.0, true)
		if st.a > 0.25:
			ring.draw_arc(cc, st.r * 0.62, 0, TAU, 40, Color(color, st.a * 0.45), 1.6, true)
	)
	_fx_layer.add_child(ring)
	var tw := create_tween()
	var update := func(v: float) -> void:
		st.r = lerpf(r0, r1, v)
		st.a = 0.9 * (1.0 - v)
		ring.queue_redraw()
	tw.tween_method(update, 0.0, 1.0, dur)
	tw.tween_callback(ring.queue_free)


func _screen_shake(mag := 5.0, dur := 0.24) -> void:
	if _shake_root == null:
		return
	var tw := create_tween()
	for i in 5:
		var off := Vector2(randf_range(-mag, mag), randf_range(-mag, mag)) * (1.0 - i * 0.18)
		tw.tween_property(_shake_root, "position", off, dur / 5.0)
	tw.tween_property(_shake_root, "position", Vector2.ZERO, 0.07)


## 全屏轻闪，强化命中/落地的冲击感。
func _screen_flash(color: Color, alpha := 0.1) -> void:
	var fl := ColorRect.new()
	fl.set_anchors_preset(Control.PRESET_FULL_RECT)
	fl.color = Color(color, alpha)
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.z_index = 140
	add_child(fl)
	create_tween().tween_property(fl, "color:a", 0.0, 0.2)
	get_tree().create_timer(0.26).timeout.connect(fl.queue_free)


## 玩家英雄受击：红屏一闪。
func _hurt_pulse() -> void:
	if _hurt_flash == null:
		return
	_hurt_flash.color = Color(0.8, 0.06, 0.06, 0.22)
	create_tween().tween_property(_hurt_flash, "color:a", 0.0, 0.5)


func _anim_turn_banner(player: int) -> void:
	_turn_banner.text = "你的回合" if player == 0 else "对手的回合"
	_turn_banner.modulate = Color(1, 1, 1, 0)
	_turn_banner.scale = Vector2(0.92, 0.92)
	_turn_banner.pivot_offset = _turn_banner.size * 0.5
	_turn_banner.position.y = 396
	Sfx.turn()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_turn_banner, "modulate:a", 1.0, 0.14)
	tw.tween_property(_turn_banner, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_turn_banner, "position:y", 382, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.42).timeout
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(_turn_banner, "modulate:a", 0.0, 0.24)
	tw2.tween_property(_turn_banner, "position:y", 372, 0.24)
	await get_tree().create_timer(0.2).timeout
	_log_line("第 %d 回合 · %s" % [state.turn, "你的回合" if player == 0 else "对手的回合"],
		UITheme.GOLD if player == 0 else UITheme.MUTED)


func _target_center(target_id: int) -> Vector2:
	if Enums.is_hero(target_id):
		var side := Enums.hero_owner(target_id)
		var hv: HeroView = _hero_views[side]
		return hv.get_global_rect().get_center()
	var v: MinionView = _minion_views.get(target_id)
	if v != null:
		return v.get_global_rect().get_center()
	return Vector2(800, 400)


func _fade_out(node: Control) -> void:
	if node.is_queued_for_deletion():
		return
	node.z_index = 0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(node, "modulate:a", 0.0, 0.26)
	tw.tween_property(node, "scale", node.scale * 0.92, 0.26)
	tw.chain().tween_callback(node.queue_free)


func _toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_toast_label, "modulate:a", 1.0, 0.12)
	tw.tween_interval(1.0)
	tw.tween_property(_toast_label, "modulate:a", 0.0, 0.3)


func _log_line(text: String, color: Color) -> void:
	var ink := color.darkened(0.55)
	ink.a = 1.0
	_log_lines.append("[color=#%s]%s[/color]" % [ink.to_html(false), text])
	if _log_lines.size() > 40:
		_log_lines.pop_front()
	_log_label.text = "\n".join(_log_lines)
	_log_label.scroll_to_line(maxi(0, _log_label.get_line_count() - 1))


func _card_name(card_id: String) -> String:
	return str(CardDB.card(card_id).get("name", card_id))


func _on_card_hover(view: CardView, hovered: bool) -> void:
	if view.card == null:
		return
	var id: int = view.card.instance_id
	if not _hand_base.has(id):
		return
	var base: Vector2 = _hand_base[id]
	var target := base - Vector2(0, 62) if hovered else base
	var idx: int = state.players[0].hand.find(view.card)
	view.z_index = 60 if hovered else 10 + maxi(idx, 0)
	create_tween().tween_property(view, "position", target, 0.1) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_minion_hover(view: MinionView, hovered: bool) -> void:
	if hovered:
		_show_tooltip(view.instance)
	else:
		_hide_tooltip()


func _show_tooltip(inst: CardInstance) -> void:
	_hide_tooltip()
	var v := CardView.new()
	v.setup(inst, false)
	v.scale = Vector2(1.1, 1.1)
	_tooltip = v
	_fx_layer.add_child(v)
	var mouse := get_global_mouse_position()
	var pos := mouse + Vector2(28, -150)
	pos.x = clampf(pos.x, 10, 1600 - 220)
	pos.y = clampf(pos.y, 10, 900 - 310)
	v.position = pos
	v.z_index = 900


func _hide_tooltip() -> void:
	if _tooltip != null and is_instance_valid(_tooltip):
		_tooltip.queue_free()
	_tooltip = null


# ================================================================== mulligan
func _begin_mulligan() -> void:
	_busy = true
	_mulligan_overlay = Control.new()
	_mulligan_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mulligan_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_layer.add_child(_mulligan_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.035, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_mulligan_overlay.add_child(dim)
	_hand_layer.visible = false

	var title := UITheme.outline_label("选择要换掉的牌", 40, UITheme.GOLD, 10)
	title.position = Vector2(0, 100)
	title.size = Vector2(1600, 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mulligan_overlay.add_child(title)

	var sub := UITheme.label("点击卡牌标记换牌，换掉的牌会重新抽取", 16, UITheme.MUTED, false)
	sub.position = Vector2(0, 158)
	sub.size = Vector2(1600, 28)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mulligan_overlay.add_child(sub)

	var hand: Array = state.players[0].hand
	var n := hand.size()
	var spacing := 220.0
	for i in n:
		var card: CardInstance = hand[i]
		var v := CardView.new()
		v.setup(card, false)
		v.position = Vector2(800 + (i - (n - 1) * 0.5) * spacing - 95, 250)
		_mulligan_overlay.add_child(v)
		_mulligan_cards[card.instance_id] = v

		var btn := Button.new()
		btn.position = v.position
		btn.size = CardView.CARD_SIZE
		btn.flat = true
		btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		btn.pressed.connect(_toggle_mulligan.bind(card.instance_id))
		_mulligan_overlay.add_child(btn)

	var confirm := Button.new()
	confirm.text = "开始对战"
	confirm.position = Vector2(650, 610)
	confirm.size = Vector2(300, 62)
	confirm.add_theme_font_size_override("font_size", 22)
	confirm.add_theme_stylebox_override("normal",
		UITheme.panel_style(Color("2a2118"), UITheme.GOLD, 2, 12, 8))
	confirm.add_theme_stylebox_override("hover",
		UITheme.panel_style(Color("3a2d1f"), Color("ffe0a0"), 2, 12, 8))
	confirm.pressed.connect(_confirm_mulligan)
	_mulligan_overlay.add_child(confirm)

	var tip := UITheme.label("保留低费牌通常更稳；高费牌可以换掉寻找前期节奏。", 14,
		Color(UITheme.MUTED, 0.9), false)
	tip.position = Vector2(0, 690)
	tip.size = Vector2(1600, 24)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mulligan_overlay.add_child(tip)


func _toggle_mulligan(instance_id: int) -> void:
	Sfx.ui_click()
	if _mulligan_selected.has(instance_id):
		_mulligan_selected.erase(instance_id)
	else:
		_mulligan_selected[instance_id] = true
	var v: CardView = _mulligan_cards.get(instance_id)
	if v == null:
		return
	var selected := _mulligan_selected.has(instance_id)
	v.modulate = Color(0.6, 0.55, 0.55, 1) if selected else Color.WHITE
	for child in v.get_children():
		if child is Label and child.name == "MulliganMark":
			child.visible = selected
	if not selected:
		for child in v.get_children():
			if child is Label and child.name == "MulliganMark":
				child.queue_free()
		return
	if selected:
		var mark := UITheme.outline_label("换", 22, Color("ff9b8a"), 6)
		mark.name = "MulliganMark"
		mark.position = Vector2(140, 8)
		mark.size = Vector2(40, 36)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(mark)


func _confirm_mulligan() -> void:
	Sfx.ui_click()
	var indices: Array = []
	var hand: Array = state.players[0].hand
	for i in hand.size():
		if _mulligan_selected.has(hand[i].instance_id):
			indices.append(i)
	_mulligan_overlay.queue_free()
	_mulligan_overlay = null
	_busy = true
	state.mulligan(0, indices)
	await _play_events(state.take_events())
	_sync_all()
	_hand_layer.visible = true
	_busy = false
	_update_interaction()
	_hint_label.text = "拖拽手牌出牌 · 拖拽随从攻击"
	_hint_label.visible = true


# ================================================================== demo
func start_demo() -> void:
	if shot_dir == "":
		return
	await get_tree().create_timer(0.6).timeout
	await _capture("02_mulligan")
	await _confirm_mulligan()
	await get_tree().create_timer(0.7).timeout
	await _capture("03_battle")
	var demo_ai := AIController.new(state, 0)
	var rounds := 0
	while state.phase == Enums.PHASE_PLAYING and rounds < 9:
		rounds += 1
		demo_ai.start_turn()
		var guard := 0
		while state.phase == Enums.PHASE_PLAYING and state.current == 0 and guard < 5:
			guard += 1
			var a: Dictionary = demo_ai.take_action()
			if a.get("type", "end") == "end":
				break
			var ok := await _demo_apply(a)
			demo_ai.notify_result(ok)
			await get_tree().create_timer(0.35).timeout
		await _capture("04_turn_%02d" % rounds)
		if state.phase == Enums.PHASE_PLAYING:
			await _on_end_turn()
		await get_tree().create_timer(0.4).timeout
	await _capture("05_final")
	# 演示用：直接弹出结算面板，便于验收外观
	state.winner = 0
	_show_game_over()
	await get_tree().create_timer(0.6).timeout
	await _capture("06_game_over")
	get_tree().quit()


func _demo_apply(action: Dictionary) -> bool:
	# 出牌走玩家同一条路径，顺带验证飞牌动画
	if action.get("type", "") == "play":
		var idx: int = int(action.get("index", -1))
		if idx < 0 or idx >= state.players[0].hand.size():
			return false
		await _do_player_play(idx, int(action.get("target", 0)),
			int(action.get("position", -1)))
		return true
	_busy = true
	_update_interaction()
	var ok := false
	match action.get("type", ""):
		"attack":
			ok = state.attack(int(action.get("attacker", 0)), int(action.get("target", 0)))
		"hero_power":
			ok = state.use_hero_power(int(action.get("target", 0)))
	await _play_events(state.take_events())
	_sync_all()
	_busy = false
	_update_interaction()
	return ok


func _capture(name: String) -> void:
	if shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_dir + "/" + name + ".png")


# ================================================================== menus
func _open_menu() -> void:
	if _menu_overlay != null or _game_over_overlay != null or _busy:
		return
	Sfx.ui_click()
	_menu_overlay = Control.new()
	_menu_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_layer.add_child(_menu_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_overlay.add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(600, 250)
	panel.size = Vector2(400, 360)
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("11161f"), UITheme.GOLD, 2, 16, 14))
	_menu_overlay.add_child(panel)

	var title := UITheme.label("对局菜单", 26, UITheme.GOLD, true)
	title.position = Vector2(0, 28)
	title.size = Vector2(400, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var resume := Button.new()
	resume.text = "继续对局"
	resume.position = Vector2(75, 92)
	resume.size = Vector2(250, 52)
	resume.pressed.connect(_close_menu)
	panel.add_child(resume)

	var resign := Button.new()
	resign.text = "认输"
	resign.position = Vector2(75, 160)
	resign.size = Vector2(250, 52)
	resign.pressed.connect(func():
		_close_menu()
		state.winner = 1
		state.phase = Enums.PHASE_OVER
		_finish_game()
	)
	panel.add_child(resign)

	var back := Button.new()
	back.text = "返回主菜单"
	back.position = Vector2(75, 228)
	back.size = Vector2(250, 52)
	back.pressed.connect(func(): navigate.emit("menu", null))
	panel.add_child(back)


func _close_menu() -> void:
	if _menu_overlay != null:
		_menu_overlay.queue_free()
		_menu_overlay = null


func _finish_game() -> void:
	if _game_over_shown:
		return
	_game_over_shown = true
	_busy = true
	_update_interaction()
	await get_tree().create_timer(0.5).timeout
	_show_game_over()


func _show_game_over() -> void:
	_game_over_overlay = Control.new()
	_game_over_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_layer.add_child(_game_over_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over_overlay.add_child(dim)

	var win := state.winner == 0
	var draw := state.winner == -1
	var text := "胜利" if win else ("平局" if draw else "失败")
	var color := UITheme.GOLD if win else (UITheme.MUTED if draw else Color("e07a6a"))

	var panel := Panel.new()
	panel.position = Vector2(550, 230)
	panel.size = Vector2(500, 400)
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.PANEL, color, 2, 18, 18))
	_game_over_overlay.add_child(panel)

	var title := UITheme.outline_label(text, 62, color, 12)
	title.position = Vector2(0, 34)
	title.size = Vector2(500, 80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var detail := UITheme.label("第 %d 回合结束   ·   你 %d 点生命   ·   对手 %d 点生命" % [
		state.turn, state.players[0].hp, state.players[1].hp], 16, UITheme.MUTED, false)
	detail.position = Vector2(0, 126)
	detail.size = Vector2(500, 30)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(detail)

	var again := Button.new()
	again.text = "再来一局"
	again.position = Vector2(80, 200)
	again.size = Vector2(340, 56)
	again.add_theme_stylebox_override("normal",
		UITheme.panel_style(Color("2a2118"), color, 2, 12, 6))
	again.pressed.connect(func(): navigate.emit("battle", hero_class))
	panel.add_child(again)

	var back := Button.new()
	back.text = "返回主菜单"
	back.position = Vector2(80, 274)
	back.size = Vector2(340, 56)
	back.pressed.connect(func(): navigate.emit("menu", null))
	panel.add_child(back)

	_log_line(text, color)
