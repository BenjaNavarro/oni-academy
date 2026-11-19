extends SceneTree
# Bake skeletal keyframes for the existing Mixamo rig. No mesh scaling.
var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var source: Animation
var base_positions := {}
var base_rotations := {}
var base_pose := []

func _initialize():
	call_deferred("build")

func world_pos(bone_name: String) -> Vector3:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_" + bone_name))).origin

func world_rotation(bone_name: String) -> Quaternion:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_" + bone_name))).basis.orthonormalized().get_rotation_quaternion()

func set_world_rotation(bone_name: String, q: Quaternion):
	var i := skeleton.find_bone("mixamorig_" + bone_name)
	var parent := skeleton.get_bone_parent(i)
	var parent_basis := skeleton.global_basis
	if parent >= 0:
		parent_basis *= skeleton.get_bone_global_pose(parent).basis
	skeleton.set_bone_pose_rotation(i, (parent_basis.orthonormalized().get_rotation_quaternion().inverse() * q).normalized())

func rotate_world(bone_name: String, degrees: float):
	set_world_rotation(bone_name, Quaternion(Vector3.RIGHT, deg_to_rad(degrees)) * world_rotation(bone_name))

func solve_limb(upper: String, lower: String, end: String, target: Vector3, pole: Vector3):
	var origin := world_pos(upper)
	var a := origin.distance_to(world_pos(lower))
	var b := world_pos(lower).distance_to(world_pos(end))
	var distance := clampf(origin.distance_to(target), absf(a - b) + 0.001, a + b - 0.001)
	var direction := origin.direction_to(target)
	var bend := (pole - direction * pole.dot(direction)).normalized()
	var along := (a * a + distance * distance - b * b) / (2.0 * distance)
	var knee := origin + direction * along + bend * sqrt(maxf(0.0, a * a - along * along))
	set_world_rotation(upper, Quaternion(origin.direction_to(world_pos(lower)), origin.direction_to(knee)) * world_rotation(upper))
	var lower_origin := world_pos(lower)
	set_world_rotation(lower, Quaternion(lower_origin.direction_to(world_pos(end)), lower_origin.direction_to(target)) * world_rotation(lower))
	if end.ends_with("Hand"):
		var index := skeleton.find_bone("mixamorig_" + end)
		skeleton.set_bone_pose_rotation(index, base_pose[index].basis.get_rotation_quaternion())
	else:
		set_world_rotation(end, base_rotations[end])

func pose(kind: String, t: float, duration: float):
	if kind == "jedi_sprint":
		# Preserve the imported running gait and layer a forward, arms-back sprint.
		player.play("running")
		player.seek(fposmod(t / duration, 1.0) * player.get_animation("running").length, true)
		player.pause()
		rotate_world("Spine", 22.0)
		rotate_world("Spine1", 8.0)
		rotate_world("Neck", -20.0)
		rotate_world("Head", -8.0)
		for side in ["Left", "Right"]:
			var side_sign := 1.0 if side == "Left" else -1.0
			var swing := sin(TAU * t / duration) * side_sign
			var hand := Vector3(side_sign * 0.27, 0.90 + swing * 0.04, -0.32 + swing * 0.07)
			solve_limb(side + "Arm", side + "ForeArm", side + "Hand", hand, Vector3(side_sign * 0.35, -1, -0.3).normalized())
		return
	for i in range(skeleton.get_bone_count()):
		skeleton.set_bone_pose_position(i, base_pose[i].origin)
		skeleton.set_bone_pose_rotation(i, base_pose[i].basis.get_rotation_quaternion())
	var crouched := kind == "crouched" or kind == "crouch_walk"
	var cycle := TAU * t / duration
	var dash_strength := 0.85 + 0.15 * sin(PI * t / duration)
	var hips_delta := Vector3.ZERO
	if crouched:
		hips_delta = Vector3(0, -0.72 + sin(cycle) * 0.006, -0.06)
	elif kind == "fall":
		hips_delta.y = -0.03
	elif kind == "dash":
		hips_delta.y = -0.18 * dash_strength
	var hips := skeleton.find_bone("mixamorig_Hips")
	skeleton.set_bone_pose_position(hips, base_pose[hips].origin + skeleton.global_basis.inverse() * hips_delta)
	if crouched:
		rotate_world("Spine", 24.0 + sin(cycle) * 0.8)
		rotate_world("Spine1", 10.0)
		rotate_world("Neck", -20.0)
		rotate_world("Head", -10.0)
	elif kind == "dash":
		rotate_world("Spine", 32.0 * dash_strength)
		rotate_world("Spine1", 12.0 * dash_strength)
		rotate_world("Neck", -25.0 * dash_strength)
		rotate_world("Head", -12.0 * dash_strength)
	else:
		rotate_world("Spine", 8.0 if kind == "jump" else 5.0)
		rotate_world("Neck", -5.0)
	for side in ["Left", "Right"]:
		var side_sign := 1.0 if side == "Left" else -1.0
		var foot: Vector3 = base_positions[side + "Foot"]
		var hand: Vector3 = base_positions[side + "Hand"]
		if crouched:
			foot.x = side_sign * 0.16
			foot.z = 0.04
			if kind == "crouch_walk":
				var phase := cycle + (0.0 if side == "Left" else PI)
				foot.z += cos(phase) * 0.16
				foot.y += maxf(0, sin(phase)) * 0.065
			hand = Vector3(side_sign * 0.27, 0.54 + sin(cycle) * 0.006, 0.31)
		elif kind == "jump":
			# Early takeoff -> tucked flight. The last frame is held in the air.
			var tuck := smoothstep(0.0, 0.20, t)
			foot += Vector3(0, 0.23 * tuck, -0.11 * tuck)
			hand = hand.lerp(Vector3(side_sign * 0.28, 1.63, 0.28), 0.65 + 0.35 * tuck)
		elif kind == "dash":
			foot = Vector3(side_sign * 0.14, base_positions[side + "Foot"].y, side_sign * 0.34 * dash_strength)
			hand = Vector3(side_sign * 0.26, 0.82, -0.32 * dash_strength)
		else:
			foot += Vector3(0, 0.025 + sin(cycle) * 0.004, 0.04)
			hand = Vector3(side_sign * 0.37, 1.26 + sin(cycle) * 0.008, 0.16)
		solve_limb(side + "UpLeg", side + "Leg", side + "Foot", foot, Vector3.FORWARD * -1)
		solve_limb(side + "Arm", side + "ForeArm", side + "Hand", hand, Vector3(side_sign * 0.35, -1, -0.3).normalized())

func build():
	model = load("res://assets/models/mixamo_base.glb").instantiate()
	root.add_child(model)
	skeleton = model.get_node("Armature/Skeleton3D")
	player = model.get_node("AnimationPlayer")
	source = player.get_animation("idle")
	player.play("idle")
	player.advance(0.0)
	player.pause()
	for i in range(skeleton.get_bone_count()):
		base_pose.append(skeleton.get_bone_pose(i))
	for name in ["LeftFoot", "RightFoot", "LeftHand", "RightHand"]:
		base_positions[name] = world_pos(name)
		base_rotations[name] = world_rotation(name)
	var library := AnimationLibrary.new()
	var static_values := []
	for track in range(source.get_track_count()):
		static_values.append(source.track_get_key_value(track, 0))
	for kind in ["crouched", "crouch_walk", "jump", "fall", "dash", "jedi_sprint"]:
		var clip: Animation = source.duplicate()
		clip.resource_name = kind
		clip.length = {"crouched": 2.4, "crouch_walk": 1.1, "jump": 0.32, "fall": 1.2, "dash": 0.20, "jedi_sprint": 0.65}[kind]
		clip.loop_mode = Animation.LOOP_NONE if kind in ["jump", "dash"] else Animation.LOOP_LINEAR
		for track in range(clip.get_track_count()):
			clip.track_set_imported(track, false)
			while clip.track_get_key_count(track) > 0:
				clip.track_remove_key(track, 0)
		var steps := int(ceil(clip.length * 24.0))
		for frame in range(steps + 1):
			var t := clip.length * float(frame) / steps
			pose(kind, t, clip.length)
			for track in range(clip.get_track_count()):
				var path := clip.track_get_path(track)
				var value = static_values[track]
				if path.get_subname_count() == 1 and str(path).begins_with("Armature/Skeleton3D:"):
					var bone := skeleton.find_bone(path.get_subname(0))
					if bone >= 0:
						match clip.track_get_type(track):
							Animation.TYPE_POSITION_3D: value = skeleton.get_bone_pose_position(bone)
							Animation.TYPE_ROTATION_3D: value = skeleton.get_bone_pose_rotation(bone)
							Animation.TYPE_SCALE_3D: value = skeleton.get_bone_pose_scale(bone)
				clip.track_insert_key(track, t, value)
		library.add_animation(kind, clip)
		pose(kind, clip.length * 0.4, clip.length)
		print(kind, " head_top=", world_pos("HeadTop_End"), " foot=", world_pos("LeftFoot"))
	# Optional output argument lets us preview a new bake before replacing the library.
	var args := OS.get_cmdline_user_args()
	var output := args[0] if not args.is_empty() else "res://assets/animations/character_poses.tres"
	var err := ResourceSaver.save(library, output)
	print("SAVE ", err)
	model.free()
	quit(err)
