extends SceneTree

func _init():
	var packer = PCKPacker.new()
	var output_path = "build/patch_v1.0.2.pck"
	var err = packer.pck_start(output_path)
	
	if err != OK:
		printerr("Failed to start PCK: ", err)
		quit(1)
		return

	var files_to_add = [
		"version.txt",
		"patch_version.txt",
		"version.json",
		"scripts/autoloads/UpdateManager.gd",
		"scripts/autoloads/NetworkManager.gd",
		"scripts/ui/MainMenu.gd",
		"scripts/combat/CombatSystem.gd",
		"scripts/ui/HUD.gd",
		"scripts/world/WorldManager.gd",
		"scripts/world/TerrainGenerator.gd",
		"scripts/player/PlayerController.gd",
		"scripts/autoloads/PlayerData.gd",
		"scripts/autoloads/SaveSystem.gd",
		"scripts/world/WorldBuilder.gd",
		"scripts/world/WaveManager.gd",
		"scripts/world/Collectable.gd",
		"scripts/data/ClassData.gd",
		"scripts/crafting/CraftingSystem.gd"
	]

	for f_path in files_to_add:
		var res_path = "res://" + f_path
		if FileAccess.file_exists(res_path):
			print("Adding file: ", res_path)
			packer.add_file(res_path, res_path)
		else:
			printerr("Warning: File not found: ", res_path)

	packer.flush()
	print("PCK created successfully at: ", output_path)
	quit(0)
