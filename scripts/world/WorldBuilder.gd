## WorldBuilder.gd
## Attached to the World scene. Procedurally builds all outdoor level geometry:
## starting camp, graveyard, ruined castle area, forest path, and enemy spawns.
extends Node3D

@export var enemy_scene: PackedScene

# ─── Materials ──────────────────────────────────────────────────────────────
var mat_stone  : StandardMaterial3D
var mat_dirt   : StandardMaterial3D
var mat_wood   : StandardMaterial3D
var mat_dark   : StandardMaterial3D
var mat_grave  : StandardMaterial3D

func _ready() -> void:
	_build_materials()
	_build_camp()
	_build_graveyard()
	_build_ruins()
	_build_forest_path()
	_build_extra_enemies()
	_spawn_collectables()
	_spawn_npcs()

# ─── Materials ───────────────────────────────────────────────────────────────
func _build_materials() -> void:
	mat_stone = _mat(Color(0.28, 0.26, 0.27), 0.8)
	mat_dirt  = _mat(Color(0.38, 0.28, 0.18), 0.9)
	mat_wood  = _mat(Color(0.35, 0.22, 0.10), 0.85)
	mat_dark  = _mat(Color(0.12, 0.1, 0.13), 0.9)
	mat_grave = _mat(Color(0.3, 0.28, 0.32), 0.85)

func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.uv1_triplanar = true # Vital for procedural textures on boxes
	
	# Create procedural noise texture for "grit" and surface detail
	var nt = NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	nt.noise = noise
	
	m.albedo_texture = nt
	return m

# ─── CAMP AREA (near spawn, ~Z 0 to -12) ─────────────────────────────────────
func _build_camp() -> void:
	# Campfire glow — orange OmniLight at centre
	_light(Vector3(0, 0.5, -6), Color(1.0, 0.45, 0.1), 4.0, 12.0)

	# Campfire log pile (small box cross)
	_box(Vector3(0, 0.15, -6), Vector3(1.8, 0.25, 0.35), mat_wood)
	_box(Vector3(0, 0.15, -6), Vector3(0.35, 0.25, 1.8), mat_wood)

	# Ember glow mesh
	var ember = MeshInstance3D.new()
	var sp = SphereMesh.new(); sp.radius = 0.25
	ember.mesh = sp
	var em = StandardMaterial3D.new()
	em.albedo_color = Color(1.0, 0.3, 0.0)
	em.emission_enabled = true; em.emission = Color(1.0, 0.3, 0.0)
	em.emission_energy_multiplier = 6.0
	ember.material_override = em
	ember.position = Vector3(0, 0.3, -6)
	add_child(ember)

	# Tent-like shelter — slanted roof using wedge of boxes
	_box(Vector3(-5, 1.5, -5), Vector3(4.0, 0.25, 4.0), mat_wood)    # roof slab
	_box(Vector3(-5, 0.75, -3), Vector3(4.0, 1.5, 0.3), mat_wood)    # front wall
	_box(Vector3(-5, 0.75, -7), Vector3(4.0, 1.5, 0.3), mat_wood)    # back wall
	_box(Vector3(-7, 0.75, -5), Vector3(0.3, 1.5, 4.0), mat_wood)    # side wall

	# Supply crates
	_box(Vector3( 3, 0.4, -4), Vector3(1.0, 0.8, 1.0), mat_wood)
	_box(Vector3( 4.2, 0.4, -4), Vector3(1.0, 0.8, 1.0), mat_wood)
	_box(Vector3( 3.6, 1.2, -4), Vector3(1.0, 0.8, 1.0), mat_wood)

	# Four perimeter torches around camp
	for pos in [Vector3(6, 2, -2), Vector3(6, 2, -10), Vector3(-8, 2, -2), Vector3(-8, 2, -10)]:
		_light(pos, Color(1.0, 0.6, 0.15), 2.5, 10.0)
		_box(pos - Vector3(0, 0.8, 0), Vector3(0.15, 1.2, 0.15), mat_wood)

	# Fence posts around camp perimeter
	for x in [-9, -7, -5, -3, 3, 5, 7, 9]:
		_box(Vector3(x, 0.6, -1),  Vector3(0.2, 1.2, 0.2), mat_wood)
		_box(Vector3(x, 0.6, -11), Vector3(0.2, 1.2, 0.2), mat_wood)
	for z in [-2, -4, -6, -8, -10]:
		_box(Vector3(-9, 0.6, z), Vector3(0.2, 1.2, 0.2), mat_wood)
		_box(Vector3( 9, 0.6, z), Vector3(0.2, 1.2, 0.2), mat_wood)

# ─── GRAVEYARD (left side, ~X -15 to -5, Z -10 to -30) ──────────────────────
func _build_graveyard() -> void:
	# Perimeter low wall
	_solid_box(Vector3(-17, 0.5, -20), Vector3(0.5, 1.0, 22.0), mat_stone, true)  # west
	_solid_box(Vector3(-6,  0.5, -20), Vector3(0.5, 1.0, 22.0), mat_stone, true)  # east
	_solid_box(Vector3(-11, 0.5, -9),  Vector3(11.0, 1.0, 0.5), mat_stone, true)  # south gate
	_solid_box(Vector3(-11, 0.5, -31), Vector3(11.0, 1.0, 0.5), mat_stone, true)  # north

	# Gate posts
	_solid_box(Vector3(-8.5, 1.5, -9), Vector3(0.6, 3.0, 0.6), mat_stone, true)
	_solid_box(Vector3(-13.5, 1.5, -9), Vector3(0.6, 3.0, 0.6), mat_stone, true)

	# Tombstones — 3 rows of 4
	var tombstone_positions: Array = []
	for row in range(3):
		for col in range(4):
			var tx = -16.0 + col * 3.2
			var tz = -13.0 - row * 5.5
			tombstone_positions.append(Vector3(tx, 0, tz))

	for tp in tombstone_positions:
		# Tombstone base
		_box(tp + Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 0.15), mat_grave)
		# Arched top cap
		_box(tp + Vector3(0, 1.3, 0), Vector3(0.55, 0.45, 0.15), mat_grave)

	# Overgrown dead trees in graveyard
	_dead_tree(Vector3(-9.5, 0, -14))
	_dead_tree(Vector3(-15, 0, -22))
	_dead_tree(Vector3(-8, 0, -27))

	# Graveyard lanterns
	_light(Vector3(-11, 2.5, -12), Color(0.5, 0.9, 0.4), 1.8, 9.0)
	_light(Vector3(-11, 2.5, -27), Color(0.5, 0.9, 0.4), 1.8, 9.0)

	# Graveyard enemies (3 skeletons)
	_spawn_enemy(Vector3(-11, 1, -16))
	_spawn_enemy(Vector3(-13, 1, -23))
	_spawn_enemy(Vector3(-9,  1, -26))

# ─── RUINED CASTLE AREA (right side ~X 10 to 30, Z -5 to -35) ───────────────
func _build_ruins() -> void:
	# Main ruined tower base (hollow square of thick walls)
	var cx = 20.0; var cz = -22.0
	var cw = 14.0; var cd = 14.0; var th = 1.2; var h = 7.0

	_solid_box(Vector3(cx, h*0.5, cz - cd*0.5), Vector3(cw, h, th), mat_stone, true)   # N wall
	_solid_box(Vector3(cx, h*0.5, cz + cd*0.5), Vector3(cw, h, th), mat_stone, true)   # S wall (broken gap)
	_solid_box(Vector3(cx - cw*0.5, h*0.5, cz), Vector3(th, h, cd), mat_stone, true)   # W wall
	_solid_box(Vector3(cx + cw*0.5, h*0.5, cz), Vector3(th, h, cd), mat_stone, true)   # E wall

	# Corner turrets
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var tp = Vector3(cx + sx*(cw*0.5), h*0.5+1.5, cz + sz*(cd*0.5))
			_solid_box(tp, Vector3(2.5, h+3.0, 2.5), mat_stone, true)

	# Collapsed rubble piles
	_box(Vector3(cx+2, 0.6, cz+4), Vector3(3.0, 1.2, 2.5), mat_stone)
	_box(Vector3(cx-3, 0.4, cz+2), Vector3(2.0, 0.8, 2.0), mat_stone)
	_box(Vector3(cx+4, 0.3, cz+1), Vector3(1.5, 0.6, 1.8), mat_stone)

	# Interior torch
	_light(Vector3(cx, 3, cz), Color(1.0, 0.5, 0.1), 3.0, 14.0)

	# Approach archway at castle front
	_solid_box(Vector3(cx-3.5, 3.5, cz + cd*0.5 + 6), Vector3(1.0, 7.0, 1.0), mat_stone, true)
	_solid_box(Vector3(cx+3.5, 3.5, cz + cd*0.5 + 6), Vector3(1.0, 7.0, 1.0), mat_stone, true)
	_box(Vector3(cx, 7.5, cz + cd*0.5 + 6), Vector3(9.0, 1.5, 1.0), mat_stone)

	# Scattered broken wall fragments nearby
	_box(Vector3(14, 1.5, -10), Vector3(6.0, 3.0, 0.8), mat_stone)
	_box(Vector3(28, 2.5, -30), Vector3(0.8, 5.0, 7.0), mat_stone)
	_box(Vector3(13, 1.0, -35), Vector3(5.0, 2.0, 0.8), mat_stone)

	# Enemies patrolling the ruins (4 skeletons)
	_spawn_enemy(Vector3(cx-3, 1, cz-2))
	_spawn_enemy(Vector3(cx+3, 1, cz+2))
	_spawn_enemy(Vector3(cx,   1, cz-5))
	_spawn_enemy(Vector3(23,   1, -10))

# ─── FOREST PATH (centre, from Z -12 to -38 leading to dungeon) ──────────────
func _build_forest_path() -> void:
	# Stone paving slabs down the centre path
	var z = -13.0
	while z > -38.0:
		_box(Vector3(0, 0.05, z), Vector3(3.5, 0.1, 2.0), mat_stone)
		z -= 3.0

	# Trees lining both sides of path
	var tz = -14.0
	while tz > -37.0:
		_dead_tree(Vector3(-5, 0, tz))
		_dead_tree(Vector3( 5, 0, tz))
		tz -= 6.0

	# Torch poles along the path every 6 units
	var lz = -14.0
	while lz > -36.0:
		_light(Vector3(-3.5, 2.8, lz), Color(1.0, 0.55, 0.15), 2.0, 9.0)
		_box(Vector3(-3.5, 1.3, lz), Vector3(0.18, 3.0, 0.18), mat_wood)
		_light(Vector3( 3.5, 2.8, lz), Color(1.0, 0.55, 0.15), 2.0, 9.0)
		_box(Vector3( 3.5, 1.3, lz), Vector3(0.18, 3.0, 0.18), mat_wood)
		lz -= 6.0

	# Two ambush skeletons hiding behind trees just before dungeon
	_spawn_enemy(Vector3(-6, 1, -33))
	_spawn_enemy(Vector3( 6, 1, -33))

# ─── EXTRA ENEMY SPAWNS scattered around the open world ──────────────────────
func _build_extra_enemies() -> void:
	for pos in [
		Vector3(15, 1, 5), Vector3(-18, 1, 5),
		Vector3(8,  1, 18), Vector3(-10, 1, 20),
		Vector3(22, 1, 15), Vector3(-22, 1, -5),
		Vector3(0, 1, 10), Vector3(35, 1, -15),
		Vector3(-35, 1, -25), Vector3(10, 1, -40),
		Vector3(-10, 1, -40), Vector3(0, 1, -50)
	]:
		_spawn_enemy(pos)

# ─── DEAD TREE helper ────────────────────────────────────────────────────────
func _dead_tree(pos: Vector3) -> void:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.1, 0.08)
	mat.roughness = 0.95
	# Trunk
	var trunk = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.12; cyl.bottom_radius = 0.22; cyl.height = 4.5
	trunk.mesh = cyl; trunk.material_override = mat
	trunk.position = pos + Vector3(0, 2.25, 0)
	trunk.rotation_degrees = Vector3(randf_range(-4, 4), randf_range(0, 360), randf_range(-3, 3))
	add_child(trunk)
	# Branch 1
	var br1 = MeshInstance3D.new()
	var bc1 = CylinderMesh.new()
	bc1.top_radius = 0.05; bc1.bottom_radius = 0.12; bc1.height = 2.0
	br1.mesh = bc1; br1.material_override = mat
	br1.position = pos + Vector3(0.8, 3.8, 0.3)
	br1.rotation_degrees = Vector3(50, 30, 20)
	add_child(br1)
	# Branch 2
	var br2 = MeshInstance3D.new()
	var bc2 = CylinderMesh.new()
	bc2.top_radius = 0.04; bc2.bottom_radius = 0.1; bc2.height = 1.6
	br2.mesh = bc2; br2.material_override = mat
	br2.position = pos + Vector3(-0.6, 3.3, -0.2)
	br2.rotation_degrees = Vector3(-55, -60, -15)
	add_child(br2)

# ─── HELPERS ─────────────────────────────────────────────────────────────────
func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = mat; mi.position = pos
	add_child(mi)

func _solid_box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, collidable: bool) -> void:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = mat; mi.position = pos
	if collidable:
		var sb = StaticBody3D.new()
		var cs = CollisionShape3D.new()
		var bs = BoxShape3D.new(); bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		mi.add_child(sb)
	add_child(mi)

func _light(pos: Vector3, color: Color, energy: float, range: float) -> void:
	var l = OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range
	l.position = pos
	add_child(l)

func _spawn_enemy(pos: Vector3) -> void:
	if not enemy_scene:
		return
	var e = enemy_scene.instantiate()
	add_child(e)
	e.global_position = pos

# ─── COLLECTABLES ──────────────────────────────────────────────────────────────────
var _collectable_script = preload("res://scripts/world/Collectable.gd")

func _spawn_collectables() -> void:
	# ―― Camp area ――
	_spawn_collectable(Vector3(2, 1.0, -3),    "health_potion",  1, Color(0.9, 0.15, 0.15))
	_spawn_collectable(Vector3(-3, 1.0, -4),   "campfire_kit",   1, Color(1.0, 0.5, 0.1))
	_spawn_collectable(Vector3(5, 1.0, -7),    "mana_crystal",   1, Color(0.3, 0.3, 0.9))
	_spawn_collectable(Vector3(2, 1.0, -9),    "herbs",          3, Color(0.2, 0.8, 0.3))
	# ―― Graveyard ――
	_spawn_collectable(Vector3(-12, 1.0, -15), "cracked_locket", 1, Color(0.8, 0.7, 0.2))
	_spawn_collectable(Vector3(-14, 1.0, -22), "dark_essence",   2, Color(0.5, 0.1, 0.7))
	_spawn_collectable(Vector3(-10, 1.0, -28), "health_potion",  2, Color(0.9, 0.15, 0.15))
	# ―― Ruins ――
	_spawn_collectable(Vector3(18, 1.0, -18),  "iron_ore",       3, Color(0.6, 0.6, 0.7))
	_spawn_collectable(Vector3(22, 1.0, -26),  "iron_sword",     1, Color(0.7, 0.7, 0.85))
	_spawn_collectable(Vector3(16, 1.0, -30),  "steel_helmet",   1, Color(0.55, 0.6, 0.7))
	# ―― Forest path ――
	_spawn_collectable(Vector3(-2, 1.0, -20),  "herbs",          2, Color(0.2, 0.8, 0.3))
	_spawn_collectable(Vector3(2, 1.0, -30),   "ruby_ring",      1, Color(0.9, 0.1, 0.1))

func _spawn_collectable(pos: Vector3, item_id: String, qty: int, color: Color) -> void:
	var node = Area3D.new()
	node.set_script(_collectable_script)
	add_child(node)
	node.global_position = pos + Vector3(0, 0.5, 0)
	node.item_id = item_id
	node.quantity = qty
	node.glow_color = color

# ─── NPCs ───────────────────────────────────────────────────────────────────────────
var _npc_script = preload("res://scripts/world/NPCDialogue.gd")

func _spawn_npcs() -> void:
	# ―― Camp: Villager Elder ――
	_spawn_npc(
		Vector3(-1.5, 0, -4), "Elder Maren", "villager",
		[
			"Welcome, stranger. These lands were peaceful once.",
			"The darkness crept from the eastern ruins. Our best warriors fell first.",
			"If you seek glory — or answers — the dungeon beneath the ruins holds both.",
			"Take care. And take a potion from our stores.",
			"..."
		],
		"find_the_darkness"
	)
	# ―― Camp: Merchant ――
	_spawn_npc(
		Vector3(4, 0, -5.5), "Trader Brix", "merchant",
		[
			"Looking to trade? My cart's seen better days, but my goods are sound.",
			"Herbs are scarce since the goblins moved in. I'll pay well for them.",
			"Check your pack — press I to open your inventory and see what you're carrying."
		],
		""
	)
	# ―― Camp: Scout ――
	_spawn_npc(
		Vector3(-4, 0, -8), "Scout Lyra", "villager",
		[
			"I've been mapping the graveyard. There are things moving in there at night.",
			"Press M to open the world map — I've marked what I could see.",
			"Watch your stamina if you run. Those legs won't last forever."
		],
		""
	)
	# ―― Ruins entrance: Guard ――
	_spawn_npc(
		Vector3(10, 0, -8), "Guard Theron", "guard",
		[
			"HALT. No civilians beyond this point.",
			"...you don't look like a civilian. Adventurer?",
			"The ruins are crawling with undead. We lost two men last week.",
			"Equip some armour before you head in. Press C for your character menu."
		],
		""
	)
	# ―― Graveyard: Sage ――
	_spawn_npc(
		Vector3(-11, 0, -20), "Sage Voss", "sage",
		[
			"The dead here are... restless. Not by accident.",
			"Something below the dungeon feeds on grief. A necromancer, perhaps... or worse.",
			"I have studied these grounds for a decade. The cracked locket — if you find one — is key.",
			"Bring it to me, and I will reveal what lies beneath."
		],
		""
	)

func _spawn_npc(pos: Vector3, name_str: String, type_str: String, lines: Array[String], quest_id: String) -> void:
	var npc = StaticBody3D.new()
	npc.set_script(_npc_script)
	add_child(npc)
	npc.global_position = pos
	npc.npc_name = name_str
	npc.npc_type = type_str
	npc.dialogue_lines.assign(lines)
	npc.quest_to_give = quest_id
