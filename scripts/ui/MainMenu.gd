## MainMenu.gd
## Cinematic 3D Character Selection Hall
extends Control

@onready var title_area: VBoxContainer = $TitleArea
@onready var subtitle_label: Label = $TitleArea/SubtitleLabel
@onready var main_vbox: VBoxContainer = $VBoxContainer

var _camera: Camera3D
var _action_btn: Button
var _delete_btn: Button
var _selection_light: SpotLight3D
var _selected_slot: int = 0
var _podiums_data = [] # Stores dicts: { "slot": int, "exists": bool, "pos_x": float, "anchor": Node3D }
var _confirmation_dialog: ConfirmationDialog
var _settings_popup: AcceptDialog

# ─── New Flow State ───
enum MenuState { LAUNCHER, CHARACTER_SELECT }
enum GameMode { SINGLE, MULTI }

var _current_state: MenuState = MenuState.LAUNCHER
var _current_mode: GameMode = GameMode.SINGLE
var is_hosting_attempt: bool = false

# UI Containers
var _launcher_ui: VBoxContainer
var _character_ui: VBoxContainer
var _multiplayer_row: HBoxContainer
var _ip_edit: LineEdit
var _status_lbl: Label
var _steam_user_lbl: Label
var _version_lbl: Label
var _update_btn: Button

func _ready() -> void:
	print("[MainMenu] Starting initialization...")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# 1. Validation & Visibility
	if has_node("Background"): $Background.hide()
	if has_node("VBoxContainer/NewGameBtn"): $VBoxContainer/NewGameBtn.hide()
	if has_node("VBoxContainer/LoadGameBtn"): $VBoxContainer/LoadGameBtn.hide()
	if has_node("SaveSlotsPanel"): $SaveSlotsPanel.hide()
	
	# 2. Critical systems
	print("[MainMenu] Setting up dialogs...")
	_setup_confirmation_dialog()
	
	print("[MainMenu] Animating title...")
	_animate_title()
	
	print("[MainMenu] Initializing Hall of Heroes...")
	_initialize_hall_of_heroes()
	
	print("[MainMenu] Integrating UI components...")
	_integrate_ui_to_main_vbox()
	
	# Initial state
	print("[MainMenu] Setting initial menu state...")
	_set_menu_state(MenuState.LAUNCHER)
	
	if not NetworkManager.lobby_id_received.is_connected(_on_lobby_id_received):
		NetworkManager.lobby_id_received.connect(_on_lobby_id_received)
	
	if not UpdateManager.update_check_completed.is_connected(_on_update_check_finished):
		UpdateManager.update_check_completed.connect(_on_update_check_finished)
	
	if not UpdateManager.download_progress.is_connected(_on_update_progress):
		UpdateManager.download_progress.connect(_on_update_progress)
	
	print("[MainMenu] Initialization complete.")

func _setup_confirmation_dialog() -> void:
	_confirmation_dialog = ConfirmationDialog.new()
	_confirmation_dialog.title = "Delete Character?"
	_confirmation_dialog.dialog_text = "Are you sure you want to delete this hero? This cannot be undone."
	_confirmation_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(_confirmation_dialog)

func _animate_title() -> void:
	print("[MainMenu] Animating title...")
	var logo_node = find_child("LogoIcon", true, false)
	if logo_node == null:
		print("[MainMenu] WARNING: LogoIcon node not found in scene tree!")
	elif not (logo_node is TextureRect):
		print("[MainMenu] WARNING: LogoIcon found but is NOT a TextureRect. It is: ", logo_node.get_class())
	else:
		var logo_res_path = "res://assets/ui/game_logo.jpg"
		var logo_abs_path = ProjectSettings.globalize_path(logo_res_path)
		print("[MainMenu] Logo nodes found. Checking path: ", logo_abs_path)
		
		if ResourceLoader.exists(logo_res_path):
			print("[MainMenu] File exists at res:// path. Loading texture...")
			var tex = load(logo_res_path)
			if tex:
				logo_node.texture = tex
				logo_node.custom_minimum_size = Vector2(0, 550)
				print("[MainMenu] SUCCESS: Logo assigned successfully.")
			else:
				print("[MainMenu] ERROR: load() returned null for: ", logo_res_path)
		else:
			print("[MainMenu] ERROR: ResourceLoader confirms file does NOT exist at: ", logo_res_path)
	
	subtitle_label.modulate = Color(1, 1, 1, 0)
	var tween = create_tween()
	tween.tween_property(subtitle_label, "modulate:a", 1.0, 1.5)

func _initialize_hall_of_heroes() -> void:
	# 1. Setup 3D Canvas
	var container = SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_PASS 
	add_child(container)
	move_child(container, 0) # Background layer
	
	var vp = SubViewport.new()
	vp.physics_object_picking = true
	container.add_child(vp)
	
	var env_node = Node3D.new()
	vp.add_child(env_node)
	
	# 2. Cinematic Environment (Darker & Moody)
	var world_env = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	(sky.sky_material as ProceduralSkyMaterial).sky_top_color = Color(0.01, 0.01, 0.02)
	(sky.sky_material as ProceduralSkyMaterial).sky_horizon_color = Color(0.05, 0.04, 0.06)
	(sky.sky_material as ProceduralSkyMaterial).ground_bottom_color = Color(0, 0, 0)
	env.sky = sky
	
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.2
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.05
	env.volumetric_fog_albedo = Color(0.1, 0.1, 0.15)
	
	_camera = Camera3D.new()
	# Pull back a bit more and look down to see the floor/pedestals
	_camera.position = Vector3(0.0, 2.6, 6.5) 
	_camera.rotation_degrees.x = -15.0
	env_node.add_child(_camera)

	# Main Scene Light (Stronger center light)
	var main_light = OmniLight3D.new()
	main_light.position = Vector3(0, 4.5, 2)
	main_light.light_energy = 8.0
	main_light.omni_range = 15.0
	env_node.add_child(main_light)
	
	_selection_light = SpotLight3D.new()
	_selection_light.rotation_degrees = Vector3(-90, 0, 0)
	_selection_light.light_energy = 6.0
	_selection_light.spot_range = 8.0
	_selection_light.spot_angle = 35.0
	_selection_light.light_color = Color(0.9, 0.95, 1.0)
	_selection_light.shadow_enabled = true
	_selection_light.position.y = 4.0
	env_node.add_child(_selection_light)
	
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.light_energy = 0.5
	light.shadow_enabled = true
	env_node.add_child(light)
	
	var rim_light = DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(10, -135, 0)
	rim_light.light_energy = 3.0
	rim_light.light_color = Color(0.8, 0.5, 0.3)
	env_node.add_child(rim_light)
	
	# 3. Build 3 Platforms
	_refresh_hall(env_node)

func _refresh_hall(parent: Node3D) -> void:
	for p in _podiums_data:
		if is_instance_valid(p["anchor"]): p["anchor"].queue_free()
	_podiums_data.clear()
	
	var slots_info = SaveSystem.get_all_save_slots()
	var positions = [-2.8, 0.0, 2.8]
	
	var newest = ""
	var default_slot = 0
	for s in slots_info:
		if s["exists"] and s["saved_at"] > newest:
			newest = s["saved_at"]
			default_slot = s["slot"]
	
	_selected_slot = default_slot
	for i in range(3):
		var info = slots_info[i] if i < slots_info.size() else {"exists": false, "slot": i}
		var pos_x = positions[i]
		var anchor = _build_pedestal(parent, i, pos_x, info)
		_podiums_data.append({"slot": i, "exists": info["exists"], "pos_x": pos_x, "name": info.get("character_name", ""), "anchor": anchor})
	
	_focus_slot(_selected_slot, 0.0)

func _integrate_ui_to_main_vbox() -> void:
	if not main_vbox: return
	
	# Clear any existing buttons from the scene file to prevent duplication
	for child in main_vbox.get_children():
		child.queue_free()
	
	# Reposition the existing VBox to the Bottom Center for better framing
	main_vbox.anchors_preset = Control.PRESET_CENTER_BOTTOM
	main_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main_vbox.grow_vertical = Control.GROW_DIRECTION_BEGIN
	main_vbox.offset_bottom = -24
	main_vbox.custom_minimum_size = Vector2(400, 0)
	main_vbox.add_theme_constant_override("separation", 15)
	
	# ─── 1. LAUNCHER UI ───
	_launcher_ui = VBoxContainer.new()
	_launcher_ui.add_theme_constant_override("separation", 12)
	main_vbox.add_child(_launcher_ui)
	
	var single_btn = _create_menu_button("⚔ Single Player", Color(0.15, 0.18, 0.25))
	single_btn.pressed.connect(func(): _on_mode_selected(GameMode.SINGLE))
	_launcher_ui.add_child(single_btn)
	
	var multi_btn = _create_menu_button("🔗 Multiplayer", Color(0.2, 0.15, 0.25))
	multi_btn.pressed.connect(func(): _on_mode_selected(GameMode.MULTI))
	_launcher_ui.add_child(multi_btn)
	
	var s_btn = _create_menu_button("⚙ Settings", Color(0.12, 0.12, 0.12))
	s_btn.pressed.connect(_on_settings_pressed)
	_launcher_ui.add_child(s_btn)
	
	var quit_btn = _create_menu_button("✕ Quit Game", Color(0.2, 0.05, 0.05))
	quit_btn.pressed.connect(func(): get_tree().quit())
	_launcher_ui.add_child(quit_btn)

	# --- Update UI ---
	_version_lbl = Label.new()
	_version_lbl.text = "v" + UpdateManager.CURRENT_VERSION
	_version_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_version_lbl.add_theme_font_size_override("font_size", 14)
	_launcher_ui.add_child(_version_lbl)
	
	_update_btn = _create_menu_button("✨ Update Available!", Color(0.1, 0.4, 0.3))
	_update_btn.hide()
	_launcher_ui.add_child(_update_btn)

	# ─── 2. CHARACTER SELECTION UI ───
	_character_ui = VBoxContainer.new()
	_character_ui.add_theme_constant_override("separation", 12)
	main_vbox.add_child(_character_ui)
	
	_steam_user_lbl = Label.new()
	_steam_user_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_steam_user_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_character_ui.add_child(_steam_user_lbl)
	if NetworkManager.is_steam_running:
		_steam_user_lbl.text = "Logged in as: " + NetworkManager.steam_name
	else:
		_steam_user_lbl.text = "Steam: " + NetworkManager.steam_status
		_steam_user_lbl.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	
	# Action Row (Continue + Delete)
	var action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	_character_ui.add_child(action_row)
	
	_action_btn = Button.new()
	_action_btn.custom_minimum_size = Vector2(0, 65)
	_action_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_btn.add_theme_font_size_override("font_size", 22)
	_action_btn.pressed.connect(_on_action_btn_pressed)
	action_row.add_child(_action_btn)
	
	_delete_btn = Button.new()
	_delete_btn.text = "🗑"
	_delete_btn.custom_minimum_size = Vector2(65, 65)
	_delete_btn.pressed.connect(func(): _confirmation_dialog.popup_centered())
	action_row.add_child(_delete_btn)
	
	# Multiplayer Row
	_multiplayer_row = HBoxContainer.new()
	_multiplayer_row.add_theme_constant_override("separation", 10)
	_character_ui.add_child(_multiplayer_row)
	
	var host_btn = Button.new()
	host_btn.text = "⚔ Host"
	host_btn.custom_minimum_size = Vector2(0, 50)
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(_on_host_pressed)
	_multiplayer_row.add_child(host_btn)
	
	var join_btn = Button.new()
	join_btn.text = "🔗 Join"
	join_btn.custom_minimum_size = Vector2(0, 50)
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(_on_join_pressed)
	_multiplayer_row.add_child(join_btn)
	
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "Paste Lobby ID here"
	_ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_character_ui.add_child(_ip_edit)
	
	var back_btn = _create_menu_button("« Back to Menu", Color(0.1, 0.1, 0.1))
	back_btn.custom_minimum_size = Vector2(0, 45)
	back_btn.pressed.connect(func(): _set_menu_state(MenuState.LAUNCHER))
	_character_ui.add_child(back_btn)
	
	_status_lbl = Label.new()
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_character_ui.add_child(_status_lbl)

func _create_menu_button(txt: String, base_color: Color) -> Button:
	var btn = Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(0, 60)
	btn.add_theme_font_size_override("font_size", 20)
	
	var style = StyleBoxFlat.new()
	style.bg_color = base_color
	style.bg_color.a = 0.85
	style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style)
	
	var hover = style.duplicate()
	hover.bg_color = base_color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", hover)
	return btn

func _set_menu_state(state: MenuState) -> void:
	_current_state = state
	match _current_state:
		MenuState.LAUNCHER:
			_launcher_ui.show()
			_character_ui.hide()
			title_area.show()
			# Cinematic effect: Hide characters in the launcher stage
			for p in _podiums_data:
				if is_instance_valid(p["anchor"]): p["anchor"].hide()
			if _selection_light: _selection_light.hide()
		MenuState.CHARACTER_SELECT:
			_launcher_ui.hide()
			_character_ui.show()
			title_area.hide()
			# Restore characters
			for p in _podiums_data:
				if is_instance_valid(p["anchor"]): p["anchor"].show()
			if _selection_light: _selection_light.show()
			_update_ui_state()

func _on_mode_selected(mode: GameMode) -> void:
	_current_mode = mode
	if mode == GameMode.SINGLE:
		NetworkManager.shutdown()
	_set_menu_state(MenuState.CHARACTER_SELECT)

func _on_settings_pressed() -> void:
	if not _settings_popup:
		_setup_settings_popup()
	_settings_popup.popup_centered(Vector2i(450, 200))

func _setup_settings_popup() -> void:
	_settings_popup = AcceptDialog.new()
	_settings_popup.title = "Settings"
	add_child(_settings_popup)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	_settings_popup.add_child(vbox)
	
	var editor_lbl = Label.new()
	editor_lbl.text = "Development Tools"
	editor_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(editor_lbl)
	
	var editor_btn = Button.new()
	editor_btn.text = "Launch Map Editor"
	editor_btn.custom_minimum_size = Vector2(0, 50)
	editor_btn.pressed.connect(_on_open_editor_pressed)
	vbox.add_child(editor_btn)

func _on_open_editor_pressed() -> void:
	var server_script_path = ProjectSettings.globalize_path("res://map_editor/server.js")
	var pid = OS.create_process("node", [server_script_path], false)
	if pid > 0:
		await get_tree().create_timer(0.8).timeout
	OS.shell_open("http://localhost:3000")

func _build_pedestal(parent: Node3D, slot_idx: int, pos_x: float, info: Dictionary) -> Node3D:
	var anchor = Node3D.new()
	anchor.position = Vector3(pos_x, 0, 0)
	parent.add_child(anchor)
	var ped = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.75; cyl.bottom_radius = 0.9; cyl.height = 0.15
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.17)
	mat.metallic = 0.6
	mat.roughness = 0.3
	cyl.material = mat
	ped.mesh = cyl; ped.position.y = -0.075
	anchor.add_child(ped)
	
	var body = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var cyl_shape = CylinderShape3D.new()
	cyl_shape.radius = 1.0; cyl_shape.height = 2.5
	shape.shape = cyl_shape; shape.position.y = 1.0
	body.add_child(shape); anchor.add_child(body)
	body.input_event.connect(func(camera, event, pos, norm, s_idx):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_focus_slot(slot_idx, 0.6)
	)
	
	var lbl = Label3D.new()
	lbl.position = Vector3(0, 2.5, 0); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 36; lbl.outline_size = 6; lbl.outline_modulate = Color(0, 0, 0, 0.8); anchor.add_child(lbl)
	if info["exists"]:
		lbl.text = info["character_name"] + " (Lv." + str(int(info["level"])) + ")"
		lbl.modulate = Color(0.9, 0.8, 0.6)
		SaveSystem.load_game(slot_idx)
		var config = _build_preview_config()
		var char_root = Node3D.new()
		char_root.position.y = -0.14 * config["config"].get("build_scale", 1.0)
		char_root.rotation.y = 0 
		anchor.add_child(char_root)
		var b_data = CharacterBuilder.build_character(char_root, config["config"])
		if b_data.get("skeleton") and b_data.get("instance"):
			CharacterBuilder.initialize_animations(b_data.instance, b_data.skeleton, b_data.instance, config["anims"])
	else:
		lbl.text = "- Empty Slot -"; lbl.modulate = Color(0.5, 0.5, 0.5, 0.8)
		var ghost = MeshInstance3D.new(); var cap = CapsuleMesh.new(); cap.radius = 0.3; cap.height = 1.6
		var g_mat = StandardMaterial3D.new(); g_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g_mat.albedo_color = Color(0.1, 0.2, 0.3, 0.1); g_mat.emission_enabled = true; g_mat.emission = Color(0.05, 0.15, 0.2)
		ghost.material_override = g_mat; ghost.mesh = cap; ghost.position.y = 0.8; anchor.add_child(ghost)
		var tween = create_tween().set_loops()
		tween.tween_property(ghost, "position:y", 0.9, 2.0).set_trans(Tween.TRANS_SINE)
		tween.tween_property(ghost, "position:y", 0.8, 2.0).set_trans(Tween.TRANS_SINE)
	return anchor

func _focus_slot(slot_idx: int, transition_time: float = 0.5) -> void:
	_selected_slot = slot_idx
	var slot_data = null
	for p in _podiums_data:
		if p["slot"] == slot_idx: slot_data = p; break
	if not slot_data: return
	
	var target_x = slot_data["pos_x"]
	var tween = create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	
	# Move the spotlight over the selected character
	tween.tween_property(_selection_light, "position:x", target_x, transition_time)
	
	# Add a pop-out scale highlight for the selected slot
	for p in _podiums_data:
		var is_selected = (p["slot"] == slot_idx)
		var t_scale = Vector3(1.4, 1.4, 1.4) if is_selected else Vector3(1.05, 1.05, 1.05)
		if is_instance_valid(p["anchor"]):
			tween.tween_property(p["anchor"], "scale", t_scale, transition_time)
	_update_ui_state()

func _update_ui_state() -> void:
	if _current_state == MenuState.LAUNCHER: return
	if not _action_btn or _selected_slot < 0 or _selected_slot >= _podiums_data.size(): return
	
	var slot_data = _podiums_data[_selected_slot]
	var exists = slot_data["exists"]
	var char_name = slot_data["name"]
	var style = _action_btn.get_theme_stylebox("normal") as StyleBoxFlat
	
	_delete_btn.visible = exists
	
	if _current_mode == GameMode.SINGLE:
		_action_btn.show()
		_multiplayer_row.hide()
		_ip_edit.hide()
		
		if exists:
			_action_btn.text = "► Continue as " + char_name
			_action_btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
			style.bg_color = Color(0.12, 0.15, 0.12, 0.95); style.border_color = Color(0.3, 0.4, 0.2, 1)
		else:
			_action_btn.text = "✚ Forge New Legend"
			_action_btn.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
			style.bg_color = Color(0.1, 0.12, 0.18, 0.95); style.border_color = Color(0.2, 0.3, 0.5, 1)
	else:
		# Multiplayer Mode
		_action_btn.hide()
		_multiplayer_row.show()
		_ip_edit.show()
		
		# Update buttons to reflect selected character
		for btn in _multiplayer_row.get_children():
			if btn is Button:
				if "Host" in btn.text:
					btn.text = "⚔ Host as " + char_name
					btn.disabled = not exists
				elif "Join" in btn.text:
					btn.text = "🔗 Join as " + char_name
					btn.disabled = not exists

func _on_action_btn_pressed() -> void:
	var slot_data = _podiums_data[_selected_slot]
	if slot_data["exists"]: SaveSystem.load_game(_selected_slot); GameManager.enter_world()
	else: PlayerData.save_slot = _selected_slot; GameManager.start_new_game()

func _on_host_pressed() -> void:
	var slot_data = _podiums_data[_selected_slot]
	if not slot_data["exists"]: 
		print("Create a character first!")
		return
		
	SaveSystem.load_game(_selected_slot)
	
	is_hosting_attempt = true
	var err = NetworkManager.host_game()
	if err == OK:
		_status_lbl.text = "Creating Steam Lobby..."

# This is now handled within _on_lobby_id_received for reliability

func _on_join_pressed() -> void:
	var slot_data = _podiums_data[_selected_slot]
	if not slot_data["exists"]: 
		print("Create a character first!")
		return
		
	var lobby_id_str = _ip_edit.text
	
	SaveSystem.load_game(_selected_slot)
	if lobby_id_str.is_empty():
		_status_lbl.text = "Enter a Lobby ID!"
		return
		
	var err = NetworkManager.join_game(lobby_id_str)
	if err == OK:
		_status_lbl.text = "Joining Lobby " + lobby_id_str + "..."
		if not NetworkManager.connection_succeeded.is_connected(_on_connection_success):
			NetworkManager.connection_succeeded.connect(_on_connection_success)
		if not NetworkManager.connection_failed.is_connected(_on_connection_fail):
			NetworkManager.connection_failed.connect(_on_connection_fail)

func _on_connection_success() -> void:
	# Clean up signals
	if NetworkManager.connection_succeeded.is_connected(_on_connection_success):
		NetworkManager.connection_succeeded.disconnect(_on_connection_success)
	GameManager.enter_world()

func _on_connection_fail() -> void:
	_status_lbl.text = "Connection Failed!"
	if NetworkManager.connection_failed.is_connected(_on_connection_fail):
		NetworkManager.connection_failed.disconnect(_on_connection_fail)

func _on_lobby_id_received(l_id: int) -> void:
	print("[MainMenu] Lobby ID received: ", l_id, " Hosting Attempt: ", is_hosting_attempt)
	_status_lbl.text = "Lobby Created! ID: " + str(l_id)
	
	# Add the "Enter World" button first for priority
	var enter_btn = _create_menu_button("🚀 ENTER WORLD", Color(0.2, 0.6, 0.3))
	enter_btn.custom_minimum_size = Vector2(0, 60)
	enter_btn.pressed.connect(func(): 
		_status_lbl.text = "Loading world..."
		GameManager.enter_world()
	)
	_character_ui.add_child(enter_btn)
	# Place it right above the "Back to Menu" button
	_character_ui.move_child(enter_btn, _character_ui.get_child_count() - 2)
	
	# Add the Copy button second
	var copy_btn = _create_menu_button("📋 Copy Lobby ID", Color(0.3, 0.3, 0.3))
	copy_btn.custom_minimum_size = Vector2(0, 45)
	copy_btn.pressed.connect(func(): 
		DisplayServer.clipboard_set(str(l_id))
		copy_btn.text = "✅ ID Copied!"
	)
	_character_ui.add_child(copy_btn)
	_character_ui.move_child(copy_btn, _character_ui.get_child_count() - 2)
	
	if is_hosting_attempt:
		is_hosting_attempt = false
		_status_lbl.text = "Lobby Ready! Click 'ENTER WORLD' to start."

func _on_delete_confirmed() -> void:
	SaveSystem.delete_save(_selected_slot)
	if _camera and _camera.get_parent(): _refresh_hall(_camera.get_parent())

func _build_preview_config() -> Dictionary:
	var combined_config: Dictionary = PlayerData.appearance_config.duplicate()
	combined_config["gender"] = PlayerData.gender; combined_config["race"] = PlayerData.race; combined_config["skin_tone"] = PlayerData.skin_tone
	var all_races: Array = RaceData.get_all_races()
	for r in all_races:
		if r["name"] == PlayerData.race:
			var profile: Dictionary = r.get("body_profile", {})
			for key in profile:
				if key == "muscle": combined_config[key] = profile[key] * PlayerData.appearance_config.get(key, 1.0)
				else: combined_config[key] = profile[key]
			break
	var all_classes: Array = ClassData.get_all_classes()
	var class_anim_config = {}
	for c in all_classes:
		if c["name"] == PlayerData.char_class:
			var sc: Dictionary = c.get("starter_clothing", {})
			combined_config["clothing_type"] = sc.get("type", "none")
			combined_config["shirt_color"] = sc.get("shirt_color", Color(0.55, 0.42, 0.28))
			combined_config["pants_color"] = sc.get("pants_color", Color(0.25, 0.18, 0.12))
			combined_config["robe_color"] = sc.get("robe_color", Color(0.18, 0.14, 0.45))
			var sw = c.get("starter_weapons", {})
			combined_config["main_hand_cfg"] = sw.get("main_hand", {}); combined_config["off_hand_cfg"] = sw.get("off_hand", {})
			class_anim_config = c.get("animations", {})
			break
	var skin_tones = PlayerData.SKIN_TONES
	if PlayerData.skin_tone < skin_tones.size(): combined_config["skin_color"] = skin_tones[PlayerData.skin_tone]
	return {"config": combined_config, "anims": class_anim_config}
func _on_update_check_finished(has_update: bool, latest_v: String, _url: String) -> void:
	print("[DEBUG] AUTO-UPDATE TRIGGERED - HasUpdate: ", has_update, " URL: ", _url)
	
	if has_update:
		_version_lbl.text = "v" + UpdateManager.CURRENT_VERSION + " -> Updating to v" + latest_v + "..."
		_version_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		_update_btn.show()
		_update_btn.disabled = true
		_update_btn.text = "Preparing Download..."
		
		# Auto-trigger download using the passed URL
		if not _url.is_empty():
			print("[MainMenu] Auto-triggering update download from: ", _url)
			UpdateManager.download_patch(_url)
			if not UpdateManager.download_completed.is_connected(_on_patch_downloaded):
				UpdateManager.download_completed.connect(_on_patch_downloaded)
		else:
			print("[MainMenu] ERROR: Update URL is empty!")

func _on_update_progress(received: int, total: int) -> void:
	var percent = int((float(received) / float(total)) * 100.0)
	_update_btn.text = "Downloading Update: " + str(percent) + "%"
	_version_lbl.text = "Downloading v" + UpdateManager.latest_version_info.get("version", "") + " (" + str(percent) + "%)"

func _on_patch_downloaded(success: bool) -> void:
	if success:
		_update_btn.text = "Update Success! Restarting..."
		_update_btn.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
		print("[MainMenu] Update successful. Relaunching game...")
		
		# Give a tiny bit of time for the UI to show success
		await get_tree().create_timer(1.5).timeout
		
		# This is the standard way to restart a Godot app
		OS.set_restart_on_exit(true)
		get_tree().quit()
	else:
		_update_btn.text = "Update Failed. Retrying in next launch."
		_update_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		_update_btn.disabled = false # Allow manual retry if it failed? Or just leave it.
