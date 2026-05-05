## WorldManager.gd
## Attached to the world scene. Manages day/night lighting, zone transitions,
## weather, auto-save intervals, and enemy/NPC spawning.
extends Node3D

# ─── Nodes ────────────────────────────────────────────────────────────────────
@onready var sun: DirectionalLight3D = find_child("Sun", true, false)
@onready var world_env: WorldEnvironment = find_child("WorldEnvironment", true, false)
@onready var hud: HUD = get_tree().get_first_node_in_group("hud")


# ─── Config ────────────────────────────────────────────────────────────────────
@export var auto_save_interval: float = 120.0  # every 2 minutes
@export var enable_weather: bool = true

# ─── State ────────────────────────────────────────────────────────────────────
var auto_save_timer: float = 0.0
var current_weather: String = "clear"
var weather_timer: float = 0.0
var weather_duration: float = 60.0
var watchdog_timer: Timer

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("world_manager")
	
	# Start the Visibility Watchdog to ensure everyone is spawned and visible
	watchdog_timer = Timer.new()
	watchdog_timer.wait_time = 3.0 # Check every 3 seconds
	watchdog_timer.autostart = true
	watchdog_timer.timeout.connect(_on_watchdog_timeout)
	add_child(watchdog_timer)
	print("[WorldManager] Visibility Watchdog started.")
	
	# Handle disconnections
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
	# Configure Cinematic Environment
	if world_env and world_env.environment:
		var env = world_env.environment
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.0
		
		# SSAO for grounded characters and ground-crease shadows
		env.ssao_enabled = true
		env.ssao_radius = 1.0
		env.ssao_intensity = 2.0
		
		# SSR for shiny gear and water
		env.ssr_enabled = true
		
		# Glow for cinematic bloom
		env.glow_enabled = true
		env.glow_intensity = 0.5
		env.glow_strength = 1.0
		env.glow_bloom = 0.05
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Initial AI narration for zone arrival
	AIDungeonMaster.narrate_arrival(PlayerData.current_zone)

	# Networking Initialization
	if NetworkManager.is_multiplayer_active():
		if multiplayer.is_server():
			print("[WorldManager] Server initializing. Spawning host player.")
			_spawn_player_multi(1)
			# IMPORTANT: The server waits for the client to say they are ready before spawning
			if not multiplayer.peer_connected.is_connected(_on_peer_connected):
				multiplayer.peer_connected.connect(_on_peer_connected)
			if not multiplayer.peer_disconnected.is_connected(_despawn_player):
				multiplayer.peer_disconnected.connect(_despawn_player)
		else:
			print("[WorldManager] Client world ready. Notifying server...")
			# Notify server that we are ready to be spawned
			notify_server_ready.rpc_id(1)

	else:
		# Spawn player at last saved position (Singleplayer)
		_spawn_player()

func _on_peer_connected(id: int) -> void:
	print("[WorldManager] Peer connected: ", id, ". Waiting for ready signal...")

@rpc("any_peer", "call_local", "reliable")
func notify_server_ready() -> void:
	var id = multiplayer.get_remote_sender_id()
	print("[WorldManager] Peer ", id, " is ready. Spawning player and syncing others...")
	_spawn_player_multi(id)
	
	# RECOVERY STEP: 
	# 1. Resend all EXISTING players to this new peer
	for p in get_tree().get_nodes_in_group("player"):
		var p_id = int(p.name.replace("@", "").replace("Player", ""))
		if p_id > 0 and p_id != id:
			var data = NetworkManager.peer_data.get(p_id, {})
			if not data.is_empty():
				NetworkManager.register_player_from_server.rpc_id(id, p_id, data)
				print("[WorldManager] Relaying existing peer ", p_id, " to new peer ", id)
	
	# 2. Tell ALL peers (including host) to verify their view of this NEW player
	# This ensures the 4th player doesn't stay invisible
	for peer_id in multiplayer.get_peers():
		var data = NetworkManager.peer_data.get(id, {})
		NetworkManager.register_player_from_server.rpc_id(peer_id, id, data)

func _on_watchdog_timeout() -> void:
	# Only spawn missing nodes if absolutely necessary
	# Using peer_data as the source of truth for who SHOULD be here
	for peer_id in NetworkManager.peer_data:
		if peer_id != multiplayer.get_unique_id():
			ensure_player_spawned(peer_id)
			
	# If we are missing players relative to what the HUD party list says, request a fresh relay
	var player_count = get_tree().get_nodes_in_group("player").size()
	var data_count = NetworkManager.peer_data.size() + 1
	
	if player_count < data_count:
		print("[WorldManager] WATCHDOG: Mismatch detected (", player_count, "/", data_count, "). Auto-Relaying...")
		NetworkManager.request_player_relay.rpc_id(1)

func _on_peer_disconnected(id: int) -> void:
	print("[WorldManager] Peer ", id, " disconnected. Cleaning up node.")
	var players_node = get_node_or_null("Players")
	if players_node and players_node.has_node(str(id)):
		players_node.get_node(str(id)).queue_free()

func _process(delta: float) -> void:
	_update_sun_position()
	_update_auto_save(delta)
	if enable_weather:
		_update_weather(delta)

# ─── Player Spawning ──────────────────────────────────────────────────────────
func _spawn_player() -> void:
	# Singleplayer spawning
	var player_scene = load("res://scenes/player.tscn")
	var player = player_scene.instantiate()
	player.name = "Player"
	# Add to group so terrain snapper can find it
	player.add_to_group("player")
	add_child(player)

	# If last_position is saved, use it directly
	if PlayerData.last_position != Vector3.ZERO:
		player.global_position = PlayerData.last_position
	else:
		# Spawn slightly above the typical 70m terrain peak. 
		# MapLoader._teleport_to_scene_spawn will perform the final teleport.
		player.global_position = Vector3(0, 75, 0)
	
	var inv = player.get_node_or_null("Inventory")
	if inv and inv.items.is_empty():
		inv.grant_starting_items()


func force_manual_sync() -> void:
	print("[WorldManager] Manual Sync Triggered. Rebuilding all remote visuals...")
	var players_node = get_node_or_null("Players")
	if players_node:
		for child in players_node.get_children():
			var p_id = int(child.name.replace("@", "").replace("Player", ""))
			if p_id > 0 and p_id != multiplayer.get_unique_id():
				# INSTEAD OF DELETING: Just force a rebuild of the visuals
				if child.has_method("_build_native_block_character"):
					var data = NetworkManager.peer_data.get(p_id, {})
					if not data.is_empty():
						print("[WorldManager] Force-rebuilding visuals for peer ", p_id)
						child._build_native_block_character(data)
	
	# Also request fresh data from server just in case
	NetworkManager.request_player_relay.rpc_id(1)
	
func ensure_player_spawned(id: int) -> void:
	var players_node = get_node_or_null("Players")
	if not players_node: return
	
	if not players_node.has_node(str(id)):
		print("[WorldManager] WATCHDOG RECOVERY: Spawning node for peer ", id)
		_spawn_player_multi(id)

func _spawn_player_multi(id: int) -> void:
	# Server handles the spawn and broadcasts it to everyone manually
	if multiplayer.is_server():
		_do_spawn.rpc(id)
	else:
		# Clients can spawn themselves locally if they know about the peer
		_do_spawn(id)

@rpc("authority", "call_local", "reliable")
func _do_spawn(id: int) -> void:
	var players_node = get_node_or_null("Players")
	if not players_node: return
	
	# Safety check to avoid double-spawning
	if players_node.has_node(str(id)): 
		print("[WorldManager] Player ", id, " already exists. Skipping spawn.")
		return
	
	print("[WorldManager] Manual RPC Spawning player for peer: ", id)
	var player_scene = load("res://scenes/player.tscn")
	var player = player_scene.instantiate()
	player.name = str(id)
	
	# Set authority immediately
	player.set_multiplayer_authority(id)
	
	# Safe Spawn: Add a small random offset to prevent physics explosions (flying into sky)
	var offset = Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	player.position = Vector3(30, 10, -20) + offset 
	
	players_node.add_child(player)
	
	# Initial data sync
	var peer_info = NetworkManager.get_player_data(id)
	if not peer_info.is_empty() and "sync_custom_data" in player:
		player.sync_custom_data = peer_info

	var spawn_pos = PlayerData.last_position if id == 1 else Vector3(0, 1, 0)
	
	# If this is a joining client, try to spawn them near the host so they aren't in the void
	if id != 1:
		var host = players_node.get_node_or_null("1") if players_node else get_node_or_null("1")
		if host:
			spawn_pos = host.global_position + Vector3(randf_range(-2,2), 0, randf_range(-2,2))
	
	player.global_position = spawn_pos
	print("[WorldManager] Player ", id, " spawned at ", spawn_pos)
	
	if spawn_pos == Vector3.ZERO:
		var spawns = get_tree().get_nodes_in_group("spawn_point")
		if spawns.size() > 0:
			spawn_pos = spawns[0].global_position
	
	player.global_position = spawn_pos
	
	# We no longer push authority from server to client here
	# because the client might not have spawned the node yet.
	# The client will request authority in its own _ready() via RPC.

func _despawn_player(id: int) -> void:
	var p = get_node_or_null(str(id))
	if p: p.queue_free()

@rpc("any_peer", "call_local", "reliable")
func request_client_authority(path: NodePath) -> void:
	if not multiplayer.is_server(): return
	var id = multiplayer.get_remote_sender_id()
	var player = get_node_or_null(path)
	if player:
		print("[WorldManager] Client ", id, " requested authority for ", path)
		player.set_multiplayer_authority(id)
		# Tell the client we've assigned it
		confirm_client_authority.rpc_id(id, path)

@rpc("authority", "call_local", "reliable")
func confirm_client_authority(path: NodePath) -> void:
	var player = get_node_or_null(path)
	if player and player.has_method("setup_as_local"):
		player.setup_as_local()

# ─── Sun / Day-Night ──────────────────────────────────────────────────────────
func _update_sun_position() -> void:
	if not sun:
		return
	var t = GameManager.get_time_of_day_normalized()
	# Rotate sun from -90° (midnight) through 90° (noon) to 270° (midnight again)
	var angle = (t * 360.0) - 90.0
	sun.rotation_degrees.x = angle
	# Adjust intensity by time of day (night = 0.4, noon = 3.0)
	var sun_factor = clampf(sin(t * PI), 0.0, 1.0)
	sun.light_energy = lerp(0.4, 3.0, sun_factor)
	sun.light_color = _get_sun_color(t)
	# Adjust ambient via environment
	if world_env and world_env.environment:
		world_env.environment.ambient_light_energy = lerp(0.4, 1.5, sun_factor)

func _get_sun_color(t: float) -> Color:
	## Dawn/dusk = warm orange, noon = white, night = deep blue
	if t < 0.1 or t > 0.9:    # night
		return Color(0.2, 0.2, 0.5)
	elif t < 0.2 or t > 0.8:  # dawn/dusk
		return Color(1.0, 0.5, 0.2)
	else:                       # day
		return Color(1.0, 0.95, 0.85)

func _on_day_night_changed(is_day: bool) -> void:
	if is_day:
		AIDungeonMaster.narrate_custom("Dawn breaks over the cursed land. A cold grey light seeps through the twisted trees.")
	else:
		AIDungeonMaster.narrate_custom("Darkness falls like a burial shroud. The sounds of unseen things stir in the night.")

# ─── Auto Save ────────────────────────────────────────────────────────────────
func _update_auto_save(delta: float) -> void:
	auto_save_timer += delta
	if auto_save_timer >= auto_save_interval:
		auto_save_timer = 0.0
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			PlayerData.last_position = players[0].global_position
		SaveSystem.auto_save()
		print("[WorldManager] Auto-saved.")

# ─── Weather ──────────────────────────────────────────────────────────────────
func _update_weather(delta: float) -> void:
	weather_timer += delta
	if weather_timer >= weather_duration:
		weather_timer = 0.0
		weather_duration = randf_range(45.0, 180.0)
		_change_weather()

func _change_weather() -> void:
	var options = ["clear", "clear", "clear", "rain", "rain", "thunder"]
	var new_weather = options[randi() % options.size()]
	if new_weather == current_weather:
		return
	current_weather = new_weather
	match current_weather:
		"rain":
			AIDungeonMaster.narrate_custom("Rain begins to fall from iron-grey clouds, turning the earth to mud.")
			if world_env and world_env.environment:
				world_env.environment.fog_enabled = true
				world_env.environment.fog_density = 0.015
		"thunder":
			AIDungeonMaster.narrate_custom("Thunder splits the sky. Lightning illuminates the horizon in ghostly white pulses.")
			if world_env and world_env.environment:
				world_env.environment.fog_density = 0.025
		"clear":
			if world_env and world_env.environment:
				world_env.environment.fog_enabled = false
				world_env.environment.fog_density = 0.005

# ─── Zone Transition ──────────────────────────────────────────────────────────
func transition_to_zone(zone_name: String, spawn_pos: Vector3) -> void:
	PlayerData.current_zone = zone_name
	PlayerData.last_position = spawn_pos
	SaveSystem.auto_save()
	AIDungeonMaster.narrate_arrival(zone_name)
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		players[0].global_position = spawn_pos
