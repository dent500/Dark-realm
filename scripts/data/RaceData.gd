## RaceData.gd
## Resource defining a playable race's properties, stat bonuses, and lore.
class_name RaceData
extends Resource

@export var race_name: String = ""
@export var description: String = ""
@export var lore: String = ""

# Stat bonuses (added on top of base 10)
@export var str_bonus: int = 0
@export var dex_bonus: int = 0
@export var int_bonus: int = 0
@export var con_bonus: int = 0
@export var wis_bonus: int = 0
@export var cha_bonus: int = 0

# Passive ability
@export var passive_ability: String = ""
@export var passive_description: String = ""

# Visual
@export var portrait_color: Color = Color.WHITE  # tint for placeholder portrait

static func get_all_races() -> Array[Dictionary]:
	return [
		{
			"name": "Human",
			"description": "Adaptable and ambitious, humans spread across the realm driven by ambition and survival.",
			"lore": "Born into a dying kingdom, humans carry the weight of fallen empires in their blood.",
			"bonuses": {"str": 1, "dex": 1, "int": 1, "con": 1, "wis": 1, "cha": 1},
			"passive_ability": "Tenacity",
			"passive_description": "Once per rest, survive a lethal blow with 1 HP.",
			"portrait_color": Color(0.9, 0.75, 0.6),
			"body_profile": {
				"build_scale": 1.0, "muscle": 1.0,
				"head_scale": 1.0, "torso_scale": 1.0, "shoulder_scale": 1.0, "leg_scale": 1.0,
				"hand_scale": 1.1,
				"special": ""
			}
		},
		{
			"name": "Elf",
			"description": "Ancient and enigmatic, elves carry centuries of grief and forbidden knowledge.",
			"lore": "Their forest homes burn. Their gods are silent. Elves walk the world seeking what was lost.",
			"bonuses": {"str": 0, "dex": 2, "int": 2, "con": -1, "wis": 1, "cha": 2},
			"passive_ability": "Shadowstep",
			"passive_description": "Move silently. Enemies have reduced detection range.",
			"portrait_color": Color(0.7, 0.85, 0.65),
			"body_profile": {
				"build_scale": 1.1, "muscle": 0.8,
				"head_scale": 0.9, "torso_scale": 0.85, "shoulder_scale": 0.85, "leg_scale": 1.1,
				"hand_scale": 0.95,
				"special": "elf_ears"
			}
		},
		{
			"name": "Dwarf",
			"description": "Forged underground, dwarves are iron-willed survivors scarred by the things below.",
			"lore": "Their deep mines carved too far. Now they seal their halls and remember what came back up.",
			"bonuses": {"str": 2, "dex": -1, "int": 0, "con": 3, "wis": 2, "cha": 0},
			"passive_ability": "Stone Skin",
			"passive_description": "+2 armor from all sources. Immune to knockback.",
			"portrait_color": Color(0.7, 0.55, 0.4),
			"body_profile": {
				# Shorter overall but legs especially squat; wide barrel chest
				"build_scale": 0.85, "muscle": 1.25,
				"head_scale": 1.10, "torso_scale": 1.15, "shoulder_scale": 1.20, "leg_scale": 0.80,
				"forearm_scale": 0.8,
				"hand_scale": 1.3,
				"special": "beard"
			}
		},

		{
			"name": "Orc",
			"description": "Feared and misunderstood, Orcs carry a warrior's spirit born from blood and survival.",
			"lore": "Driven from ancestral lands, Orcs now roam as mercenaries, raiders, or reluctant heroes.",
			"bonuses": {"str": 3, "dex": 1, "int": -1, "con": 2, "wis": -1, "cha": 0},
			"passive_ability": "Blood Rage",
			"passive_description": "+25% damage when below 30% HP.",
			"portrait_color": Color(0.4, 0.65, 0.3),
			"body_profile": {
				# Tallest race, thick but not spherical — values kept moderate so
				# the sculpt bulge doesn't compound into balloon proportions
				"build_scale": 1.12, "muscle": 1.25,
				"head_scale": 1.10, "torso_scale": 1.15, "shoulder_scale": 1.20, "leg_scale": 1.08,
				"forearm_scale": 0.8,
				"hand_scale": 1.4,
				"special": "brow_ridge"
			}
		},

		{
			"name": "Tiefling",
			"description": "Born with infernal blood, Tieflings are cursed with power and hunted by the faithful.",
			"lore": "A pact made generations ago left its mark. You carry hellfire in your veins — and a price on your head.",
			"bonuses": {"str": 0, "dex": 1, "int": 2, "con": 0, "wis": 0, "cha": 3},
			"passive_ability": "Hellfire Aura",
			"passive_description": "Spells deal +15% fire damage. Fire resistance 50%.",
			"portrait_color": Color(0.7, 0.3, 0.3),
			"body_profile": {
				"build_scale": 1.0, "muscle": 0.95,
				"head_scale": 1.0, "torso_scale": 1.0, "shoulder_scale": 1.0, "leg_scale": 1.0,
				"hand_scale": 1.05,
				"special": "horns"
			}
		}
	]

