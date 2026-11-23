@tool
extends EditorDock

# ====================================================
# Leiste "EXPORT" unten im Editor (Performance-Fahrplan P2f): links der Client, rechts der Server, je ein Knopf für
# Linux, Windows, macOS, iOS und Android. Bisher arbeitet nur "Client Export for Linux" (client_export.gd); der
# Server für Linux folgt (P2g), die übrigen Plattformen sind noch ohne Funktion.
# Darunter: Speichergrenze (GB je Umwandlungs-Prozess; gemerkt in den Projekt-Metadaten "export"), "alles neu"
# (auch schon aktuelle Maps umwandeln), "nur Maps" (z.B. s9,s31; leer = alle), Abbrechen, Fortschritt und Protokoll.
# Spieldaten-Ordner: wie in der Leiste ECM-GFX-MAP. Ergebnis und Protokolle: res://Export/ (vom Editor nicht erfasst).
# ====================================================

const ClientExport = preload("client_export.gd")
const META_SECTION = "export"
const ECM_META = "ecm_gfx_panel" # Spieldaten-Ordner der Leiste ECM-GFX-MAP
const DEFAULT_ROOT = "res://Stock-PWE-Client"
const PLATFORMS = ["Linux", "Windows", "MacOS", "iOS", "Android"]

var _client_buttons = {}
var _server_buttons = {}
var _ram: SpinBox
var _force: CheckBox
var _maps: LineEdit
var _cancel_btn: Button
var _open_btn: Button
var _progress: ProgressBar
var _status: Label
var _log: TextEdit
var _export: Node


func _init() -> void:
	title = "EXPORT"
	layout_key = "PWE-Export"
	icon_name = &"Load"
	default_slot = DOCK_SLOT_BOTTOM
	custom_minimum_size = Vector2(0, 200)

	var box = VBoxContainer.new()
	add_child(box)
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)
	_client_buttons = _column(columns, "Client", "Client Export for %s")
	_server_buttons = _column(columns, "Server", "Server Export for %s")
	for p in PLATFORMS:
		var cb: Button = _client_buttons[p]
		var sb: Button = _server_buttons[p]
		cb.disabled = p != "Linux"
		cb.tooltip_text = "Noch ohne Funktion" if p != "Linux" else \
			"Alle Maps einzeln umwandeln (je ein eigener Prozess), aufräumen, dann als Linux-Programm nach res://Export/Client-Linux exportieren"
		sb.disabled = true
		sb.tooltip_text = "Funktion folgt (Performance-Fahrplan P2g)" if p == "Linux" else "Noch ohne Funktion"
	(_client_buttons["Linux"] as Button).pressed.connect(_start_client_linux)

	var opts = HBoxContainer.new()
	box.add_child(opts)
	var ram_label = Label.new()
	ram_label.text = "Speichergrenze (GB):"
	opts.add_child(ram_label)
	_ram = SpinBox.new()
	_ram.min_value = 1
	_ram.max_value = 256
	_ram.step = 0.5
	_ram.tooltip_text = "Ein Umwandlungs-Prozess startet erst, wenn so viel Speicher frei ist, und wird abgebrochen, wenn er mehr belegt"
	opts.add_child(_ram)
	_force = CheckBox.new()
	_force.text = "Alles neu"
	_force.tooltip_text = "Auch Maps umwandeln, die schon mit dem jetzigen Code umgewandelt sind"
	opts.add_child(_force)
	var maps_label = Label.new()
	maps_label.text = "Nur Maps:"
	opts.add_child(maps_label)
	_maps = LineEdit.new()
	_maps.placeholder_text = "alle (oder z.B. s9,s31)"
	_maps.custom_minimum_size.x = 160
	_maps.tooltip_text = "Nur diese Maps umwandeln, durch Komma getrennt; leer = alle Maps der Spieldaten"
	opts.add_child(_maps)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Abbrechen"
	_cancel_btn.disabled = true
	_cancel_btn.tooltip_text = "Laufenden Schritt beenden; fertige Maps bleiben, der nächste Lauf macht weiter"
	_cancel_btn.pressed.connect(_on_cancel)
	opts.add_child(_cancel_btn)
	_open_btn = Button.new()
	_open_btn.text = "Ordner öffnen"
	_open_btn.tooltip_text = "res://Export im Dateimanager öffnen"
	_open_btn.pressed.connect(_on_open)
	opts.add_child(_open_btn)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.x = 140
	_progress.max_value = 1.0
	_progress.step = 0.001
	opts.add_child(_progress)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	opts.add_child(_status)

	_log = TextEdit.new()
	_log.editable = false
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size.y = 80
	box.add_child(_log)

	_export = ClientExport.new()
	add_child(_export)
	_export.line.connect(_on_line)
	_export.progress.connect(_on_progress)
	_export.finished.connect(_on_finished)

func _ready() -> void:
	var settings = EditorInterface.get_editor_settings()
	var physical = float(OS.get_memory_info().get("physical", 0)) / 1073741824.0
	var def = clamp(floor(physical / 2.0), 2.0, 12.0) if physical > 0.0 else 8.0
	_ram.value = float(settings.get_project_metadata(META_SECTION, "ram_gb", def))
	_maps.text = str(settings.get_project_metadata(META_SECTION, "maps", ""))
	_ram.value_changed.connect(func(v): settings.set_project_metadata(META_SECTION, "ram_gb", v))
	_maps.text_changed.connect(func(t): settings.set_project_metadata(META_SECTION, "maps", t))

# Plugin aus / Editor zu: laufenden Prozess beenden
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _export != null and _export.running:
		_export.cancel()

func _column(parent: Control, heading: String, fmt: String) -> Dictionary:
	var col = VBoxContainer.new()
	parent.add_child(col)
	var head = Label.new()
	head.text = heading
	col.add_child(head)
	var out = {}
	for p in PLATFORMS:
		var b = Button.new()
		b.text = fmt % p
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		col.add_child(b)
		out[p] = b
	return out

func _start_client_linux() -> void:
	var root = str(EditorInterface.get_editor_settings().get_project_metadata(ECM_META, "root", DEFAULT_ROOT))
	_log.text = ""
	var err = _export.start({
		"root": root,
		"maps": Array(_maps.text.replace(" ", "").split(",", false)),
		"force": _force.button_pressed,
		"ram_gb": _ram.value,
	})
	if err != "":
		_set_status("Nicht gestartet: " + err)
		return
	_set_running(true)

func _on_cancel() -> void:
	_export.cancel()

func _on_open() -> void:
	ClientExport._write_gdignore()
	OS.shell_open(ProjectSettings.globalize_path(ClientExport.OUT_DIR))

func _on_line(text: String) -> void:
	_log.text += text + "\n"
	_log.scroll_vertical = _log.get_line_count()
	print("Export: ", text)

func _on_progress(fraction: float, text: String) -> void:
	_progress.value = fraction
	_set_status(text)

func _on_finished(ok: bool, summary: String) -> void:
	_set_running(false)
	_set_status(("Fertig: " if ok else "Nicht fertig: ") + summary)

func _set_running(on: bool) -> void:
	(_client_buttons["Linux"] as Button).disabled = on
	_cancel_btn.disabled = not on
	_force.disabled = on
	_maps.editable = not on
	_ram.editable = not on

func _set_status(text: String) -> void:
	_status.text = text
	_status.tooltip_text = text
