@tool
extends RefCounted

# ====================================================
# Tabellen, Texte und Lua für den Client-Export umwandeln (Leiste EXPORT, Performance-Fahrplan P2f3), aufgerufen von
# export_job.gd --job=tabellen. Ziel: der umgewandelte Speicher (Data/angelica_store.gd, Ressourcen Data/angelica_blob.gd):
#   je Sprache (Deu, Eng, Franz)  alle .lua unter <Sprache>/script, die Quests (tasks.data + Teildateien, task_npc.data)
#                                 samt fertigem Quest-Index, path.data und elements.data (je Liste eine Ressource, Kopf mit
#                                 Version und IDs, Gespräche extra) - jeweils die Dateien, die angelica_tasks.gd /
#                                 angelica_elements.gd locate() für die Sprache nimmt (Eng hat keine eigenen Tabellen)
#   resources/configs             alle Dateien (Statuseffekte, Fertigkeits-Texte, Gegenstands-Texte ...)
#   maps/<Map>                    Wegekarte (movemaps/*), precinct.clt, <Map>.ecwld, <Map>.ecbsd
#   Pfadverzeichnis (P2f6)        alle Ordner und Dateien der Original-Daten (Name, Ordner ja / nein, Größe) in Teilen je
#                                 Bereich (angelica_store.gd LISTING) - das exportierte Spiel findet damit ohne die
#                                 Original-Daten weiter jede Datei über ihren Pfad
# Inkrementell: eine Datei, deren Quelle gleich groß ist wie beim letzten Mal und deren Ressource noch da ist, bleibt.
# Dateien liegen nach Inhalt (Store.blob_path, gleiche Inhalte einmal); das Teilverzeichnis dieses Schritts ist Store.INDEX
# (client_ui.gd erbt von hier und schreibt eigene Teilverzeichnisse).
# Ergebnis {"text"} bzw. {"error"}; warnings / written wie client_assets.gd.
# ====================================================

const Files = preload("../Data/angelica_files.gd")
const VFS = preload("../Data/angelica_vfs.gd")
const Store = preload("../Data/angelica_store.gd")
const Blob = preload("../Data/angelica_blob.gd")
const Elements = preload("../Data/angelica_elements.gd")
const Tasks = preload("../Data/angelica_tasks.gd")
const LANGUAGES = ["Deu", "Eng", "Franz"]
const MAP_FILES = ["precinct.clt"] # dazu <Map>.ecwld, <Map>.ecbsd und movemaps/*

var warnings: Array = []
var written: Array = []
var _files
var _root = ""
var _old = {} # Verzeichnis des letzten Laufs
var _new = {}
var _bytes_written = 0
var _kept = 0
var _shared = 0 # Dateien, deren Inhalt schon im Speicher lag
var _index_path = ""


# Lauf beginnen: Originale lesen, altes Teilverzeichnis laden
func _begin(data_root: String, index_path: String) -> void:
	Store.enabled = false # die Originale lesen, nicht den (alten) Speicher
	_root = data_root.trim_suffix("/")
	_files = Files.new(_root)
	_index_path = index_path
	var old_index = Store.table(index_path)
	_old = old_index.get("files", {}) if int(old_index.get("format", 0)) == Store.FORMAT else {}
	_new = {}

# Teilverzeichnis schreiben -> "" oder Fehler
func _finish() -> String:
	var index = Blob.new()
	index.table = {"format": Store.FORMAT, "files": _new}
	DirAccess.make_dir_recursive_absolute(Store.STORE_DIR)
	var err = ResourceSaver.save(index, _index_path)
	Store.reset()
	Store.enabled = true
	if err != OK:
		return _index_path + " nicht schreibbar"
	written.append(_index_path)
	return ""

func convert(data_root: String) -> Dictionary:
	_begin(data_root, Store.INDEX)
	var n_files = 0
	var seen_elements = {}
	var seen_tasks = {}
	for lang in LANGUAGES:
		var script_dir: String = _files.resolve(lang + "/script")
		if script_dir != "":
			for p in _walk(script_dir):
				if p.get_extension().to_lower() == "lua":
					n_files += _file(p)
		var tasks_path = Tasks.locate(_files, lang)
		if tasks_path != "" and not seen_tasks.has(tasks_path):
			seen_tasks[tasks_path] = true
			n_files += _tasks(tasks_path)
		var el_path = Elements.locate(_files, lang)
		if el_path != "" and not seen_elements.has(el_path):
			seen_elements[el_path] = true
			var err = _elements(el_path)
			if err != "":
				return {"error": err}
			var pd: String = _files.resolve("path.data", el_path.get_base_dir())
			if pd != "":
				n_files += _file(pd)
	var configs: String = _files.resolve("resources/configs")
	if configs != "":
		for p in _walk(configs):
			n_files += _file(p)
	var maps: String = _files.resolve("maps")
	for m in (_files.list_dir(maps)["dirs"] if maps != "" else []):
		var dir = maps.path_join(m)
		for f in MAP_FILES + [m + ".ecwld", m + ".ecbsd"]:
			var p: String = _files.resolve(f, dir)
			if p != "":
				n_files += _file(p)
		var mm: String = _files.resolve("movemaps", dir)
		if mm != "":
			for p in _walk(mm):
				n_files += _file(p)
	var listed = _listing()
	var err = _finish()
	if err != "":
		return {"error": err}
	return {"text": "%d Dateien (%d unverändert, %d gleichen Inhalts), elements.data %d, Quest-Index %d, %.0f MB geschrieben; Pfadverzeichnis %d Dateien in %d Teilen" % [
		n_files, _kept, _shared, seen_elements.size(), seen_tasks.size(), _bytes_written / 1048576.0, listed[0], listed[1]]}

# Pfadverzeichnis aller Original-Dateien schreiben -> [Dateien, Teile]
func _listing() -> Array:
	var parts = {} # Bereich -> {Ordner relativ klein: {Name klein: [Name, ist Ordner, Größe]}}
	var n = [0]
	_list_dir(_root, "", parts, n)
	DirAccess.make_dir_recursive_absolute(Store.LISTING_DIR)
	var map = {}
	for key in parts:
		var res = Store.LISTING_DIR.path_join(str(key).md5_text() + ".res")
		if _save(PackedByteArray(), {"dirs": parts[key]}, res, 0) == OK:
			map[key] = res
	var b = Blob.new()
	b.table = {"format": Store.FORMAT, "parts": map}
	if ResourceSaver.save(b, Store.LISTING) == OK:
		written.append(Store.LISTING)
	else:
		warnings.append(Store.LISTING + " nicht schreibbar")
	return [n[0], map.size()]

func _list_dir(dir: String, rel: String, parts: Dictionary, n: Array) -> void:
	var l = _files.list_dir(dir)
	var entries = {}
	for f in l["files"]:
		entries[str(f).to_lower()] = [str(f), false, _files.file_size(dir.path_join(f))]
		n[0] += 1
	for d in l["dirs"]:
		entries[str(d).to_lower()] = [str(d), true, 0]
	var key = Store.listing_key(rel)
	if not parts.has(key):
		parts[key] = {}
	parts[key][rel] = entries
	for d in l["dirs"]:
		_list_dir(dir.path_join(d), (rel + "/" + str(d).to_lower()) if rel != "" else str(d).to_lower(), parts, n)

# Alle Dateien unter einem Ordner (echt oder im Paket)
func _walk(dir: String) -> Array:
	var out = []
	var l = _files.list_dir(dir)
	for f in l["files"]:
		out.append(dir.path_join(f))
	for d in l["dirs"]:
		out.append_array(_walk(dir.path_join(d)))
	return out

func _rel(path: String) -> String:
	return path.substr(_root.length() + 1) if path.begins_with(_root + "/") else ""

# Eine Datei in den Speicher -> 1 (0 wenn nicht lesbar)
func _file(path: String) -> int:
	var rel = _rel(path)
	if rel == "":
		return 0
	var key = rel.to_lower()
	var size: int = _files.file_size(path)
	var old: Array = _old.get(key, [])
	if not old.is_empty() and int(old[1]) == size and ResourceLoader.exists(str(old[0])):
		_new[key] = old
		_kept += 1
		return 1
	var b: PackedByteArray = _files.get_bytes(path)
	if b.is_empty() and size != 0:
		warnings.append(rel + " nicht lesbar")
		return 0
	var res = Store.blob_path(md5(b))
	if ResourceLoader.exists(res):
		_shared += 1 # gleicher Inhalt schon gespeichert (andere Sprache, anderer Pfad)
	elif _save(b, {}, res, b.size()) != OK:
		return 0
	_new[key] = [res, b.size()]
	return 1

static func md5(b: PackedByteArray) -> String:
	if b.is_empty():
		return "d41d8cd98f00b204e9800998ecf8427e"
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(b)
	return ctx.finish().hex_encode()

func _save(bytes: PackedByteArray, table: Dictionary, res: String, source_size: int) -> int:
	var blob = Blob.new()
	blob.bytes = bytes
	blob.table = table
	blob.source_size = source_size
	DirAccess.make_dir_recursive_absolute(res.get_base_dir())
	var err = ResourceSaver.save(blob, res, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		warnings.append("%s nicht gespeichert (%s)" % [res, error_string(err)])
		return err
	written.append(res)
	_bytes_written += bytes.size()
	return OK

# Quests: Inhaltsverzeichnis, Teildateien, task_npc.data, fertiger Index -> Anzahl Dateien
func _tasks(path: String) -> int:
	var n = _file(path)
	var t = Tasks.new()
	var err = t.open(path, _files)
	if err != "":
		warnings.append(err)
		return n
	for k in t.pack_count:
		n += _file(path + str(k + 1))
	var npc: String = _files.resolve("task_npc.data", path.get_base_dir())
	if npc != "":
		n += _file(npc)
	var rel = _rel(path)
	var key = rel.to_lower() + "#index"
	var res = Store.res_path(rel).trim_suffix(".res") + ".index.res"
	var old: Array = _old.get(key, [])
	var code = Tasks.code_stamp()
	if not old.is_empty() and int(old[1]) == t.export_time and str(old[2] if old.size() > 2 else "") == code \
			and ResourceLoader.exists(res):
		_new[key] = old
		return n
	t.index_all()
	if _save(PackedByteArray(), {"index": t.index, "top": t.top, "export_time": t.export_time, "code": code}, res, 0) == OK:
		_new[key] = [res, t.export_time, code]
	return n

# elements.data: je Liste eine Ressource, Kopf mit Version, Größe / Anzahl, IDs und Gesprächen -> "" oder Fehler
func _elements(path: String) -> String:
	var rel = _rel(path)
	var key = rel.to_lower()
	var dir = Store.STORE_DIR.path_join(rel)
	var meta_path = dir.path_join(Store.ELEMENTS_META)
	var size: int = _files.file_size(path)
	var old: Array = _old.get(key, [])
	if not old.is_empty() and int(old[1]) == size and ResourceLoader.exists(meta_path):
		_new[key] = old
		_kept += 1
		return ""
	var el = Elements.new()
	var err = el.open(path, _files)
	if err != "":
		return "elements.data: " + err
	var lists = []
	var ids = {}
	for l in el.lists:
		var b: PackedByteArray = el.list_bytes(int(l["index"]))
		var n = int(l["count"])
		var rs = int(l["size"])
		var list_ids = PackedInt64Array()
		list_ids.resize(n)
		for i in n:
			list_ids[i] = b.decode_u32(i * rs) if rs >= 4 else 0
		ids[int(l["index"])] = list_ids
		lists.append([rs, n])
		if _save(b, {}, dir.path_join("list_%d.res" % int(l["index"])), b.size()) != OK:
			el.close()
			return "elements.data: Liste %d nicht gespeichert" % int(l["index"])
	var talk = el.talk_bytes()
	var version = el.version
	el.close()
	if _save(talk, {}, dir.path_join(Store.ELEMENTS_TALKS), talk.size()) != OK:
		return "elements.data: Gespräche nicht gespeichert"
	if _save(PackedByteArray(), {"version": version, "lists": lists, "ids": ids}, meta_path, size) != OK:
		return "elements.data: Kopf nicht gespeichert"
	_new[key] = [meta_path, size]
	return ""
