## SaveSystem.gd
## Handles saving and loading player data to JSON files (3 save slots).
extends Node

var SAVE_DIR = "user://saves/"
const SAVE_SLOTS = 3

# ─── Signals ───────────────────────────────────────────────────────────────────
signal game_saved(slot: int)
signal game_loaded(slot: int)

var _instance_lock: TCPServer # Holds a port to mark this instance as "primary"

# ─── Save ──────────────────────────────────────────────────────────────────────
func save_game(slot: int) -> bool:
	var path = _get_save_path(slot)
	var data = _build_save_data(slot)
	var json_str = JSON.stringify(data, "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveSystem] Could not open save file for writing: " + path)
		return false
	file.store_string(json_str)
	file.close()
	emit_signal("game_saved", slot)
	print("[SaveSystem] Game saved to slot ", slot)
	return true

func auto_save() -> void:
	if PlayerData.character_name != "":
		save_game(PlayerData.save_slot)

# ─── Load ──────────────────────────────────────────────────────────────────────
func load_game(slot: int) -> bool:
	var path = _get_save_path(slot)
	if not FileAccess.file_exists(path):
		push_error("[SaveSystem] No save file found at slot " + str(slot))
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var json_str = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(json_str)
	if err != OK:
		push_error("[SaveSystem] JSON parse error in slot " + str(slot))
		return false
	var data = json.data
	_restore_save_data(data, slot)
	emit_signal("game_loaded", slot)
	print("[SaveSystem] Game loaded from slot ", slot)
	return true

# ─── Slot Info ─────────────────────────────────────────────────────────────────
func get_save_slot_info(slot: int) -> Dictionary:
	## Returns metadata about a save slot without fully loading it
	var path = _get_save_path(slot)
	if not FileAccess.file_exists(path):
		return {"exists": false, "slot": slot}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"exists": false, "slot": slot}
	var json_str = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(json_str) != OK:
		return {"exists": false, "slot": slot}
	var data = json.data
	return {
		"exists": true,
		"slot": slot,
		"character_name": data.get("player", {}).get("character_name", "Unknown"),
		"race": data.get("player", {}).get("race", ""),
		"char_class": data.get("player", {}).get("char_class", ""),
		"level": data.get("player", {}).get("level", 1),
		"zone": data.get("player", {}).get("current_zone", ""),
		"saved_at": data.get("saved_at", "")
	}

func get_all_save_slots() -> Array:
	var slots = []
	for i in range(SAVE_SLOTS):
		slots.append(get_save_slot_info(i))
	return slots

func delete_save(slot: int) -> void:
	var path = _get_save_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		print("[SaveSystem] Deleted save slot ", slot)

# ─── Internal ──────────────────────────────────────────────────────────────────
func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)

func _get_save_path(slot: int) -> String:
	_ensure_save_dir()
	return SAVE_DIR + "save_slot_" + str(slot) + ".json"

func _build_save_data(slot: int) -> Dictionary:
	return {
		"version": "1.0",
		"saved_at": Time.get_datetime_string_from_system(),
		"slot": slot,
		"player": PlayerData.to_dict(),
		"quests": QuestManager.get_save_data(),
		"inventory": _get_inventory_data(),
	}

func _restore_save_data(data: Dictionary, slot: int) -> void:
	var player_data = data.get("player", {})
	PlayerData.from_dict(player_data)
	PlayerData.save_slot = slot
	var quest_data = data.get("quests", {})
	if not quest_data.is_empty():
		QuestManager.load_save_data(quest_data)

func _get_inventory_data() -> Dictionary:
	## Retrieve inventory from player node if available
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0].has_node("Inventory"):
		var inv = players[0].get_node("Inventory")
		if inv.has_method("to_dict"):
			return inv.to_dict()
	return {}

func _ready() -> void:
	_detect_instance_and_split_data()
	_ensure_save_dir()

func _detect_instance_and_split_data() -> void:
	# We try to bind local ports to detect which instance index we are.
	# Instance 1: Port 19999
	# Instance 2: Port 20000
	# Instance 3: Port 20001
	# Instance 4: Port 20002
	
	var base_port = 19999
	var instance_index = 1
	
	for i in range(4):
		var server = TCPServer.new()
		var err = server.listen(base_port + i)
		if err == OK:
			_instance_lock = server
			instance_index = i + 1
			if instance_index == 1 or instance_index == 0:
				SAVE_DIR = "user://saves_test_host/"
				print("[SaveSystem] Test Host Instance: Using folder ", SAVE_DIR)
				_wipe_test_instance_data(SAVE_DIR)
			else:
				SAVE_DIR = "user://saves_instance_" + str(instance_index) + "/"
				print("[SaveSystem] Test Peer Instance ", instance_index, ": Using folder ", SAVE_DIR)
				_wipe_test_instance_data(SAVE_DIR)
				
				# Ensure directory exists
				if not DirAccess.dir_exists_absolute(SAVE_DIR):
					DirAccess.make_dir_recursive_absolute(SAVE_DIR)
			break
	
	# Always create default test saves for all test instances (1-4)
	_create_default_test_saves(instance_index)

func _wipe_test_instance_data(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		var dir = DirAccess.open(path)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if not dir.current_is_dir():
					dir.remove(file_name)
				file_name = dir.get_next()
			print("[SaveSystem] Wiped existing test data at: ", path)

func _create_default_test_saves(instance_idx: int) -> void:
	var path = _get_save_path(0)
	if FileAccess.file_exists(path): return
	
	print("[SaveSystem] Creating default test save for Instance ", instance_idx)
	var names = ["Darcy Mark Dent", "Gorak Doom", "Lyra Nightshade", "Thrum Goldbeard"]
	var races = ["Human", "Orc", "Elf", "Dwarf"]
	var classes = ["Warrior", "Ranger", "Mage", "Rogue"]
	var colors = [Color("#ffe0c0"), Color("#608060"), Color("#e0c0f0"), Color("#d0b090")]
	
	var idx = clamp(instance_idx - 1, 0, 3)
	
	var test_data = {
		"version": "1.0",
		"saved_at": Time.get_datetime_string_from_system(),
		"slot": 0,
		"player": {
			"character_name": names[idx],
			"race": races[idx],
			"char_class": classes[idx],
			"gender": "male",
			"level": idx + 1,
			"experience": 0,
			"strength": 12,
			"dexterity": 10,
			"intelligence": 10,
			"constitution": 12,
			"wisdom": 10,
			"charisma": 10,
			"current_hp": 100 + (idx * 20),
			"max_hp": 100 + (idx * 20),
			"current_mana": 50,
			"max_mana": 50,
			"appearance_config": {
				"skin_color": colors[idx],
				"muscle": 1.0,
				"clothing_type": "shirt_pants"
			}
		}
	}
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(test_data, "\t"))
		file.close()
