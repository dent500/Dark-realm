func build(root: Node3D, config: Dictionary) -> MeshInstance3D:
	var file = config.get("file", "")
	var node = config.get("node", "Bow")
	if file != "":
		var glb_mi = WeaponBuilder.load_mesh_from_glb(root, file, node)
		if glb_mi:
			glb_mi.scale = Vector3(1.1, 1.1, 1.1)
			return glb_mi

	var wood = WeaponBuilder.create_wood_material(Color(0.3, 0.2, 0.1))
	var string_mat = WeaponBuilder.create_metal_material(Color(0.9, 0.9, 0.9))
	var iron = WeaponBuilder.create_metal_material(Color(0.5, 0.5, 0.5))
	var feather = WeaponBuilder.create_cloth_material(Color(0.8, 0.2, 0.1))

	var grip := WeaponBuilder.add_box(root, Vector3(0.045, 0.12, 0.06), Vector3(0, 0, 0), Vector3.ZERO, wood)
	WeaponBuilder.add_box(root, Vector3(0.03, 0.3, 0.03), Vector3(0, 0.18, 0.05), Vector3(-15, 0, 0), wood)
	WeaponBuilder.add_box(root, Vector3(0.025, 0.3, 0.025), Vector3(0, 0.42, 0.15), Vector3(-35, 0, 0), wood)
	WeaponBuilder.add_box(root, Vector3(0.02, 0.2, 0.02), Vector3(0, 0.58, 0.28), Vector3(-55, 0, 0), wood)
	WeaponBuilder.add_box(root, Vector3(0.03, 0.3, 0.03), Vector3(0, -0.18, 0.05), Vector3(15, 0, 0), wood)
	WeaponBuilder.add_box(root, Vector3(0.025, 0.3, 0.025), Vector3(0, -0.42, 0.15), Vector3(35, 0, 0), wood)
	WeaponBuilder.add_box(root, Vector3(0.02, 0.2, 0.02), Vector3(0, -0.58, 0.28), Vector3(55, 0, 0), wood)
	WeaponBuilder.add_cylinder(root, 0.004, 1.25, Vector3(0, 0, 0.3), Vector3(0, 0, 0), string_mat)
	
	var arrow_root := Node3D.new()
	arrow_root.name = "Arrow"
	root.add_child(arrow_root)
	WeaponBuilder.add_cylinder(arrow_root, 0.008, 0.8, Vector3(0, 0, 0.1), Vector3(90, 0, 0), wood)
	WeaponBuilder.add_box(arrow_root, Vector3(0.04, 0.04, 0.01), Vector3(0, 0, 0.5), Vector3(0, 0, 45), iron)
	WeaponBuilder.add_box(arrow_root, Vector3(0.01, 0.08, 0.1), Vector3(0, 0.04, -0.2), Vector3.ZERO, feather)
	WeaponBuilder.add_box(arrow_root, Vector3(0.01, 0.08, 0.1), Vector3(0, -0.04, -0.2), Vector3.ZERO, feather)

	return grip
