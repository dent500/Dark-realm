## MeatBuilder.gd
## Art-directed mannequin builder using BoneAttachment3D.
## Supports per-race body profiles with region-specific scaling and special features.
class_name MeatBuilder

const SKIP_BONES = [
	"Thumb", "Index", "Middle", "Ring", "Pinky",
	"Toe", "Eye", "Jaw", "HeadTop_End",
	"LeftHandEnd", "RightHandEnd", "LeftFootEnd", "RightFootEnd",
	"Reference", "Armature", "PreRotation", "Site"
]

const TARGET_CHILD: Dictionary = {
	"Hips":         "Spine",
	"Spine":        "Spine1",
	"Spine1":       "Spine2",
	"Spine2":       "Neck",
	"Neck":         "Head",
	"LeftShoulder": "LeftArm",
	"RightShoulder":"RightArm",
	"LeftArm":      "LeftForeArm",
	"RightArm":     "RightForeArm",
	"LeftForeArm":  "LeftHand",
	"RightForeArm": "RightHand",
	"LeftUpLeg":    "LeftLeg",
	"RightUpLeg":   "RightLeg",
	"LeftLeg":      "LeftFoot",
	"RightLeg":     "RightFoot",
}

static func build_meat(skeleton: Skeleton3D, config: Dictionary) -> Array:
	var segments: Array = []
	var muscle: float = config.get("muscle", 1.0)
	var gender: String = config.get("gender", "male")

	# Gender-based proportional scaling:
	# Narrower shoulders and reduced overall bulk for females of most races.
	# Elves are skipped as their baseline is already slender.
	var is_fem: bool   = (gender == "female")
	var race: String   = str(config.get("race", "")).to_lower()
	var fem_mod: float = 0.92 if (is_fem and race != "elf") else 1.0
	
	muscle *= fem_mod

	# Per-region overrides from race body_profile
	var head_s: float     = config.get("head_scale", 1.0)
	var torso_s: float    = config.get("torso_scale", 1.0) * fem_mod
	var shoulder_s: float = config.get("shoulder_scale", 1.0) * (0.90 if is_fem else 1.0) * fem_mod
	var leg_s: float      = config.get("leg_scale", 1.0) * fem_mod
	var forearm_s: float  = config.get("forearm_scale", 1.0) # forearm_scale already accounts for bulk
	var hand_s: float     = config.get("hand_scale", 1.0)
	var special: String   = config.get("special", "")

	for i in range(skeleton.get_bone_count()):
		var bone_name: String = skeleton.get_bone_name(i)
		var clean: String = bone_name.replace("mixamorig_", "").replace("mixamorig:", "")
		var b: String = clean.to_lower()

		var skip := false
		for s in SKIP_BONES:
			if clean.containsn(s):
				skip = true
				break
		if skip:
			continue

		var att := BoneAttachment3D.new()
		att.name = "Link_" + clean
		skeleton.add_child(att)
		att.bone_name = bone_name

		if b == "head":
			_add_head(att, head_s, muscle * head_s, special, gender, segments)
		elif b == "neck":
			# Neck: subtle taper (wider at base, narrow at head)
			_add_spanning_capsule(att, skeleton, i, 0.060 * muscle, segments, 0.06)
		elif b == "hips":
			# Pelvis: pulled in slightly for athletic taper (0.13 -> 0.118)
			_add_spanning_capsule(att, skeleton, i, 0.118 * muscle * torso_s, segments, 0.06)
		elif b == "spine":
			# Waist taper: narrower than hips/chest (0.095 -> 0.09)
			_add_spanning_capsule(att, skeleton, i, 0.090 * muscle * torso_s, segments, 0.04)
		elif b == "spine1":
			# Mid-chest: widest torso segment (0.125 -> 0.130)
			_add_spanning_capsule(att, skeleton, i, 0.130 * muscle * torso_s, segments, 0.06)
			_add_chest_definition(att, muscle, shoulder_s, gender, segments)
		elif b == "spine2":
			# Upper chest
			_add_spanning_capsule(att, skeleton, i, 0.115 * muscle * torso_s, segments, 0.04)
		elif "shoulder" in b:
			_add_spanning_capsule(att, skeleton, i, 0.05 * muscle * shoulder_s, segments, 0.05)
		elif b.ends_with("arm"):
			# Upper arm / bicep — boosted bulge for definition (0.22 -> 0.28)
			_add_spanning_capsule(att, skeleton, i, 0.068 * muscle * shoulder_s, segments, 0.28)
		elif "forearm" in b:
			_add_spanning_capsule(att, skeleton, i, 0.038 * muscle * forearm_s, segments, 0.10)
		elif "upleg" in b:
			# Quad — big muscle group (0.2 -> 0.26)
			_add_spanning_capsule(att, skeleton, i, 0.09 * muscle * leg_s, segments, 0.26)
		elif b.ends_with("leg"):
			# Calf — tapers (0.18 -> 0.22)
			_add_spanning_capsule(att, skeleton, i, 0.068 * muscle * leg_s, segments, 0.22)
		elif b.ends_with("hand"):
			_add_hand(att, muscle, hand_s, segments)
		elif b.ends_with("foot"):
			_add_foot(att, muscle, leg_s, segments)

	return segments

# ── Head builder — includes optional racial features ───────────────────────────

static func _add_head(att: Node3D, sc: float, mu: float,
		special: String, gender: String, segs: Array) -> void:
	# Cranium sphere — high-poly for a smooth silhouette
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12 * mu
	sm.height = 0.22 * sc
	sm.radial_segments = 48
	sm.rings = 32
	mi.mesh = sm
	mi.position = Vector3(0, 0.11 * sc, 0)
	_apply_smooth_normals(mi)
	att.add_child(mi)
	segs.append(mi)

	match special:
		"elf_ears":
			_add_elf_ears(att, 0.12 * mu, 0.11 * sc, segs)
		"brow_ridge":
			_add_brow_ridge(att, 0.12 * mu, 0.11 * sc, segs)
		"horns":
			_add_horns(att, 0.12 * mu, 0.11 * sc, segs)
		"beard":
			if gender != "female":  # Female dwarves don't have beards
				_add_beard(att, sc, segs)

static func _add_elf_ears(att: Node3D, head_r: float, head_y: float, segs: Array) -> void:
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = 0.030
		cm.top_radius    = 0.004
		cm.height        = 0.095
		cm.radial_segments = 20
		cm.rings = 4
		ear.mesh = cm
		ear.position = Vector3(side * head_r * 0.85, head_y, 0.0)
		ear.rotation = Vector3(0.0, 0.0, side * deg_to_rad(-20))
		_apply_smooth_normals(ear)
		att.add_child(ear)
		segs.append(ear)

static func _add_brow_ridge(att: Node3D, head_r: float, head_y: float, segs: Array) -> void:
	# A more subtle, curved brow ridge rather than a floating bar.
	var brow := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = head_r * 0.45
	sm.height = head_r * 0.15
	sm.radial_segments = 24
	sm.rings = 10
	brow.mesh = sm
	# Positioned at the forehead line, slightly forward.
	brow.position = Vector3(0.0, head_y + head_r * 0.35, head_r * 0.78)
	brow.scale = Vector3(1.5, 0.6, 0.4) # Flattened and widened
	_apply_smooth_normals(brow)
	att.add_child(brow)
	segs.append(brow)


static func _add_horns(att: Node3D, head_r: float, head_y: float, segs: Array) -> void:
	# Two curved capsule horns curving outward and upward
	for side in [-1.0, 1.0]:
		var horn := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.022
		cm.height = 0.18
		cm.radial_segments = 10
		cm.rings = 6
		horn.mesh = cm
		horn.position = Vector3(side * head_r * 0.65, head_y + head_r * 0.85, 0)
		horn.rotation = Vector3(deg_to_rad(15), 0, side * deg_to_rad(30))
		att.add_child(horn)
		segs.append(horn)

static func _add_beard(att: Node3D, sc: float, segs: Array) -> void:
	# Tapered cylinder: wide at the jaw, narrowing to a rounded tip — classic dwarf beard.
	# Anchored so its top face sits at the chin (local y≈0 on the head attachment).
	var beard := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius    = 0.070 * sc   # Flush against jaw width
	cm.bottom_radius = 0.025 * sc   # Tapers to a point
	cm.height        = 0.18 * sc
	cm.radial_segments = 20
	cm.rings = 6
	beard.mesh = cm
	# Anchor top-face at chin (y=0), push forward so it clears the neck capsule,
	# and tilt slightly so it hangs away from the face naturally
	beard.position = Vector3(0.0, -(cm.height * 0.28), 0.07 * sc)
	beard.rotation_degrees = Vector3(-15.0, 0.0, 0.0)
	_apply_smooth_normals(beard)
	att.add_child(beard)
	segs.append(beard)



## Chest definition — breast hemispheres. Used by both meat and clothing builders.
static func _add_chest_definition(att: Node3D, muscle: float, shoulder_s: float,
		gender: String, segs: Array, mat: Material = null) -> void:
	if gender != "female":
		return
	for side in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		# Rounded breast — upper chest, forward-facing.
		# When called from clothing (mat provided), add a small offset so the
		# clothing layer sits outside the skin layer, exactly like capsule zones.
		# Realistic proportions — radius reduced from 0.088 to 0.075 to balance
		# volume and frame integration.
		var r: float = 0.075 * muscle
		if mat:
			r += 0.012
		sm.radius = r
		sm.height = r * 1.8
		sm.radial_segments = 32
		sm.rings = 16
		mi.mesh = sm
		if mat:
			mi.material_override = mat
		# Raised position (Y = 0.165) and pulled slightly closer (X offset 0.044)
		# to sit naturally on the upper chest.
		mi.position = Vector3(side * 0.044 * shoulder_s,
							  0.165 * muscle,
							  0.13 * muscle)
		mi.scale = Vector3(1.0, 0.85, 0.85)
		_apply_smooth_normals(mi)
		att.add_child(mi)
		segs.append(mi)


## Organic hand — Reworked into a 'fist' shape for better weapon gripping.
static func _add_hand(att: Node3D, muscle: float, hand_s: float, segs: Array) -> void:
	# 1. Palm Core — Slightly more compact the fist
	var palm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.065 * muscle * hand_s, 0.045 * hand_s, 0.05 * hand_s)
	palm.mesh = bm
	palm.position = Vector3(0, 0, -0.01 * hand_s)
	att.add_child(palm)
	segs.append(palm)
	
	# 2. Clenched Fingers — Using a cylinder to simulate tightly wrapped fingers
	var fingers := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.038 * muscle * hand_s
	fm.bottom_radius = 0.038 * muscle * hand_s
	fm.height = 0.085 * muscle * hand_s
	fm.radial_segments = 24
	fingers.mesh = fm
	# Rotate so it's a horizontal grip mass
	fingers.rotation_degrees = Vector3(0, 0, 90)
	fingers.position = Vector3(0, 0.01, 0.035 * hand_s)
	fingers.scale = Vector3(1.0, 1.1, 0.8) # Flattened slightly towards palm
	_apply_smooth_normals(fingers)
	att.add_child(fingers)
	segs.append(fingers)
	
	# 3. Knuckle Top — A soft cap for the clenched grip
	var knuckles := MeshInstance3D.new()
	knuckles.mesh = SphereMesh.new()
	knuckles.mesh.radius = 0.035 * muscle * hand_s
	knuckles.mesh.height = 0.045 * muscle * hand_s
	knuckles.position = Vector3(0, 0.018, 0.025 * hand_s)
	knuckles.scale = Vector3(1.1, 0.5, 1.1)
	_apply_smooth_normals(knuckles)
	att.add_child(knuckles)
	segs.append(knuckles)

	# 4. Wrap-around Thumb — More 'heroic' placement
	var side_sign: float = 1.0 if "Right" in att.name else -1.0
	var thumb := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.019 * muscle * hand_s
	tm.height = 0.065 * hand_s
	thumb.mesh = tm
	# Positioned to wrap over the finger cylinder
	thumb.position = Vector3(side_sign * 0.042 * muscle * hand_s, 0.01, 0.04 * hand_s)
	thumb.rotation_degrees = Vector3(-30, side_sign * 90, 0)
	_apply_smooth_normals(thumb)
	att.add_child(thumb)
	segs.append(thumb)

## Organic wedge foot.
static func _add_foot(att: Node3D, muscle: float, leg_s: float, segs: Array) -> void:
	# Heel sphere
	var heel := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.038 * muscle * leg_s
	sm.height = 0.07 * muscle * leg_s
	sm.radial_segments = 28
	sm.rings = 18
	heel.mesh = sm
	# Heel/Midfoot: flattened oval
	# Heel Sphere
	heel.position = Vector3(0, -0.012, 0.0)
	heel.scale = Vector3(1.0, 1.0, 1.0)
	_apply_smooth_normals(heel)
	att.add_child(heel)
	segs.append(heel)
	
	# Sole/Toe Oval
	var toes := MeshInstance3D.new()
	var tsm := SphereMesh.new()
	tsm.radius = 0.038 * muscle * leg_s
	tsm.height = 0.07 * muscle * leg_s
	toes.mesh = tsm
	toes.position = Vector3(0, -0.015, 0.05)
	toes.scale = Vector3(1.1, 0.5, 2.1)
	_apply_smooth_normals(toes)
	att.add_child(toes)
	segs.append(toes)

# ── Core spanning helpers ──────────────────────────────────────────────────────

## Builds a bone-spanning capsule and sculpts it with a muscle bulge at its belly.
## bulge=0.0 → perfect cylinder; bulge=0.22 → bicep-level definition.
static func _add_spanning_capsule(att: Node3D, skeleton: Skeleton3D,
		bone_idx: int, radius: float, segs: Array, bulge: float = 0.0) -> void:
	var parent_idx := skeleton.get_bone_parent(bone_idx)
	var clean := skeleton.get_bone_name(bone_idx).replace("mixamorig_", "").replace("mixamorig:", "")

	# Determine the target child using the map
	var local_vec := Vector3(0, 0.12, 0)
	if clean in TARGET_CHILD:
		var tgt_clean: String = TARGET_CHILD[clean]
		var tgt_idx: int = skeleton.find_bone("mixamorig_" + tgt_clean)
		if tgt_idx == -1:
			tgt_idx = skeleton.find_bone(tgt_clean)
		if tgt_idx != -1:
			var my_gs := skeleton.get_bone_global_rest(bone_idx)
			var tgt_gs := skeleton.get_bone_global_rest(tgt_idx)
			var v := my_gs.affine_inverse() * tgt_gs.origin
			if v.length() > 0.01:
				local_vec = v
	elif parent_idx != -1:
		var my_gs := skeleton.get_bone_global_rest(bone_idx)
		var p_gs := skeleton.get_bone_global_rest(parent_idx)
		var v := my_gs.affine_inverse() * p_gs.origin
		if v.length() > 0.01:
			local_vec = v

	var length := local_vec.length()
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = max(length, radius * 2.5)
	cm.radial_segments = 36
	cm.rings = 16
	mi.mesh = cm
	# Sculpt muscle before smoothing — sculpt reads/writes raw geometry
	_sculpt_muscle_bulge(mi, bulge)  # also calls _apply_smooth_normals internally

	# Joint sphere at pivot — slightly oversized so capsule seams blend away
	_add_sphere(att, radius * 1.05, Vector3.ZERO, segs)

	# Rotate capsule Y-axis along local_vec
	var y_target: Vector3 = local_vec.normalized()
	var dot: float = clamp(Vector3.UP.dot(y_target), -1.0, 1.0)
	if dot < -0.9999:
		mi.transform.basis = Basis(Vector3.RIGHT, PI)
	elif dot < 0.9999:
		var axis: Vector3 = Vector3.UP.cross(y_target).normalized()
		if axis.length_squared() > 0.0001:
			mi.transform.basis = Basis(axis, acos(dot))

	mi.position = local_vec * 0.5
	att.add_child(mi)
	segs.append(mi)

static func _add_sphere(att: Node3D, radius: float, offset: Vector3, segs: Array) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 36
	sm.rings = 20
	mi.mesh = sm
	mi.position = offset
	_apply_smooth_normals(mi)
	att.add_child(mi)
	segs.append(mi)

static func _add_box(att: Node3D, size: Vector3, offset: Vector3, segs: Array) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = offset
	att.add_child(mi)
	segs.append(mi)

## Deforms capsule vertices radially at the belly (mid-section) to simulate
## muscle mass. bulge=0 → no change; bulge=0.22 → pronounced bicep/calf bulge.
## After sculpting, smooth normals are regenerated so the surface stays rounded.
static func _sculpt_muscle_bulge(mi: MeshInstance3D, bulge: float) -> void:
	if bulge <= 0.001:
		_apply_smooth_normals(mi)
		return
	var src_mesh := mi.mesh
	if not src_mesh or src_mesh.get_surface_count() == 0:
		_apply_smooth_normals(mi)
		return

	# Step 1: Bake any PrimitiveMesh (CapsuleMesh) into a proper ArrayMesh.
	# SurfaceTool fills every slot correctly — unlike PrimitiveMesh.surface_get_arrays()
	# which leaves UV2 / bones / weights as null and breaks add_surface_from_arrays().
	var st := SurfaceTool.new()
	var arr_mesh := ArrayMesh.new()
	st.create_from(src_mesh, 0)
	st.commit(arr_mesh)

	# Step 2: MeshDataTool handles index buffers and format flags internally.
	var mdt := MeshDataTool.new()
	if mdt.create_from_surface(arr_mesh, 0) != OK:
		_apply_smooth_normals(mi)
		return

	# Find Y-extent to normalise along the capsule's long axis
	var max_y: float = 0.001
	for vi in range(mdt.get_vertex_count()):
		var y: float = abs(mdt.get_vertex(vi).y)
		if y > max_y:
			max_y = y

	# Expand XZ by a smooth bell-curve: max at belly, zero at end-caps
	for vi in range(mdt.get_vertex_count()):
		var v: Vector3 = mdt.get_vertex(vi)
		var t: float = abs(v.y) / max_y
		var e: float = pow(1.0 - t * t, 1.5)
		var s: float = 1.0 + bulge * e
		mdt.set_vertex(vi, Vector3(v.x * s, v.y, v.z * s))

	var new_mesh := ArrayMesh.new()
	mdt.commit_to_surface(new_mesh)
	mi.mesh = new_mesh
	_apply_smooth_normals(mi)

## Smooths normals on a MeshInstance3D so adjacent faces share tangents,
## giving capsules and spheres a perfectly round appearance at any segment count.
static func _apply_smooth_normals(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	if not mesh:
		return
	var st := SurfaceTool.new()
	var new_arr_mesh := ArrayMesh.new()
	for surf_idx in range(mesh.get_surface_count()):
		st.create_from(mesh, surf_idx)
		st.generate_normals(false)   # smooth normals — weighted by face area
		st.generate_tangents()
		var mat = mesh.surface_get_material(surf_idx)
		st.commit(new_arr_mesh)
		if mat:
			new_arr_mesh.surface_set_material(surf_idx, mat)
	mi.mesh = new_arr_mesh

## Skin-quality material with subsurface scattering, specular sheen,
## and a slight roughness variation for an organic, fleshed-out appearance.
static func create_flesh_material(skin_color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# ── Base colour ──────────────────────────────────────────────────────────
	mat.albedo_color = skin_color

	# ── Specular / roughness — skin is slightly shiny due to oils ───────────
	mat.roughness = 0.55
	mat.metallic = 0.0
	mat.metallic_specular = 0.3

	# ── Subsurface Scattering — light bleeds through thin skin ───────────────
	mat.subsurf_scatter_enabled = true
	mat.subsurf_scatter_strength = 0.25
	mat.subsurf_scatter_skin_mode = true  # Use the dedicated skin SSS model
	# Tint SSS slightly red/orange to simulate blood under skin
	mat.subsurf_scatter_transmittance_color = Color(skin_color.r * 1.1,
		skin_color.g * 0.6, skin_color.b * 0.5, 1.0).clamp()

	# ── Rim lighting — fresnel edge glow that pops the silhouette ────────────
	mat.rim_enabled = true
	mat.rim = 0.18                # Strength of the rim effect
	mat.rim_tint = 0.35           # 0 = white rim, 1 = albedo-tinted rim

	# ── Shading ──────────────────────────────────────────────────────────────
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat

# ─────────────────────────────────────────────────────────────────────────────
# CLOTHING
# ─────────────────────────────────────────────────────────────────────────────

## Builds a clothing layer over the skeleton using the class-driven preset.
## Each clothing zone gets a slightly-enlarged capsule in a fabric material.
## This is called after build_meat() so the skin is already in place.
static func build_clothing(skeleton: Skeleton3D, config: Dictionary) -> Array:
	var segs: Array = []
	var clothing_type: String = config.get("clothing_type", "none")
	if clothing_type == "none":
		return segs

	var gender: String = config.get("gender", "male")
	var race: String   = config.get("race", "").to_lower()
	var is_fem := gender == "female"
	var fem_mod: float = 0.92 if (is_fem and race != "elf") else 1.0

	var muscle: float     = config.get("muscle",         1.0) * fem_mod
	var torso_s: float    = config.get("torso_scale",    1.0) * fem_mod
	var shoulder_s: float = config.get("shoulder_scale", 1.0) * (0.90 if is_fem else 1.0) * fem_mod
	var leg_s: float      = config.get("leg_scale",      1.0) * fem_mod
	var forearm_s: float  = config.get("forearm_scale",    1.0)

	# Robes disabled for now as requested
	# if clothing_type == "robes":
	# 	var robe_color: Color = config.get("robe_color", Color(0.18, 0.14, 0.45))
	# 	return _build_robe(skeleton, config, muscle, torso_s, shoulder_s, leg_s, robe_color)

	# ── shirt_pants path ──────────────────────────────────────────────────────
	var top_color:    Color = config.get("shirt_color", Color(0.52, 0.40, 0.26))
	var bottom_color: Color = config.get("pants_color", Color(0.22, 0.16, 0.10))

	var top_mat:    StandardMaterial3D = create_cloth_material(top_color)
	var bottom_mat: StandardMaterial3D = create_cloth_material(bottom_color)
	var boot_mat:   StandardMaterial3D = create_leather_material(Color(0.16, 0.11, 0.07))

	# How far outside the skin the clothing sits
	const OFFSET: float = 0.015

	var zones: Dictionary = {
		"spine":          {"radius": 0.090 * muscle * torso_s    + OFFSET, "bulge": 0.04, "mat": top_mat},
		"spine1":         {"radius": 0.130 * muscle * torso_s    + OFFSET, "bulge": 0.06, "mat": top_mat},
		"spine2":         {"radius": 0.115 * muscle * torso_s    + OFFSET, "bulge": 0.04, "mat": top_mat},
		"leftshoulder":   {"radius": 0.050 * muscle * shoulder_s + OFFSET, "bulge": 0.05, "mat": top_mat},
		"rightshoulder":  {"radius": 0.050 * muscle * shoulder_s + OFFSET, "bulge": 0.05, "mat": top_mat},
		"leftarm":        {"radius": 0.068 * muscle * shoulder_s + OFFSET, "bulge": 0.28, "mat": top_mat},
		"rightarm":       {"radius": 0.068 * muscle * shoulder_s + OFFSET, "bulge": 0.28, "mat": top_mat},
		"leftforearm":    {"radius": 0.038 * muscle * forearm_s + OFFSET, "bulge": 0.10, "mat": top_mat},
		"rightforearm":   {"radius": 0.038 * muscle * forearm_s + OFFSET, "bulge": 0.10, "mat": top_mat},
		"hips":           {"radius": 0.118 * muscle * torso_s   + OFFSET, "bulge": 0.06, "mat": bottom_mat},
		"leftupleg":      {"radius": 0.090 * muscle * leg_s     + OFFSET, "bulge": 0.26, "mat": bottom_mat},
		"rightupleg":     {"radius": 0.090 * muscle * leg_s     + OFFSET, "bulge": 0.26, "mat": bottom_mat},
		"leftleg":        {"radius": 0.068 * muscle * leg_s     + OFFSET, "bulge": 0.22, "mat": bottom_mat},
		"rightleg":       {"radius": 0.068 * muscle * leg_s     + OFFSET, "bulge": 0.22, "mat": bottom_mat},
	}

	for bone_idx in range(skeleton.get_bone_count()):
		var bname: String = skeleton.get_bone_name(bone_idx)
		var clean: String = bname.to_lower()\
			.replace("mixamorig_", "").replace("mixamorig:", "").replace(" ", "")

		# Foot bone — add very-flat boot spheres that cover the skin foot
		# but are too squashed vertically to clip into the shin above.
		if clean in ["leftfoot", "rightfoot"]:
			# Mixamo foot bones often have a permanent downward tilt (high-heel stance).
			# To keep feet parallel to the ground, we attach the boot meshes to the shin instead.
			continue

		if not zones.has(clean):
			continue

		var zone: Dictionary = zones[clean]
		var radius: float = zone["radius"]
		var bulge: float = zone.get("bulge", 0.0)

		var att := BoneAttachment3D.new()
		att.bone_name = bname
		skeleton.add_child(att)

		var mi_arr: Array = []
		_add_spanning_capsule(att, skeleton, bone_idx, radius, mi_arr, bulge)
		for mi in mi_arr:
			if mi is MeshInstance3D:
				mi.material_override = zone["mat"]
		segs.append_array(mi_arr)

		# Leg skirts disabled for now as requested
		# if clean in ["leftupleg", "rightupleg"] and config.get("has_leg_skirt", false):
		# 	_add_leg_skirt(att, skeleton, bone_idx, muscle, torso_s, leg_s, top_mat, segs)

		# Shin boot cap — a wide flat sphere at the ankle end of the shin capsule.
		# Attaching to the shin (not the foot) means the boot cap never rotates
		# with the foot bone, so it can't clip into the shin during walking.
		if clean in ["leftleg", "rightleg"]:
			var tgt_clean: String = TARGET_CHILD.get("LeftLeg" if clean == "leftleg" else "RightLeg", "")
			var tgt_idx := skeleton.find_bone("mixamorig_" + tgt_clean)
			if tgt_idx == -1: tgt_idx = skeleton.find_bone(tgt_clean)
			if tgt_idx != -1:
				var my_gs := skeleton.get_bone_global_rest(bone_idx)
				var tgt_gs := skeleton.get_bone_global_rest(tgt_idx)
				var ankle_local: Vector3 = my_gs.affine_inverse() * tgt_gs.origin
				# Boot attached to the shin! This ignores Mixamo's "high heel" foot bone tilt
				# and keeps the foot safely parallel to the ground.
				
				# 1. Ankle joint cap
				_add_sphere(att, 0.06 * muscle * leg_s, ankle_local, segs)
				var ankle_cap := segs.back() as MeshInstance3D
				if ankle_cap:
					ankle_cap.material_override = boot_mat
					
				# 2. Main foot body (thick boot shape)
				var foot_body := MeshInstance3D.new()
				var fts := SphereMesh.new()
				fts.radius = 0.070 * muscle * leg_s
				fts.height = 0.120 * muscle * leg_s
				fts.radial_segments = 28
				fts.rings = 18
				foot_body.mesh = fts
				foot_body.material_override = boot_mat
				# Position it tightly against the ankle, shift forward and down
				foot_body.position = ankle_local + Vector3(0.0, -0.035, 0.050)
				# Increased Y scale (0.9) to make the boot much thicker/taller
				foot_body.scale = Vector3(1.2, 0.9, 2.1)
				# Tilt the toe down to flatten the sole against the floor
				foot_body.rotation_degrees = Vector3(-15.0, 0.0, 0.0)
				_apply_smooth_normals(foot_body)
				att.add_child(foot_body)
				segs.append(foot_body)

		# If this is Spine1 and we are building clothing, add the clothed breasts
		if clean == "spine1" and config.get("gender") == "female":
			_add_chest_definition(att, muscle, shoulder_s, "female", segs, zone["mat"])

	# ── Hide skin-layer feet to prevent "double feet" clipping ─────────
	# Nodes were created with lowercase 'clean' names: Link_leftfoot, Link_rightfoot
	for side in ["left", "right"]:
		var foot_link = skeleton.get_node_or_null("Link_" + side + "foot")
		if foot_link: foot_link.hide()

	return segs


## Internal helper: Adds leather foot geometry to a boot.
static func _add_leather_boot_foot(att: Node3D, muscle: float, leg_s: float, 
		mat: Material, segs: Array) -> void:
	# Leather Heel Sphere
	var heel := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.040 * muscle * leg_s
	sm.height = 0.07 * muscle * leg_s
	heel.mesh = sm
	heel.material_override = mat
	heel.position = Vector3(0, -0.012, 0.0)
	heel.scale = Vector3(1.0, 1.0, 1.0)
	_apply_smooth_normals(heel)
	att.add_child(heel)
	segs.append(heel)
	
	# Leather Sole/Ball Oval
	var toes := MeshInstance3D.new()
	var tsm := SphereMesh.new()
	tsm.radius = 0.040 * muscle * leg_s
	tsm.height = 0.07 * muscle * leg_s
	toes.mesh = tsm
	toes.material_override = mat
	toes.position = Vector3(0, -0.015, 0.05)
	toes.scale = Vector3(1.15, 0.5, 2.3)
	_apply_smooth_normals(toes)
	att.add_child(toes)
	segs.append(toes)


## Robe silhouette: fitted torso + wide sleeves, then a single flared skirt
## cylinder anchored at the Hips bone that drapes down over the legs.
static func _build_robe(skeleton: Skeleton3D, config: Dictionary,
		muscle: float, torso_s: float, shoulder_s: float, leg_s: float,
		robe_color: Color) -> Array:
	var segs: Array = []
	var mat: StandardMaterial3D = create_cloth_material(robe_color)
	var forearm_s: float = config.get("forearm_scale", 1.0)

	const OFFSET: float = 0.018  # Slightly more drape than normal clothes

	# Torso + sleeve bones covered by fitted capsules (same as shirt_pants).
	# Legs are intentionally OMITTED — the skirt covers them.
	var robe_zones: Dictionary = {
		"spine":         {"radius": 0.100 * muscle * torso_s    + OFFSET, "bulge": 0.02},
		"spine1":        {"radius": 0.140 * muscle * torso_s    + OFFSET, "bulge": 0.03},
		"spine2":        {"radius": 0.115 * muscle * torso_s    + OFFSET, "bulge": 0.02},
		"leftshoulder":  {"radius": 0.055 * muscle * shoulder_s + OFFSET, "bulge": 0.03},
		"rightshoulder": {"radius": 0.055 * muscle * shoulder_s + OFFSET, "bulge": 0.03},
		# Wide, flowing sleeves — larger radius than normal shirt arms
		"leftarm":       {"radius": 0.080 * muscle * shoulder_s + OFFSET, "bulge": 0.08},
		"rightarm":      {"radius": 0.080 * muscle * shoulder_s + OFFSET, "bulge": 0.08},
		"leftforearm":   {"radius": 0.055 * muscle * forearm_s + OFFSET, "bulge": 0.06},
		"rightforearm":  {"radius": 0.055 * muscle * forearm_s + OFFSET, "bulge": 0.06},
		"hips":          {"radius": 0.125 * muscle * torso_s   + OFFSET, "bulge": 0.04},
	}

	var hips_att: BoneAttachment3D = null  # will attach the skirt here

	for bone_idx in range(skeleton.get_bone_count()):
		var bname: String = skeleton.get_bone_name(bone_idx)
		var clean: String = bname.to_lower()\
			.replace("mixamorig_", "").replace("mixamorig:", "").replace(" ", "")

		if not robe_zones.has(clean):
			continue

		var zone: Dictionary = robe_zones[clean]
		var att := BoneAttachment3D.new()
		att.bone_name = bname
		skeleton.add_child(att)

		var mi_arr: Array = []
		_add_spanning_capsule(att, skeleton, bone_idx, zone["radius"], mi_arr, zone.get("bulge", 0.0))
		for mi in mi_arr:
			if mi is MeshInstance3D:
				mi.material_override = mat
		segs.append_array(mi_arr)

		if clean == "spine1" and config.get("gender") == "female":
			_add_chest_definition(att, muscle, shoulder_s, "female", segs, mat)

		if clean == "hips":
			hips_att = att

	# ── Skirt: floor-length cylinder anchored at Hips ────────────────────────
	# A floor-grazing hem is animation-safe: the rigid cone reaches the ground
	# regardless of how far the legs spread, so nothing looks out of place.
	if hips_att:
		_add_robe_skirt(hips_att, muscle, torso_s, leg_s, mat, segs)

	# ── Hide all leg/foot skin segments.
	# The hem rests at ground level, so no feet should be visible — a foot
	# poking out at an angle from a floor-length robe would look wrong.
	# The character is grounded by the skirt hem itself, not the feet.
	var leg_links := [
		"Link_LeftUpLeg",  "Link_RightUpLeg",
		"Link_LeftLeg",    "Link_RightLeg",
		"Link_LeftFoot",   "Link_RightFoot",
	]
	for link_name in leg_links:
		var node: Node = skeleton.get_node_or_null(link_name)
		if node:
			for child in node.get_children():
				if child is MeshInstance3D:
					child.visible = false

	return segs


## Generates the flowing skirt portion of the robe by building a wide, tapered
## cylinder that hangs from the Hips attachment point down past the knees.
static func _add_robe_skirt(att: Node3D, muscle: float, torso_s: float,
		leg_s: float, mat: StandardMaterial3D, segs: Array) -> void:
	# Dimensions:
	#   height ~= thigh + shin length ≈ 0.50 m for a standard rig
	#   top_radius: snug around the hips
	#   bottom_radius: flared hem — about 2× the top radius for a proper drape
	# Floor-dragging length: hips sit ~1.0 m above floor on a Mixamo rig.
	# 1.25 × leg_s gives generous overshoot so the hem scrapes the floor even
	# when the hips bob upward during the walk/run cycle.
	# The extra -0.06 downward bias ensures the hem is always below the floor
	# plane — the underground clipping is never visible, but floating never happens.
	var skirt_height: float = 1.25 * leg_s
	var top_r: float        = 0.155 * muscle * torso_s   # snug at the waist
	var bottom_r: float     = 0.215 * muscle * torso_s   # gentle flare at the hem

	var mi := MeshInstance3D.new()
	mi.name = "RobeSkirt"   # PlayerController finds this node to drive spring sway
	var cm := CylinderMesh.new()
	cm.top_radius       = top_r
	cm.bottom_radius    = bottom_r
	cm.height           = skirt_height
	cm.radial_segments  = 36
	cm.rings            = 8
	mi.mesh = cm
	mi.material_override = mat

	# Shift the cylinder so its top sits at the hips bone, then bias an extra
	# 0.06 m downward so the hem is guaranteed to intersect the floor plane.
	mi.position = Vector3(0.0, -(skirt_height * 0.5) - 0.06, 0.0)

	_apply_smooth_normals(mi)
	att.add_child(mi)
	segs.append(mi)

## Adds a skirt cylinder to the upper leg bone that points toward the foot.
## As the leg moves during animation, this attached cylinder will naturally swing and flow with it.
static func _add_leg_skirt(att: BoneAttachment3D, skeleton: Skeleton3D, bone_idx: int,
		muscle: float, torso_s: float, leg_s: float, mat: StandardMaterial3D, segs: Array) -> void:
	var bname: String = att.bone_name
	var clean: String = bname.to_lower().replace("mixamorig_", "").replace("mixamorig:", "")
	var is_left: bool = "left" in clean
	var foot_name: String = "LeftFoot" if is_left else "RightFoot"
	
	var foot_idx: int = skeleton.find_bone("mixamorig_" + foot_name)
	if foot_idx == -1: foot_idx = skeleton.find_bone(foot_name)
	
	var local_vec := Vector3(0, -0.8, 0)
	if foot_idx != -1:
		var my_gs := skeleton.get_bone_global_rest(bone_idx)
		var foot_gs := skeleton.get_bone_global_rest(foot_idx)
		local_vec = my_gs.affine_inverse() * foot_gs.origin
		
	var length := local_vec.length() * 1.15 # go slightly past foot
	
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius       = 0.150 * muscle * torso_s
	cm.bottom_radius    = 0.225 * muscle * torso_s
	cm.height           = length
	cm.radial_segments  = 24
	cm.rings            = 8
	mi.mesh = cm
	mi.material_override = mat
	
	# Align Y axis along local_vec
	var y_target: Vector3 = local_vec.normalized()
	var dot: float = clamp(Vector3.UP.dot(y_target), -1.0, 1.0)
	if dot < -0.9999:
		mi.transform.basis = Basis(Vector3.RIGHT, PI)
	elif dot < 0.9999:
		var axis: Vector3 = Vector3.UP.cross(y_target).normalized()
		if axis.length_squared() > 0.0001:
			mi.transform.basis = Basis(axis, acos(dot))
			
	mi.position = local_vec * 0.5
	
	_apply_smooth_normals(mi)
	att.add_child(mi)
	segs.append(mi)

## Matte woven fabric — high roughness, no metallic sheen.
static func create_cloth_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness    = 0.92
	mat.metallic     = 0.0
	mat.metallic_specular = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat

## Worn leather — slightly smoother, very faint specular highlight.
static func create_leather_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness    = 0.74
	mat.metallic     = 0.0
	mat.metallic_specular = 0.12
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat
