## PlayerData.gd
## Global singleton holding the active character's data.
extends Node

signal stats_changed
signal xp_gained(amount: int)
signal level_up(new_level: int)
signal gold_changed(new_amount: int)
signal face_customization_changed

# ─── Visual Constants ──────────────────────────────────────────────────────────
const SKIN_TONES = [
	Color(0.85, 0.76, 0.68), # Light
	Color(0.75, 0.58, 0.45), # Medium
	Color(0.45, 0.32, 0.22), # Dark
	Color(0.25, 0.15, 0.10)  # Deep
]

# ─── Identity ──────────────────────────────────────────────────────────────────
var character_name: String = ""
var race: String = "Human"
var char_class: String = "Warrior"
var gender: String = "male"
var appearance_config: Dictionary = {
	"muscle": 1.0,
	"build_scale": 1.0,
	"skin_color": Color(0.85, 0.76, 0.68)
}
var face_customization: Dictionary = {}

# ─── Core Stats ────────────────────────────────────────────────────────────────
var strength: int = 10
var dexterity: int = 10
var intelligence: int = 10
var constitution: int = 10
var wisdom: int = 10
var charisma: int = 10

# ─── Derived Stats ─────────────────────────────────────────────────────────────
var max_hp: int = 100
var current_hp: int = 100
var max_mana: int = 50
var current_mana: int = 50
var max_stamina: float = 100.0
var current_stamina: float = 100.0

# ─── Progression ───────────────────────────────────────────────────────────────
var level: int = 1
var experience: int = 0
var experience_to_next: int = 100
var gold: int = 50
var unspent_stat_points: int = 0

# ─── World State ───────────────────────────────────────────────────────────────
var last_position: Vector3 = Vector3.ZERO
var current_zone: String = "starter_village"
var save_slot: int = 0

# ─── Equipment ─────────────────────────────────────────────────────────────────
var equipped: Dictionary = {
	"main_hand": "",
	"off_hand": "",
	"body": "",
	"hands": "",
	"feet": "",
	"head": ""
}

# ─── Appearance Detail ──────────────────────────────────────────────────────────
var skin_tone: int = 0
var hair_color: int = 0
var eye_color: int = 0

# ─── Dungeon Progression ────────────────────────────────────────────────────────
var dungeon_floor: int = 1

func calculate_derived_stats() -> void:
	max_hp = 80 + (constitution * 5) + (level * 10)
	max_mana = 20 + (intelligence * 4) + (level * 5)
	max_stamina = 80.0 + (dexterity * 2.0)
	current_hp = max_hp
	current_mana = max_mana
	current_stamina = max_stamina
	emit_signal("stats_changed")

## Returns the character's base attack power derived from core stats.
## Strength drives physical damage; Intelligence provides a small bonus
## for mage-type builds. Scales gently with level.
func get_attack_power() -> int:
	var base: int = 5 + (strength * 2) + level
	var int_bonus: int = intelligence / 4   # mages get a small melee top-up
	return base + int_bonus

func get_defense() -> int:
	return 2 + (constitution / 2) + (level / 2)

func to_dict() -> Dictionary:
	# Serialize colors in appearance_config for JSON safety
	var serialized_app = appearance_config.duplicate()
	if serialized_app.has("skin_color") and serialized_app["skin_color"] is Color:
		serialized_app["skin_color"] = serialized_app["skin_color"].to_html()
	
	return {
		"character_name": character_name,
		"race": race,
		"char_class": char_class,
		"gender": gender,
		"appearance_config": serialized_app,
		"strength": strength,
		"dexterity": dexterity,
		"intelligence": intelligence,
		"constitution": constitution,
		"wisdom": wisdom,
		"charisma": charisma,
		"max_hp": max_hp,
		"current_hp": current_hp,
		"max_mana": max_mana,
		"current_mana": current_mana,
		"level": level,
		"experience": experience,
		"gold": gold,
		"unspent_stat_points": unspent_stat_points,
		"skin_tone": skin_tone,
		"hair_color": hair_color,
		"eye_color": eye_color,
		"save_slot": save_slot,
		"current_zone": current_zone,
		"dungeon_floor": dungeon_floor,
		"equipped": equipped,
		"last_position": {"x": last_position.x, "y": last_position.y, "z": last_position.z}
	}

func from_dict(data: Dictionary) -> void:
	character_name = data.get("character_name", "")
	race = data.get("race", "Human")
	char_class = data.get("char_class", "Warrior")
	gender = data.get("gender", "male")
	
	var raw_app = data.get("appearance_config")
	if raw_app is Dictionary:
		appearance_config = raw_app
		# Reconstruct colors from serialized format
		if appearance_config.has("skin_color") and appearance_config["skin_color"] is String:
			appearance_config["skin_color"] = Color.from_string(appearance_config["skin_color"], Color(0.85, 0.76, 0.68))
	
	# Handle backward compatibility or malformed JSON
	if appearance_config == null or appearance_config.is_empty():
		appearance_config = {
			"muscle": 1.0, "build_scale": 1.0,
			"skin_color": Color(0.85, 0.76, 0.68)
		}
	
	# Core Stats
	strength = int(data.get("strength", 10))
	dexterity = int(data.get("dexterity", 10))
	intelligence = int(data.get("intelligence", 10))
	constitution = int(data.get("constitution", 10))
	wisdom = int(data.get("wisdom", 10))
	charisma = int(data.get("charisma", 10))
	
	# Derived/Progress
	max_hp = int(data.get("max_hp", 100))
	current_hp = int(data.get("current_hp", 100))
	max_mana = int(data.get("max_mana", 50))
	current_mana = int(data.get("current_mana", 50))
	level = int(data.get("level", 1))
	experience = int(data.get("experience", 0))
	gold = int(data.get("gold", 50))
	unspent_stat_points = int(data.get("unspent_stat_points", 0))
	
	# Appearance
	skin_tone = int(data.get("skin_tone", 0))
	hair_color = int(data.get("hair_color", 0))
	eye_color = int(data.get("eye_color", 0))
	
	# Game State
	save_slot = int(data.get("save_slot", 0))
	current_zone = data.get("current_zone", "starter_village")
	dungeon_floor = int(data.get("dungeon_floor", 1))
	equipped = data.get("equipped", equipped)
	
	var pos_data = data.get("last_position", {"x": 0, "y": 0, "z": 0})
	last_position = Vector3(pos_data.x, pos_data.y, pos_data.z)
	
	emit_signal("stats_changed")

## Processes incoming damage and returns true if it results in death.
func take_damage(amount: int) -> bool:
	current_hp -= amount
	current_hp = clamp(current_hp, 0, max_hp)
	emit_signal("stats_changed")
	return current_hp <= 0

## Adds gold to the player's purse and notifies the UI.
func add_gold(amount: int) -> void:
	gold += amount
	emit_signal("gold_changed", gold)
	emit_signal("stats_changed")

## Processes experience gain and handles the level-up loop.
func gain_experience(amount: int) -> void:
	experience += amount
	emit_signal("xp_gained", amount)
	while experience >= experience_to_next:
		experience -= experience_to_next
		_level_up()
	emit_signal("stats_changed")

func _level_up() -> void:
	level += 1
	unspent_stat_points += 5
	# Gentle exponential curve for next level requirements
	experience_to_next = int(experience_to_next * 1.4)
	calculate_derived_stats()
	emit_signal("level_up", level)

## Consumes mana and returns true if successful.
func use_mana(amount: int) -> bool:
	if current_mana >= amount:
		current_mana -= amount
		emit_signal("stats_changed")
		return true
	return false

## Restores health to the player.
func heal(amount: int) -> void:
	current_hp = clamp(current_hp + amount, 0, max_hp)
	emit_signal("stats_changed")
