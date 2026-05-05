func build(root: Node3D, config: Dictionary) -> MeshInstance3D:
	var file = config.get("file", "")
	var node = config.get("node", "Mace")
	if file != "":
		var glb_mi = WeaponBuilder.load_mesh_from_glb(root, file, node)
		if glb_mi:
			glb_mi.scale = Vector3(1.0, 1.0, 1.0)
			return glb_mi

	var steel = WeaponBuilder.create_metal_material(Color(0.65, 0.65, 0.7))
	var wood  = WeaponBuilder.create_wood_material(Color(0.2, 0.15, 0.1))

	var head := WeaponBuilder.add_sphere(root, 0.12, Vector3(0, 0.65, 0), steel)
	WeaponBuilder.add_box(root, Vector3(0.04, 0.2, 0.28), Vector3(0, 0.65, 0), Vector3.ZERO, steel)
	WeaponBuilder.add_box(root, Vector3(0.28, 0.2, 0.04), Vector3(0, 0.65, 0), Vector3.ZERO, steel)
	WeaponBuilder.add_box(root, Vector3(0.2, 0.2, 0.2), Vector3(0, 0.65, 0), Vector3(45, 45, 45), steel)
	WeaponBuilder.add_cylinder(root, 0.035, 0.75, Vector3(0, 0.3, 0), Vector3.ZERO, wood)

	return head
