extends SceneTree

# ====================================================
# Ein Schritt des Exports in einem eigenen Godot-Prozess (Performance-Fahrplan P2f): der Speicher einer Map-Umwandlung
# (mehrere GB) ist mit dem Prozess wieder frei. Gestartet von client_export.gd:
#   godot --headless --path <Projekt> -s res://addons/PWE-Manager/Export/export_job.gd -- --job=<Art> ...
#   --job=map --src=maps/s9/s9.trn2 --root=res://Stock-PWE-Client --written=<Datei>
#       Map samt Gebäuden, Objekten, Effekten, Spawn-Modellen und Kollision umwandeln (ecm_importer.gd import_map);
#       die geschriebenen Dateien kommen zeilenweise nach --written.
#   --job=figuren --root=...    Spielfiguren je Rasse / Geschlecht, ihre Skins, Listen für Ausrüstung und Effekte (client_assets.gd)
#   --job=ausruestung --part=<k> --parts=<n> --root=...   Teil k (ab 0) von n der Ausrüstungs-Liste (Skins, Waffen)
#   --job=effekte --part=<k> --parts=<n> --root=...       Teil k von n der GFX-Liste
#       (P2f2; alle drei schreiben ihre Dateien wie --job=map nach --written)
#   --job=tabellen --root=...   Tabellen, Texte, Lua, Wegekarten in den umgewandelten Speicher (P2f3, client_tables.gd)
#   --job=oberflaeche --part=<gemeinsam|Deu|Eng|Franz> --root=...   Oberfläche: Bilder, Dialoge (fertig gelesen),
#       Texttabellen, Schriften (P2f4, client_ui.gd)
#   --job=klaenge --root=...    Klänge der Figuren, des Clients und der Oberfläche, Musik (P2f5, client_sounds.gd)
#   --job=cleanup
#       Verwaiste Dateien unter res://ECM_Import in den Papierkorb: alte Text-Szenen (.tscn) neben ihrer binären Szene
#       (.scn, P2c) und Shader-Dateien (P1), die keine Szene mehr braucht. Gelöscht wird nur, worauf keine übrige Szene
#       oder Ressource verweist (ResourceLoader.get_dependencies).
# Letzte Zeile "EXPORT-JOB OK ..." bzw. "EXPORT-JOB FEHLER ...", Rückgabewert 0 / 1.
# ====================================================

const Importer = preload("../ECM/ecm_importer.gd")
const Assets = preload("client_assets.gd")
const Tables = preload("client_tables.gd")
const UIConv = preload("client_ui.gd")
const Sounds = preload("client_sounds.gd")
const IMPORT_ROOT = "res://ECM_Import"
const SHADER_DIR = Importer.SHADER_DIR
const RESOURCE_EXT = ["tscn", "scn", "res", "tres"]


func _initialize() -> void:
	var args = {}
	for a in OS.get_cmdline_user_args():
		var kv = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var out: Dictionary
	match str(args.get("job", "")):
		"map": out = _map(args)
		"figuren", "ausruestung", "effekte": out = _assets(args)
		"tabellen", "oberflaeche": out = _tables(args)
		"klaenge": out = _sounds(args)
		"cleanup": out = _cleanup()
		_: out = {"error": "unbekannter Schritt '%s' (--job=map oder --job=cleanup)" % args.get("job", "")}
	if out.has("error"):
		print("EXPORT-JOB FEHLER ", out["error"])
		quit(1)
	else:
		print("EXPORT-JOB OK ", out.get("text", ""))
		quit(0)


func _map(args: Dictionary) -> Dictionary:
	var src = str(args.get("src", ""))
	if src == "":
		return {"error": "--src fehlt"}
	var t0 = Time.get_ticks_msec()
	var importer = Importer.new(str(args.get("root", "res://Stock-PWE-Client")))
	var res = importer.import_map(src)
	if res.has("error"):
		return res
	var written: Array = res.get("written", [])
	var path = str(args.get("written", ""))
	if path != "":
		var f = FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			for w in written:
				f.store_line(str(w))
	var warnings: Array = res.get("warnings", [])
	for w in warnings:
		print("Hinweis: ", w)
	return {"text": "%s: %d ms, %d Dateien, %d Hinweise" % [src.get_file(), Time.get_ticks_msec() - t0, written.size(), warnings.size()]}


func _assets(args: Dictionary) -> Dictionary:
	var t0 = Time.get_ticks_msec()
	var importer = Importer.new(str(args.get("root", "res://Stock-PWE-Client")))
	var assets = Assets.new()
	var part = int(args.get("part", "0"))
	var parts = int(args.get("parts", "1"))
	var res: Dictionary
	match str(args["job"]):
		"figuren": res = assets.figures(importer)
		"ausruestung": res = assets.equipment(importer, part, parts)
		_: res = assets.effects(importer, part, parts)
	assets.collect(importer)
	for w in assets.warnings:
		print("Hinweis: ", w)
	if res.has("error"):
		return res
	var path = str(args.get("written", ""))
	if path != "":
		var f = FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			for w in assets.written:
				f.store_line(str(w))
	return {"text": "%s, %d ms, %d Dateien, %d Hinweise" % [res["text"], Time.get_ticks_msec() - t0, assets.written.size(), assets.warnings.size()]}

func _tables(args: Dictionary) -> Dictionary:
	var t0 = Time.get_ticks_msec()
	var tables = UIConv.new() if str(args["job"]) == "oberflaeche" else Tables.new()
	var root = str(args.get("root", "res://Stock-PWE-Client"))
	var res = tables.convert_part(root, str(args.get("part", ""))) if str(args["job"]) == "oberflaeche" else tables.convert(root)
	for w in tables.warnings:
		print("Hinweis: ", w)
	if res.has("error"):
		return res
	var path = str(args.get("written", ""))
	if path != "":
		var f = FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			for w in tables.written:
				f.store_line(str(w))
	return {"text": "%s, %d ms, %d Hinweise" % [res["text"], Time.get_ticks_msec() - t0, tables.warnings.size()]}

func _sounds(args: Dictionary) -> Dictionary:
	var t0 = Time.get_ticks_msec()
	var sounds = Sounds.new()
	var res = sounds.convert(Importer.new(str(args.get("root", "res://Stock-PWE-Client"))))
	for w in sounds.warnings:
		print("Hinweis: ", w)
	if res.has("error"):
		return res
	var path = str(args.get("written", ""))
	if path != "":
		var f = FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			for w in sounds.written:
				f.store_line(str(w))
	return {"text": "%s, %d ms, %d Dateien, %d Hinweise" % [res["text"], Time.get_ticks_msec() - t0, sounds.written.size(), sounds.warnings.size()]}

func _cleanup() -> Dictionary:
	var files = []
	_collect(IMPORT_ROOT, files)
	var candidates = {}
	var present = {}
	for f in files:
		present[f] = true
	for f in files:
		if f.get_extension() == "tscn" and present.has(f.get_basename() + Importer.SCENE_EXT):
			candidates[f] = true
	var used = {}
	for f in files:
		if candidates.has(f) or not f.get_extension() in RESOURCE_EXT:
			continue
		for d in ResourceLoader.get_dependencies(f):
			var p = d.get_slice("::", 2)
			if p == "":
				var uid = ResourceUID.text_to_id(d.get_slice("::", 0))
				if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
					p = ResourceUID.get_id_path(uid)
			if p != "":
				used[p] = true
	var gone = []
	var kept = 0
	for f in candidates:
		if used.has(f):
			kept += 1
		else:
			gone.append(f)
	var shaders = 0
	for f in files:
		if f.begins_with(SHADER_DIR + "/") and f.get_extension() == "gdshader" and not used.has(f):
			gone.append(f)
			shaders += 1
	var failed = 0
	for f in gone:
		for p in [f, f + ".uid"]:
			if FileAccess.file_exists(p) and OS.move_to_trash(ProjectSettings.globalize_path(p)) != OK:
				failed += 1
				printerr("Nicht in den Papierkorb: ", p)
	var text = "%d Dateien geprüft, %d alte Szenen und %d Shader in den Papierkorb" % [files.size(), gone.size() - shaders, shaders]
	if kept > 0:
		text += ", %d alte Szenen bleiben (noch verwendet)" % kept
	if failed > 0:
		return {"error": text + ", %d ließen sich nicht verschieben" % failed}
	return {"text": text}


func _collect(dir: String, out: Array) -> void:
	var d = DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension() in RESOURCE_EXT or f.get_extension() == "gdshader":
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)
