extends SceneTree

# ====================================================
# Startfertigkeiten aller Klassen (Fertigkeiten-Fahrplan F6) gegen einen eigenen Server (tests/test_server.gd:
# Ordner user://test_server/klassen, frische Datenbank, Maps s9, s10, s11, s31):
#   godot --headless --path <Projekt> -s res://game/tests/class_test.gd -- [--port=29125]
# Je Rasse / Klasse der Startvorlagen (14) eine Figur, alle gleichzeitig: beide Startfertigkeiten und das
# Stadtportal (120) sind einsetzbar (skill_info usable) und wirken:
#   Angriff / Fluch   zum nächsten wählbaren Monster laufen (ist keins in 100 m Sicht, erst zum nächsten Spawn-Gebiet
#                     aus den Server-Daten: Steinmensch, Kindred und Werwolf starten 140 - 170 m davon entfernt;
#                     abgelehnte Ziele wie Deko-Tiere zählen nicht) (Ansturm: auf 12 m, sonst bis in die Annäherungsweite), einsetzen,
#                     Zaubern endet (skill_end ok), Treffer mit der Fertigkeit (hit mit skill, auch verfehlt bzw. nodmg);
#                     Ansturm: dazu skill_move bis vor das Monster
#   Rassen-Segen (Z1) erst ab Stufe 10 (Z5: Server-tasks.data): auf Stufe 1 unbekannt, skills.race beginnt trotzdem mit ihm;
#                     nach dem Lernen (debug_char Stufe 10 / 25) bekannt (skill_new), wird eingesetzt und überdauert (Z2)
#                     Verlassen und Betreten der Welt (Restzeit bleibt)
#   Gebet (Z2)        Menschen: sofort (Zeit 0, keine Aktion), Mana +25 %, Effekt 1113 mit GFX 16, danach immun gegen Betäuben
#   Stärkung          auf sich selbst: Heilung (heal an die Figur) bzw. ein Effekt (buffs der Figur)
#   Stadtportal       9,85 s still stehen, dann pos_correct an den nächsten Stadtpunkt der Welt (town_pos der Startvorlagen)
#   Passiv (F7)       per Testbefehl debug_skill eine passive Fertigkeit der Klasse lernen: ihr Dauer-Effekt liegt (Rest 0),
#                     Stufe 3 ersetzt ihn (kein zweiter), Krieger: Leben +3 %; einsetzen -> SKILL_PASSIVE; nach Verlassen
#                     und Betreten der Welt liegt er wieder
#   Schalter (F7)     einen einsetzbaren Schalter der Klasse lernen und einsetzen -> skill_switch an; erneut -> aus (off)
#   NPC-Ort (B19)     quest_where "npc" nach Edward Olgen 44826 (Werwolf-Folgequest 15850): der Server kennt ihn aus seinen
#                     Spawn-Daten in s31 nahe (-194 | 257 | 336) - beim Werwolf in derselben Welt, bei allen anderen
#                     world -1 (anderes Gebiet); die task_npc.data des neueren Clients hat ihn schon in s43
#   Lernen (F8)       debug_char Stufe 10: alle Klassen-Fertigkeiten bis Stufe 10 von selbst (skill_new, skill_catalog);
#                     Stufe 25: von selbst nur bis Stufe 20; eine Stufe bis 25 ohne Geld -> NOT_ENOUGH_MONEY, nur mit Gold
#                     -> NOT_ENOUGH_BIND_MONEY (Rückfrage), mit gold = true gelernt (Gold - Kosten); eine zweite mit
#                     Seelenmünzen (Z4: Seelenmünzen - Kosten, Gold bleibt); eine über 25 -> SKILL_LEVEL_LOW
# Ende: "KLASSEN-TEST OK" (Exit 0) oder "KLASSEN-TEST FEHLER" (Exit 1), nach Zeitlimit Abbruch (Exit 2).
# ====================================================

const Proto = preload("../common/protocol.gd")
const Settings = preload("../common/settings.gd")
const Session = preload("../client/session.gd")
const TestServer = preload("test_server.gd")
const TestUtil = preload("test_util.gd")
const PLUGIN_SERVER = "res://addons/PWE-Manager/Server/"
const Npcs = preload("../server/npcs.gd")
const HUNT_NEAR = 100.0 # m: so nah muss ein wählbares Monster sein, sonst erst zum Spawn-Gebiet laufen
const DIR = "user://test_server/klassen"
const DEFAULT_PORT = 29125
const RACE_WOLF = 6
const EDWARD = 44826 # Edward Olgen (15850 "Silberflügelherzog")
const EDWARD_POS = Vector3(-194, 257, 336) # Server task_npc.data, Welt 31
const MAPS = "s9,s10,s11,s31"
const PASSWORD = "geheim-123"
const LOOK = {"face": 1, "mask": 2, "hair": 3, "skin": 4, "hair_color": 0xD25720}
const PORTAL = 120
const CHARGE_AT = 12.0 # m: von hier stürmt der Krieger (Ansturm: mindestens 8, höchstens 21 m)
const TRIES = 4
const SKILLS_JSON = PLUGIN_SERVER + "skill_templates.json"
# Rasse -> [Quest, Segen] (versteckte Automatik-Quest, Z1): ab Stufe 10 bekannt, erste Rassen-Fertigkeit der K-Liste
const BLESSINGS = {1: [8702, 2497], 2: [8703, 2498], 3: [8705, 2500], 4: [8706, 2501], 5: [8704, 2499], 6: [15802, 4214]}
const BLESS_LEVEL = 10 # Mindeststufe der Segen-Quests (Server-tasks.data, Z5)
const BLESS_STATE = {1: 1237, 2: 1238, 3: 1240, 4: 1241, 5: 1239, 6: 2880} # Effekt des Segens (30 min, offline_save)
const PRAYER = 1958 # Gebet (Menschen)
const MANA_DRAIN = 1102 # 通用-直接减魔: zieht sofort Mana ab (Testbefehl debug_state)
const STUN = 365

var u: TestUtil
var srv: TestServer
var port = DEFAULT_PORT
var checks = 0
var failures = 0
var monsters = {} # Vorlage -> true (npc_templates.json)
var towns = {} # Welt -> [Vector3] (Stadtpunkte)
var hunt = {} # "Rasse_Klasse" -> Vector3: nächstes wählbares Monster vom Start (Server-Spawndaten)
var bots: Array = []
var passive_of = {} # "Rasse_Klasse" -> [ID, [Effekte]] einer passiven Fertigkeit mit Dauer-Effekt
var switch_of = {} # "Rasse_Klasse" -> ID eines Schalters, der auf die eigene Figur wirkt
var _running = 0


func _initialize() -> void:
	var args = Settings.user_args()
	port = int(args.get("port", str(DEFAULT_PORT)))
	Engine.max_fps = 120
	var t = JSON.parse_string(FileAccess.get_file_as_string(PLUGIN_SERVER + "npc_templates.json"))
	for k in (t.get("monsters", {}) if t is Dictionary else {}):
		monsters[int(k)] = true
	var sr = JSON.parse_string(FileAccess.get_file_as_string(PLUGIN_SERVER + "start_roles.json"))
	var maps = {}
	for r in (sr.get("roles", []) if sr is Dictionary else []):
		var tp: Array = r.get("town_pos", [])
		if tp.size() == 3:
			var list: Array = towns.get(int(r["town_world"]), [])
			if not list.has(Vector3(tp[0], tp[1], tp[2])):
				list.append(Vector3(tp[0], tp[1], tp[2]))
			towns[int(r["town_world"])] = list
		var key = "%d_%d" % [int(r["race"]), int(r["class"])]
		if not hunt.has(key):
			var p: Array = r["pos"]
			hunt[key] = _hunt_point(str(r["map"]), Vector3(p[0], p[1], p[2]), t, maps)
	var sk = JSON.parse_string(FileAccess.get_file_as_string(SKILLS_JSON))
	for e in (sk.get("skills", []) if sk is Dictionary else []):
		var key = "%d_%d" % [int(e["race"]), int(e["class"])]
		if int(e["use"]) == 6 and not e["states"].is_empty() and not passive_of.has(key):
			passive_of[key] = [int(e["id"]), e["states"].map(func(x): return int(x["id"]))]
		elif int(e["use"]) == 7 and int(e["type"]) == 2 and int(e["range"]["approach"]) in [5, 8] and int(e["move_mode"]) == 0 \
				and not e["procs"].is_empty() and not switch_of.has(key):
			switch_of[key] = int(e["id"])
	u = TestUtil.new(self)
	srv = TestServer.new(DIR, port, ["--maps=" + MAPS, "--max_clients=32", "--debug_commands"])
	create_timer(300.0).timeout.connect(func(): _end(2))
	_run.call_deferred()

func _process(_delta: float) -> bool:
	u.poll()
	return false

func _run() -> void:
	srv.fresh()
	_check("Server startet (Port %d, Maps %s)" % [port, MAPS], await srv.start(self))
	if not srv.running():
		_end(1)
		return
	var probe = u.session("Vorlagen", port)
	await probe.open()
	await probe.register("Klassenprobe", PASSWORD)
	await probe.login("Klassenprobe", PASSWORD)
	var r = await probe.list_chars()
	var combos = {} # "Rasse_Klasse" -> "Rasse_Klasse_Geschlecht"
	for c in r["data"].get("classes", []):
		var k = "_".join(str(c).split("_").slice(0, 2))
		if not combos.has(k):
			combos[k] = str(c)
	probe.close()
	_check("%d Rasse / Klasse-Kombinationen in den Startvorlagen" % combos.size(), combos.size() == 14)
	var i = 0
	for k in combos:
		var b = {"i": i, "key": k, "combo": combos[k], "name": "Klasse%02d" % i, "s": u.session("Klasse%02d" % i, port),
			"id": 0, "pos": Vector3.ZERO, "info": {}, "skills": [], "done": [], "errors": [], "bad": {}, "world": 0}
		bots.append(b)
		_bot(b)
		i += 1
	await u.until(func(): return _running == 0, 260.0)
	for b in bots:
		for e in b["done"]:
			_check("%s: %s" % [b["key"], e[1]], e[0])
		for e in b["errors"]:
			_check("%s: %s" % [b["key"], e], false)
	for b in bots:
		b["s"].close()
	_check("Server stoppt sauber", await srv.stop(self))
	_end(0 if failures == 0 else 1)

# Eine Figur: anmelden, Startfertigkeiten einsetzen, Stadtportal
func _bot(b: Dictionary) -> void:
	_running += 1
	var s: Session = b["s"]
	var c = str(b["combo"]).split("_")
	var acc = "Klassenbot%02d" % b["i"]
	var r = await s.open()
	if r["code"] == Proto.Code.OK:
		r = await s.register(acc, PASSWORD)
	if r["code"] == Proto.Code.OK:
		r = await s.login(acc, PASSWORD)
	if r["code"] == Proto.Code.OK:
		r = await s.create_char("Kheld%02d" % b["i"], int(c[0]), int(c[1]), int(c[2]), LOOK)
	if r["code"] == Proto.Code.OK:
		b["char"] = int(r["data"]["char"]["id"])
		r = await s.enter_char(b["char"])
	if r["code"] == Proto.Code.OK:
		var p: Array = r["data"]["pos"]
		b["pos"] = Vector3(p[0], p[1], p[2])
		b["world"] = int(r["data"].get("world", 0))
		r = await s.world_ready()
	if r["code"] != Proto.Code.OK:
		b["errors"].append("Anmelden: %s" % Proto.text(int(r["code"])))
		_running -= 1
		return
	b["id"] = int(r["data"]["id"])
	b["max_hp"] = int(r["data"].get("stats", {}).get("max_hp", 0))
	var sk: Dictionary = r["data"].get("skills", {})
	b["info"] = sk.get("info", {})
	b["skills"] = sk.get("skills", []).map(func(e): return int(e[0])).filter(func(id): return id != PORTAL)
	b["skills"].sort()
	var bless: Array = BLESSINGS.get(int(c[0]), [0, 0])
	var race_ids = sk.get("race", []).map(func(e): return int(e[0]))
	var qs: Dictionary = r["data"].get("quests", {})
	var running = qs.get("active", []).map(func(e): return int(e[0]))
	b["done"].append([not b["skills"].has(int(bless[1])) and not race_ids.is_empty() and race_ids[0] == int(bless[1])
		and not qs.get("done", []).has(int(bless[0])) and not running.has(int(bless[0])),
		"Rassen-Segen %d erst ab Stufe %d: auf Stufe 1 unbekannt (Quest %d nicht vergeben), K-Liste Rasse beginnt mit ihm %s" % [
		bless[1], BLESS_LEVEL, bless[0], str(race_ids)]])
	await create_timer(1.5).timeout # NPCs in Sicht
	var wr = await s.quest_where("npc", EDWARD, 0)
	var wd: Dictionary = wr.get("data", {})
	var at: Array = wd.get("pos", [])
	var near = at.size() >= 3 and Vector3(at[0], at[1], at[2]).distance_to(EDWARD_POS) < 30.0
	if int(c[0]) == RACE_WOLF:
		b["done"].append([wr["code"] == Proto.Code.OK and str(wd.get("map", "")) == "s31" and int(wd.get("world", 0)) == b["world"]
			and near, "Edward Olgen (quest_where npc %s): %s, Welt %s, %s" % [Proto.text(int(wr["code"])), str(wd.get("map", "")),
			str(wd.get("world", "")), str(at)]])
	else:
		b["done"].append([wr["code"] == Proto.Code.OK and int(wd.get("world", 0)) == -1 and near,
			"Edward Olgen von hier: anderes Gebiet (%s, Welt %s)" % [Proto.text(int(wr["code"])), str(wd.get("world", ""))]])
	for id in b["skills"] + [PORTAL]:
		var i: Dictionary = b["info"].get(str(id), {})
		if not i.get("usable", false):
			b["done"].append([false, "%d nicht einsetzbar (%s)" % [id, str(i)]])
			continue
		if id == PORTAL:
			await _portal(b)
		elif i.get("bless", false):
			await _bless(b, id)
		else:
			await _attack(b, id, i)
	await _switch(b)
	await _passive(b)
	await _learning(b)
	await _race(b)
	_running -= 1

# Letzte Effekt-Liste der eigenen Figur seit from ([[Effekt, Stapel, Rest ms, ...]]), null ohne Meldung
func _my_buffs(b: Dictionary, from: int):
	var list = null
	for e in b["s"].get_meta("pushes").slice(from):
		if e[0] == "buffs" and int(e[1]["id"]) == b["id"]:
			list = e[1]["list"]
	return list

# Passive Fertigkeit (F7): lernen, Dauer-Effekt, neue Stufe ersetzt, nicht einsetzbar, nach erneutem Betreten wieder da
func _passive(b: Dictionary) -> void:
	if not passive_of.has(b["key"]):
		b["done"].append([true, "Passiv: die Klasse hat keine passive Fertigkeit mit Effekt"])
		return
	var id = int(passive_of[b["key"]][0])
	var want: Array = passive_of[b["key"]][1]
	var s: Session = b["s"]
	var pushes: Array = s.get_meta("pushes")
	var n0 = pushes.size()
	var hp_before = b["max_hp"] # Höchst-Leben vor dem Lernen (mit dem Rassen-Segen: +1 % laut Dump, Z1)
	for e in pushes:
		if e[0] == "stats" and e[1].has("max_hp"):
			hp_before = int(e[1]["max_hp"])
	var r = await s.debug_skill(id, 1)
	await create_timer(0.5).timeout
	var l1 = _my_buffs(b, n0)
	var info = pushes.slice(n0).filter(func(e): return e[0] == "skill_info" and int(e[1]["id"]) == id)
	var lasting = func(l): return l != null and want.all(func(w): return l.filter(func(x): return int(x[0]) == w and int(x[2]) == 0).size() == 1)
	var n1 = pushes.size()
	await s.debug_skill(id, 3)
	await create_timer(0.5).timeout
	var l3 = _my_buffs(b, n1)
	var hp = -1
	for e in pushes.slice(n1):
		if e[0] == "stats" and e[1].has("max_hp"):
			hp = int(e[1]["max_hp"])
	var hp_ok = true
	if id in [131, 1973]: # Krieger: Leben +1 % je Stufe
		hp_ok = hp == hp_before + int(b["max_hp"] * 0.03) # Prozent vom Grundwert
	var c = await s.skill_cast(id, 0, b["pos"])
	b["done"].append([r["code"] == Proto.Code.OK and not info.is_empty() and info[0][1]["info"].get("passive", false)
		and lasting.call(l1) and lasting.call(l3) and hp_ok and c["code"] == Proto.Code.SKILL_PASSIVE,
		"Passiv %d: Effekte %s dauerhaft (Stufe 1 %s, Stufe 3 %s)%s, einsetzen: %s" % [id, str(want),
		str(lasting.call(l1)), str(lasting.call(l3)), (", Leben %d -> %d (+3 %% vom Grundwert %d)" % [hp_before, hp, b["max_hp"]]) if id in [131, 1973] else "",
		Proto.text(int(c["code"]))]])
	# Welt verlassen und wieder betreten: Dauer-Effekte kommen beim Betreten neu (EVENT_RESET)
	await s.world_leave()
	r = await s.enter_char(int(b.get("char", 0)))
	if r["code"] == Proto.Code.OK:
		r = await s.world_ready()
	var again: Array = r["data"].get("buffs", []) if r["code"] == Proto.Code.OK else []
	b["done"].append([r["code"] == Proto.Code.OK and lasting.call(again),
		"Passiv %d nach erneutem Betreten: %s" % [id, str(again.map(func(x): return int(x[0])))]])

# Rassen-Fertigkeiten (Z2): der eingesetzte Segen überdauert Verlassen und Betreten der Welt (Restzeit bleibt); Menschen:
# Gebet sofort (Zeit 0, keine Aktion), Mana +25 %, Effekt 1113 mit GFX 16, 4,2 s immun gegen Betäuben
func _race(b: Dictionary) -> void:
	var s: Session = b["s"]
	var race = int(str(b["combo"]).split("_")[0])
	var bless = int(BLESS_STATE.get(race, 0))
	# nach debug_char (Stufe 10 / 25, _learning) vergibt der Server die Segen-Quest: Segen gelernt, einsetzen
	var skill = int(BLESSINGS.get(race, [0, 0])[1])
	var got = s.get_meta("pushes").any(func(e): return e[0] == "skill_new" and int(e[1].get("id", 0)) == skill)
	b["done"].append([got, "Rassen-Segen %d ab Stufe %d gelernt (skill_new nach dem Stufenwechsel)" % [skill, BLESS_LEVEL]])
	if got:
		await _bless(b, skill)
	await s.world_leave()
	var r = await s.enter_char(int(b.get("char", 0)))
	if r["code"] == Proto.Code.OK:
		r = await s.world_ready()
	var kept = (r["data"].get("buffs", []) if r["code"] == Proto.Code.OK else []).filter(func(x): return int(x[0]) == bless)
	b["done"].append([kept.size() == 1 and int(kept[0][2]) > 1500000 and int(kept[0][3]) == 1800000,
		"Segen (Effekt %d) nach erneutem Betreten: %s" % [bless, ("Rest %.1f min von %.0f" % [int(kept[0][2]) / 60000.0, int(kept[0][3]) / 60000.0]) if not kept.is_empty() else "fehlt"]])
	if race != 1:
		return
	var pushes: Array = s.get_meta("pushes")
	await s.debug_skill(PRAYER, 1)
	await create_timer(0.3).timeout
	var info = pushes.filter(func(e): return e[0] == "skill_info" and int(e[1]["id"]) == PRAYER)
	await s.debug_state(MANA_DRAIN, 0, 1000, [100000])
	await create_timer(0.3).timeout
	var mp0 = _last_mp(pushes, 0)
	var n0 = pushes.size()
	var c = await s.skill_cast(PRAYER, 0, b["pos"])
	await create_timer(0.4).timeout
	var mp1 = _last_mp(pushes, n0)
	var mine = _my_buffs(b, n0)
	var prayer = (mine if mine != null else []).filter(func(x): return int(x[0]) == 1113)
	var st = await s.debug_state(STUN, 0, 2000, [])
	var max_mp = 0
	for e in pushes:
		if e[0] == "stats" and e[1].has("max_mp"):
			max_mp = int(e[1]["max_mp"])
	var act = str(info[-1][1]["info"].get("act", "?")) if not info.is_empty() else "?"
	b["done"].append([c["code"] == Proto.Code.OK and int(c["data"].get("time", -1)) == 0 and act == ""
		and mp1 - mp0 >= int(max_mp * 0.25) and mp1 - mp0 <= int(max_mp * 0.35) and prayer.size() == 1 and int(prayer[0][4]) == 16
		and st["code"] == Proto.Code.OK and not st["data"].get("ok", true),
		"Gebet: %s, Zeit %s, Aktion '%s', Mana %d -> %d (+25 %% von %d, dazu ggf. Regeneration), Effekt 1113 GFX %s, Betäuben danach %s" % [
		Proto.text(int(c["code"])), str(c["data"].get("time")), act, mp0, mp1, max_mp,
		str(prayer[0][4]) if not prayer.is_empty() else "-", "abgewehrt" if not st["data"].get("ok", true) else "greift"]])

func _last_mp(pushes: Array, from: int) -> int:
	var mp = -1
	for e in pushes.slice(from):
		if e[0] == "stats" and e[1].has("mp"):
			mp = int(e[1]["mp"])
	return mp

# Schalter (F7): einsetzen -> an, erneut einsetzen -> aus (ohne Kosten, auch in der Abklingzeit)
func _switch(b: Dictionary) -> void:
	if not switch_of.has(b["key"]):
		b["done"].append([true, "Schalter: die Klasse hat keinen Schalter, der auf sich wirkt (Flächen später)"])
		return
	var id = int(switch_of[b["key"]])
	var s: Session = b["s"]
	var pushes: Array = s.get_meta("pushes")
	await s.debug_skill(id, 1)
	await create_timer(0.3).timeout
	var n0 = pushes.size()
	var r = await s.skill_cast(id, 0, b["pos"])
	if r["code"] == Proto.Code.OK and r["data"].get("off", false): # war schon an (Startfertigkeit, z.B. 2093): neu ein
		await create_timer(0.3).timeout
		n0 = pushes.size()
		r = await s.skill_cast(id, 0, b["pos"])
	if r["code"] != Proto.Code.OK:
		b["done"].append([false, "Schalter %d: %s" % [id, Proto.text(int(r["code"]))]])
		return
	var ended = func(): return pushes.slice(n0).any(func(e): return e[0] == "skill_end" and int(e[1]["src"]) == b["id"])
	await u.until(ended, float(r["data"].get("time", 1000)) / 1000.0 + 3.0)
	await create_timer(0.3).timeout
	var on = pushes.slice(n0).any(func(e): return e[0] == "skill_switch" and int(e[1]["id"]) == id and e[1]["on"])
	var with = _my_buffs(b, n0)
	var n1 = pushes.size()
	var r2 = await s.skill_cast(id, 0, b["pos"])
	await create_timer(0.3).timeout
	var off = pushes.slice(n1).any(func(e): return e[0] == "skill_switch" and int(e[1]["id"]) == id and not e[1]["on"])
	var without = _my_buffs(b, n1)
	b["done"].append([on and r2["code"] == Proto.Code.OK and r2["data"].get("off", false) and off,
		"Schalter %d: an %s (Effekte %s), erneut eingesetzt: %s, aus %s (Effekte %s)" % [id, str(on),
		str(with.map(func(x): return int(x[0]))) if with != null else "-", Proto.text(int(r2["code"])), str(off),
		str(without.map(func(x): return int(x[0]))) if without != null else "-"]])

# Angriff / Fluch auf das nächste Monster
func _attack(b: Dictionary, id: int, i: Dictionary) -> void:
	var s: Session = b["s"]
	var pushes: Array = s.get_meta("pushes")
	var charge = int(i.get("move", 0)) == 1
	var note = ""
	var tries = 0
	var rounds = 0
	while tries < TRIES and rounds < 40: # abgelehnte Ziele (Deko-Tiere am Start) zählen nicht als Versuch
		rounds += 1
		tries += 1
		var mid = _nearest_monster(b, charge)
		var hp: Vector3 = hunt.get(b["key"], Vector3.INF)
		if (mid == 0 or u.npcs(pushes)[mid]["at"].distance_to(b["pos"]) > HUNT_NEAR) and hp != Vector3.INF \
				and hp.distance_to(b["pos"]) > 30.0:
			b["pos"] = await u.walk(s, b["pos"], hp, 20.0) # zum Spawn-Gebiet
			await create_timer(1.0).timeout
			mid = _nearest_monster(b, charge)
		if mid == 0:
			note = "kein Monster in Sicht"
			break
		var at: Vector3 = u.npcs(pushes)[mid]["at"]
		if charge: # genau CHARGE_AT m vom Monster, notfalls zurück (Ansturm braucht mindestens 8 m)
			var away = Vector2(b["pos"].x - at.x, b["pos"].z - at.z)
			away = away.normalized() if away.length() > 0.1 else Vector2(1, 0)
			b["pos"] = await u.walk(s, b["pos"], Vector3(at.x + away.x * CHARGE_AT, at.y, at.z + away.y * CHARGE_AT), 0.0)
		else:
			b["pos"] = await u.walk(s, b["pos"], at, maxf(1.0, float(i.get("cast", 4.0)) - 1.0))
		var n0 = pushes.size()
		var r = await s.skill_cast(id, mid, b["pos"])
		if r["code"] == Proto.Code.NO_TARGET:
			b["bad"][mid] = true # nicht wählbar (Deko-Tier) oder schon tot
			tries -= 1
		if r["code"] in [Proto.Code.OUT_OF_RANGE, Proto.Code.TOO_CLOSE, Proto.Code.NO_TARGET, Proto.Code.SKILL_BUSY]:
			note = Proto.text(int(r["code"]))
			await create_timer(0.5).timeout
			continue
		if r["code"] != Proto.Code.OK:
			note = Proto.text(int(r["code"]))
			break
		var ended = func(): return pushes.slice(n0).any(func(e): return e[0] == "skill_end" and int(e[1]["src"]) == b["id"])
		await u.until(ended, float(r["data"].get("time", 1000)) / 1000.0 + 3.0)
		await create_timer(0.3).timeout
		var end = pushes.slice(n0).filter(func(e): return e[0] == "skill_end" and int(e[1]["src"]) == b["id"])
		var hit = pushes.slice(n0).filter(func(e): return e[0] == "hit" and int(e[1]["src"]) == b["id"] and int(e[1].get("skill", 0)) == id)
		var moved = pushes.slice(n0).filter(func(e): return e[0] == "skill_move" and int(e[1]["id"]) == b["id"])
		if not moved.is_empty():
			var mp: Array = moved[0][1]["pos"]
			b["pos"] = Vector3(mp[0], mp[1], mp[2]) # der Server kennt den neuen Ort
		if end.is_empty() or not end[0][1].get("ok", false):
			note = "Zaubern abgebrochen"
			await create_timer(0.5).timeout
			continue
		var h: Dictionary = hit[0][1] if not hit.is_empty() else {}
		var what = "verfehlt" if h.get("miss", false) else ("ohne Schaden (Fluch)" if h.get("nodmg", false) else "%d Schaden" % int(h.get("dmg", 0)))
		if charge:
			var dist = b["pos"].distance_to(u.npcs(pushes).get(mid, {}).get("at", b["pos"])) if not moved.is_empty() else -1.0
			var stun = pushes.slice(n0).any(func(e): return e[0] == "buffs" and int(e[1]["id"]) == mid and e[1]["list"].any(func(x): return int(x[0]) == 365))
			b["done"].append([not hit.is_empty() and not moved.is_empty() and (h.get("miss", false) or (h.get("nodmg", false) and stun)),
				"Ansturm %d: stürmt zum Monster (%.1f m davor), Treffer %s, betäubt (365) %s" % [id, dist, what, str(stun)]])
		else:
			b["done"].append([not hit.is_empty(), "%d trifft ein Monster: %s" % [id, what]])
		return
	b["done"].append([false, "%d nicht eingesetzt (%s)" % [id, note]])

# Stärkung auf sich selbst: Heilung oder ein Effekt an der Figur
func _bless(b: Dictionary, id: int) -> void:
	var s: Session = b["s"]
	var pushes: Array = s.get_meta("pushes")
	var n0 = pushes.size()
	var r = await s.skill_cast(id, 0, b["pos"])
	if r["code"] != Proto.Code.OK:
		b["done"].append([false, "Stärkung %d: %s" % [id, Proto.text(int(r["code"]))]])
		return
	var ended = func(): return pushes.slice(n0).any(func(e): return e[0] == "skill_end" and int(e[1]["src"]) == b["id"])
	await u.until(ended, float(r["data"].get("time", 1000)) / 1000.0 + 3.0)
	await create_timer(0.3).timeout
	var heals = pushes.slice(n0).filter(func(e): return e[0] == "heal" and int(e[1]["dst"]) == b["id"])
	var healed = not heals.is_empty()
	var buffed = pushes.slice(n0).filter(func(e): return e[0] == "buffs" and int(e[1]["id"]) == b["id"] and not e[1]["list"].is_empty())
	# Treffer-Meldung der Stärkung (für das Treffer-GFX im Client), Heilbetrag auch bei vollem Leben
	var hit = pushes.slice(n0).any(func(e): return e[0] == "hit" and e[1].get("bless", false) and int(e[1]["dst"]) == b["id"] and int(e[1]["skill"]) == id)
	var amount = int(heals[0][1]["amount"]) if healed else 0
	var ok = ended.call() and hit and ((healed and amount > 0) or not buffed.is_empty())
	b["done"].append([ok, "Stärkung %d auf sich: %s, hit bless %s" % [id, ("Heilung +%d bei vollem Leben" % amount) if healed else ("Effekt %s" % str(buffed[0][1]["list"].map(func(x): return int(x[0]))) if not buffed.is_empty() else "keine Wirkung"), str(hit)]])

# Stadtportal: still stehen, dann zum Stadtpunkt
func _portal(b: Dictionary) -> void:
	var s: Session = b["s"]
	var pushes: Array = s.get_meta("pushes")
	await create_timer(0.5).timeout
	var n0 = pushes.size()
	var r = await s.skill_cast(PORTAL, 0, b["pos"])
	if r["code"] != Proto.Code.OK:
		b["done"].append([false, "Stadtportal: %s" % Proto.text(int(r["code"]))])
		return
	var moved = func(): return pushes.slice(n0).any(func(e): return e[0] == "pos_correct")
	var town = Vector3.INF
	for q in towns.get(b["world"], []):
		if q.distance_to(b["pos"]) < town.distance_to(b["pos"]):
			town = q
	await u.until(moved, float(r["data"].get("time", 10000)) / 1000.0 + 3.0)
	var got = Vector3.INF
	for e in pushes.slice(n0):
		if e[0] == "pos_correct":
			got = Vector3(e[1]["pos"][0], e[1]["pos"][1], e[1]["pos"][2])
	b["done"].append([got.distance_to(town) < 1.0, "Stadtportal nach %.1f s: am Stadtpunkt %s (%s)" % [float(r["data"].get("time", 0)) / 1000.0,
		str(town), str(got) if got != Vector3.INF else "kein pos_correct"]])
	if got != Vector3.INF:
		b["pos"] = got

# fresh: nur eines, das die Figur noch nicht getroffen hat (Ansturm: das getroffene verfolgt sie, mindestens 8 m Abstand
# gäbe es dann nicht)
func _nearest_monster(b: Dictionary, fresh: bool = false) -> int:
	var pushes: Array = b["s"].get_meta("pushes")
	var nc = u.npcs(pushes)
	var hit = {}
	if fresh:
		for e in pushes:
			if e[0] == "hit" and int(e[1]["src"]) == b["id"]:
				hit[int(e[1]["dst"])] = true
	var best = INF
	var out = 0
	for id in nc:
		if monsters.has(int(nc[id]["tid"])) and not b["bad"].has(id) and not hit.has(id) and nc[id]["at"].distance_to(b["pos"]) < best:
			best = nc[id]["at"].distance_to(b["pos"])
			out = id
	return out

# Nächstes wählbares Monster vom Start aus den Spawn-Daten des Servers (wie npcs.gd sie anlegt) -> Ort
func _hunt_point(map_name: String, from: Vector3, templates, maps: Dictionary) -> Vector3:
	if not maps.has(map_name):
		var sb = load(PLUGIN_SERVER + "spawn_builder.gd")
		var terrain = load(PLUGIN_SERVER + "heightmap.gd").new()
		terrain.load_dir(sb.server_dir().path_join("data/" + map_name))
		var nm = Npcs.new(map_name, templates, {"next": Proto.NPC_ID_BASE})
		nm.load_spawns(load(PLUGIN_SERVER + "npcgen.gd").new().read(sb.npcgen_path(map_name)), map_name, terrain, 0.0, 1)
		maps[map_name] = nm
	var best = Vector3.INF
	for o in maps[map_name].objects.values():
		if not o["npc"] and not o.get("mine", false) and o["select"] and monsters.has(int(o["tid"])) \
				and o["home"].distance_to(from) < best.distance_to(from):
			best = o["home"]
	return best

func _check(what: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("KLASSEN-TEST: ", "ok      " if ok else "FEHLER  ", what)

func _end(code: int) -> void:
	if srv != null and srv.running():
		srv.kill(self)
	if code == 2:
		print("KLASSEN-TEST FEHLER: Zeitlimit (%d Prüfungen bis dahin)" % checks)
	elif failures == 0:
		print("KLASSEN-TEST OK (%d Prüfungen)" % checks)
	else:
		print("KLASSEN-TEST FEHLER: %d von %d Prüfungen" % [failures, checks])
	quit(code)

# Letzte Übersicht der Klassen-Fertigkeiten seit from ([[ID, nächste Stufe, benötigte Stufe, Kosten, ...]]), null ohne
func _catalog(b: Dictionary, from: int):
	var list = null
	for e in b["s"].get_meta("pushes").slice(from):
		if e[0] == "skill_catalog":
			list = e[1]["list"]
	return list

func _money(b: Dictionary, from: int, key: String = "money") -> int:
	var m = -1
	for e in b["s"].get_meta("pushes").slice(from):
		if e[0] == "stats" and e[1].has(key):
			m = int(e[1][key])
	return m

# Lernen (F8): bis Stufe 20 von selbst, darüber gegen Seelenmünzen (Z4), Gold nur auf Nachfrage
func _learning(b: Dictionary) -> void:
	var s: Session = b["s"]
	var pushes: Array = s.get_meta("pushes")
	var n0 = pushes.size()
	var r = await s.debug_char(10, 0)
	await create_timer(0.6).timeout
	var c10 = _catalog(b, n0)
	var news = pushes.slice(n0).filter(func(e): return e[0] == "skill_new").map(func(e): return int(e[1]["id"]))
	var done10 = c10 != null and c10.all(func(e): return int(e[1]) == 0 or int(e[2]) > 10)
	b["done"].append([r["code"] == Proto.Code.OK and done10 and not news.is_empty(),
		"Stufe 10: von selbst gelernt %s, alles bis Stufe 10 (%s)" % [str(news), str(done10)]])
	n0 = pushes.size()
	r = await s.debug_char(25, 0)
	await create_timer(0.6).timeout
	var c25 = _catalog(b, n0)
	var done20 = c25 != null and c25.all(func(e): return int(e[1]) == 0 or int(e[2]) > 20)
	var buy = c25.filter(func(e): return int(e[1]) > 0 and int(e[2]) > 20 and int(e[2]) <= 25) if c25 != null else []
	var high = c25.filter(func(e): return int(e[1]) > 0 and int(e[2]) > 25) if c25 != null else []
	if buy.is_empty():
		b["done"].append([done20, "Stufe 25: von selbst nur bis Stufe 20 (%s), keine Lernstufe zwischen 21 und 25" % str(done20)])
	else:
		var e: Array = buy[0]
		var poor = await s.skill_learn(int(e[0]))
		await s.debug_char(25, 10000000, 0)
		var only_gold = await s.skill_learn(int(e[0])) # ohne Seelenmünzen: erst fragen
		var n1 = pushes.size()
		var rich = await s.skill_learn(int(e[0]), true)
		await create_timer(0.4).timeout
		var money = _money(b, n1)
		var lv = pushes.slice(n1).filter(func(x): return x[0] == "skill_level" and int(x[1]["id"]) == int(e[0]))
		b["done"].append([done20 and poor["code"] == Proto.Code.NOT_ENOUGH_MONEY
			and only_gold["code"] == Proto.Code.NOT_ENOUGH_BIND_MONEY and int(only_gold["data"].get("cost", 0)) == int(e[3])
			and rich["code"] == Proto.Code.OK and int(rich["data"].get("gold", -1)) == int(e[3])
			and int(rich["data"].get("level", 0)) == int(e[1]) and money == 10000000 - int(e[3]) and not lv.is_empty(),
			"Stufe 25: von selbst nur bis 20 (%s); %d Stufe %d (ab %d) ohne Geld: %s, nur Gold: %s, Gold zugelassen: %s, %d Kupfer, Gold danach %d" % [
			str(done20), int(e[0]), int(e[1]), int(e[2]), Proto.text(int(poor["code"])), Proto.text(int(only_gold["code"])),
			Proto.text(int(rich["code"])), int(e[3]), money]])
		if buy.size() > 1: # Seelenmünzen (Z4): bezahlt ohne Nachfrage, Gold bleibt
			var e2: Array = buy[1]
			await s.debug_char(25, 500, 10000000)
			var n2 = pushes.size()
			var soul = await s.skill_learn(int(e2[0]))
			await create_timer(0.4).timeout
			var bind_after = _money(b, n2, "bind_money")
			var gold_after = _money(b, n2)
			b["done"].append([soul["code"] == Proto.Code.OK and int(soul["data"].get("bind", -1)) == int(e2[3])
				and int(soul["data"].get("gold", -1)) == 0 and bind_after == 10000000 - int(e2[3]) and gold_after == 500,
				"Seelenmünzen: %d Stufe %d für %d Kupfer -> %s, Seelenmünzen danach %d, Gold bleibt %d" % [int(e2[0]), int(e2[1]),
				int(e2[3]), Proto.text(int(soul["code"])), bind_after, gold_after]])
	if not high.is_empty():
		var t = await s.skill_learn(int(high[0][0]))
		b["done"].append([t["code"] == Proto.Code.SKILL_LEVEL_LOW and int(t["data"].get("need", 0)) == int(high[0][2]),
			"%d Stufe %d (ab %d) auf Stufe 25: %s" % [int(high[0][0]), int(high[0][1]), int(high[0][2]), Proto.text(int(t["code"]))]])
