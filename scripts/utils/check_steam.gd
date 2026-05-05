extends SceneTree

func _init():
	if ClassDB.class_exists("Steam"):
		print("SUCCESS: GodotSteam is loaded.")
		var s = Steam.get_singleton()
		var res = s.steamInit()
		print("Steam Init Result: ", res)
	else:
		print("FAILURE: GodotSteam not found.")
	quit()
