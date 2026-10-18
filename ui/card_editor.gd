class_name CardEditorScreen
extends Control
## 自定义卡牌：左侧卡牌库（含官方卡，可覆盖编辑），中间实时卡面预览，右侧属性表单。

signal navigate(target: String, data: Variant)

const LIST_X := 40.0
const LIST_W := 292.0
const PREVIEW_X := 356.0
const FORM_X := 596.0
const FORM_W := 960.0
const TOP_Y := 108.0
const BODY_H := 742.0

var _spec: Dictionary = {}
var _editing_id := ""
var _search := ""
var _text_manual := false
var _updating := false

var _list_box: VBoxContainer
var _list_search: LineEdit
var _preview_holder: Control
var _preview: CardView
var _preview_type := ""
var _status: Label

var _name_edit: LineEdit
var _type_opt: OptionButton
var _class_opt: OptionButton
var _rarity_opt: OptionButton
var _race_opt: OptionButton
var _target_opt: OptionButton
var _cost_spin: SpinBox
var _atk_spin: SpinBox
var _hp_spin: SpinBox
var _stat_row: Control
var _keyword_checks: Dictionary = {}
var _effect_box: VBoxContainer
var _text_edit: TextEdit
var _art_thumb: TextureRect
var _art_picker: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	CustomCards.ensure_loaded()
	_build()
	_new_card()
	_rebuild_library()


# ================================================================== 布局
func _build() -> void:
	var back := Button.new()
	back.text = "← 返回"
	back.position = Vector2(40, 26)
	back.size = Vector2(112, 44)
	back.add_theme_font_size_override("font_size", 16)
	back.pressed.connect(func(): navigate.emit("menu", null))
	add_child(back)

	var title := UITheme.outline_label("自定义卡牌", 38, UITheme.GOLD, 8)
	title.position = Vector2(176, 16)
	title.size = Vector2(400, 56)
	add_child(title)

	var sub := UITheme.label("自由设定费用、攻防、种族与效果 · 保存后立即进入卡池，可组进卡组",
		15, UITheme.MUTED, false)
	sub.position = Vector2(420, 38)
	sub.size = Vector2(760, 26)
	add_child(sub)

	_build_library()
	_build_preview()
	_build_form()


# ------------------------------------------------------------------ 左：卡牌库
func _build_library() -> void:
	_panel(Vector2(LIST_X, TOP_Y), Vector2(LIST_W, BODY_H))
	var head := UITheme.label("卡牌库", 15, UITheme.GOLD, true)
	head.position = Vector2(LIST_X + 14, TOP_Y + 10)
	head.size = Vector2(200, 22)
	add_child(head)

	_list_search = LineEdit.new()
	_list_search.placeholder_text = "搜索…"
	_list_search.position = Vector2(LIST_X + 12, TOP_Y + 36)
	_list_search.size = Vector2(LIST_W - 24, 32)
	_list_search.add_theme_font_size_override("font_size", 14)
	_list_search.text_changed.connect(func(t):
		_search = t.strip_edges()
		_rebuild_library()
	)
	add_child(_list_search)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(LIST_X + 8, TOP_Y + 76)
	scroll.size = Vector2(LIST_W - 16, BODY_H - 140)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.custom_minimum_size = Vector2(LIST_W - 30, 0)
	_list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_list_box)

	var new_btn := Button.new()
	new_btn.text = "＋ 新建卡牌"
	new_btn.position = Vector2(LIST_X + 12, TOP_Y + BODY_H - 54)
	new_btn.size = Vector2(LIST_W - 24, 44)
	new_btn.add_theme_font_size_override("font_size", 16)
	new_btn.pressed.connect(func():
		_new_card()
		if Sfx != null:
			Sfx.ui_click()
	)
	add_child(new_btn)


func _rebuild_library() -> void:
	_clear(_list_box)
	var mine := CustomCards.all_defs()
	var mine_ids := {}
	for d in mine:
		mine_ids[str(d["id"])] = true
	if not mine.is_empty():
		_list_box.add_child(_group_label("我的卡牌 · %d" % mine.size()))
		for d in mine:
			if _match_search(d):
				_list_box.add_child(_list_item(d, true))
	var official: Array = []
	for c in CardDB.all_cards():
		var cid := str(c["id"])
		if CardDB.is_custom(cid):
			continue
		official.append(c)
	official.sort_custom(func(a, b):
		var ca := int(a.get("cost", 0))
		var cb := int(b.get("cost", 0))
		if ca == cb:
			return str(a.get("name", "")) < str(b.get("name", ""))
		return ca < cb
	)
	_list_box.add_child(_group_label("官方卡牌 · %d" % official.size()))
	for c in official:
		if _match_search(c):
			_list_box.add_child(_list_item(c, false))


func _match_search(def: Dictionary) -> bool:
	if _search == "":
		return true
	return str(def.get("name", "")).contains(_search)


func _group_label(text: String) -> Control:
	var l := UITheme.label(text, 13, Color(UITheme.GOLD, 0.85), true)
	l.custom_minimum_size = Vector2(LIST_W - 30, 24)
	return l


func _list_item(def: Dictionary, custom: bool) -> Control:
	var cid := str(def["id"])
	var active := cid == _editing_id
	var b := Button.new()
	b.custom_minimum_size = Vector2(LIST_W - 30, 46)
	b.add_theme_stylebox_override("normal", _item_style(active, false))
	b.add_theme_stylebox_override("hover", _item_style(active, true))
	b.add_theme_stylebox_override("pressed", _item_style(active, true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func(): _load_card.call_deferred(cid))

	var tag := "★ " if custom else ""
	var name_lbl := UITheme.label(tag + str(def.get("name", "")), 14,
		UITheme.TEXT if active else Color(UITheme.MUTED, 0.95), active)
	name_lbl.position = Vector2(10, 4)
	name_lbl.size = Vector2(180, 20)
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(name_lbl)

	var meta_text := "%d 费" % int(def.get("cost", 0))
	if str(def.get("type", "MINION")) == "MINION":
		meta_text += "  %d/%d" % [int(def.get("attack", 0)), int(def.get("health", 1))]
	else:
		meta_text += "  法术"
	var meta := UITheme.label(meta_text, 12, Color(UITheme.MUTED, 0.85), false)
	meta.position = Vector2(10, 24)
	meta.size = Vector2(200, 18)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(meta)

	var dot := ColorRect.new()
	dot.color = CardDB.class_color(str(def.get("class", "NEUTRAL")))
	dot.position = Vector2(0, 0)
	dot.size = Vector2(3, 46)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(dot)
	return b


func _item_style(active: bool, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1d2634") if active else (Color("171e29") if not hover
		else Color("1a222e"))
	sb.set_corner_radius_all(8)
	sb.border_color = UITheme.GOLD if active else Color(0, 0, 0, 0.35)
	sb.set_border_width_all(1)
	return sb


# ------------------------------------------------------------------ 中：预览
func _build_preview() -> void:
	var frame := Panel.new()
	frame.position = Vector2(PREVIEW_X, TOP_Y)
	frame.size = Vector2(220, BODY_H)
	frame.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0.06, 0.075, 0.10, 0.86), Color(UITheme.GOLD_DIM, 0.55), 1, 14, 10))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	var head := UITheme.label("实时预览", 14, UITheme.GOLD, true)
	head.position = Vector2(PREVIEW_X + 14, TOP_Y + 10)
	head.size = Vector2(160, 22)
	add_child(head)

	_preview_holder = Control.new()
	_preview_holder.position = Vector2(PREVIEW_X + 10, TOP_Y + 40)
	_preview_holder.size = Vector2(200, 300)
	_preview_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_preview_holder)

	# 美术：缩略图 + 两个按钮
	var art_label := UITheme.label("卡图", 13, Color(UITheme.GOLD, 0.85), true)
	art_label.position = Vector2(PREVIEW_X + 14, TOP_Y + 366)
	art_label.size = Vector2(80, 20)
	add_child(art_label)

	_art_thumb = UITheme.rounded_art(null, Vector2(190, 96), 8.0)
	_art_thumb.position = Vector2(PREVIEW_X + 15, TOP_Y + 390)
	_art_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art_thumb)

	var pick := Button.new()
	pick.text = "更换卡图"
	pick.position = Vector2(PREVIEW_X + 15, TOP_Y + 494)
	pick.size = Vector2(190, 38)
	pick.add_theme_font_size_override("font_size", 14)
	pick.pressed.connect(_open_art_picker)
	add_child(pick)

	var import_btn := Button.new()
	import_btn.text = "从电脑导入图片…"
	import_btn.position = Vector2(PREVIEW_X + 15, TOP_Y + 538)
	import_btn.size = Vector2(190, 38)
	import_btn.add_theme_font_size_override("font_size", 14)
	import_btn.pressed.connect(_open_file_dialog)
	add_child(import_btn)

	_status = UITheme.label("", 12, Color(UITheme.MUTED, 0.9), false)
	_status.position = Vector2(PREVIEW_X + 12, TOP_Y + 592)
	_status.size = Vector2(196, 60)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	var hint := UITheme.label("提示：官方卡也可直接改，\n保存后覆盖生效，可随时恢复。",
		12, Color(UITheme.MUTED, 0.7), false)
	hint.position = Vector2(PREVIEW_X + 12, TOP_Y + 664)
	hint.size = Vector2(196, 60)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)


func _panel(pos: Vector2, size: Vector2) -> void:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0.06, 0.075, 0.10, 0.86), Color(UITheme.GOLD_DIM, 0.55), 1, 14, 10))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)


# ------------------------------------------------------------------ 右：表单
func _build_form() -> void:
	_panel(Vector2(FORM_X, TOP_Y), Vector2(FORM_W, BODY_H))

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(FORM_X + 16, TOP_Y + 14)
	scroll.size = Vector2(FORM_W - 32, BODY_H - 92)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(FORM_W - 56, 0)
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	# 名称
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "输入卡牌名称（最多 12 字）"
	_name_edit.max_length = CustomCards.MAX_NAME_LEN
	_name_edit.add_theme_font_size_override("font_size", 17)
	_name_edit.text_changed.connect(func(_t): _on_form_changed())
	box.add_child(_labeled("卡牌名称", _name_edit, 320))

	# 类型 / 职业 / 稀有度
	_type_opt = _option([["MINION", "随从"], ["SPELL", "法术"]], "MINION",
		func(v): _on_type_changed(v))
	_class_opt = _option(_class_items(), "NEUTRAL", func(v):
		_spec["class"] = v
		_on_form_changed()
	)
	_rarity_opt = _option([["COMMON", "普通"], ["RARE", "稀有"], ["EPIC", "史诗"],
		["LEGENDARY", "传说"]], "COMMON", func(v):
		_spec["rarity"] = v
		_on_form_changed()
	)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 18)
	row1.add_child(_inline("类型", _type_opt, 130))
	row1.add_child(_inline("职业", _class_opt, 130))
	row1.add_child(_inline("稀有度", _rarity_opt, 130))
	box.add_child(row1)

	# 费用 / 攻击 / 生命 / 种族
	_cost_spin = _spin(0, 10, 2, func(v):
		_spec["cost"] = int(v)
		_on_form_changed()
	)
	_atk_spin = _spin(0, 30, 2, func(v):
		_spec["attack"] = int(v)
		_on_form_changed()
	)
	_hp_spin = _spin(1, 30, 2, func(v):
		_spec["health"] = int(v)
		_on_form_changed()
	)
	_race_opt = _option(_race_items(), "", func(v):
		_spec["race"] = v
		_on_form_changed()
	)
	_stat_row = HBoxContainer.new()
	_stat_row.add_theme_constant_override("separation", 18)
	_stat_row.add_child(_inline("费用", _cost_spin, 96))
	_stat_row.add_child(_inline("攻击力", _atk_spin, 96))
	_stat_row.add_child(_inline("生命值", _hp_spin, 96))
	_stat_row.add_child(_inline("种族", _race_opt, 130))
	box.add_child(_stat_row)

	# 关键字
	box.add_child(_section("关键字"))
	var kw_row := HFlowContainer.new()
	kw_row.add_theme_constant_override("h_separation", 14)
	kw_row.add_theme_constant_override("v_separation", 4)
	for k in CustomCards.KEYWORDS:
		var cb := CheckBox.new()
		cb.text = k[1]
		cb.add_theme_font_size_override("font_size", 14)
		cb.toggled.connect(func(on):
			if _updating:
				return
			var words: Array = _spec.get("keywords", []).duplicate()
			if on:
				if not words.has(k[0]):
					words.append(k[0])
			else:
				words.erase(k[0])
			_spec["keywords"] = words
			_on_form_changed()
		)
		kw_row.add_child(cb)
		_keyword_checks[k[0]] = cb
	box.add_child(kw_row)

	# 目标范围
	_target_opt = _option(CustomCards.TARGET_MODES, "", func(v):
		_spec["target_mode"] = v
		_on_form_changed()
	)
	box.add_child(_labeled("选择目标", _target_opt, 260))

	# 效果
	var eff_head := HBoxContainer.new()
	eff_head.add_theme_constant_override("separation", 12)
	var eff_title := UITheme.label("卡牌效果", 15, UITheme.GOLD, true)
	eff_title.custom_minimum_size = Vector2(120, 26)
	eff_head.add_child(eff_title)
	var add_eff := Button.new()
	add_eff.text = "＋ 添加效果"
	add_eff.add_theme_font_size_override("font_size", 14)
	add_eff.pressed.connect(_add_effect_row)
	eff_head.add_child(add_eff)
	box.add_child(eff_head)

	_effect_box = VBoxContainer.new()
	_effect_box.add_theme_constant_override("separation", 6)
	box.add_child(_effect_box)

	# 描述
	box.add_child(_section("卡牌文字"))
	_text_edit = TextEdit.new()
	_text_edit.custom_minimum_size = Vector2(FORM_W - 56, 96)
	_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text_edit.add_theme_font_size_override("font_size", 14)
	_text_edit.text_changed.connect(func():
		if _updating:
			return
		_text_manual = true
		_spec["text"] = _text_edit.text
		_refresh_preview()
	)
	box.add_child(_text_edit)

	var text_tools := HBoxContainer.new()
	text_tools.add_theme_constant_override("separation", 10)
	var regen := Button.new()
	regen.text = "按效果重新生成"
	regen.add_theme_font_size_override("font_size", 13)
	regen.pressed.connect(func():
		_text_manual = false
		_suggest_text(true)
	)
	text_tools.add_child(regen)
	var hint2 := UITheme.label("留空或点左侧按钮会自动按效果生成文字", 12,
		Color(UITheme.MUTED, 0.75), false)
	hint2.custom_minimum_size = Vector2(360, 24)
	text_tools.add_child(hint2)
	box.add_child(text_tools)

	# 底部操作条固定在外层，滚动时也可见（见 _build_footer_bar）
	add_child(_build_footer_bar())


func _build_footer_bar() -> Control:
	# 底部固定在面板外的操作条（滚动时也可见）
	var holder := Control.new()
	holder.position = Vector2(FORM_X + 16, TOP_Y + BODY_H - 68)
	holder.size = Vector2(FORM_W - 32, 54)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := Panel.new()
	bg.position = Vector2.ZERO
	bg.size = holder.size
	bg.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color(0.05, 0.06, 0.085, 0.95), Color(UITheme.GOLD_DIM, 0.45), 1, 10))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)

	var save := Button.new()
	save.text = "保存卡牌"
	save.position = Vector2(10, 6)
	save.size = Vector2(180, 42)
	save.add_theme_font_size_override("font_size", 17)
	save.add_theme_stylebox_override("normal",
		UITheme.panel_style(Color("1e3a2a"), Color("7ed49a"), 2, 10))
	save.add_theme_stylebox_override("hover",
		UITheme.panel_style(Color("24503a"), Color("a6f0c0"), 2, 10))
	save.pressed.connect(_save)
	holder.add_child(save)

	var restore := Button.new()
	restore.text = "恢复默认 / 删除"
	restore.position = Vector2(200, 6)
	restore.size = Vector2(170, 42)
	restore.add_theme_font_size_override("font_size", 14)
	restore.pressed.connect(_restore)
	holder.add_child(restore)

	var dup := Button.new()
	dup.text = "另存为副本"
	dup.position = Vector2(380, 6)
	dup.size = Vector2(140, 42)
	dup.add_theme_font_size_override("font_size", 14)
	dup.pressed.connect(_duplicate)
	holder.add_child(dup)

	var note := UITheme.label("保存后立即生效，可在「我的卡组」里加进卡组", 13,
		Color(UITheme.MUTED, 0.8), false)
	note.position = Vector2(540, 14)
	note.size = Vector2(400, 24)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(note)
	return holder


# ------------------------------------------------------------------ 控件工厂
func _labeled(text: String, ctrl: Control, width: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UITheme.label(text, 15, UITheme.GOLD, true)
	l.custom_minimum_size = Vector2(120, 30)
	row.add_child(l)
	ctrl.custom_minimum_size = Vector2(width, 34)
	row.add_child(ctrl)
	return row


func _inline(text: String, ctrl: Control, width: float) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var l := UITheme.label(text, 14, Color(UITheme.GOLD, 0.92), true)
	l.custom_minimum_size = Vector2(58, 30)
	box.add_child(l)
	ctrl.custom_minimum_size = Vector2(width, 34)
	box.add_child(ctrl)
	return box


func _section(text: String) -> Control:
	var l := UITheme.label(text, 15, UITheme.GOLD, true)
	l.custom_minimum_size = Vector2(FORM_W - 56, 26)
	return l


func _option(items: Array, current: String, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", 14)
	var idx := 0
	for i in items.size():
		o.add_item(str(items[i][1]), i)
		o.set_item_metadata(i, str(items[i][0]))
		if str(items[i][0]) == current:
			idx = i
	o.select(idx)
	o.item_selected.connect(func(i):
		cb.call(str(o.get_item_metadata(i)))
	)
	return o


func _spin(min_v: int, max_v: int, value: int, cb: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = 1
	s.value = value
	s.allow_greater = false
	s.allow_lesser = false
	var le := s.get_line_edit()
	if le != null:
		le.add_theme_font_size_override("font_size", 15)
		le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.value_changed.connect(func(v): cb.call(int(v)))
	return s


func _class_items() -> Array:
	return [["NEUTRAL", "中立"], ["MAGE", "法师"], ["WARRIOR", "战士"], ["PALADIN", "圣骑士"]]


func _race_items() -> Array:
	var out: Array = [["", "无"]]
	for key in CardDB.RACE_NAMES:
		if key != "":
			out.append([key, CardDB.RACE_NAMES[key]])
	out.append(["ALL", "全部"])
	return out


# ================================================================== 效果行
func _add_effect_row() -> void:
	var rows: Array = _spec.get("effects", [])
	rows.append(CustomCards.blank_effect_row(str(_spec.get("type", "MINION")) == "SPELL"))
	_spec["effects"] = rows
	_rebuild_effect_rows()
	_text_manual = false
	_suggest_text(false)
	_refresh_preview()


func _remove_effect_row(index: int) -> void:
	var rows: Array = _spec.get("effects", [])
	if index < 0 or index >= rows.size():
		return
	rows.remove_at(index)
	_spec["effects"] = rows
	_rebuild_effect_rows()
	_text_manual = false
	_suggest_text(false)
	_refresh_preview()


func _rebuild_effect_rows() -> void:
	_clear(_effect_box)
	var rows: Array = _spec.get("effects", [])
	if rows.is_empty():
		var hint := UITheme.label("暂无效果 · 随从默认只有身材，法术建议至少加一条效果", 13,
			Color(UITheme.MUTED, 0.7), false)
		hint.custom_minimum_size = Vector2(FORM_W - 56, 26)
		_effect_box.add_child(hint)
		return
	for i in rows.size():
		_effect_box.add_child(_make_effect_row(rows[i], i))


func _make_effect_row(row: Dictionary, index: int) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var idx_lbl := UITheme.label("%d" % (index + 1), 13, Color(UITheme.MUTED, 0.7), true)
	idx_lbl.custom_minimum_size = Vector2(18, 32)
	idx_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(idx_lbl)

	# 触发时机
	var trig := _option(_trigger_items(), str(row.get("trigger", "battlecry")),
		_setter(row, "trigger"))
	trig.custom_minimum_size = Vector2(112, 32)
	trig.add_theme_font_size_override("font_size", 13)
	box.add_child(trig)

	# 动作
	var act := _option(_action_items(), str(row.get("do", "damage")), _on_action_changed.bind(row))
	act.custom_minimum_size = Vector2(126, 32)
	act.add_theme_font_size_override("font_size", 13)
	box.add_child(act)

	for field in _fields_of(str(row.get("do", "damage"))):
		box.add_child(_field_control(row, field))

	var del := Button.new()
	del.text = "×"
	del.custom_minimum_size = Vector2(32, 32)
	del.add_theme_font_size_override("font_size", 15)
	del.pressed.connect(func(): _remove_effect_row(index))
	box.add_child(del)
	return box


func _trigger_items() -> Array:
	var out: Array = []
	for t in CustomCards.TRIGGERS:
		out.append([t[0], t[1]])
	return out


func _action_items() -> Array:
	var out: Array = []
	for a in CustomCards.ACTIONS:
		out.append([a["id"], a["name"]])
	return out


func _fields_of(action_id: String) -> Array:
	for a in CustomCards.ACTIONS:
		if a["id"] == action_id:
			return a["fields"]
	return []


func _setter(row: Dictionary, key: String) -> Callable:
	return func(v): _assign(row, key, v)


func _assign(row: Dictionary, key: String, value) -> void:
	row[key] = str(value)
	_on_form_changed()


func _on_action_changed(value: String, row: Dictionary) -> void:
	row["do"] = value
	_rebuild_effect_rows()
	_text_manual = false
	_suggest_text(false)
	_refresh_preview()


func _field_control(row: Dictionary, field: String) -> Control:
	match field:
		"amount":
			return _field_spin(row, "amount", "数值", 1, 30, 70)
		"atk":
			return _field_spin(row, "atk", "攻击", 0, 20, 70)
		"hp":
			return _field_spin(row, "hp", "生命", 0, 20, 70)
		"count":
			if str(row.get("do", "")) == "summon":
				return _field_spin(row, "count", "数量", 1, 7, 70)
			return _field_spin(row, "count", "次数", 1, 10, 70)
		"to":
			var o := _option(CustomCards.TARGETS, str(row.get("to", "chosen")),
				_setter(row, "to"))
			o.custom_minimum_size = Vector2(160, 32)
			o.add_theme_font_size_override("font_size", 12)
			return o
		"who":
			var w := _option([["owner", "我方"], ["opponent", "对手"], ["both", "双方"]],
				str(row.get("who", "owner")), _setter(row, "who"))
			w.custom_minimum_size = Vector2(96, 32)
			w.add_theme_font_size_override("font_size", 12)
			return w
		"pool":
			var p := _option(CustomCards.POOLS, str(row.get("pool", "enemy_characters")),
				_setter(row, "pool"))
			p.custom_minimum_size = Vector2(160, 32)
			p.add_theme_font_size_override("font_size", 12)
			return p
		"keyword":
			var k := _option(CustomCards.KEYWORDS, str(row.get("keyword", "TAUNT")),
				_setter(row, "keyword"))
			k.custom_minimum_size = Vector2(110, 32)
			k.add_theme_font_size_override("font_size", 12)
			return k
		"token":
			var items: Array = []
			for t in CardDB.tokens():
				items.append([str(t["id"]), str(t.get("name", t["id"]))])
			if items.is_empty():
				items.append(["", "（无可用衍生牌）"])
			var tok := _option(items, str(row.get("token", "")), _setter(row, "token"))
			tok.custom_minimum_size = Vector2(170, 32)
			tok.add_theme_font_size_override("font_size", 12)
			return tok
	return Control.new()


func _field_spin(row: Dictionary, key: String, label: String, min_v: int, max_v: int,
		width: float) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var l := UITheme.label(label, 12, Color(UITheme.MUTED, 0.9), false)
	l.custom_minimum_size = Vector2(34, 26)
	box.add_child(l)
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = 1
	s.value = int(row.get(key, min_v))
	var le := s.get_line_edit()
	if le != null:
		le.add_theme_font_size_override("font_size", 13)
		le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.value_changed.connect(func(v):
		row[key] = int(v)
		_on_form_changed()
	)
	s.custom_minimum_size = Vector2(width, 32)
	box.add_child(s)
	return box


# ================================================================== 数据
func _new_card() -> void:
	_editing_id = ""
	_spec = CustomCards.blank_spec(_default_art())
	_text_manual = false
	_load_spec_into_form()
	_status.text = "新建卡牌 · 尚未保存"


func _load_card(card_id: String) -> void:
	var def := CardDB.card(card_id)
	if def.is_empty():
		return
	_editing_id = card_id
	_spec = CustomCards.to_spec(def)
	_text_manual = true
	_load_spec_into_form()
	if CardDB.is_custom(card_id):
		_status.text = "编辑自定义卡 · %s" % card_id
	else:
		_status.text = "编辑官方卡 · 保存后覆盖（可恢复）"
	_rebuild_library()


func _default_art() -> String:
	var arts := CustomCards.builtin_arts()
	return arts[0] if not arts.is_empty() else ""


func _load_spec_into_form() -> void:
	_updating = true
	_name_edit.text = str(_spec.get("name", ""))
	_select_option(_type_opt, str(_spec.get("type", "MINION")))
	_select_option(_class_opt, str(_spec.get("class", "NEUTRAL")))
	_select_option(_rarity_opt, str(_spec.get("rarity", "COMMON")))
	_select_option(_race_opt, str(_spec.get("race", "")))
	_select_option(_target_opt, str(_spec.get("target_mode", "")))
	_cost_spin.value = int(_spec.get("cost", 1))
	_atk_spin.value = int(_spec.get("attack", 1))
	_hp_spin.value = int(_spec.get("health", 1))
	var words: Array = _spec.get("keywords", [])
	for k in _keyword_checks:
		_keyword_checks[k].button_pressed = words.has(k)
	_text_edit.text = str(_spec.get("text", ""))
	_rebuild_effect_rows()
	_update_stat_visibility()
	_update_art_thumb()
	_updating = false
	_refresh_preview()


func _select_option(opt: OptionButton, value: String) -> void:
	for i in opt.item_count:
		if str(opt.get_item_metadata(i)) == value:
			opt.select(i)
			return


func _update_stat_visibility() -> void:
	var is_minion := str(_spec.get("type", "MINION")) == "MINION"
	if _atk_spin != null:
		_atk_spin.editable = is_minion
	if _hp_spin != null:
		_hp_spin.editable = is_minion
	if _race_opt != null:
		_race_opt.disabled = not is_minion


func _on_type_changed(value: String) -> void:
	_spec["type"] = value
	_update_stat_visibility()
	for row in _spec.get("effects", []):
		if value == "SPELL" and str(row.get("trigger", "")) == "battlecry":
			row["trigger"] = "spell"
		elif value == "MINION" and str(row.get("trigger", "")) == "spell":
			row["trigger"] = "battlecry"
	_rebuild_effect_rows()
	_text_manual = false
	_suggest_text(false)
	_rebuild_preview()
	_refresh_preview()


func _on_form_changed() -> void:
	if _updating:
		return
	_spec["name"] = _name_edit.text
	if not _text_manual:
		_suggest_text(false)
	_refresh_preview()


func _suggest_text(force: bool) -> void:
	if not force and _text_manual:
		return
	var def := CustomCards.build(_spec)
	var text := str(def.get("text", ""))
	_updating = true
	_text_edit.text = text
	_spec["text"] = text
	_updating = false
	_refresh_preview()


func _refresh_preview() -> void:
	var def := CustomCards.build(_spec)
	if _preview == null or _preview_type != str(def.get("type", "MINION")):
		_rebuild_preview()
		return
	_preview.apply_def(def)


func _rebuild_preview() -> void:
	var def := CustomCards.build(_spec)
	if _preview != null and is_instance_valid(_preview):
		_preview_holder.remove_child(_preview)
		_preview.queue_free()
	if _preview_type != str(def.get("type", "MINION")) or _preview == null:
		_preview_type = str(def.get("type", "MINION"))
	_preview = CardView.new()
	_preview.setup_def(def, false)
	_preview.position = Vector2(5, 0)
	_preview_holder.add_child(_preview)


func _update_art_thumb() -> void:
	var tex := CardDB.texture(str(_spec.get("art", "")))
	_art_thumb.texture = tex


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# ================================================================== 保存
func _save() -> void:
	if _name_edit.text.strip_edges() == "":
		_status.text = "请先填写卡牌名称"
		if Sfx != null:
			Sfx.error()
		return
	_spec["name"] = _name_edit.text
	if _editing_id != "":
		_spec["id"] = _editing_id
	var def := CustomCards.build(_spec)
	if _editing_id == "":
		def["id"] = ""
	var stored := CustomCards.upsert(def)
	_editing_id = str(stored["id"])
	_spec = CustomCards.to_spec(stored)
	_text_manual = true
	_load_spec_into_form()
	_status.text = "已保存 · %s" % stored["name"]
	_rebuild_library()
	if Sfx != null:
		Sfx.spell(false)


func _restore() -> void:
	if _editing_id == "":
		_new_card()
		return
	var had_original := not CardDB.original(_editing_id).is_empty()
	CustomCards.erase(_editing_id)
	_rebuild_library()
	if had_original:
		_status.text = "已恢复官方原始卡"
		_load_card(_editing_id)
	else:
		_status.text = "已删除自定义卡"
		_new_card()


func _duplicate() -> void:
	_spec["name"] = _name_edit.text
	var def := CustomCards.build(_spec)
	def["id"] = ""
	def["name"] = str(def["name"]) + "·改"
	var stored := CustomCards.upsert(def)
	_editing_id = str(stored["id"])
	_spec = CustomCards.to_spec(stored)
	_text_manual = true
	_load_spec_into_form()
	_status.text = "已另存为 %s" % stored["name"]
	_rebuild_library()


# ================================================================== 卡图选择
func _open_art_picker() -> void:
	if _art_picker != null and is_instance_valid(_art_picker):
		_art_picker.queue_free()
		_art_picker = null
		return
	_art_picker = Control.new()
	_art_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_art_picker)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_open_art_picker()
	)
	_art_picker.add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(230, 90)
	panel.size = Vector2(1140, 720)
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("131a24"), Color(UITheme.GOLD, 0.7), 2, 16, 16))
	_art_picker.add_child(panel)

	var title := UITheme.outline_label("选择卡图", 24, UITheme.GOLD, 6)
	title.position = Vector2(260, 108)
	title.size = Vector2(300, 34)
	_art_picker.add_child(title)

	var close := Button.new()
	close.text = "关闭"
	close.position = Vector2(1250, 106)
	close.size = Vector2(96, 38)
	close.pressed.connect(_open_art_picker)
	_art_picker.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(260, 158)
	scroll.size = Vector2(1090, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_art_picker.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	for path in CustomCards.builtin_arts():
		var btn := TextureButton.new()
		btn.custom_minimum_size = Vector2(128, 76)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
		btn.texture_normal = CardDB.texture(path)
		btn.pressed.connect(func():
			_spec["art"] = path
			_update_art_thumb()
			_refresh_preview()
			_open_art_picker()
		)
		grid.add_child(btn)


func _open_file_dialog() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; 图片"])
	dlg.size = Vector2(900, 620)
	dlg.file_selected.connect(func(path):
		var stored := CustomCards.import_art(path)
		if stored == "":
			_status.text = "导入失败：仅支持 png / jpg / webp"
			return
		_spec["art"] = stored
		_update_art_thumb()
		_refresh_preview()
		_status.text = "卡图已导入"
	)
	add_child(dlg)
	dlg.popup_centered()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and (_art_picker == null or not is_instance_valid(_art_picker)):
			navigate.emit("menu", null)


## 演示模式下自动填一张示例卡，用来截「效果已配置」的界面。
func demo_fill() -> void:
	var art := "res://assets/art/CS2_029.webp"
	if not ResourceLoader.exists(art):
		var arts := CustomCards.builtin_arts()
		art = str(arts[0]) if not arts.is_empty() else ""
	_spec = CustomCards.blank_spec(art)
	_spec["name"] = "余烬火种"
	_spec["type"] = "SPELL"
	_spec["class"] = "MAGE"
	_spec["rarity"] = "RARE"
	_spec["cost"] = 3
	_spec["target_mode"] = "any"
	_spec["effects"] = [
		{"trigger": "spell", "do": "damage", "amount": 4, "to": "chosen", "atk": 1, "hp": 1,
			"count": 1, "who": "owner", "pool": "enemy_characters", "keyword": "TAUNT", "token": ""},
		{"trigger": "spell", "do": "freeze", "amount": 1, "to": "chosen", "atk": 1, "hp": 1,
			"count": 1, "who": "owner", "pool": "enemy_characters", "keyword": "TAUNT", "token": ""},
	]
	_text_manual = false
	_editing_id = ""
	_load_spec_into_form()
	_suggest_text(true)
	_status.text = "示例卡 · 未保存"
