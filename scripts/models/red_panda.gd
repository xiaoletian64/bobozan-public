class_name RedPandaModel
extends RefCounted
# Shared authored surfaces; each fighter supplies its own material slots and joints.
static var meshes: Dictionary = {}
static func surface(parent: Node3D, mesh: Mesh, material: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node
static func profile(key: String, rings: Array, segments: int = 32) -> ArrayMesh:
	if meshes.has(key): return meshes[key]
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rings.size()-1):
		var a: Vector3 = rings[row]
		var b: Vector3 = rings[row+1]
		for j in range(segments):
			var u = TAU*j/segments
			var v = TAU*(j+1)/segments
			var p = Vector3(cos(u)*a.x,a.y,sin(u)*a.z)
			var q = Vector3(cos(v)*a.x,a.y,sin(v)*a.z)
			var r = Vector3(cos(u)*b.x,b.y,sin(u)*b.z)
			var t = Vector3(cos(v)*b.x,b.y,sin(v)*b.z)
			for vertex in [p,q,r,q,t,r]: st.add_vertex(vertex)
	st.index()
	st.generate_normals()
	meshes[key] = st.commit()
	return meshes[key]
static func strip(parent: Node3D, points: Array, width: float, material: Material) -> MeshInstance3D:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()-1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i+1]
		var tangent = (b-a).normalized()
		var edge = tangent.cross(Vector3.FORWARD).normalized()*width*0.5
		for p in [a-edge,b-edge,a+edge,a+edge,b-edge,b+edge]: st.add_vertex(p)
	st.generate_normals()
	return surface(parent,st.commit(),material)
static func head_mesh() -> ArrayMesh:
	if meshes.has("head"): return meshes.head
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(32):
		for col in range(48):
			for index in [Vector2i(row,col),Vector2i(row+1,col),Vector2i(row,col+1),Vector2i(row,col+1),Vector2i(row+1,col),Vector2i(row+1,col+1)]:
				var v = PI*float(index.x)/32.0
				var u = TAU*float(index.y)/48.0
				var y = cos(v)*0.48
				var cheek = 1.0+0.16*exp(-pow((y+0.12)/0.18,2))
				var p = Vector3(cos(u)*sin(v)*0.53*cheek,y,sin(u)*sin(v)*0.40)
				var color = Color("b95229").lerp(Color("dc7c38"),clampf((y+0.25)*1.3,0,1))
				if p.z > 0.10:
					var white_mask = pow((absf(p.x)-0.29)/0.28,2)+pow((p.y+0.18)/0.21,2)
					color = color.lerp(Color("ead9b7"),1.0-smoothstep(0.65,1.22,white_mask))
					var eye_mask = pow((absf(p.x)-0.235)/0.17,2)+pow((p.y+0.005)/0.15,2)
					color = color.lerp(Color("4e3028"),1.0-smoothstep(0.65,1.18,eye_mask))
				color = color.darkened(0.014*(1.0+sin(u*37.0+v*29.0)))
				st.set_color(color)
				st.set_normal(Vector3(p.x/0.28,p.y/0.23,p.z/0.16).normalized())
				st.add_vertex(p)
	st.index()
	meshes.head = st.commit()
	return meshes.head
static func tail_mesh() -> ArrayMesh:
	if meshes.has("tail"): return meshes.tail
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curve = Curve3D.new()
	curve.add_point(Vector3(0,0,0),Vector3.ZERO,Vector3(-0.15,-0.12,-0.28))
	curve.add_point(Vector3(-0.72,-0.15,-0.61),Vector3(0.26,-0.08,0.05),Vector3(-0.30,0.15,-0.08))
	curve.add_point(Vector3(-1.06,0.54,-0.62),Vector3(-0.04,-0.29,0),Vector3(0.04,0.29,0.05))
	curve.add_point(Vector3(-0.65,1.00,-0.40),Vector3(-0.24,-0.04,-0.04),Vector3.ZERO)
	var length = curve.get_baked_length()
	for i in range(64):
		for j in range(16):
			for pair in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i,j+1),Vector2i(i,j+1),Vector2i(i+1,j),Vector2i(i+1,j+1)]:
				var t = float(pair.x)/64
				var at = curve.sample_baked(t*length,true)
				var direction = (curve.sample_baked(minf(t+0.008,1)*length,true)-curve.sample_baked(maxf(t-0.008,0)*length,true)).normalized()
				var across = direction.cross(Vector3.FORWARD).normalized()
				var up = direction.cross(across).normalized()
				var angle = TAU*float(pair.y)/16
				var normal = across*cos(angle)+up*sin(angle)
				var radius = (0.13+0.14*sin(PI*t))*minf(1.0,(1-t)*10+0.015)
				var color = Color("b44c27") if int(t*9)%2 == 0 else Color("e5a25c")
				st.set_color(color)
				st.set_normal(normal)
				st.add_vertex(at+normal*radius)
	st.index()
	meshes.tail = st.commit()
	return meshes.tail
static func build(f) -> void:
	for slot in ["cloth","trim","dark","hood","face","ink","fur","nose","gold","lining"]:
		f.palette[slot] = f.material(Color.WHITE)
		f.palette[slot].metallic_specular = 0.18
	f.palette.face.albedo_color = Color("ead9b7")
	f.palette.ink.albedo_color = Color("352c2a")
	f.palette.fur.albedo_color = Color("ac4d2b")
	f.palette.nose.albedo_color = Color("292629")
	f.palette.gold.albedo_color = Color("b7a16d")
	f.palette.lining.albedo_color = Color("cdb484")
	var vertex_material = f.material(Color.WHITE)
	vertex_material.vertex_color_use_as_albedo = true
	vertex_material.metallic_specular = 0.1
	# Two-sided thin cloth ribbons, opaque and unlit by emission.
	for slot in ["trim","lining","gold"]: f.palette[slot].cull_mode = BaseMaterial3D.CULL_DISABLED
	f.body = f.pivot(f,Vector3.ZERO)
	var coat = profile("coat",[Vector3(0.01,0.58,0.01),Vector3(0.43,0.61,0.29),Vector3(0.44,0.68,0.29),Vector3(0.34,0.88,0.25),Vector3(0.35,1.07,0.26),Vector3(0.42,1.30,0.25),Vector3(0.31,1.43,0.20),Vector3(0.18,1.46,0.16),Vector3(0.01,1.47,0.01)])
	surface(f.body,coat,f.palette.cloth)
	f.piece(f.body,Vector3(0,1.48,0),Vector3(0.40,0.28,0.36),"fur")
	# Sculpted russet head with cream cheeks, dark eye mask, muzzle and pointed ears.
	f.head = f.pivot(f.body,Vector3(0,1.96,0.01))
	surface(f.head,head_mesh(),vertex_material)
	var ear = profile("ear",[Vector3(0.10,-0.10,0.06),Vector3(0.20,0.0,0.10),Vector3(0.17,0.16,0.085),Vector3(0.09,0.30,0.04),Vector3(0.005,0.34,0.004)],24)
	for side in [-1,1]:
		var ear_root = f.pivot(f.head,Vector3(side*0.40,0.32,-0.04))
		ear_root.rotation.z = -side*0.23
		ear_root.scale.y = 0.78
		surface(ear_root,ear,f.palette.face)
		var inner = surface(ear_root,ear,f.palette.ink,Vector3(0,0.017,0.069))
		inner.scale = Vector3(0.65,0.74,0.39)
		var eye = f.pivot(f.head,Vector3(side*0.235,0.005,0.35))
		eye.rotation.y = side*0.20
		f.piece(eye,Vector3.ZERO,Vector3(0.218,0.24,0.075),"ink")
		f.piece(eye,Vector3(0,-0.008,0.04),Vector3(0.155,0.18,0.052),"face")
		f.sphere(eye,Vector3(-side*0.012,-0.012,0.066),Vector3(0.125,0.155,0.028),Color("754329"))
		f.piece(eye,Vector3(-side*0.015,-0.012,0.080),Vector3(0.079,0.125,0.021),"nose")
		f.sphere(eye,Vector3(-0.027,0.038,0.095),Vector3(0.038,0.045,0.014),Color("fff0d5"))
		f.eyes.append(eye)
		var brow = f.piece(f.head,Vector3(side*0.25,0.165,0.34),Vector3(0.21,0.055,0.065),"face")
		brow.rotation.z = side*0.12
		# Swept cheek wisps keep the animal silhouette readable from the side.
		for j in range(2):
			var tuft = f.piece(f.head,Vector3(side*(0.47+j*0.025),-0.13-j*0.07,0.09),Vector3(0.26-j*0.035,0.13,0.24),"face")
			tuft.rotation.z = -side*(0.28+j*0.12)
	f.piece(f.head,Vector3(0,-0.20,0.365),Vector3(0.53,0.30,0.26),"face")
	f.piece(f.head,Vector3(0,-0.12,0.508),Vector3(0.17,0.105,0.08),"nose")
	f.piece(f.head,Vector3(0,-0.195,0.501),Vector3(0.017,0.07,0.012),"ink")
	strip(f.head,[Vector3(-0.10,-0.23,0.489),Vector3(-0.05,-0.25,0.497),Vector3(0,-0.238,0.503),Vector3(0.05,-0.25,0.497),Vector3(0.10,-0.23,0.489)],0.012,f.palette.ink)
	# Overlapping lapels, side fastening and a wide sash; no hoodie or zipper.
	strip(f.body,[Vector3(-0.19,1.43,0.19),Vector3(-0.13,1.32,0.259),Vector3(0.10,1.13,0.274),Vector3(0.17,0.94,0.248)],0.075,f.palette.trim)
	strip(f.body,[Vector3(0.18,1.43,0.19),Vector3(0.14,1.30,0.26),Vector3(0.05,1.22,0.278)],0.053,f.palette.trim)
	for y in [1.17,1.04]:
		f.piece(f.body,Vector3(0.18,y,0.25),Vector3(0.13,0.033,0.05),"lining")
	f.piece(f.body,Vector3(0,0.88,0),Vector3(0.73,0.12,0.54),"trim")
	f.sphere(f.body,Vector3(-0.21,1.13,0.25),Vector3(0.12,0.12,0.035),f.tint)
	strip(f.body,[Vector3(0.11,0.84,0.279),Vector3(0.15,0.70,0.31),Vector3(0.20,0.53,0.30)],0.12,f.palette.trim)
	# Modest bamboo embroidery on the hem, shared with the costume palette.
	strip(f.body,[Vector3(-0.17,0.64,0.282),Vector3(-0.15,0.74,0.283),Vector3(-0.14,0.80,0.281)],0.015,f.palette.lining)
	for side in [-1,1]:
		var leaf = f.piece(f.body,Vector3(-0.15+side*0.045,0.735,0.294),Vector3(0.10,0.025,0.018),"lining")
		leaf.rotation.z = side*0.55
	var thigh = profile("thigh",[Vector3(0.04,-0.46,0.06),Vector3(0.145,-0.40,0.16),Vector3(0.18,-0.22,0.19),Vector3(0.17,-0.05,0.17),Vector3(0.04,0.02,0.04)],24)
	var sleeve = profile("sleeve",[Vector3(0.13,-0.31,0.14),Vector3(0.16,-0.25,0.16),Vector3(0.19,-0.07,0.18),Vector3(0.12,0.04,0.12)],24)
	for side in [-1,1]:
		var leg = f.pivot(f.body,Vector3(side*0.235,0.73,0))
		f.legs.append(leg)
		surface(leg,thigh,f.palette.dark)
		f.piece(leg,Vector3(0,-0.45,0.02),Vector3(0.30,0.17,0.34),"trim")
		f.piece(leg,Vector3(0,-0.57,0.13),Vector3(0.39,0.24,0.54),"ink")
		for toe in range(3):
			f.piece(leg,Vector3(-0.10+toe*0.10,-0.58,0.33),Vector3(0.07,0.09,0.09),"nose")
		var arm = f.pivot(f.body,Vector3(side*0.41,1.32,0))
		surface(arm,sleeve,f.palette.cloth)
		f.piece(arm,Vector3(0,-0.26,0),Vector3(0.34,0.065,0.34),"trim")
		var elbow = f.pivot(arm,Vector3(0,-0.27,0))
		f.piece(elbow,Vector3(0,-0.115,0.01),Vector3(0.24,0.34,0.26),"ink")
		f.piece(elbow,Vector3(0,-0.23,0.025),Vector3(0.28,0.12,0.29),"trim")
		f.piece(elbow,Vector3(0,-0.36,0.05),Vector3(0.30,0.30,0.23),"ink")
		f.piece(elbow,Vector3(-side*0.13,-0.33,0.10),Vector3(0.12,0.18,0.14),"ink")
		for digit in range(3):
			f.piece(elbow,Vector3(-0.09+digit*0.09,-0.46,0.075),Vector3(0.085,0.09,0.14),"ink")
		if side == -1:
			f.left = arm
			f.left_elbow = elbow
		else:
			f.right = arm
			f.right_elbow = elbow
	f.plush_tail = f.pivot(f.body,Vector3(0,0.78,-0.22))
	surface(f.plush_tail,tail_mesh(),vertex_material)
	# The three-day reward adds a shoulder scarf and an engraved belt clasp.
	f.reward_parts = f.pivot(f.body,Vector3.ZERO)
	f.piece(f.reward_parts,Vector3(0,1.45,0),Vector3(0.63,0.14,0.46),"trim")
	strip(f.reward_parts,[Vector3(-0.28,1.40,-0.12),Vector3(-0.42,1.18,-0.29),Vector3(-0.49,0.91,-0.35),Vector3(-0.60,0.78,-0.40)],0.20,f.palette.cloth)
	f.piece(f.reward_parts,Vector3(0,0.88,0.29),Vector3(0.16,0.12,0.04),"gold")
	f.apply_skin(f.skin_id)
