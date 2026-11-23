@tool
extends "client_tables.gd"

# ====================================================
# Oberfläche für den Client-Export umwandeln (Leiste EXPORT, Performance-Fahrplan P2f4), aufgerufen von export_job.gd
# --job=oberflaeche --part=<Teil>; Teile PARTS, jeder mit eigenem Teilverzeichnis im Speicher (Store.index_part):
#   gemeinsam   resources/surfaces (Bilder, wenn die Sprache eins nicht hat), resources/interfaces, font/ - die Schriften dazu
#               als fertige FontFile unter FONT_DIR (angelica_ui_builder.gd lädt sie von dort)
#   Deu / Eng / Franz   <Sprache>/surfaces und <Sprache>/interfaces als Bytes, dazu jeder Dialog (.xml), jede Texttabelle
#               (.stf) und Dialog-Liste (.dcf) fertig gelesen (angelica_ui.gd parse_*, Pfade relativ: map_paths)
# Bilder bleiben ihre Original-Bytes: fertige Texturen (PortableCompressedTexture2D) luden nicht schneller (HUD 20 Dialoge
# 583 statt 541 ms), das Dekodieren der 484 HUD-Bilder kostet zusammen ~12 ms. Gleiche Bilder der Sprachen liegen einmal.
# ====================================================

const UI = preload("../UI-XML/angelica_ui.gd")
const FONT_DIR = "res://ECM_Import/font" # wie angelica_ui_builder.gd FONT_DIR
const PARTS = ["gemeinsam", "Deu", "Eng", "Franz"]
const PARSED = {"xml": "dialog", "stf": "stf", "dcf": "dcf"}

var _parsed = 0
var _fonts = 0


func convert_part(data_root: String, part: String) -> Dictionary:
	if not part in PARTS:
		return {"error": "unbekannter Teil '%s' (%s)" % [part, ", ".join(PARTS)]}
	_begin(data_root, Store.index_part("ui_" + part.to_lower()))
	var n = 0
	if part == "gemeinsam":
		for sub in ["resources/surfaces", "resources/interfaces", "font"]:
			var dir: String = _files.resolve(sub)
			if dir != "":
				for p in _walk(dir):
					n += _file(p)
		_save_fonts()
	else:
		var ui = UI.new(_root, part)
		for sub in ["surfaces", "interfaces"]:
			var dir: String = _files.resolve(part + "/" + sub)
			if dir == "":
				continue
			for p in _walk(dir):
				n += _file(p)
				var kind = PARSED.get(p.get_extension().to_lower(), "")
				if sub == "interfaces" and kind != "":
					_parsed_entry(ui, p, kind)
	var err = _finish()
	if err != "":
		return {"error": err}
	return {"text": "%s: %d Dateien (%d unverändert, %d gleichen Inhalts), %d gelesen, %d Schriften, %.0f MB geschrieben" % [
		part, n, _kept, _shared, _parsed, _fonts, _bytes_written / 1048576.0]}

# Fertig gelesenes Ergebnis einer Oberflächen-Datei (Dialog, Texttabelle, Dialog-Liste)
func _parsed_entry(ui, path: String, kind: String) -> void:
	var rel = _rel(path)
	if rel == "":
		return
	var key = rel.to_lower() + "#" + kind
	var size: int = _files.file_size(path)
	var code = UI.code_stamp()
	var res = Store.STORE_DIR.path_join("parsed").path_join(rel) + "." + kind + ".res"
	var old: Array = _old.get(key, [])
	if not old.is_empty() and int(old[1]) == size and str(old[2] if old.size() > 2 else "") == code and ResourceLoader.exists(res):
		_new[key] = old
		return
	var data
	match kind:
		"dialog":
			data = ui.parse_dialog(path)
			if not data.is_empty():
				UI.map_paths(data, _root, true)
		"stf":
			data = ui.parse_string_table(path)
		_:
			data = UI.map_paths(ui.parse_layout(path), _root, true)
	if _save(PackedByteArray(), {"data": data}, res, size) == OK:
		_new[key] = [res, size, code]
		_parsed += 1

# Schriften als FontFile (angelica_ui_builder.gd _font sucht FONT_DIR/<Name>.res)
func _save_fonts() -> void:
	var dir: String = _files.resolve("font")
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(FONT_DIR)
	for f in _files.list_dir(dir)["files"]:
		if not str(f).to_lower().ends_with(".ttf"):
			continue
		var b: PackedByteArray = _files.get_bytes(dir.path_join(f))
		if b.is_empty():
			warnings.append(str(f) + " nicht lesbar")
			continue
		var font = FontFile.new()
		font.data = b
		var dest = FONT_DIR.path_join(str(f).get_basename() + ".res")
		if ResourceSaver.save(font, dest) == OK:
			written.append(dest)
			_fonts += 1
		else:
			warnings.append(dest + " nicht gespeichert")
