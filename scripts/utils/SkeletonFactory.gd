## SkeletonFactory.gd
## Utility for programmatically creating a bone hierarchy for procedural characters.
class_name SkeletonFactory

# --- MIXAMO HIERARCHY DEFINITION ---
# Format: [BoneName, ParentName, RelativeRestPosition]
const HIERARCHY = [
	["Hips", "", Vector3(0, 0.9, 0)],
	
	["Spine", "Hips", Vector3(0, 0.1, 0)],
	["Spine1", "Spine", Vector3(0, 0.15, 0)],
	["Spine2", "Spine1", Vector3(0, 0.15, 0)],
	
	["Neck", "Spine2", Vector3(0, 0.1, 0)],
	["Head", "Neck", Vector3(0, 0.1, 0)],
	
	["LeftShoulder", "Spine2", Vector3(0.1, 0, 0)],
	["LeftArm", "LeftShoulder", Vector3(0.15, 0, 0)],
	["LeftForeArm", "LeftArm", Vector3(0.25, 0, 0)],
	["LeftHand", "LeftForeArm", Vector3(0.25, 0, 0)],
	
	["RightShoulder", "Spine2", Vector3(-0.1, 0, 0)],
	["RightArm", "RightShoulder", Vector3(-0.15, 0, 0)],
	["RightForeArm", "RightArm", Vector3(-0.25, 0, 0)],
	["RightHand", "RightForeArm", Vector3(-0.25, 0, 0)],
	
	["LeftUpLeg", "Hips", Vector3(0.1, -0.05, 0)],
	["LeftLeg", "LeftUpLeg", Vector3(0, -0.4, 0)],
	["LeftFoot", "LeftLeg", Vector3(0, -0.4, 0)],
	
	["RightUpLeg", "Hips", Vector3(-0.1, -0.05, 0)],
	["RightLeg", "RightUpLeg", Vector3(0, -0.4, 0)],
	["RightFoot", "RightLeg", Vector3(0, -0.4, 0)]
]

static func create_skeleton() -> Skeleton3D:
	var skeleton = Skeleton3D.new()
	skeleton.name = "GeneralSkeleton"
	
	# Pass 1: Add all bones
	for data in HIERARCHY:
		var name = data[0]
		skeleton.add_bone(name)
	
	# Pass 2: Setup parents and rests
	for data in HIERARCHY:
		var name = data[0]
		var parent = data[1]
		var rel_pos = data[2]
		
		var bone_idx = skeleton.find_bone(name)
		var parent_idx = -1 if parent == "" else skeleton.find_bone(parent)
		
		if parent_idx != -1:
			skeleton.set_bone_parent(bone_idx, parent_idx)
		
		# Set bone rest position relative to parent
		var rest = Transform3D.IDENTITY
		rest.origin = rel_pos
		skeleton.set_bone_rest(bone_idx, rest)
	
	# Finalize: Reset bones to their rests
	skeleton.reset_bone_poses()
	return skeleton

static func create_skin(skeleton: Skeleton3D) -> Skin:
	# Ensure the skeleton is fully calculated before taking the snapshot
	skeleton.force_update_all_bone_transforms()
	
	var skin = Skin.new()
	for i in range(skeleton.get_bone_count()):
		var bone_name = skeleton.get_bone_name(i)
		# Godot 4: Skin binds must be the inverse of the bone's GLOBAL rest in skeleton-space
		skin.add_bind(i, skeleton.get_bone_global_rest(i).inverse())
		skin.set_bind_name(i, bone_name)
		skin.set_bind_bone(i, i)
		
	return skin
