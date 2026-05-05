## CombatSystem.gd
## Attached to the Player node. Manages melee, ranged, and magic attacks.
extends Node

# ─── Signals ───────────────────────────────────────────────────────────────────
signal attack_hit(target: Node, damage: int)
signal spell_cast(spell_name: String)
signal combat_started
signal combat_ended

# ─── Config ────────────────────────────────────────────────────────────────────
@export var melee_range: float = 4.0
@export var melee_arc_degrees: float = 120.0
@export var projectile_scene: PackedScene  # assign in editor
@export var spell_effects: Dictionary = {}  # spell_name -> PackedScene

# ─── Cooldowns ────────────────────────────────────────────────────────────────
var attack_cooldown: float = 0.0
var spell_cooldowns: Dictionary = {}
var active_spell_index: int = 0

# ─── State ────────────────────────────────────────────────────────────────────
var is_attacking: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	attack_cooldown = max(0.0, attack_cooldown - delta)
	for spell in spell_cooldowns.keys():
		spell_cooldowns[spell] = max(0.0, spell_cooldowns[spell] - delta)

# ─── Melee ────────────────────────────────────────────────────────────────────
func melee_attack() -> void:
	if attack_cooldown > 0 or is_attacking:
		return
	
	# Only the authority can initiate an attack
	var player = get_parent()
	if player.has_method("is_multiplayer_authority") and not player.is_multiplayer_authority():
		return

	var attack_speed = _get_attack_speed()
	attack_cooldown = attack_speed
	is_attacking = true
	
	# Sync the animation to other peers
	if NetworkManager.is_multiplayer_active():
		rpc("sync_attack_anim")
	# Find enemies in melee arc
	# Windup
	await get_tree().create_timer(0.15).timeout 
	var targets = _find_targets_in_arc(melee_range, melee_arc_degrees)
	for target in targets:
		if target.has_method("take_damage"):
			var dmg = _calculate_melee_damage()
			target.take_damage(dmg)
			emit_signal("attack_hit", target, dmg)
			AIDungeonMaster.narrate_combat_start(target.enemy_name if target.has_method("take_damage") else "enemy")
	
	# Recovery: keep is_attacking true for a while longer to let the animation finish
	# A total of 0.8s (0.15 windup + 0.65 recovery) covers most standard attack cycles.
	await get_tree().create_timer(0.65).timeout 
	is_attacking = false

@rpc("any_peer", "call_local", "unreliable")
func sync_attack_anim() -> void:
	var player = get_parent()
	if player.has_method("_animate_attack"):
		player._animate_attack()

func _find_targets_in_arc(range_dist: float, arc_deg: float) -> Array:
	var player = get_parent()
	var player_pos = player.global_position
	# Use character_yaw if available (root node doesn't rotate, only the mesh does)
	var player_forward: Vector3
	if "character_yaw" in player:
		player_forward = Vector3(-sin(player.character_yaw), 0, -cos(player.character_yaw))
	else:
		player_forward = -player.global_transform.basis.z
		player_forward.y = 0
		if player_forward.length_squared() > 0.001:
			player_forward = player_forward.normalized()
	
	var targets = []
	for body in get_tree().get_nodes_in_group("enemy"):
		var raw_to_target = body.global_position - player_pos
		if raw_to_target.length() > range_dist:
			continue
			
		# Flatten relative target vector horizontally
		var to_target = raw_to_target
		to_target.y = 0
		if to_target.length_squared() < 0.001:
			targets.append(body) # Directly standing inside them
			continue
			
		to_target = to_target.normalized()
		var angle = rad_to_deg(player_forward.angle_to(to_target))
		if angle <= arc_deg * 0.5:
			targets.append(body)
	return targets

func _calculate_melee_damage() -> int:
	var base = PlayerData.get_attack_power()
	var variance = randi_range(-3, 5)
	return max(1, base + variance)

func _get_attack_speed() -> float:
	match PlayerData.char_class:
		"Rogue":   return 0.4
		"Warrior": return 0.6
		"Ranger":  return 0.7
		_:         return 0.8

# ─── Ranged ───────────────────────────────────────────────────────────────────
func ranged_attack() -> void:
	if attack_cooldown > 0:
		return
	if PlayerData.char_class not in ["Ranger", "Rogue"]:
		return
	attack_cooldown = 1.0
	if projectile_scene:
		var projectile = projectile_scene.instantiate()
		get_tree().current_scene.add_child(projectile)
		var player = get_parent()
		projectile.global_position = player.global_position + Vector3(0, 1.4, 0)
		if "character_yaw" in player:
			projectile.direction = Vector3(-sin(player.character_yaw), 0, -cos(player.character_yaw))
		else:
			projectile.direction = -player.global_transform.basis.z
		projectile.damage = _calculate_melee_damage()

# ─── Magic ────────────────────────────────────────────────────────────────────
func cast_active_spell() -> void:
	var class_data = ClassData.get_all_classes()
	var my_class: Dictionary = {}
	for c in class_data:
		if c["name"] == PlayerData.char_class:
			my_class = c
			break
	if my_class.is_empty():
		return
	var abilities = my_class["abilities"]
	if active_spell_index >= abilities.size():
		return
	var spell = abilities[active_spell_index]
	if spell_cooldowns.get(spell["name"], 0.0) > 0:
		return
	if not PlayerData.use_mana(spell["mana_cost"]):
		print("[Combat] Not enough mana!")
		return
	spell_cooldowns[spell["name"]] = float(spell["cooldown"])
	emit_signal("spell_cast", spell["name"])
	_execute_spell(spell)

func _execute_spell(spell: Dictionary) -> void:
	match spell["name"]:
		"Fireball":
			_cast_projectile_spell(30, 4.0, Color.ORANGE_RED)
		"Arcane Missile":
			for i in range(3):
				await get_tree().create_timer(0.2).timeout
				_cast_projectile_spell(10, 2.0, Color.CYAN)
		"Healing Word":
			PlayerData.heal(40)
			AIDungeonMaster.narrate_custom("You channel healing energy, knitting wounds shut with golden light.")
		"Smite":
			var targets = _find_targets_in_arc(3.0, 90.0)
			for t in targets:
				if t.has_method("take_damage"):
					t.take_damage(PlayerData.get_attack_power() + 20)
		"Power Strike":
			var targets = _find_targets_in_arc(melee_range, 60.0)
			for t in targets:
				if t.has_method("take_damage"):
					t.take_damage(int(PlayerData.get_attack_power() * 1.5))
		"War Cry":
			# Applied via temporary buff – simplified
			var player = get_parent()
			if player.has_method("_animate_taunt"):
				player._animate_taunt()
			print("[Combat] War Cry activated! +20% damage for 10s")
		"Backstab":
			var targets = _find_targets_in_arc(2.0, 180.0)
			for t in targets:
				if t.has_method("take_damage"):
					t.take_damage(PlayerData.get_attack_power() * 3)
		"Barrage":
			for i in range(5):
				await get_tree().create_timer(0.1).timeout
				_cast_projectile_spell(int(PlayerData.get_attack_power() * 0.5), 3.0, Color.YELLOW_GREEN)
		"Marked Shot":
			# Mark nearest enemy
			var targets = _find_targets_in_arc(20.0, 45.0)
			if targets.size() > 0 and targets[0].has_method("apply_mark"):
				targets[0].apply_mark()
		_:
			print("[Combat] Spell not yet implemented: ", spell["name"])

func _cast_projectile_spell(damage: int, speed: float, color: Color) -> void:
	# Create a simple projectile MeshInstance3D manually
	var proj = RigidBody3D.new()
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.2
	mesh.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mesh.material_override = mat
	proj.add_child(mesh)
	var col = CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 0.2
	proj.add_child(col)
	get_tree().current_scene.add_child(proj)
	var player = get_parent()
	proj.global_position = player.global_position + Vector3(0, 1.4, 0)
	var forward: Vector3
	if "character_yaw" in player:
		forward = Vector3(-sin(player.character_yaw), 0, -cos(player.character_yaw))
	else:
		forward = -player.global_transform.basis.z
	proj.linear_velocity = forward * (speed * 10.0)
	# Script to handle collision
	var script = GDScript.new()
	script.source_code = """extends RigidBody3D
var damage = %d
var lifetime = 3.0
func _ready():
	body_entered.connect(_on_body_entered)
	await get_tree().create_timer(lifetime).timeout
	queue_free()
func _on_body_entered(body):
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
""" % damage
	script.reload()
	proj.set_script(script)

func cycle_spell() -> void:
	var class_data = ClassData.get_all_classes()
	for c in class_data:
		if c["name"] == PlayerData.char_class:
			active_spell_index = (active_spell_index + 1) % c["abilities"].size()
			break
