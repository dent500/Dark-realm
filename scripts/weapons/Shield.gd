func build(root: Node3D, config: Dictionary) -> MeshInstance3D:
	var file = config.get("file", "")
	var node = config.get("node", "Shield")
	if file != "":
		var glb_mi = WeaponBuilder.load_mesh_from_glb(root, file, node)
		if glb_mi:
			glb_mi.scale = Vector3(1.0, 1.0, 1.0)
			return glb_mi

	var wood   = WeaponBuilder.create_wood_material(Color(0.4, 0.25, 0.15))
	var iron   = WeaponBuilder.create_metal_material(Color(0.5, 0.5, 0.55))
	var bronze = WeaponBuilder.create_metal_material(Color(0.6, 0.4, 0.2))

	var plate := WeaponBuilder.add_box(root, Vector3(0.5, 0.6, 0.04), Vector3(0, 0, 0.05), Vector3.ZERO, wood)
	WeaponBuilder.add_box(root, Vector3(0.52, 0.62, 0.01), Vector3(0, 0, 0.07), Vector3.ZERO, iron)
	WeaponBuilder.add_box(root, Vector3(0.04, 0.62, 0.02), Vector3(0.25, 0, 0.07), Vector3.ZERO, iron)
	WeaponBuilder.add_box(root, Vector3(0.04, 0.62, 0.02), Vector3(-0.25, 0, 0.07), Vector3.ZERO, iron)
	WeaponBuilder.add_sphere(root, 0.1, Vector3(0, 0, 0.08), bronze)

	return plate
