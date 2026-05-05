## WeaponBuilder.gd
## Static utility for procedural weapon construction using primitive meshes.
class_name WeaponBuilder

## Shared materials
static func create_metal_material(color: Color = Color(0.7, 0.7, 0.75)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 1.0
	mat.roughness = 0.25
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat

static func create_wood_material(color: Color = Color(0.35, 0.22, 0.12)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat

static func create_gem_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.8)
	mat.metallic = 0.2
	mat.roughness = 0.05
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

static func create_leather_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat

static func create_cloth_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat

## Generic Mesh Helpers
static func add_box(parent: Node3D, size: Vector3, offset: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = offset
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi

static func add_cylinder(parent: Node3D, r: float, h: float, offset: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 24
	mi.mesh = cm
	mi.position = offset
	mi.rotation_degrees = rot
	mi.material_override = mat
	_apply_smooth_normals(mi)
	parent.add_child(mi)
	return mi

static func add_sphere(parent: Node3D, r: float, offset: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	mi.position = offset
	mi.material_override = mat
	_apply_smooth_normals(mi)
	parent.add_child(mi)
	return mi

## Entry point for building any weapon
static func build_weapon(type: String, parent: Node3D, config: Dictionary = {}) -> MeshInstance3D:
	var root := Node3D.new()
	root.name = "Weapon_" + type.capitalize()
	parent.add_child(root)
	
	var mi: MeshInstance3D = null
	
	match type.to_lower():
		"sword":
			var script = load("res://scripts/weapons/Sword.gd")
			mi = script.new().build(root, config)
		"shield":
			var script = load("res://scripts/weapons/Shield.gd")
			mi = script.new().build(root, config)
		"mace":
			var script = load("res://scripts/weapons/Mace.gd")
			mi = script.new().build(root, config)
		"staff":
			var script = load("res://scripts/weapons/Staff.gd")
			mi = script.new().build(root, config)
		"dagger":
			var script = load("res://scripts/weapons/Dagger.gd")
			mi = script.new().build(root, config)
		"bow":
			var script = load("res://scripts/weapons/Bow.gd")
			mi = script.new().build(root, config)
		"book":
			var script = load("res://scripts/weapons/Book.gd")
			mi = script.new().build(root, config)
		_:
			push_warning("[WeaponBuilder] Unknown weapon type: " + type)
			root.queue_free()
			return null
			
	return mi

## Robust helper for loading a specific mesh from a GLB scene
static func load_mesh_from_glb(parent: Node3D, file_path: String, target_node: String) -> MeshInstance3D:
	if file_path == "" or not ResourceLoader.exists(file_path): return null
	var packed = load(file_path)
	if not packed: return null
	var scene = packed.instantiate()
	if not scene: return null
	
	# Priority 1: Search for "Baked" version
	var found = _find_node_fuzzy(scene, "Baked " + target_node)
	if not found: found = _find_node_fuzzy(scene, target_node)
	
	if not found:
		scene.queue_free()
		return null
		
	var mi: MeshInstance3D = null
	if found is MeshInstance3D:
		mi = found.duplicate()
	else:
		# Extract the FIRST mesh child to avoid armature scale issues
		var meshes = found.find_children("*", "MeshInstance3D", true)
		if meshes.size() > 0:
			mi = meshes[0].duplicate()
			print("[WeaponBuilder] Extracted mesh node: ", mi.name)
	
	scene.queue_free()
	
	if mi:
		_attempt_material_fix(mi, target_node)
		parent.add_child(mi)
		mi.visible = true
	return mi

static func _find_node_fuzzy(node: Node, target: String) -> Node:
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
		var found = _find_node_fuzzy(child, target)
		if found: return found
	return null

static func _super_clean(s: String) -> String:
	# Removes EVERYTHING except letters - internal helper
	var regex = RegEx.new()
	regex.compile("[^a-zA-Z]")
	return regex.sub(s.to_lower(), "", true)

static func _attempt_material_fix(mi: MeshInstance3D, target_node: String) -> void:
	var mesh = mi.mesh
	if not mesh: return
	
	var textures_dir = "res://assets/equipment/textures/"
	var dir = DirAccess.open(textures_dir)
	var all_textures = []
	if dir:
		for f in dir.get_files():
			var f_clean = f.replace(".import", "")
			if f_clean.ends_with(".png") and not all_textures.has(f_clean):
				all_textures.append(f_clean)
	
	for i in range(mesh.get_surface_count()):
		var mat = mi.get_surface_override_material(i)
		if not mat: mat = mesh.surface_get_material(i)
		
		if mat is StandardMaterial3D and not mat.albedo_texture:
			var mat_name = mat.resource_name.to_lower()
			var weapon_name = target_node.to_lower()
			
			for tex_file in all_textures:
				var tf_low = tex_file.to_lower()
				if (weapon_name != "" and weapon_name in tf_low) or (mat_name != "" and mat_name in tf_low):
					var new_tex = load(textures_dir + tex_file)
					if new_tex:
						var new_mat = mat.duplicate()
						new_mat.albedo_texture = new_tex
						mi.set_surface_override_material(i, new_mat)
						print("[WeaponBuilder] Re-linked texture: ", tex_file)
						break

static func _apply_smooth_normals(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	if not mesh: return
	var st := SurfaceTool.new()
	var new_arr_mesh := ArrayMesh.new()
	for surf_idx in range(mesh.get_surface_count()):
		st.create_from(mesh, surf_idx)
		st.generate_normals(false)
		st.generate_tangents()
		var mat = mesh.surface_get_material(surf_idx)
		st.commit(new_arr_mesh)
		if mat: new_arr_mesh.surface_set_material(surf_idx, mat)
	mi.mesh = new_arr_mesh
