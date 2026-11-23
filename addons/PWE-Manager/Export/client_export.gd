@tool
extends Node

# ====================================================
# "Client Export for Linux" (Leiste EXPORT, Performance-Fahrplan P2f). Schritte, jeder in einem eigenen Godot-Prozess
# (der Speicher einer Map-Umwandlung ist danach wieder frei), immer nur einer zur Zeit:
#   1. Maps: jede Map der Spieldaten (maps/<Name>/<Name>.trn2) mit export_job.gd --job=map umwandeln. Übersprungen wird,
#      was schon mit dem jetzigen Code umgewandelt ist (Stempel in STATE_FILE; "alles neu" wandelt alles um).
#   1b. Figuren (P2f2): export_job.gd --job=figuren (Skelette, Aktionen, Köpfe / Frisuren / Standardkleidung, Listen), danach
#      die Listen in Teilen: --job=ausruestung (je PART_EQUIP Rüstungs-Skins / Waffen) und --job=effekte (je PART_GFX GFX);
#      jeder Teil hat seinen Stempel (Code + Liste), fertige Teile überspringt der nächste Lauf
#   1c. Tabellen (P2f3): export_job.gd --job=tabellen - Lua, Quests samt Index, elements.data (je Liste), path.data,
#      Konfigurationen, Wegekarten in den umgewandelten Speicher (Data/angelica_store.gd); unveränderte Dateien bleiben
#   1d. Oberfläche (P2f4): export_job.gd --job=oberflaeche in 4 Teilen (gemeinsam, Deu, Eng, Franz) - Bilder, Dialoge
#      (fertig gelesen), Texttabellen, Dialog-Listen, Schriften; Stempel samt Stand des Dialog-Lesers (angelica_ui.gd)
#   1e. Klänge (P2f5): export_job.gd --job=klaenge - Klänge der Figuren, des Clients und der Oberfläche, Musik
#   2. Aufräumen: export_job.gd --job=cleanup (alte .tscn neben .scn, verwaiste Shader-Dateien -> Papierkorb)
#   3. Export: Vorgabe PRESET in export_presets.cfg anlegen, falls sie fehlt, dann
#      godot --headless --path <Projekt> --export-release PRESET res://Export/Client-Linux/PWE-Client.x86_64
# Speichergrenze (options.ram_gb): ein Schritt startet erst, wenn so viel Speicher frei ist, und wird abgebrochen, wenn
# sein Prozess mehr belegt (/proc/<pid>/status VmRSS). Abbrechen beendet den laufenden Prozess; fertige Maps bleiben
# im Stempel, der nächste Lauf macht dort weiter. Ausgaben der Prozesse: res://Export/logs/.
# Noch liest der exportierte Client Oberfläche, Texte, Tabellen und Klänge aus den Original-Paketen (Ordner
# Stock-PWE-Client neben dem Programm, settings.gd); die Umwandlung auch dieser Daten folgt in P2f2 - P2f6.
# Benutzt von export_panel.gd (Editor) und export_cli.gd (Kommandozeile).
# ====================================================

signal line(text: String) # eine Zeile für das Protokoll
signal progress(fraction: float, text: String)
signal finished(ok: bool, summary: String)

const PLUGIN = "res://addons/PWE-Manager/"
const JOB = PLUGIN + "Export/export_job.gd"
const OUT_DIR = "res://Export"
const STATE_FILE = OUT_DIR + "/client_linux.json"
const LOG_DIR = OUT_DIR + "/logs"
const BUILD_DIR = OUT_DIR + "/Client-Linux"
const BINARY = "PWE-Client.x86_64"
const PRESET = "PWE-Client Linux"
const PRESETS_FILE = "res://export_presets.cfg"
const IMPORT_ROOT = "res://ECM_Import"
# Was nicht ins Spiel gehört (Ordner mit .gdignore erfasst Godot ohnehin nicht)
const EXCLUDE = "Stock-PWE-Client/*, Stock-PWE-Server/*, GFX_Load/*, Export/*, addons/PWE-Manager/Docs/*, addons/PWE-Manager/tools/*"
# Dateien ohne Godot-Ressource, die Client und Plugin-Leser zur Laufzeit lesen (GBK-Tabelle, Server-Daten der Maps, eigene
# Dialoge des Spiels game/client/ui/*.xml)
const INCLUDE = "*.json, *.bin, *.data, *.prmap, *.pdhmap, *.hmap, *.bht, *.cfg, *.txt, *.xml"
# Code, von dem das Ergebnis einer Map-Umwandlung abhängt (Leisten / Docks nicht)
const STAMP_DIRS = ["ECM", "GFX", "MAP", "Data"]
const STAMP_FILES = ["Server/spawn_builder.gd", "Server/npcgen.gd", "Server/brushes.gd", "Export/export_job.gd", "Export/client_assets.gd",
	"Export/client_tables.gd", "Export/client_ui.gd", "Export/client_sounds.gd"]
const WEIGHT_SOUNDS = 1.0
const UIConv = preload("client_ui.gd")
const WEIGHT_UI = 1.5
const WEIGHT_TABLES = 2.0
const Assets = preload("client_assets.gd")
const PART_EQUIP = 400 # Einträge der Ausrüstungs-Liste je Prozess
const PART_GFX = 300 # GFX je Prozess
const WEIGHT_FIGURES = 2.0
const WEIGHT_PART = 1.0
const STAMP_SKIP = ["_panel.gd", "_dock.gd", "gfx_buttons.gd"]
const WEIGHT_MAP = 1.0
const WEIGHT_CLEANUP = 0.5
const WEIGHT_EXPORT = 3.0
const POLL = 0.25 # s zwischen zwei Blicken auf den Prozess
const RAM_RECHECK = 2.0 # s zwischen zwei Blicken auf den freien Speicher

var options = {
	"root": "res://Stock-PWE-Client", # Spieldaten
	"maps": [], # nur diese Maps (Namen wie "s9"), leer = alle
	"force": false, # alles neu umwandeln
	"ram_gb": 12.0,
	"assets": true, # Figuren, Ausrüstung, Effekte (P2f2)
	"tables": true, # Tabellen, Texte, Lua (P2f3)
	"ui": true, # Oberfläche (P2f4)
	"sounds": true, # Klänge und Musik (P2f5)
	"cleanup": true,
	"export": true,
}
var running = false

var _jobs: Array = [] # {kind, name, label, weight, args, src}
var _index = -1
var _pid = -1
var _stdio: FileAccess
var _stderr: FileAccess
var _log: FileAccess
var _out = "" # Ausgabe des laufenden Prozesses (für die Ergebniszeile)
var _peak = 0 # höchster VmRSS des laufenden Prozesses (Bytes)
var _job_t0 = 0
var _run_t0 = 0
var _wait_ram = false
var _poll_left = 0.0
var _state = {}
var _stamp = ""
var _failed: Array = []
var _skipped = 0
var _done_weight = 0.0
var _total_weight = 0.0
var _map_ms: Array = [] # Dauer der umgewandelten Maps (Restzeit)
var _cancel = false
var _skipped_assets: Array = [] # übersprungene (aktuelle) Figuren / Teile
var _parts_pending = false # Teile von Ausrüstung / Effekte noch einzuplanen


# ====================================================
# START / ABBRUCH
# ====================================================
func start(opts: Dictionary = {}) -> String:
	if running:
		return "läuft schon"
	options.merge(opts, true)
	_stamp = code_stamp()
	_state = _load_state()
	var maps = list_maps(str(options["root"]))
	if maps.is_empty():
		return "keine Maps unter %s/maps" % options["root"]
	var wanted: Array = options["maps"]
	_jobs = []
	_skipped = 0
	_skipped_assets = []
	_parts_pending = false
	for m in maps:
		if not wanted.is_empty() and not m["name"] in wanted:
			continue
		if not bool(options["force"]) and map_current(m["name"]):
			_skipped += 1
			continue
		_jobs.append({"kind": "map", "name": m["name"], "src": m["src"], "weight": WEIGHT_MAP,
			"label": "Map " + m["name"], "args": ["--job=map", "--src=" + m["src"], "--root=" + str(options["root"]),
			"--written=" + ProjectSettings.globalize_path(LOG_DIR.path_join("map_%s_dateien.txt" % m["name"]))]})
	if bool(options["assets"]):
		if not bool(options["force"]) and str(_state.get("figuren", "")) == _stamp and FileAccess.file_exists(Assets.LIST_EQUIP) \
				and FileAccess.file_exists(Assets.LIST_GFX):
			_skipped_assets = ["Figuren"]
			_parts_pending = true # Teile gleich nach den Maps einplanen (Listen liegen schon da)
		else:
			_jobs.append({"kind": "figuren", "name": "figuren", "weight": WEIGHT_FIGURES, "label": "Figuren",
				"args": ["--job=figuren", "--root=" + str(options["root"]),
				"--written=" + ProjectSettings.globalize_path(LOG_DIR.path_join("figuren_dateien.txt"))]})
	if bool(options["tables"]):
		if not bool(options["force"]) and str(_state.get("tabellen", "")) == _stamp:
			_skipped_assets.append("Tabellen")
		else:
			_jobs.append({"kind": "tabellen", "name": "tabellen", "weight": WEIGHT_TABLES, "label": "Tabellen",
				"args": ["--job=tabellen", "--root=" + str(options["root"]),
				"--written=" + ProjectSettings.globalize_path(LOG_DIR.path_join("tabellen_dateien.txt"))]})
	if bool(options["ui"]):
		var ui_stamp = "%s_%s" % [_stamp, UIConv.UI.code_stamp()]
		for part in UIConv.PARTS:
			var name = "oberflaeche_" + part.to_lower()
			if not bool(options["force"]) and str(_state.get(name, "")) == ui_stamp:
				_skipped_assets.append("Oberfläche " + part)
				continue
			_jobs.append({"kind": "oberflaeche", "name": name, "weight": WEIGHT_UI, "label": "Oberfläche " + part,
				"stamp": ui_stamp, "args": ["--job=oberflaeche", "--part=" + part, "--root=" + str(options["root"]),
				"--written=" + ProjectSettings.globalize_path(LOG_DIR.path_join("%s_dateien.txt" % name))]})
	if bool(options["sounds"]):
		if not bool(options["force"]) and str(_state.get("klaenge", "")) == _stamp:
			_skipped_assets.append("Klänge")
		else:
			_jobs.append({"kind": "klaenge", "name": "klaenge", "weight": WEIGHT_SOUNDS, "label": "Klänge",
				"args": ["--job=klaenge", "--root=" + str(options["root"]),
				"--written=" + ProjectSettings.globalize_path(LOG_DIR.path_join("klaenge_dateien.txt"))]})
	if bool(options["cleanup"]):
		_jobs.append({"kind": "cleanup", "name": "aufraeumen", "weight": WEIGHT_CLEANUP, "label": "Aufräumen",
			"args": ["--job=cleanup"]})
	if bool(options["export"]):
		_jobs.append({"kind": "export", "name": "export", "weight": WEIGHT_EXPORT, "label": "Godot-Export Linux"})
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	_write_gdignore()
	_total_weight = 0.0
	for j in _jobs:
		_total_weight += float(j["weight"])
	_done_weight = 0.0
	_failed = []
	_map_ms = []
	_cancel = false
	if _parts_pending:
		_parts_pending = false
		var at = 0
		while at < _jobs.size() and _jobs[at]["kind"] == "map":
			at += 1
		_insert_parts(at)
	_index = -1
	_run_t0 = Time.get_ticks_msec()
	running = true
	var n_maps = _jobs.filter(func(j): return j["kind"] == "map").size()
	line.emit("Client-Export Linux: %d Maps umwandeln, %d schon aktuell; Speichergrenze %.1f GB; Stand des Codes %s"
		% [n_maps, _skipped, float(options["ram_gb"]), _stamp.left(8)])
	if not _skipped_assets.is_empty():
		line.emit("Schon aktuell: " + ", ".join(_skipped_assets))
	_next()
	return ""

func cancel() -> void:
	if not running:
		return
	_cancel = true
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	line.emit("Abgebrochen - fertige Maps bleiben, der nächste Lauf macht weiter.")
	_finish(false, "abgebrochen")


# ====================================================
# ABLAUF
# ====================================================
func _process(delta: float) -> void:
	if not running:
		return
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = POLL
	if _wait_ram:
		_poll_left = RAM_RECHECK
		_try_start()
		return
	if _pid <= 0:
		return
	_pump()
	var rss = _rss(_pid)
	_peak = max(_peak, rss)
	var limit = int(float(options["ram_gb"]) * 1073741824.0)
	if rss > limit:
		OS.kill(_pid)
		_pump()
		_job_done(false, "Speichergrenze überschritten (%.1f GB von %.1f GB)" % [rss / 1073741824.0, float(options["ram_gb"])])
		return
	_report_running()
	if not OS.is_process_running(_pid):
		_pump()
		var code = OS.get_process_exit_code(_pid)
		_job_done(code == 0, _result_line(code))

func _next() -> void:
	_index += 1
	if _cancel:
		return
	if _index >= _jobs.size():
		var ok = _failed.is_empty()
		var secs = (Time.get_ticks_msec() - _run_t0) / 1000.0
		var summary = ("fertig in %s" % _fmt_time(secs)) if ok else ("%d Schritte fehlgeschlagen: %s" % [_failed.size(), ", ".join(_failed)])
		if ok and bool(options["export"]):
			summary += " - " + ProjectSettings.globalize_path(BUILD_DIR.path_join(BINARY))
		_finish(ok, summary)
		return
	var job: Dictionary = _jobs[_index]
	if job["kind"] == "export" and not _failed.is_empty():
		line.emit("Godot-Export übersprungen: erst die fehlgeschlagenen Schritte beheben (%s)." % ", ".join(_failed))
		_failed.append("Export")
		_done_weight += float(job["weight"])
		_next()
		return
	if job["kind"] == "export":
		var err = ensure_preset()
		if err != "":
			_job_done(false, err)
			return
		DirAccess.make_dir_recursive_absolute(BUILD_DIR)
		job["args_full"] = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--export-release", PRESET,
			ProjectSettings.globalize_path(BUILD_DIR.path_join(BINARY))]
	else:
		job["args_full"] = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", JOB, "--"] + job["args"]
	_try_start()

# Startet den Schritt, sobald genug Speicher frei ist
func _try_start() -> void:
	var job: Dictionary = _jobs[_index]
	var need = float(options["ram_gb"]) * 1073741824.0
	var avail = float(available_memory())
	if avail < need and job["kind"] != "cleanup":
		if not _wait_ram:
			line.emit("%s wartet auf freien Speicher: %.1f GB frei, %.1f GB nötig" % [job["label"], avail / 1073741824.0, need / 1073741824.0])
		_wait_ram = true
		progress.emit(_fraction(0.0), "%s: warte auf freien Speicher (%.1f / %.1f GB)" % [job["label"], avail / 1073741824.0, need / 1073741824.0])
		return
	_wait_ram = false
	var info = OS.execute_with_pipe(OS.get_executable_path(), PackedStringArray(job["args_full"]), false)
	if info.is_empty():
		_job_done(false, "Prozess ließ sich nicht starten")
		return
	_pid = int(info["pid"])
	_stdio = info["stdio"]
	_stderr = info["stderr"]
	if job["kind"] == "map" and _state.get("maps", {}).has(job["name"]):
		# halb geschriebene Map (Abbruch, Speichergrenze) darf nicht als aktuell gelten
		_state["maps"].erase(job["name"])
		_save_state()
	elif job["kind"] == "figuren" and _state.has("figuren"):
		_state.erase("figuren")
		_save_state()
	elif job["kind"] == "tabellen" and _state.has("tabellen"):
		_state.erase("tabellen")
		_save_state()
	elif job["kind"] == "klaenge" and _state.has("klaenge"):
		_state.erase("klaenge")
		_save_state()
	elif job["kind"] == "oberflaeche" and _state.has(job["name"]):
		_state.erase(job["name"])
		_save_state()
	elif job["kind"] in ["ausruestung", "effekte"] and _state.get("parts", {}).has(job["name"]):
		_state["parts"].erase(job["name"])
		_save_state()
	_log = FileAccess.open(LOG_DIR.path_join("%s.log" % job["name"]), FileAccess.WRITE)
	_out = ""
	_peak = 0
	_job_t0 = Time.get_ticks_msec()
	_poll_left = POLL
	_report_running()

func _job_done(ok: bool, text: String) -> void:
	var job: Dictionary = _jobs[_index]
	var ms = Time.get_ticks_msec() - _job_t0
	_pid = -1
	_stdio = null
	_stderr = null
	if _log != null:
		_log.flush()
		_log = null
	var peak = " (%.1f GB Speicher)" % (_peak / 1073741824.0) if _peak > 0 else ""
	line.emit("%s %s: %s, %s%s" % ["OK    " if ok else "FEHLER", job["label"], text, _fmt_time(ms / 1000.0), peak])
	if job["kind"] == "map":
		_map_ms.append(ms)
		if ok:
			var maps: Dictionary = _state.get("maps", {})
			maps[job["name"]] = {"stamp": _stamp, "ms": ms, "peak_mb": int(_peak / 1048576), "time": Time.get_datetime_string_from_system(), "root": str(options["root"])}
			_state["maps"] = maps
			_save_state()
	elif job["kind"] == "tabellen" and ok:
		_state["tabellen"] = _stamp
		_save_state()
	elif job["kind"] == "klaenge" and ok:
		_state["klaenge"] = _stamp
		_save_state()
	elif job["kind"] == "oberflaeche" and ok:
		_state[job["name"]] = job["stamp"]
		_save_state()
	elif job["kind"] == "figuren" and ok:
		_state["figuren"] = _stamp
		_save_state()
		_insert_parts(_index + 1)
	elif job["kind"] in ["ausruestung", "effekte"] and ok:
		var parts: Dictionary = _state.get("parts", {})
		parts[job["name"]] = job["stamp"]
		_state["parts"] = parts
		_save_state()
	elif job["kind"] == "export" and ok:
		_state["export"] = {"stamp": _stamp, "time": Time.get_datetime_string_from_system(), "ms": ms}
		_save_state()
	if not ok:
		_failed.append(job["label"])
	_done_weight += float(job["weight"])
	_next()

func _finish(ok: bool, summary: String) -> void:
	running = false
	_wait_ram = false
	_pid = -1
	if _log != null:
		_log.flush()
		_log = null
	progress.emit(1.0 if ok else _fraction(0.0), summary)
	finished.emit(ok, summary)


# ====================================================
# PROZESS
# ====================================================
func _pump() -> void:
	for pipe in [_stdio, _stderr]:
		if pipe == null:
			continue
		while true:
			var b = pipe.get_buffer(65536)
			if b.is_empty():
				break
			var t = b.get_string_from_utf8()
			_out = (_out + t).right(20000)
			if _log != null:
				_log.store_string(t)

# Ergebniszeile des Prozesses: "EXPORT-JOB OK ..." bzw. die Fehlerzeile; beim Godot-Export die Datei
func _result_line(code: int) -> String:
	var job: Dictionary = _jobs[_index]
	if job["kind"] == "export":
		var bin = BUILD_DIR.path_join(BINARY)
		var pck = bin.get_basename() + ".pck"
		if code == 0 and FileAccess.file_exists(bin) and FileAccess.file_exists(pck):
			return "%s und %s (%s)" % [BINARY, pck.get_file(), _fmt_size(_file_size(pck))]
		return "Godot-Export fehlgeschlagen (Rückgabe %d, siehe %s)" % [code, LOG_DIR.path_join("export.log")]
	for l in _out.split("\n"):
		if l.begins_with("EXPORT-JOB OK "):
			return l.trim_prefix("EXPORT-JOB OK ")
		if l.begins_with("EXPORT-JOB FEHLER "):
			return l.trim_prefix("EXPORT-JOB FEHLER ")
	return "Prozess endete mit %d ohne Ergebnis (siehe %s)" % [code, LOG_DIR.path_join("%s.log" % job["name"])]

# Verfügbarer Speicher in Bytes: Linux MemAvailable (samt freigebbarem Datei-Zwischenspeicher); Godots
# get_memory_info()["available"] zählt nur freien Speicher und Auslagerung (z.B. 7 GB statt 25 GB)
static func available_memory() -> int:
	var f = FileAccess.open("/proc/meminfo", FileAccess.READ)
	if f != null:
		while not f.eof_reached():
			var l = f.get_line()
			if l.begins_with("MemAvailable:"):
				return int(l.trim_prefix("MemAvailable:").strip_edges().split(" ")[0]) * 1024
	return int(OS.get_memory_info().get("available", 0))

# Belegter Speicher eines Prozesses (Linux /proc), 0 wenn unbekannt
static func _rss(pid: int) -> int:
	var f = FileAccess.open("/proc/%d/status" % pid, FileAccess.READ)
	if f == null:
		return 0
	while not f.eof_reached():
		var l = f.get_line()
		if l.begins_with("VmRSS:"):
			return int(l.trim_prefix("VmRSS:").strip_edges().split(" ")[0]) * 1024
	return 0

func _report_running() -> void:
	var job: Dictionary = _jobs[_index]
	var secs = (Time.get_ticks_msec() - _job_t0) / 1000.0
	var text = "%s (%d / %d): %s" % [job["label"], _index + 1, _jobs.size(), _fmt_time(secs)]
	if _peak > 0:
		text += ", %.1f GB" % (_peak / 1073741824.0)
	var rest = _rest_seconds()
	if rest > 0.0:
		text += ", noch etwa " + _fmt_time(rest)
	progress.emit(_fraction(clamp(secs / max(_avg_map_s(), 1.0), 0.0, 0.95) if job["kind"] == "map" else 0.0), text)

func _fraction(part: float) -> float:
	if _total_weight <= 0.0 or _index < 0 or _index >= _jobs.size():
		return 0.0
	return clamp((_done_weight + part * float(_jobs[_index]["weight"])) / _total_weight, 0.0, 1.0)

func _avg_map_s() -> float:
	if _map_ms.is_empty():
		return 120.0
	var s = 0.0
	for m in _map_ms:
		s += m
	return s / _map_ms.size() / 1000.0

func _rest_seconds() -> float:
	if _map_ms.is_empty():
		return 0.0
	var left = 0
	for i in range(_index + 1, _jobs.size()):
		if _jobs[i]["kind"] == "map":
			left += 1
	return left * _avg_map_s()


# Teile von Ausrüstung und Effekten an Stelle at einplanen (Listen aus dem Schritt Figuren); aktuelle überspringen
func _insert_parts(at: int) -> void:
	var added = []
	var skipped = 0
	for spec in [[Assets.LIST_EQUIP, "ausruestung", PART_EQUIP, "Ausrüstung"], [Assets.LIST_GFX, "effekte", PART_GFX, "Effekte"]]:
		var n = Assets.read_list(spec[0]).size()
		if n == 0:
			continue
		var parts = int(ceil(float(n) / float(spec[2])))
		var list_md5 = FileAccess.get_md5(spec[0])
		for k in parts:
			var name = "%s_%d" % [spec[1], k + 1]
			var stamp = "%s_%s_%d" % [_stamp, list_md5, parts]
			if not bool(options["force"]) and str(_state.get("parts", {}).get(name, "")) == stamp:
				skipped += 1
				continue
			added.append({"kind": spec[1], "name": name, "weight": WEIGHT_PART, "stamp": stamp,
				"label": "%s %d / %d" % [spec[3], k + 1, parts],
				"args": ["--job=" + spec[1], "--part=%d" % k, "--parts=%d" % parts, "--root=" + str(options["root"]),
				"--written=" + ProjectSettings.globalize_path(LOG_DIR.path_join("%s_dateien.txt" % name))]})
	for i in added.size():
		_jobs.insert(at + i, added[i])
		_total_weight += float(added[i]["weight"])
	line.emit("Ausrüstung / Effekte: %d Teile einzeln umwandeln, %d schon aktuell" % [added.size(), skipped])


# ====================================================
# MAPS / STEMPEL
# ====================================================
# Maps der Spieldaten: [{name, src}] (src relativ zum Spieldaten-Ordner wie in der Leiste ECM-GFX-MAP)
static func list_maps(root: String) -> Array:
	var files = load(PLUGIN + "Data/angelica_files.gd").new(root)
	var out = []
	var dirs: Array = files.list_dir(root.path_join("maps"))["dirs"]
	dirs.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	for d in dirs:
		var src = "maps/%s/%s.trn2" % [d, d]
		if files.file_exists(root.path_join(src)):
			out.append({"name": d, "src": root.path_join(src)})
	return out

# Ist die Map mit dem jetzigen Code umgewandelt (Stempel) und liegt ihre Szene noch da?
func map_current(map_name: String) -> bool:
	var e = _state.get("maps", {}).get(map_name, {})
	if str(e.get("stamp", "")) != _stamp or str(e.get("root", "")) != str(options["root"]):
		return false
	return ResourceLoader.exists("%s/maps/%s/%s.tscn" % [IMPORT_ROOT, map_name, map_name])

# Stand des Umwandlungs-Codes: MD5 über die Skripte / Shader in STAMP_DIRS und STAMP_FILES
static func code_stamp() -> String:
	var files: Array = []
	for d in STAMP_DIRS:
		_collect_code(PLUGIN + d, files)
	for f in STAMP_FILES:
		files.append(PLUGIN + f)
	files.sort()
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for f in files:
		if FileAccess.file_exists(f):
			ctx.update((f + FileAccess.get_md5(f)).to_utf8_buffer())
	return ctx.finish().hex_encode()

static func _collect_code(dir: String, out: Array) -> void:
	var d = DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if not f.get_extension() in ["gd", "gdshader", "gdshaderinc"]:
			continue
		if STAMP_SKIP.any(func(s): return f.ends_with(s)):
			continue
		out.append(dir.path_join(f))
	for sub in d.get_directories():
		_collect_code(dir.path_join(sub), out)

func _load_state() -> Dictionary:
	if not FileAccess.file_exists(STATE_FILE):
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(STATE_FILE))
	return v if v is Dictionary else {}

func _save_state() -> void:
	var f = FileAccess.open(STATE_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_state, " ", true))

# res://Export soll der Editor nicht erfassen (das Programm und die .pck sind keine Projekt-Dateien)
static func _write_gdignore() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var p = OUT_DIR.path_join(".gdignore")
	if not FileAccess.file_exists(p):
		FileAccess.open(p, FileAccess.WRITE)


# ====================================================
# EXPORT-VORGABE
# ====================================================
# Legt die Vorgabe PRESET in export_presets.cfg an, wenn sie fehlt; in einer vorhandenen ergänzt es nur fehlende Muster
# von INCLUDE / EXCLUDE (sonst bleibt sie, wie der Spieler sie eingestellt hat) -> Fehler oder ""
static func ensure_preset() -> String:
	var cfg = ConfigFile.new()
	if FileAccess.file_exists(PRESETS_FILE) and cfg.load(PRESETS_FILE) != OK:
		return PRESETS_FILE + " ist nicht lesbar"
	var n = 0
	while cfg.has_section("preset.%d" % n):
		var sec = "preset.%d" % n
		if str(cfg.get_value(sec, "name", "")) == PRESET:
			var changed = false
			for pair in [["include_filter", INCLUDE], ["exclude_filter", EXCLUDE]]:
				var merged = _merge_patterns(str(cfg.get_value(sec, pair[0], "")), pair[1])
				if merged != str(cfg.get_value(sec, pair[0], "")):
					cfg.set_value(sec, pair[0], merged)
					changed = true
			if changed and cfg.save(PRESETS_FILE) != OK:
				return PRESETS_FILE + " ist nicht schreibbar"
			return ""
		n += 1
	var s = "preset.%d" % n
	var values = {
		"name": PRESET, "platform": "Linux", "runnable": false, "advanced_options": false, "dedicated_server": false,
		"custom_features": "fw_game", "export_filter": "all_resources", "include_filter": INCLUDE, "exclude_filter": EXCLUDE,
		"export_path": BUILD_DIR.trim_prefix("res://").path_join(BINARY), "patches": PackedStringArray(),
		"encryption_include_filters": "", "encryption_exclude_filters": "", "seed": 0, "encrypt_pck": false,
		"encrypt_directory": false, "script_export_mode": 2,
	}
	for k in values:
		cfg.set_value(s, k, values[k])
	var opts = {
		"custom_template/debug": "", "custom_template/release": "", "debug/export_console_wrapper": 1,
		"binary_format/embed_pck": false, "texture_format/s3tc_bptc": true, "texture_format/etc2_astc": false,
		"binary_format/architecture": "x86_64",
	}
	for k in opts:
		cfg.set_value(s + ".options", k, opts[k])
	if cfg.save(PRESETS_FILE) != OK:
		return PRESETS_FILE + " ist nicht schreibbar"
	return ""


# "a, b" + "b, c" -> "a, b, c"
static func _merge_patterns(have: String, need: String) -> String:
	var out: Array = []
	for p in (have + "," + need).split(",", false):
		p = p.strip_edges()
		if p != "" and not p in out:
			out.append(p)
	return ", ".join(out)


# ====================================================
# HILFEN
# ====================================================
static func _file_size(path: String) -> int:
	var f = FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0

static func _fmt_size(n: int) -> String:
	if n >= 1073741824:
		return "%.2f GB" % (n / 1073741824.0)
	return "%.0f MB" % (n / 1048576.0)

static func _fmt_time(secs: float) -> String:
	var s = int(secs)
	if s >= 3600:
		return "%d h %02d min" % [s / 3600, (s / 60) % 60]
	if s >= 60:
		return "%d min %02d s" % [s / 60, s % 60]
	return "%d s" % s
