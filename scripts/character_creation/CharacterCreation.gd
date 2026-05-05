## CharacterCreation.gd
## Drives the character creation scene: name, race, and class selection.
extends Control

# ─── UI References ──────────────────────────────────────────────────────────
@onready var name_input: LineEdit = $VBoxContainer/NameSection/NameInput
@onready var race_grid: GridContainer = $VBoxContainer/RaceSection/RaceGrid
@onready var class_grid: GridContainer = $VBoxContainer/ClassSection/ClassGrid
@onready var stat_panel: VBoxContainer = $VBoxContainer/StatsSection/StatPanel
@onready var points_label: Label = $VBoxContainer/StatsSection/PointsLabel
@onready var preview_panel: Panel = $PreviewPanel
@onready var main_vbox: VBoxContainer = $VBoxContainer
@onready var race_lore_label: Label = $PreviewPanel/VBox/LoreLabel
@onready var class_lore_label: Label = $PreviewPanel/VBox/ClassLoreLabel
@onready var passive_label: Label = $PreviewPanel/VBox/PassiveLabel
@onready var ability_list: VBoxContainer = $PreviewPanel/VBox/AbilityList
@onready var confirm_btn: Button = $ConfirmButton
@onready var portrait_rect: SubViewportContainer = $PreviewPanel/Portrait
@onready var preview_viewport: SubViewport = $PreviewPanel/Portrait/SubViewport
@onready var preview_model_root: Node3D = $PreviewPanel/Portrait/SubViewport/Model
@onready var preview_camera: Camera3D = $PreviewPanel/Portrait/SubViewport/Camera3D
@onready var appearance_picker: HBoxContainer = $VBoxContainer/AppearanceSection/AppearancePanel

# ─── Data ─────────────────────────────────────────────────────────────────────
var races: Array = []
var classes: Array = []
var selected_race_index: int = 0
var selected_class_index: int = 0
var stat_allocations: Dictionary = {"str": 0, "dex": 0, "int": 0, "con": 0, "wis": 0, "cha": 0}
var POINT_BUY_TOTAL: int = 27
var points_spent: int = 0

var appearance_config: Dictionary = {
	"muscle": 1.0,
	"skin_color": Color(0.85, 0.76, 0.68)
}

# Gender toggle button references so we can highlight the active one
var _gender_btns: Array[Button] = []
# Race / class button references for selection highlight
var _race_btns:  Array[Button] = []
var _class_btns: Array[Button] = []


# Interactive Camera Controls
var is_rotating: bool = false
var is_panning: bool = false
var current_rotation_y: float = 0.0
var current_zoom: float = 4.0
var current_height: float = 1.2

var debug_rot: Vector3 = Vector3(0, 0, 90)
var debug_label: Label = null


# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	races = RaceData.get_all_races()
	classes = ClassData.get_all_classes()
	
	_build_race_buttons()
	_build_class_buttons()
	_build_stat_sliders()
	_build_appearance_controls()
	
	_select_race(0)
	_select_class(0)
	_update_points_label()
	
	_apply_layout()
	
	confirm_btn.pressed.connect(_on_confirm_pressed)
	
	debug_label = Label.new()
	debug_label.add_theme_font_size_override("font_size", 24)
	debug_label.add_theme_color_override("font_color", Color(1, 1, 0)) # Yellow
	debug_label.position = Vector2(20, 20)
	debug_label.text = "USE ARROW KEYS OR W/S/A/D/Q/E TO ROTATE SWORD\nCURRENT ROT: (0, 0, 0)"
	preview_panel.add_child(debug_label)
	
	# Fix: Ensure the 3D viewport is at the absolute top of the index
	preview_panel.z_index = 0
	portrait_rect.z_index = 100
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	if not portrait_rect.gui_input.is_connected(_on_portrait_gui_input):
		portrait_rect.gui_input.connect(_on_portrait_gui_input)
	
	# Fix "Dead Zone": Force background panels to ignore mouse so they don't block the bottom 70%
	main_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$PreviewPanel/VBox.mouse_filter = Control.MOUSE_FILTER_IGNORE # Force-ignore the Lore/Active container
	
	print("[Info] Character creation studio ready.")


func _apply_layout() -> void:
	race_lore_label.hide()
	class_lore_label.hide()
	
	if passive_label.get_parent() != main_vbox:
		passive_label.get_parent().remove_child(passive_label)
		main_vbox.add_child(passive_label)
		passive_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		
	if ability_list.get_parent() != main_vbox:
		ability_list.get_parent().remove_child(ability_list)
		main_vbox.add_child(ability_list)
	
	main_vbox.show()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE, Control.PRESET_MODE_KEEP_WIDTH, 0)
	main_vbox.anchor_left = 0.5
	main_vbox.anchor_right = 1.0
	main_vbox.offset_left = 40
	main_vbox.offset_right = -40
	
	preview_panel.show()
	preview_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE, Control.PRESET_MODE_KEEP_WIDTH, 0)
	preview_panel.anchor_left = 0.0
	preview_panel.anchor_right = 0.5
	preview_panel.offset_left = 0
	preview_panel.offset_right = 0
	
	var vs = get_viewport_rect().size
	preview_viewport.size = Vector2(vs.x * 0.5, vs.y)
	
	# Fix: The container must be resized to match the viewport size for clicks to work
	portrait_rect.stretch = true
	portrait_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	_update_camera()

func _update_camera() -> void:
	preview_camera.position = Vector3(0, current_height, current_zoom)
	preview_camera.fov = 35

func _build_preview_character() -> void:
	for child in preview_model_root.get_children():
		child.queue_free()
		
	var config = appearance_config.duplicate()
	config["gender"] = PlayerData.gender
	config["race"] = races[selected_race_index]["name"]
	
	# Apply race body_profile:
	# - Slider-adjustable keys (muscle) are MULTIPLIED with the race base
	#   so the slider still works as a fine-tuning modifier within the race.
	# - Race-only keys (build_scale, head_scale, etc.) are set directly.
	var profile: Dictionary = races[selected_race_index].get("body_profile", {})
	var slider_keys := ["muscle"]   # Keys where slider acts as multiplier on race base
	for key in profile:
		if key in slider_keys:
			config[key] = profile[key] * appearance_config.get(key, 1.0)
		else:
			config[key] = profile[key]

	# Apply class-specific hand modification
	var class_data: Dictionary = classes[selected_class_index]
	var class_hand_mod: float = class_data.get("hand_mod", 1.0)
	config["hand_scale"] = config.get("hand_scale", 1.0) * class_hand_mod

	# Inject starter clothing from the selected class — no UI override, class decides
	var starter_clothing: Dictionary = class_data.get("starter_clothing", {})
	config["clothing_type"]  = starter_clothing.get("type", "none")
	config["shirt_color"]    = starter_clothing.get("shirt_color",  Color(0.55, 0.42, 0.28))
	config["pants_color"]    = starter_clothing.get("pants_color",  Color(0.25, 0.18, 0.12))
	config["robe_color"]     = starter_clothing.get("robe_color",   Color(0.18, 0.14, 0.45))
	
	# Inject starter weapons for the preview skeleton
	var sw: Dictionary = classes[selected_class_index].get("starter_weapons", {})
	config["main_hand_cfg"] = sw.get("main_hand", {})
	config["off_hand_cfg"]  = sw.get("off_hand",  {})

	var build_data = CharacterBuilder.build_character(preview_model_root, config)

	var active_skeleton = build_data.get("skeleton")
	var rig = build_data.get("instance")
	
	if active_skeleton and rig:
		var class_anim_config = classes[selected_class_index].get("animations", {})
		CharacterBuilder.initialize_animations(rig, active_skeleton, rig, class_anim_config)
		
	# Pedestal (CylinderMesh): height=0.2, scene y=-1.0 → top surface at y=-0.9 (absolute).
	# Setting the model root here places the character's feet exactly on the pedestal.
	preview_model_root.position.y = -0.9

	preview_model_root.rotation.y = current_rotation_y

func _process(delta: float) -> void:
	var speed = deg_to_rad(90.0 * delta)
	
	var skel: Skeleton3D = preview_model_root.find_child("Skeleton3D", true, false)
	if skel:
		var rh_idx = skel.find_bone("mixamorig_RightHand")
		if rh_idx == -1: rh_idx = skel.find_bone("RightHand")
		
		if rh_idx != -1:
			var changed = false
			var current_q: Quaternion = skel.get_bone_pose_rotation(rh_idx)
			
			if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
				current_q = current_q * Quaternion(Vector3.RIGHT, speed); changed = true
			if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
				current_q = current_q * Quaternion(Vector3.RIGHT, -speed); changed = true
			if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
				current_q = current_q * Quaternion(Vector3.UP, speed); changed = true
			if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
				current_q = current_q * Quaternion(Vector3.UP, -speed); changed = true
			if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_PAGEUP):
				current_q = current_q * Quaternion(Vector3.FORWARD, speed); changed = true
			if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_PAGEDOWN):
				current_q = current_q * Quaternion(Vector3.FORWARD, -speed); changed = true
				
			if changed:
				skel.set_bone_pose_rotation(rh_idx, current_q.normalized())
				var deg = current_q.get_euler() * (180.0 / PI)
				debug_label.text = "USE W/S/A/D/Q/E TO ROTATE WRIST\nWRIST EULER: (%d, %d, %d)" % [int(deg.x), int(deg.y), int(deg.z)]

# ─── Interactive Controls ──────────────────────────────────────────────────────
func _on_portrait_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_flash_debug_color()
		print("[Diagnostic] SUCCESS: Mouse Click Detected on Preview Pane!")
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_rotating = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_zoom = clamp(current_zoom - 0.2, 1.5, 6.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_zoom = clamp(current_zoom + 0.2, 1.5, 6.0)
			_update_camera()
			
	if event is InputEventMouseMotion:
		if is_rotating:
			current_rotation_y += event.relative.x * 0.01
			preview_model_root.rotation.y = current_rotation_y
		elif is_panning:
			current_height = clamp(current_height + event.relative.y * 0.005, 0.2, 2.5)
			_update_camera()

func _flash_debug_color() -> void:
	var original = preview_panel.self_modulate
	preview_panel.self_modulate = Color(0.2, 1.0, 0.2, 0.3)
	await get_tree().create_timer(0.1).timeout
	preview_panel.self_modulate = original

# ─── Race & Class Logic ──────────────────────────────────────────────────────
func _build_race_buttons() -> void:
	_race_btns.clear()
	for i in range(races.size()):
		var r = races[i]
		var btn = Button.new()
		btn.text = r["name"]
		btn.custom_minimum_size = Vector2(120, 40)
		btn.pressed.connect(_select_race.bind(i))
		race_grid.add_child(btn)
		_race_btns.append(btn)

func _select_race(index: int) -> void:
	selected_race_index = index
	_update_selection_highlight(_race_btns, index)
	var r = races[index]
	passive_label.text = "✦ " + r["passive_ability"] + ": " + r["passive_description"]
	_update_stat_display()
	_build_preview_character()

func _build_class_buttons() -> void:
	_class_btns.clear()
	for i in range(classes.size()):
		var c = classes[i]
		var btn = Button.new()
		btn.text = c["name"]
		btn.custom_minimum_size = Vector2(120, 40)
		btn.pressed.connect(_select_class.bind(i))
		class_grid.add_child(btn)
		_class_btns.append(btn)

func _select_class(index: int) -> void:
	selected_class_index = index
	_update_selection_highlight(_class_btns, index)
	for child in ability_list.get_children():
		child.queue_free()
	for ability in classes[index]["abilities"]:
		var lbl = Label.new()
		lbl.text = "⚡ " + ability["name"] + " — " + ability["description"]
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ability_list.add_child(lbl)
	_update_stat_display()
	_build_preview_character()


## Highlights the button at active_idx; resets all others to default style.
func _update_selection_highlight(btns: Array[Button], active_idx: int) -> void:
	for i in range(btns.size()):
		var btn: Button = btns[i]
		if i == active_idx:
			var style := StyleBoxFlat.new()
			style.bg_color        = Color(0.65, 0.46, 0.10)   # Warm amber fill
			style.border_color    = Color(1.00, 0.82, 0.30)   # Bright gold border
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			style.content_margin_left   = 8
			style.content_margin_right  = 8
			style.content_margin_top    = 4
			style.content_margin_bottom = 4
			btn.add_theme_stylebox_override("normal",  style)
			btn.add_theme_stylebox_override("hover",   style)
			btn.add_theme_stylebox_override("pressed", style)
			btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
		else:
			btn.remove_theme_stylebox_override("normal")
			btn.remove_theme_stylebox_override("hover")
			btn.remove_theme_stylebox_override("pressed")
			btn.remove_theme_color_override("font_color")

# ─── Appearance Logic ────────────────────────────────────────────────────────

func _build_appearance_controls() -> void:
	for child in appearance_picker.get_children():
		child.queue_free()
	var v_box = VBoxContainer.new()
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	appearance_picker.add_child(v_box)
	
	# ── Gender toggle ─────────────────────────────────────────────────────────
	_build_gender_toggle(v_box)
	
	_add_appearance_slider(v_box, "Muscle", "muscle", 0.5, 2.0)
	var skin_lbl = Label.new()
	skin_lbl.text = "Skin Tone"
	v_box.add_child(skin_lbl)
	var color_row = HBoxContainer.new()
	v_box.add_child(color_row)
	var skin_tones = PlayerData.SKIN_TONES
	for i in range(skin_tones.size()):
		var color = skin_tones[i]
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(40, 40)
		var style = StyleBoxFlat.new()
		style.bg_color = color
		btn.add_theme_stylebox_override("normal", style)
		btn.pressed.connect(func():
			_set_skin_color(color)
			PlayerData.skin_tone = i
		)
		color_row.add_child(btn)

func _build_gender_toggle(container: VBoxContainer) -> void:
	var lbl = Label.new()
	lbl.text = "Gender"
	container.add_child(lbl)
	
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	container.add_child(row)
	
	_gender_btns.clear()
	var genders := [{"label": "♂  Male", "key": "male"}, {"label": "♀  Female", "key": "female"}]
	for gd in genders:
		var btn := Button.new()
		btn.text = gd["label"]
		btn.custom_minimum_size = Vector2(100, 36)
		btn.toggle_mode = false
		# Highlight the currently active gender on first build
		_style_gender_btn(btn, PlayerData.gender == gd["key"])
		btn.pressed.connect(_set_gender.bind(gd["key"]))
		row.add_child(btn)
		_gender_btns.append(btn)

func _style_gender_btn(btn: Button, active: bool) -> void:
	var style := StyleBoxFlat.new()
	if active:
		style.bg_color = Color(0.25, 0.50, 0.90, 1.0)   # Bright blue active
		style.border_width_bottom = 2
		btn.add_theme_color_override("font_color", Color(1, 1, 1))
	else:
		style.bg_color = Color(0.18, 0.18, 0.22, 1.0)  # Dark inactive
		btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	style.corner_radius_top_left    = 6
	style.corner_radius_top_right   = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)

func _set_gender(gender_key: String) -> void:
	PlayerData.gender = gender_key
	# Re-style both buttons to reflect the new selection
	var keys := ["male", "female"]
	for i in _gender_btns.size():
		_style_gender_btn(_gender_btns[i], keys[i] == gender_key)
	_build_preview_character()

func _add_appearance_slider(container: Control, label: String, key: String, min_v: float, max_v: float) -> void:
	var hbox = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(80, 0)
	var slider = HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 0.05
	slider.value = appearance_config[key]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(val): 
		appearance_config[key] = val
		_build_preview_character()
	)
	hbox.add_child(lbl)
	hbox.add_child(slider)
	container.add_child(hbox)

func _set_skin_color(color: Color) -> void:
	appearance_config["skin_color"] = color
	_build_preview_character()

# ─── Stat Logic ─────────────────────────────────────────────────────────────
func _build_stat_sliders() -> void:
	var stat_names = ["str", "dex", "int", "con", "wis", "cha"]
	var stat_labels_text = ["Strength", "Dexterity", "Intelligence", "Constitution", "Wisdom", "Charisma"]
	for i in range(stat_names.size()):
		var stat = stat_names[i]
		var row = HBoxContainer.new()
		var name_lbl = Label.new()
		name_lbl.text = stat_labels_text[i]
		name_lbl.custom_minimum_size = Vector2(120, 0)
		var value_lbl = Label.new()
		value_lbl.name = "StatValue_" + stat
		value_lbl.custom_minimum_size = Vector2(40, 0)
		var minus_btn = Button.new()
		minus_btn.text = "-"
		minus_btn.pressed.connect(_change_stat.bind(stat, -1))
		var plus_btn = Button.new()
		plus_btn.text = "+"
		plus_btn.pressed.connect(_change_stat.bind(stat, 1))
		row.add_child(name_lbl)
		row.add_child(minus_btn)
		row.add_child(value_lbl)
		row.add_child(plus_btn)
		stat_panel.add_child(row)
	_update_stat_display()

func _change_stat(stat: String, delta: int) -> void:
	var new_val = stat_allocations[stat] + delta
	if new_val < 0: return
	var new_spent = points_spent - stat_allocations[stat] + new_val
	if new_spent > POINT_BUY_TOTAL: return
	stat_allocations[stat] = new_val
	points_spent = new_spent
	_update_stat_display()
	_update_points_label()

func _update_stat_display() -> void:
	var race = races[selected_race_index]
	var char_class = classes[selected_class_index]
	var stat_names = ["str", "dex", "int", "con", "wis", "cha"]
	for stat in stat_names:
		var total = char_class["base_stats"].get(stat, 10) + race["bonuses"].get(stat, 0) + stat_allocations[stat]
		var lbl = stat_panel.find_child("StatValue_" + stat, true, false)
		if lbl: lbl.text = str(total)

func _update_points_label() -> void:
	points_label.text = "Points remaining: " + str(POINT_BUY_TOTAL - points_spent)

func _on_confirm_pressed() -> void:
	var char_name = name_input.text.strip_edges()
	if char_name.is_empty(): char_name = "The Unnamed One"
	PlayerData.character_name = char_name
	PlayerData.race = races[selected_race_index]["name"]
	PlayerData.char_class = classes[selected_class_index]["name"]
	PlayerData.gender = PlayerData.gender
	PlayerData.appearance_config = appearance_config
	
	# Initialize equipped slots with starter weapons from class data
	var sw: Dictionary = classes[selected_class_index].get("starter_weapons", {})
	PlayerData.equipped["main_hand"] = sw.get("main_hand", {}).get("node", "Unarmed")
	PlayerData.equipped["off_hand"]  = sw.get("off_hand", {}).get("node", "")
	
	PlayerData.calculate_derived_stats()
	
	# BROADCAST the new character data to the server/host immediately
	if NetworkManager.is_multiplayer_active():
		NetworkManager.register_player.rpc_id(1, PlayerData.to_dict())
	
	GameManager.enter_world()
