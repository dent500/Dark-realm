func build(root: Node3D, config: Dictionary) -> MeshInstance3D:
	# 1. Try to load from GLB if provided
	var file = config.get("file", "")
	var node = config.get("node", "Staff")
	if file != "":
		var glb_mi = WeaponBuilder.load_mesh_from_glb(root, file, node)
		if glb_mi:
			# Magic staves often need a bit of extra height/scale
			glb_mi.scale = Vector3(1.1, 1.1, 1.1)
			return glb_mi

	# 2. Procedural Fallback
	var wood  = WeaponBuilder.create_wood_material(Color(0.25, 0.15, 0.1))
	var gold  = WeaponBuilder.create_metal_material(Color(0.9, 0.7, 0.1))
	var gem   = WeaponBuilder.create_gem_material(Color(0.2, 0.4, 1.2))

	var shaft := WeaponBuilder.add_cylinder(root, 0.025, 1.8, Vector3(0, 0.5, 0), Vector3.ZERO, wood)
	WeaponBuilder.add_cylinder(root, 0.035, 0.04, Vector3(0, 1.3, 0), Vector3.ZERO, gold)
	WeaponBuilder.add_cylinder(root, 0.04, 0.04, Vector3(0, 1.35, 0), Vector3.ZERO, gold)
	WeaponBuilder.add_sphere(root, 0.08, Vector3(0, 1.45, 0), gem)
	WeaponBuilder.add_cylinder(root, 0.07, 0.015, Vector3(0, 1.45, 0), Vector3(90, 0, 0), gold)
	WeaponBuilder.add_cylinder(root, 0.07, 0.015, Vector3(0, 1.45, 0), Vector3(45, 45, 0), gold)

	return shaft
