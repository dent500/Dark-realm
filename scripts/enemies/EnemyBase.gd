## EnemyBase.gd
## Base class for all enemies. Handles AI states, navigation, combat, loot drops.
extends CharacterBody3D

# ─── Signals ───────────────────────────────────────────────────────────────────
signal enemy_died(enemy: Node)
signal enemy_spotted_player

# ─── Config ────────────────────────────────────────────────────────────────────
@export var enemy_name: String = "Unknown Enemy"
@export var max_hp: int = 50
@export var attack_damage: int = 10
@export var attack_range: float = 2.0
@export var detection_range: float = 12.0
@export var move_speed: float = 3.5
@export var xp_reward: int = 25
@export var gold_reward_min: int = 0
@export var gold_reward_max: int = 10
@export var loot_table: Array[Dictionary] = [
	{"item": "ancient_coin", "chance": 0.4, "min": 1, "max": 2}
]

# ─── State Machine ─────────────────────────────────────────────────────────────
enum State { IDLE, PATROL, CHASE, ATTACK, HURT, DEAD }
var state: State = State.IDLE
var current_hp: int = 0
var attack_cooldown: float = 0.0
var attack_rate: float = 1.5  # seconds between attacks
var hurt_timer: float = 0.0

# ─── Navigation ───────────────────────────────────────────────────────────────
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var detection_area: Area3D = $DetectionArea
@onready var mesh_instance: Node3D = $EnemyMesh

@onready var left_arm: Node3D = get_node_or_null("EnemyMesh/Torso/LeftArmPivot") as Node3D
@onready var right_arm: Node3D = get_node_or_null("EnemyMesh/Torso/RightArmPivot") as Node3D
@onready var left_leg: Node3D = get_node_or_null("EnemyMesh/Torso/LeftLegPivot") as Node3D
@onready var right_leg: Node3D = get_node_or_null("EnemyMesh/Torso/RightLegPivot") as Node3D

var anim_player: AnimationPlayer = null
var current_anim: String = ""

const ANIM_FPS = 30.0
const ANIM_DATA = {
	"Walk": [0, 170, true],
	"Idle": [170, 349, true],
	"Attack": [781, 890, false],
	"Death": [1212, 1264, false]
}

var player: CharacterBody3D = null
var patrol_target: Vector3 = Vector3.ZERO
var home_position: Vector3 = Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("enemy")
	current_hp = max_hp
	home_position = global_position
	patrol_target = global_position
	
	# Transition to High-Fidelity Animated Skeleton
	if mesh_instance:
		mesh_instance.visible = false # Hide procedural blocks
	
	var skel_scene = load("res://assets/Enemies/skeleton_animated.glb")
	if skel_scene:
		var skel_inst = skel_scene.instantiate()
		add_child(skel_inst)
		skel_inst.scale = Vector3(0.25, 0.25, 0.25) # Balanced humanoid size
		skel_inst.rotation.y = PI # Face forward relative to enemy movement
		
		# More robust AnimationPlayer lookup
		var anim_players = skel_inst.find_children("*", "AnimationPlayer", true)
		if anim_players.size() > 0:
			anim_player = anim_players[0]
			_slice_animations(anim_player)
			anim_player.playback_default_blend_time = 0.2
			_play_animation("Idle")
			print("[Enemy] Animated skeleton integrated and sliced.")
		else:
			push_error("[Enemy] AnimationPlayer NOT FOUND in ", skel_inst.name)
	
	if detection_area:
		detection_area.body_entered.connect(_on_body_entered_detection)
		detection_area.body_exited.connect(_on_body_exited_detection)
	_pick_new_patrol_target()

func _physics_process(delta: float) -> void:
	if state == State.DEAD or not is_multiplayer_authority():
		return
	_apply_gravity(delta)
	attack_cooldown = max(0.0, attack_cooldown - delta)
	if hurt_timer > 0:
		hurt_timer -= delta
		if hurt_timer <= 0:
			_return_to_chase_or_idle()
	match state:
		State.IDLE:    _process_idle(delta)
		State.PATROL:  _process_patrol(delta)
		State.CHASE:   _process_chase(delta)
		State.ATTACK:  _process_attack(delta)
	move_and_slide()
	
	# Animation Logic
	if anim_player:
		if state == State.IDLE or state == State.PATROL:
			if velocity.length() > 0.1:
				_play_animation("Walk")
			else:
				_play_animation("Idle")
		elif state == State.CHASE:
			_play_animation("Walk") # Or "Run" if available
	else:
		# Fallback to procedural walk animation if GLB failed
		if velocity.length() > 0.1:
			var walk_time = Time.get_ticks_msec() / 150.0
			if left_leg: left_leg.rotation.x = cos(walk_time) * 0.6
			if right_leg: right_leg.rotation.x = sin(walk_time) * 0.6
			if left_arm: left_arm.rotation.x = sin(walk_time) * 0.6
		else:
			if left_leg: left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.0, 10.0 * delta)
			if right_leg: right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.0, 10.0 * delta)
			if left_arm: left_arm.rotation.x = lerpf(left_arm.rotation.x, 0.0, 10.0 * delta)

func _process(delta: float) -> void:
	# Billboard health bar to face camera
	var hp_bar = get_node_or_null("HealthBar3D")
	if hp_bar:
		var cam = get_viewport().get_camera_3d()
		if cam:
			hp_bar.look_at(cam.global_position, Vector3.UP, true)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

# ─── States ───────────────────────────────────────────────────────────────────
func _process_idle(_delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	if randf() < 0.005:
		_pick_new_patrol_target()
		state = State.PATROL

func _process_patrol(delta: float) -> void:
	var dir = (patrol_target - global_position)
	if dir.length() < 1.5:
		state = State.IDLE
		return
	var move_dir = dir
	move_dir.y = 0
	move_dir = move_dir.normalized()
	velocity.x = move_dir.x * (move_speed * 0.6)
	velocity.z = move_dir.z * (move_speed * 0.6)
	var target_look = Vector3(patrol_target.x, global_position.y, patrol_target.z)
	if global_position.distance_to(target_look) > 0.1:
		look_at(target_look)

func _process_chase(_delta: float) -> void:
	if player == null:
		state = State.IDLE
		return
	var dist = global_position.distance_to(player.global_position)
	if dist > detection_range * 1.5:
		player = null
		state = State.PATROL
		_pick_new_patrol_target()
		return
	if dist <= attack_range:
		state = State.ATTACK
		return
	
	var move_dir = (player.global_position - global_position)
	move_dir.y = 0
	move_dir = move_dir.normalized()
	
	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed
	# Face player
	var look_pos = Vector3(player.global_position.x, global_position.y, player.global_position.z)
	if global_position.distance_to(look_pos) > 0.1:
		look_at(look_pos)

func _process_attack(_delta: float) -> void:
	if player == null:
		state = State.IDLE
		return
	var dist = global_position.distance_to(player.global_position)
	if dist > attack_range * 1.3:
		state = State.CHASE
		return
	velocity = Vector3.ZERO
	if attack_cooldown <= 0:
		attack_cooldown = attack_rate
		_do_attack()

func _do_attack() -> void:
	# Attack Animation
	if anim_player:
		_play_animation("Attack")
	else:
		var r_arm = get_node_or_null("EnemyMesh/RightArmPivot")
		if r_arm:
			var tw = create_tween()
			tw.tween_property(r_arm, "rotation:x", deg_to_rad(60), 0.2)
			tw.tween_property(r_arm, "rotation:x", deg_to_rad(-80), 0.1)
			tw.tween_property(r_arm, "rotation:x", 0.0, 0.4).set_delay(0.1)
		
	# Wait for swing impact
	await get_tree().create_timer(0.25).timeout
	
	# Only the server applies damage to the player
	if NetworkManager.is_multiplayer_active() and not is_multiplayer_authority(): return
	
	if not is_instance_valid(player) or state == State.DEAD: return
	
	var dmg = attack_damage + randi_range(-2, 3)
	if "is_blocking" in player and player.is_blocking:
		dmg = 1
		_spawn_dmg_text("BLOCKED!", true, player.global_position)
	else:
		_spawn_dmg_text(dmg, true, player.global_position)
		
	# Notify the specific player client to take damage
	if player.has_method("receive_damage"):
		player.rpc_id(player.get_multiplayer_authority(), "receive_damage", dmg)
	else:
		# Singleplayer fallback
		PlayerData.take_damage(dmg)

func _return_to_chase_or_idle() -> void:
	if player != null:
		state = State.CHASE
	else:
		state = State.IDLE

func _pick_new_patrol_target() -> void:
	var offset = Vector3(
		randf_range(-8.0, 8.0),
		0,
		randf_range(-8.0, 8.0)
	)
	patrol_target = home_position + offset

# ─── Detection ────────────────────────────────────────────────────────────────
func _on_body_entered_detection(body: Node3D) -> void:
	if body.is_in_group("player") and state != State.DEAD:
		player = body
		state = State.CHASE
		emit_signal("enemy_spotted_player")
		AIDungeonMaster.narrate_combat_start(enemy_name)

func _on_body_exited_detection(body: Node3D) -> void:
	if body.is_in_group("player"):
		pass  # Keep chasing until out of extended range

# ─── Damage Receiving ──────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return
	current_hp -= amount
	hurt_timer = 0.3
	state = State.HURT
	_spawn_dmg_text(amount, false, global_position)
	
	# Update 3D Health Bar
	var hp_fg = get_node_or_null("HealthBar3D/Fg")
	if hp_fg:
		var pct = max(0.0, float(current_hp) / float(max_hp))
		hp_fg.scale.x = pct
		hp_fg.position.x = -(1.2 - (1.2 * pct)) / 2.0
	
	# Flash red (Recursive for all mesh parts)
	if mesh_instance:
		_flash_node_red(mesh_instance)
	
	if current_hp <= 0:
		_die()

func _flash_node_red(node: Node) -> void:
	if node is MeshInstance3D:
		var mat = node.get_surface_override_material(0)
		if mat:
			var old_color = mat.albedo_color
			mat.albedo_color = Color.RED
			get_tree().create_timer(0.2).timeout.connect(func(): mat.albedo_color = old_color)
	for child in node.get_children():
		_flash_node_red(child)

func apply_mark() -> void:
	## Applied by Ranger's Marked Shot — next hit deals 200% damage
	pass  # simplified

func _get_base_color() -> Color:
	return Color.GRAY

# ─── Death ────────────────────────────────────────────────────────────────────
func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	# Disable collisions immediately so they don't block loot interaction
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	# Also disable any internal collision shapes
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
		if child is Area3D:
			child.set_deferred("monitoring", false)
			child.set_deferred("monitorable", false)
	# Give rewards immediately
	PlayerData.gain_experience(xp_reward)
	var gold = randi_range(gold_reward_min, gold_reward_max)
	if gold > 0:
		PlayerData.add_gold(gold)
	print("[", enemy_name, "] Died. Gave ", xp_reward, " XP and ", gold, " gold.")
	AIDungeonMaster.narrate_enemy_death(enemy_name)
	# Drop loot
	_drop_loot()
	# ── Death Animation: GLB death if available ──
	if anim_player:
		_play_animation("Death")
	elif mesh_instance:
		var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(mesh_instance, "rotation:x", deg_to_rad(80.0), 0.4)
		tween.tween_property(mesh_instance, "position:y", -1.2, 0.5).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(2.5).timeout
	queue_free()

func _play_animation(anim_name: String) -> void:
	if not anim_player or current_anim == anim_name:
		return
		
	# Best guess mapping for common animation names
	var actual_anim = anim_name
	var list = anim_player.get_animation_list()
	
	if not anim_player.has_animation(actual_anim):
		for name in list:
			if anim_name.to_lower() in name.to_lower():
				actual_anim = name
				break
	
	if anim_player.has_animation(actual_anim):
		anim_player.play(actual_anim)
		current_anim = anim_name
	elif list.size() > 0:
		# Fallback if somehow slicing failed
		if anim_player.has_animation("Take 001"):
			anim_player.play("Take 001")
			current_anim = anim_name

func _slice_animations(player: AnimationPlayer) -> void:
	if not player or not player.has_animation("Take 001"):
		return
	
	var base_anim = player.get_animation("Take 001")
	
	for anim_name in ANIM_DATA:
		var start_f = ANIM_DATA[anim_name][0]
		var end_f = ANIM_DATA[anim_name][1]
		var loop = ANIM_DATA[anim_name][2]
		
		var start_t = start_f / ANIM_FPS
		var end_t = end_f / ANIM_FPS
		var duration = end_t - start_t
		
		var new_anim = Animation.new()
		new_anim.length = duration
		new_anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		
		# Copy relevant tracks and keys
		for track_idx in range(base_anim.get_track_count()):
			var track_path = base_anim.track_get_path(track_idx)
			var type = base_anim.track_get_type(track_idx)
			
			var new_track = new_anim.add_track(type)
			new_anim.track_set_path(new_track, track_path)
			
			for key_idx in range(base_anim.track_get_key_count(track_idx)):
				var key_time = base_anim.track_get_key_time(track_idx, key_idx)
				if key_time >= start_t and key_time <= end_t:
					var value = base_anim.track_get_key_value(track_idx, key_idx)
					new_anim.track_insert_key(new_track, key_time - start_t, value)
		
		# Godot 4: Animations must be added to a library
		var lib_name = "" # Default library
		var lib = player.get_animation_library(lib_name)
		if not lib:
			lib = AnimationLibrary.new()
			player.add_animation_library(lib_name, lib)
			
		lib.add_animation(anim_name, new_anim)

func _drop_loot() -> void:
	if loot_table.is_empty():
		return
		
	# Load the script for dynamic instantiation
	var pickup_script = load("res://scripts/inventory/Pickup.gd")
	if not pickup_script:
		push_error("[Enemy] Failed to load Pickup.gd script!")
		return
		
	for entry in loot_table:
		var chance = entry.get("chance", 0.3)
		if randf() < chance:
			var item_id = entry.get("item", "")
			if item_id == "": continue
			
			# Create a StaticBody3D with the Pickup script attached
			var pickup = StaticBody3D.new()
			pickup.set_script(pickup_script)
			pickup.item_id = item_id
			pickup.quantity = randi_range(entry.get("min", 1), entry.get("max", 1))
			
			# Spawn at the enemy's feet (y=0) and slightly forward
			var spawn_pos = global_position + Vector3(0, 0.2, 0)
			# Set position BEFORE adding to child tree so _ready() logic is consistent
			pickup.position = spawn_pos
			get_tree().current_scene.add_child(pickup)
			# The Pickup script handles its own "pop" animation in _ready()

func _spawn_dmg_text(amount: Variant, is_player: bool, spawn_pos: Vector3) -> void:
	var lbl = Label3D.new()
	if typeof(amount) == TYPE_STRING:
		lbl.text = amount
	else:
		lbl.text = "-" + str(amount) if is_player else str(amount)
	
	lbl.font_size = 96 if is_player else 64
	lbl.modulate = Color(1.0, 0.2, 0.2) if is_player else Color(0.9, 0.9, 0.9)
	lbl.outline_modulate = Color.BLACK
	lbl.outline_size = 12
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	get_tree().current_scene.add_child(lbl)
	lbl.global_position = spawn_pos + Vector3(randf_range(-0.5, 0.5), 2.0, randf_range(-0.5, 0.5))
	
	var tween = lbl.create_tween()
	tween.tween_property(lbl, "global_position:y", lbl.global_position.y + 1.2, 0.8).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(lbl, "scale", Vector3(1.5, 1.5, 1.5) if is_player else Vector3(1.3, 1.3, 1.3), 0.2)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8).set_delay(0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(lbl.queue_free)
