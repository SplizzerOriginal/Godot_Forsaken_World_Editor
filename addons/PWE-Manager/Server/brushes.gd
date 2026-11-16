@tool
extends RefCounted

# ====================================================
# Kollision des Spielservers je Map (config\<Ordner>\map.bht, CBrushTree / CCDBrush). Dasselbe CCDBrush-Format haben die
# Kollisions-Hüllen am Ende der Gebäude (.bmd, CELBrushBuilding; MAP/angelica_buildings.gd read_hulls -> read_brush).
#   "frtb" (0x62747266), Version 1, Anzahl Brushes, je Brush:
#     A3DAABB (Mitte, Ausdehnung, Min, Max: 4 x Vector3 = 48 Bytes), reserviert (4),
#     Anzahl Seiten, je Seite Normale (3 float), Abstand (float), Fase (bool) = 17 Bytes
#   danach der Suchbaum (Knoten mit Mitte / Ausdehnung in x / z), hier nicht gebraucht.
# Ein Brush ist ein konvexer Körper: Schnitt der Halbräume Normale * p <= Abstand. Fasen-Seiten sind
# zusätzliche Ebenen an Kanten (für glattere Kollision), geometrisch überflüssig.
# convex_points() liefert die Ecken (Godot Geometry3D), daraus ConvexPolygonShape3D; triangles() die
# Außenflächen als Dreiecke - für die ganze Map ein ConcavePolygonShape3D (collision_shape), das baut
# Jolt auch für Brushes, deren konvexe Hülle es ablehnt (fast entartete mit vielen Seiten).
# Koordinaten wie die Spawns und Maps (Spiel = Godot).
# ====================================================

const MAGIC = 0x62747266 # "frtb"
const VERSION = 1
const AABB_SIZE = 48
const SIDE_SIZE = 17
const FACE_EPSILON = 0.01 # Ecke liegt auf der Ebene (Meter)
const FLAT_EPSILON = 0.005 # m: dünner gilt als flach
const SKIP_COLLISION = 0x4 # CHDATA_SKIP_COLLISION
const SKIP_RAYTRACE = 0x8 # CHDATA_SKIP_RAYTRACE
const GROW_STEPS = [0.0, 0.02, 0.05] # m nach außen, wenn die Ebenen keinen Körper bilden (Platten ohne Dicke)

var brushes: Array = [] # [{"center", "extents", "planes": [Plane], "bevels": [bool]}]


# map.bht lesen -> "" oder Fehlertext
func read(path: String) -> String:
	brushes = []
	var b = FileAccess.get_file_as_bytes(path)
	if b.size() < 12 or b.decode_u32(0) != MAGIC:
		return path + ": keine map.bht"
	if b.decode_u32(4) != VERSION:
		return path + ": Version %d unbekannt" % b.decode_u32(4)
	var n = b.decode_s32(8)
	var p = 12
	for i in n:
		var r = read_brush(b, p)
		if r[0] == null:
			return path + ": endet vorzeitig (Brush %d)" % i
		brushes.append(r[0])
		p = r[1]
	return ""

# Ein CCDBrush ab p (CCDBrush::Load: A3DAABB, Flags, Anzahl Seiten, je Seite Normale / Abstand / Fase) -> [Brush, Ende]
# Flags (ConvexHullData.h CHDATA_*): 0x2 NPCs kommen nicht durch, 0x4 SKIP_COLLISION (beim Laufen ignoriert, CELBrushBuilding::
# TraceWithBrush), 0x8 SKIP_RAYTRACE (Strahlen gehen durch; Gebäude "nur Kollision"), 0x10 SKIP_CAMERA
# bzw. [null, -1], wenn die Daten nicht reichen
static func read_brush(b: PackedByteArray, p: int) -> Array:
	if p + AABB_SIZE + 8 > b.size():
		return [null, -1]
	var br = {"center": _vec(b, p), "extents": _vec(b, p + 12), "planes": [], "bevels": [], "flags": b.decode_u32(p + AABB_SIZE)}
	p += AABB_SIZE + 4
	var sides = b.decode_s32(p)
	p += 4
	if sides < 0 or p + sides * SIDE_SIZE > b.size():
		return [null, -1]
	for s in sides:
		br["planes"].append(Plane(_vec(b, p), b.decode_float(p + 12)))
		br["bevels"].append(b.decode_u8(p + 16) != 0)
		p += SIDE_SIZE
	return [br, p]

# Ecken eines Brushes (leer, wenn die Ebenen keinen Körper bilden)
static func convex_points(brush: Dictionary) -> PackedVector3Array:
	return _solid(brush)[1]

# Ebenen und Ecken des Körpers: erst die Ebenen ohne Fasen; bilden die keinen Körper (flache Platten ohne Dicke, z.B. die
# 17 x 17 m Bodenplatte bei der Kindred-Startstadt in s11), dieselben um GROW_STEPS nach außen geschoben; erst danach alle
# Ebenen (bei manchen Hüllen schließen erst die "Fasen" den Körper - bei flachen Platten schneiden sie dagegen zu viel ab)
# -> [Ebenen, Ecken]
static func _solid(brush: Dictionary) -> Array:
	var sides: Array[Plane] = []
	for i in brush["planes"].size():
		if not brush["bevels"][i]:
			sides.append(brush["planes"][i])
	for set in [sides, brush["planes"]]:
		for grow in GROW_STEPS:
			var planes: Array[Plane] = []
			for pl in set:
				planes.append(Plane(pl.normal, pl.d + grow))
			var pts = Geometry3D.compute_convex_mesh_points(planes)
			if pts.size() >= 4 and not _flat(pts, planes):
				return [planes, pts]
	return [sides, PackedVector3Array()]

# Ist der Körper flach? Dicke = Spanne der Ecken entlang der Normale einer seiner Ebenen (bei Platten ohne Dicke liefert
# compute_convex_mesh_points nur ein flaches, oft unvollständiges Stück)
static func _flat(pts: PackedVector3Array, planes: Array) -> bool:
	for pl in planes:
		var lo = INF
		var hi = -INF
		for p in pts:
			var d = pl.normal.dot(p)
			lo = minf(lo, d)
			hi = maxf(hi, d)
		if hi - lo < FLAT_EPSILON:
			return true
	return false

# Außenflächen eines Brushes als Dreiecksliste (je Ebene die Ecken darauf, im Kreis sortiert, als
# Fächer; Reihenfolge so, dass die Normale nach außen zeigt)
static func triangles(brush: Dictionary) -> PackedVector3Array:
	var out = PackedVector3Array()
	var solid = _solid(brush)
	var pts: PackedVector3Array = solid[1]
	if pts.size() < 4:
		return out
	for pl in solid[0]:
		var face = []
		for p in pts:
			if absf(pl.distance_to(p)) < FACE_EPSILON:
				face.append(p)
		if face.size() < 3:
			continue
		var c = Vector3.ZERO
		for p in face:
			c += p
		c /= face.size()
		var u = (face[0] - c).normalized()
		var v = pl.normal.cross(u)
		face.sort_custom(func(a, b): return atan2((a - c).dot(v), (a - c).dot(u)) < atan2((b - c).dot(v), (b - c).dot(u)))
		for k in range(1, face.size() - 1):
			out.append(face[0])
			out.append(face[k + 1])
			out.append(face[k])
	return out

# Kollision aller Brushes als ein Dreiecksnetz (beide Seiten)
func collision_shape() -> ConcavePolygonShape3D:
	var faces = PackedVector3Array()
	for br in brushes:
		faces.append_array(triangles(br))
	var shape = ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	return shape

# Brushes, deren Box die gegebene Box schneidet (z.B. Umgebung eines Spielers)
func in_box(box: AABB) -> Array:
	var out = []
	for br in brushes:
		if AABB(br["center"] - br["extents"], br["extents"] * 2.0).intersects(box):
			out.append(br)
	return out

static func _vec(b: PackedByteArray, p: int) -> Vector3:
	return Vector3(b.decode_float(p), b.decode_float(p + 4), b.decode_float(p + 8))
