extends Control
## 应用入口：主题、背景与页面切换。

var _holder: Control
var _screen: Control
var _fade: ColorRect

var _demo := false
var _shot_dir := ""


func _ready() -> void:
	theme = UITheme.make()
	CustomCards.ensure_loaded()
	DeckStore.ensure_loaded()
	_parse_args()
	_build()
	show_main_menu()
	if _demo:
		_run_demo()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for a in args:
		if a == "--demo":
			_demo = true
		elif a.begins_with("--shot-dir="):
			_shot_dir = a.substr("--shot-dir=".length())
	if _shot_dir != "":
		DirAccess.make_dir_recursive_absolute(_shot_dir)


func _run_demo() -> void:
	await get_tree().create_timer(0.8).timeout
	await _capture("00_menu")
	show_hero_select()
	await get_tree().create_timer(0.6).timeout
	await _capture("01_hero_select")
	show_collection()
	await get_tree().create_timer(0.6).timeout
	await _capture("01b_collection")
	show_decks()
	await get_tree().create_timer(0.6).timeout
	await _capture("01c_decks")
	show_custom_cards()
	await get_tree().create_timer(0.8).timeout
	await _capture("01d_custom")
	if _screen is CardEditorScreen:
		_screen.demo_fill()
		await get_tree().create_timer(0.5).timeout
		await _capture("01e_custom_fx")
	var b := BattleScreen.new()
	b.hero_class = "MAGE"
	b.shot_dir = _shot_dir
	_switch(b)
	b.start_demo()


func _capture(name: String) -> void:
	if _shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_dir + "/" + name + ".png")


func _build() -> void:
	var bg := Backdrop.new()
	add_child(bg)

	_holder = Control.new()
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _switch(screen: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = screen
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_holder.add_child(screen)
	if screen.has_signal("navigate"):
		screen.navigate.connect(_on_navigate)


func _on_navigate(target: String, data: Variant = null) -> void:
	match target:
		"menu":
			show_main_menu()
		"select":
			show_hero_select()
		"collection":
			show_collection()
		"decks":
			show_decks()
		"custom":
			show_custom_cards()
		"battle":
			if typeof(data) == TYPE_DICTIONARY:
				start_battle(str(data.get("hero_class", "MAGE")), data.get("deck", []))
			else:
				start_battle(str(data))
		"quit":
			get_tree().quit()


func show_main_menu() -> void:
	var s := MainMenuScreen.new()
	_switch(s)


func show_hero_select() -> void:
	_switch(HeroSelectScreen.new())


func show_collection() -> void:
	_switch(CollectionScreen.new())


func show_decks() -> void:
	_switch(DeckScreen.new())


func show_custom_cards() -> void:
	_switch(CardEditorScreen.new())


func start_battle(hero_class: String, deck_cards: Array = []) -> void:
	var b := BattleScreen.new()
	b.hero_class = hero_class
	b.deck_cards = deck_cards
	_switch(b)
