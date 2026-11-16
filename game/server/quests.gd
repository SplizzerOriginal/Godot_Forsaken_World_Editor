extends RefCounted

# ====================================================
# Quests auf dem Server (Fahrplan Schritt 10), vereinfacht nach ATaskTempl (gs/task: CheckDeliverTask,
# DeliverTask, RecursiveAward). Daten: Plugin Server/quest_templates.json (tools/server_data/
# quest_templates.gd aus der tasks.data des Clients, dazu die Quest-Dienste der NPCs).
# Zustand je Figur (players[...]["quests"]): active {ID: {p: Fortschritt, t: angenommen}} für jede
# laufende Quest samt ihren laufenden Unteraufgaben, done {ID: {ok, times, t}} für erledigte Quests
# der obersten Ebene; in der Tabelle quests: state 0 = läuft, 1 = erfüllt, 2 = gescheitert.
# Vergabe (can_deliver, CheckPrerequisite): oberste Ebene, nicht gesperrt (block: Bedingungen, die
# der Server noch nicht prüft), nicht schon laufend, erledigt nur mit redo / redo_fail, Stufe,
# Rasse, Klasse, Geschlecht (1 = männlich, 2 = weiblich), alle Vorquests erfüllt, keine Ausschluss-
# Quest läuft oder ist erledigt, Mit-Quests (cotask: laufen alle bzw. mit cotask_any eine davon), Effekte (buffs:
# [Effekt, Mindest-Stufe, muss haben], buffs_all = alle, sonst einer), Platz für die ausgehändigten Gegenstände
# (given, kommen bei der Vergabe in die Tasche). Mit Unteraufgaben: der Reihe nach (order) nur die erste, sonst alle.
#   accept    am NPC, der vergibt (delv bzw. NPC_TASK_OUT_SERVICE), höchstens SERVICE_RANGE m entfernt
#   complete  am NPC, der abnimmt (anpc bzw. NPC_TASK_IN_SERVICE): Methode 3 "NPC ansprechen" ist damit
#             erfüllt; Methode 2 "Gegenstände sammeln", wenn alle gesuchten in der Tasche sind; andere
#             Methoden erst, wenn ihr Ziel erreicht ist (Kampf: später)
#   kill      Monster getötet (combat.gd): Methode 1 "Monster töten" zählt die Kills je Vorlage (Fortschritt
#             k {Vorlage: Anzahl}) bzw. - mit drop - kommt mit prob der Beute-Gegenstand in die Tasche, bis
#             drop_num erreicht ist; Abschluss "sofort" (f 0) dann erfüllt, sonst beim NPC. Mit clear
#             (m_bClearAcquired) wird die Beute beim Abschluss eingezogen (RemoveAcquiredItem).
#   mine      Sammeln an einem Punkt mit task_out (inventory.gd, CheckMining): läuft die Quest mit
#             Methode 2, kommt ihr erster gesuchter Gegenstand (1 Stück) in die Tasche, solange noch
#             welche fehlen; Abschluss "sofort" (f 0) ist dann erfüllt, sobald alle da sind
#             (check_items, auch nach jeder Belohnung). Die gesammelten Gegenstände bleiben (die
#             Quests hier haben kein m_bClearAcquired).
#   abandon   nur Quests der obersten Ebene mit giveup; gilt als gescheitert
#   tick      Methode 5 "Warten": erfüllt nach wait s (und mit fin_buffs); Zeitlimit (time): gescheitert
#   Methode 11 "Quest mehrmals erfüllen" (fin [Quest, Anzahl]): zählt, wie oft die Quest erfüllt wird, solange diese
#             läuft (Fortschritt n); Abschluss beim NPC erst mit fin_buffs (Effekte wie buffs, m_FinBuff)
# Abschluss einer Unteraufgabe: psucc -> auch die Eltern-Quest erfüllt; sonst der Reihe nach die
# nächste, ohne nächste bzw. wenn alle erfüllt sind die Eltern-Quest; Misserfolg mit pfail auch.
# Belohnung je erfüllter Quest: EXP (mit exp_lev * Stufenfaktor task_factor, stats.gd task_exp; Stufenaufstieg mit
# vollen HP / MP), Goldmünzen (gold) und Seelenmünzen
# (bind; mit money_lev * Stufenfaktor, stats.gd task_money; höchstens MONEY_MAX), Gegenstände (Gruppe
# random: einer nach prob, sonst alle; vorher Platz im Inventar geprüft, inventory.gd stapelt),
# Folgequest (new).
# Automatische Vergabe beim Betreten der Welt, nach jeder Vergabe / jedem Abschluss / Stufenaufstieg und wenn ein
# Spieler einen Effekt bekommt (buffs.gd on_gain): auto, vorläufig nur sichtbare Quests mit Rassen- / Klassen-
# Bedingung, Vorquest oder Mit-Quest (Story-Ketten wie 5678; 6967 "Erste Begegnung" der Kindred mit Effekt 914
# aus 1889 "初拥"). Versteckte automatische Quests nur, wenn sie allein eine Fertigkeit geben (grant_list: die
# Rassen-Segen 8702 - 8706 / 15802 ab Stufe 1, die Werwolf-Verwandlung 15800 / 15801 nach 15358): sofort erfüllt,
# ohne Meldung in der Quest-Liste. Die übrigen automatischen Quests und die versteckten Auslöser-Quests (z.B. 15014
# "Gnädiger Mut", sofort erfüllt mit Folgequest voller Gegenstände) warten auf Bedingungen, die es noch nicht
# gibt (Gebiete, Zähler, Kontomerkmale, Lua) bzw. die erst die Server-Quests (v179) zeigen. Dazu (Z5) die Essenz-Geschenke
# je Stufe (_gift: Vorquest 13008 aus DONE_BY_DEFAULT, Stufenfenster der Server-tasks.data, z.B. 12699 genau Stufe 10).
# Vorbedingungs-Gegenstände (prem [ID, Anzahl, deposit]) müssen in der Tasche sein, mit deposit zieht deliver sie ein.
# Fenster-Quests (ui) nimmt accept auch ohne NPC an (Essenz-Tausch); dice vergibt die Quest eines benutzten Quest-Würfels.
# Meldungen an den Spieler: quests {active: [[ID, Fortschritt]], done: [IDs]}, quest_event {id, kind
# ("new" / "done" / "failed" / "bag_full"), exp, gold, bind, items}, stats {level, exp, exp_next, hp,
# max_hp, mp, max_mp, money, bind_money, attr}.
# ====================================================

const Proto = preload("../common/protocol.gd")
const Stats = preload("stats.gd")
const Buffs = preload("buffs.gd")
const PLUGIN_SERVER = "res://addons/PWE-Manager/Server/"
const SERVICE_RANGE = 10.0 # m, MAX_SERVICE_DISTANCE des gs
const ACTIVE = 0
const SUCCESS = 1
const FAILED = 2
const MONEY_MAX = 2000000000 # Kupfer je Währung (MAX_BIND_MONEY des gs; Goldmünzen ebenso)
# Lua- / Fenster-Quests, die als Vorquest gelten, ohne dass der Server sie vergibt: 13008 "Prüfungs-Essenz erhalten"
# (m_bUIButtonTask, Skript in task_list1.lua: zahlt beim ersten Mal die Essenzen früherer Stufen nach) - unsere Figuren
# beginnen auf Stufe 1, also gibt es nichts nachzuzahlen; die Geschenke je Stufe (12692 ...) setzen sie voraus
const DONE_BY_DEFAULT = {13008: true}

var db
var net
var log_line: Callable
var stats # stats.gd
var inventory = null # inventory.gd (setzt der Server)
var buffs = null # buffs.gd (setzt der Server): Prozent-Werte der Effekte nach dem Stufenaufstieg neu
var skills = null # skills.gd (setzt der Server): Fertigkeiten aus Belohnungen (award skill / del_skill)
var on_level_up: Callable # (p) nach einem Stufenaufstieg (skills.gd auto_learn bis Stufe 20)
var tasks = {} # ID -> Quest (quest_templates.json)
var npc_out = {} # NPC-Vorlage -> [Quest-IDs]
var npc_in = {}
var auto_list: Array = [] # automatisch vergebbare Quests der obersten Ebene
var grant_list: Array = [] # versteckte automatische Quests, die nur eine Fertigkeit geben (sofort erfüllt)
var _auto_busy = false # auto_deliver läuft (Vergaben darin rufen es wieder auf)
var _auto_again = false


func _init(p_db, p_net, p_log: Callable, p_stats) -> void:
	db = p_db
	net = p_net
	log_line = p_log
	stats = p_stats

# quest_templates.json laden -> "" oder Fehlertext
func load_templates() -> String:
	var path = PLUGIN_SERVER + "quest_templates.json"
	var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not d is Dictionary or not d.has("tasks"):
		return path + " fehlt oder ist unlesbar"
	for k in d["tasks"]:
		tasks[int(k)] = _ints(d["tasks"][k])
	for part in [[npc_out, "npc_out"], [npc_in, "npc_in"]]:
		for k in d.get(part[1], {}):
			part[0][int(k)] = d[part[1]][k].map(func(x): return int(x))
	for id in tasks:
		var t = tasks[id]
		if t.has("p") or not t.get("auto", false) or t.has("block"):
			continue
		var cond = t.has("race") or t.has("occ") or t.has("pre") or t.has("cotask")
		if not t.get("hidden", false) and cond:
			auto_list.append(id)
		elif t.get("hidden", false) and (cond or t.has("gender")) and _skill_only(t.get("award", {})):
			grant_list.append(id)
		elif t.get("hidden", false) and _gift(t):
			grant_list.append(id) # Essenz-Geschenke je Stufe (Z5)
	auto_list.sort()
	grant_list.sort()
	return ""

# JSON-Zahlen (float) -> int, Listen von IDs ebenso
static func _ints(t: Dictionary) -> Dictionary:
	for k in t:
		var v = t[k]
		if v is float:
			t[k] = int(v)
		elif v is Array and k in ["s", "pre", "mutex", "race", "occ", "lv", "cotask", "fin"]:
			t[k] = v.map(func(x): return int(x))
	return t

func task(id: int) -> Dictionary:
	return tasks.get(id, {})

# Geschenk je Stufe (Z5): hängt an einer Fenster-Quest aus DONE_BY_DEFAULT, Stufenfenster aus der Server-tasks.data,
# Belohnung nur Gegenstände (12692 - 12759 "Geschenk: Prüfungs-Essenz!")
static func _gift(t: Dictionary) -> bool:
	var a: Dictionary = t.get("award", {})
	if not t.has("lv") or not a.has("items") or a.size() != 1:
		return false
	for pre in t.get("pre", []):
		if DONE_BY_DEFAULT.has(int(pre)):
			return true
	return false

# Belohnung nur aus einer Fertigkeit (und ggf. einer, die dafür wegfällt)?
static func _skill_only(a: Dictionary) -> bool:
	if not a.has("skill"):
		return false
	for k in a:
		if not k in ["skill", "del_skill"]:
			return false
	return true


# ====================================================
# ZUSTAND JE FIGUR
# ====================================================
func load_player(p: Dictionary) -> void:
	var q = {"active": {}, "done": {}}
	var rows = db.query("SELECT task_id, state, progress, accepted, finished, times FROM quests WHERE character_id = ?", [p["id"]])
	for r in (rows if rows != null else []):
		var id = int(r["task_id"])
		if not tasks.has(id):
			continue
		if int(r["state"]) == ACTIVE:
			var prog = JSON.parse_string(str(r["progress"]))
			q["active"][id] = {"p": prog if prog is Dictionary else {}, "t": int(r["accepted"]) if r["accepted"] != null else 0}
		else:
			q["done"][id] = {"ok": int(r["state"]) == SUCCESS, "times": int(r["times"]), "t": int(r["finished"]) if r["finished"] != null else 0}
			var dp = JSON.parse_string(str(r["progress"]))
			if dp is Dictionary and dp.has("pk"): # Zähler je Zeitraum (max_fin)
				q["done"][id]["pk"] = int(dp["pk"])
				q["done"][id]["pn"] = int(dp.get("pn", 0))
	p["quests"] = q

# Zustand für den Client: {active: [[ID, Fortschritt]], done: [IDs]}
func state_of(p: Dictionary) -> Dictionary:
	var q: Dictionary = p["quests"]
	var active = []
	for id in q["active"]:
		active.append([id, q["active"][id]["p"]])
	var done = []
	for id in q["done"]:
		if q["done"][id]["ok"]:
			done.append(id)
	return {"active": active, "done": done}

func _push_state(peer: int, p: Dictionary) -> void:
	net.push(peer, "quests", state_of(p))


# ====================================================
# VERGABE
# ====================================================
# Bedingungen einer Quest der obersten Ebene -> Code (OK = vergebbar)
func can_deliver(p: Dictionary, id: int) -> int:
	var t = task(id)
	if t.is_empty() or t.has("p") or t.has("block"):
		return Proto.Code.QUEST_INVALID
	var q: Dictionary = p["quests"]
	if q["active"].has(id):
		return Proto.Code.QUEST_CONDITIONS
	if q["done"].has(id):
		var ok = q["done"][id]["ok"]
		if (ok and not t.get("redo", false)) or (not ok and not t.get("redo_fail", false)):
			return Proto.Code.QUEST_CONDITIONS
		var mf: Array = t.get("max_fin", [])
		if mf.size() == 2 and int(q["done"][id].get("pk", -1)) == _period(int(mf[1]), _now()) \
				and int(q["done"][id].get("pn", 0)) >= int(mf[0]):
			return Proto.Code.QUEST_LIMIT
	var lv: Array = t.get("lv", [0, 0])
	if (int(lv[0]) != 0 and p["level"] < int(lv[0])) or (int(lv[1]) != 0 and p["level"] > int(lv[1])):
		return Proto.Code.QUEST_CONDITIONS
	if t.has("race") and not _has(t["race"], p["race"]):
		return Proto.Code.QUEST_CONDITIONS
	if t.has("occ") and not _has(t["occ"], p["class"]):
		return Proto.Code.QUEST_CONDITIONS
	var g = int(t.get("gender", 0))
	if (g == 1 and p["gender"] != 0) or (g == 2 and p["gender"] != 1):
		return Proto.Code.QUEST_CONDITIONS
	for pre in t.get("pre", []):
		var d = q["done"].get(int(pre))
		if (d == null or not d["ok"]) and not DONE_BY_DEFAULT.has(int(pre)):
			return Proto.Code.QUEST_CONDITIONS
	for it in t.get("prem", []): # Gegenstände in der Tasche (m_PremItems)
		if inventory == null or inventory.count_of(p, int(it[0])) < int(it[1]):
			return Proto.Code.QUEST_CONDITIONS
	for m in t.get("mutex", []):
		if q["active"].has(int(m)) or q["done"].has(int(m)):
			return Proto.Code.QUEST_CONDITIONS
	if t.has("cotask") and not _cotask_ok(p, t):
		return Proto.Code.QUEST_CONDITIONS
	if t.has("buffs") and not buffs_ok(p, t["buffs"], t.get("buffs_all", false)):
		return Proto.Code.QUEST_CONDITIONS
	if not _given_room(p, id):
		return Proto.Code.QUEST_BAG_FULL
	return Proto.Code.OK

# Mit-Quests laufen (alle bzw. eine davon)
static func _cotask_ok(p: Dictionary, t: Dictionary) -> bool:
	var any = t.get("cotask_any", false)
	for c in t["cotask"]:
		var running: bool = p["quests"]["active"].has(int(c))
		if running and any:
			return true
		if not running and not any:
			return false
	return not any

# Effekt-Bedingung [[Effekt, Mindest-Stufe, muss haben]]: alle bzw. eine erfüllt (Stufe = Stapel des Effekts)
static func buffs_ok(p: Dictionary, list: Array, all: bool) -> bool:
	if list.is_empty():
		return true
	var hits = 0
	for e in list:
		var has = false
		for b in p.get("buffs", []):
			if int(b["id"]) == int(e[0]) and (int(e[1]) == 0 or int(b.get("stack", 1)) >= int(e[1])):
				has = true
				break
		if has == bool(e[2]):
			hits += 1
	return hits == list.size() if all else hits > 0

# Platz für die Gegenstände, die die Quest (und ihre ersten Unteraufgaben) bei der Vergabe aushändigt
func _given_room(p: Dictionary, id: int) -> bool:
	var need = _given_of(id)
	return need.is_empty() or (inventory != null and inventory.can_add(p, need))

func _given_of(id: int) -> Array:
	var t = task(id)
	var out = []
	for g in t.get("given", []):
		out.append([int(g["id"]), maxi(1, int(g["num"]))])
	var subs: Array = t.get("s", [])
	if not subs.is_empty():
		var first = subs if not (t.get("order", false) or t.get("one", false) or t.get("rand", false)) else [subs[0]]
		for sid in first:
			out.append_array(_given_of(int(sid)))
	return out

static func _has(list: Array, v: int) -> bool:
	for x in list:
		if int(x) == v:
			return true
	return false

# Quest (oberste Ebene) samt laufender Unteraufgaben eintragen (DeliverTask)
func deliver(peer: int, p: Dictionary, id: int) -> void:
	var now = _now()
	_take_prem(peer, p, id)
	_add_active(p, id, now)
	var given = _hand_out(peer, p, id)
	_push_state(peer, p)
	var ev = {"id": id, "kind": "new"}
	if not given.is_empty():
		ev["items"] = given
	net.push(peer, "quest_event", ev)
	log_line.call("Quest: %s bekommt %d '%s'" % [p["name"], id, task(id).get("name", "")])
	check_items(peer, p) # gesuchte Gegenstände schon in der Tasche (z.B. 15766 mit 44134 aus 15358)
	auto_deliver(peer, p) # Quests mit dieser als Mit-Quest

# Vorbedingungs-Gegenstände mit deposit einziehen (RemovePrerequisiteItem: z.B. die Essenzen beim Tausch)
func _take_prem(peer: int, p: Dictionary, id: int) -> void:
	var taken = false
	for it in task(id).get("prem", []):
		if it.size() > 2 and bool(it[2]) and inventory != null:
			inventory.remove(p, int(it[0]), int(it[1]))
			taken = true
	if taken:
		inventory.push(peer, p)

# Ausgehändigte Gegenstände (given) der Quest und ihrer gerade begonnenen Unteraufgaben -> [[ID, Anzahl, Platz]]
func _hand_out(peer: int, p: Dictionary, id: int) -> Array:
	var out = []
	if inventory == null:
		return out
	for it in _given_of(id):
		var put: Array = inventory.add(p, it[0], it[1])
		if not put.is_empty():
			out.append([it[0], it[1], put[0][0]])
	if not out.is_empty():
		inventory.push(peer, p)
	return out

# Versteckte Quest, die nur eine Fertigkeit gibt (grant_list): eintragen und gleich erfüllen
func _grant(peer: int, p: Dictionary, id: int) -> void:
	_add_active(p, id, _now())
	log_line.call("Quest: %s bekommt versteckt %d '%s'" % [p["name"], id, task(id).get("name", "")])
	finish(peer, p, id, true)

func _add_active(p: Dictionary, id: int, now: int) -> void:
	var t = task(id)
	var prog = {}
	if int(t.get("m", 0)) == 5:
		prog["until"] = now + int(t.get("wait", 0))
	p["quests"]["active"][id] = {"p": prog, "t": now}
	_save_row(p, id, ACTIVE, prog, now, null, 0)
	var subs: Array = t.get("s", [])
	if subs.is_empty():
		return
	if t.get("order", false) or t.get("one", false) or t.get("rand", false):
		_add_active(p, int(subs[0]), now)
	else:
		for s in subs:
			_add_active(p, int(s), now)

# Automatische Quests vergeben, deren Bedingungen erfüllt sind
func auto_deliver(peer: int, p: Dictionary) -> void:
	if _auto_busy:
		_auto_again = true # eine Vergabe darin: noch eine Runde
		return
	_auto_busy = true
	_auto_again = true
	while _auto_again:
		_auto_again = false
		for id in grant_list:
			if can_deliver(p, id) == Proto.Code.OK:
				_grant(peer, p, id)
		for id in auto_list:
			if can_deliver(p, id) == Proto.Code.OK:
				deliver(peer, p, id)
	_auto_busy = false


# ====================================================
# ANFRAGEN -> [Code, Daten]
# ====================================================
# NPC_GIVE_TASK: Quest beim NPC annehmen; ohne NPC nur Fenster-Quests (ui, ohne vergebenden NPC, sichtbar - z.B. der
# Essenz-Tausch in Win_LvupAward, GameApi.AcceptTask)
func accept(peer: int, p: Dictionary, npc: Dictionary, id: int) -> Array:
	var t = task(id)
	if t.is_empty() or t.has("p"):
		return [Proto.Code.QUEST_INVALID, {}]
	var ui = npc.is_empty() and t.get("ui", false) and not t.get("hidden", false) and int(t.get("delv", 0)) == 0
	if not ui and (npc.is_empty() or not _near(p, npc) or not (int(t.get("delv", 0)) == npc["tid"] or _has(npc_out.get(npc["tid"], []), id))):
		return [Proto.Code.QUEST_NOT_HERE, {}]
	var code = can_deliver(p, id)
	if code != Proto.Code.OK:
		return [code, {}]
	deliver(peer, p, id)
	if ui:
		tick(peer, p) # Warten 0 s, sofort erfüllt: die Belohnung kommt gleich
	return [Proto.Code.OK, {"id": id}]

# Quest-Würfel benutzt (inventory.gd use, z.B. EXP-Cocktail 9056 -> 4218): die Quest vergeben und sofort erfüllen
func dice(peer: int, p: Dictionary, id: int) -> int:
	var code = can_deliver(p, id)
	if code == Proto.Code.OK:
		_grant(peer, p, id)
	return code

# NPC_COMPLETE_TASK: laufende Quest beim NPC abschließen
func complete(peer: int, p: Dictionary, npc: Dictionary, id: int) -> Array:
	var t = task(id)
	if t.is_empty():
		return [Proto.Code.QUEST_INVALID, {}]
	if not p["quests"]["active"].has(id) or not t.get("s", []).is_empty():
		return [Proto.Code.QUEST_NOT_ACTIVE, {}]
	if npc.is_empty() or not _near(p, npc) or not (int(t.get("anpc", 0)) == npc["tid"] or _has(npc_in.get(npc["tid"], []), id)):
		return [Proto.Code.QUEST_NOT_HERE, {}]
	if not _goal_reached(p, id) or (t.has("fin_buffs") and not buffs_ok(p, t["fin_buffs"], t.get("fin_buffs_all", false))):
		return [Proto.Code.QUEST_NOT_DONE, {}]
	if not _bag_room(p, id):
		return [Proto.Code.QUEST_BAG_FULL, {}]
	finish(peer, p, id, true)
	return [Proto.Code.OK, {"id": id}]

func abandon(peer: int, p: Dictionary, id: int) -> Array:
	var t = task(id)
	if not p["quests"]["active"].has(id) or t.has("p"):
		return [Proto.Code.QUEST_NOT_ACTIVE, {}]
	if not t.get("giveup", false):
		return [Proto.Code.QUEST_NO_GIVEUP, {}]
	finish(peer, p, id, false)
	return [Proto.Code.OK, {"id": id}]

# Ziel einer Quest ohne Unteraufgaben erreicht? (3 NPC ansprechen: ja; 5 Warten: Zeit um;
# 2 Gegenstände: alle gesuchten in der Tasche)
func _goal_reached(p: Dictionary, id: int) -> bool:
	var t = task(id)
	match int(t.get("m", 0)):
		1:
			if t.get("mon", []).is_empty():
				return false
			var prog: Dictionary = p["quests"]["active"][id]["p"].get("k", {})
			for m in t["mon"]:
				if int(m.get("drop", 0)) != 0:
					if inventory == null or inventory.count_of(p, int(m["drop"])) < int(m["drop_num"]):
						return false
				elif int(prog.get(str(int(m["id"])), 0)) < int(m["num"]):
					return false
			return true
		2:
			if inventory == null or t.get("items", []).is_empty():
				return false
			for it in t["items"]:
				if inventory.count_of(p, int(it["id"])) < maxi(1, int(it["num"])):
					return false
			return true
		3:
			return true
		5:
			return _now() >= int(p["quests"]["active"][id]["p"].get("until", 0))
		11:
			return t.has("fin") and int(p["quests"]["active"][id]["p"].get("n", 0)) >= int(t["fin"][1])
	return false

# Sammeln für die Quest id (CheckMining) -> gegebene Gegenstände [[ID, Anzahl]]
func mine(peer: int, p: Dictionary, id: int) -> Array:
	var t = task(id)
	if not p["quests"]["active"].has(id) or int(t.get("m", 0)) != 2 or t.get("items", []).is_empty() or inventory == null:
		return []
	var want: Dictionary = t["items"][0]
	var item_id = int(want["id"])
	if int(want["num"]) > 0 and inventory.count_of(p, item_id) >= int(want["num"]):
		return []
	if not inventory.can_add(p, [[item_id, 1]]):
		net.push(peer, "quest_event", {"id": id, "kind": "bag_full"})
		return []
	inventory.add(p, item_id, 1)
	return [[item_id, 1]]

# Monster tid getötet: Kills / Beute der laufenden Quests mit Methode 1
func kill(peer: int, p: Dictionary, tid: int) -> void:
	var changed = false
	var bag = false
	for id in p["quests"]["active"].keys():
		var t = task(id)
		if int(t.get("m", 0)) != 1 or not t.get("s", []).is_empty():
			continue
		var e: Dictionary = p["quests"]["active"][id]
		for m in t.get("mon", []):
			if int(m["id"]) != tid:
				continue
			if int(m.get("drop", 0)) != 0:
				var drop = int(m["drop"])
				if inventory != null and inventory.count_of(p, drop) < int(m["drop_num"]) and randf() <= float(m.get("prob", 1.0)):
					if inventory.can_add(p, [[drop, 1]]):
						inventory.add(p, drop, 1)
						bag = true
					else:
						net.push(peer, "quest_event", {"id": id, "kind": "bag_full"})
			else:
				var k: Dictionary = e["p"].get("k", {})
				var key = str(tid)
				if int(k.get(key, 0)) < int(m["num"]):
					k[key] = int(k.get(key, 0)) + 1
					e["p"]["k"] = k
					_save_row(p, id, ACTIVE, e["p"], e["t"], null, 0)
					changed = true
	if bag:
		inventory.push(peer, p)
	if changed or bag:
		_push_state(peer, p)
	for id in p["quests"]["active"].keys():
		if not p["quests"]["active"].has(id):
			continue
		var t = task(id)
		if int(t.get("m", 0)) == 1 and int(t.get("f", 0)) == 0 and t.get("s", []).is_empty() and _goal_reached(p, id) and _bag_room(p, id):
			finish(peer, p, id, true)

# Gegenstands-Ziele mit Abschluss "sofort" prüfen (nach jeder Änderung der Tasche)
func check_items(peer: int, p: Dictionary) -> void:
	for id in p["quests"]["active"].keys():
		if not p["quests"]["active"].has(id):
			continue
		var t = task(id)
		if int(t.get("m", 0)) == 2 and int(t.get("f", 0)) == 0 and t.get("s", []).is_empty() and _goal_reached(p, id) \
				and _bag_room(p, id):
			finish(peer, p, id, true)

func _near(p: Dictionary, npc: Dictionary) -> bool:
	return npc.has("pos") and p["pos"].distance_to(npc["pos"]) <= SERVICE_RANGE


# ====================================================
# ABSCHLUSS UND BELOHNUNG
# ====================================================
# Quest id erfüllt (ok) oder gescheitert; reicht das an die Eltern-Quest weiter
func finish(peer: int, p: Dictionary, id: int, ok: bool) -> void:
	var t = task(id)
	var q: Dictionary = p["quests"]
	var now = _now()
	_clear_subtree(p, id)
	var award = {}
	if ok:
		award = _award(peer, p, t)
		if t.get("clear", false) and int(t.get("m", 0)) == 1 and inventory != null:
			var taken = 0
			for m in t.get("mon", []):
				if int(m.get("drop", 0)) != 0:
					taken += inventory.remove(p, int(m["drop"]), int(m["drop_num"]))
			if taken > 0:
				inventory.push(peer, p)
	if not t.has("p"):
		var times = int(q["done"].get(id, {}).get("times", 0)) + (1 if ok else 0)
		var before: Dictionary = q["done"].get(id, {})
		q["done"][id] = {"ok": ok, "times": times, "t": now}
		var rec = {}
		var mf: Array = t.get("max_fin", [])
		if mf.size() == 2: # erfüllt in diesem Zeitraum (Tag / Woche / insgesamt) mitzählen
			var pk = _period(int(mf[1]), now)
			var pn = int(before.get("pn", 0)) if int(before.get("pk", -1)) == pk else 0
			rec = {"pk": pk, "pn": pn + (1 if ok else 0)}
			q["done"][id].merge(rec)
		_save_row(p, id, SUCCESS if ok else FAILED, rec, null, now, times)
		var ev = {"id": id, "kind": "done" if ok else "failed"}
		ev.merge(award)
		net.push(peer, "quest_event", ev)
		log_line.call("Quest: %s %s %d '%s'%s" % [p["name"], "erfüllt" if ok else "scheitert an", id, t.get("name", ""),
			(" (+%d EXP)" % award.get("exp", 0)) if award.get("exp", 0) else ""])
		if ok:
			_count_finish(p, id)
		if ok and int(t.get("award", {}).get("new", 0)) != 0:
			var nid = int(t["award"]["new"])
			if can_deliver(p, nid) == Proto.Code.OK:
				deliver(peer, p, nid)
		_push_state(peer, p)
		auto_deliver(peer, p)
		return
	var parent_id = int(t["p"])
	var parent = task(parent_id)
	if not award.is_empty():
		var ev = {"id": id, "kind": "done"}
		ev.merge(award)
		net.push(peer, "quest_event", ev)
	if not ok:
		if t.get("pfail", false) and q["active"].has(parent_id):
			finish(peer, p, parent_id, false)
		else:
			_push_state(peer, p)
		return
	if t.get("psucc", false):
		finish(peer, p, parent_id, true)
		return
	var subs: Array = parent.get("s", [])
	if parent.get("order", false):
		var at = subs.find(id)
		if at >= 0 and at + 1 < subs.size():
			_add_active(p, int(subs[at + 1]), now)
			if not _hand_out(peer, p, int(subs[at + 1])).is_empty():
				check_items(peer, p)
			_push_state(peer, p)
			log_line.call("Quest: %s weiter mit %d '%s'" % [p["name"], int(subs[at + 1]), task(int(subs[at + 1])).get("name", "")])
			return
		finish(peer, p, parent_id, true)
		return
	for s in subs:
		if q["active"].has(int(s)):
			_push_state(peer, p) # Geschwister laufen noch
			return
	finish(peer, p, parent_id, true)

# Methode 11: laufende Quests, die auf das Erfüllen von id warten, zählen mit (Fortschritt n)
func _count_finish(p: Dictionary, id: int) -> void:
	for qid in p["quests"]["active"]:
		var w = task(qid)
		if int(w.get("m", 0)) == 11 and w.has("fin") and int(w["fin"][0]) == id:
			var e: Dictionary = p["quests"]["active"][qid]
			if int(e["p"].get("n", 0)) < int(w["fin"][1]):
				e["p"]["n"] = int(e["p"].get("n", 0)) + 1
				_save_row(p, qid, ACTIVE, e["p"], e["t"], null, 0)
				log_line.call("Quest: %s zählt für %d '%s' (%d/%d)" % [p["name"], qid, w.get("name", ""), e["p"]["n"], int(w["fin"][1])])

# Laufende Einträge einer Quest und ihrer Unteraufgaben entfernen
func _clear_subtree(p: Dictionary, id: int) -> void:
	var q: Dictionary = p["quests"]
	if q["active"].has(id):
		q["active"].erase(id)
		db.run("DELETE FROM quests WHERE character_id = ? AND task_id = ? AND state = ?", [p["id"], id, ACTIVE])
	for s in task(id).get("s", []):
		_clear_subtree(p, int(s))

# Belohnung einer erfüllten Quest -> {exp, gold, items: [[ID, Anzahl]]}
func _award(peer: int, p: Dictionary, t: Dictionary) -> Dictionary:
	var a: Dictionary = t.get("award", {})
	if a.is_empty():
		return {}
	var out = {}
	var changed = false
	var lev = int(a.get("money_lev", 0))
	var gold = Stats.task_money(int(a.get("gold", 0)), lev, int(p["level"]), stats.task_money_factor if stats != null else [])
	var bind = Stats.task_money(int(a.get("bind", 0)), lev, int(p["level"]), stats.task_bind_money_factor if stats != null else [])
	if gold > 0:
		out["gold"] = add_money(p, "money", gold)
		changed = true
	if bind > 0:
		out["bind"] = add_money(p, "bind_money", bind)
		changed = true
	var items = _award_items(a)
	if not items.is_empty() and inventory != null:
		out["items"] = []
		for it in items:
			var put: Array = inventory.add(p, it[0], it[1])
			if put.is_empty():
				break
			out["items"].append([it[0], it[1], put[0][0]])
		inventory.push(peer, p)
	if skills != null and int(a.get("del_skill", 0)) != 0:
		skills.forget(peer, p, int(a["del_skill"]))
	var sk: Array = a.get("skill", [])
	if skills != null and sk.size() == 2 and int(p.get("skills", {}).get(int(sk[0]), 0)) < int(sk[1]):
		skills.learn(peer, p, int(sk[0]), int(sk[1])) # z.B. Rassen-Segen (Segen der Menschen 8702 ...)
		out["skill"] = [int(sk[0]), int(sk[1])]
	var xp = Stats.task_exp(int(a.get("exp", 0)), int(a.get("exp_lev", 0)), a.get("exp_fix", false), int(p["level"]),
		stats.task_factor if stats != null else [])
	if xp != 0:
		out["exp"] = xp
		add_exp(p, xp)
		changed = true
	if changed:
		save_stats(p)
		net.push(peer, "stats", stats_of(p))
	return out

# Gegenstände einer Belohnung: [[ID, Anzahl]]
func _award_items(a: Dictionary) -> Array:
	var out = []
	for g in a.get("items", []):
		var list: Array = g.get("items", [])
		if g.get("random", false):
			var r = randf()
			for it in list:
				r -= float(it.get("prob", 0.0))
				if r <= 0.0:
					out.append([int(it["id"]), maxi(1, int(it["num"]))])
					break
		else:
			for it in list:
				out.append([int(it["id"]), maxi(1, int(it["num"]))])
	return out

# Reicht der Platz im Inventar für die Gegenstände der Quest (und ihrer Eltern, die mit ihr enden)?
# Bei einer Zufallsgruppe zählt der größte mögliche Gegenstand.
func _bag_room(p: Dictionary, id: int) -> bool:
	var need = []
	var t = task(id)
	while not t.is_empty():
		for g in t.get("award", {}).get("items", []):
			var list: Array = g.get("items", [])
			if g.get("random", false) and not list.is_empty():
				var big = list[0]
				for it in list:
					if int(it["num"]) > int(big["num"]):
						big = it
				need.append([int(big["id"]), maxi(1, int(big["num"]))])
			else:
				for it in list:
					need.append([int(it["id"]), maxi(1, int(it["num"]))])
		if not t.has("p") or not t.get("psucc", false) and not _last_in_order(t):
			break
		t = task(int(t["p"]))
	return need.is_empty() or (inventory != null and inventory.can_add(p, need))

func _last_in_order(t: Dictionary) -> bool:
	var parent = task(int(t.get("p", 0)))
	var subs: Array = parent.get("s", [])
	return parent.get("order", false) and not subs.is_empty() and int(subs[subs.size() - 1]) == int(t["id"])

# EXP dazu; Stufenaufstieg wie PLAYER_LEVELEXP_CONFIG (EXP bis zur nächsten Stufe), volle HP / MP
func add_exp(p: Dictionary, amount: int) -> void:
	p["exp"] = int(p.get("exp", 0)) + amount
	var was = int(p["level"])
	var need = stats.exp_next(p["level"])
	while need > 0 and p["exp"] >= need:
		p["exp"] -= need
		p["level"] += 1
		if inventory != null:
			inventory.apply_stats(p)
		else:
			p["max_hp"] = stats.max_hp(p["class"], p["level"], p["max_hp"])
			p["max_mp"] = stats.max_mp(p["class"], p["level"], p["max_mp"])
		if buffs != null:
			buffs.refresh(p) # z.B. passiv +1 % Leben je Stufe: vom neuen Grundwert
		p["hp"] = p["max_hp"]
		p["mp"] = p["max_mp"]
		log_line.call("Stufe: %s erreicht Stufe %d" % [p["name"], p["level"]])
		need = stats.exp_next(p["level"])
	if int(p["level"]) > was and on_level_up.is_valid():
		on_level_up.call(p)

# Geld gutschreiben ("money" Goldmünzen / "bind_money" Seelenmünzen), höchstens MONEY_MAX -> tatsächlich erhalten
static func add_money(p: Dictionary, key: String, amount: int) -> int:
	var before = int(p.get(key, 0))
	p[key] = clampi(before + amount, 0, MONEY_MAX)
	return int(p[key]) - before

func stats_of(p: Dictionary) -> Dictionary:
	return {"level": p["level"], "exp": p.get("exp", 0), "exp_next": stats.exp_next(p["level"]), "hp": p["hp"],
		"max_hp": p["max_hp"], "mp": p["mp"], "max_mp": p["max_mp"], "money": p.get("money", 0),
		"bind_money": p.get("bind_money", 0), "attr": attr_of(p),
		"speed_add": float(p.get("speed_add", 0.0))}

# Kampfwerte für das Charakter-Fenster wie CDlgCharacter::UpdateInfo / UpdateInfoEx: Grundwerte mit Ausrüstung (attr) und
# den Effekten (Buffs.with_mods: Angriff, Verteidigung, Genauigkeit, Ausweichen, Krit), dazu Meisterschaft (mas) und Widerstand
# (res) je [physisch, Erde, Wasser, Feuer, Wind, Licht, Dunkel, PvE]: Grundwert der Klasse (stats.gd) + Effekte (mastery0..6 /
# res0..6 und "alle"); der achte Platz zeigt im Original PvE-Intensität / -Zähigkeit (eigene Werte, anfangs 0, ohne Segen)
static func attr_of(p: Dictionary) -> Dictionary:
	var base: Dictionary = p.get("attr", {})
	var a: Dictionary = Buffs.with_mods(base, p).duplicate()
	var d: Array = a.get("dmg", [0, 0])
	a["dmg"] = [int(d[0]), int(d[1])]
	for k in ["def", "hit", "eva"]:
		a[k] = int(a.get(k, 0))
	for k in ["crit", "crit_dmg", "anti_crit", "anti_crit_dmg"]:
		a[k] = snappedf(float(a.get(k, 0.0)), 0.1)
	a.erase("absorb")
	var m: Dictionary = p.get("buff_mod", {})
	var base_mas: Array = base.get("mas", [])
	var base_res: Array = base.get("res", [])
	var res = []
	var mas = []
	for i in 8:
		if i == 7:
			mas.append(0) # PvE-Intensität
			res.append(0) # PvE-Zähigkeit
			continue
		mas.append(int(round((float(base_mas[i]) if i < base_mas.size() else 0.0) + float(m.get("mastery%d" % i, 0.0)) + float(m.get("mastery_all", 0.0)))))
		res.append(int(round((float(base_res[i]) if i < base_res.size() else 0.0) + float(m.get("res%d" % i, 0.0)) + float(m.get("res_all", 0.0)))))
	a["res"] = res
	a["mas"] = mas
	return a

func save_stats(p: Dictionary) -> void:
	if not db.run("UPDATE characters SET level = ?, exp = ?, hp = ?, mp = ?, money = ?, bind_money = ? WHERE id = ?",
			[p["level"], p.get("exp", 0), p["hp"], p["mp"], p.get("money", 0), p.get("bind_money", 0), p["id"]]):
		log_line.call("FEHLER Datenbank: " + db.last_error)


# ====================================================
# TAKT
# ====================================================
# Warten (Methode 5) und Zeitlimits der laufenden Quests eines Spielers
func tick(peer: int, p: Dictionary) -> void:
	var now = _now()
	for id in p["quests"]["active"].keys():
		if not p["quests"]["active"].has(id):
			continue # in diesem Takt schon mit einer anderen beendet
		var t = task(id)
		var e: Dictionary = p["quests"]["active"][id]
		if int(t.get("m", 0)) == 5 and t.get("s", []).is_empty() and now >= int(e["p"].get("until", 0)):
			if _bag_room(p, id) and (not t.has("fin_buffs") or buffs_ok(p, t["fin_buffs"], t.get("fin_buffs_all", false))):
				finish(peer, p, id, true) # z.B. 15791 "Werwolfanbetung": erst mit den Effekten 2885 und 2886
		elif int(t.get("time", 0)) > 0 and now - int(e["t"]) > int(t["time"]):
			finish(peer, p, id, false)


# ====================================================
# DATENBANK
# ====================================================
func _save_row(p: Dictionary, id: int, state: int, prog: Dictionary, accepted, finished, times: int) -> void:
	if not db.run("INSERT OR REPLACE INTO quests (character_id, task_id, state, progress, accepted, finished, times) VALUES (?, ?, ?, ?, ?, ?, ?)",
			[p["id"], id, state, JSON.stringify(prog), accepted, finished, times]):
		log_line.call("FEHLER Datenbank: " + db.last_error)

# Zeitraum für max_fin: Art 1 = Tag, 2 = Woche (ab Montag), sonst 0 (insgesamt); Unix-Zeit in s (UTC)
static func _period(kind: int, now: int) -> int:
	var day = now / 86400
	match kind:
		1:
			return day
		2:
			return (day + 3) / 7 # 1.1.1970 war ein Donnerstag
	return 0

static func _now() -> int:
	return int(Time.get_unix_time_from_system())
