extends SceneTree

# ====================================================
# Test der Kollision (Bug-Fahrplan B2: Durchfallen in Höhlen, kleine Stufen) ohne Server und ohne importierte Map:
#   godot --headless --path <Projekt> -s res://game/tests/collision_test.gd
# Gebäude-Kollision wie der Client (Plugin angelica_buildings.gd collision_faces: Hüllen der Gebäude-Dateien, die die Map
# nennt), Gelände aus den Höhen des Servers (Server/heightmap.gd, gleich dem Gelände des Clients); die Figur ist die echte
# local_player.gd (Kapsel, Schwerkraft, Stufen).
# Prüft:
#   Hüllen      s9 / s11: alle Gebäude lesbar, Hüllen gezählt; die flache 17 x 17 m Bodenplatte bei der Kindred-Startstadt
#               (s11, Dicke 0) gibt Dreiecke (Server/brushes.gd: Fasen / Ausweiten)
#   Durchfallen je Startgebiet (Zwergenstadt s9, Menschen s9, Kindred s11): auf jedes begehbare Feld der Wegekarte (movemaps,
#               Boden über dem Gelände) eine Figur setzen und fallen lassen - sie muss dort stehen bleiben (höchstens
#               MAX_FALL_SHARE fallen tiefer als 1,5 m; zum Vergleich dasselbe mit der map.bht des Servers)
#   Spawns      Server (npcs.gd) mit der Wegekarte (Server/data/s9/movemaps): Objekte der Zwergenstadt stehen auf dem Stadtboden
#               (einer der Sammelpunkte 21067 auf ~183 m statt am Gelände 160 m), und der Bodenstrahl des Clients (world_npc.gd: ab 0,6 m
#               darüber bis 4 m darunter) trifft für alle Objekte dort einen Boden
#   Stufen      auf einer Platte: 0,3 m und 0,6 m hohe Stufen nimmt die Figur auf der Autoroute, an 1,0 m bleibt sie stehen
# Ende: "KOLLISIONS-TEST OK" (Exit 0) oder "KOLLISIONS-TEST FEHLER" (Exit 1).
# ====================================================

const Brushes = preload("res://addons/PWE-Manager/Server/brushes.gd")
const HeightMap = preload("res://addons/PWE-Manager/Server/heightmap.gd")
const MoveMap = preload("res://addons/PWE-Manager/MAP/angelica_movemap.gd")
const Files = preload("res://addons/PWE-Manager/Data/angelica_files.gd")
const Buildings = preload("res://addons/PWE-Manager/MAP/angelica_buildings.gd")
const Importer = preload("res://addons/PWE-Manager/ECM/ecm_importer.gd")
const LocalPlayer = preload("../client/local_player.gd")
const DATA_ROOT = "res://Stock-PWE-Client"
# Startgebiete [Map, Name, Mitte]: Startpunkte der Startvorlagen (Server/start_roles.json)
const AREAS = [["s9", "Zwergenstadt", Vector3(184.31, 184.5, -171.162)], ["s9", "Menschen", Vector3(-144.556, 101.998, 34.636)],
	["s11", "Kindred", Vector3(207.77, 139.088, 198.776)]]
const RADIUS = 60.0 # m um die Mitte
const STEP = 3 # Felder zwischen den Figuren
const MIN_DH = 1.0 # m: nur Felder, deren Boden so weit über dem Gelände liegt (Brücken, Plattformen, Höhlenböden)
const MAX_FALL_SHARE = 0.02 # höchstens dieser Anteil darf durchfallen (Gelände des Servers und Wegekarte sind nicht ganz genau)
const FLAT_PLATE = Vector3(195.0, 144.2, 162.7) # s11: Bodenplatte ohne Dicke
const FIGURE_HEIGHT = 1.5

var checks = 0
var failures = 0
var _faces = {} # Map -> {faces, buildings, hulls, errors}


func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var imp = Importer.new(DATA_ROOT)
	for m in ["s9", "s11"]:
		var t0 = Time.get_ticks_msec()
		var r: Dictionary = Buildings.new(imp).collision_faces(m)
		_faces[m] = r
		_check("%s: %d Gebäude, %d Hüllen, %d Dreiecke, Fehler %s (%d ms)" % [m, r["buildings"], r["hulls"], r["faces"].size() / 3,
			str(r["errors"].slice(0, 2)), Time.get_ticks_msec() - t0], r["errors"].is_empty() and r["hulls"] > 10000)
	var plate = _plate_triangles()
	_check("s11: flache Bodenplatte bei %s (Dicke 0) gibt Dreiecke: %d" % [FLAT_PLATE, plate], plate > 0)
	for a in AREAS:
		await _drop_area(a[0], a[1], a[2])
	await _spawns()
	await _steps()
	_end()

# Hüllen der Kindred-Stadt, deren Mitte bei FLAT_PLATE liegt -> Dreiecke
func _plate_triangles() -> int:
	var imp = Importer.new(DATA_ROOT)
	var bld = Buildings.new(imp)
	var world = load("res://addons/PWE-Manager/MAP/angelica_world.gd").new(imp)
	var list: Array = world.building_files(imp.find_game_file("maps/s11/s11.trn2"))
	var dir = imp.find_game_dir("litmodels/s11")
	for rel in list:
		var h = bld.read_hulls(dir.path_join(str(rel).replace("\\", "/")))
		if not h is Array:
			continue
		for br in h:
			if (br["center"] as Vector3).distance_to(FLAT_PLATE) < 0.2 and float(br["extents"].y) < 0.01:
				return Brushes.triangles(br).size() / 3
	return -1

func _body(faces: PackedVector3Array) -> StaticBody3D:
	var sb = StaticBody3D.new()
	sb.collision_layer = 1
	var cs = CollisionShape3D.new()
	var sh = ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(faces)
	cs.shape = sh
	sb.add_child(cs)
	root.add_child(sb)
	return sb

# Gelände um c aus den Höhen des Servers als Dreiecksnetz
func _terrain(hm, c: Vector3, r: float) -> StaticBody3D:
	var faces = PackedVector3Array()
	var g = 2.0
	var n = int(r * 2.0 / g) + 2
	var x0 = c.x - r - g
	var z0 = c.z - r - g
	for j in n:
		for i in n:
			var a = Vector3(x0 + i * g, 0, z0 + j * g)
			var b = a + Vector3(g, 0, 0)
			var d = a + Vector3(0, 0, g)
			var e = a + Vector3(g, 0, g)
			a.y = hm.height(a.x, a.z)
			b.y = hm.height(b.x, b.z)
			d.y = hm.height(d.x, d.z)
			e.y = hm.height(e.x, e.z)
			faces.append_array(PackedVector3Array([a, b, e, a, e, d]))
	return _body(faces)

func _drop_area(m: String, label: String, c: Vector3) -> void:
	var maps = JSON.parse_string(FileAccess.get_file_as_string("res://addons/PWE-Manager/Server/maps.json"))["maps"]
	var folder = str(maps[m][0]["folder"])
	var hm = HeightMap.new()
	hm.load_dir("res://addons/PWE-Manager/Server/data/" + folder)
	var files = Files.new(DATA_ROOT)
	var mm = MoveMap.new()
	var err = mm.load(files, files.resolve("maps/%s/movemaps" % m))
	if err != "":
		_check("%s %s: Wegekarte %s" % [m, label, err], false)
		return
	var cells = []
	var c0 = mm.cell_of(c.x - RADIUS, c.z - RADIUS)
	var c1 = mm.cell_of(c.x + RADIUS, c.z + RADIUS)
	for v in range(c0.y, c1.y + 1, STEP):
		for u in range(c0.x, c1.x + 1, STEP):
			for L in mm.layers.size():
				if mm.passable(L, u, v) and mm.dh(L, u, v) >= MIN_DH:
					var xz = mm.world_of(Vector2i(u, v))
					cells.append(Vector3(xz.x, hm.height(xz.x, xz.y) + mm.dh(L, u, v), xz.y))
	var area = AABB(c - Vector3(RADIUS + 5, 300, RADIUS + 5), Vector3(RADIUS * 2 + 10, 600, RADIUS * 2 + 10))
	var near = PackedVector3Array()
	var src: PackedVector3Array = _faces[m]["faces"]
	for i in range(0, src.size(), 3):
		if area.has_point(src[i]) or area.has_point(src[i + 1]) or area.has_point(src[i + 2]):
			near.append(src[i])
			near.append(src[i + 1])
			near.append(src[i + 2])
	var bht = Brushes.new()
	bht.read("res://addons/PWE-Manager/Server/data/%s/map.bht" % folder)
	var old = PackedVector3Array()
	for br in bht.in_box(area):
		old.append_array(Brushes.triangles(br))
	var results = []
	for faces in [near, old]:
		var t = _terrain(hm, c, RADIUS + 5)
		var b = _body(faces)
		var players = []
		for p in cells:
			var lp = LocalPlayer.new()
			lp.setup(Node3D.new(), FIGURE_HEIGHT)
			lp.input_enabled = false
			lp.camera.current = false
			root.add_child(lp)
			lp.global_position = p + Vector3(0, 0.3, 0)
			players.append(lp)
		for k in 45:
			await physics_frame
		var fell = []
		for i in players.size():
			if players[i].global_position.y < cells[i].y - 1.5:
				fell.append(cells[i].snapped(Vector3(0.1, 0.1, 0.1)))
			players[i].queue_free()
		results.append(fell)
		t.queue_free()
		b.queue_free()
		await process_frame
	var share = float(results[0].size()) / maxf(1.0, cells.size())
	_check("%s %s: %d Figuren auf Böden über dem Gelände, durchgefallen %d (%.1f %%; mit der map.bht %d), z.B. %s" % [m, label,
		cells.size(), results[0].size(), share * 100.0, results[1].size(), str(results[0].slice(0, 4))],
		not cells.is_empty() and share <= MAX_FALL_SHARE)

# Spawns des Servers in der Zwergenstadt: mit Wegekarte auf dem Boden der Stadt, Bodenstrahl des Clients trifft
func _spawns() -> void:
	var ps = "res://addons/PWE-Manager/Server/"
	var Npcs = load("res://game/server/npcs.gd")
	var sb = load(ps + "spawn_builder.gd")
	var templates = JSON.parse_string(FileAccess.get_file_as_string(ps + "npc_templates.json"))
	var items = JSON.parse_string(FileAccess.get_file_as_string(ps + "item_templates.json"))
	var mines = {}
	for k in items["mines"]:
		mines[int(k)] = items["mines"][k]
	var dir = sb.server_dir().path_join("data").path_join("s9")
	var hm = HeightMap.new()
	hm.load_dir(dir)
	var mm = MoveMap.new()
	var err = mm.load(Files.new(dir), dir.path_join("movemaps"))
	var nm = Npcs.new("s9", templates, {"next": 1 << 30})
	nm.mine_templates = mines
	nm.movemap = mm if err == "" else null
	nm.load_spawns(load(ps + "npcgen.gd").new().read(sb.npcgen_path("s9")), "s9", hm, 0.0, 12345)
	var c: Vector3 = AREAS[0][2]
	var objs = nm.objects.values().filter(func(o): return Vector2(o["pos"].x - c.x, o["pos"].z - c.z).length() <= 90.0)
	var mine = objs.filter(func(o): return int(o["tid"]) == 21067)
	mine.sort_custom(func(a, b): return float(a["pos"].y) > float(b["pos"].y)) # der auf dem Stadtboden zuerst
	var mine_y = float(mine[0]["pos"].y) if not mine.is_empty() else 0.0
	var area = AABB(c - Vector3(100, 300, 100), Vector3(200, 600, 200))
	var near = PackedVector3Array()
	var src: PackedVector3Array = _faces["s9"]["faces"]
	for i in range(0, src.size(), 3):
		if area.has_point(src[i]) or area.has_point(src[i + 1]) or area.has_point(src[i + 2]):
			near.append(src[i])
			near.append(src[i + 1])
			near.append(src[i + 2])
	var t = _terrain(hm, c, 100.0)
	var b = _body(near)
	await physics_frame
	await physics_frame
	var space = b.get_world_3d().direct_space_state
	var miss = []
	for o in objs:
		var p: Vector3 = o["pos"]
		var q = PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0), p - Vector3(0, 4.0, 0), 1)
		if space.intersect_ray(q).is_empty():
			miss.append("%d %s" % [o["tid"], p.snapped(Vector3(0.1, 0.1, 0.1))])
	_check("Spawns der Zwergenstadt (Wegekarte %s): %d Objekte, Sammelpunkt 21067 auf %.1f m (Gelände %.1f m), Bodenstrahl ohne Treffer %s" % [
		"'" + err + "'", objs.size(), mine_y, hm.height(float(mine[0]["pos"].x), float(mine[0]["pos"].z)) if not mine.is_empty() else 0.0, str(miss)],
		err == "" and not mine.is_empty() and mine_y > 180.0 and miss.is_empty())
	t.queue_free()
	b.queue_free()
	await process_frame

# Platte mit drei Stufen (0,3 / 0,6 / 1,0 m) nebeneinander; je eine Figur läuft per Autoroute darüber
func _steps() -> void:
	var faces = PackedVector3Array()
	faces.append_array(_box(Vector3(-20, -1, -20), Vector3(40, 1, 40)))
	var heights = [0.3, 0.6, 1.0]
	var players = []
	for i in heights.size():
		var x = -8.0 + i * 8.0
		faces.append_array(_box(Vector3(x - 1.5, 0, 2), Vector3(3, heights[i], 6)))
		var lp = LocalPlayer.new()
		lp.setup(Node3D.new(), FIGURE_HEIGHT)
		lp.input_enabled = false
		lp.camera.current = false
		root.add_child(lp)
		lp.global_position = Vector3(x, 0.05, -2)
		players.append(lp)
	var b = _body(faces)
	for k in 5:
		await physics_frame
	for i in players.size():
		var x = -8.0 + i * 8.0
		players[i].follow_path(PackedVector3Array([Vector3(x, 0, 5)]))
	for k in 150:
		await physics_frame
	var ys = players.map(func(p): return snappedf(p.global_position.y, 0.01))
	var zs = players.map(func(p): return snappedf(p.global_position.z, 0.01))
	_check("Stufen 0,3 / 0,6 / 1,0 m: Figuren auf Höhe %s, z %s (0,3 und 0,6 oben, an 1,0 unten stehen geblieben)" % [str(ys), str(zs)],
		absf(ys[0] - 0.3) < 0.1 and absf(ys[1] - 0.6) < 0.1 and ys[2] < 0.2 and zs[2] < 2.0)
	for p in players:
		p.queue_free()
	b.queue_free()
	await process_frame

static func _box(pos: Vector3, size: Vector3) -> PackedVector3Array:
	var bm = BoxMesh.new()
	bm.size = size
	var out = PackedVector3Array()
	var arrays = bm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var off = pos + size * 0.5
	for i in idx:
		out.append(verts[i] + off)
	return out

func _check(what: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("KOLLISIONS-TEST: ", "ok      " if ok else "FEHLER  ", what)

func _end() -> void:
	print("KOLLISIONS-TEST %s (%d Prüfungen)" % ["OK" if failures == 0 else "FEHLER", checks])
	quit(0 if failures == 0 else 1)
