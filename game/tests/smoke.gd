extends Node

# ====================================================
# Rauchtest des exportierten Clients (Leiste EXPORT, Performance-Fahrplan P2f). Das exportierte Programm führt kein Skript
# von der Kommandozeile aus (Godot 4.7: "-s" startet dort einfach das Spiel), darum eine Rolle von main.gd:
#   PWE-Client.x86_64 --headless -- --smoke --port=29000
# Läuft neben dem normalen Client (Net, Session, Login): legt ein Konto mit einem Menschen-Krieger an, meldet sich an wie
# über den Login, betritt die Welt und prüft Map, Figur und NPCs mit Modell. Letzte Zeile "RAUCHTEST OK ..." bzw.
# "RAUCHTEST FEHLER ...", Rückgabewert 0 / 1.
# ====================================================

const Proto = preload("../common/protocol.gd")
const LoginScreen = preload("../client/login_screen.gd")
const PASSWORD = "geheim-123"
const LOOK = {"face": 0, "mask": 0, "hair": 1, "skin": 0, "hair_color": 0x902E1E}
const LIMIT = 300.0 # s für alles

var _failures: Array = []
var _checks = 0


func _ready() -> void:
	get_tree().create_timer(LIMIT).timeout.connect(_end.bind("Zeitlimit"))
	_run.call_deferred()

func _run() -> void:
	await _frames(5)
	var ls = get_parent().get_node_or_null("Login")
	_check("Login im Spielstil (Spieldaten gefunden)", ls != null)
	if ls == null:
		_end("")
		return
	var acc = "Rt_%05d" % (randi() % 100000)
	var r = await ls.session.register(acc, PASSWORD)
	_check("Konto %s angelegt (Code %d)" % [acc, int(r["code"])], r["code"] == Proto.Code.OK)
	if r["code"] != Proto.Code.OK:
		_end("")
		return
	ls.dlg_login.set_text("DEFAULT_Txt_Account", acc)
	ls.dlg_login.set_text("Txt_PassWord", PASSWORD)
	ls._on_login_command("Btn_Login")
	await _until(func(): return ls.state == LoginScreen.State.SELECT_CHAR and ls.chars.dlg_list.visible, 30.0)
	var hero = "Probe%03d" % (randi() % 1000)
	r = await ls.session.create_char(hero, 1, 1, 0, LOOK)
	_check("Figur %s angelegt" % hero, r["code"] == Proto.Code.OK)
	await ls.chars.refresh()
	ls.chars.show_list()
	ls.chars._on_enter_command("Btn_EnterWorld")
	await _until(func(): return ls.world != null and ls.world.ready_in_world, 120.0)
	var w = ls.world
	_check("Welt geladen (%s)" % ", ".join(w.warnings if w != null else []), w != null and w.ready_in_world and w.map_root != null)
	if w == null or not w.ready_in_world:
		_end("")
		return
	_check("eigene Figur steht in der Welt", w.player != null and w.player.is_inside_tree())
	await _until(func(): return w.npcs.size() > 20, 10.0)
	var with_model = w.npcs.values().filter(func(n): return n.anim != null).size()
	_check("NPCs und Monster (%d, %d mit Modell; %d Modelle nicht importiert, %d gebaut)" % [w.npcs.size(), with_model,
		w.missing_models.size(), w.built_models], w.npcs.size() > 20 and with_model >= w.npcs.size() - 2)
	_end("")

func _check(text: String, ok: bool) -> void:
	_checks += 1
	print("RAUCHTEST: ", "ok      " if ok else "FEHLER  ", text)
	if not ok:
		_failures.append(text)

func _end(reason: String) -> void:
	if reason != "":
		_failures.append(reason)
	var ls = get_parent().get_node_or_null("Login")
	if ls != null and ls.session != null:
		ls.session.close()
	if ls != null and ls.world != null:
		ls.world.stop_sounds()
	await _frames(3)
	if _failures.is_empty():
		print("RAUCHTEST OK (%d Prüfungen)" % _checks)
	else:
		print("RAUCHTEST FEHLER: %s" % "; ".join(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _until(cond: Callable, seconds: float) -> void:
	var end = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await get_tree().process_frame
	await _frames(2)
