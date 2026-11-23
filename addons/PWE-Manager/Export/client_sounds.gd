@tool
extends RefCounted

# ====================================================
# Klänge und Musik für den Client-Export umwandeln (Leiste EXPORT, Performance-Fahrplan P2f5), export_job.gd --job=klaenge:
#   Klänge der Aktions-Ereignisse (101) aller Spielfiguren (Schritte, Angriffe, Zauber, Sammeln ...), feste Klänge der
#   Client-Skripte ("....wav", z.B. der Stufenaufstieg) und die Oberflächen-Klänge (resources/sfx/interface, auch Unter-
#   ordner) -> <wav>_sfx.res (AudioStreamWAV, ecm_importer.gd source_sound)
#   Musik (music/*.ogg) -> res://ECM_Import/music/<Datei>.res (AudioStreamOggVorbis, ecm_importer.gd source_music)
# Die Klänge der GFX entstehen schon mit den GFX (Map-Import, Schritt Effekte), die Umgebungsklänge mit den Maps.
# Ergebnis {"text"} bzw. {"error"}; warnings / written wie client_assets.gd.
# ====================================================

const Importer = preload("../ECM/ecm_importer.gd")
const Assets = preload("client_assets.gd")
const CLIENT_SCRIPTS = "res://game/client"
const INTERFACE = "resources/sfx/interface"

var warnings: Array = []
var written: Array = []


func convert(importer) -> Dictionary:
	var data = Assets.player_data()
	if data.is_empty():
		return {"error": "angelica_player_data.json fehlt"}
	var sounds = {} # Pfad relativ zu sfx\ -> true
	var seen = {}
	for race in data["ecm"]:
		for g in data["ecm"][race]:
			var rel = str(data["ecm"][race][g])
			if seen.has(rel):
				continue
			seen[rel] = true
			var p: String = importer.find_game_file(rel)
			var ecm: Dictionary = importer.read_ecm(p) if p != "" else {}
			var events = Importer.action_events(ecm)
			for a in events:
				for e in events[a]:
					if int(e["type"]) == 101:
						for f in e["files"]:
							sounds[str(f)] = true
	var re = RegEx.create_from_string("\"([^\"]+\\.wav)\"")
	for f in DirAccess.get_files_at(CLIENT_SCRIPTS):
		if f.get_extension() == "gd":
			for m in re.search_all(FileAccess.get_file_as_string(CLIENT_SCRIPTS.path_join(f))):
				sounds[m.get_string(1)] = true
	var iface: String = importer.files.resolve(INTERFACE)
	if iface != "":
		var sfx_root = iface.get_base_dir() # .../sfx
		for p in _walk(importer.files, iface):
			if p.get_extension().to_lower() == "wav":
				sounds[p.substr(sfx_root.length() + 1)] = true
	var done = {}
	var n_snd = 0
	var failed = 0
	for s in sounds:
		var key = str(s).to_lower().replace("\\", "/")
		if done.has(key):
			continue
		done[key] = true
		if importer.source_sound(str(s)) != null:
			n_snd += 1
		else:
			failed += 1
		importer._cache.clear() # die Klänge nicht alle im Speicher halten
	var n_music = 0
	var music: String = importer.files.resolve("music")
	if music != "":
		for f in importer.files.list_dir(music)["files"]:
			if str(f).to_lower().ends_with(".ogg"):
				if importer.source_music(str(f)) != null:
					n_music += 1
				else:
					failed += 1
	warnings.append_array(importer.warnings)
	written.append_array(importer.written)
	return {"text": "%d Klänge (Figuren, Client, Oberfläche), %d Musikstücke, %d nicht umgewandelt" % [n_snd, n_music, failed]}

static func _walk(files, dir: String) -> Array:
	var out = []
	var l = files.list_dir(dir)
	for f in l["files"]:
		out.append(dir.path_join(f))
	for d in l["dirs"]:
		out.append_array(_walk(files, dir.path_join(d)))
	return out
