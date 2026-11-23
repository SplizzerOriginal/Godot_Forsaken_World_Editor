extends RefCounted

# ====================================================
# Ausweichschritt der Autoroute (Bug-Fahrplan B2). Die Wegekarte (Felder von 1 m) kennt dünne Wände neuer Gebäude nicht,
# z.B. die Bude litmodel_2750 am Wiederbelebungspunkt von s9: die Route führt quer durch ihre Seitenwand, die Figur steht.
# Den Streifen davor zu sperren und neu zu suchen endet dort in "kein Weg" (in der Wegekarte war die Wand der einzige
# Ausgang). Darum mit der echten Kollision: Richtungen rund um die Figur, die STEP m frei begehbar sind (test_move, etwas
# angehoben gegen Bodenkontakt und kleine Stufen), von dort eine Route zum Ziel, deren erstes Stück (bis LEG m) ebenfalls
# frei ist - die kürzeste gewinnt.
# find -> {"path": [Figur, Ausweichpunkt, Route ...] (x, Höhe über Gelände, z wie movemap find_path), "length", "dir"} oder {}
# ====================================================

const DIRS = 16
const STEP = 1.2 # m Ausweichschritt
const LIFT = 0.25 # m angehoben prüfen (die Kapsel, 1,52 m, bleibt unter Balken ab ~1,8 m)
const LEG = 2.0 # m: so weit muss das erste Stück der neuen Route frei sein
const REACHED = 0.6 # m: Wegpunkt gilt als erreicht (local_player.gd WAYPOINT_REACHED)


static func find(player: CharacterBody3D, mm, goal: Vector3, dh_from: float, goal_any: bool, dh_to: float) -> Dictionary:
	var s = player.global_position
	var base = player.global_transform
	base.origin += Vector3(0.0, LIFT, 0.0)
	var best = {}
	for k in DIRS:
		var a = TAU * k / DIRS
		var d = Vector3(cos(a), 0.0, sin(a))
		if player.test_move(base, d * STEP):
			continue
		var e = s + d * STEP
		var path: PackedVector3Array = mm.find_path(e, goal, dh_from, goal_any, dh_to)
		if path.size() < 2:
			continue
		var i = 0
		while i < path.size() - 1 and Vector2(path[i].x - e.x, path[i].z - e.z).length() < REACHED:
			i += 1
		var leg = Vector3(path[i].x - e.x, 0.0, path[i].z - e.z).limit_length(LEG)
		var t = base
		t.origin = e + Vector3(0.0, LIFT, 0.0)
		if leg.length() > 0.05 and player.test_move(t, leg):
			continue
		var length = STEP
		for j in range(1, path.size()):
			length += Vector2(path[j].x - path[j - 1].x, path[j].z - path[j - 1].z).length()
		if best.is_empty() or length < float(best["length"]):
			var full = PackedVector3Array([Vector3(s.x, path[0].y, s.z), Vector3(e.x, path[0].y, e.z)])
			full.append_array(path)
			best = {"path": full, "length": length, "dir": d}
	return best
