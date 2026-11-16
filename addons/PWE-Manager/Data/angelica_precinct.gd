extends RefCounted

# ====================================================
# Gebiete einer Map: maps/<Map>/precinct.clt (Textform, UTF-16 mit BOM, "Element pricinct file (client
# version)"). Je Gebiet:
#   "Name"
#   ID  Eckpunkte  Markierungen  Priorität  Ziel-Instanz  Musik ...   (eine Zeile ganzer Zahlen)
#   vier Wiederbelebungspunkte   Maske, Instanz, x, y, z
#   Eckpunkte                    x  y  z   (Umriss in x / z)
#   Markierungen, Klänge, Musik  (hier nicht gebraucht)
# Ein Punkt gehört zu dem Gebiet mit dem kleinsten Prioritätswert, das ihn enthält (bei Gleichstand zum
# späteren in der Datei): die ganze Map hat einen großen Wert, Städte und Lager kleine.
# Nutzung: Client (Name der Rückkehrstadt im Stadtportal-Text, GameApi.GetHostTownName der Fertigkeiten-Skripte).
# ====================================================

var precincts: Array = [] # [{id, name, priority, poly: PackedVector2Array (x, z), reborn: [Vector3]}]

static var _num_line = RegEx.create_from_string("^-?\\d+(\\s+-?\\d+)+$")
static var _reborn_line = RegEx.create_from_string("^-?\\d+\\s*,\\s*-?\\d+\\s*,\\s*(-?[\\d.]+)\\s*,\\s*(-?[\\d.]+)\\s*,\\s*(-?[\\d.]+)$")


# files: angelica_files.gd -> "" oder Fehler
func read(files, map_name: String) -> String:
	precincts = []
	var path: String = files.resolve("maps/%s/precinct.clt" % map_name)
	if path == "" or not files.file_exists(path):
		return "precinct.clt fehlt (%s)" % map_name
	var b: PackedByteArray = files.get_bytes(path)
	var text = b.slice(2).get_string_from_utf16() if b.size() > 1 and b[0] == 0xFF and b[1] == 0xFE else files.decode(b)
	parse(text)
	return "" if not precincts.is_empty() else "precinct.clt ohne Gebiete (%s)" % map_name

func parse(text: String) -> void:
	var lines = text.replace("\r", "").split("\n")
	var i = 0
	while i + 5 < lines.size():
		var name_line = lines[i].strip_edges()
		var head = lines[i + 1].strip_edges()
		# Gebietsanfang: "Name", dann eine Zeile ganzer Zahlen, dann vier Wiederbelebungspunkte
		if not (name_line.length() >= 2 and name_line.begins_with("\"") and name_line.ends_with("\"")) \
				or _num_line.search(head) == null or _reborn_line.search(lines[i + 2].strip_edges()) == null:
			i += 1
			continue
		var nums = head.split(" ", false)
		var n_points = int(nums[1]) if nums.size() > 1 else 0
		var reborn = []
		for k in 4:
			var m = _reborn_line.search(lines[i + 2 + k].strip_edges())
			if m != null:
				reborn.append(Vector3(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3))))
		var poly = PackedVector2Array()
		var j = i + 6
		while j < lines.size() and poly.size() < n_points:
			var v = lines[j].strip_edges().split(" ", false)
			if v.size() == 3:
				poly.append(Vector2(float(v[0]), float(v[2])))
			j += 1
		precincts.append({"id": int(nums[0]), "name": name_line.substr(1, name_line.length() - 2),
			"priority": int(nums[3]) if nums.size() > 3 else 0, "poly": poly, "reborn": reborn})
		i = j

# Gebiet eines Punkts (kleinster Prioritätswert) oder {}
func at(x: float, z: float) -> Dictionary:
	var best = {}
	for p in precincts:
		if p["poly"].size() >= 3 and Geometry2D.is_point_in_polygon(Vector2(x, z), p["poly"]) \
				and (best.is_empty() or int(p["priority"]) <= int(best["priority"])):
			best = p
	return best

func name_at(x: float, z: float) -> String:
	return str(at(x, z).get("name", ""))
