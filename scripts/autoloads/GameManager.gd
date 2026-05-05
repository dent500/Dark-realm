## GameManager.gd
## Global game state manager — tracks scene flow, game phase, time of day.
extends Node

# ─── Signals ───────────────────────────────────────────────────────────────────
signal scene_changed(scene_name: String)
signal game_paused(is_paused: bool)
signal day_night_changed(is_day: bool)

# ─── Enums ─────────────────────────────────────────────────────────────────────
enum GamePhase {
	MAIN_MENU,
	CHARACTER_CREATION,
	PLAYING,
	PAUSED,
	CUTSCENE,
	GAME_OVER
}

# ─── State ─────────────────────────────────────────────────────────────────────
var current_phase: GamePhase = GamePhase.MAIN_MENU
var is_paused: bool = false
var is_day: bool = true
var session_time: float = 0.0  # seconds since session start

# Day/night cycle
var day_duration: float = 600.0  # 10 real minutes per full day
var day_cycle_time: float = 0.0

# ─── Scene Management ──────────────────────────────────────────────────────────
func change_scene(path: String) -> void:
	var scene_name = path.get_file().get_basename()
	SaveSystem.auto_save()
	get_tree().change_scene_to_file(path)
	emit_signal("scene_changed", scene_name)
	print("[GameManager] Scene changed to: ", scene_name)

func go_to_main_menu() -> void:
	current_phase = GamePhase.MAIN_MENU
	change_scene("res://scenes/main_menu.tscn")

func start_new_game() -> void:
	current_phase = GamePhase.CHARACTER_CREATION
	change_scene("res://scenes/character_creation.tscn")

func enter_world() -> void:
	current_phase = GamePhase.PLAYING
	change_scene("res://scenes/world.tscn")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ─── Pause ────────────────────────────────────────────────────────────────────
func toggle_pause() -> void:
	is_paused = !is_paused
	get_tree().paused = is_paused
	if is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		if current_phase == GamePhase.PLAYING:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	emit_signal("game_paused", is_paused)

# ─── Time ──────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if current_phase != GamePhase.PLAYING:
		return
	session_time += delta
	_update_day_night(delta)

func _update_day_night(delta: float) -> void:
	# In multiplayer, only the server advances time
	if NetworkManager.is_multiplayer_active():
		if multiplayer.is_server():
			day_cycle_time += delta
			if day_cycle_time > day_duration:
				day_cycle_time = 0.0
			# Periodically sync time to clients (every 1 second)
			if int(session_time) % 1 == 0:
				rpc("sync_time", day_cycle_time)
		else:
			# Clients don't advance time locally, they wait for sync
			pass
	else:
		# Singleplayer advances time normally
		day_cycle_time += delta
		if day_cycle_time > day_duration:
			day_cycle_time = 0.0
			
	var was_day = is_day
	is_day = day_cycle_time < (day_duration * 0.5)
	if is_day != was_day:
		emit_signal("day_night_changed", is_day)

@rpc("any_peer", "unreliable")
func sync_time(time: float) -> void:
	day_cycle_time = time

func get_time_of_day_normalized() -> float:
	## Returns 0.0 = midnight, 0.5 = noon, 1.0 = midnight again
	return day_cycle_time / day_duration

func get_time_string() -> String:
	var normalized = get_time_of_day_normalized()
	var hour = int(normalized * 24.0)
	var minute = int(fmod(normalized * 24.0 * 60.0, 60.0))
	return "%02d:%02d" % [hour, minute]

# ─── Input ─────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and current_phase == GamePhase.PLAYING:
		toggle_pause()
