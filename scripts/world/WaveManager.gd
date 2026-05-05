extends Node

var current_wave: int = 0
var wave_active: bool = false
@onready var enemy_scene: PackedScene = preload("res://scenes/skeleton_enemy.tscn")

func _ready() -> void:
	wave_active = true # Start true to let player clear initialization wave

func _process(_delta: float) -> void:
	if wave_active:
		var enemies = get_tree().get_nodes_in_group("enemy")
		var living_enemies = 0
		for e in enemies:
			if "state" in e and e.state != 5: # 5 = DEAD
				living_enemies += 1
		
		# Allow clearing of wave
		if living_enemies == 0:
			wave_active = false
			print("[WaveManager] Wave ", current_wave, " completed!")
			var hud = get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("update_wave_ui"):
				hud.update_wave_ui(current_wave, 0, false)
				
			if current_wave > 0:
				AIDungeonMaster.narrate_custom("The horde falls silent. You have survived wave " + str(current_wave) + ". Brace yourself.")
			else:
				AIDungeonMaster.narrate_custom("The initial guards have fallen. The true endless hordes awaken...")
				
			# Wait briefly, then launch next wave
			await get_tree().create_timer(4.0).timeout
			start_next_wave()
		else:
			var hud = get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("update_wave_ui"):
				hud.update_wave_ui(current_wave if current_wave > 0 else 1, living_enemies, true)

func start_next_wave() -> void:
	current_wave += 1
	wave_active = true
	var num_enemies = 2 + (current_wave * 2)
	print("[WaveManager] Starting Wave ", current_wave, " with ", num_enemies, " enemies.")
	AIDungeonMaster.narrate_custom("Wave " + str(current_wave) + " has begun. " + str(num_enemies) + " skeletons rise from the dust! Their power has drastically increased.")
	
	var spawn_points = []
	var spawns_parent = get_parent().get_node_or_null("EnemySpawns")
	if spawns_parent:
		for c in spawns_parent.get_children():
			if c is Node3D: spawn_points.append(c.global_position)
	
	for i in range(num_enemies):
		var en = enemy_scene.instantiate()
		get_parent().add_child(en)
		
		# Scatter logic
		if spawn_points.size() > 0:
			en.global_position = spawn_points[randi() % spawn_points.size()] + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		else:
			en.global_position = Vector3(randf_range(-20, 20), 10, randf_range(-20, 20))
			
		# Aggressively scale stats based on wave
		en.max_hp = 50 + (current_wave * 25)
		en.attack_damage = 10 + (current_wave * 8)
		en.move_speed = min(8.0, 3.8 + (current_wave * 0.3))
		en.current_hp = en.max_hp # Fully heal spawn
