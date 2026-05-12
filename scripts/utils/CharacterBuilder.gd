## CharacterBuilder.gd
## Orchestrates the creation of a procedural character using a Native FBX skeleton.
class_name CharacterBuilder

static func build_character(root_node: Node3D, config: Dictionary) -> Dictionary:
	print("[Diagnostic] CharacterBuilder.build_character (Native FBX Mode) started.")
	
	# 1. Instantiate the Native Mixamo FBX to guarantee perfect Rest Poses
	var fbx_path = "res://assets/animations/player/locomotion/Idle.fbx"
	var fbx = load(fbx_path)
	if not fbx:
		printerr("[CharacterBuilder] ERROR: Failed to load base rig at: ", fbx_path)
		return _build_fallback_character(root_node, config)
	
	var rig = fbx.instantiate()
	rig.visible = true
	root_node.add_child(rig)
	# Store race so initialize_animations can pick the right idle
	rig.set_meta("race", config.get("race", ""))

	# Apply racial height/size scale — Dwarf 0.75×, Orc 1.15×, Elf 1.1×, etc.
	var build_scale: float = config.get("build_scale", 1.0)
	rig.scale = Vector3(build_scale, build_scale, build_scale)

	# 2. Extract Skeleton
	var skeleton: Skeleton3D = null
	for child in rig.find_children("*", "Skeleton3D", true):
		skeleton = child
		break
		
	if not skeleton:
		print("[Diagnostic] CRITICAL ERROR: FBX has no skeleton!")
		return {}

	print("[Diagnostic] Native Skeleton acquired: ", skeleton.name)
		
	# 3. Strip original Mixamo meshes
	for child in rig.find_children("*", "MeshInstance3D", true):
		child.queue_free()
	
	# 4. Build Meat segments on the perfect skeleton
	var segments = MeatBuilder.build_meat(skeleton, config)
	
	# 5. Apply skin material
	var skin_color = config.get("skin_color", Color(0.85, 0.76, 0.68))
	var flesh_mat = MeatBuilder.create_flesh_material(skin_color)
	for mi in segments:
		mi.material_override = flesh_mat

	# 6. Build clothing layer
	MeatBuilder.build_clothing(skeleton, config)

	# 7. Attach Gear (Starter Weapons / Equipment)
	var main_cfg = config.get("main_hand_cfg", {})
	var off_cfg  = config.get("off_hand_cfg", {})
	var gear = {}
	if main_cfg.get("file") or off_cfg.get("file") or main_cfg.get("weapon_type") or off_cfg.get("weapon_type"):
		gear = attach_gear(skeleton, main_cfg, off_cfg)

	# 8. Final Pose Polish (Wrist Rotation etc)
	_apply_heroic_pose(skeleton)

	return {
		"instance": rig,
		"skeleton": skeleton,
		"segments": segments,
		"gear": gear
	}


static func initialize_animations(rig: Node3D, skeleton: Skeleton3D, _unused: Node3D, class_anim_config: Dictionary = {}) -> AnimationPlayer:
	# Find the native AnimationPlayer built into the FBX rig
	var ap: AnimationPlayer = null
	for child in rig.find_children("*", "AnimationPlayer", true):
		ap = child
		break
	if not ap:
		print("[CharacterBuilder] WARNING: No AnimationPlayer in native rig.")
		return null

	# Map: game animation name → FBX file path (Base defaults)
	var ANIM_MAP: Dictionary = {
		"player/idle":       "res://assets/animations/player/locomotion/Idle.fbx",
		"player/idle_a":     "res://assets/animations/player/locomotion/idle_01.fbx",
		"player/idle_b":     "res://assets/animations/player/locomotion/idle_looking_ver._1.fbx",
		"player/idle_orc":   "res://assets/animations/player/locomotion/Orc_Idle.fbx",
		"player/walk":       "res://assets/animations/player/locomotion/walk_forward.fbx",
		"player/run":        "res://assets/animations/player/locomotion/run_forward.fbx",
		"player/block_idle": "res://assets/animations/player/combat/block_idle.fbx",
		"player/strike_1":   "res://assets/animations/player/combat/melee_combo_ver._1.fbx",
		"player/strike_2":   "res://assets/animations/player/combat/melee_combo_ver._2.fbx",
		"player/strike_3":   "res://assets/animations/player/combat/melee_combo_ver._3.fbx",
		"player/taunt":      "res://assets/animations/player/gestures/taunt_battlecry.fbx",
		"player/jump":       "res://assets/animations/player/mobility/jump.fbx",
	}

	# Apply class-specific overrides
	for key in class_anim_config.keys():
		ANIM_MAP[key] = class_anim_config[key]

	# Build a unified library
	var lib := AnimationLibrary.new()

	for game_name in ANIM_MAP:
		var fbx_path: String = ANIM_MAP[game_name]
		var packed = load(fbx_path)
		if not packed:
			print("[CharacterBuilder] WARNING: Could not load ", fbx_path)
			continue
		var scene: Node3D = packed.instantiate()
		var src_ap: AnimationPlayer = null
		for child in scene.find_children("*", "AnimationPlayer", true):
			src_ap = child
			break
		if src_ap and src_ap.get_animation_list().size() > 0:
			var src_anim: Animation = src_ap.get_animation(src_ap.get_animation_list()[0]).duplicate()
			
			if game_name.to_lower().contains("jump"):
				src_anim.loop_mode = Animation.LOOP_NONE
			else:
				src_anim.loop_mode = Animation.LOOP_LINEAR

			# Strip ALL position tracks — the CharacterBody3D physics engine owns
			# real-world translation. Baked position data (including Hips X/Z root
			# motion) causes the mesh to drift forward then snap back at the loop
			# point. Hips Y (vertical bob) is a minor cosmetic loss but far less
			# jarring than the snap, so we disable all position tracks uniformly.
			for t in range(src_anim.get_track_count()):
				if src_anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
					src_anim.track_set_enabled(t, false)

			# Friendly name for library (no slashes allowed in AnimationLibrary keys)
			var lib_key: String = game_name.replace("player/", "")
			lib.add_animation(lib_key, src_anim)
		scene.queue_free()

	# Wipe existing libraries and install ours
	for old_lib in ap.get_animation_library_list():
		ap.remove_animation_library(old_lib)
	ap.add_animation_library("player", lib)

	# Decide which idle to use for this character.
	var race: String = rig.get_meta("race", "").to_lower()
	var idle_key: String

	if class_anim_config.has("player/idle"):
		idle_key = "player/idle" # Uses the overridden class animation
	elif race == "orc":
		idle_key = "player/idle_orc"
	else:
		# Alternate idle_a / idle_b deterministically based on race name
		idle_key = "player/idle_b" if (race.hash() % 2 == 0) else "player/idle_a"
		# Fall back to idle_a if neither new idle loaded
		if not lib.get_animation_list().has(idle_key.replace("player/", "")):
			idle_key = "player/idle_a"
		if not lib.get_animation_list().has(idle_key.replace("player/", "")):
			idle_key = "player/idle"

	ap.active = true
	var play_key: String = idle_key.replace("player/", "")
	if lib.get_animation_list().has(play_key):
		ap.play("player/" + play_key)
	elif lib.get_animation_list().has("idle"):
		ap.play("player/idle")
	elif ap.get_animation_list().size() > 0:
		ap.play(ap.get_animation_list()[0])

	print("[CharacterBuilder] Animations loaded: ", lib.get_animation_list())
	print("[CharacterBuilder] Playing idle: ", play_key, " for race: ", race)
	return ap

static func _build_fallback_character(root: Node3D, config: Dictionary) -> Dictionary:
	print("[CharacterBuilder] Building SAFETY FALLBACK character.")
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = CapsuleMesh.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mesh_inst.material_override = mat
	root.add_child(mesh_inst)
	return {"instance": mesh_inst}


## Find an existing BoneAttachment3D for a bone, or create one if missing.
## Called by PlayerController to get pivot nodes for IK and weapon attachment.
static func get_or_create_ba(bone_name: String, skeleton: Skeleton3D) -> BoneAttachment3D:
	# MeatBuilder names attachments "Link_CleanBoneName"
	var clean = bone_name.replace("mixamorig_", "").replace("mixamorig:", "")
	var existing = skeleton.get_node_or_null("Link_" + clean)
	if existing is BoneAttachment3D:
		return existing
	# Create a fresh one if not found
	var att := BoneAttachment3D.new()
	att.name = "Link_" + clean
	skeleton.add_child(att)
	# Find best matching bone (handles both prefixed and clean names)
	var full_name = "mixamorig_" + clean
	var idx = skeleton.find_bone(full_name)
	if idx == -1:
		idx = skeleton.find_bone(clean)
	if idx != -1:
		att.bone_name = skeleton.get_bone_name(idx)
	return att

## Attach class starter weapons to the character's hands.
## weapon_cfg / off_cfg are dictionaries with keys "file" and "node" from ClassData.
## Returns {"weapon": MeshInstance3D, "shield": MeshInstance3D} (either may be null).
static func attach_gear(skeleton: Skeleton3D,
		weapon_cfg: Dictionary = {}, off_cfg: Dictionary = {}) -> Dictionary:
	var result := {"weapon": null, "shield": null}
	if skeleton == null:
		return result

	result["weapon"] = _attach_weapon(skeleton, weapon_cfg, "RightHand", false)
	result["shield"] = _attach_weapon(skeleton, off_cfg,   "LeftHand",  true)
	return result


## Load a mesh from a GLB by node name, OR build a procedural weapon, and attach to hand.
static func _attach_weapon(skeleton: Skeleton3D, cfg: Dictionary,
		bone_name: String, is_off_hand: bool) -> MeshInstance3D:
	if cfg.is_empty():
		return null

	var mi: MeshInstance3D = null

	# --- Option B: GLB-based Weapon (Preferred) ---
	if cfg.has("file") and cfg.has("node"):
		var file_path = cfg["file"]
		var node_name = cfg["node"]
		var packed = load(file_path)
		if packed:
			var scene: Node = packed.instantiate()
			var target: Node = _find_node_by_name(scene, node_name)
			if target:
				var meshes: Array = []
				if target is MeshInstance3D:
					meshes.append(target)
				meshes.append_array(target.find_children("*", "MeshInstance3D", true))
				
				if meshes.size() > 0:
					# Create a container if there are multiple meshes to keep the hierarchy clean
					var container: Node3D
					if meshes.size() > 1:
						container = Node3D.new()
						container.name = node_name + "_Container"
						var ba = get_or_create_ba(bone_name, skeleton)
						ba.add_child(container)
						mi = container # Return container as the 'mi' handle
					
					for m in meshes:
						var mi_part: MeshInstance3D = m.duplicate()
						if container:
							container.add_child(mi_part)
						else:
							var ba = get_or_create_ba(bone_name, skeleton)
							ba.add_child(mi_part)
							mi = mi_part
						
						# Link materials for each part
						WeaponBuilder._attempt_material_fix(mi_part, node_name)
					
					print("[CharacterBuilder] Loaded GLB weapon: ", node_name, " (Parts: ", meshes.size(), ") from ", file_path)
				else:
					print("[CharacterBuilder] WARNING: No MeshInstance3D found within node '", node_name, "' in ", file_path)
			scene.queue_free() # Clean up the instantiated scene
		else:
			print("[CharacterBuilder] WARNING: Could not load weapon file: ", file_path)

	# --- Option A: Procedural Weapon (Fallback) ---
	if mi == null and cfg.has("weapon_type"):
		var w_type: String = cfg["weapon_type"]
		var hand_ba: BoneAttachment3D = get_or_create_ba(bone_name, skeleton)
		mi = WeaponBuilder.build_weapon(w_type, hand_ba, cfg)
		if mi:
			print("[CharacterBuilder] Created procedural weapon: ", w_type)

	# --- Common Positioning & Scaling ---
	if mi:
		# Apply scale override if provided
		if cfg.has("scale"):
			var s = cfg["scale"]
			if s is float or s is int:
				mi.scale = Vector3(s, s, s)
			elif s is Vector3:
				mi.scale = s
		elif not cfg.has("file"): # Only apply mod to procedural
			mi.scale = Vector3.ONE * cfg.get("procedural_scale_mod", 1.0)
		
		if is_off_hand:
			mi.position        = cfg.get("position", Vector3(-0.06, 0.05, 0.0))
			mi.rotation_degrees = cfg.get("rotation", Vector3(43.0, 23.0, 85.0))
		else:
			mi.position        = cfg.get("position", Vector3(0.0, 0.0, 0.0))
			mi.rotation_degrees = cfg.get("rotation", Vector3(-90.0, -90.0, 0.0))
		
		return mi

	return null


static func _find_node_by_name(node: Node, target: String) -> Node:
	if target == "": return null
	
	# Split target into keywords (e.g. "Baked Sword" -> ["baked", "sword"])
	var keywords = []
	for word in target.to_lower().split(" ", false):
		var clean_word = _super_clean(word)
		if clean_word != "": keywords.append(clean_word)
	
	if keywords.size() == 0: return null
	
	var n_clean = _super_clean(node.name)
	
	# Check if ALL keywords are in the node name
	var all_match = true
	for kw in keywords:
		if not kw in n_clean:
			all_match = false
			break
			
	if all_match:
		return node
		
	for child in node.get_children():
		var found = _find_node_by_name(child, target)
		if found: return found
	return null

static func _super_clean(s: String) -> String:
	# Removes EVERYTHING except letters - internal helper
	var regex = RegEx.new()
	regex.compile("[^a-zA-Z0-9]")
	return regex.sub(s.to_lower(), "", true)

static func _find_mesh_recursive(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found = _find_mesh_recursive(child)
		if found:
			return found
	return null


## Heroic pose refinement — small bone adjustments to make the stance look professional.
static func _apply_heroic_pose(skeleton: Skeleton3D) -> void:
	if not skeleton: return
	
	# Rotate the Right Hand (Wrist) to make the sword grip look more natural
	var rh_idx = skeleton.find_bone("mixamorig_RightHand")
	if rh_idx == -1: rh_idx = skeleton.find_bone("RightHand")
	if rh_idx != -1:
		# Rotating on the local X axis of the wrist to tilt the fist slightly up/down
		# A negative tilt pulls the fist 'up' relative to the forearm.
		var quat = Quaternion(Vector3(1, 0, 0), deg_to_rad(-45))
		skeleton.set_bone_pose_rotation(rh_idx, quat)

	# Optional: Slight rotation for the shield hand for better framing
	var lh_idx = skeleton.find_bone("mixamorig_LeftHand")
	if lh_idx == -1: lh_idx = skeleton.find_bone("LeftHand")
	if lh_idx != -1:
		var quat = Quaternion(Vector3(1, 0, 0), deg_to_rad(-15))
		skeleton.set_bone_pose_rotation(lh_idx, quat)

## Debug helper — list all node names in a scene.
static func _list_node_names(node: Node, depth: int = 0) -> Array:
	var names: Array = [" ".repeat(depth * 2) + node.name]
	for child in node.get_children():
		names.append_array(_list_node_names(child, depth + 1))
	return names
