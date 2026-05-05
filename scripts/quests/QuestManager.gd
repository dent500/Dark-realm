## QuestManager.gd
## Autoload: tracks active, completed, and failed quests. Interfaces with AI DM.
extends Node

# ─── Signals ───────────────────────────────────────────────────────────────────
signal quest_started(quest_id: String)
signal quest_stage_advanced(quest_id: String, stage: int)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String)

# ─── Quest Database ────────────────────────────────────────────────────────────
var quest_db: Dictionary = {}   # quest_id -> quest definition
var active_quests: Dictionary = {}    # quest_id -> {stage, started_at}
var completed_quests: Array[String] = []
var failed_quests: Array[String] = []

func _ready() -> void:
	_register_starter_quests()

# ─── Quest Registration ────────────────────────────────────────────────────────
func _register_starter_quests() -> void:
	register_quest({
		"id": "awakening",
		"title": "The Awakening",
		"description": "You awaken with no memory of how you came to be in this cursed land. Find someone who can explain what happened.",
		"stages": [
			{"objective": "Find an NPC in the Starter Village", "hint": "Head towards the ruined tavern."},
			{"objective": "Ask the elder about your origins",    "hint": "The old woman knows more than she lets on."},
			{"objective": "Retrieve the Cracked Locket",        "hint": "It was buried near the old well."}
		],
		"rewards": {"xp": 150, "gold": 30, "item": "Cracked Locket"},
		"zone": "starter_village",
		"auto_start": true
	})
	register_quest({
		"id": "ruined_keep",
		"title": "The Ruined Keep",
		"description": "Goblins have overrun the old watchtower east of the village. The frightened villagers need them cleared out.",
		"stages": [
			{"objective": "Travel to the Ruined Keep",        "hint": "Head east along the haunted road."},
			{"objective": "Kill 5 Goblins",                   "hint": "They nest in the lower levels.", "kill_count": {"enemy": "Goblin", "required": 5, "current": 0}},
			{"objective": "Defeat the Goblin Warlord",        "hint": "He hides on the top floor with stolen relics."},
			{"objective": "Return to the village elder",      "hint": "Bring proof of your victory."}
		],
		"rewards": {"xp": 300, "gold": 80, "item": "Iron Ax"},
		"zone": "starter_village"
	})
	register_quest({
		"id": "missing_merchant",
		"title": "The Missing Merchant",
		"description": "A travelling merchant named Aldric left for the crossroads three days ago and never returned. His apprentice is desperate for news.",
		"stages": [
			{"objective": "Speak to Aldric's apprentice, Petra",  "hint": "She waits near the south gate."},
			{"objective": "Investigate the crossroads",           "hint": "Look for signs of a struggle."},
			{"objective": "Follow the trail into Ashwood Forest", "hint": "Something dragged him from the road."},
			{"objective": "Find Aldric (dead or alive)",          "hint": "The forest does not give up its secrets easily."}
		],
		"rewards": {"xp": 250, "gold": 60, "item": "Merchant Ledger"},
		"zone": "starter_village"
	})

func register_quest(quest: Dictionary) -> void:
	quest_db[quest["id"]] = quest
	if quest.get("auto_start", false):
		start_quest(quest["id"])

# ─── Quest Control ─────────────────────────────────────────────────────────────
func start_quest(quest_id: String) -> bool:
	if not quest_db.has(quest_id):
		push_error("[QuestManager] Quest not found: " + quest_id)
		return false
	if active_quests.has(quest_id) or quest_id in completed_quests:
		return false
	active_quests[quest_id] = {"stage": 0, "started_at": Time.get_ticks_msec()}
	var quest = quest_db[quest_id]
	emit_signal("quest_started", quest_id)
	AIDungeonMaster.narrate_quest_start(quest["title"], quest["description"])
	print("[QuestManager] Started quest: ", quest["title"])
	return true

func advance_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return
	var quest = quest_db[quest_id]
	var current_stage = active_quests[quest_id]["stage"]
	current_stage += 1
	if current_stage >= quest["stages"].size():
		_complete_quest(quest_id)
	else:
		active_quests[quest_id]["stage"] = current_stage
		emit_signal("quest_stage_advanced", quest_id, current_stage)
		var stage = quest["stages"][current_stage]
		print("[QuestManager] Quest advanced: ", quest["title"], " -> Stage ", current_stage, ": ", stage["objective"])

func _complete_quest(quest_id: String) -> void:
	var quest = quest_db[quest_id]
	active_quests.erase(quest_id)
	completed_quests.append(quest_id)
	# Give rewards
	var rewards = quest.get("rewards", {})
	if rewards.has("xp"):
		PlayerData.gain_experience(rewards["xp"])
	if rewards.has("gold"):
		PlayerData.add_gold(rewards["gold"])
	emit_signal("quest_completed", quest_id)
	AIDungeonMaster.narrate_custom("You have completed the quest: " + quest["title"] + ". " + str(rewards.get("xp", 0)) + " experience and " + str(rewards.get("gold", 0)) + " gold gained.")
	print("[QuestManager] Completed quest: ", quest["title"])

func fail_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return
	active_quests.erase(quest_id)
	failed_quests.append(quest_id)
	emit_signal("quest_failed", quest_id)

# ─── Kill Tracking ────────────────────────────────────────────────────────────
func on_enemy_killed(enemy_name: String) -> void:
	## Call this from EnemyBase._die() to track kill objectives
	for quest_id in active_quests.keys():
		var quest = quest_db[quest_id]
		var stage_index = active_quests[quest_id]["stage"]
		var stage = quest["stages"][stage_index]
		if stage.has("kill_count"):
			if stage["kill_count"]["enemy"] == enemy_name:
				stage["kill_count"]["current"] += 1
				print("[QuestManager] Kill count: ", stage["kill_count"]["current"], "/", stage["kill_count"]["required"])
				if stage["kill_count"]["current"] >= stage["kill_count"]["required"]:
					advance_quest(quest_id)

# ─── Queries ──────────────────────────────────────────────────────────────────
func get_active_quest_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest_id in active_quests.keys():
		var q = quest_db[quest_id].duplicate()
		q["current_stage"] = active_quests[quest_id]["stage"]
		q["current_objective"] = q["stages"][q["current_stage"]]["objective"]
		result.append(q)
	return result

func get_quest_stage_objective(quest_id: String) -> String:
	if not active_quests.has(quest_id):
		return ""
	var quest = quest_db[quest_id]
	var stage_index = active_quests[quest_id]["stage"]
	return quest["stages"][stage_index]["objective"]

# ─── Save / Load ──────────────────────────────────────────────────────────────
func get_save_data() -> Dictionary:
	return {
		"active_quests": active_quests,
		"completed_quests": completed_quests,
		"failed_quests": failed_quests
	}

func load_save_data(data: Dictionary) -> void:
	active_quests = data.get("active_quests", {})
	completed_quests.assign(data.get("completed_quests", []))
	failed_quests.assign(data.get("failed_quests", []))
