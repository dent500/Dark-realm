## HUD.gd
## Main in-game HUD: health/mana/stamina bars, minimap placeholder, quest tracker,
## AI DM journal panel, and toggleable sub-panels (inventory, crafting, quest log).
extends Control
class_name HUD


# ─── Nodes ────────────────────────────────────────────────────────────────────
@onready var hp_bar: ProgressBar = get_node_or_null("HUDLayout/BottomLeft/StatsBar/HPBar")
@onready var mana_bar: ProgressBar = get_node_or_null("HUDLayout/BottomLeft/StatsBar/ManaBar")
@onready var stamina_bar: ProgressBar = get_node_or_null("HUDLayout/BottomLeft/StatsBar/StaminaBar")
@onready var hp_label: Label = get_node_or_null("HUDLayout/BottomLeft/StatsBar/HPLabel")
@onready var mana_label: Label = get_node_or_null("HUDLayout/BottomLeft/StatsBar/ManaLabel")
@onready var gold_label: Label = get_node_or_null("HUDLayout/TopLeft/GoldLabel")
@onready var level_label: Label = get_node_or_null("HUDLayout/TopLeft/LevelLabel")
@onready var time_label: Label = get_node_or_null("HUDLayout/TopRight/TimeLabel")
@onready var zone_label: Label = get_node_or_null("HUDLayout/TopLeft/ZoneLabel")
@onready var quest_tracker: VBoxContainer = get_node_or_null("HUDLayout/TopLeft/QuestTracker")
@onready var journal_panel: Panel = get_node_or_null("JournalPanel")
@onready var journal_text: RichTextLabel = get_node_or_null("JournalPanel/MarginContainer/JournalText")
@onready var interact_label: Label = get_node_or_null("HUDLayout/Center/InteractLabel")
@onready var crosshair: TextureRect = get_node_or_null("HUDLayout/Center/Crosshair")
@onready var death_screen: Panel = get_node_or_null("DeathScreen")
@onready var pause_menu: Panel = get_node_or_null("PauseMenu")

# Chat UI
var chat_panel: Panel
var chat_log: RichTextLabel
var chat_input: LineEdit
var party_panel: VBoxContainer
var multiplayer_status_label: Label

var minimap_canvas: Control
var world_map_canvas: Control

# Custom Panels
var character_panel: Panel
var inventory_panel: Panel
var char_stats_lbl: RichTextLabel
var char_equip_container: GridContainer
var bag_grid: GridContainer
var _menu_layer: CanvasLayer # Dedicated layer for popups
var _redraw_timer: float = 0.0
var _save_timer: float = 0.0
var _loading_screen: ColorRect = null

# XP bar
var xp_bar: ProgressBar
var xp_label: Label

# Pickup toast
var _toast_label: Label

# Minimap / Fog of War Data
var map_data: Array = []
var explored_cells: Array = []
var map_grid_size: int = 0
var map_cell_size: float = 2.0
var map_offset: Vector2 = Vector2.ZERO
var exit_pos_grid: Vector2i = Vector2i(-1, -1)
var exit_found: bool = false
var exit_icon: Texture2D
var discovered_enemies: Dictionary = {}  # InstanceID -> bool
var map_pan_offset: Vector2 = Vector2.ZERO
var is_panning_map: bool = false

var underwater_overlay: ColorRect

# Sub-panels (toggled with keyboard)
var active_panel: String = ""
var face_editor_panel: Panel

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Ensure HUD covers the whole screen for correctly centering child panels
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE # Allow mouse to pass through to 3D world
	
	add_to_group("hud")
	if pause_menu: pause_menu.hide()
	
	# FORCE RESUME: Ensure the game isn't stuck in a paused state on startup
	GameManager.is_paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	discovery_mask = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	discovery_mask.fill(Color(0, 0, 0, 0.7)) # Slightly transparent fog for debug
	discovery_texture = ImageTexture.create_from_image(discovery_mask)
	print("[HUD] Discovery system initialized in _ready.")
	# Connect signals
	PlayerData.stats_changed.connect(_refresh_stats)
	PlayerData.gold_changed.connect(_refresh_gold)
	PlayerData.level_up.connect(_on_level_up)
	PlayerData.xp_gained.connect(_refresh_xp)
	AIDungeonMaster.narration_received.connect(_on_narration_received)
	QuestManager.quest_started.connect(_refresh_quest_tracker)
	QuestManager.quest_stage_advanced.connect(_refresh_quest_tracker_stage)
	QuestManager.quest_completed.connect(_on_quest_completed)
	NetworkManager.chat_message_received.connect(_on_chat_message_received)
	NetworkManager.peer_connected.connect(func(_id): _refresh_party_panel())
	NetworkManager.peer_disconnected.connect(func(_id): _refresh_party_panel())
	NetworkManager.player_data_synced.connect(func(_id, _data): _refresh_party_panel())
	
	# Listen for MapLoader finishing
	var loaders = get_tree().get_nodes_in_group("map_loader")
	if loaders.size() > 0:
		loaders[0].map_loaded.connect(_on_map_loaded)
	else:
		# Fallback if MapLoader spawns after HUD (though usually HUD is lower in tree)
		call_deferred("_try_connect_map_loader")
	
	# Create a dedicated layer for menu popups to ensure they are always on top
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 100 # High layer to be above standard HUD
	add_child(_menu_layer)
	
	# Underwater Overlay
	underwater_overlay = ColorRect.new()
	underwater_overlay.name = "UnderwaterOverlay"
	underwater_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	underwater_overlay.color = Color(0.1, 0.3, 0.6, 0.4)
	underwater_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underwater_overlay.hide()
	add_child(underwater_overlay)
	# Move to be behind other HUD elements but above 3D world
	move_child(underwater_overlay, 0)
	
	_build_dynamic_panels()
	_build_inventory_panel()
	_build_chat_panel()
	
	# (Silence exit icon warning for clean logs)
	# if FileAccess.file_exists("res://assets/ui/exit_icon.png"):
	# 	var icon_res = load("res://assets/ui/exit_icon.png")
	# 	if icon_res:
	# 		exit_icon = icon_res
	# 	else:
	# 		print("[HUD] Warning: exit_icon.png exists but failed to load. Resource might be corrupted or not yet imported.")
	# else:
	# 	print("[HUD] Warning: res://assets/ui/exit_icon.png not found.")
	
	_refresh_stats()
	_refresh_gold(PlayerData.gold)
	_refresh_quest_tracker("")
	_refresh_party_panel()
	
	# Setup Loading Screen
	_create_loading_screen()
	
	# Connect to NetworkManager for automatic loading screen dismissal
	NetworkManager.player_data_synced.connect(_on_network_sync)

func _try_connect_map_loader() -> void:
	var loaders = get_tree().get_nodes_in_group("map_loader")
	if loaders.size() > 0:
		var loader = loaders[0]
		if not loader.map_loaded.is_connected(_on_map_loaded):
			loader.map_loaded.connect(_on_map_loaded)
		
		# If the loader finished before we connected, grab the data directly
		if not loader.current_map_data.is_empty() and map_data.is_empty():
			_on_map_loaded(loader.current_map_data, loader.current_grid_size, loader.current_cell_size, loader.current_offset)

func _on_map_loaded(m_data: Array, g_size: int, c_size: float, offset: Vector2) -> void:
	print("[HUD] _on_map_loaded received. Linking terrain map...")
	map_data = m_data
	map_grid_size = g_size
	map_cell_size = c_size
	map_offset = offset
	
	_try_link_terrain_map()

func _try_link_terrain_map() -> void:
	if get_tree().has_meta("terrain_map_texture"):
		map_tex = get_tree().get_meta("terrain_map_texture")
		world_size = get_tree().get_meta("terrain_map_size")
		print("[HUD] Success: Terrain map linked. Map size: ", world_size)
	else:
		print("[HUD] Waiting for terrain map texture...")

func _process(delta: float) -> void:
	# Safety check for map texture recovery
	if not map_tex:
		_try_link_terrain_map()
		
	# Update stamina every frame
	if stamina_bar:
		stamina_bar.value = (PlayerData.current_stamina / PlayerData.max_stamina) * 100.0
		
		# Visual indicator for exhaustion
		var player = get_tree().get_first_node_in_group("local_player")
		if player and "is_exhausted" in player:
			var fill = stamina_bar.get_theme_stylebox("fill") as StyleBoxFlat
			if fill:
				if player.is_exhausted:
					fill.bg_color = Color(0.4, 0.4, 0.4, 1.0) # Gray
				else:
					fill.bg_color = Color(0.9, 0.5, 0.1, 1.0) # Orange
	if time_label:
		time_label.text = "🕐 " + GameManager.get_time_string()
		
	_update_discovery(delta)
	_update_debug_overlay(delta)
	
	# Rate-limit minimap redraw
	_redraw_timer += delta
	if _redraw_timer >= 0.05:
		_redraw_timer = 0.0
		if minimap_canvas:
			minimap_canvas.queue_redraw()
		if world_map_canvas and world_map_canvas.is_visible_in_tree():
			world_map_canvas.queue_redraw()

func _update_debug_overlay(_delta: float) -> void:
	pass

func _update_discovery(_delta: float) -> void:
	if not discovery_mask: return
	
	# Safety: If map_tex was missed during init, try grabbing it now
	if not map_tex and get_tree().has_meta("terrain_map_texture"):
		map_tex = get_tree().get_meta("terrain_map_texture")
		world_size = get_tree().get_meta("terrain_map_size")
		print("[HUD] Map texture recovered in process loop.")

	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty(): return
	
	# Find local player instance (multiplayer authority)
	var p = null
	for candidate in players:
		if candidate.is_multiplayer_authority():
			p = candidate
			break
	
	if not p: return
	
	# Reveal larger circle around all players
	var radius = 12
	var changed = false
	for player_node in players:
		# Convert 3D world pos to 0..255 texture pos
		var tx = int(clamp(((player_node.global_position.x / world_size.x) + 0.5) * 256, 0, 255))
		var tz = int(clamp(((player_node.global_position.z / world_size.y) + 0.5) * 256, 0, 255))
		
		for y in range(max(0, tz - radius), min(256, tz + radius + 1)):
			for x in range(max(0, tx - radius), min(256, tx + radius + 1)):
				if Vector2(x, y).distance_to(Vector2(tx, tz)) <= radius:
					if discovery_mask.get_pixel(x, y).a > 0.0:
						discovery_mask.set_pixel(x, y, Color(1, 1, 1, 0.0))
						changed = true
	
	if changed:
		discovery_texture.update(discovery_mask)

# ─── Stat Display ─────────────────────────────────────────────────────────────
func set_underwater(active: bool) -> void:
	if underwater_overlay:
		underwater_overlay.visible = active

func _refresh_stats() -> void:
	if hp_bar:
		hp_bar.value = float(PlayerData.current_hp) / float(PlayerData.max_hp) * 100.0
		if hp_label: hp_label.text = str(PlayerData.current_hp) + " / " + str(PlayerData.max_hp)
	if mana_bar:
		mana_bar.value = float(PlayerData.current_mana) / float(PlayerData.max_mana) * 100.0
		if mana_label: mana_label.text = str(PlayerData.current_mana) + " / " + str(PlayerData.max_mana)
	if level_label:
		level_label.text = "Lvl " + str(PlayerData.level)
	if zone_label:
		zone_label.text = PlayerData.current_zone.replace("_", " ").capitalize()

func _refresh_gold(amount: int) -> void:
	if gold_label:
		gold_label.text = "🪙 " + str(amount)

func _on_level_up(new_level: int) -> void:
	if level_label: level_label.text = "Lvl " + str(new_level)
	_flash_level_label()
	_refresh_xp(0)  # reset bar for new level

func _refresh_xp(_amount: int = 0) -> void:
	if xp_bar:
		xp_bar.value = float(PlayerData.experience) / float(max(PlayerData.experience_to_next, 1)) * 100.0
	if xp_label:
		xp_label.text = str(PlayerData.experience) + " / " + str(PlayerData.experience_to_next) + " XP"

func _flash_level_label() -> void:
	var tween = create_tween()
	tween.tween_property(level_label, "modulate", Color.GOLD, 0.2)
	tween.tween_property(level_label, "modulate", Color.WHITE, 0.5)

# ─── AI DM Journal ────────────────────────────────────────────────────────────
func _on_narration_received(text: String) -> void:
	if journal_panel: journal_panel.show()
	if journal_text:
		journal_text.append_text("\n\n[color=#c8a87a]" + text + "[/color]")
		journal_text.scroll_to_line(journal_text.get_line_count())
	# Auto-hide after 12 seconds
	await get_tree().create_timer(12.0).timeout
	if active_panel != "journal" and journal_panel:
		journal_panel.hide()

# ─── Quest Tracker ────────────────────────────────────────────────────────────
func _refresh_quest_tracker(_id: String) -> void:
	if not quest_tracker:
		return
	for child in quest_tracker.get_children():
		child.queue_free()
	var active = QuestManager.get_active_quest_list()
	for q in active:
		var lbl = Label.new()
		lbl.text = "◈ " + q["title"] + "\n  " + q["current_objective"]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
		quest_tracker.add_child(lbl)

func _refresh_quest_tracker_stage(_id: String, _stage: int) -> void:
	_refresh_quest_tracker(_id)

func _on_quest_completed(quest_id: String) -> void:
	_refresh_quest_tracker(quest_id)
	_show_completion_banner(QuestManager.quest_db.get(quest_id, {}).get("title", "Quest"))

func _show_completion_banner(title: String) -> void:
	var banner = Label.new()
	banner.text = "✦ QUEST COMPLETE: " + title + " ✦"
	banner.add_theme_color_override("font_color", Color.GOLD)
	banner.add_theme_font_size_override("font_size", 22)
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position.y += 80
	add_child(banner)
	var tween = create_tween()
	tween.tween_property(banner, "modulate:a", 0.0, 3.0)
	tween.tween_callback(banner.queue_free)

# ─── Dynamic Panels ───────────────────────────────────────────────────────────
func _build_dynamic_panels() -> void:
	# ─── Level Badge ───
	level_label = Label.new()
	level_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	level_label.position = Vector2(40, 13)
	level_label.add_theme_font_size_override("font_size", 18)
	level_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))   # gold
	level_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	level_label.add_theme_constant_override("shadow_outline_size", 4)
	level_label.text = "⚔ Level " + str(PlayerData.level)
	add_child(level_label)

	# ─── Interaction & Dialogue Label ───
	var center_container = CenterContainer.new()
	center_container.name = "HUDLayout"
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_container)
	
	var center_vbox = VBoxContainer.new()
	center_container.add_child(center_vbox)
	
	interact_label = Label.new()
	interact_label.name = "InteractLabel"
	interact_label.add_theme_font_size_override("font_size", 24)
	interact_label.add_theme_color_override("font_color", Color.WHITE)
	interact_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	interact_label.add_theme_constant_override("shadow_outline_size", 4)
	interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_label.hide()
	center_vbox.add_child(interact_label)
	
	# Add a crosshair too if missing
	crosshair = TextureRect.new()
	crosshair.name = "Crosshair"
	crosshair.custom_minimum_size = Vector2(8, 8)
	crosshair.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	crosshair.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Use a simple color rect as fallback if texture missing
	var dot = ColorRect.new()
	dot.custom_minimum_size = Vector2(4, 4)
	dot.color = Color(1, 1, 1, 0.5)
	crosshair.add_child(dot)
	center_vbox.add_child(crosshair)

	# ─── Player Health Bar ───
	var hp_bg = Panel.new()
	hp_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hp_bg.custom_minimum_size = Vector2(400, 45)
	hp_bg.position = Vector2(40, 40)
	
	hp_bar = ProgressBar.new()
	hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_bar.show_percentage = false
	var stylebox_bg = StyleBoxFlat.new()
	stylebox_bg.bg_color = Color(0.1, 0.05, 0.05, 0.9)
	var stylebox_fg = StyleBoxFlat.new()
	stylebox_fg.bg_color = Color(0.7, 0.15, 0.15, 1.0)
	hp_bar.add_theme_stylebox_override("background", stylebox_bg)
	hp_bar.add_theme_stylebox_override("fill", stylebox_fg)
	hp_bg.add_child(hp_bar)
	
	hp_label = Label.new()
	hp_label.set_anchors_preset(Control.PRESET_CENTER)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 22)
	hp_label.add_theme_color_override("font_color", Color.WHITE)
	hp_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	hp_label.add_theme_constant_override("shadow_outline_size", 4)
	hp_bg.add_child(hp_label)
	
	add_child(hp_bg)

	# ─── XP Bar ───
	var xp_bg = Panel.new()
	xp_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	xp_bg.custom_minimum_size = Vector2(400, 24)
	xp_bg.position = Vector2(40, 92)  # directly below the HP bar

	xp_bar = ProgressBar.new()
	xp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	xp_bar.show_percentage = false
	var xp_stylebox_bg = StyleBoxFlat.new()
	xp_stylebox_bg.bg_color = Color(0.05, 0.04, 0.10, 0.9)
	var xp_stylebox_fg = StyleBoxFlat.new()
	xp_stylebox_fg.bg_color = Color(0.65, 0.50, 0.05, 1.0)  # deep gold
	xp_bar.add_theme_stylebox_override("background", xp_stylebox_bg)
	xp_bar.add_theme_stylebox_override("fill", xp_stylebox_fg)
	xp_bg.add_child(xp_bar)

	xp_label = Label.new()
	xp_label.set_anchors_preset(Control.PRESET_CENTER)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_label.add_theme_font_size_override("font_size", 12)
	xp_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	xp_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	xp_label.add_theme_constant_override("shadow_outline_size", 3)
	xp_bg.add_child(xp_label)

	add_child(xp_bg)
	_refresh_xp()
	
	# ─── Stamina Bar ───
	var st_bg = Panel.new()
	st_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	st_bg.custom_minimum_size = Vector2(400, 16)
	st_bg.position = Vector2(40, 120)
	
	stamina_bar = ProgressBar.new()
	stamina_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	stamina_bar.show_percentage = false
	var st_stylebox_bg = StyleBoxFlat.new()
	st_stylebox_bg.bg_color = Color(0.1, 0.08, 0.05, 0.9)
	var st_stylebox_fg = StyleBoxFlat.new()
	st_stylebox_fg.bg_color = Color(0.9, 0.5, 0.1, 1.0)
	stamina_bar.add_theme_stylebox_override("background", st_stylebox_bg)
	stamina_bar.add_theme_stylebox_override("fill", st_stylebox_fg)
	st_bg.add_child(stamina_bar)
	add_child(st_bg)

	# ─── Party Panel (Multiplayer) ───
	party_panel = VBoxContainer.new()
	party_panel.name = "PartyPanel"
	party_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	party_panel.position = Vector2(40, 150) # Below stats bars
	party_panel.add_theme_constant_override("separation", 8)
	add_child(party_panel)

	
	# ─── Character Panel (C) — Two-column: Equip Slots | Stats ───
	character_panel = Panel.new()
	character_panel.name = "CharacterPanel"
	character_panel.custom_minimum_size = Vector2(780, 560)
	character_panel.set_anchors_preset(Control.PRESET_CENTER)
	character_panel.offset_left = -390
	character_panel.offset_top = -280
	character_panel.offset_right = 390
	character_panel.offset_bottom = 280
	character_panel.hide()
	
	var char_bg = ColorRect.new()
	char_bg.color = Color(0.05, 0.04, 0.08, 0.98)
	char_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	character_panel.add_child(char_bg)
	
	var char_title = Label.new()
	char_title.text = "🛡️  CHARACTER  🛡️"
	char_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_title.add_theme_font_size_override("font_size", 34)
	char_title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	char_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	char_title.position.y = 10
	character_panel.add_child(char_title)
	
	var close_btn_c = Button.new()
	close_btn_c.text = "✕"
	close_btn_c.add_theme_font_size_override("font_size", 20)
	close_btn_c.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn_c.offset_left = -50
	close_btn_c.offset_top = 10
	close_btn_c.offset_right = -10
	close_btn_c.offset_bottom = 50
	close_btn_c.pressed.connect(func(): toggle_panel("character"))
	character_panel.add_child(close_btn_c)
	
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 20
	hbox.offset_top = 70
	hbox.offset_right = -20
	hbox.offset_bottom = -20
	hbox.add_theme_constant_override("separation", 30)
	character_panel.add_child(hbox)
	
	var equip_vbox = VBoxContainer.new()
	equip_vbox.custom_minimum_size = Vector2(360, 0)
	hbox.add_child(equip_vbox)
	
	var equip_title = Label.new()
	equip_title.text = "EQUIPMENT"
	equip_title.add_theme_font_size_override("font_size", 20)
	equip_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	equip_vbox.add_child(equip_title)
	
	char_equip_container = GridContainer.new()
	char_equip_container.columns = 1
	char_equip_container.add_theme_constant_override("v_separation", 6)
	equip_vbox.add_child(char_equip_container)
	
	var stats_vbox = VBoxContainer.new()
	stats_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(stats_vbox)
	
	var stats_title = Label.new()
	stats_title.text = "STATISTICS"
	stats_title.add_theme_font_size_override("font_size", 20)
	stats_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	stats_vbox.add_child(stats_title)
	
	char_stats_lbl = RichTextLabel.new()
	char_stats_lbl.bbcode_enabled = true
	char_stats_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	char_stats_lbl.add_theme_font_size_override("normal_font_size", 18)
	stats_vbox.add_child(char_stats_lbl)
	
	_menu_layer.add_child(character_panel)
	
	# ─── HUD MiniMap ───
	var frame = Panel.new()
	frame.clip_contents = true
	frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	frame.offset_left = -270 # 250 width + 20 margin
	frame.offset_right = -20
	frame.offset_top = 20
	frame.offset_bottom = 270
	
	# Styling background
	var m_bg = ColorRect.new()
	m_bg.color = Color(0.04, 0.04, 0.05, 0.8)
	m_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(m_bg)
	
	# Circular Mask Shader
	var shader = Shader.new()
	shader.code = "shader_type canvas_item;
		void fragment() {
			float d = distance(UV, vec2(0.5, 0.5));
			if (d > 0.5) discard;
			COLOR = texture(TEXTURE, UV);
		}"
	var mat = ShaderMaterial.new()
	mat.shader = shader
	frame.material = mat
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	
	minimap_canvas = Control.new()
	minimap_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimap_canvas.draw.connect(_on_minimap_draw.bind(minimap_canvas, 6.0, true))
	frame.add_child(minimap_canvas)
	
	# Gold Circular Border
	var border = ColorRect.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_shader = Shader.new()
	border_shader.code = "shader_type canvas_item;
		void fragment() {
			float d = distance(UV, vec2(0.5, 0.5));
			if (d < 0.48 || d > 0.5) discard;
			COLOR = vec4(0.9, 0.75, 0.3, 1.0); // Gold
		}"
	var b_mat = ShaderMaterial.new()
	b_mat.shader = border_shader
	border.material = b_mat
	frame.add_child(border)
	
	add_child(frame)

	# ─── Full World Map Panel ───
	var map_panel = Panel.new()
	map_panel.name = "MapPanel"
	map_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.hide()
	var map_bg = ColorRect.new()
	map_bg.color = Color(0.04, 0.02, 0.05, 0.95)
	map_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_panel.add_child(map_bg)
	
	var map_lbl = Label.new()
	map_lbl.text = "WORLD MAP"
	map_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_lbl.add_theme_color_override("font_color", Color(0.7, 0.6, 0.4))
	map_lbl.add_theme_font_size_override("font_size", 32)
	map_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	map_lbl.position.y += 40
	map_panel.add_child(map_lbl)
	
	var center_node = CenterContainer.new()
	center_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_panel.add_child(center_node)
	
	var map_container = Panel.new()
	map_container.custom_minimum_size = Vector2(800, 800)
	map_container.clip_contents = true
	var mc_bg = ColorRect.new()
	mc_bg.color = Color(0, 0, 0, 0.6)
	mc_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_container.add_child(mc_bg)
	
	world_map_canvas = Control.new()
	world_map_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	world_map_canvas.draw.connect(_on_minimap_draw.bind(world_map_canvas, 1.5, false)) # Use 1.5x zoom for world map
	world_map_canvas.gui_input.connect(_on_map_gui_input)
	map_container.add_child(world_map_canvas)
	
	center_node.add_child(map_container)
	add_child(map_panel)
	
	# Quest Log Panel
	var quest_panel = Panel.new()
	quest_panel.name = "QuestLogPanel"
	quest_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	quest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quest_panel.hide()
	var q_bg = ColorRect.new()
	q_bg.color = Color(0.06, 0.04, 0.08, 0.95)
	q_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	quest_panel.add_child(q_bg)
	var q_title = Label.new()
	q_title.text = "Quest Log"
	q_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q_title.add_theme_font_size_override("font_size", 48)
	q_title.add_theme_color_override("font_color", Color.GOLD)
	q_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	q_title.position.y += 100
	quest_panel.add_child(q_title)
	var q_list = RichTextLabel.new()
	q_list.name = "QuestListContainer"
	q_list.bbcode_enabled = true
	q_list.set_anchors_preset(Control.PRESET_CENTER)
	q_list.custom_minimum_size = Vector2(800, 400)
	quest_panel.add_child(q_list)
	add_child(quest_panel)
	
	# Pause Menu
	pause_menu = Panel.new()
	pause_menu.name = "PauseMenu"
	pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.hide()
	var p_bg = ColorRect.new()
	p_bg.color = Color(0, 0, 0, 0.8)
	p_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(p_bg)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(400, 400)
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)
		
	# Buttons
	var r_btn = Button.new()
	r_btn.text = "Resume"
	r_btn.custom_minimum_size = Vector2(0, 50)
	r_btn.add_theme_font_size_override("font_size", 24)
	r_btn.pressed.connect(func(): toggle_panel("pause_menu"))
	vbox.add_child(r_btn)
	
	# Unstuck Section
	var u_box = HBoxContainer.new()
	u_box.alignment = BoxContainer.ALIGNMENT_CENTER
	u_box.add_theme_constant_override("separation", 10)
	vbox.add_child(u_box)
	
	var fwd_btn = Button.new()
	fwd_btn.text = "Unstuck: Fwd"
	fwd_btn.custom_minimum_size = Vector2(145, 50)
	fwd_btn.add_theme_font_size_override("font_size", 20)
	fwd_btn.pressed.connect(func():
		var p = get_tree().get_first_node_in_group("player")
		if p:
			p.global_position += Vector3(0, 1.0, 0) - p.global_transform.basis.z * 3.0
			toggle_panel("pause_menu")
	)
	u_box.add_child(fwd_btn)
	
	var back_btn = Button.new()
	back_btn.text = "Unstuck: Back"
	back_btn.custom_minimum_size = Vector2(145, 50)
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.pressed.connect(func():
		var p = get_tree().get_first_node_in_group("player")
		if p:
			p.global_position += Vector3(0, 1.0, 0) + p.global_transform.basis.z * 3.0
			toggle_panel("pause_menu")
	)
	u_box.add_child(back_btn)
	
	var q_btn = Button.new()
	q_btn.text = "Quit to Menu"
	q_btn.custom_minimum_size = Vector2(0, 50)
	q_btn.add_theme_font_size_override("font_size", 24)
	q_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	vbox.add_child(q_btn)
	
	# Emergency Multiplayer Sync
	var sync_btn = Button.new()
	sync_btn.text = "🔄  FORCE RELOAD PLAYERS"
	sync_btn.custom_minimum_size = Vector2(0, 50)
	sync_btn.add_theme_font_size_override("font_size", 20)
	sync_btn.add_theme_color_override("font_color", Color.YELLOW)
	sync_btn.pressed.connect(_on_force_sync_pressed)
	vbox.add_child(sync_btn)
	
	var legend_lbl = RichTextLabel.new()
	legend_lbl.bbcode_enabled = true
	legend_lbl.custom_minimum_size = Vector2(0, 250)
	legend_lbl.text = "\n[center][color=gray]──────── CONTROLS ────────[/color]\n[color=white]W/A/S/D[/color] - Move & Turn\n[color=white]Left Click[/color] - Attack\n[color=white]Right Click[/color] - Block\n[color=white]E[/color] - Interact / Talk\n[color=white]I[/color] - Inventory Bag\n[color=white]C[/color] - Character & Equipment\n[color=white]M[/color] - Toggle Map\n[color=white]Q[/color] - Toggle Quests\n[color=white]Esc[/color] - Pause Menu[/center]"
	legend_lbl.add_theme_font_size_override("normal_font_size", 20)
	vbox.add_child(legend_lbl)
	
	# Multiplayer Status Tag (Moved here from main screen)
	multiplayer_status_label = Label.new()
	multiplayer_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	multiplayer_status_label.add_theme_color_override("font_color", Color.YELLOW)
	multiplayer_status_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(multiplayer_status_label)
	
	
	# Ability Display
	var ability_box = Panel.new()
	ability_box.custom_minimum_size = Vector2(250, 40)
	ability_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ability_box.position = Vector2(40, 1080 - 180) # Above chat
	var ab_style = StyleBoxFlat.new()
	ab_style.bg_color = Color(0, 0, 0, 0.6)
	ab_style.set_corner_radius_all(6)
	ability_box.add_theme_stylebox_override("panel", ab_style)
	
	var ability_lbl = Label.new()
	ability_lbl.name = "AbilityLabel"
	ability_lbl.text = "Active: Melee Strike"
	ability_lbl.set_anchors_preset(Control.PRESET_CENTER)
	ability_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ability_lbl.add_theme_font_size_override("font_size", 16)
	ability_box.add_child(ability_lbl)
	add_child(ability_box)
	
	# ─── Action Bar ───
	var action_bar = HBoxContainer.new()
	action_bar.name = "ActionBar"
	action_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	action_bar.offset_top = -100
	action_bar.add_theme_constant_override("separation", 15)
	add_child(action_bar)
	
	for i in range(1, 5):
		var slot = Panel.new()
		slot.custom_minimum_size = Vector2(80, 80)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.12, 0.8)
		style.set_border_width_all(2)
		style.border_color = Color(0.4, 0.4, 0.45)
		style.set_corner_radius_all(4)
		slot.add_theme_stylebox_override("panel", style)
		
		var lbl = Label.new()
		lbl.name = "Slot" + str(i) + "_Label"
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		slot.add_child(lbl)
		action_bar.add_child(slot)
	
	update_ability_slots()
	
	add_child(pause_menu)
	
	# ─── Face Editor Panel (Placeholder) ───
	# CharacterEditor.gd is currently missing from the repository.
	# var editor_script = load("res://scripts/ui/CharacterEditor.gd")
	# if editor_script:
	# 	face_editor_panel = Panel.new()
	# 	face_editor_panel.set_script(editor_script)
	# 	face_editor_panel.hide()
	# 	_menu_layer.add_child(face_editor_panel)

func _build_chat_panel() -> void:
	chat_panel = Panel.new()
	chat_panel.name = "ChatPanel"
	chat_panel.custom_minimum_size = Vector2(400, 250)
	chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_panel.position = Vector2(40, 1080 - 450) # Above stats bar
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.4)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	chat_panel.add_child(bg)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 5; vbox.offset_top = 5; vbox.offset_right = -5; vbox.offset_bottom = -5
	chat_panel.add_child(vbox)
	
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.scroll_following = true
	chat_log.add_theme_font_size_override("normal_font_size", 14)
	vbox.add_child(chat_log)
	
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Press Enter to chat..."
	chat_input.flat = true
	chat_input.text_submitted.connect(_on_chat_submitted)
	vbox.add_child(chat_input)
	
	add_child(chat_panel)
	NetworkManager.system_message("Welcome to the realm.")

func _on_chat_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		chat_input.release_focus()
		return
		
	NetworkManager.send_chat_message(text)
	chat_input.clear()
	chat_input.release_focus()

func _on_chat_message_received(sender: String, message: String, color: Color) -> void:
	if chat_log:
		var color_hex = color.to_html(false)
		chat_log.append_text("\n[color=#%s][b]%s:[/b][/color] %s" % [color_hex, sender, message])

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not chat_input.has_focus():
		chat_input.grab_focus()
		get_viewport().set_input_as_handled()

func _refresh_quest_log_panel() -> void:
	if has_node("QuestLogPanel/QuestListContainer"):
		var r = $QuestLogPanel/QuestListContainer
		r.text = ""
		var active = QuestManager.get_active_quest_list()
		if active.is_empty():
			r.text = "[center][color=gray]No active quests. Explore the world.[/color][/center]"
		else:
			for q in active:
				r.text += "[color=gold][b]◈ " + q["title"] + "[/b][/color]\n"
				r.text += "   [color=lightgray]" + q["current_objective"] + "[/color]\n\n"

# ─── Procedural 2D Map Rendering ──────────────────────────────────────────────
func _update_fog_of_war() -> void:
	if map_data.is_empty() or explored_cells.is_empty():
		return
		
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty(): return
	var p = players[0]
	
	# Convert player 3D pos back to 2D grid pos
	var p_x = p.global_position.x + map_offset.x
	var p_z = p.global_position.z + map_offset.y
	
	var grid_x = int(round(p_x / map_cell_size))
	var grid_y = int(round(p_z / map_cell_size))
	
	# Reveal cells in a small radius around player
	var reveal_radius = 4
	for y in range(grid_y - reveal_radius, grid_y + reveal_radius + 1):
		if y < 0 or y >= explored_cells.size(): continue
		for x in range(grid_x - reveal_radius, grid_x + reveal_radius + 1):
			if x >= 0 and x < explored_cells[y].size():
				# Simple distance check for circular reveal
				if Vector2(x, y).distance_to(Vector2(grid_x, grid_y)) <= reveal_radius:
					explored_cells[y][x] = true
					
	# Detect enemies & exit if within range
	var enemies = get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		if e.global_position.distance_to(p.global_position) < 25.0:
			discovered_enemies[e.get_instance_id()] = true

	if exit_pos_grid != Vector2i(-1, -1) and not exit_found:
		var exit_world_x = (exit_pos_grid.x * map_cell_size) - map_offset.x
		var exit_world_z = (exit_pos_grid.y * map_cell_size) - map_offset.y
		var exit_pos_3d = Vector3(exit_world_x, p.global_position.y, exit_world_z)
		
		if p.global_position.distance_to(exit_pos_3d) < 30.0:
			exit_found = true
			# Auto-reveal the exit cell
			if exit_pos_grid.y < explored_cells.size() and exit_pos_grid.x < explored_cells[exit_pos_grid.y].size():
				explored_cells[exit_pos_grid.y][exit_pos_grid.x] = true


# Discovery Map Data
var discovery_mask: Image
var discovery_texture: ImageTexture
var map_tex: Texture2D
var world_size: Vector2 = Vector2(800, 800)

func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_panning_map = event.pressed
	elif event is InputEventMouseMotion and is_panning_map:
		map_pan_offset += event.relative
		if world_map_canvas:
			world_map_canvas.queue_redraw()

func _on_minimap_draw(canvas: Control, scale_factor: float, center_on_player: bool) -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty(): return
	
	# Reference player for centering (Always the local player if possible)
	var p = null
	for candidate in players:
		if candidate.is_multiplayer_authority():
			p = candidate
			break
	if not p: p = players[0]
	
	var center = canvas.size / 2.0
	var p_2d = Vector2(p.global_position.x, p.global_position.z)
	var pan = map_pan_offset if not center_on_player else Vector2.ZERO
	
	# ─── Draw Terrain Map ───
	if map_tex:
		var tex_rect: Rect2
		var map_draw_size = world_size * scale_factor
		# Both minimap and world map now use the same centering logic, 
		# but world map can be offset by map_pan_offset
		var map_draw_pos = center + pan - ((p_2d / world_size + Vector2(0.5, 0.5)) * map_draw_size)
		tex_rect = Rect2(map_draw_pos, map_draw_size)
			
		canvas.draw_texture_rect(map_tex, tex_rect, false)
		
		# ─── Draw Discovery Mask ───
		if discovery_texture:
			canvas.draw_texture_rect(discovery_texture, tex_rect, false)

	# ─── Draw Discovered Enemies ───
	var enemies = get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		var eid = e.get_instance_id()
		if discovered_enemies.has(eid):
			if "state" in e and e.state == 5: continue
			var e_2d = Vector2(e.global_position.x, e.global_position.z)
			var e_draw_pos = center + pan + ((e_2d - p_2d) * scale_factor)
			
			canvas.draw_circle(e_draw_pos, 5.0, Color.CRIMSON)

	# ─── Draw All Players ───
	for player_node in players:
		var p_auth = player_node.get_multiplayer_authority()
		var p_color = _get_player_color(p_auth)
		var p_pos_2d = Vector2(player_node.global_position.x, player_node.global_position.z)
		
		var draw_pos = center + pan + ((p_pos_2d - p_2d) * scale_factor)
		
		# If this is the LOCAL player, draw as an arrow
		if player_node.is_multiplayer_authority():
			var look_node = player_node.get_node_or_null("PlayerMesh")
			if not look_node and "mesh" in player_node:
				look_node = player_node.mesh
			
			var rot_y = look_node.global_rotation.y if look_node else player_node.global_rotation.y
			var fwd_2d = Vector2(0, -1).rotated(-rot_y + PI)
			
			var arrow_size = 14.0
			var pts = PackedVector2Array([
				draw_pos + fwd_2d * arrow_size,
				draw_pos + fwd_2d.rotated(deg_to_rad(135)) * arrow_size * 0.8,
				draw_pos + fwd_2d.rotated(deg_to_rad(-135)) * arrow_size * 0.8
			])
			canvas.draw_colored_polygon(pts, p_color)
			canvas.draw_polyline(pts + PackedVector2Array([pts[0]]), Color.WHITE, 1.5, true)
		else:
			# Remote players are circles with distinct colors
			canvas.draw_circle(draw_pos, 8.0, p_color)
			canvas.draw_circle(draw_pos, 8.0, Color.WHITE, false, 1.5)

func _get_player_color(id: int) -> Color:
	if id == 1: return Color.CYAN # Host/Peer 1
	# Deterministic color based on ID
	var hue = fmod(float(id) * 0.381, 1.0) # Golden ratio distribution
	return Color.from_hsv(hue, 0.7, 1.0)

func _refresh_party_panel() -> void:
	if not party_panel: return
	for child in party_panel.get_children():
		child.queue_free()
	
	if not NetworkManager.is_multiplayer_active():
		party_panel.hide()
		return
	
	party_panel.show()
	
	# Add local player first
	_add_party_member_ui(multiplayer.get_unique_id(), PlayerData.to_dict(), true)
	
	# Add peers
	for id in NetworkManager.peer_data:
		if id != multiplayer.get_unique_id():
			_add_party_member_ui(id, NetworkManager.peer_data[id], false)

func _add_party_member_ui(id: int, data: Dictionary, is_local: bool) -> void:
	var member_box = HBoxContainer.new()
	member_box.custom_minimum_size = Vector2(250, 40)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.3)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	member_box.add_child(bg)
	
	var color_tab = ColorRect.new()
	color_tab.custom_minimum_size = Vector2(4, 0)
	color_tab.color = _get_player_color(id)
	member_box.add_child(color_tab)
	
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	member_box.add_child(info_vbox)
	
	var name_lbl = Label.new()
	var name_text = data.get("character_name", "Player " + str(id))
	if is_local: name_text += " (You)"
	name_lbl.text = name_text
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	info_vbox.add_child(name_lbl)
	
	var stats_lbl = Label.new()
	var lvl = data.get("level", 1)
	var race = data.get("race", "Human")
	stats_lbl.text = "Lvl %d %s" % [lvl, race]
	stats_lbl.add_theme_font_size_override("font_size", 10)
	stats_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_vbox.add_child(stats_lbl)
	
	party_panel.add_child(member_box)

# ─── Panel Toggling ───────────────────────────────────────────────────────────
func toggle_panel(panel_name: String) -> void:
	if active_panel == panel_name:
		active_panel = ""
		_hide_all_panels()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		GameManager.is_paused = false
		# Force update focus for all local players
		for p in get_tree().get_nodes_in_group("local_player"):
			p.set_process_unhandled_input(true)
	else:
		active_panel = panel_name
		_hide_all_panels()
		# Always show panel FIRST, then populate (so it appears even if refresh has an issue)
		match panel_name:
			"character":
				if character_panel:
					_menu_layer.move_child(character_panel, -1)
					character_panel.show()
					_refresh_character_panel()
			"inventory":
				if inventory_panel:
					_menu_layer.move_child(inventory_panel, -1)
					inventory_panel.show()
					_refresh_bag_panel()
			"map":
				if has_node("MapPanel"):
					var mp = get_node("MapPanel")
					_menu_layer.move_child(mp, -1)
					mp.show()
			"quest_log":
				if has_node("QuestLogPanel"):
					var qp = get_node("QuestLogPanel")
					_menu_layer.move_child(qp, -1)
					qp.show()
			"pause_menu":
				if pause_menu:
					pause_menu.show()
			"face_editor":
				if face_editor_panel:
					face_editor_panel.show()
		
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if panel_name == "pause_menu":
			GameManager.is_paused = true
			# Update status label if it exists in the pause menu
			_update_multiplayer_status()

func _hide_all_panels() -> void:
	if character_panel: character_panel.hide()
	if inventory_panel: inventory_panel.hide()
	if journal_panel: journal_panel.hide()
	if has_node("MapPanel"): $MapPanel.hide()
	if has_node("QuestLogPanel"): $QuestLogPanel.hide()
	if pause_menu: pause_menu.hide()
	if face_editor_panel: face_editor_panel.hide()

# ─── Interact Prompt ──────────────────────────────────────────────────────────
func show_interact_prompt(text: String) -> void:
	if interact_label:
		interact_label.text = "[E] " + text
		interact_label.show()

func hide_interact_prompt() -> void:
	if interact_label:
		interact_label.hide()

# ─── Death Screen ─────────────────────────────────────────────────────────────
func show_death_screen() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var death_panel = Panel.new()
	death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var bg = ColorRect.new()
	bg.color = Color(0.2, 0, 0, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_panel.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	
	var lbl = Label.new()
	lbl.text = "YOU DIED"
	lbl.add_theme_font_size_override("font_size", 72)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	
	var respawn_btn = Button.new()
	respawn_btn.text = "Respawn"
	respawn_btn.custom_minimum_size = Vector2(300, 60)
	respawn_btn.add_theme_font_size_override("font_size", 32)
	respawn_btn.pressed.connect(func():
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("respawn"):
			player.respawn()
		death_panel.queue_free()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	)
	vbox.add_child(respawn_btn)
	
	center.add_child(vbox)
	death_panel.add_child(center)
	add_child(death_panel)

# ─── Pause Menu ───────────────────────────────────────────────────────────────
func show_pause_menu() -> void:
	if pause_menu:
		_update_multiplayer_status()
		pause_menu.show()

func _update_multiplayer_status() -> void:
	if not multiplayer_status_label: return
	
	var conn_status = "OFFLINE"
	if NetworkManager.is_multiplayer_active():
		conn_status = "CONNECTED"
	elif multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		var status = multiplayer.multiplayer_peer.get_connection_status()
		if status == MultiplayerPeer.CONNECTION_CONNECTING:
			conn_status = "CONNECTING..."
		else:
			conn_status = "DISCONNECTED"
			
	var player_count = get_tree().get_nodes_in_group("player").size()
	multiplayer_status_label.text = "Multiplayer: %s | Players: %d" % [conn_status, player_count]

func hide_pause_menu() -> void:
	if pause_menu:
		pause_menu.hide()

func update_wave_ui(_wave: int, _remaining: int, _is_active: bool) -> void:
	pass

func _refresh_character_panel() -> void:
	# Get inventory node once — used for both slot display and bonus calc
	var p = get_tree().get_first_node_in_group("player")
	var inv = p.get_node_or_null("Inventory") if p else null
	
	# ── Compute equipment bonuses inline (safe — no scene-tree traversal from autoload) ──
	var atk_bonus: int = 0
	var def_bonus: int = 0
	if inv:
		for slot in PlayerData.equipped:
			var eid = PlayerData.equipped[slot]
			if eid != "" and inv.ITEM_DB.has(eid):
				atk_bonus += inv.ITEM_DB[eid].get("damage_bonus", 0)
				def_bonus += inv.ITEM_DB[eid].get("defense_bonus", 0)
	
	# ── Rebuild equipment slot buttons (synchronous) ──
	if char_equip_container:
		for c in char_equip_container.get_children():
			char_equip_container.remove_child(c)
			c.queue_free()
		var slot_labels: Dictionary = {
			"head": "Head", "body": "Body", "hands": "Hands",
			"legs": "Legs", "feet": "Feet",
			"main_hand": "Main Hand", "off_hand": "Off Hand",
			"ring": "Ring", "amulet": "Amulet"
		}
		for slot in ["head", "body", "hands", "legs", "feet", "main_hand", "off_hand", "ring", "amulet"]:
			var item_id = PlayerData.equipped.get(slot, "")
			var label = slot_labels.get(slot, slot)
			var btn_text: String
			if item_id == "":
				btn_text = "[" + label + "]: Empty"
			else:
				var display = item_id.replace("_", " ").capitalize()
				if inv and inv.ITEM_DB.has(item_id):
					display = inv.ITEM_DB[item_id]["name"]
				btn_text = "[" + label + "]: " + display + "  (click to unequip)"
			
			var btn = Button.new()
			btn.text = btn_text
			btn.add_theme_font_size_override("font_size", 14)
			btn.custom_minimum_size = Vector2(340, 34)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if item_id != "":
				btn.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
				var captured_slot = slot
				btn.pressed.connect(func():
					var p2 = get_tree().get_first_node_in_group("player")
					if p2:
						var inv2 = p2.get_node_or_null("Inventory")
						if inv2:
							inv2.unequip_item(captured_slot)
							_refresh_character_panel()
				)
			else:
				btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			char_equip_container.add_child(btn)
	
	# ── Stats ──
	if char_stats_lbl:
		var base_atk = PlayerData.get_attack_power()
		var base_def = PlayerData.get_defense()
		var text = ""
		text += "[color=gold]" + str(PlayerData.character_name) + "[/color]\n"
		text += "[color=silver]" + str(PlayerData.race) + " " + str(PlayerData.char_class) + "[/color]\n\n"
		text += "[color=gold]Level:[/color] " + str(PlayerData.level) + "\n"
		text += "[color=gold]XP:[/color] " + str(PlayerData.experience) + " / " + str(PlayerData.experience_to_next) + "\n\n"
		text += "[color=red]HP:[/color] " + str(PlayerData.current_hp) + " / " + str(PlayerData.max_hp) + "\n"
		text += "[color=cyan]Mana:[/color] " + str(PlayerData.current_mana) + " / " + str(PlayerData.max_mana) + "\n"
		text += "[color=yellow]Stamina:[/color] " + str(int(PlayerData.current_stamina)) + " / " + str(int(PlayerData.max_stamina)) + "\n\n"
		text += "[color=white]STR:[/color] " + str(PlayerData.strength) + "   "
		text += "[color=white]DEX:[/color] " + str(PlayerData.dexterity) + "   "
		text += "[color=white]INT:[/color] " + str(PlayerData.intelligence) + "\n"
		text += "[color=white]CON:[/color] " + str(PlayerData.constitution) + "   "
		text += "[color=white]WIS:[/color] " + str(PlayerData.wisdom) + "   "
		text += "[color=white]CHA:[/color] " + str(PlayerData.charisma) + "\n\n"
		text += "[color=orange]Attack:[/color] " + str(base_atk + atk_bonus)
		if atk_bonus > 0: text += " [color=green](+" + str(atk_bonus) + " gear)[/color]"
		text += "\n"
		text += "[color=lightblue]Defense:[/color] " + str(base_def + def_bonus)
		if def_bonus > 0: text += " [color=green](+" + str(def_bonus) + " gear)[/color]"
		text += "\n\n"
		text += "[color=yellow]Gold:[/color] " + str(PlayerData.gold) + "\n"
		if PlayerData.unspent_stat_points > 0:
			text += "\n[color=lime]* Unspent Points: " + str(PlayerData.unspent_stat_points) + "[/color]"
		char_stats_lbl.text = text

# ─── Inventory Bag Panel (I) ──────────────────────────────────────────────────
func _build_inventory_panel() -> void:
	inventory_panel = Panel.new()
	inventory_panel.name = "InventoryPanel"
	# Explicitly centre a 660×520 panel on screen
	inventory_panel.anchor_left   = 0.5
	inventory_panel.anchor_top    = 0.5
	inventory_panel.anchor_right  = 0.5
	inventory_panel.anchor_bottom = 0.5
	inventory_panel.offset_left   = -330
	inventory_panel.offset_top    = -260
	inventory_panel.offset_right  =  330
	inventory_panel.offset_bottom =  260
	inventory_panel.hide()
	
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.09, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	inventory_panel.add_child(bg)
	
	# Title
	var title = Label.new()
	title.text = "🎒  INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position.y = 12
	inventory_panel.add_child(title)
	
	# Close button
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_left = -44; close_btn.offset_right = -8
	close_btn.offset_top = 8; close_btn.offset_bottom = 44
	close_btn.pressed.connect(func(): toggle_panel("inventory"))
	inventory_panel.add_child(close_btn)
	
	# Slot count label
	var count_lbl = Label.new()
	count_lbl.name = "SlotCountLabel"
	count_lbl.add_theme_font_size_override("font_size", 13)
	count_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	count_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	count_lbl.position = Vector2(-160, 50)
	inventory_panel.add_child(count_lbl)
	
	# Scroll container for grid
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 62; scroll.offset_bottom = -12
	scroll.offset_left = 12; scroll.offset_right = -12
	inventory_panel.add_child(scroll)
	
	bag_grid = GridContainer.new()
	bag_grid.columns = 5
	bag_grid.add_theme_constant_override("h_separation", 8)
	bag_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(bag_grid)
	
	_menu_layer.add_child(inventory_panel)
	
	# Pickup toast
	_toast_label = Label.new()
	_toast_label.name = "PickupToast"
	_toast_label.add_theme_font_size_override("font_size", 22)
	_toast_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	_toast_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_toast_label.add_theme_constant_override("shadow_outline_size", 4)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast_label.position.y -= 180
	_toast_label.modulate.a = 0.0
	add_child(_toast_label)

func _refresh_bag_panel() -> void:
	if not bag_grid:
		return
	# Clear existing slots synchronously (use .free() so no await needed)
	for c in bag_grid.get_children():
		bag_grid.remove_child(c)
		c.queue_free()
	
	var p = get_tree().get_first_node_in_group("player")
	if not p:
		return
	var inv = p.get_node_or_null("Inventory")
	if not inv:
		return
	
	# Update slot count
	var count_lbl = inventory_panel.get_node_or_null("SlotCountLabel")
	if count_lbl:
		count_lbl.text = str(inv.items.size()) + " / " + str(inv.MAX_SLOTS)
	
	# Populate filled slots
	for item in inv.items:
		_make_bag_slot(item, inv)
	
	# Fill remaining empty slots up to 20 visible empties
	var empty_count = max(0, min(20, inv.MAX_SLOTS - inv.items.size()))
	for _i in range(empty_count):
		var empty_slot = Panel.new()
		empty_slot.custom_minimum_size = Vector2(118, 72)
		var es_bg = StyleBoxFlat.new()
		es_bg.bg_color = Color(0.1, 0.09, 0.12, 0.7)
		es_bg.border_color = Color(0.25, 0.25, 0.3)
		es_bg.set_border_width_all(1)
		es_bg.set_corner_radius_all(4)
		empty_slot.add_theme_stylebox_override("panel", es_bg)
		bag_grid.add_child(empty_slot)

func _make_bag_slot(item: Dictionary, inv: Node) -> void:
	var item_id: String = item.get("id", "")
	var item_type: String = item.get("type", "")
	var qty: int = item.get("quantity", 1)
	var display_name: String = item.get("name", item_id.replace("_", " ").capitalize())
	var icon: String = inv.ITEM_DB.get(item_id, {}).get("icon", "⬜")
	
	var slot_btn = Button.new()
	slot_btn.custom_minimum_size = Vector2(118, 72)
	
	# Slot background style
	var sb = StyleBoxFlat.new()
	match item_type:
		"weapon":    sb.bg_color = Color(0.18, 0.10, 0.08, 0.95)
		"armor":     sb.bg_color = Color(0.08, 0.13, 0.18, 0.95)
		"accessory": sb.bg_color = Color(0.15, 0.08, 0.18, 0.95)
		"consumable":sb.bg_color = Color(0.08, 0.15, 0.10, 0.95)
		"quest":     sb.bg_color = Color(0.18, 0.16, 0.05, 0.95)
		_:           sb.bg_color = Color(0.12, 0.11, 0.14, 0.95)
	sb.border_color = Color(0.4, 0.38, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	slot_btn.add_theme_stylebox_override("normal", sb)
	var sb_hover = sb.duplicate()
	sb_hover.border_color = Color(0.85, 0.7, 0.3)
	sb_hover.border_width_top = 2; sb_hover.border_width_bottom = 2
	sb_hover.border_width_left = 2; sb_hover.border_width_right = 2
	slot_btn.add_theme_stylebox_override("hover", sb_hover)
	
	# Slot text
	var slot_lbl = RichTextLabel.new()
	slot_lbl.bbcode_enabled = true
	slot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot_lbl.add_theme_font_size_override("normal_font_size", 12)
	var qty_str = " x" + str(qty) if qty > 1 else ""
	slot_lbl.text = "[center]" + icon + "\n" + display_name + qty_str + "[/center]"
	slot_btn.add_child(slot_lbl)
	
	# Main Click Action: Use or Equip
	var can_equip = inv.ITEM_DB.get(item_id, {}).has("slot")
	var is_consumable = item_type == "consumable"
	var cap_id = item_id
	
	if can_equip or is_consumable:
		slot_btn.pressed.connect(func():
			var p2 = get_tree().get_first_node_in_group("player")
			if not p2: return
			var inv2 = p2.get_node_or_null("Inventory")
			if not inv2: return
			if can_equip:
				inv2.equip_item(cap_id)
				if active_panel == "inventory": _refresh_bag_panel()
				elif active_panel == "character": _refresh_character_panel()
			else:
				inv2.use_item(cap_id)
				_refresh_bag_panel()
		)
	
	# Drop Button: Small button in the corner of the slot
	var drop_btn = Button.new()
	drop_btn.text = "🗑"
	drop_btn.add_theme_font_size_override("font_size", 10)
	drop_btn.custom_minimum_size = Vector2(24, 24)
	drop_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	drop_btn.offset_left = -28
	drop_btn.offset_top = 4
	drop_btn.pressed.connect(func():
		var p2 = get_tree().get_first_node_in_group("player")
		if p2:
			var inv2 = p2.get_node_or_null("Inventory")
			if inv2 and inv2.has_method("drop_item"):
				inv2.drop_item(cap_id)
				_refresh_bag_panel()
	)
	slot_btn.add_child(drop_btn)
	
	bag_grid.add_child(slot_btn)

# ─── Loading Screen ───────────────────────────────────────────────────────────
func _create_loading_screen() -> void:
	_loading_screen = ColorRect.new()
	_loading_screen.name = "LoadingScreen"
	_loading_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_screen.color = Color(0.05, 0.05, 0.08, 1.0)
	_loading_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE # Don't block clicks!
	_loading_screen.z_index = 100
	add_child(_loading_screen)
	
	var label = Label.new()
	label.text = "SYNCHRONIZING DARK REALM..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading_screen.add_child(label)
	
	# Auto-dismiss after 10 seconds as a failsafe (increased for 4-player sync)
	get_tree().create_timer(10.0).timeout.connect(hide_loading_screen)

func hide_loading_screen() -> void:
	if _loading_screen and _loading_screen.visible:
		var tween = create_tween()
		tween.tween_property(_loading_screen, "modulate:a", 0.0, 0.5)
		tween.tween_callback(_loading_screen.hide)
		print("[HUD] Loading screen dismissed.")

func _on_force_sync_pressed() -> void:
	print("[HUD] Manual Sync Requested via Character Panel.")
	var wm = get_tree().get_first_node_in_group("world_manager")
	if wm and wm.has_method("force_manual_sync"):
		wm.force_manual_sync()

func _on_network_sync(id: int, _data: Dictionary) -> void:
	if id == multiplayer.get_unique_id():
		# Local player is synced, wait a tiny bit for world to settle then hide
		get_tree().create_timer(1.0).timeout.connect(hide_loading_screen)

# ─── Pickup Toast ─────────────────────────────────────────────────────────────
func show_pickup_toast(item_name: String, qty: int) -> void:
	if not _toast_label:
		return
	var qty_str = " x" + str(qty) if qty > 1 else ""
	_toast_label.text = "+ " + item_name + qty_str
	var tween = create_tween()
	tween.tween_property(_toast_label, "modulate:a", 1.0, 0.15)
	tween.tween_interval(1.8)
	tween.tween_property(_toast_label, "modulate:a", 0.0, 0.5)

func show_toast(text: String) -> void:
	var lbl = find_child("AbilityLabel", true, false)
	if lbl:
		lbl.text = text
		var tween = create_tween()
		tween.tween_property(lbl, "modulate", Color.GOLD, 0.1)
		tween.tween_property(lbl, "modulate", Color.WHITE, 0.3).set_delay(0.1)

func update_ability_slots() -> void:
	# Update the action bar icons/labels
	var slot1 = find_child("Slot1_Label", true, false)
	var slot2 = find_child("Slot2_Label", true, false)
	
	if slot1:
		slot1.text = "Primary\n[LMB]"
	if slot2:
		slot2.text = "Block\n[RMB]"
		
	# Update 1 and 2 slots based on class abilities
	var abilities = []
	var class_data = ClassData.get_all_classes()
	for c in class_data:
		if c["name"] == PlayerData.char_class:
			abilities = c["abilities"]
			break
			
	var slot3 = find_child("Slot3_Label", true, false)
	var slot4 = find_child("Slot4_Label", true, false)
	
	if slot3 and abilities.size() > 0:
		var player = get_tree().get_first_node_in_group("local_player")
		var idx = 0
		if player and player.combat_system:
			idx = player.combat_system.active_spell_index
		
		slot3.text = abilities[idx]["name"] + "\n[1]"
		slot3.add_theme_color_override("font_color", Color.GOLD)
		
	if slot4:
		slot4.text = "Cycle\n[2]"
