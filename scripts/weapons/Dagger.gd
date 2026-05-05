func build(root: Node3D, config: Dictionary) -> MeshInstance3D:
	var file = config.get("file", "")
	var node = config.get("node", "Dagger")
	if file != "":
		var glb_mi = WeaponBuilder.load_mesh_from_glb(root, file, node)
		if glb_mi:
			glb_mi.scale = Vector3(1.0, 1.0, 1.0)
			return glb_mi

	var steel   = WeaponBuilder.create_metal_material(Color(0.75, 0.75, 0.8))
	var gold    = WeaponBuilder.create_metal_material(Color(0.85, 0.7, 0.2))
	var leather = WeaponBuilder.create_leather_material(Color(0.3, 0.15, 0.1))

	var blade := WeaponBuilder.add_box(root, Vector3(0.045, 0.45, 0.012), Vector3(0, 0.35, 0), Vector3.ZERO, steel)
	WeaponBuilder.add_box(root, Vector3(0.12, 0.02, 0.03), Vector3(0, 0.14, 0), Vector3.ZERO, gold)
	WeaponBuilder.add_cylinder(root, 0.022, 0.14, Vector3(0, 0.07, 0), Vector3.ZERO, leather)
	WeaponBuilder.add_sphere(root, 0.028, Vector3(0, 0, 0), gold)

	return blade
