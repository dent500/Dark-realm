## DungeonGenerator.gd
## Builds a dungeon level either from a map-editor JSON (res://level_map.json)
## or, when that file is absent, by procedural generation.
## Emits map_loaded (same signature as MapLoader) so the HUD minimap works
## on floors 2+ just like it does on the entry floor.
extends Node3D

# ─── Signal (mirrors MapLoader so HUD can connect identically) ──────────────
signal map_loaded(map_data: Array, grid_size: int, cell_size: float, offset: Vector2)

# ─── Config ─────────────────────────────────────────────────────────────────
@export var room_count: int = 8
@export var min_room_w: float = 20.0
@export var max_room_w: float = 40.0
@export var min_room_d: float = 20.0
@export var max_room_d: float = 40.0
@export var wall_height: float = 5.0
@export var corridor_width: float = 3.0
@export var enemies_per_room: int = 3
@export var enemy_scene: PackedScene

## Path inside res:// where the exported map JSON lives.
## NOTE: This is intentionally NOT used by DungeonGenerator — MapLoader handles
## the JSON map for floor 1 (world.tscn). DungeonGenerator always procedurally
## generates floors 2+ so each floor is unique.
const MAP_JSON_PATH := "res://level_map.json"

# ─── Materials ──────────────────────────────────────────────────────────────
var mat_floor : StandardMaterial3D
var mat_wall  : StandardMaterial3D
var mat_ceil  : StandardMaterial3D

# ─── State ──────────────────────────────────────────────────────────────────
var rooms: Array = []  # used by procedural path only

## Exposed so HUD._try_connect_map_loader() can grab them if it connects late.
var current_map_data: Array = []
var current_grid_size: int  = 0
var current_cell_size: float = 1.0
var current_offset: Vector2 = Vector2.ZERO

# ─── Lifecycle ──────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("map_loader")  # lets HUD find us just like MapLoader
	_build_materials()
	
	var custom_path = "res://maps/level" + str(PlayerData.dungeon_floor) + ".json"
	if ResourceLoader.exists(custom_path):
		print("[DungeonGenerator] Loading custom level: ", custom_path)
		_generate_from_map(custom_path)
	else:
		print("[DungeonGenerator] Procedurally generating floor ", PlayerData.dungeon_floor)
		_generate()
	
	call_deferred("_emit_map_to_hud")

# ─── Clear ──────────────────────────────────────────────────────────────────
## Removes every generated object from the map (rooms, corridors, torches,
## enemies, exit portal) while leaving the player node untouched.
func clear_map() -> void:
	for child in get_children():
		if child.is_in_group("player"):
			continue
		child.queue_free()
	rooms.clear()

# ─── Materials ──────────────────────────────────────────────────────────────
func _build_materials() -> void:
	mat_floor = StandardMaterial3D.new()
	mat_floor.albedo_color = Color(0.15, 0.12, 0.1) # Match MapLoader floor
	mat_floor.roughness = 0.95
	mat_floor.grow = true
	mat_floor.grow_amount = -0.003

	mat_wall = StandardMaterial3D.new()
	mat_wall.albedo_color = Color(0.35, 0.33, 0.38) # Match MapLoader stone
	mat_wall.roughness = 0.7

	mat_ceil = StandardMaterial3D.new()
	mat_ceil.albedo_color = Color(0.15, 0.13, 0.15)
	mat_ceil.roughness = 1.0
	mat_ceil.grow = true
	mat_ceil.grow_amount = -0.003

# ═══════════════════════════════════════════════════════════════════════════
#  MAP-EDITOR PATH
# ═══════════════════════════════════════════════════════════════════════════

## Tile IDs – must match map_editor/script.js TOOLS list
const TILE_WALL        := 1
const TILE_PLAYER      := 2
const TILE_ENEMY       := 3
const TILE_TORCH       := 4
const TILE_TOMBSTONE   := 5
const TILE_TREE        := 6
const TILE_CAMPFIRE    := 7
const TILE_EXIT        := 8

func _generate_from_map(path: String = MAP_JSON_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[DungeonGenerator] Could not open " + path)
		_generate()
		return

	var json_text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if parsed == null or not parsed is Dictionary:
		push_error("[DungeonGenerator] Failed to parse level_map.json – falling back to procedural.")
		_generate()
		return

	var grid_size : int  = parsed.get("gridSize", 20)
	var cell_size : float = float(parsed.get("cellSize", 2.0))
	var map_rows  : Array = parsed.get("map", [])

	if map_rows.is_empty():
		push_error("[DungeonGenerator] level_map.json has no map data – falling back.")
		_generate()
		return

	# Half-extents so (0,0,0) is the centre of the map
	var half := (grid_size * cell_size) * 0.5
	var h    := wall_height
	var th   := 0.4  # wall/floor thickness

	# ── Continuous base floor ─────────────────────────────────────────────────
	# Cover the entire map with one solid slab so every walkable cell
	# (including open/0 cells) has ground beneath it.
	# Without this, empty (0) cells that form room interiors have no floor
	# and the player falls through.
	var floor_size := (grid_size * cell_size) + 4.0  # small margin around edges
	_add_box(Vector3(0, -th * 0.5, 0), Vector3(floor_size, th, floor_size), mat_floor, true)

	var player_spawned := false
	var exit_spawned   := false

	for row_idx in range(map_rows.size()):
		var row : Array = map_rows[row_idx]
		for col_idx in range(row.size()):
			var tile_id : int = int(row[col_idx])
			if tile_id == 0:
				continue  # empty space

			# World position of this cell's centre (Y=0 is ground level)
			var wx := col_idx * cell_size - half + cell_size * 0.5
			var wz := row_idx * cell_size - half + cell_size * 0.5
			var base := Vector3(wx, 0.0, wz)

			match tile_id:
				TILE_WALL:
					# No floor slab under walls – it's invisible and its top face
					# is coplanar with the wall bottom at Y=0, causing Z-fighting.
					# Full-height wall column
					_add_box(base + Vector3(0, h * 0.5, 0),
						Vector3(cell_size, h, cell_size), mat_wall, true)
					_add_box(base + Vector3(0, 5.3, 0),
						Vector3(cell_size, th, cell_size), mat_ceil, false)

				TILE_PLAYER:
					# Floor & Ceiling
					_add_box(base + Vector3(0, -th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_floor, true)
					_add_box(base + Vector3(0, h + th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_ceil, false)
					if not player_spawned:
						_teleport_player(base + Vector3(0, 1.5, 0))
						player_spawned = true

				TILE_ENEMY:
					# Floor & Ceiling
					_add_box(base + Vector3(0, -th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_floor, true)
					_add_box(base + Vector3(0, 5.3, 0),
						Vector3(cell_size, th, cell_size), mat_ceil, false)
					_spawn_enemy_at(base + Vector3(0, 1.0, 0))

				TILE_TORCH:
					# Floor & Ceiling
					_add_box(base + Vector3(0, -th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_floor, true)
					_add_box(base + Vector3(0, h + th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_ceil, false)
					_add_torch(base + Vector3(0, 3.5, 0))

				TILE_TOMBSTONE:
					# Floor & Ceiling
					_add_box(base + Vector3(0, -th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_floor, true)
					_add_box(base + Vector3(0, h + th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_ceil, false)
					_add_tombstone(base)

				TILE_TREE:
					# Floor & Ceiling
					_add_box(base + Vector3(0, -th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_floor, true)
					_add_box(base + Vector3(0, h + th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_ceil, false)
					_add_tree(base)

				TILE_CAMPFIRE:
					# Floor & Ceiling + campfire setup
					_add_box(base + Vector3(0, -th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_floor, true)
					_add_box(base + Vector3(0, h + th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_ceil, false)
					_add_campfire(base)

				TILE_EXIT:
					_add_box(base + Vector3(0, -th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_floor, true)
					if not exit_spawned:
						_spawn_exit_at(base)
						exit_spawned = true

				_:
					# Unknown tile – treat as plain floor
					_add_box(base + Vector3(0, -th * 0.5, 0),
						Vector3(cell_size, th, cell_size), mat_floor, true)

	# Safety: if the map had no exit tile, warn
	if not exit_spawned:
		push_warning("[DungeonGenerator] No exit tile (id=8) found in level_map.json.")

func _teleport_player(pos: Vector3) -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0] as Node3D
		if p.has_method("teleport_to"):
			p.teleport_to(pos, 10.0)
		else:
			p.global_position = pos
			p.rotation_degrees.y = 10.0

func _spawn_enemy_at(pos: Vector3) -> void:
	if not enemy_scene:
		return
	var e := enemy_scene.instantiate()
	add_child(e)
	e.global_position = pos

func _spawn_exit_at(base: Vector3) -> void:
	var exit_pos := base + Vector3(0, 0.1, 0)

	# Glowing portal light
	var portal_light := OmniLight3D.new()
	portal_light.light_color  = Color(0.3, 0.6, 1.0)
	portal_light.light_energy = 4.0
	portal_light.omni_range   = 8.0
	portal_light.position     = exit_pos + Vector3(0, 1.5, 0)
	add_child(portal_light)

	# Portal mesh (glowing sphere)
	var portal_mesh := MeshInstance3D.new()
	var sphere      := SphereMesh.new()
	sphere.radius   = 0.6
	portal_mesh.mesh = sphere
	var portal_mat                        := StandardMaterial3D.new()
	portal_mat.albedo_color               = Color(0.3, 0.6, 1.0)
	portal_mat.emission_enabled           = true
	portal_mat.emission                   = Color(0.3, 0.6, 1.0)
	portal_mat.emission_energy_multiplier = 4.0
	portal_mesh.material_override         = portal_mat
	portal_mesh.position                  = exit_pos + Vector3(0, 1.5, 0)
	add_child(portal_mesh)

	# Trigger area
	var area  := Area3D.new()
	area.name  = "ExitTrigger"
	var col   := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 2.5
	col.shape    = shape
	area.add_child(col)
	area.position = exit_pos + Vector3(0, 1.0, 0)
	area.body_entered.connect(_on_exit_entered)
	add_child(area)

	# Floating label
	var lbl        := Label3D.new()
	lbl.text       = "[ EXIT ]"
	lbl.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size  = 64
	lbl.modulate   = Color(0.5, 0.8, 1.0)
	lbl.position   = exit_pos + Vector3(0, 3.0, 0)
	add_child(lbl)

# ─── HUD Map Feed ────────────────────────────────────────────────────────────
## Converts the procedural rooms into a 2D int grid (same format as the JSON
## map editor export) and emits map_loaded so the HUD minimap populates.
func _emit_map_to_hud() -> void:
	if rooms.is_empty():
		return

	# Determine world AABB of all rooms
	var min_x :=  INF;  var max_x := -INF
	var min_z :=  INF;  var max_z := -INF
	for r in rooms:
		var p : Vector3 = r["pos"]
		var hw : float  = r["w"] * 0.5
		var hd : float  = r["d"] * 0.5
		min_x = min(min_x, p.x - hw);  max_x = max(max_x, p.x + hw)
		min_z = min(min_z, p.z - hd);  max_z = max(max_z, p.z + hd)

	var cell   := 2.0          # 2 world-units per map cell
	var margin := 4.0 * cell   # a few cells of border
	min_x -= margin;  max_x += margin
	min_z -= margin;  max_z += margin

	var cols : int = int(ceil((max_x - min_x) / cell))
	var rows : int = int(ceil((max_z - min_z) / cell))
	cols = max(cols, 1);  rows = max(rows, 1)

	# Build blank grid (all 0 = open/irrelevant)
	var grid : Array = []
	for _y in range(rows):
		grid.append(Array())
		grid[-1].resize(cols)
		grid[-1].fill(0)

	# Paint rooms as FLOOR (value 0 keeps them transparent on minimap;
	# paint walls around room edges as 1 so they show as grey outlines)
	for r_idx in range(rooms.size()):
		var r = rooms[r_idx]
		var p : Vector3 = r["pos"]
		var hw : float  = r["w"] * 0.5
		var hd : float  = r["d"] * 0.5

		var cx0 : int = int(floor((p.x - hw - min_x) / cell))
		var cx1 : int = int(ceil ((p.x + hw - min_x) / cell))
		var cy0 : int = int(floor((p.z - hd - min_z) / cell))
		var cy1 : int = int(ceil ((p.z + hd - min_z) / cell))

		for cy in range(max(0, cy0), min(rows, cy1 + 1)):
			for cx in range(max(0, cx0), min(cols, cx1 + 1)):
				var is_edge = (cx == cx0 or cx == cx1 or cy == cy0 or cy == cy1)
				grid[cy][cx] = 1 if is_edge else 0   # 1=wall outline, 0=floor

		# Mark exit room with tile 8 at its centre
		if r_idx == rooms.size() - 1:
			var ec : int = clamp(int((p.x - min_x) / cell), 0, cols - 1)
			var er : int = clamp(int((p.z - min_z) / cell), 0, rows - 1)
			grid[er][ec] = 8

	var offset := Vector2(min_x * -1.0, min_z * -1.0)  # matches MapLoader convention
	current_map_data  = grid
	current_grid_size = max(rows, cols)
	current_cell_size = cell
	current_offset    = offset

	map_loaded.emit(grid, current_grid_size, cell, offset)

# ═══════════════════════════════════════════════════════════════════════════
#  PROCEDURAL PATH  (unchanged from original)
# ═══════════════════════════════════════════════════════════════════════════

func _generate() -> void:
	_place_rooms()
	_build_rooms()
	_build_corridors()
	_spawn_enemies()
	_spawn_decorations()
	_spawn_exit()
	_spawn_player()

func _spawn_decorations() -> void:
	# Add some flavour to procedural rooms (Tombstones, Trees, Campfires)
	for i in range(rooms.size()):
		var r = rooms[i]
		var w = r["w"]
		var d = r["d"]
		var pos = r["pos"]
		
		# Skip first room (player spawn) for heavy decorations, maybe just a light
		if i == 0:
			var light_pos = pos + Vector3(0, 1.5, 0)
			_add_torch(light_pos)
			continue

		# Random number of decorations per room
		var count = randi_range(2, 5)
		for j in range(count):
			var rx = randf_range(-w * 0.35, w * 0.35)
			var rz = randf_range(-d * 0.35, d * 0.35)
			var d_pos = pos + Vector3(rx, 0, rz)
			
			var type = randf()
			if type < 0.4:
				_add_tombstone(d_pos)
			elif type < 0.7:
				_add_tree(d_pos, randf_range(2.5, 4.0))
			else:
				_add_campfire(d_pos)

func _place_rooms() -> void:
	rooms.clear()
	var spread := 30.0
	for i in range(room_count):
		var attempts := 0
		while attempts < 30:
			var rx := randf_range(-spread, spread)
			var rz := randf_range(-spread, spread)
			var rw := randf_range(min_room_w, max_room_w)
			var rd := randf_range(min_room_d, max_room_d)
			var candidate := { "pos": Vector3(rx, 0, rz), "w": rw, "d": rd }
			if not _overlaps(candidate):
				rooms.append(candidate)
				break
			spread += 2.0
			attempts += 1

func _overlaps(candidate: Dictionary) -> bool:
	for r in rooms:
		var dx = abs(candidate["pos"].x - r["pos"].x)
		var dz = abs(candidate["pos"].z - r["pos"].z)
		var min_sx = (candidate["w"] + r["w"]) * 0.5 + 2.0
		var min_sz = (candidate["d"] + r["d"]) * 0.5 + 2.0
		if dx < min_sx and dz < min_sz:
			return true
	return false

func _build_rooms() -> void:
	for i in range(rooms.size()):
		var r = rooms[i]
		var p: Vector3 = r["pos"]
		var w: float = r["w"]
		var d: float = r["d"]
		var h: float = wall_height
		var th := 0.4

		_add_box(p + Vector3(0, -th * 0.5, 0), Vector3(w, th, d), mat_floor, true)
		_add_box(p + Vector3(0, h + th * 0.5, 0), Vector3(w, th, d), mat_ceil, false)
		_add_box(p + Vector3(0, h * 0.5, -d * 0.5 - th * 0.5), Vector3(w, h, th), mat_wall, true)
		_add_box(p + Vector3(0, h * 0.5,  d * 0.5 + th * 0.5), Vector3(w, h, th), mat_wall, true)
		_add_box(p + Vector3(-w * 0.5 - th * 0.5, h * 0.5, 0), Vector3(th, h, d), mat_wall, true)
		_add_box(p + Vector3( w * 0.5 + th * 0.5, h * 0.5, 0), Vector3(th, h, d), mat_wall, true)

		for tx in [-1, 1]:
			for tz in [-1, 1]:
				var torch_pos = p + Vector3(tx * (w * 0.4), h * 0.7, tz * (d * 0.4))
				_add_torch(torch_pos)

func _build_corridors() -> void:
	for i in range(rooms.size() - 1):
		var a: Dictionary = rooms[i]
		var b: Dictionary = rooms[i + 1]
		var ap: Vector3 = a["pos"]
		var bp: Vector3 = b["pos"]
		var cw := corridor_width
		var h := wall_height
		var th := 0.4

		var mid_x = (ap.x + bp.x) * 0.5
		var seg1_cx = (ap.x + mid_x) * 0.5
		var seg1_len = abs(mid_x - ap.x)
		if seg1_len > 0.5:
			var seg1_pos = Vector3(seg1_cx, 0, ap.z)
			_add_box(seg1_pos + Vector3(0, -th * 0.5, 0), Vector3(seg1_len, th, cw), mat_floor, true)
			_add_box(seg1_pos + Vector3(0, h + th * 0.5, 0), Vector3(seg1_len, th, cw), mat_ceil, false)
			_add_box(seg1_pos + Vector3(0, h * 0.5, -cw * 0.5), Vector3(seg1_len, h, th), mat_wall, true)
			_add_box(seg1_pos + Vector3(0, h * 0.5,  cw * 0.5), Vector3(seg1_len, h, th), mat_wall, true)

		var seg2_cz = (ap.z + bp.z) * 0.5
		var seg2_len = abs(bp.z - ap.z)
		if seg2_len > 0.5:
			var seg2_pos = Vector3(mid_x, 0, seg2_cz)
			_add_box(seg2_pos + Vector3(0, -th * 0.5, 0), Vector3(cw, th, seg2_len), mat_floor, true)
			_add_box(seg2_pos + Vector3(0, h + th * 0.5, 0), Vector3(cw, th, seg2_len), mat_ceil, false)
			_add_box(seg2_pos + Vector3(-cw * 0.5, h * 0.5, 0), Vector3(th, h, seg2_len), mat_wall, true)
			_add_box(seg2_pos + Vector3( cw * 0.5, h * 0.5, 0), Vector3(th, h, seg2_len), mat_wall, true)

		var seg3_cx = (mid_x + bp.x) * 0.5
		var seg3_len = abs(bp.x - mid_x)
		if seg3_len > 0.5:
			var seg3_pos = Vector3(seg3_cx, 0, bp.z)
			_add_box(seg3_pos + Vector3(0, -th * 0.5, 0), Vector3(seg3_len, th, cw), mat_floor, true)
			_add_box(seg3_pos + Vector3(0, h + th * 0.5, 0), Vector3(seg3_len, th, cw), mat_ceil, false)
			_add_box(seg3_pos + Vector3(0, h * 0.5, -cw * 0.5), Vector3(seg3_len, h, th), mat_wall, true)
			_add_box(seg3_pos + Vector3(0, h * 0.5,  cw * 0.5), Vector3(seg3_len, h, th), mat_wall, true)

		# ── Elbow corner patches ──────────────────────────────────────────────
		# The L-bend leaves two cw×cw squares uncovered: (mid_x, ap.z) and
		# (mid_x, bp.z).  Without these patches the player falls through.
		var corner1 := Vector3(mid_x, 0, ap.z)
		_add_box(corner1 + Vector3(0, -th * 0.5, 0), Vector3(cw, th, cw), mat_floor, true)
		_add_box(corner1 + Vector3(0, h + th * 0.5, 0), Vector3(cw, th, cw), mat_ceil, false)

		if abs(bp.z - ap.z) > cw:  # only patch the second corner when seg2 exists
			var corner2 := Vector3(mid_x, 0, bp.z)
			_add_box(corner2 + Vector3(0, -th * 0.5, 0), Vector3(cw, th, cw), mat_floor, true)
			_add_box(corner2 + Vector3(0, h + th * 0.5, 0), Vector3(cw, th, cw), mat_ceil, false)

func _spawn_enemies() -> void:
	if not enemy_scene:
		return
	for i in range(1, rooms.size()):
		var r = rooms[i]
		for j in range(enemies_per_room):
			var e = enemy_scene.instantiate()
			add_child(e)
			var ox = randf_range(-r["w"] * 0.3, r["w"] * 0.3)
			var oz = randf_range(-r["d"] * 0.3, r["d"] * 0.3)
			e.global_position = r["pos"] + Vector3(ox, 1.0, oz)

func _spawn_exit() -> void:
	if rooms.is_empty():
		return
	_spawn_exit_at(rooms[rooms.size() - 1]["pos"])

func _spawn_player() -> void:
	if rooms.is_empty():
		return
	_teleport_player(rooms[0]["pos"] + Vector3(0, 1.5, 0))

# ─── Shared exit handler ─────────────────────────────────────────────────────
func _on_exit_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	PlayerData.dungeon_floor += 1
	PlayerData.current_zone = "Dungeon Floor " + str(PlayerData.dungeon_floor)

	if body.has_method("set_physics_process"):
		body.set_physics_process(false)

	# Find the HUD via its group – works regardless of node name or tree position
	var hud_nodes := get_tree().get_nodes_in_group("hud")
	var canvas : Control = hud_nodes[0] as Control if hud_nodes.size() > 0 else null

	if not canvas:
		# Fallback: look for any CanvasLayer in the scene root
		for child in get_tree().root.get_children():
			if child is CanvasLayer:
				for sub in child.get_children():
					if sub is Control:
						canvas = sub
						break
			if canvas:
				break

	if not canvas:
		# No HUD found at all – skip animation and reload immediately
		get_tree().reload_current_scene()
		return

	# Full-screen black fade
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(overlay)

	# "Floor X Complete" gold text
	var lbl := Label.new()
	lbl.text = "Floor " + str(PlayerData.dungeon_floor - 1) + " Complete"
	lbl.add_theme_font_size_override("font_size", 64)
	lbl.add_theme_color_override("font_color", Color.GOLD)
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_outline_size", 6)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.modulate.a = 0
	canvas.add_child(lbl)

	# Animate: fade to black + text in → hold → reload
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 1.0, 1.5)
	tween.parallel().tween_property(lbl, "modulate:a", 1.0, 1.5)
	tween.tween_interval(1.5)
	tween.tween_callback(func(): get_tree().reload_current_scene())

# ─── Helpers ─────────────────────────────────────────────────────────────────
func _add_box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, collidable: bool) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box       := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.position = pos

	if collidable:
		var body   := StaticBody3D.new()
		var cshape := CollisionShape3D.new()
		var bshape := BoxShape3D.new()
		bshape.size = size
		cshape.shape = bshape
		body.add_child(cshape)
		mesh_inst.add_child(body)

	add_child(mesh_inst)

func _add_torch(pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color  = Color(1.0, 0.8, 0.4)
	light.light_energy = 5.0
	light.omni_range   = 15.0
	light.position     = pos
	add_child(light)

	var mesh_inst := MeshInstance3D.new()
	var cyl       := CylinderMesh.new()
	cyl.top_radius    = 0.05
	cyl.bottom_radius = 0.08
	cyl.height        = 0.4
	mesh_inst.mesh    = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.4, 0.25, 0.1)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 2.0
	mesh_inst.material_override    = mat
	mesh_inst.position             = pos - Vector3(0, 0.2, 0)
	add_child(mesh_inst)

func _add_tombstone(pos: Vector3) -> void:
	# Standard tombstone (matches MapLoader)
	var base_pos = pos + Vector3(0, 0.5, 0)
	_add_box(base_pos, Vector3(0.8, 1.0, 0.2), mat_wall, true)

func _add_tree(pos: Vector3, h: float = 4.0) -> void:
	# Dead dungeon tree
	var trunk_pos = pos + Vector3(0, h * 0.5, 0)
	
	var mi = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.3
	cyl.height = h
	mi.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.15, 0.1)
	mi.material_override = mat
	mi.position = trunk_pos
	add_child(mi)

func _add_campfire(pos: Vector3) -> void:
	var fire_light := OmniLight3D.new()
	fire_light.light_color  = Color(1.0, 0.4, 0.0)
	fire_light.light_energy = 4.0
	fire_light.omni_range   = 10.0
	fire_light.position     = pos + Vector3(0, 1.0, 0)
	add_child(fire_light)
	
	# Small glowing cube as ember
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	mi.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0)
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	mi.position = pos + Vector3(0, 0.2, 0)
	add_child(mi)
