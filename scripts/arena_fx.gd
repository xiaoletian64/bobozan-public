class_name ArenaFX
extends Node3D
const Actor = preload("res://scripts/fighter.gd")
func ring(at: Vector3, color: Color, radius: float = 1.0, duration: float = 0.6, upright: bool = false) -> void:
	var n = MeshInstance3D.new()
	var mesh = TorusMesh.new()
	mesh.inner_radius = 0.92
	mesh.outer_radius = 1.0
	mesh.rings = 40
	mesh.ring_segments = 8
	n.mesh = mesh
	n.material_override = Actor.material(color, 0.7)
	n.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	n.position = at
	if upright: n.rotation.x = PI / 2
	n.scale = Vector3.ONE * 0.12
	add_child(n)
	var t = n.create_tween().set_parallel(true)
	t.tween_property(n,"scale",Vector3.ONE*radius,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(n.material_override,"albedo_color:a",0.0,duration)
	t.chain().tween_callback(n.queue_free)
func burst(at: Vector3, color: Color, big: bool = false) -> void:
	ring(at,color,2.1 if big else 1.0,0.65,true)
	for i in range(18 if big else 9):
		var n = MeshInstance3D.new()
		var m = SphereMesh.new()
		m.radius = 0.045 if big else 0.025
		m.height = m.radius * 2
		m.radial_segments = 8
		m.rings = 4
		n.mesh = m
		n.material_override = Actor.material(color,1.0)
		n.position = at
		add_child(n)
		var angle = TAU*float(i)/(18 if big else 9)
		var offset = Vector3(cos(angle),sin(angle),sin(angle*3)*0.4)*(1.6 if big else 0.7)
		var t = n.create_tween().set_parallel(true)
		t.tween_property(n,"position",at+offset,0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(n,"scale",Vector3.ZERO,0.6)
		t.chain().tween_callback(n.queue_free)
func clear() -> void:
	for n in get_children():
		remove_child(n)
		n.queue_free()
	finisher = null

# Driven by the match clock so background/resume and hit-stop cannot skip the slash.
var finisher: Node3D
var blade: MeshInstance3D
var core: MeshInstance3D
var source: Vector3
var target: Vector3
var heavy = false
func begin_finisher(from: Vector3, to: Vector3, color: Color, strong: bool) -> void:
	if is_instance_valid(finisher):
		remove_child(finisher)
		finisher.queue_free()
	source = from + Vector3(0,1.2,0)
	target = to + Vector3(0,1.2,0)
	heavy = strong
	finisher = Node3D.new()
	add_child(finisher)
	blade = MeshInstance3D.new()
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Tapered crescent in the vertical plane of travel, with an open centre.
	for i in range(32):
		var a = lerpf(-1.25,1.25,float(i)/32)
		var b = lerpf(-1.25,1.25,float(i+1)/32)
		var wa = sin(PI*float(i)/32)*0.22
		var wb = sin(PI*float(i+1)/32)*0.22
		var p = Vector3(cos(a),sin(a),0)
		var q = Vector3(cos(b),sin(b),0)
		for v in [p,q,q*(1-wb),p,q*(1-wb),p*(1-wa)]: mesh.surface_add_vertex(v)
	mesh.surface_end()
	blade.mesh = mesh
	blade.material_override = Actor.material(Color(color,0),1.3)
	blade.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blade.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blade.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	finisher.add_child(blade)
	core = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.16
	sphere_mesh.height = 0.32
	sphere_mesh.radial_segments = 16
	sphere_mesh.rings = 8
	core.mesh = sphere_mesh
	core.material_override = Actor.material(Color(color.lightened(0.65),0),1.5)
	core.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	finisher.add_child(core)
	seek_finisher(0)
func seek_finisher(elapsed: float) -> void:
	if not is_instance_valid(finisher): return
	var direction = (target-source).normalized()
	var travel = clampf((elapsed-0.22)/0.33,0,1)
	var fade = clampf((0.85-elapsed)/0.30,0,1)
	core.position = source.lerp(target,travel)
	core.scale = Vector3.ONE*(1.0+minf(elapsed/0.22,1.0)*(1.6 if heavy else 0.6))
	core.material_override.albedo_color.a = fade*0.85
	blade.position = core.position-direction*0.6
	blade.scale = Vector3(1 if direction.x > 0 else -1,1,1)*(1.15 if heavy else 0.75)
	blade.rotation.z = (-0.18 if direction.x > 0 else 0.18)
	blade.material_override.albedo_color.a = fade*(0.9 if elapsed >= 0.22 else 0.0)
	finisher.visible = elapsed < 0.85

# Inward motion distinguishes gaining energy from an outward impact.
func gather(at: Vector3, color: Color, duration: float = 0.45) -> void:
	for i in range(6):
		var n = MeshInstance3D.new()
		var mesh = SphereMesh.new()
		mesh.radius = 0.045
		mesh.height = 0.09
		mesh.radial_segments = 8
		mesh.rings = 4
		n.mesh = mesh
		n.material_override = Actor.material(color,1.0)
		var angle = TAU*float(i)/6
		n.position = at+Vector3(cos(angle)*0.85,sin(angle)*0.55,0)
		add_child(n)
		var t = n.create_tween().set_parallel(true)
		t.tween_property(n,"position",at,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(n,"scale",Vector3.ONE*0.2,duration)
		t.chain().tween_callback(n.queue_free)
func deflect(at: Vector3, color: Color) -> void:
	ring(at,color,0.85,0.22,true)
	ring(at,color.lightened(0.4),0.55,0.15,true)
