@tool
extends RefCounted

# ====================================================
# Spielfiguren, Ausrüstung und Effekte für den Client-Export umwandeln (Leiste EXPORT, Performance-Fahrplan P2f2), aufgerufen
# von export_job.gd. Dateien so, wie angelica_player.gd / ecm_importer.gd sie zur Laufzeit suchen:
#   figures(importer)   je Rasse / Geschlecht (angelica_player_data.json "ecm") <ecm>_player.scn (Skelett, leerer
#                       AnimationPlayer), <ecm>_player.bin (eingelesene .ecm, Grundaktionen, Pfade) und jede Grundaktion der
#                       .smd als <smd>_player_actions/<Name>.res; als Skins (<ski>_ski.scn) alle Köpfe und Frisuren (die .ski
#                       ihrer Ordner), die Standardkleidung aller Klassen und die Standard-Mode. Schreibt die Listen der
#                       nächsten Schritte: LIST_EQUIP (Rüstungs-Skins mit dem Skelett ihrer Rasse / ihres Geschlechts und Waffen
#                       aus allen EQUIPMENT_ESSENCE models[], dazu die Modelle aller NPC- / Monster-Vorlagen und die Hinweis-
#                       Modelle der Quest-Würfel - P2f6: auch was auf keiner Map steht, baut der Client sonst aus den
#                       Original-Daten) und LIST_GFX (GFX der Aktions-Ereignisse und der .att aller
#                       Figuren - die .att selbst werden dabei als <att>_att.bin gespeichert -, der Statuseffekte und die festen
#                       GFX-Pfade der Client-Skripte).
#   equipment(importer, part, parts)  Teil part (ab 0) von parts der Ausrüstungs-Liste: Skins gegen das umgewandelte Skelett,
#                       Waffen als importierte Szene (ecm_importer.gd import_ecm, mit CoGfx und ihren Aktions-GFX)
#   effects(importer, part, parts)    Teil der GFX-Liste (ecm_importer.gd ensure_gfx)
# Ergebnis {"text": ...} bzw. {"error": ...}; Hinweise und geschriebene Dateien stehen danach in warnings / written (jeder Import
# des Importers setzt seine eigenen Listen zurück, darum hier gesammelt).
# ====================================================

const Player = preload("../ECM/angelica_player.gd")
const Builder = preload("../ECM/angelica_model_builder.gd")
const Importer = preload("../ECM/ecm_importer.gd")
const Elements = preload("../Data/angelica_elements.gd")
const Buffs = preload("../Data/angelica_buffs.gd")
const GfxRefresh = preload("../ECM/gfx_refresh.gd")
const LIST_DIR = "res://Export/lists"
const LIST_EQUIP = LIST_DIR + "/ausruestung.txt"
const LIST_GFX = LIST_DIR + "/effekte.txt"
const CLIENT_SCRIPTS = "res://game/client" # feste GFX-Pfade ("....gfx") in den Client-Skripten
const BUILDER_EVERY = 100 # Skins je Textur-Bauer (danach ist sein Zwischenspeicher frei)
var warnings: Array = []
var written: Array = []

const MODEL_LISTS = {"NPC_ESSENCE": "file_model", "MONSTER_ESSENCE": "file_model", "TASKDICE_ESSENCE": "file_hint_model"}
const EQUIP_FIELDS = {"file_model_male": "m", "file_model_female": "w", "file_model_male_l": "m", "file_model_female_l": "w"}


# Hinweise und Dateien des Importers übernehmen (nach jedem Schritt, bevor der nächste Import sie zurücksetzt)
func collect(importer) -> void:
	warnings.append_array(importer.warnings)
	written.append_array(importer.written)
	importer.warnings = []
	importer.written = []

static func player_data() -> Dictionary:
	var script: Script = Player
	var d = JSON.parse_string(FileAccess.get_file_as_string(script.resource_path.get_base_dir().path_join(Player.DATA_FILE)))
	return d if d is Dictionary else {}


# ====================================================
# FIGUREN
# ====================================================
func figures(importer) -> Dictionary:
	var data = player_data()
	if data.is_empty():
		return {"error": Player.DATA_FILE + " fehlt"}
	var stamp = Player.conv_stamp()
	var figs = {} # Skelett-ECM (relativ) -> {root, sk, bon, ecm, ecm_path, actions}
	var actions = 0
	for race in data["ecm"]:
		for g in data["ecm"][race]:
			var rel: String = data["ecm"][race][g]
			if figs.has(rel):
				continue
			var r = _figure(importer, rel, stamp)
			if r.has("error"):
				_free_figs(figs)
				return {"error": "%s: %s" % [rel.get_file(), r["error"]]}
			figs[rel] = r
			actions += int(r["actions"])
			collect(importer)
	# Skins der Figuren: Köpfe, Frisuren, Standardkleidung, Standard-Mode
	var skins = {} # .ski (wirklicher Pfad) -> Skelett-ECM
	for race in data["ecm"]:
		for g in data["ecm"][race]:
			var rel: String = data["ecm"][race][g]
			for key in ["head", "hair"]:
				var pattern: String = data[key].get(race, {}).get(g, "")
				var dir = importer.find_game_dir(pattern.get_base_dir()) if pattern != "" else ""
				if dir == "":
					continue
				for f in importer.files.list_dir(dir)["files"]:
					if str(f).to_lower().ends_with(".ski"):
						_add_skin(skins, dir.path_join(f), rel)
			for slot in data.get("fashion", {}):
				var p = str(data["fashion"][slot].get(race, {}).get(g, ""))
				if p != "":
					_add_skin(skins, importer.find_game_file(p), rel)
	for key in data.get("default_skins", {}):
		var parts = str(key).split("_")
		if parts.size() != 3:
			continue
		var rel = str(data["ecm"].get(parts[0], {}).get(parts[2], ""))
		for slot in data["default_skins"][key]:
			_add_skin(skins, importer.find_game_file(str(data["default_skins"][key][slot])), rel)
	var builder = null
	var n_skins = 0
	var failed = 0
	for ski_path in skins:
		var fig = figs.get(skins[ski_path], {})
		if fig.is_empty():
			continue
		if builder == null or n_skins % BUILDER_EVERY == 0:
			if builder != null:
				importer.take_builder(builder)
			builder = importer.new_builder()
		var err = convert_skin(importer, builder, ski_path, fig["sk"], fig["bon"], stamp)
		if err != "":
			importer.warn(err)
			failed += 1
		else:
			n_skins += 1
	if builder != null:
		importer.take_builder(builder)
	collect(importer)
	var lists = _write_lists(importer, data, figs)
	collect(importer)
	_free_figs(figs)
	if lists.has("error"):
		return lists
	return {"text": "%d Figuren, %d Aktionen, %d Skins (%d nicht lesbar); Listen: %d Ausrüstung, %d GFX" % [figs.size(), actions,
		n_skins, failed, lists["equip"], lists["gfx"]]}

static func _add_skin(skins: Dictionary, path: String, skeleton_rel: String) -> void:
	if path != "" and skeleton_rel != "" and not skins.has(path):
		skins[path] = skeleton_rel

static func _free_figs(figs: Dictionary) -> void:
	for f in figs.values():
		if f.has("root") and is_instance_valid(f["root"]):
			f["root"].free()

# Eine Figur: Skelett-Szene, Bündel, Grundaktionen -> {root, sk, bon, ecm, ecm_path, actions} oder {"error"}
func _figure(importer, rel: String, stamp: String) -> Dictionary:
	var ecm_path: String = importer.find_game_file(rel)
	if ecm_path == "":
		return {"error": "nicht in den Spieldaten"}
	var ecm: Dictionary = importer.read_ecm(ecm_path)
	if ecm.has("error"):
		return ecm
	var smd_path: String = importer._find_model(ecm["skin_model"], ecm_path, importer._model_roots(ecm_path))
	if smd_path == "":
		return {"error": "Modell " + str(ecm["skin_model"]) + " fehlt"}
	var smd: Dictionary = importer.reader.read_smd(smd_path)
	if smd.has("error"):
		return smd
	var bon_path: String = importer.files.resolve(smd["bon"], smd_path.get_base_dir())
	var bon: Dictionary = importer.reader.read_bon(bon_path) if bon_path != "" else {"error": "Skelett fehlt"}
	if bon.has("error"):
		return bon
	var builder = Builder.new(importer.files, importer.reader, func(_src): return "")
	builder.extra_roots = importer.game_roots()
	var only = smd.duplicate()
	only["skins"] = []
	only["actions"] = []
	var built = builder.build("Player", only, [])
	if built.has("error"):
		return built
	var root: Node3D = built["root"]
	var sk: Skeleton3D = root.get_node("Skeleton3D")
	root.set_meta("ecm_path", ecm_path)
	root.set_meta("smd_path", smd_path)
	root.set_meta(Player.CONV_META, stamp)
	# Grundaktionen; bei gleichen Namen gilt wie in angelica_player.gd smd_actions die letzte
	var base = {}
	for a in smd["actions"]:
		base[a["name"]] = a
	var dir: String = importer.out_path(smd_path, Player.ACTIONS_SUFFIX)
	var seen = {}
	var n = 0
	for name in base:
		var f = Player.action_file(name)
		if seen.has(f):
			importer.warn("Aktion %s: Datei %s doppelt" % [name, f])
			continue
		seen[f] = true
		var lib: AnimationLibrary = builder.build_actions({"path": smd["path"], "tcks": smd["tcks"], "actions": [base[name]]}, bon, sk)
		var names = lib.get_animation_list()
		if names.is_empty():
			continue
		if importer.save_resource(lib.get_animation(names[0]), dir.path_join(f)) == OK:
			n += 1
	importer.take_builder(builder)
	# Skelett-Szene mit AnimationPlayer ohne Bibliothek (angelica_player.gd gibt jeder Figur eine eigene und lädt die Aktionen
	# einzeln; eine mitgespeicherte wäre eine geteilte Unter-Ressource)
	var ap: AnimationPlayer = root.get_node("AnimationPlayer")
	if ap.has_animation_library(""):
		ap.remove_animation_library("")
	var packed = PackedScene.new()
	var err = packed.pack(root)
	if err == OK:
		err = importer.save_resource(packed, importer.out_path(ecm_path, Player.PLAYER_SCENE))
	if err != OK:
		root.free()
		return {"error": "Skelett-Szene nicht gespeichert (%s)" % error_string(err)}
	var bundle_path: String = importer.out_path(ecm_path, Player.PLAYER_BUNDLE)
	var fb = FileAccess.open(bundle_path, FileAccess.WRITE)
	if fb == null:
		root.free()
		return {"error": bundle_path + " nicht schreibbar"}
	# smd_rel relativ zum Spieldaten-Ordner: im exportierten Spiel liegt der woanders (settings.gd data_dir)
	fb.store_var({"ecm": ecm, "smd_path": smd_path, "smd_rel": smd_path.trim_prefix(importer.data_root + "/"),
		"bon_path": bon_path, "base": base.keys(), "conv": stamp})
	fb.close()
	importer.written.append(bundle_path)
	return {"root": root, "sk": sk, "bon": bon, "ecm": ecm, "ecm_path": ecm_path, "actions": n}

# Ein Skin gegen ein Skelett -> <ski>_ski.scn; "" oder Fehler
static func convert_skin(importer, builder, ski_path: String, sk: Skeleton3D, bon: Dictionary, stamp: String) -> String:
	var ski: Dictionary = importer.reader.read_ski(ski_path)
	if ski.has("error"):
		return ski_path.get_file() + ": " + str(ski["error"])
	var mi: MeshInstance3D = builder.build_mesh_instance(ski, sk, bon)
	if mi == null:
		return ski_path.get_file() + ": keine Meshes"
	mi.set_meta("tint_surfaces", Player.tint_surfaces(mi, builder, ski))
	mi.set_meta(Player.CONV_META, stamp)
	mi.skeleton = NodePath("..")
	var packed = PackedScene.new()
	var err = packed.pack(mi)
	if err == OK:
		err = importer.save_resource(packed, importer.out_path(ski_path, Player.SKIN_SCENE))
	mi.free()
	return "" if err == OK else "%s: nicht gespeichert (%s)" % [ski_path.get_file(), error_string(err)]


# ====================================================
# LISTEN
# ====================================================
func _write_lists(importer, data: Dictionary, figs: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(LIST_DIR)
	# Ausrüstung: alle Modelle der EQUIPMENT_ESSENCE (je Pfad einmal, das Skelett der ersten Rasse / des ersten Geschlechts)
	var el = Elements.new()
	# eigener Datei-Zugriff: der des Importers zeigt nach einem Import auf dessen Spielordner (files.root)
	var files = load("res://addons/PWE-Manager/Data/angelica_files.gd").new(importer.data_root)
	var err = el.open(Elements.locate(files, "Deu"), files)
	if err != "":
		return {"error": "elements.data: " + err}
	var equip = {} # Pfad klein -> Zeile
	var li = el.list_of("EQUIPMENT_ESSENCE")
	var i = 0
	while li >= 0:
		var r: Dictionary = el.record(li, i)
		if r.is_empty():
			break
		i += 1
		for m in r.get("models", []):
			for field in EQUIP_FIELDS:
				var id = int(m.get(field, 0))
				if id == 0:
					continue
				var p: String = el.path_of(id)
				var key = p.to_lower().replace("\\", "/")
				if p == "" or equip.has(key):
					continue
				if key.ends_with(".ski"):
					var skel = str(data["ecm"].get(str(int(m.get("race", 0))), {}).get(EQUIP_FIELDS[field], ""))
					if skel != "":
						equip[key] = "ski\t%s\t%s" % [p, skel]
				elif key.ends_with(".ecm"):
					equip[key] = "ecm\t" + p
	# Modelle der NPC- / Monster-Vorlagen und Hinweis-Modelle (Quest-Würfel)
	for type in MODEL_LISTS:
		var ml = el.list_of(type)
		var j = 0
		while ml >= 0:
			var r: Dictionary = el.record(ml, j)
			if r.is_empty():
				break
			j += 1
			var id = int(r.get(MODEL_LISTS[type], 0))
			var p: String = el.path_of(id) if id != 0 else ""
			var key = p.to_lower().replace("\\", "/")
			if p != "" and key.ends_with(".ecm") and not equip.has(key):
				equip[key] = "ecm\t" + p
	el.close()
	var lines: Array = equip.values()
	lines.sort()
	if not _write(LIST_EQUIP, lines):
		return {"error": LIST_EQUIP + " nicht schreibbar"}
	# GFX: Aktions-Ereignisse und .att der Figuren, Statuseffekte, feste GFX des Clients
	var gfx = {}
	for f in figs.values():
		var events = Importer.action_events(f["ecm"])
		for a in events:
			for e in events[a]:
				if int(e["type"]) == 100:
					for file in e["files"]:
						gfx[str(file)] = true
		var points = Importer.attack_points(f["ecm"])
		var atts = {}
		for a in points:
			for pt in points[a]:
				atts[str(pt[1])] = true
		for att in atts:
			for g in Importer.att_gfx(importer.save_att(att)):
				gfx[g] = true
	var buffs = Buffs.new(files, "Deu")
	if buffs.open() == "":
		for key in buffs._gfx:
			for light in buffs._gfx[key]:
				var e = buffs._gfx[key][light]
				if e is Array and not e.is_empty() and str(e[0]) != "":
					gfx[str(e[0])] = true
	var re = RegEx.create_from_string("\"([^\"]+\\.gfx)\"")
	for f in DirAccess.get_files_at(CLIENT_SCRIPTS):
		if f.get_extension() == "gd":
			for m in re.search_all(FileAccess.get_file_as_string(CLIENT_SCRIPTS.path_join(f))):
				gfx[m.get_string(1)] = true
	var glines: Array = []
	var seen = {}
	for g in gfx:
		var k = str(g).to_lower().replace("\\", "/")
		if k.ends_with(".gfx") and not seen.has(k):
			seen[k] = true
			glines.append(str(g))
	glines.sort()
	if not _write(LIST_GFX, glines):
		return {"error": LIST_GFX + " nicht schreibbar"}
	return {"equip": lines.size(), "gfx": glines.size()}

static func _write(path: String, lines: Array) -> bool:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	for l in lines:
		f.store_line(str(l))
	return true

static func read_list(path: String) -> PackedStringArray:
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	return FileAccess.get_file_as_string(path).split("\n", false)

static func slice(lines: PackedStringArray, part: int, parts: int) -> Array:
	var n = lines.size()
	return [n * part / maxi(parts, 1), n * (part + 1) / maxi(parts, 1)]


# ====================================================
# AUSRÜSTUNG / EFFEKTE (je Teil)
# ====================================================
func equipment(importer, part: int, parts: int) -> Dictionary:
	var lines = read_list(LIST_EQUIP)
	if lines.is_empty():
		return {"error": LIST_EQUIP + " fehlt (erst der Schritt Figuren)"}
	var stamp = Player.conv_stamp()
	var r = slice(lines, part, parts)
	var skeletons = {} # Skelett-ECM -> {root, sk, bon} oder {}
	var builder = null
	var n_ski = 0
	var n_ecm = 0
	var failed = 0
	for i in range(r[0], r[1]):
		var cols = lines[i].split("\t")
		var p: String = importer.find_game_file(cols[1]) if cols.size() > 1 else ""
		if p == "":
			importer.warn("Ausrüstung fehlt: " + (cols[1] if cols.size() > 1 else lines[i]))
			failed += 1
			continue
		if cols[0] == "ski" and cols.size() > 2:
			var s = _skeleton(importer, skeletons, cols[2])
			if s.is_empty():
				failed += 1
				continue
			if builder == null or n_ski % BUILDER_EVERY == 0:
				if builder != null:
					importer.take_builder(builder)
				builder = importer.new_builder()
			var err = convert_skin(importer, builder, p, s["sk"], s["bon"], stamp)
			if err != "":
				importer.warn(err)
				failed += 1
			else:
				n_ski += 1
		elif cols[0] == "ecm":
			if builder != null: # Texturen der Skins vor dem Import übernehmen (der setzt die Listen zurück)
				importer.take_builder(builder)
				builder = null
			collect(importer)
			var sp: String = importer.scene_of(p)
			if sp != "" and ResourceLoader.exists(sp): # schon mit einer Map importiert (gleicher Stand des Codes)
				var have = load(sp) as PackedScene
				if have != null and not GfxRefresh.outdated(have):
					n_ecm += 1
					continue
			var res: Dictionary = importer.import_ecm(p)
			if res.has("error"):
				importer.warn(p.get_file() + ": " + str(res["error"]))
				failed += 1
			else:
				n_ecm += 1
			collect(importer)
	if builder != null:
		importer.take_builder(builder)
	collect(importer)
	for s in skeletons.values():
		if s.has("root"):
			s["root"].free()
	return {"text": "Teil %d / %d: %d Skins, %d Waffen, %d nicht umgewandelt" % [part + 1, parts, n_ski, n_ecm, failed]}

# Umgewandeltes Skelett einer Rasse / eines Geschlechts (Schritt Figuren) samt .bon
static func _skeleton(importer, cache: Dictionary, rel: String) -> Dictionary:
	if cache.has(rel):
		return cache[rel]
	var out = {}
	var ecm_path: String = importer.find_game_file(rel)
	var scene_path: String = importer.out_path(ecm_path, Player.PLAYER_SCENE) if ecm_path != "" else ""
	var bundle_path: String = importer.out_path(ecm_path, Player.PLAYER_BUNDLE) if ecm_path != "" else ""
	if scene_path != "" and ResourceLoader.exists(scene_path) and FileAccess.file_exists(bundle_path):
		var f = FileAccess.open(bundle_path, FileAccess.READ)
		var bundle = f.get_var() if f != null else null
		var bon: Dictionary = importer.reader.read_bon(str(bundle["bon_path"])) if bundle is Dictionary else {"error": "Bündel"}
		if not bon.has("error"):
			var root: Node3D = (load(scene_path) as PackedScene).instantiate()
			out = {"root": root, "sk": root.get_node("Skeleton3D"), "bon": bon}
	if out.is_empty():
		importer.warn("Skelett %s nicht umgewandelt (erst der Schritt Figuren)" % rel.get_file())
	cache[rel] = out
	return out

func effects(importer, part: int, parts: int) -> Dictionary:
	var lines = read_list(LIST_GFX)
	if lines.is_empty():
		return {"error": LIST_GFX + " fehlt (erst der Schritt Figuren)"}
	var r = slice(lines, part, parts)
	var failed = 0
	for i in range(r[0], r[1]):
		var err: String = importer.ensure_gfx(lines[i])
		if err != "":
			importer.warn(err)
			failed += 1
		collect(importer)
	return {"text": "Teil %d / %d: %d GFX, %d nicht umgewandelt" % [part + 1, parts, r[1] - r[0] - failed, failed]}
