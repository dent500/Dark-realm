extends SceneTree

# ---------------------------------------------------------
# build_patch.gd
# Run this script using:
# Godot --headless -s build_patch.gd
# ---------------------------------------------------------

func _init():
	print("--- Starting OTA Patch Build ---")
	
	# Determine version from version.txt
	var v_file = FileAccess.open("res://version.txt", FileAccess.READ)
	var current_version = "unknown"
	if v_file:
		current_version = v_file.get_as_text().strip_edges()
		print("Building Patch for Version: ", current_version)
	else:
		printerr("ERROR: version.txt not found!")
		quit(1)
		return

	var packer = PCKPacker.new()
	var output_path = "build/patch_v" + current_version + ".pck"
	
	# Ensure build directory exists
	if not DirAccess.dir_exists_absolute("res://build"):
		DirAccess.make_dir_absolute("res://build")

	var err = packer.pck_start(output_path)
	if err != OK:
		printerr("Failed to start PCK Packer. Error: ", err)
		quit(1)
		return

	# List of files/folders to include in OTA patches
	var files_to_add = [
		"version.txt",
		"patch_version.txt",
		"version.json",
		"scripts/autoloads/UpdateManager.gd",
		"scripts/autoloads/NetworkManager.gd",
		"scripts/autoloads/PlayerData.gd",
		"scripts/autoloads/SaveSystem.gd",
		"scripts/autoloads/GameManager.gd",
		"scripts/ui/MainMenu.gd",
		"scripts/ui/HUD.gd",
		"scripts/combat/CombatSystem.gd",
		"scripts/world/WorldManager.gd",
		"scripts/world/TerrainGenerator.gd",
		"scripts/world/WorldBuilder.gd",
		"scripts/world/WaveManager.gd",
		"scripts/world/Collectable.gd",
		"scripts/player/PlayerController.gd",
		"scripts/data/ClassData.gd",
		"scripts/crafting/CraftingSystem.gd"
	]

	var added_count = 0
	for f_path in files_to_add:
		var res_path = "res://" + f_path
		if FileAccess.file_exists(res_path):
			packer.add_file(res_path, res_path)
			added_count += 1
		else:
			printerr("Warning: File not found and skipped: ", res_path)

	packer.flush()
	print("---------------------------------------------------")
	print("SUCCESS: PCK created at: ", output_path)
	print("Included ", added_count, " files.")
	print("---------------------------------------------------")
	quit(0)
