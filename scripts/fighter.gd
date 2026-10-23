class_name Fighter
extends Node3D
const Catalog = preload("res://scripts/cosmetics/skin_catalog.gd")
var skin_id = Catalog.BASE
var palette: Dictionary = {}
var reward_parts: Node3D
var plush_tail: Node3D
var body: Node3D
var head: Node3D
var left: Node3D
var right: Node3D
var left_elbow: Node3D
var right_elbow: Node3D
var orb: MeshInstance3D
var shield: MeshInstance3D
var aura: MeshInstance3D
static var shared_sphere: SphereMesh
var surfaces: Dictionary = {}
var legs: Array = []
var eyes: Array = []
var tails: Array = []
var tint = Color("65ead2")
var phase = "idle"
var finishing = false
var projectile_spent = false
var animation_speed = 1.0
var age = 0.0
var life = 0.0
var recoil_age = 1.0
var projectile_direction = Vector3(0,0,1)
static func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.78
	if glow > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m
func sphere(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	if shared_sphere == null:
		shared_sphere = SphereMesh.new()
		shared_sphere.radius = 0.5
		shared_sphere.height = 1.0
		shared_sphere.radial_segments = 20
		shared_sphere.rings = 12
	n.mesh = shared_sphere
	if not surfaces.has(color): surfaces[color] = material(color)
	n.material_override = surfaces[color]
	n.position = at
	n.scale = size
	parent.add_child(n)
	return n
func pivot(parent: Node3D, at: Vector3) -> Node3D:
	var n = Node3D.new()
	n.position = at
	parent.add_child(n)
	return n
# A shared articulated body with material slots and optional skin accessories.
func piece(parent: Node3D, at: Vector3, size: Vector3, slot: String) -> MeshInstance3D:
	var n = sphere(parent,at,size,Color.WHITE)
	n.material_override = palette[slot]
	return n
func _ready() -> void:
	preload("res://scripts/models/red_panda.gd").build(self)
	orb = sphere(self,Vector3(0,1.2,0.8),Vector3.ONE*0.4,tint)
	orb.material_override = material(tint.lightened(0.3),1.2)
	aura = sphere(orb,Vector3.ZERO,Vector3.ONE*1.55,Color(tint,0.19))
	aura.material_override = material(Color(tint,0.19),0.3)
	aura.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield = sphere(self,Vector3(0,1.2,0.7),Vector3(1.35,1.6,0.07),tint)
	shield.material_override = material(Color(tint,0.30),0.35)
	shield.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	orb.hide()
	shield.hide()
func apply_skin(id: String) -> void:
	skin_id = Catalog.safe_id(id)
	if palette.is_empty(): return
	var data = Catalog.get_skin(skin_id)
	for slot in ["cloth","trim","dark","hood"]:
		palette[slot].albedo_color = Color(data[slot])
	reward_parts.visible = skin_id == Catalog.REWARD
func block_impact() -> void:
	recoil_age = 0.0
func act(value: String) -> void:
	phase = value
	recoil_age = 1.0
	finishing = false
	projectile_spent = false
	age = 0
func _process(delta: float) -> void:
	delta *= animation_speed
	age += delta
	recoil_age += delta
	life += delta
	var target_left = Vector3(0.1,0,-0.12)
	var target_right = Vector3(0.1,0,0.12)
	var elbow_angle = -0.12
	var height = sin(life*3.5)*0.015
	var tilt = Vector3.ZERO
	var advance = 0.0
	var stride = 0.0
	head.rotation.y = sin(life*1.3)*0.045
	for eye in eyes: eye.scale.y = 0.15 if fmod(life,4.2) > 4.08 else 1.0
	for tail in tails: tail.rotation.x = sin(life*6)*0.12
	plush_tail.rotation.x = minf(age*2.5,1.45) if phase == "lose" else 0.0
	plush_tail.rotation.y = sin(life*1.8)*0.12
	plush_tail.rotation.z = sin(life*2.2)*0.045
	orb.visible = not finishing and not projectile_spent and phase in ["charge","wave","super"] and age < 0.76
	shield.visible = phase in ["guard","strong_guard"] and age < 0.76
	orb.position = Vector3(0,1.18,0.65)
	orb.scale = Vector3.ONE * (0.24+minf(age,0.5)*0.32+0.035*sin(age*28))
	if phase == "boss_ready":
		target_left = Vector3(-0.95,0,0.6)
		target_right = Vector3(-0.95,0,-0.6)
		elbow_angle = -1.1
		head.rotation.y = -0.12
		tilt.x = -0.06
	elif phase == "ready":
		target_left = Vector3(-0.48,0,0.22)
		target_right = Vector3(-0.48,0,-0.22)
		elbow_angle = -0.9
		height = -sin(minf(age/0.6,1.0)*PI)*0.07
	elif phase == "charge":
		target_left = Vector3(-0.45,0,0.6)
		target_right = Vector3(-0.45,0,-0.6)
		elbow_angle = -1.1
		height = -0.10
		tilt.x = -0.08
		stride = 0.16
	elif phase in ["wave","super"]:
		var launch = clampf((age-0.13)/0.18,0,1)
		target_left = Vector3(lerpf(-0.45,-1.55,launch),0,0.10)
		target_right = Vector3(lerpf(-0.45,-1.55,launch),0,-0.10)
		elbow_angle = lerpf(-1.3,-0.03,launch)
		tilt.x = launch*0.18
		advance = launch*0.22
		stride = launch*0.38
		orb.position = Vector3(0,1.2,0) + projectile_direction*(0.65+maxf(age-0.18,0)*10.6)
		orb.scale = Vector3.ONE * (0.67 if phase == "super" else 0.36)
	elif phase in ["guard","strong_guard"]:
		target_left = Vector3(-0.85,0,0.55)
		target_right = Vector3(-0.85,0,-0.55)
		elbow_angle = -1.25
		height = -0.06
		shield.scale.x = 1.4 if phase == "strong_guard" else 1.1
	elif phase == "hit":
		tilt.x = -0.35
		target_left.z = -0.8
		target_right.z = 0.8
	elif phase == "lose":
		tilt.x = -minf(age*2.5,1.45)
		height = minf(age*0.5,0.10)
		advance = -minf(age*1.3,0.65)
		stride = -0.28
	elif phase == "win":
		target_left.z = -2.7
		target_right.z = 2.7
		height = abs(sin(age*5))*0.22
	if recoil_age < 0.24:
		var recoil = sin(recoil_age/0.24*PI)
		tilt.x -= recoil*0.20
		advance -= recoil*0.12
		shield.scale.x += recoil*0.16
	var blend = 1.0-exp(-delta*18.0)
	left.rotation = left.rotation.lerp(target_left,blend)
	right.rotation = right.rotation.lerp(target_right,blend)
	left_elbow.rotation.x = lerpf(left_elbow.rotation.x,elbow_angle,blend)
	right_elbow.rotation.x = lerpf(right_elbow.rotation.x,elbow_angle,blend)
	for i in range(legs.size()):
		legs[i].rotation.x = lerpf(legs[i].rotation.x,stride*(1 if i == 0 else -1),blend)
	body.position.z = lerpf(body.position.z,advance,blend)
	body.position.y = lerpf(body.position.y,height,blend)
	body.rotation = body.rotation.lerp(tilt,blend)
