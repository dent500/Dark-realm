extends Control

func _ready():
	# 1. Wait a tiny moment for the engine to breathe
	await get_tree().process_frame
	
	if has_node("%StatusLabel"):
		get_node("%StatusLabel").text = "Checking for Patches..."
	
	# 2. UpdateManager is already an autoload, so it ran its _init()
	# Only load patches if NOT in the editor.
	if not OS.has_feature("editor"):
		if has_node("/root/UpdateManager"):
			get_node("/root/UpdateManager")._load_installed_patches()
	else:
		print("[Bootstrap] Editor detected. Skipping manual patch load to preserve local edits.")
	
	if has_node("%StatusLabel"):
		get_node("%StatusLabel").text = "Loading Realm..."
	
	await get_tree().create_timer(0.5).timeout
	
	# 3. Transition to Main Menu
	print("[Bootstrap] Switching to Main Menu...")
	var err = get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	if err != OK:
		printerr("[Bootstrap] FAILED to load main menu! Error code: ", err)
