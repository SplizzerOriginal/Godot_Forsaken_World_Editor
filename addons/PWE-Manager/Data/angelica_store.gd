@tool
extends RefCounted

# ====================================================
# Umgewandelte Spieldaten (Leiste EXPORT, Performance-Fahrplan P2f3): Dateien der Spieldaten als Godot-Ressourcen
# (angelica_blob.gd) unter STORE_DIR, je Datei <Pfad relativ zum Spieldaten-Ordner>.res, dazu das Verzeichnis INDEX
# (table: {Pfad klein: [Ressource, Größe der Quelle]}) und
#   elements.data  je Liste <Pfad>/list_<Nummer>.res, Kopf <Pfad>/meta.res (Version, Listen, IDs je Liste), Gespräche
#                  <Pfad>/talks.res
#                  - angelica_elements.gd lädt nur die Listen, die es braucht
#   Quest-Index    <Pfad von tasks.data>.index.res (angelica_tasks.gd index_all ohne alle Teile zu lesen)
#   Oberfläche     (P2f4) Bilder, Dialoge, Texttabellen, Schriften als Bytes; dazu fertig gelesene Dialoge, Texttabellen und
#                  Dialog-Listen (angelica_ui.gd read_dialog / read_string_table / read_layout) unter dem Schlüssel
#                  <Pfad>#dialog / #stf / #dcf: [Ressource, Größe der Quelle, Stand des Lesers]
# Gleiche Inhalte liegen einmal (Ressource nach MD5: c/<xx>/<MD5>.res). Mehrere Teilverzeichnisse (index*.res: Tabellen,
# Oberfläche je Sprache ...) werden zusammengeführt; jeder Export-Schritt schreibt nur sein eigenes. Ein Sprachteil
# (index_ui_<sprache>.res, Pfade <sprache>/...) lädt erst, wenn ein Pfad dieser Sprache gefragt wird (alle drei zusammen
# kosteten beim Start ~250 ms).
# angelica_vfs.gd fragt zuerst hier (get_bytes, file_exists, file_size). Den Spieldaten-Ordner meldet angelica_files.gd
# (register_root): Pfade werden relativ dazu nachgeschlagen, auch wenn der Ordner im exportierten Spiel woanders liegt.
# Mit den Original-Daten daneben (Editor, Tests) gilt ein Eintrag nur bei gleicher Größe der Quelle (sonst: neu exportieren).
# enabled = false: nur Originale (der Export selbst liest so seine Quellen).
# Pfadverzeichnis (P2f6): alle Ordner und Dateien der Original-Daten (Name in wirklicher Schreibweise, Ordner ja / nein, Größe),
# je Bereich ein Teil unter LISTING_DIR (Bereich: die ersten LISTING_DEPTH Ordner, unter resources/ einer mehr; flache
# Ordner im Teil ""), Übersicht LISTING. Liegt ein gemeldeter Spieldaten-Ordner nicht auf der Platte (exportiertes Spiel
# ohne Original-Daten), beantwortet angelica_vfs.gd Ordnerlisten, Existenz und Größen hieraus (listing_active) - so finden
# resolve / find_game_file die umgewandelten Dateien weiter über ihre Original-Pfade.
# ====================================================

const STORE_DIR = "res://ECM_Import/data"
const INDEX = STORE_DIR + "/index.res" # Teilverzeichnis der Tabellen (P2f3)
const REL_MARK = "\u0001/" # Pfad relativ zum Spieldaten-Ordner in gelesenen Dialogen (relativize / reroot)
const LISTING = STORE_DIR + "/listing.res"
const LISTING_DIR = STORE_DIR + "/listing"
const LISTING_DEPTH = 2
const FORMAT = 1 # Aufbau des Speichers; ein anderer Wert im Verzeichnis = neu umwandeln
const ELEMENTS_META = "meta.res"
const ELEMENTS_TALKS = "talks.res"

static var enabled = true
static var _lock = Mutex.new()
static var _index = null # {Pfad klein: [Ressource, Größe]} oder {}
static var _roots: Array = [] # gemeldete Spieldaten-Ordner (längste zuerst)
static var _lazy = {} # erster Pfadteil (klein, z.B. "deu") -> Teilverzeichnis, noch nicht geladen
static var _listing_parts = null # Bereich -> Ressource
static var _listing_dirs = {} # Ordner relativ, klein -> {Name klein: [Name, ist Ordner, Größe]}
static var _listing_loaded = {} # Bereich -> true
static var _listing_on = {} # Spieldaten-Ordner -> Pfadverzeichnis benutzen?
const LAZY_PREFIX = "index_ui_"
const EAGER_PARTS = ["gemeinsam"]


# Spieldaten-Ordner melden (angelica_files.gd beim Anlegen)
static func register_root(root: String) -> void:
	root = root.trim_suffix("/")
	if root == "":
		return
	_lock.lock()
	if not root in _roots:
		_roots.append(root)
		_roots.sort_custom(func(a, b): return a.length() > b.length())
	_lock.unlock()

# Pfad relativ zum Spieldaten-Ordner, klein; "" außerhalb
static func rel_of(path: String) -> String:
	for r in _roots:
		if path.begins_with(r + "/"):
			return path.substr(r.length() + 1).to_lower()
	return ""

static func _load_index() -> Dictionary:
	if _index == null:
		_lock.lock()
		if _index == null:
			var d = {}
			_lazy = {}
			# ohne Speicher (Projekt vor dem ersten Export) leer, ohne Fehlermeldung
			var names = DirAccess.get_files_at(STORE_DIR) if DirAccess.dir_exists_absolute(STORE_DIR) else PackedStringArray()
			for f in names:
				if not (f.begins_with("index") and f.ends_with(".res")):
					continue
				var part = f.trim_prefix(LAZY_PREFIX).trim_suffix(".res") if f.begins_with(LAZY_PREFIX) else ""
				if part != "" and not part in EAGER_PARTS:
					_lazy[part] = STORE_DIR.path_join(f)
					continue
				_merge_part(d, STORE_DIR.path_join(f))
			_index = d
		_lock.unlock()
	return _index

static func _merge_part(d: Dictionary, path: String) -> void:
	var b = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if b != null and int(b.table.get("format", 0)) == FORMAT:
		d.merge(b.table.get("files", {}), true)

# Eintrag nachschlagen, ein noch nicht geladenes Sprach-Teilverzeichnis vorher laden
# (unter der Sperre: Daten-Threads lesen, während ein Sprachteil hinzukommt)
static func _entry(rel: String) -> Array:
	var idx = _load_index()
	_lock.lock()
	if not _lazy.is_empty():
		var first = rel.get_slice("/", 0)
		if _lazy.has(first):
			_merge_part(idx, _lazy[first])
			_lazy.erase(first)
	var e = idx.get(rel, [])
	_lock.unlock()
	return e

# Verzeichnis neu laden (nach dem Umwandeln)
static func reset() -> void:
	_lock.lock()
	_index = null
	_listing_parts = null
	_listing_dirs = {}
	_listing_loaded = {}
	_listing_on = {}
	_lock.unlock()


# ====================================================
# PFADVERZEICHNIS (P2f6)
# ====================================================
# Bereich eines Ordners (relativ, klein) im Pfadverzeichnis
static func listing_key(rel_dir: String) -> String:
	var parts = rel_dir.split("/", false)
	var k = LISTING_DEPTH + (1 if not parts.is_empty() and parts[0] == "resources" else 0)
	return "/".join(parts.slice(0, k)) if parts.size() >= k else ""

static func _root_for(path: String) -> String:
	for r in _roots:
		if path == r or path.begins_with(r + "/"):
			return r
	return ""

# Fragt das VFS für diesen Pfad das Pfadverzeichnis? (Spieldaten-Ordner fehlt auf der Platte, Verzeichnis vorhanden)
static func listing_active(path: String) -> bool:
	if not enabled:
		return false
	var root = _root_for(path)
	if root == "":
		return false
	if not _listing_on.has(root):
		_lock.lock()
		_listing_on[root] = not DirAccess.dir_exists_absolute(root) and ResourceLoader.exists(LISTING)
		_lock.unlock()
	return _listing_on[root]

# Einträge eines Ordners {Name klein: [Name, ist Ordner, Größe]} oder null (gibt es nicht)
static func listing_dir(path: String):
	var root = _root_for(path)
	if root == "":
		return null
	var rel = "" if path.trim_suffix("/") == root else path.substr(root.length() + 1).trim_suffix("/").to_lower()
	_lock.lock()
	_ensure_listing("")
	_ensure_listing(listing_key(rel))
	var d = _listing_dirs.get(rel)
	_lock.unlock()
	return d

# Eintrag einer Datei / eines Ordners [Name, ist Ordner, Größe] oder []
static func listing_entry(path: String) -> Array:
	var d = listing_dir(path.get_base_dir())
	return d.get(path.get_file().to_lower(), []) if d != null else []

static func _ensure_listing(key: String) -> void:
	if _listing_loaded.has(key):
		return
	_listing_loaded[key] = true
	if _listing_parts == null:
		var t = table(LISTING)
		_listing_parts = t.get("parts", {}) if int(t.get("format", 0)) == FORMAT else {}
	var p = str(_listing_parts.get(key, ""))
	if p != "":
		_listing_dirs.merge(table(p).get("dirs", {}), true)

# Eintrag einer Datei -> [Ressource, Größe der Quelle] oder []
static func lookup(path: String) -> Array:
	if not enabled or _roots.is_empty():
		return []
	var rel = rel_of(path)
	return _entry(rel) if rel != "" else []

static func read(entry: Array) -> PackedByteArray:
	var b = ResourceLoader.load(str(entry[0]), "", ResourceLoader.CACHE_MODE_IGNORE)
	return b.bytes if b != null else PackedByteArray()

static func table(res_path: String) -> Dictionary:
	if not ResourceLoader.exists(res_path):
		return {}
	var b = ResourceLoader.load(res_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return b.table if b != null else {}

# Ressource einer Datei im Speicher (für das Umwandeln)
static func res_path(rel: String) -> String:
	return STORE_DIR.path_join(rel) + ".res"

# Ressource nach Inhalt (MD5 der Bytes): gleiche Dateien der Sprachen liegen nur einmal
static func blob_path(md5: String) -> String:
	return STORE_DIR.path_join("c").path_join(md5.substr(0, 2)).path_join(md5 + ".res")

# Teilverzeichnis eines Export-Schritts
static func index_part(name: String) -> String:
	return STORE_DIR.path_join("index_%s.res" % name)

# Fertig gelesenes Ergebnis zu einer Datei (kind: dialog / stf / dcf) -> [Ressource, Größe der Quelle, Stand] oder []
static func parsed(path: String, kind: String) -> Array:
	if not enabled or _roots.is_empty():
		return []
	var rel = rel_of(path)
	return _entry(rel + "#" + kind) if rel != "" else []

# Pfad unter einem Spieldaten-Ordner -> REL_MARK + relativer Pfad (unverändert, wenn er nicht darunter liegt)
static func relativize(s: String, root: String) -> String:
	return REL_MARK + s.substr(root.length() + 1) if root != "" and s.begins_with(root + "/") else s

# Umkehrung: REL_MARK-Pfad -> Pfad unter dem jetzigen Spieldaten-Ordner
static func reroot(s: String, root: String) -> String:
	return root.path_join(s.substr(REL_MARK.length())) if s.begins_with(REL_MARK) else s

# Ordner von elements.data im Speicher, "" wenn nicht umgewandelt
static func elements_dir(path: String) -> String:
	var e = lookup(path)
	return str(e[0]).get_base_dir() if not e.is_empty() and str(e[0]).ends_with("/" + ELEMENTS_META) else ""

# Quest-Index zu tasks.data, {} wenn nicht umgewandelt
static func tasks_index(path: String) -> Dictionary:
	if not enabled or _roots.is_empty():
		return {}
	var rel = rel_of(path)
	var e = _entry(rel + "#index") if rel != "" else []
	return table(str(e[0])) if not e.is_empty() else {}
