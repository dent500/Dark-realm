func build(root: Node3D, config: Dictionary) -> MeshInstance3D:
	var file = config.get("file", "")
	var node = config.get("node", "Book")
	if file != "":
		var glb_mi = WeaponBuilder.load_mesh_from_glb(root, file, node)
		if glb_mi:
			glb_mi.scale = Vector3(1.2, 1.2, 1.2)
			# Books are often flat on ground, rotate for vertical carry in hand
			glb_mi.rotation_degrees = Vector3(90, 0, 0)
			return glb_mi

	var leather = WeaponBuilder.create_leather_material(Color(0.25, 0.12, 0.08))
	var cloth   = WeaponBuilder.create_cloth_material(Color(0.9, 0.85, 0.75))
	var gold    = WeaponBuilder.create_metal_material(Color(0.85, 0.7, 0.2))

	var cover := WeaponBuilder.add_box(root, Vector3(0.25, 0.32, 0.06), Vector3(0, 0, 0), Vector3.ZERO, leather)
	WeaponBuilder.add_box(root, Vector3(0.22, 0.3, 0.07), Vector3(0.02, 0, 0), Vector3.ZERO, cloth)
	WeaponBuilder.add_box(root, Vector3(0.26, 0.04, 0.08), Vector3(0, 0.14, 0), Vector3.ZERO, gold)
	WeaponBuilder.add_box(root, Vector3(0.26, 0.04, 0.08), Vector3(0, -0.14, 0), Vector3.ZERO, gold)
	WeaponBuilder.add_sphere(root, 0.04, Vector3(-0.1, 0, 0), gold)

	return cover
