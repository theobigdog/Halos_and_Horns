# A crouch for sneaking (Ted, Nov 20; the KayKit packs have no crouch animation): after the normal
# animation poses the skeleton each frame, this bends the knees, sinks the hips and leans the body
# forward, by `amount` (0 standing .. 1 fully crouched). character_rig.gd eases it in and out.
extends SkeletonModifier3D

var amount := 0.0

# bone -> [local axis, degrees at a full crouch]
const BENDS := {
	"upperleg.l": [Vector3.RIGHT, -62.0], "upperleg.r": [Vector3.RIGHT, -62.0],
	"lowerleg.l": [Vector3.RIGHT, 95.0], "lowerleg.r": [Vector3.RIGHT, 95.0],
	"foot.l": [Vector3.RIGHT, -35.0], "foot.r": [Vector3.RIGHT, -35.0],
	"spine": [Vector3.RIGHT, 18.0], "chest": [Vector3.RIGHT, 10.0],
	"head": [Vector3.RIGHT, -20.0],
}
const HIP_DROP := 0.18          # KayKit units the hips sink at a full crouch


func _process_modification_with_delta(_delta: float) -> void:
	if amount <= 0.001:
		return
	var sk := get_skeleton()
	if sk == null:
		return
	for bone in BENDS:
		var b := sk.find_bone(bone)
		if b < 0:
			continue
		var turn := Quaternion(BENDS[bone][0], deg_to_rad(BENDS[bone][1] * amount))
		sk.set_bone_pose_rotation(b, sk.get_bone_pose_rotation(b) * turn)
	var hips := sk.find_bone("hips")
	if hips >= 0:
		sk.set_bone_pose_position(hips, sk.get_bone_pose_position(hips) + Vector3.DOWN * HIP_DROP * amount)
