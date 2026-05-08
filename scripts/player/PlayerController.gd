## PlayerController.gd
## Handles all player movement, camera control, and interaction in the 3D world.
extends CharacterBody3D

# ─── Movement Config ──────────────────────────────────────────────────────────
@export var walk_speed: float = 3.5
@export var sprint_speed: float = 6.5
@export var jump_velocity: float = 4.5
@export var sprint_stamina_drain: float = 20.0  # per second
@export var stamina_regen_rate: float = 8.0  	# per second (when not sprinting)
@export var acceleration: float = 8.0
@export var friction: float = 10.0

# ─── Camera Config ────────────────────────────────────────────────────────────
@export var mouse_sensitivity: float = 0.002
@export var camera_min_pitch: float = -60.0
@export var camera_max_pitch: float = 70.0
@export var camera_distance: float = 5.0
@export var attack_speed_scale: float = 1.1 # Faster, more responsive swings

# ─── Nodes ───────────────────────────────────────────────────────────────────
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var interact_ray: RayCast3D = $InteractRay
@onready var combat_system = $CombatSystem
@onready var inventory = $Inventory
@onready var animation_player: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
var mesh: Node3D = null
var head_model = null
var left_arm = null
var right_arm = null
var left_arm_pivot = null
var elbow_l_pivot = null
var wrist_l_pivot = null
var right_arm_pivot = null
var elbow_r_pivot = null
var wrist_r_pivot = null
var left_leg_pivot = null
var knee_l_pivot = null
var right_leg_pivot = null
var knee_r_pivot = null
var hair_mesh = null
var left_eye = null
var right_eye = null
var shield_mesh = null
var weapon_mesh = null
var torso_mesh = null
var belt_mesh = null
var pauldrons_l = null
var pauldrons_r = null
var boots_l = null
var boots_r = null
var heel_l = null
var heel_r = null

# ─── Robe Spring Sway ────────────────────────────────────────────────────────
var _robe_skirt: MeshInstance3D = null
var _skirt_tilt: Vector3 = Vector3.ZERO   # current spring state (euler angles)


# Facial Materials (Stored for dynamic updates)
var _face_mat_skin: Variant
var _face_mat_white: Variant
var _face_mat_iris: Variant
var _face_mat_pupil: Variant
var _face_mat_mouth: Variant
var _face_nodes: Array = []
var _face_skeleton: Skeleton3D = null


# ─── Multiplayer Variables (Synced via MultiplayerSynchronizer) ───────────────

var _spawn_time: int = 0
var _remote_watchdog_timer: float = 0.0

func _process(delta: float) -> void:
	# 1. Update Animations & Cloth
	_update_animations(delta)
	_update_robe_skirt(delta)
	
	# 2. Update Visual Orientation
	if mesh:
		if is_multiplayer_authority():
			# Authority calculates orientation from movement
			var move_vec = velocity
			if move_vec.length() > 0.1:
				# Corrected: Align model's forward direction with movement.
				# We negate the direction because the native model faces +Z but Godot expects -Z forward.
				var look_dir = Vector3(move_vec.x, 0, move_vec.z)
				if not look_dir.is_zero_approx():
					var target_basis = Basis.looking_at(-look_dir, Vector3.UP)
					sync_quaternion = Quaternion(target_basis)
		
		# All peers (Local & Remote) smoothly interpolate to the synced quaternion
		var lerp_weight = 15.0 * delta
		if Time.get_ticks_msec() - _spawn_time < 500: 
			lerp_weight = 1.0 # Snap on spawn
		
		var current_q = mesh.quaternion
		mesh.quaternion = current_q.slerp(sync_quaternion, lerp_weight)
	
	# 3. Remote Player Interpolation (Smoothing)
	if not is_multiplayer_authority():
		if sync_position.length_squared() > 0:
			# Use velocity as a hint to improve interpolation
			var dist = global_position.distance_to(sync_position)
			if dist > 5.0: # Snap if too far
				global_position = sync_position
			else:
				var weight = 10.0 * delta # Adjust for smoothness vs responsiveness
				global_position = global_position.lerp(sync_position, weight)
		
	# 4. Remote Player Watchdog (Safety pass for visibility)
	if not is_multiplayer_authority():
		_remote_watchdog_timer += delta
		if _remote_watchdog_timer > 1.0:
			_remote_watchdog_timer = 0.0
			_enforce_remote_visibility()

func _enforce_remote_visibility() -> void:
	if not mesh: return
	# If remote player has no children, they failed to build
	if mesh.get_child_count() == 0 and not sync_custom_data.is_empty():
		_on_appearance_relay(get_multiplayer_authority(), sync_custom_data)
	
	# Ensure they are on the correct layer and visible
	_recursive_show(mesh)
	visible = true

func _update_animations(delta: float) -> void:
	if _jump_timer > 0:
		_jump_timer -= delta
		
	# This runs for both local authority and remote peers
	var is_moving = velocity.length() > 0.1
	var target_anim = "player/idle"
	
	# REMOTE PEER LOGIC: Since remote peers don't run move_and_slide(), is_on_floor() is always false.
	# We use velocity.y and _jump_timer as hints to detect if they are actually jumping.
	var on_floor = is_on_floor()
	if not is_multiplayer_authority():
		on_floor = abs(velocity.y) < 0.1 and _jump_timer <= 0
	
	# BUFFER: Treat as on_floor for a few frames after landing to prevent flicker
	if on_floor:
		_landed_timer = 0.1
	else:
		_landed_timer -= delta
	
	var stable_on_floor = on_floor or _landed_timer > 0
	
	if not stable_on_floor or _jump_timer > 0:
		target_anim = "player/jump"
	elif is_moving:
		target_anim = "player/run" if is_sprinting else "player/walk"
	
	if is_dead:
		return

	# Allow Attack/Block to override movement animations
	if not (combat_system and combat_system.is_attacking) and not is_blocking:
		if target_anim == "player/idle":
			if animation_player and animation_player.has_animation("player/idle"):
				if animation_player.current_animation != "player/idle":
					animation_player.play("player/idle", 0.3)
		else:
			if animation_player and animation_player.has_animation(target_anim):
				if animation_player.current_animation != target_anim:
					animation_player.play(target_anim, 0.2)
				
				# Scale movement animation speed
				if target_anim != "player/jump":
					var v_speed = velocity.length() / (sprint_speed if is_sprinting else walk_speed)
					animation_player.set_speed_scale(max(0.6, v_speed * 1.2))
				else:
					animation_player.set_speed_scale(1.0) # Jump is a one-shot feel

func _update_facial_nodes() -> void:
	pass

# ─── State ────────────────────────────────────────────────────────────────────
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_sprinting: bool = false
var is_exhausted: bool = false
var is_interacting: bool = false
var is_in_combat: bool = false
var is_dead: bool = false
var is_blocking: bool = false
var _landed_timer: float = 0.0
var _jump_timer: float = 0.0
var current_speed: float = 0.0
var is_underwater: bool = false
var bubble_particles: GPUParticles3D = null

# Combo Tracking
var attack_combo_step: int = 0
var last_attack_time: float = 0.0
var sync_position: Vector3 = Vector3.ZERO
var sync_quaternion: Quaternion = Quaternion.IDENTITY
var _last_synced_config: Dictionary = {}
var sync_custom_data: Dictionary = {}:
	set(val):
		# PROTECTION: Never let network data overwrite our own local character data
		# Our own local data should only come from SaveSystem/PlayerData
		if is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
			if multiplayer.get_unique_id() == get_multiplayer_authority():
				return
				
		# OPTIMIZATION: Only rebuild if the appearance configuration has actually changed.
		if val == _last_synced_config: 
			return
			
		sync_custom_data = val
		_last_synced_config = val.duplicate()
		
		# When remote data arrives via MultiplayerSynchronizer, rebuild the character
		if not is_multiplayer_authority() and not val.is_empty():
			print("[PlayerController] Remote config change detected for peer ", name, ". Rebuilding rig.")
			_build_native_block_character(val)

# Camera
var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var character_yaw: float = 0.0
var turn_speed: float = 3.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("player")
	
	# Ensure remote players always start at their last known sync position
	if not is_multiplayer_authority():
		var data = NetworkManager.peer_data.get(int(name.replace("Player", "").replace("@", "")), {})
		if data.has("last_pos"):
			global_position = data["last_pos"]
	_spawn_time = Time.get_ticks_msec()
	
	# 1. Start the Handshake Process
	if is_multiplayer_authority() and not multiplayer.is_server():
		# Request a fresh data relay from the server to ensure we see everyone
		NetworkManager.request_player_relay.rpc_id(1)
		
		# Wait longer for network and local save data to settle
		get_tree().create_timer(1.5).timeout.connect(_request_appearance_handshake)
	
	# Fallback: if we are a remote player and still haven't built our character after 2 seconds, 
	# request a data refresh from the server.
	if not is_multiplayer_authority():
		get_tree().create_timer(2.5).timeout.connect(func():
			if _last_synced_config.is_empty():
				print("[PlayerController] Mannequin detected for ", name, ". Requesting sync.")
				NetworkManager.request_player_relay.rpc_id(1)
		)
	
	# Reference components
	mesh = get_node_or_null("Visuals")
	if not camera: camera = get_node_or_null("CameraPivot/SpringArm3D/Camera3D")
	if not spring_arm: spring_arm = get_node_or_null("CameraPivot/SpringArm3D")
	
	# Listen for appearance updates from the network relay
	if not NetworkManager.player_appearance_updated.is_connected(_on_appearance_relay):
		NetworkManager.player_appearance_updated.connect(_on_appearance_relay)
	
	# Check if we already have data for this player in the NetworkManager cache
	var my_node_id = get_multiplayer_authority()
	if NetworkManager.peer_data.has(my_node_id):
		_on_appearance_relay(my_node_id, NetworkManager.peer_data[my_node_id])
		spring_arm.add_excluded_object(self) # Prevent camera snapping inside player
		spring_arm.collision_mask = 1 # Only collide with World (Layer 1), ignore Player (Layer 2)
		camera_pitch = deg_to_rad(-15.0)
		spring_arm.rotation.x = camera_pitch
	
	# Set Multiplayer Authority based on node name
	if NetworkManager.is_multiplayer_active():
		var my_id = multiplayer.get_unique_id()
		var clean_name = name.replace("@", "").replace("Player", "")
		var node_id = clean_name.to_int()
		
		# Local setup based on peer ID matching node name
		if node_id == my_id and my_id > 0:
			print("[PlayerController] Initializing local player: ", node_id)
			set_multiplayer_authority(my_id)
			if has_node("MultiplayerSynchronizer"):
				$MultiplayerSynchronizer.set_multiplayer_authority(my_id)
				
			if camera:
				camera.make_current()
				camera.current = true
				camera.position = Vector3.ZERO
				camera.rotation = Vector3.ZERO
			visible = true
			
			# Build local character once
			var my_config = _get_local_config()
			_last_synced_config = my_config.duplicate()
			sync_custom_data = my_config
			_build_native_block_character(my_config)
		elif node_id > 0:
			# Remote player initialization
			if camera:
				camera.current = false
			visible = true
			
			# Force a build if we already have data
			if not sync_custom_data.is_empty():
				_on_appearance_relay(my_node_id, sync_custom_data)
				_last_synced_config = sync_custom_data.duplicate()
				_build_native_block_character(sync_custom_data)
			else:
				# Default build while waiting for sync
				_build_native_block_character({})
	else:
		# Singleplayer initialization
		if camera:
			camera.make_current()
			camera.current = true
		_build_native_block_character(_get_local_config())
	
	# ─── Local player initialization (Singleplayer or Authority) ───
	if is_multiplayer_authority():
		if camera: 
			camera.make_current()
		add_to_group("local_player")
	else:
		# Remote player: disable local-only systems
		if camera:
			camera.current = false
		if spring_arm:
			spring_arm.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Snap to server position on start for clients to prevent void fall
	if NetworkManager.is_multiplayer_active() and not multiplayer.is_server():
		_wait_for_terrain_and_snap()

func setup_as_local() -> void:
	print("[PlayerController] Received setup_as_local RPC!")
	var my_id = multiplayer.get_unique_id()
	set_multiplayer_authority(my_id)
	if has_node("MultiplayerSynchronizer"):
		$MultiplayerSynchronizer.set_multiplayer_authority(my_id)
	
	if not is_in_group("local_player"):
		add_to_group("local_player")
	
	if camera:
		camera.make_current()
		camera.current = true
	visible = true
	print("[PlayerController] Local setup complete. Authority: ", is_multiplayer_authority())

func _wait_for_terrain_and_snap() -> void:
	var terrain = get_tree().get_first_node_in_group("terrain")
	if terrain and not terrain.has_node("TerrainCollision"):
		if terrain.has_signal("terrain_ready"):
			await terrain.terrain_ready
	
	await get_tree().create_timer(0.2).timeout
	_snap_to_terrain()
	if is_multiplayer_authority() and camera:
		camera.make_current()
	
	# Character visuals are now initialized in _check_authority_and_setup to ensure they run on the host too.

	# (Debug spheres and labels removed for final cleanup)

	# Add a small debug light to the local player to help see underground
	if is_multiplayer_authority():
		var light = OmniLight3D.new()
		light.light_energy = 2.0
		light.omni_range = 10.0
		light.position.y = 1.0
		add_child(light)

	# Face customization
	if not PlayerData.face_customization_changed.is_connected(_update_facial_features):
		PlayerData.face_customization_changed.connect(_update_facial_features)
	
	# Final check for underground status after terrain loads
	get_tree().create_timer(1.0).timeout.connect(_check_underground)
	
	# Ensure InputMap is set up
	_setup_input_map()
	
	# Connect PlayerData signals
	if not PlayerData.stats_changed.is_connected(_on_stats_changed):
		PlayerData.stats_changed.connect(_on_stats_changed)
	
	# ─── Camera Rig Alignment & Force-Centering ───
	if camera_pivot:
		camera_pivot.position = Vector3(0, 1.6, 0)
		camera_pivot.rotation = Vector3.ZERO
	if spring_arm:
		spring_arm.position = Vector3(0, 0, 0)
		spring_arm.rotation = Vector3.ZERO
		spring_arm.spring_length = camera_distance
		spring_arm.add_excluded_object(get_rid())
	if camera:
		camera.position = Vector3(0, 0, 0)
		camera.rotation = Vector3.ZERO
		camera.h_offset = 0.0 # Force center
		camera.v_offset = 0.0
	
	# Ensure the player mesh itself is perfectly centered in the collision cylinder
	if mesh:
		mesh.position = Vector3.ZERO
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if inventory and inventory.has_method("grant_starting_items"):
		inventory.grant_starting_items()
		
	# ─── Fix Interaction Ray ───
	if interact_ray:
		interact_ray.add_exception(self)
		if camera:
			if interact_ray.get_parent():
				interact_ray.get_parent().remove_child(interact_ray)
			camera.add_child(interact_ray)
			interact_ray.position = Vector3.ZERO
			interact_ray.target_position = Vector3(0, 0, -15.0) 
			interact_ray.add_exception(self)
			for child in get_children():
				if child is CollisionObject3D:
					interact_ray.add_exception(child)
	
	_on_stats_changed()
	_setup_bubbles()

func _setup_bubbles() -> void:
	if not is_multiplayer_authority(): return
	
	bubble_particles = GPUParticles3D.new()
	bubble_particles.name = "Bubbles"
	bubble_particles.emitting = false
	bubble_particles.amount = 20
	bubble_particles.lifetime = 1.5
	
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(0.5, 0.2, 0.5)
	mat.direction = Vector3.UP
	mat.spread = 20.0
	mat.gravity = Vector3(0, 2.0, 0)
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.0
	mat.scale_min = 0.05
	mat.scale_max = 0.15
	bubble_particles.process_material = mat
	
	var sphere = SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	var s_mat = StandardMaterial3D.new()
	s_mat.albedo_color = Color(1, 1, 1, 0.6)
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = s_mat
	bubble_particles.draw_pass_1 = sphere
	
	add_child(bubble_particles)
	bubble_particles.position = Vector3(0, 1.0, 0) # Near face

func _setup_input_map() -> void:
	var actions = {
		"open_character": KEY_C,
		"open_inventory": KEY_I,
		"open_map": KEY_M,
		"attack": MOUSE_BUTTON_LEFT,
		"block": MOUSE_BUTTON_RIGHT,
		"jump": KEY_SPACE,
		"interact": KEY_E,
		"ui_cancel": KEY_ESCAPE,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"move_backward": KEY_S,
		"sprint": KEY_SHIFT,
		"cast_spell": KEY_1,
		"cycle_spell": KEY_2,
		"ranged_attack": KEY_Q
	}
	
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		
		var key = actions[action]
		var found = false
		for event in InputMap.action_get_events(action):
			if (key is int and event is InputEventKey and event.physical_keycode == key) or \
			   (key is int and event is InputEventMouseButton and event.button_index == key):
				found = true
				break
		
		if not found:
			if key == MOUSE_BUTTON_LEFT or key == MOUSE_BUTTON_RIGHT:
				var ev = InputEventMouseButton.new()
				ev.button_index = key
				InputMap.action_add_event(action, ev)
			else:
				var ev = InputEventKey.new()
				ev.keycode = actions[action]
				InputMap.action_add_event(action, ev)
				
				# Also add as physical keycode for robustness
				var ev_phys = InputEventKey.new()
				ev_phys.physical_keycode = actions[action]
				InputMap.action_add_event(action, ev_phys)

func _check_authority_and_setup() -> void:
	pass # Logic moved to _ready for immediate initialization
	_recursive_show(mesh)

func _check_underground() -> void:
	if not is_multiplayer_authority(): return
	var terrain = get_tree().get_first_node_in_group("terrain")
	if not terrain or not terrain.has_node("TerrainCollision"): return
	if terrain and terrain.has_method("_get_h"):
		var h = terrain._get_h(global_position.x, global_position.z)
		if global_position.y < h - 0.5:
			global_position.y = h + 0.5

# ─── Physics ──────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
		
	if is_dead:
		return
	
	_handle_stamina(delta)

	# Handle Blocking Logic
	if Input.is_action_pressed("block") and (not combat_system or not combat_system.is_attacking):
		if not is_blocking:
			is_blocking = true
			_animate_block_start_v3()
	else:
		if is_blocking:
			is_blocking = false
			_animate_block_end_v3()

	_apply_gravity(delta)
	_handle_movement(delta)
	_update_interact_prompt()
	_check_water_status()
	move_and_slide()
	
	# After physics, authority updates the sync position
	sync_position = global_position
	
	_handle_void_recovery()
	_update_robe_skirt(delta)

func _check_water_status() -> void:
	var terrain = get_tree().get_first_node_in_group("terrain")
	var water_y = 0.0
	if terrain and "water_level" in terrain:
		water_y = terrain.water_level
	
	var head_y = global_position.y + 1.6
	var currently_under = head_y < water_y
	
	if currently_under != is_underwater:
		is_underwater = currently_under
		var hud = get_tree().get_first_node_in_group("hud")
		if hud:
			hud.set_underwater(is_underwater)
		if bubble_particles:
			bubble_particles.emitting = is_underwater

func _handle_stamina(delta: float) -> void:
	if is_sprinting:
		PlayerData.current_stamina = max(0, PlayerData.current_stamina - sprint_stamina_drain * delta)
		if PlayerData.current_stamina <= 0:
			is_sprinting = false
			is_exhausted = true
	else:
		PlayerData.current_stamina = min(PlayerData.max_stamina, PlayerData.current_stamina + stamina_regen_rate * delta)
		# Recover from exhaustion when stamina is back above 25%
		if is_exhausted and PlayerData.current_stamina >= PlayerData.max_stamina * 0.25:
			is_exhausted = false

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		if is_underwater:
			# Buoyancy: slower fall, slight upward float if not moving down
			velocity.y -= gravity * 0.2 * delta
			velocity.y = lerp(velocity.y, 0.5, 2.0 * delta)
		else:
			velocity.y -= gravity * delta

func _handle_movement(delta: float) -> void:
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (camera_pivot.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	is_sprinting = Input.is_action_pressed("sprint") and input_dir.length() > 0 and PlayerData.current_stamina > 0 and not is_exhausted
	
	var target_speed = sprint_speed if is_sprinting else walk_speed
	
	# Apply movement penalties during actions
	if is_blocking:
		target_speed *= 0.4
	elif combat_system and combat_system.is_attacking:
		target_speed *= 0.5
		
	if is_underwater:
		target_speed *= 0.5 # Slow down underwater
	
	if input_dir.length() > 0:
		current_speed = lerp(current_speed, target_speed, acceleration * delta)
		# Improved: Interpolate the horizontal velocity vector for directional inertia
		var target_vel = direction * current_speed
		velocity.x = lerp(velocity.x, target_vel.x, acceleration * delta)
		velocity.z = lerp(velocity.z, target_vel.z, acceleration * delta)
		
		if direction.length() > 0.1:
			# The model faces movement direction; no manual rotation needed here as it's handled in _process via sync_quaternion
			pass
	else:
		current_speed = lerp(current_speed, 0.0, friction * delta)
		# Smooth deceleration
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		if animation_player and animation_player.has_animation("player/jump"):
			animation_player.play("player/jump")

func _on_stats_changed() -> void:
	if PlayerData.current_hp <= 0 and not is_dead:
		_on_player_died()
	
	if weapon_mesh:
		weapon_mesh.visible = PlayerData.equipped.get("main_hand", "") != ""
	if shield_mesh:
		shield_mesh.visible = PlayerData.equipped.get("off_hand", "") != ""
	if belt_mesh:
		belt_mesh.visible = PlayerData.equipped.get("body", "") != ""
	if pauldrons_l:
		pauldrons_l.visible = PlayerData.equipped.get("hands", "") != ""
	if pauldrons_r:
		pauldrons_r.visible = PlayerData.equipped.get("hands", "") != ""
	if boots_l: boots_l.visible = true
	if boots_r: boots_r.visible = true

# ─── Input ────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if is_dead or not is_multiplayer_authority(): return
	
	if event.is_action_pressed("open_character"):
		_toggle_ui("character")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_inventory"):
		_toggle_ui("inventory")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_map"):
		_toggle_ui("map")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_toggle_ui("pause_menu")
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return
	
	# Clicking into the window should ALWAYS try to capture the mouse if not paused
	if event is InputEventMouseButton and event.pressed:
		if not GameManager.is_paused:
			if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if is_dead or GameManager.is_paused: 
		return
	
	if event is InputEventMouseMotion:
		# AGGRESSIVE FAIL-SAFE: If mouse isn't captured but we are playing, force capture it.
		# This handles cases where focus is lost or blocked by a transparent HUD layer.
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and not GameManager.is_paused:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			character_yaw -= event.relative.x * mouse_sensitivity
			camera_pitch -= event.relative.y * mouse_sensitivity
			camera_pitch = clamp(camera_pitch, deg_to_rad(-80), deg_to_rad(80))
			
			spring_arm.rotation.x = camera_pitch
			camera_pivot.rotation.y = character_yaw

	if event.is_action_pressed("attack"):
		if combat_system and not combat_system.is_attacking:
			# Contextual attack: Ranger with bow uses ranged_attack
			if PlayerData.char_class == "Ranger" and PlayerData.equipped.get("main_hand", "").to_lower().contains("bow"):
				combat_system.ranged_attack()
			else:
				if has_method("_animate_attack"): call("_animate_attack")
				combat_system.melee_attack()
	
	if event.is_action_pressed("ranged_attack"):
		if combat_system and not combat_system.is_attacking:
			combat_system.ranged_attack()
			
	if event.is_action_pressed("cast_spell"):
		if combat_system:
			print("[Player] Casting spell...")
			combat_system.cast_active_spell()
			
	if event.is_action_pressed("cycle_spell"):
		if combat_system:
			print("[Player] Cycling spell...")
			combat_system.cycle_spell()
			var hud = get_tree().get_first_node_in_group("hud")
			if hud:
				if hud.has_method("update_ability_slots"): hud.update_ability_slots()
				if hud.has_method("show_toast"):
					var class_data = ClassData.get_all_classes()
					for c in class_data:
						if c["name"] == PlayerData.char_class:
							var spell = c["abilities"][combat_system.active_spell_index]
							hud.show_toast("Active Ability: " + spell["name"])
							break
	
	if event.is_action_pressed("interact"):
		_try_interact()

# ─── Interaction ──────────────────────────────────────────────────────────────
func _update_interact_prompt() -> void:
	if not interact_ray or is_interacting: return
	
	interact_ray.force_raycast_update() # Ensure ray matches current camera frame
	if interact_ray.is_colliding():
		var collider = interact_ray.get_collider()
		if collider and collider.has_method("interact"):
			var hud = get_tree().get_first_node_in_group("hud")
			if hud:
				var prompt = "Interact"
				if "display_name" in collider: prompt = "Pick up " + str(collider.display_name)
				elif "npc_name" in collider: prompt = "Talk to " + str(collider.npc_name)
				hud.show_interact_prompt(prompt)
				return
				
	var hud = get_tree().get_first_node_in_group("hud")
	if not hud: return
	
	# Fallback: if looking at nothing, check if we are standing near an NPC
	var npcs = get_tree().get_nodes_in_group("npc")
	for npc in npcs:
		if npc.get("player_nearby") == true:
			var n_name = npc.get("npc_name")
			hud.show_interact_prompt("Talk to " + str(n_name if n_name != null else "NPC"))
			return
			
	hud.hide_interact_prompt()

func _try_interact() -> void:
	if not interact_ray: return
	
	interact_ray.force_raycast_update()
	if interact_ray.is_colliding():
		var collider = interact_ray.get_collider()
		print("[Player] Interacting with: ", collider.name)
		if collider.has_method("interact"):
			collider.interact(self)
			return
		else:
			print("[Player] Collider has no interact method")
	
	# Proximity fallback for NPCs
	var npcs2 = get_tree().get_nodes_in_group("npc")
	for npc in npcs2:
		if npc.get("player_nearby") == true:
			if npc.has_method("interact"):
				npc.interact(self)
				return
	
	print("[Player] No valid interaction target found (Raycast or Proximity)")

func try_pickup(item_data: Dictionary) -> bool:
	if inventory and inventory.has_method("add_item_dict"):
		return inventory.add_item_dict(item_data)
	elif inventory and inventory.has_method("add_item"):
		return inventory.add_item(item_data.get("id", ""), item_data.get("quantity", 1))
	return false

# ─── UI Toggling ──────────────────────────────────────────────────────────────
func _toggle_ui(ui_name: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toggle_panel"):
		hud.toggle_panel(ui_name)

# ─── Death & Damage ──────────────────────────────────────────────────────────
@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: int) -> void:
	# Only the local player (authority) should process their own PlayerData changes
	if is_multiplayer_authority():
		PlayerData.take_damage(amount)
		print("[Player] Received network damage: ", amount)

func _recursive_show(n: Node) -> void:
	if n is VisualInstance3D:
		n.visible = true
		n.layers = 2 # Player is on Layer 2 to avoid camera clipping
		# CRITICAL: Force a valid AABB so the engine doesn't cull the procedural mesh
		n.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	for child in n.get_children():
		_recursive_show(child)

func _on_player_died() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	print("[Player] Player died!")
	# ── Death Animation: slump forward ──
	if mesh and is_instance_valid(mesh):
		var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(mesh, "rotation:x", deg_to_rad(80.0), 0.5)
		tween.tween_property(mesh, "position:y", mesh.position.y - 0.8, 0.4)
	# Show death screen via HUD
	await get_tree().create_timer(2.0).timeout
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_death_screen"):
		hud.show_death_screen()

func respawn() -> void:
	is_dead = false
	PlayerData.current_hp = PlayerData.max_hp
	PlayerData.emit_signal("stats_changed")
	# Reset death animation
	if mesh:
		mesh.rotation.x = 0.0
		mesh.position.y = 0.0
	# Teleport to nearest spawn point
	var spawns = get_tree().get_nodes_in_group("spawn_point")
	if spawns.size() > 0:
		global_position = spawns[0].global_position
	else:
		global_position = Vector3(0, 1.0, 0) # Safe floor-level fallback

func teleport_to(pos: Vector3, rot_deg: float) -> void:
	global_position = pos
	rotation.y = 0 # Keep root alignment clean
	character_yaw = deg_to_rad(rot_deg)
	if camera_pivot:
		camera_pivot.rotation.y = character_yaw
	if mesh:
		var target_q = Quaternion(Vector3.UP, character_yaw)
		mesh.quaternion = target_q
		sync_quaternion = target_q

# ─── Combat Animations ────────────────────────────────────────────────────────
func _animate_attack() -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	# Reset combo after 1.5 seconds of inactivity
	if current_time - last_attack_time > 1.5:
		attack_combo_step = 0
	last_attack_time = current_time
	
	var tw = create_tween().set_parallel(true)
	
	if attack_combo_step == 0:
		_animate_combo_strike_1(tw)
	elif attack_combo_step == 1:
		_animate_combo_strike_2(tw)
	else:
		_animate_combo_strike_3(tw)
		attack_combo_step = -1 # Next addition wraps to 0
	
	attack_combo_step += 1

# ─── COMBAT ANIMATIONS (FBX DRIVEN) ───

func _animate_combo_strike_1(tw: Tween) -> void:
	if animation_player and animation_player.has_animation("player/strike_1"):
		animation_player.play("player/strike_1", 0.1)
		animation_player.speed_scale = attack_speed_scale
		# Procedural Lunge: move the entire visual rig to prevent spine popping
		tw.tween_property(mesh, "position:z", -0.4, 0.15 / attack_speed_scale).set_trans(Tween.TRANS_QUART)
		tw.tween_property(mesh, "position:z", 0.0, 0.3 / attack_speed_scale).set_delay(0.25 / attack_speed_scale)
	else:
		# Fallback to simple procedural if FBX not loaded
		if right_arm_pivot:
			tw.tween_property(right_arm_pivot, "rotation:z", deg_to_rad(65), 0.15)
			tw.tween_property(right_arm_pivot, "rotation:z", deg_to_rad(35), 0.3).set_delay(0.2)

func _animate_combo_strike_2(tw: Tween) -> void:
	if animation_player and animation_player.has_animation("player/strike_2"):
		animation_player.play("player/strike_2", 0.1)
		animation_player.speed_scale = attack_speed_scale
		tw.tween_property(mesh, "position:z", -0.5, 0.15 / attack_speed_scale).set_trans(Tween.TRANS_QUART)
		tw.tween_property(mesh, "position:z", 0.0, 0.3 / attack_speed_scale).set_delay(0.25 / attack_speed_scale)

func _animate_combo_strike_3(tw: Tween) -> void:
	if animation_player and animation_player.has_animation("player/strike_3"):
		animation_player.play("player/strike_3", 0.1)
		animation_player.speed_scale = attack_speed_scale
		# Lunges move the entire character visual root (skeleton) slightly forward
		tw.tween_property(mesh, "position:z", -0.4, 0.2 / attack_speed_scale).set_trans(Tween.TRANS_QUART)
		tw.tween_property(mesh, "position:z", 0.0, 0.4 / attack_speed_scale).set_delay(0.3 / attack_speed_scale)
	
	# Keep wrist/blade alignment for finishers
	if weapon_mesh and is_instance_valid(weapon_mesh):
		var tw_w = create_tween()
		tw_w.tween_property(weapon_mesh, "rotation:x", 0.0, 0.2)
		tw_w.tween_property(weapon_mesh, "rotation:x", deg_to_rad(-90), 0.4).set_delay(0.4)

func _add_combo_recovery(tw: Tween) -> void:
	if right_arm_pivot: tw.tween_property(right_arm_pivot, "rotation", Vector3(0, 0, deg_to_rad(15)), 0.6).set_delay(0.2).set_trans(Tween.TRANS_SINE)
	if elbow_r_pivot: tw.tween_property(elbow_r_pivot, "rotation", Vector3.ZERO, 0.6).set_delay(0.2)
	if weapon_mesh:
		tw.tween_property(weapon_mesh, "rotation:x", deg_to_rad(-90), 0.6).set_delay(0.2)
	if wrist_r_pivot:
		tw.tween_property(wrist_r_pivot, "rotation", Vector3.ZERO, 0.6).set_delay(0.2)
	if torso_mesh:
		tw.tween_property(torso_mesh, "position:y", 1.05, 0.6).set_delay(0.2)
		tw.tween_property(torso_mesh, "position:z", 0.0, 0.6).set_delay(0.2)
		tw.tween_property(torso_mesh, "rotation:x", 0.0, 0.6).set_delay(0.2)
		tw.tween_property(torso_mesh, "rotation:y", 0.0, 0.6).set_delay(0.2)
	if left_leg_pivot: tw.tween_property(left_leg_pivot, "rotation:x", 0.0, 0.6).set_delay(0.2)
	if right_leg_pivot: tw.tween_property(right_leg_pivot, "rotation:x", 0.0, 0.6).set_delay(0.2)
	if knee_l_pivot: tw.tween_property(knee_l_pivot, "rotation:x", 0.0, 0.6).set_delay(0.2)
	if knee_r_pivot: tw.tween_property(knee_r_pivot, "rotation:x", 0.0, 0.6).set_delay(0.2)

func _animate_block_start_v3() -> void:
	if animation_player and animation_player.has_animation("player/block_idle"):
		animation_player.play("player/block_idle", 0.2)

func _animate_block_end_v3() -> void:
	if animation_player:
		animation_player.play("player/idle", 0.3)

func _animate_taunt() -> void:
	if animation_player and animation_player.has_animation("player/taunt"):
		animation_player.play("player/taunt", 0.2)

## Constructs the character visual rig from scratch using the Native FBX system.
## Handles local player data (PlayerData) or remote peer data if provided.
func is_ghost() -> bool:
	# A ghost is a node that has existed for a bit but has no actual body geometry
	if Time.get_ticks_msec() - _spawn_time < 2000: return false
	var visuals = get_node_or_null("Visuals")
	if not visuals: return true
	return visuals.get_child_count() == 0

func _build_native_block_character(char_appearance: Dictionary = {}) -> void:
	if not mesh: return
	
	# 1. CLEANUP: Remove ALL existing rigs/meshes to prevent conjoined twins
	for child in mesh.get_children():
		mesh.remove_child(child)
		child.queue_free()

	var root_anchor = Node3D.new()
	root_anchor.name = "BasemeshInstance"
	mesh.add_child(root_anchor)

	# ── Build the full config ──
	var combined_config = char_appearance.duplicate()
	var is_local = is_multiplayer_authority()
	
	if not combined_config.has("race"): 
		combined_config["race"] = PlayerData.race if is_local else "human"
	if not combined_config.has("gender"): 
		combined_config["gender"] = PlayerData.gender if is_local else "male"
	
	# ONLY merge PlayerData for the LOCAL player
	if is_local:
		var local_appearance = PlayerData.appearance_config.duplicate()
		for key in local_appearance:
			if not combined_config.has(key):
				combined_config[key] = local_appearance[key]
		if not combined_config.has("skin_color"):
			var skin_idx = PlayerData.skin_tone
			if skin_idx >= 0 and skin_idx < PlayerData.SKIN_TONES.size():
				combined_config["skin_color"] = PlayerData.SKIN_TONES[skin_idx]
		
		# Ensure class is included for the local build
		if not combined_config.has("char_class"):
			combined_config["char_class"] = PlayerData.char_class
	else:
		# For remote players, ensure we have at least a default skin color if missing
		if not combined_config.has("skin_color"):
			combined_config["skin_color"] = Color(0.8, 0.7, 0.6)

	var char_race = combined_config.get("race", "Human")
	# IMPORTANT: Default to empty if not found, so we can detect if sync hasn't happened yet
	var char_class = combined_config.get("char_class", "") 
	
	# Apply race body_profile (scales, special features) from RaceData
	var all_races: Array = RaceData.get_all_races()
	for r in all_races:
		if r["name"].to_lower() == char_race.to_lower():
			var profile: Dictionary = r.get("body_profile", {})
			var slider_keys := ["muscle"]
			for key in profile:
				if key in slider_keys:
					combined_config[key] = profile[key] * char_appearance.get(key, 1.0)
				else:
					combined_config[key] = profile[key]
			break

	# Apply starter clothing from ClassData
	var all_classes: Array = ClassData.get_all_classes()
	var class_found = false
	for c in all_classes:
		if c["name"].to_lower() == char_class.to_lower():
			class_found = true
			var sc: Dictionary = c.get("starter_clothing", {})
			combined_config["clothing_type"] = sc.get("type",         "none")
			combined_config["shirt_color"]   = sc.get("shirt_color",  Color(0.55, 0.42, 0.28))
			combined_config["pants_color"]   = sc.get("pants_color",  Color(0.25, 0.18, 0.12))
			combined_config["robe_color"]    = sc.get("robe_color",   Color(0.18, 0.14, 0.45))
			break
			
	# If class not synced yet, don't build gear/clothing to avoid 'Warrior' ghosts
	if not class_found and not is_local:
		print("[PlayerController] Waiting for class sync for: ", char_race)
		return

	# ── Gear ──
	var sw: Dictionary = {}
	var class_anim_config: Dictionary = {}
	for cls in all_classes:
		if cls["name"] == char_class:
			sw = cls.get("starter_weapons", {})
			class_anim_config = cls.get("animations", {})
			combined_config["main_hand_cfg"] = sw.get("main_hand", {})
			combined_config["off_hand_cfg"]  = sw.get("off_hand",  {})
			break

	var build_data = CharacterBuilder.build_character(mesh, combined_config)

	var build_scale: float = combined_config.get("build_scale", 1.0)
	mesh.position.y = -0.21 * build_scale

	var skeleton = build_data.get("skeleton") as Skeleton3D
	if not skeleton:
		return
		
	# Store references but DO NOT overwrite the class-level 'mesh' (Visuals) variable
	var rig = build_data.get("instance") as Node3D
	
	# Extract gear references from build_data
	var gear = build_data.get("gear", {})
	weapon_mesh = gear.get("weapon")
	shield_mesh = gear.get("shield")
	
	# Native FBX rig already contains its own AnimationPlayer
	if rig:
		animation_player = CharacterBuilder.initialize_animations(rig, skeleton, rig, class_anim_config)
	
	# Fetch bone attachments
	left_arm_pivot = CharacterBuilder.get_or_create_ba("LeftArm", skeleton)
	right_arm_pivot = CharacterBuilder.get_or_create_ba("RightArm", skeleton)
	elbow_l_pivot = CharacterBuilder.get_or_create_ba("LeftForeArm", skeleton)
	elbow_r_pivot = CharacterBuilder.get_or_create_ba("RightForeArm", skeleton)
	wrist_l_pivot = CharacterBuilder.get_or_create_ba("LeftHand", skeleton)
	wrist_r_pivot = CharacterBuilder.get_or_create_ba("RightHand", skeleton)
	left_leg_pivot = CharacterBuilder.get_or_create_ba("LeftUpLeg", skeleton)
	right_leg_pivot = CharacterBuilder.get_or_create_ba("RightUpLeg", skeleton)
	knee_l_pivot = CharacterBuilder.get_or_create_ba("LeftLeg", skeleton)
	knee_r_pivot = CharacterBuilder.get_or_create_ba("RightLeg", skeleton)

	# Find the robe skirt node
	_robe_skirt = null
	var skirt_candidate = skeleton.find_child("RobeSkirt", true, false)
	if skirt_candidate is MeshInstance3D:
		_robe_skirt = skirt_candidate
	
	# Find and assign procedural armor pieces
	for seg in build_data.get("segments", []):
		var n: String = seg.name.to_lower()
		if "pauldron_l" in n: pauldrons_l = seg
		elif "pauldron_r" in n: pauldrons_r = seg
		elif "belt" in n: belt_mesh = seg
		elif "boot_l" in n: boots_l = seg
		elif "boot_r" in n: boots_r = seg
		elif "chest" in n: torso_mesh = seg

	if animation_player and animation_player.has_animation("player/idle"):
		animation_player.play("player/idle", 0.0)
		
	# Final visibility pass
	_recursive_show(get_node("Visuals"))

func _rebuild_for_peer(peer_id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	var data = NetworkManager.get_player_data(peer_id)
	if data:
		_build_native_block_character(data)

# ─── Appearance Handshake System ──────────────────────────────────────────────
func _request_appearance_handshake() -> void:
	if is_multiplayer_authority():
		# Tell everyone: "I'm here, tell me what you look like and here's my data"
		rpc("_rpc_handshake_appearance", _get_local_config())

@rpc("any_peer", "call_local", "reliable")
func _rpc_handshake_appearance(data: Dictionary) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	
	# 1. Update the sender's model on our machine via the setter (which handles rebuilding)
	if sync_custom_data != data:
		sync_custom_data = data
		_recursive_show(mesh)
	
	# 2. If someone asked us, and we are NOT them, reply with our own data
	if sender_id != 0 and sender_id != multiplayer.get_unique_id():
		if is_multiplayer_authority():
			rpc_id(sender_id, "_rpc_sync_appearance_reply", _get_local_config())

func _on_appearance_relay(id: int, data: Dictionary) -> void:
	if id != get_multiplayer_authority(): return
	
	# Only rebuild if the data has actually changed
	if _last_synced_config == data and mesh.get_child_count() > 0:
		return
		
	_last_synced_config = data.duplicate()
	sync_custom_data = data
	_build_native_block_character(data)
	_recursive_show(mesh)

@rpc("any_peer", "call_local", "reliable")
func _rpc_sync_appearance_reply(data: Dictionary) -> void:
	_on_appearance_relay(get_multiplayer_authority(), data)

func _get_local_config() -> Dictionary:
	var cfg = {}
	cfg["character_name"] = PlayerData.character_name
	cfg["race"] = PlayerData.race if "race" in PlayerData else "human"
	cfg["gender"] = PlayerData.gender if "gender" in PlayerData else "male"
	cfg["skin_color"] = PlayerData.skin_color if "skin_color" in PlayerData else Color(0.8, 0.7, 0.6)
	cfg["muscle"] = PlayerData.muscle if "muscle" in PlayerData else 1.0
	cfg["clothing_type"] = PlayerData.clothing_type if "clothing_type" in PlayerData else "robes"
	cfg["robe_color"] = PlayerData.robe_color if "robe_color" in PlayerData else Color.NAVY_BLUE
	cfg["face_customization"] = PlayerData.face_customization if "face_customization" in PlayerData else {}
	return cfg

func _update_facial_features() -> void:
	pass


# ─── Robe Spring Sway ────────────────────────────────────────────────────────
func _update_robe_skirt(delta: float) -> void:
	if not _robe_skirt or not is_instance_valid(_robe_skirt):
		return

	var horiz_vel := Vector2(velocity.x, velocity.z)
	var speed: float = horiz_vel.length()
	var speed_t: float = clamp(speed / sprint_speed, 0.0, 1.0)

	const MAX_TILT_DEG: float = 10.0
	var tilt_target := Vector3.ZERO

	if speed > 0.1 and mesh and is_instance_valid(mesh):
		var world_dir := Vector3(horiz_vel.x, 0.0, horiz_vel.y).normalized()
		var local_dir: Vector3 = mesh.global_transform.basis.inverse() * world_dir
		var tilt_rad: float = deg_to_rad(MAX_TILT_DEG) * speed_t
		tilt_target.x = local_dir.z * tilt_rad
		tilt_target.z = -local_dir.x * tilt_rad

	var time: float = Time.get_ticks_msec() / 1000.0
	var sway_freq: float = 1.8 + speed_t * 2.2
	var sway_amp: float  = deg_to_rad(3.5) * speed_t
	tilt_target.z += sin(time * sway_freq) * sway_amp

	const STIFFNESS: float = 5.5
	_skirt_tilt = _skirt_tilt.lerp(tilt_target, STIFFNESS * delta)
	_robe_skirt.rotation = _skirt_tilt

func _handle_void_recovery() -> void:
	if global_position.y < -100.0:
		print("[Player] Void fall at ", global_position, " — respawning.")
		respawn()

func _snap_to_terrain() -> void:
	var terrain = get_tree().get_first_node_in_group("terrain")
	if terrain and terrain.has_method("get_height_at"):
		var ground_y = terrain.get_height_at(global_position.x, global_position.z)
		global_position.y = ground_y + 1.0
		print("[Player] Snapped to terrain at Y: ", global_position.y)
	else:
		# Fallback: simple raycast down
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 50, global_position + Vector3.DOWN * 50)
		var result = space_state.intersect_ray(query)
		if result:
			global_position = result.position + Vector3.UP
			print("[Player] Snapped via raycast to: ", global_position)
