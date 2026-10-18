class_name CollectionScreen
extends Control
## 卡牌图鉴：100 张卡牌按职业筛选、按费用排序。

signal navigate(target: String, data: Variant)

var _grid: GridContainer
var _filter := "ALL"
var _count_label: Label
var _filter_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var title := UITheme.outline_label("卡牌图鉴", 40, UITheme.GOLD, 9)
	title.position = Vector2(120, 44)
	title.size = Vector2(400, 56)
	add_child(title)

	_count_label = UITheme.label("", 16, UITheme.MUTED, false)
	_count_label.position = Vector2(330, 62)
	_count_label.size = Vector2(400, 26)
	add_child(_count_label)

	var filters := [["ALL", "全部"], ["NEUTRAL", "中立"], ["MAGE", "法师"],
		["WARRIOR", "战士"], ["PALADIN", "圣骑士"]]
	var x := 120.0
	for f in filters:
		var b := Button.new()
		b.text = f[1]
		b.position = Vector2(x, 112)
		b.size = Vector2(110, 40)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_set_filter.bind(f[0]))
		add_child(b)
		_filter_buttons[f[0]] = b
		x += 120

	var back := Button.new()
	back.text = "返回主菜单"
	back.position = Vector2(1310, 46)
	back.size = Vector2(180, 48)
	back.pressed.connect(func(): navigate.emit("menu", null))
	add_child(back)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(120, 176)
	scroll.size = Vector2(1360, 676)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 20)
	scroll.add_child(_grid)

	_rebuild()


func _set_filter(value: String) -> void:
	_filter = value
	_rebuild()


func _rebuild() -> void:
	for child in _grid.get_children():
		child.queue_free()
	for key in _filter_buttons:
		_filter_buttons[key].button_pressed = key == _filter
	var cards := CardDB.all_cards()
	cards.sort_custom(func(a, b):
		if int(a.get("cost", 0)) == int(b.get("cost", 0)):
			return a["name"] < b["name"]
		return int(a.get("cost", 0)) < int(b.get("cost", 0))
	)
	var shown := 0
	for c in cards:
		if _filter != "ALL" and c.get("class", "NEUTRAL") != _filter:
			continue
		shown += 1
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(206, 296)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var inst := CardInstance.new()
		inst.setup(1, c["id"], -1)
		var view := CardView.new()
		view.setup(inst, true)
		view.position = Vector2(8, 8)
		cell.add_child(view)
		_grid.add_child(cell)
	_count_label.text = "共 %d 张  ·  当前显示 %d 张" % [cards.size(), shown]
