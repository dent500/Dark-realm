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


# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	print("=== [WorldManager] _ready() v2 LOADED — script is up to date ===")
	add_to_group("world_manager")
	
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
	# ─── Essential World Nodes ────────────────────────────────────────────────────
	_ensure_essential_world_nodes()
	
	# ─── Networking Initialization ───────────────────────────────────────────────
	if multiplayer.multiplayer_peer:
		_run_network_init()
		

	var peer = multiplayer.multiplayer_peer
	var conn_status: int = MultiplayerPeer.CONNECTION_DISCONNECTED
	if peer != null:
		conn_status = peer.get_connection_status()
	
	if conn_status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		# No active peer — singleplayer
		_spawn_player()
	elif conn_status == MultiplayerPeer.CONNECTION_CONNECTED:
		# Already fully connected (host or very fast client)
		pass
	else:
		# STATUS = CONNECTION_CONNECTING — P2P handshake in progress
		print("[WorldManager] Steam P2P connecting. Waiting for handshake signal...")
		if not multiplayer.connected_to_server.is_connected(_on_p2p_connected_to_server):
			multiplayer.connected_to_server.connect(_on_p2p_connected_to_server, CONNECT_ONE_SHOT)
		
		# Robustness Fallback: Poll every 0.5s for 5s in case we missed the signal
		# (Signals can sometimes be lost during scene transitions if timing is tight)
		_poll_for_connection_success(0)

func _poll_for_connection_success(retry_count: int) -> void:
	if retry_count > 10: # 5 seconds max
		printerr("[WorldManager] ERROR: P2P handshake timeout after 5s.")
		if not NetworkManager.is_multiplayer_active():
			_spawn_player()
		return
		
	if NetworkManager.is_multiplayer_active():
		if multiplayer.connected_to_server.is_connected(_on_p2p_connected_to_server):
			multiplayer.connected_to_server.disconnect(_on_p2p_connected_to_server)
		print("[WorldManager] Connection confirmed via polling fallback.")
		_run_network_init()
		return
		
	await get_tree().create_timer(0.5).timeout
	_poll_for_connection_success(retry_count + 1)

func _on_p2p_connected_to_server() -> void:
	print("[WorldManager] P2P handshake complete. Running client network init.")
	_run_network_init()

func _run_network_init() -> void:
	var my_id = multiplayer.get_unique_id()
	print("[WorldManager] Running network init for peer: ", my_id)
	
	# 1. Spawn OURSELVES locally immediately
	_spawn_player_multi(my_id)
	
	# 2. Spawn any peers we already know about from NetworkManager
	# Specifically ensure the host (1) is checked first
	if 1 in NetworkManager.peer_data and my_id != 1:
		_spawn_player_multi(1)
		
	for peer_id in NetworkManager.peer_data:
		if peer_id != my_id and peer_id != 1:
			_spawn_player_multi(peer_id)
	
	# 3. If we are NOT the server, notify the server that we are ready to receive spawn data
	if not multiplayer.is_server():
		print("[WorldManager] Client ready. Notifying server and waiting for sync data...")
		notify_server_ready.rpc_id(1)
	else:
		# Server-specific listeners
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
		if not multiplayer.peer_disconnected.is_connected(_despawn_player):
			multiplayer.peer_disconnected.connect(_despawn_player)


func _ensure_essential_world_nodes() -> void:
	# Ensure WaveManager is active for endless skeleton waves
	if not has_node("WaveManager"):
		var wm = Node.new()
		wm.name = "WaveManager"
		wm.set_script(load("res://scripts/world/WaveManager.gd"))
		add_child(wm)
		print("[WorldManager] WaveManager initialized.")
	
	# Ensure WorldBuilder is active for initial environmental skeletons
	if not has_node("WorldBuilder"):
		var wb = Node3D.new()
		wb.name = "WorldBuilder"
		wb.set_script(load("res://scripts/world/WorldBuilder.gd"))
		var loader = get_node_or_null("MapLoader")
		if loader and "enemy_scene" in loader:
			wb.enemy_scene = loader.enemy_scene
		else:
			wb.enemy_scene = load("res://scenes/skeleton_enemy.tscn")
		add_child(wb)
		print("[WorldManager] WorldBuilder initialized.")

func _on_peer_connected(id: int) -> void:
	print("[WorldManager] Peer connected: ", id, ". Waiting for ready signal...")

# Only runs on the server — do NOT use call_local here
@rpc("any_peer", "reliable")
func notify_server_ready() -> void:
	if not multiplayer.is_server(): return
	var id = multiplayer.get_remote_sender_id()
	print("[WorldManager] Peer ", id, " is ready. Pushing full spawn and data relay...")
	
	# 1. First, send ALL known appearance data (including the host/server itself)
	# This ensures the client can resolve the character rigs for everyone
	NetworkManager.register_player_from_server.rpc_id(id, 1, PlayerData.to_dict())
	
	for p_id in NetworkManager.peer_data:
		if p_id != id: # No need to send the requester's own data back to them
			NetworkManager.register_player_from_server.rpc_id(id, p_id, NetworkManager.peer_data[p_id])
	
	# 2. Spawn the actual node on the server
	# The MultiplayerSpawner will replicate this to the client automatically
	_spawn_player_multi(id)



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
	
	if not players_node or not players_node.has_node(str(id)):
		print("[WorldManager] ensure_player_spawned: Triggering spawn for peer ", id)
		_spawn_player_multi(id)


func _spawn_player_multi(id: int) -> void:
	print("[WorldManager] _spawn_player_multi called for peer: ", id, " (Am Server: ", multiplayer.is_server(), ")")
	if not multiplayer.is_server():
		return # Clients should never spawn players manually when using MultiplayerSpawner
		
	if not has_node("Players"):
		var p_node = Node3D.new()
		p_node.name = "Players"
		add_child(p_node)
		print("[WorldManager] Created 'Players' container.")
	
	var players_node = get_node("Players")
	if players_node.has_node(str(id)):
		print("[WorldManager] Node already exists for peer ", id, ". Skipping.")
		return
		
	var player_scene = load("res://scenes/player.tscn")
	var player = player_scene.instantiate()
	player.name = str(id)
	
	# Detect if this is a simulated bot ID (9000-9999) BEFORE adding to tree
	if id >= 9000 and id < 10000:
		if "is_simulated" in player:
			player.is_simulated = true
			print("[WorldManager] Bot identity confirmed for: ", id)
	
	# Spawn HIGH to avoid falling through terrain while it generates
	player.global_position = Vector3(0, 150, 0)
	
	# IMPORTANT: Add to tree BEFORE setting authority if possible, 
	# but for MultiplayerSpawner, adding to tree triggers the spawn on clients.
	players_node.add_child(player)
	
	# Set authority so it replicates to clients correctly
	player.set_multiplayer_authority(id)
	
	print("[WorldManager] SERVER: Spawned player node for ", id, " in Players container.")
	
	# Initial data sync (pushed via MultiplayerSynchronizer automatically)
	var peer_info = NetworkManager.get_player_data(id)
	if not peer_info.is_empty() and "sync_custom_data" in player:
		player.sync_custom_data = peer_info

	# Only overwrite global_position if we have a valid last_position or spawn marker
	if PlayerData.last_position != Vector3.ZERO and id == 1:
		player.global_position = PlayerData.last_position
		print("[WorldManager] Player ", id, " restored to last position: ", PlayerData.last_position)
	else:
		# Keep the safe high-spawn position until terrain is ready
		print("[WorldManager] Player ", id, " initial safe spawn set to: ", player.global_position)
	
	# Only use spawn markers if we aren't restoring a saved position and aren't the high-spawn client
	if PlayerData.last_position == Vector3.ZERO or id != 1:
		var spawns = get_tree().get_nodes_in_group("spawn_point")
		if spawns.size() > 0 and id == 1: # Only host uses spawn markers initially
			player.global_position = spawns[0].global_position
			print("[WorldManager] Player ", id, " moved to spawn marker: ", player.global_position)


func spawn_simulated_peer() -> void:
	var bot_id = 9000 + randi() % 1000
	print("[WorldManager] Spawning simulated bot with ID: ", bot_id)
	
	# Register bot data in NetworkManager
	var bot_data = {
		"name": "Bot_" + str(bot_id),
		"appearance": {
			"race": ["human", "elf", "orc"][randi() % 3],
			"gender": ["male", "female"][randi() % 2],
			"skin_color": Color(randf(), randf(), randf(), 1.0).to_html()
		},
		"class": "Warrior"
	}
	NetworkManager.peer_data[bot_id] = bot_data
	
	_spawn_player_multi(bot_id)
	
	# Position the bot near the local player and ACTIVATE AI
	var players_node = get_node_or_null("Players")
	if players_node and players_node.has_node(str(bot_id)):
		var bot_node = players_node.get_node(str(bot_id))
		bot_node.is_simulated = true
		
		var local_player = get_tree().get_first_node_in_group("local_player")
		if local_player:
			bot_node.ai_target = local_player
			bot_node.global_position = local_player.global_position + Vector3(randf_range(-3,3), 0, randf_range(-3,3))
			print("[WorldManager] Bot AI activated near local player.")

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

@rpc("any_peer", "call_local", "reliable")
func confirm_client_authority(path: NodePath) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != 0 and not multiplayer.is_server() and sender_id != 1:
		return
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
