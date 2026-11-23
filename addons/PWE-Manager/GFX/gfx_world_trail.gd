extends Node

# ====================================================
# Lage-Geschichte einer GFX in der Welt (Bug-Fahrplan B10) für ihre ungebundenen Partikel (IsBind 0) und Spuren (110 mit
# Bind 0: A3DTrail merkt sich Weltpositionen, z.B. der Bogen hinter der Klinge beim Blitzschläger): Angelica speichert
# solche Partikel mit absoluter Position (A3DParticleSystemEx, IsParticlePosAbs) - bewegt sich die GFX (an einer laufenden
# Figur), bleiben sie dort, wo sie ausgestoßen wurden, z.B. die Staubspur des Kriegers beim Überfall (Effekt 53 "冲锋用加速",
# 策划联入\加速.gfx am Rücken). Unser Partikel-Shader (create_id_120.gd) rechnet zustandslos; diese Hilfe merkt sich je Bild
# die Lage des Partikel-Netzes (höchstens SAMPLES Proben über die Lebensdauer TTL der Partikel) und gibt dem Shader die
# damaligen Lagen im Raum von jetzt (TrailPos: Verschiebung + Alter in s, TrailRot: Drehung).
# enable(root) hängt sie nur an GFX, die der Client an Figuren bindet (attack_fx.gd attach / gebundene Aktions-Ereignisse);
# die vielen festen GFX der Map brauchen sie nicht (ohne Geschichte rechnet der Shader wie bisher).
# Jede so versorgte GFX bekommt eine eigene Kopie ihres Materials (die Werte gelten je Figur).
# ====================================================

const SAMPLES = 16 # gfx_parser.gd TRAIL_SAMPLES
const STEP_MIN = 0.03 # s zwischen zwei Proben
const STEP_MAX = 0.25

var mesh: GeometryInstance3D
var _mat: ShaderMaterial
var _hist: Array = [] # [ms, Transform3D], neueste zuerst
var _step_ms = 50


# An alle ungebundenen Partikel-Netze unter root -> Anzahl versorgter Netze
static func enable(root: Node) -> int:
	if root == null:
		return 0
	var n = 0
	for mi in root.find_children("*", "GeometryInstance3D", true, false):
		var m = mi.material_override as ShaderMaterial
		if m == null or m.shader == null or not "TrailCount" in m.shader.code or mi.has_node("Lage_Geschichte"):
			continue
		var el = mi.get_parent()
		var d = el.get("parsed_data") if el != null else null
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var ttl = 0.0
		if str(d.get("IsBind", "1")).strip_edges() == "0": # Partikel (create_id_120)
			ttl = float(str(d.get("TTL", "1")))
		elif str(d.get("Bind", "1")).strip_edges() == "0": # Spur (create_id_110, A3DTrail): SegLife ms
			ttl = float(str(d.get("SegLife", "500"))) / 1000.0
		else:
			continue
		var drv = new()
		drv.name = "Lage_Geschichte"
		drv.setup(mi, ttl)
		mi.add_child(drv)
		n += 1
	return n

func setup(mi: GeometryInstance3D, ttl: float) -> void:
	mesh = mi
	_mat = (mi.material_override as ShaderMaterial).duplicate()
	mi.material_override = _mat
	_step_ms = int(clampf(maxf(0.05, ttl) / float(SAMPLES - 1), STEP_MIN, STEP_MAX) * 1000.0)

func _process(_dt: float) -> void:
	if not is_instance_valid(mesh) or not mesh.is_inside_tree():
		return
	var now = Time.get_ticks_msec()
	var t: Transform3D = mesh.global_transform
	if _hist.is_empty() or now - int(_hist[0][0]) >= _step_ms:
		_hist.push_front([now, t])
		if _hist.size() > SAMPLES - 1:
			_hist.resize(SAMPLES - 1)
	var inv = t.affine_inverse()
	var pos = PackedVector4Array()
	var rot = PackedVector4Array()
	pos.resize(SAMPLES)
	rot.resize(SAMPLES)
	pos[0] = Vector4(0.0, 0.0, 0.0, 0.0) # Probe 0 = jetzt
	rot[0] = Vector4(0.0, 0.0, 0.0, 1.0)
	var count = 1
	for h in _hist:
		var age = (now - int(h[0])) / 1000.0
		if age <= 0.0:
			continue
		var d: Transform3D = inv * (h[1] as Transform3D)
		var q = d.basis.orthonormalized().get_rotation_quaternion()
		pos[count] = Vector4(d.origin.x, d.origin.y, d.origin.z, age)
		rot[count] = Vector4(q.x, q.y, q.z, q.w)
		count += 1
		if count >= SAMPLES:
			break
	_mat.set_shader_parameter("TrailCount", count)
	_mat.set_shader_parameter("TrailPos", pos)
	_mat.set_shader_parameter("TrailRot", rot)
