@tool
extends SceneTree

func _init() -> void:
	var fbx_path = "res://animation/sword and shield idle.fbx"
	var fbx = load(fbx_path)
	var fbx_scene = fbx.instantiate()
	var skels = fbx_scene.find_children("*", "Skeleton3D", true)
	if skels.size() > 0:
		var skeleton = skels[0]
		print("Found Skeleton: ", skeleton.name)
		print("Bones: ", skeleton.get_bone_count())
		print("Bone 0: ", skeleton.get_bone_name(0), " rest: ", skeleton.get_bone_rest(0))
	var aps = fbx_scene.find_children("*", "AnimationPlayer", true)
	if aps.size() > 0:
		print("Found AP: ", aps[0].name)
		var anims = aps[0].get_animation_list()
		if anims.size() > 0:
			print("Anim 0 tracks: ", aps[0].get_animation(anims[0]).get_track_count())
	quit()
