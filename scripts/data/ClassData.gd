## ClassData.gd
## Defines each playable class: starting stats, starting gear, and core abilities.
class_name ClassData
extends Resource

static func get_all_classes() -> Array[Dictionary]:
	return [
		{
			"name": "Warrior",
			"description": "A seasoned fighter who excels with any weapon. High defense, relentless offense.",
			"lore": "You have survived wars that shattered kingdoms. Your blade has drunk deeper than you care to remember.",
			"primary_stat": "Strength",
			"base_stats": {"str": 14, "dex": 10, "int": 8, "con": 13, "wis": 9, "cha": 9},
			"starting_gear": ["Iron Sword", "Iron Shield", "Leather Armor", "Health Potion x2"],
			"abilities": [
				{"name": "Power Strike", "description": "A heavy blow dealing 150% weapon damage.", "mana_cost": 0, "cooldown": 5},
				{"name": "War Cry",      "description": "Boosts your attack by 20% for 10 seconds.",  "mana_cost": 15, "cooldown": 30},
				{"name": "Shield Bash",  "description": "Staggers an enemy, dealing minor damage.",   "mana_cost": 0, "cooldown": 8}
			],
			"hand_mod": 1.35,
			"icon_color": Color(0.8, 0.2, 0.2),
			"starter_clothing": {
				"type": "shirt_pants",
				"shirt_color": Color(0.52, 0.40, 0.26),
				"pants_color": Color(0.22, 0.16, 0.10),
			},
			"animations": {
				"player/idle": "res://assets/animations/player/class_specific/shield_idle.fbx",
				"player/walk": "res://assets/animations/player/class_specific/shield_walk.fbx",
				"player/run":  "res://assets/animations/player/class_specific/shield_run.fbx",
				"player/block_idle": "res://assets/animations/player/combat/shield_block.fbx",
				"player/strike_1": "res://assets/animations/player/combat/melee_slash_horizontal.fbx",
				"player/strike_2": "res://assets/animations/player/combat/melee_slash_downward.fbx",
				"player/strike_3": "res://assets/animations/player/combat/shield_attack_(2).fbx",
				"player/jump":     "res://assets/animations/player/mobility/shield_jump.fbx"
			},

			"starter_weapons": {
				"main_hand": {"weapon_type": "sword", "file": "res://assets/equipment/models/low_poly_weapons_pack_rigged_blender.glb", "node": "Baked one handed sword", "scale": 1.5, "position": Vector3(0, 0, 0.05), "rotation": Vector3(-90, -90, 0)},
				"off_hand":  {"weapon_type": "shield", "file": "res://assets/equipment/models/low_poly_weapons_pack_rigged_blender.glb", "node": "Baked shield 1", "scale": 0.8, "position": Vector3(-0.1, 0.08, 0.05), "rotation": Vector3(43, 26, 114)},
			}
		},
		{
			"name": "Mage",
			"description": "A wielder of forbidden arcane arts. Devastating power at the cost of frailty.",
			"lore": "Magic always takes something. You have paid that price, and still you reach for more.",
			"primary_stat": "Intelligence",
			"base_stats": {"str": 7, "dex": 9, "int": 15, "con": 8, "wis": 12, "cha": 11},
			"starting_gear": ["Apprentice Staff", "Spellbook", "Cloth Robes", "Mana Crystal x3"],
			"abilities": [
				{"name": "Fireball",         "description": "Launches a ball of fire dealing area damage.", "mana_cost": 25, "cooldown": 3},
				{"name": "Arcane Missile",   "description": "Rapid-fire arcane bolts (3 projectiles).",    "mana_cost": 10, "cooldown": 1},
				{"name": "Blink",            "description": "Teleport 8m forward instantly.",              "mana_cost": 30, "cooldown": 12}
			],
			"hand_mod": 1.05,
			"icon_color": Color(0.3, 0.3, 0.9),
			"starter_clothing": {
				"type": "shirt_pants",
				"shirt_color": Color(0.14, 0.12, 0.42),
				"pants_color": Color(0.10, 0.08, 0.25),
				"has_leg_skirt": true,
			},
			"animations": {
				"player/strike_1": "res://assets/animations/player/combat/melee_slash_horizontal.fbx",
				"player/strike_2": "res://assets/animations/player/combat/melee_slash_downward.fbx",
				"player/strike_3": "res://assets/animations/player/combat/melee_slash_horizontal.fbx",
				"player/jump":     "res://assets/animations/player/mobility/jump.fbx"
			},
			"starter_weapons": {
				"main_hand": {"weapon_type": "staff", "file": "res://assets/equipment/models/low_poly_weapons_pack_rigged_blender.glb", "node": "Baked wand", "scale": 1.5, "position": Vector3(0, 0, 0.05), "rotation": Vector3(-90, -90, 0)},
				"off_hand":  {"weapon_type": "book"},
			}
		},
		{
			"name": "Rogue",
			"description": "A shadow dancer who strikes fast, hard, and from the dark.",
			"lore": "Every city has its secrets. You have learned them all — and weaponized them.",
			"primary_stat": "Dexterity",
			"base_stats": {"str": 10, "dex": 15, "int": 10, "con": 9, "wis": 9, "cha": 11},
			"starting_gear": ["Dual Daggers", "Lockpick Set", "Dark Leather Armor", "Smoke Bomb x2"],
			"abilities": [
				{"name": "Backstab",     "description": "Triple damage from stealth or behind.",    "mana_cost": 0, "cooldown": 6},
				{"name": "Evasion",      "description": "50% dodge chance for 5 seconds.",          "mana_cost": 20, "cooldown": 20},
				{"name": "Shadow Step",  "description": "Teleport behind target enemy.",            "mana_cost": 25, "cooldown": 15}
			],
			"hand_mod": 1.15,
			"icon_color": Color(0.4, 0.1, 0.6),
			"starter_clothing": {
				"type": "shirt_pants",
				"shirt_color": Color(0.18, 0.18, 0.20),
				"pants_color": Color(0.12, 0.10, 0.10),
			},
			"animations": {
				"player/idle": "res://assets/animations/player/unarmed/unarmed_idle_looking_ver._1.fbx",
				"player/run":  "res://assets/animations/player/unarmed/unarmed_run_forward.fbx",
				"player/strike_1": "res://assets/animations/player/combat/melee_slash_360_high.fbx",
				"player/strike_2": "res://assets/animations/player/combat/melee_slash_backhand.fbx",
				"player/strike_3": "res://assets/animations/player/combat/melee_combo_ver._3.fbx",
				"player/jump":     "res://assets/animations/player/unarmed/unarmed_jump.fbx"
			},
			"starter_weapons": {
				"main_hand": {"weapon_type": "dagger", "file": "res://assets/equipment/models/low_poly_weapons_pack_rigged_blender.glb", "node": "Baked dagger", "scale": 1.2, "position": Vector3(0, 0, 0.05), "rotation": Vector3(-90, -90, 0)},
				"off_hand":  {"weapon_type": "dagger", "file": "res://assets/equipment/models/low_poly_weapons_pack_rigged_blender.glb", "node": "Baked dagger", "scale": 1.2, "position": Vector3(0, 0.05, 0.0), "rotation": Vector3(188, 314, 177)},
			}
		},
		{
			"name": "Ranger",
			"description": "A wilderness survivor who hunts from range and communes with beasts.",
			"lore": "The wilds called and you answered. Civilization's wars are not yours — unless you choose them.",
			"primary_stat": "Dexterity",
			"base_stats": {"str": 10, "dex": 14, "int": 10, "con": 10, "wis": 13, "cha": 9},
			"starting_gear": ["Hunting Bow", "Quiver of Arrows", "Ranger Cloak", "Herbal Salve x2"],
			"abilities": [
				{"name": "Marked Shot",   "description": "Mark a target, dealing 200% damage on next hit.", "mana_cost": 15, "cooldown": 8},
				{"name": "Barrage",       "description": "Fire 5 arrows rapidly in a cone.",               "mana_cost": 20, "cooldown": 12},
				{"name": "Beast Sense",   "description": "Highlight all enemies through walls for 15s.",   "mana_cost": 10, "cooldown": 25}
			],
			"hand_mod": 1.02,
			"icon_color": Color(0.2, 0.6, 0.2),
			"starter_clothing": {
				"type": "shirt_pants",
				"shirt_color": Color(0.28, 0.40, 0.20),
				"pants_color": Color(0.30, 0.22, 0.14),
			},
			"animations": {
				"player/idle": "res://assets/animations/player/unarmed/unarmed_idle_looking_ver._1.fbx",
				"player/run":  "res://assets/animations/player/unarmed/unarmed_run_forward.fbx",
				"player/jump": "res://assets/animations/player/unarmed/unarmed_jump.fbx"
			},
			"starter_weapons": {
				"main_hand": {"weapon_type": "bow", "file": "res://assets/equipment/models/low_poly_weapons_pack_rigged_blender.glb", "node": "Baked bow 1", "scale": 1.5, "position": Vector3(0.0, 0.05, 0.0), "rotation": Vector3(-45, 90, 0)},
				"off_hand":  {},
			}
		},
		{
			"name": "Cleric",
			"description": "A divine warrior who balances holy wrath with healing grace.",
			"lore": "The gods are mostly silent. You carry their last commands — and the doubt that comes with them.",
			"primary_stat": "Wisdom",
			"base_stats": {"str": 11, "dex": 9, "int": 11, "con": 11, "wis": 14, "cha": 12},
			"starting_gear": ["Blessed Mace", "Holy Symbol", "Chain Armor", "Health Potion x3"],
			"abilities": [
				{"name": "Smite",        "description": "Channel divine power into a crushing blow.",     "mana_cost": 20, "cooldown": 6},
				{"name": "Healing Word", "description": "Restore 40 HP to self or nearby ally.",         "mana_cost": 25, "cooldown": 10},
				{"name": "Sacred Ward",  "description": "+30% damage reduction aura for 8 seconds.",     "mana_cost": 30, "cooldown": 30}
			],
			"hand_mod": 1.25,
			"icon_color": Color(0.9, 0.85, 0.3),
			"starter_clothing": {
				"type": "shirt_pants",
				"shirt_color": Color(0.88, 0.84, 0.72),
				"pants_color": Color(0.68, 0.64, 0.52),
				"has_leg_skirt": true,
			},
			"animations": {
				"player/idle": "res://assets/animations/player/class_specific/shield_idle.fbx",
				"player/walk": "res://assets/animations/player/class_specific/shield_walk.fbx",
				"player/run":  "res://assets/animations/player/class_specific/shield_run.fbx",
				"player/block_idle": "res://assets/animations/player/combat/shield_block.fbx",
				"player/strike_1": "res://assets/animations/player/combat/melee_slash_horizontal.fbx",
				"player/strike_2": "res://assets/animations/player/combat/melee_slash_downward.fbx",
				"player/strike_3": "res://assets/animations/player/combat/shield_attack_(2).fbx",
				"player/jump":     "res://assets/animations/player/mobility/shield_jump.fbx"
			},
			"starter_weapons": {
				"main_hand": {"weapon_type": "mace", "file": "res://assets/equipment/models/low_poly_weapons_pack_rigged_blender.glb", "node": "Baked one handed mace", "scale": 1.5, "position": Vector3(0, 0, 0.05), "rotation": Vector3(-90, -90, 0)},
				"off_hand":  {"weapon_type": "shield", "file": "res://assets/equipment/models/low_poly_weapons_pack_rigged_blender.glb", "node": "Baked shield 1", "scale": 0.8, "position": Vector3(-0.1, 0.08, 0.05), "rotation": Vector3(43, 26, 114)},
			}
		}
	]
