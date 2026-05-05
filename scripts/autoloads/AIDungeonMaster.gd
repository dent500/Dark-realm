## AIDungeonMaster.gd
## Connects to an LLM API (OpenAI or Gemini) to generate narrative narration,
## event descriptions, and dynamic quest hooks based on player context.
extends Node

# ─── Signals ───────────────────────────────────────────────────────────────────
signal narration_received(text: String)
signal narration_failed(error: String)

# ─── Config ────────────────────────────────────────────────────────────────────
## Set your API key here, or load it from a config file (recommended)
var api_key: String = ""
var api_provider: String = "openai"  # "openai" or "gemini"
var model: String = "gpt-4o-mini"

# OpenAI endpoint
const OPENAI_URL = "https://api.openai.com/v1/chat/completions"
# Gemini endpoint
const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"

# ─── Internal ──────────────────────────────────────────────────────────────────
var _http: HTTPRequest
var _is_requesting: bool = false
var _narration_queue: Array[String] = []
var _story_context: Array[Dictionary] = []
const MAX_CONTEXT_MESSAGES = 12

# ─── System Prompt ─────────────────────────────────────────────────────────────
const SYSTEM_PROMPT = """You are the Dungeon Master of Dark Realm, a dark fantasy world of ancient curses, fallen kingdoms, corrupted magic, and forgotten gods. You narrate events vividly and dramatically in second-person present tense. Keep responses to 2-4 sentences unless describing a major event. Describe sensory details: sights, sounds, smells. Respond ONLY with narration — no dialogue choices, no stat blocks. The tone is dark, gritty, and atmospheric."""

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_load_api_key()

func _load_api_key() -> void:
	## Load API key from user://api_config.json if it exists
	var path = "user://api_config.json"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data = json.data
			api_key = data.get("api_key", "")
			api_provider = data.get("provider", "openai")
			model = data.get("model", "gpt-4o-mini")
		file.close()

func save_api_config(key: String, provider: String = "openai", mdl: String = "gpt-4o-mini") -> void:
	api_key = key
	api_provider = provider
	model = mdl
	var data = {"api_key": key, "provider": provider, "model": mdl}
	var file = FileAccess.open("user://api_config.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

# ─── Narration Requests ────────────────────────────────────────────────────────
func narrate_arrival(zone: String) -> void:
	var prompt = _build_context_prompt(
		"The player has just arrived at: " + zone + ". Describe the atmosphere and first impressions of this place."
	)
	_request_narration(prompt)

func narrate_combat_start(enemy_name: String) -> void:
	var prompt = _build_context_prompt(
		"A " + enemy_name + " attacks the player. Describe the start of this combat encounter dramatically."
	)
	_request_narration(prompt)

func narrate_enemy_death(enemy_name: String) -> void:
	var prompt = _build_context_prompt(
		"The player has just defeated a " + enemy_name + ". Briefly describe the killing blow."
	)
	_request_narration(prompt)

func narrate_quest_start(quest_title: String, quest_desc: String) -> void:
	var prompt = _build_context_prompt(
		"The player has accepted the quest '" + quest_title + "': " + quest_desc + ". Narrate the beginning of this quest."
	)
	_request_narration(prompt)

func narrate_discovery(discovery: String) -> void:
	var prompt = _build_context_prompt(
		"The player discovers: " + discovery + ". Describe this discovery with intrigue and dark atmosphere."
	)
	_request_narration(prompt)

func narrate_level_up(new_level: int) -> void:
	var race = PlayerData.race
	var char_class = PlayerData.char_class
	var prompt = _build_context_prompt(
		"The " + race + " " + char_class + " has grown stronger and reached level " + str(new_level) + ". Narrate this moment of growth in the dark fantasy world."
	)
	_request_narration(prompt)

func narrate_custom(event_description: String) -> void:
	var prompt = _build_context_prompt(event_description)
	_request_narration(prompt)

# ─── Internal Request Handling ─────────────────────────────────────────────────
func _build_context_prompt(user_message: String) -> String:
	## Inject player character context into the request
	var context = "[Character: %s the %s %s, Level %d, currently in %s] %s" % [
		PlayerData.character_name,
		PlayerData.race,
		PlayerData.char_class,
		PlayerData.level,
		PlayerData.current_zone,
		user_message
	]
	return context

func _request_narration(prompt: String) -> void:
	if api_key.is_empty():
		emit_signal("narration_received", "[AI DM offline — set your API key in Settings]")
		return
	if _is_requesting:
		_narration_queue.append(prompt)
		return
	_is_requesting = true
	_story_context.append({"role": "user", "content": prompt})
	if _story_context.size() > MAX_CONTEXT_MESSAGES:
		_story_context.pop_front()
	_send_request()

func _send_request() -> void:
	var headers = ["Content-Type: application/json"]
	var body: Dictionary
	if api_provider == "openai":
		headers.append("Authorization: Bearer " + api_key)
		var messages = [{"role": "system", "content": SYSTEM_PROMPT}]
		messages.append_array(_story_context)
		body = {
			"model": model,
			"messages": messages,
			"max_tokens": 200,
			"temperature": 0.85
		}
		_http.request(OPENAI_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	elif api_provider == "gemini":
		var url = GEMINI_URL + "?key=" + api_key
		var contents = []
		for msg in _story_context:
			contents.append({"role": msg.role, "parts": [{"text": msg.content}]})
		body = {
			"system_instruction": {"parts": [{"text": SYSTEM_PROMPT}]},
			"contents": contents,
			"generationConfig": {"maxOutputTokens": 200, "temperature": 0.85}
		}
		_http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_requesting = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var err = "HTTP error: " + str(response_code)
		push_error("[AIDungeonMaster] " + err)
		emit_signal("narration_failed", err)
	else:
		var text = _parse_response(body)
		if text != "":
			_story_context.append({"role": "assistant", "content": text})
			emit_signal("narration_received", text)
	# Process queue
	if _narration_queue.size() > 0:
		var next = _narration_queue.pop_front()
		_request_narration(next)

func _parse_response(body: PackedByteArray) -> String:
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return ""
	var data = json.data
	if api_provider == "openai":
		var choices = data.get("choices", [])
		if choices.size() > 0:
			return choices[0].get("message", {}).get("content", "")
	elif api_provider == "gemini":
		var candidates = data.get("candidates", [])
		if candidates.size() > 0:
			var parts = candidates[0].get("content", {}).get("parts", [])
			if parts.size() > 0:
				return parts[0].get("text", "")
	return ""
