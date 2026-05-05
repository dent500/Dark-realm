## NetworkManager.gd
## Autoloaded singleton that manages Steam P2P connections and player synchronization.
extends Node

signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal player_data_synced(id: int, data: Dictionary)
signal player_appearance_updated(id: int, data: Dictionary)
signal server_disconnected
signal chat_message_received(sender_name: String, message: String, color: Color)
signal connection_succeeded
signal connection_failed
signal lobby_id_received(id: int)

const MAX_CLIENTS = 4

# Steam Data
var is_steam_running: bool = false
var steam_id: int = 0
var steam_name: String = ""
var lobby_id: int = 0
var steam_peer: SteamMultiplayerPeer

# Store peer character data: { peer_id: { "appearance": {...}, "name": "...", ... } }
var peer_data = {}

func _ready() -> void:
	_initialize_steam()
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	
	# Ensure we start in a clean offline state
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _process(_delta: float) -> void:
	if is_steam_running:
		Steam.run_callbacks()

func _initialize_steam() -> void:
	var response: Dictionary = Steam.steamInitEx()
	print("[Steam] Status: ", response)
	
	if response["status"] > 0:
		print("[Steam] Failed to initialize: ", response["verbal"])
		is_steam_running = false
		return
		
	is_steam_running = true
	steam_id = Steam.getSteamID()
	steam_name = Steam.getPersonaName()
	print("[Steam] Initialized as: ", steam_name, " (", steam_id, ")")
	
	# Necessary for Steam Relay (bypasses port forwarding)
	Steam.initRelayNetworkAccess()
	
	# Connect Steam Signals
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_lobby_join_requested)

# ─── Steam Callbacks ─────────────────────────────────────────────────────────

func _on_lobby_created(connect: int, l_id: int) -> void:
	if connect != 1:
		print("[Steam] Failed to create lobby.")
		return
	
	lobby_id = l_id
	print("[Steam] Lobby created: ", lobby_id)
	
	# Set lobby data
	Steam.setLobbyData(lobby_id, "name", steam_name + "'s Game")
	Steam.setLobbyJoinable(lobby_id, true)
	
	# Initialize the peer as server
	steam_peer = SteamMultiplayerPeer.new()
	var err = steam_peer.create_host(0) # 0 is the default host port/ID for Steam
	if err != OK:
		print("[Steam] Failed to create host peer: ", err)
		return
		
	multiplayer.multiplayer_peer = steam_peer
	_register_player(1, PlayerData.to_dict())
	emit_signal("lobby_id_received", lobby_id)
	system_message("Lobby created! ID: " + str(lobby_id))

func _on_lobby_joined(l_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:
		print("[Steam] Failed to join lobby: ", response)
		emit_signal("connection_failed")
		return
		
	lobby_id = l_id
	print("[Steam] Joined lobby: ", lobby_id)
	
	steam_peer = SteamMultiplayerPeer.new()
	var err = steam_peer.create_client(Steam.getLobbyOwner(lobby_id))
	if err != OK:
		print("[Steam] Failed to create client peer: ", err)
		return
		
	multiplayer.multiplayer_peer = steam_peer
	emit_signal("connection_succeeded")

func _on_lobby_join_requested(l_id: int, _friend_id: int) -> void:
	print("[Steam] Join requested for lobby: ", l_id)
	join_lobby(l_id)

# ─── Connection Methods ──────────────────────────────────────────────────────

func host_game() -> int:
	if not is_steam_running:
		printerr("[NetworkManager] Cannot host: Steam not running.")
		return ERR_CANT_CONNECT
		
	# Create a Steam Lobby
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, MAX_CLIENTS)
	return OK

func join_lobby(l_id: int) -> void:
	if not is_steam_running: return
	Steam.joinLobby(l_id)

func join_game(address: String) -> Error:
	# Fallback/Compatibility: If address is a number, treat as Lobby ID
	if address.is_valid_int():
		join_lobby(address.to_int())
		return OK
	
	print("[NetworkManager] Direct IP joining is disabled in Steam mode. Use Lobby ID.")
	return ERR_CANT_CONNECT

# ─── Internal Registration ───────────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	print("[NetworkManager] Peer connected: ", id)
	if multiplayer.is_server():
		rpc_id(id, "register_player_from_server", 1, PlayerData.to_dict())
		for peer_id in peer_data:
			if peer_id != id and peer_id != 1:
				rpc_id(id, "register_player_from_server", peer_id, peer_data[peer_id])
	
	if not multiplayer.is_server():
		rpc_id(1, "register_player", PlayerData.to_dict())
		
	emit_signal("peer_connected", id)

func _on_peer_disconnected(id: int) -> void:
	print("[NetworkManager] Peer disconnected: ", id)
	peer_data.erase(id)
	emit_signal("peer_disconnected", id)

func _on_server_disconnected() -> void:
	print("[NetworkManager] Server disconnected.")
	peer_data.clear()
	emit_signal("server_disconnected")
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_connected_to_server() -> void:
	print("[NetworkManager] Successfully connected to server via Steam.")
	emit_signal("connection_succeeded")

func _on_connection_failed() -> void:
	print("[NetworkManager] Connection failed.")
	emit_signal("connection_failed")
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

@rpc("any_peer", "reliable")
func register_player(data: Dictionary) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	_register_player(sender_id, data)
	if multiplayer.is_server():
		for peer_id in multiplayer.get_peers():
			if peer_id != sender_id:
				register_player_from_server.rpc_id(peer_id, sender_id, data)

@rpc("any_peer", "reliable")
func request_player_relay() -> void:
	if multiplayer.is_server():
		var requester_id = multiplayer.get_remote_sender_id()
		for peer_id in peer_data:
			if peer_id != requester_id:
				register_player_from_server.rpc_id(requester_id, peer_id, peer_data[peer_id])

@rpc("authority", "reliable")
func register_player_from_server(id: int, data: Dictionary) -> void:
	_register_player(id, data)
	var wm = get_tree().get_first_node_in_group("world_manager")
	if wm and wm.has_method("ensure_player_spawned"):
		wm.ensure_player_spawned(id)

func _register_player(id: int, data: Dictionary) -> void:
	print("[NetworkManager] Registering player ", id, ": ", data.get("character_name", "Unknown"))
	peer_data[id] = data
	emit_signal("player_appearance_updated", id, data)
	emit_signal("player_data_synced", id, data)

# ─── Helpers ─────────────────────────────────────────────────────────────────

func shutdown() -> void:
	print("[NetworkManager] Shutting down networking...")
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
		lobby_id = 0
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer_data.clear()

func is_multiplayer_active() -> bool:
	var peer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func get_player_data(id: int) -> Dictionary:
	return peer_data.get(id, {})

# ─── Chat System ─────────────────────────────────────────────────────────────

func send_chat_message(message: String) -> void:
	if not is_multiplayer_active():
		emit_signal("chat_message_received", PlayerData.character_name, message, Color.WHITE)
		return
	rpc("receive_chat_message", PlayerData.character_name, message)

@rpc("any_peer", "call_local", "reliable")
func receive_chat_message(sender_name: String, message: String) -> void:
	var id = multiplayer.get_remote_sender_id()
	var color = Color.WHITE
	if id == 1: color = Color(0.9, 0.8, 0.4)
	elif id == multiplayer.get_unique_id(): color = Color(0.6, 0.8, 1.0)
	emit_signal("chat_message_received", sender_name, message, color)

func system_message(message: String) -> void:
	emit_signal("chat_message_received", "[SYSTEM]", message, Color.GRAY)
