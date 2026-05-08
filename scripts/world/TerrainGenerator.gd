extends Node3D
class_name TerrainGenerator

## TerrainGenerator.gd
## Natural terrain with height-based coloring and detail textures.

@export var size_x: int = 400
@export var size_z: int = 400
@export var subdivision: float = 2.0
@export var height_scale: float = 70.0
@export var noise_seed: int = 42

@export_category("Colors")
@export var color_deep_water: Color    = Color(0.06, 0.22, 0.52)
@export var color_sand: Color   = Color(0.82, 0.74, 0.50)
@export var color_grass: Color  = Color(0.20, 0.48, 0.15)
@export var color_dirt: Color   = Color(0.36, 0.27, 0.16)
@export var color_rock: Color   = Color(0.46, 0.44, 0.40)
@export var color_snow: Color   = Color(0.88, 0.90, 0.94)

@export_category("Water")
@export var water_level: float = 0.0

var noise: FastNoiseLite
signal terrain_ready

func _ready() -> void:
	if Engine.is_editor_hint(): return
	add_to_group("terrain")
	if noise_seed == 0: noise_seed = randi()
	_generate_terrain()
	# Ensure late-joining players also get snapped
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node.is_in_group("player"):
		# Wait one frame for the node to be fully initialized and positioned
		await get_tree().process_frame
		if has_node("TerrainCollision"):
			_snap_entities()


func _generate_terrain() -> void:
	noise = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.006
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	
	for c in get_children(): c.queue_free()
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var cols = int(size_x / subdivision) + 1
	var rows = int(size_z / subdivision) + 1
	var half_x = size_x * 0.5
	var half_z = size_z * 0.5
	
	# Pass 1: Vertices
	for z in range(rows):
		for x in range(cols):
			var px = -half_x + x * subdivision
			var pz = -half_z + z * subdivision
			var h = _get_h(px, pz)
			
			st.set_uv(Vector2(float(x)/cols, float(z)/rows))
			st.set_color(_get_color_for_height(h))
			st.add_vertex(Vector3(px, h, pz))
			
	# Pass 2: Indices
	for r in range(rows - 1):
		for c in range(cols - 1):
			var i = r * cols + c
			st.add_index(i); st.add_index(i + 1); st.add_index(i + cols)
			st.add_index(i + 1); st.add_index(i + cols + 1); st.add_index(i + cols)
			
	st.generate_normals()
	st.generate_tangents()
	var mesh = st.commit()
	
	# Visual Mesh
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	
	# Detail texture
	if ResourceLoader.exists("res://assets/textures/ground.png"):
		var tex = load("res://assets/textures/ground.png")
		if tex:
			mat.albedo_texture = tex
			mat.uv1_triplanar = true
			mat.uv1_scale = Vector3(0.05, 0.05, 0.05)
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		else:
			# Fallback color if texture exists but fails to load
			mat.albedo_color = Color(0.3, 0.25, 0.2)
			print("[TerrainGenerator] WARNING: Failed to load res://assets/textures/ground.png even though it exists.")
	else:
		# Fallback color if texture missing
		mat.albedo_color = Color(0.3, 0.25, 0.2)
		print("[TerrainGenerator] WARNING: res://assets/textures/ground.png not found.")
	
	mi.material_override = mat
	add_child(mi)
	
	# Collision
	var sb = StaticBody3D.new()
	sb.name = "TerrainCollision"
	var cs = CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	sb.add_child(cs)
	add_child(sb)
	
	# Water
	_create_water()
	

	# Generate 2D Map Texture for HUD
	_generate_map_texture()


func _generate_map_texture() -> void:
	var img_size = 256 # Small texture for minimap
	var img = Image.create(img_size, img_size, false, Image.FORMAT_RGBA8)
	
	print("[TerrainGenerator] Starting map texture generation...")
	var half_s = img_size / 2.0
	var world_to_img = float(img_size) / size_x
	
	for y in range(img_size):
		for x in range(img_size):
			var wx = (x - half_s) / world_to_img
			var wz = (y - half_s) / world_to_img
			var h = _get_h(wx, wz)
			var col = _get_color_for_height(h)
			# Add a subtle water color if below water level
			if h < water_level:
				col = color_deep_water.lerp(Color.BLACK, 0.2)
			img.set_pixel(x, y, col)
	
	var tex = ImageTexture.create_from_image(img)
	get_tree().set_meta("terrain_map_texture", tex)
	get_tree().set_meta("terrain_map_size", Vector2(size_x, size_z))
	print("[TerrainGenerator] Texture generated and metadata set.")
	
	# Delay to ensure all collision shapes are settled
	await get_tree().process_frame
	_snap_entities()
	
	terrain_ready.emit()
	print("[TerrainGenerator] Generation complete. terrain_ready emitted.")

func _create_water() -> void:
	var w = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(size_x, size_z)
	w.mesh = pm
	w.position.y = water_level
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.4, 0.8, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.metallic = 0.1
	mat.roughness = 0.2
	w.material_override = mat
	add_child(w)

func _get_h(x: float, z: float) -> float:
	# CURRENT MAP SIZE: 400x400 units
	var d = Vector2(x, z).length()
	var max_d = size_x * 0.48
	
	# The falloff creates the "Island" shape by pushing edges to 0 height.
	# We use a steeper edge falloff to allow more room for varied terrain in the center.
	var falloff = 1.0 - smoothstep(max_d * 0.7, max_d, d)
	
	# Base height + Noise-driven hills
	var base_h  = height_scale * 0.15 * falloff
	
	# Noise 1: Main landforms
	var noise_val = noise.get_noise_2d(x, z)
	var noise_h = (noise_val + 1.0) * 0.5 * height_scale * 0.85 * falloff
	
	# Noise 2: Create lakes/rivers by carving out basins
	# We use a deeper carve threshold to ensure it reaches the water_level
	var lake_carve = 0.0
	if noise_val < 0.1:
		# Carve deeper where noise is already low
		lake_carve = abs(noise_val - 0.1) * height_scale * 0.7 * falloff
	
	return base_h + noise_h - lake_carve

func _get_color_for_height(h: float) -> Color:
	# Majority of the map should be grass (Earth-like)
	var p = h / height_scale
	if h < water_level + 1.5: return color_sand
	if p < 0.75: return color_grass
	if p < 0.85: return color_dirt
	if p < 0.92: return color_rock
	return color_snow

func _snap_entities() -> void:
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.is_multiplayer_authority():
			var h = _get_h(p.global_position.x, p.global_position.z)
			if p.has_method("teleport_to"):
				p.teleport_to(Vector3(p.global_position.x, h + 0.2, p.global_position.z), 0.0)
			else:
				p.global_position.y = h + 0.2
	
	# Snap all enemies and markers in the scene
	var enemies = get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		var h = _get_h(e.global_position.x, e.global_position.z)
		e.global_position.y = max(h, water_level) + 0.2
		if "home_position" in e:
			e.home_position = e.global_position

	var spawns = get_tree().get_nodes_in_group("enemy_spawn")
	for s in spawns:
		s.global_position.y = max(_get_h(s.global_position.x, s.global_position.z), water_level)

	var npc_group = get_tree().get_nodes_in_group("npc") # Assume NPCs might be in a group
	for n in npc_group:
		n.global_position.y = max(_get_h(n.global_position.x, n.global_position.z), water_level)

func get_height_at(x: float, z: float) -> float:
	return _get_h(x, z)

func get_safe_spawn_near(x: float, z: float, _r: float = 0.0) -> Vector3:
	return Vector3(x, _get_h(x, z) + 0.2, z)
