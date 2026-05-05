## Sword.gd
extends RefCounted

func build(root: Node3D, config: Dictionary) -> MeshInstance3D:
	# 1. Try to load from GLB if provided
	var file = config.get("file", "")
	var node = config.get("node", "Sword")
	if file != "":
		var glb_mi = WeaponBuilder.load_mesh_from_glb(root, file, node)
		if glb_mi:
			# Adjust scale/rotation for GLB models if they are too small/big
			glb_mi.scale = Vector3(1.2, 1.2, 1.2)
			return glb_mi

	# 2. Procedural Fallback
	var steel = WeaponBuilder.create_metal_material(Color(0.8, 0.8, 0.85))
	var gold  = WeaponBuilder.create_metal_material(Color(0.9, 0.75, 0.2))
	var dark  = WeaponBuilder.create_wood_material(Color(0.15, 0.1, 0.08))

	var blade := WeaponBuilder.add_box(root, Vector3(0.06, 0.9, 0.015), Vector3(0, 0.65, 0), Vector3.ZERO, steel)
	WeaponBuilder.add_box(root, Vector3(0.24, 0.03, 0.04), Vector3(0, 0.22, 0), Vector3.ZERO, gold)
	WeaponBuilder.add_cylinder(root, 0.025, 0.18, Vector3(0, 0.12, 0), Vector3.ZERO, dark)
	WeaponBuilder.add_sphere(root, 0.035, Vector3(0, 0.03, 0), gold)

	return blade # Return the blade as the "main" mesh for simple visibility toggling
