## Inventory.gd
## Attached to the Player node. Manages items (max 40 slots), gold display.
extends Node

# ─── Signals ───────────────────────────────────────────────────────────────────
signal inventory_changed
signal item_added(item: Dictionary)
signal item_removed(item: Dictionary)

# ─── Config ────────────────────────────────────────────────────────────────────
const MAX_SLOTS = 40

# ─── Data ─────────────────────────────────────────────────────────────────────
var items: Array[Dictionary] = []

# ─── Item Database ─────────────────────────────────────────────────────────
## Keys are item_id strings used everywhere. Slot matches PlayerData.equipped keys.
const ITEM_DB = {
	# ―― Consumables ――
	"health_potion":   {"name": "Health Potion",   "type": "consumable", "icon": "🧪", "value": 20,  "weight": 0.5, "effect": "heal_30"},
	"mana_crystal":    {"name": "Mana Crystal",    "type": "consumable", "icon": "🔮", "value": 25,  "weight": 0.3, "effect": "restore_mana_40"},
	"campfire_kit":    {"name": "Campfire Kit",    "type": "consumable", "icon": "🔥", "value": 15,  "weight": 1.5, "effect": "rest"},
	# ―― Weapons ――
	"iron_sword":      {"name": "Iron Sword",       "type": "weapon",    "icon": "⚔️",  "value": 80,  "weight": 3.0, "damage_bonus": 8,  "slot": "main_hand"},
	"iron_axe":        {"name": "Iron Axe",         "type": "weapon",    "icon": "🪓",  "value": 90,  "weight": 4.5, "damage_bonus": 10, "slot": "main_hand"},
	"iron_shield":     {"name": "Iron Shield",      "type": "armor",     "icon": "🛡️",  "value": 60,  "weight": 4.0, "defense_bonus": 5, "slot": "off_hand"},
	# ―― Armour ――
	"leather_armor":   {"name": "Leather Armor",    "type": "armor",     "icon": "🛡️",  "value": 50,  "weight": 8.0, "defense_bonus": 3, "slot": "body"},
	"chainmail":       {"name": "Chainmail",        "type": "armor",     "icon": "🛡️",  "value": 120, "weight": 14.0, "defense_bonus": 6, "slot": "body"},
	"steel_helmet":    {"name": "Steel Helmet",     "type": "armor",     "icon": "⛑️",  "value": 75,  "weight": 4.0, "defense_bonus": 3, "slot": "head"},
	"iron_boots":      {"name": "Iron Boots",       "type": "armor",     "icon": "🥾",  "value": 55,  "weight": 3.0, "defense_bonus": 2, "slot": "feet"},
	"iron_gloves":     {"name": "Iron Gloves",      "type": "armor",     "icon": "🧤",  "value": 45,  "weight": 2.0, "defense_bonus": 1, "damage_bonus": 1, "slot": "hands"},
	# ―― Accessories ――
	"ruby_ring":       {"name": "Ruby Ring",         "type": "accessory", "icon": "💍",  "value": 150, "weight": 0.1, "damage_bonus": 3,  "slot": "ring"},
	"silver_amulet":   {"name": "Silver Amulet",    "type": "accessory", "icon": "📿",  "value": 200, "weight": 0.1, "defense_bonus": 4, "slot": "amulet"},
	# ―― Materials ――
	"wood":            {"name": "Wood",              "type": "material",  "icon": "🪵",  "value": 2,   "weight": 1.0},
	"iron_ore":        {"name": "Iron Ore",          "type": "material",  "icon": "🪭",  "value": 8,   "weight": 2.0},
	"herbs":           {"name": "Healing Herbs",     "type": "material",  "icon": "🌿",  "value": 5,   "weight": 0.2},
	"wolf_pelt":       {"name": "Wolf Pelt",         "type": "material",  "icon": "🐺",  "value": 12,  "weight": 1.5},
	"goblin_tooth":    {"name": "Goblin Tooth",      "type": "material",  "icon": "🦷",  "value": 3,   "weight": 0.1},
	"dark_essence":    {"name": "Dark Essence",      "type": "material",  "icon": "🟣",  "value": 40,  "weight": 0.1},
	# ―― Quest Items ――
	"cracked_locket":  {"name": "Cracked Locket",    "type": "quest",     "icon": "🔐",  "value": 0,   "weight": 0.1},
	"merchant_ledger": {"name": "Merchant Ledger",   "type": "quest",     "icon": "📜",  "value": 0,   "weight": 0.3},
	# ―― Undead / Skeleton Loot ――
	"bone_fragment":   {"name": "Bone Fragment",    "type": "material",  "icon": "🦴",  "value": 5,   "weight": 0.1},
	"ancient_coin":    {"name": "Ancient Coin",     "type": "material",  "icon": "🪙",  "value": 15,  "weight": 0.01},
	"undead_ribs":     {"name": "Undead Ribs",      "type": "material",  "icon": "🥩",  "value": 8,   "weight": 0.5},
	"soul_essence":    {"name": "Soul Essence",     "type": "material",  "icon": "🔮",  "value": 50,  "weight": 0.1},
	"relic_of_old":    {"name": "Relic of Old",     "type": "accessory", "icon": "🏺",  "value": 350, "weight": 2.0, "defense_bonus": 5, "slot": "amulet"},
}

# ─── Add / Remove ─────────────────────────────────────────────────────────────
func add_item(item_id: String, quantity: int = 1) -> bool:
	if not ITEM_DB.has(item_id):
		push_error("[Inventory] Unknown item: " + item_id)
		return false
	# Stack with existing
	for existing in items:
		if existing["id"] == item_id and existing["type"] != "weapon" and existing["type"] != "armor":
			existing["quantity"] = existing.get("quantity", 1) + quantity
			emit_signal("inventory_changed")
			emit_signal("item_added", existing)
			return true
	if items.size() >= MAX_SLOTS:
		print("[Inventory] Inventory full!")
		return false
	var item = ITEM_DB[item_id].duplicate()
	item["id"] = item_id
	item["quantity"] = quantity
	items.append(item)
	emit_signal("inventory_changed")
	emit_signal("item_added", item)
	return true

func add_item_dict(item_data: Dictionary) -> bool:
	## Add a raw item dict (for loot drops)
	if item_data.has("id"):
		return add_item(item_data["id"], item_data.get("quantity", 1))
	# Raw dict without known ID
	items.append(item_data)
	emit_signal("inventory_changed")
	return true

func remove_item(item_id: String, quantity: int = 1) -> bool:
	for i in range(items.size()):
		if items[i]["id"] == item_id:
			var current_qty = items[i].get("quantity", 1)
			if current_qty < quantity:
				return false
			if current_qty == quantity:
				var removed = items[i]
				items.remove_at(i)
				emit_signal("inventory_changed")
				emit_signal("item_removed", removed)
			else:
				items[i]["quantity"] = current_qty - quantity
				emit_signal("inventory_changed")
			return true
	return false

func has_item(item_id: String, quantity: int = 1) -> bool:
	for item in items:
		if item["id"] == item_id:
			return item.get("quantity", 1) >= quantity
	return false

func get_item_count(item_id: String) -> int:
	for item in items:
		if item["id"] == item_id:
			return item.get("quantity", 1)
	return 0

# ─── Use Item ─────────────────────────────────────────────────────────────────
func use_item(item_id: String) -> bool:
	if not has_item(item_id):
		return false
	var item = ITEM_DB.get(item_id, {})
	var effect = item.get("effect", "")
	match effect:
		"heal_30":
			PlayerData.heal(30)
			print("[Inventory] Used Health Potion. +30 HP")
		"restore_mana_40":
			PlayerData.restore_mana(40)
			print("[Inventory] Used Mana Crystal. +40 Mana")
		"rest":
			PlayerData.current_stamina = PlayerData.max_stamina
			PlayerData.heal(int(PlayerData.max_hp * 0.2))
			print("[Inventory] Rested at campfire.")
			AIDungeonMaster.narrate_custom("You kindle a fire and rest for a while. The dark woods press close, but for now you are safe.")
		_:
			print("[Inventory] Item has no use effect: ", item_id)
			return false
	remove_item(item_id, 1)
	return true

# ─── Equipment ──────────────────────────────────────────────────────────────────
func equip_item(item_id: String) -> bool:
	## Move item from bag to the appropriate equipment slot in PlayerData.
	if not has_item(item_id):
		return false
	var item = ITEM_DB.get(item_id, {})
	var slot: String = item.get("slot", "")
	if slot == "":
		print("[Inventory] Item '" + item_id + "' has no equip slot.")
		return false
	# If something is already in that slot, unequip it first (return to bag)
	var current = PlayerData.equipped.get(slot, "")
	if current != "":
		var returned = ITEM_DB.get(current, {}).duplicate()
		returned["id"] = current
		returned["quantity"] = 1
		items.append(returned)
	# Remove from bag and set in equipped slot
	remove_item(item_id, 1)
	PlayerData.equip(item_id, slot)
	emit_signal("inventory_changed")
	print("[Inventory] Equipped '%s' to slot '%s'" % [item_id, slot])
	return true

func unequip_item(slot: String) -> bool:
	## Return equipped item from slot back to bag.
	var item_id = PlayerData.equipped.get(slot, "")
	if item_id == "":
		return false
	if items.size() >= MAX_SLOTS:
		print("[Inventory] Bag full, cannot unequip.")
		return false
	PlayerData.unequip(slot)
	add_item(item_id, 1)
	print("[Inventory] Unequipped '%s' from slot '%s'" % [item_id, slot])
	return true

func drop_item(item_id: String) -> bool:
	## Remove item from bag and spawn a physical 3D pickup on the ground.
	for i in range(items.size()):
		if items[i]["id"] == item_id:
			var removed = items[i]
			var quantity = removed.get("quantity", 1)
			
			# ─── Spawn the 3D Pickup ───
			var player = get_parent()
			if player is Node3D:
				var pickup_script = load("res://scripts/inventory/Pickup.gd")
				if pickup_script:
					var pickup = StaticBody3D.new()
					pickup.set_script(pickup_script)
					pickup.item_id = item_id
					pickup.quantity = quantity
					
					# Spawn in front of the player (camera-relative)
					var forward = Vector3.FORWARD
					var camera = player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D")
					if camera:
						forward = -camera.global_transform.basis.z
						forward.y = 0 # keep it level
						forward = forward.normalized()
					
					var spawn_pos = player.global_position + (forward * 1.5) + Vector3(0, 0.5, 0)
					
					# Set position BEFORE adding to child tree so _ready() logic is consistent
					pickup.position = spawn_pos
					get_tree().current_scene.add_child(pickup)
					print("[Inventory] Spawned 3D pickup for: ", item_id, " at ", spawn_pos)
				else:
					push_error("[Inventory] Failed to load Pickup.gd script for dropping!")
			
			# ─── Remove from Data ───
			items.remove_at(i)
			emit_signal("inventory_changed")
			emit_signal("item_removed", removed)
			print("[Inventory] Dropped item data: ", item_id)
			return true
	return false

# ─── Starting Inventory ───────────────────────────────────────────────────────
func grant_starting_items() -> void:
	var char_class = PlayerData.char_class
	var gear: Array = []
	var class_data = ClassData.get_all_classes()
	for c in class_data:
		if c["name"] == char_class:
			gear = c["starting_gear"]
			break
	# Map starting gear names to item IDs
	var gear_map = {
		"Iron Sword": "iron_sword", "Iron Shield": "iron_shield",
		"Leather Armor": "leather_armor", "Health Potion x2": "health_potion",
		"Apprentice Staff": "iron_sword", "Spellbook": "mana_crystal",
		"Cloth Robes": "leather_armor", "Mana Crystal x3": "mana_crystal",
		"Dual Daggers": "iron_sword", "Lockpick Set": "herbs",
		"Dark Leather Armor": "leather_armor", "Smoke Bomb x2": "herbs",
		"Hunting Bow": "iron_sword", "Quiver of Arrows": "herbs",
		"Ranger Cloak": "leather_armor", "Herbal Salve x2": "herbs",
		"Blessed Mace": "iron_axe", "Holy Symbol": "cracked_locket",
		"Chain Armor": "leather_armor", "Health Potion x3": "health_potion",
	}
	for gear_name in gear:
		var item_id = gear_map.get(gear_name, "")
		if item_id != "":
			add_item(item_id)
	add_item("campfire_kit", 1)

# ─── Serialization ────────────────────────────────────────────────────────────
func to_dict() -> Dictionary:
	return {"items": items}

func from_dict(data: Dictionary) -> void:
	items = data.get("items", [])
	emit_signal("inventory_changed")
