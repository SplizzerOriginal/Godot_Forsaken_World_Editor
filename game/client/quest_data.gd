extends RefCounted

# ====================================================
# Quests im Client (Fahrplan Schritt 10): Texte und Gespräche aus der tasks.data der Sprache
# (angelica_tasks.gd im Index-Modus: nur die gebrauchten Quests liegen im Speicher), Quest-Dienste der
# NPCs aus der elements.data (NPC_TASK_OUT_SERVICE / NPC_TASK_IN_SERVICE), Symbole aus
# script\NPCTaskInfo.lua (angelica_lua.gd) mit dem Bildersatz surfaces\ingame\QuestList.tga (.txt).
# Der Server entscheidet; der Client zeigt an, was nach seinem Zustand (quests-Meldung) möglich ist:
#   npc_entries(NPC)  Einträge des NPC-Fensters wie CDlgNPC::PopupTaskDialog: abschließbar (talk_award),
#                     annehmbar (talk_deliver), sichtbar aber nicht annehmbar (can_show: grey, talk_unqualified), läuft
#                     (talk_execute)
#   head_icon(NPC)    Symbol über dem Kopf wie CECNPCServer::UpdateCurQuestIcon (abschließbar vor
#                     annehmbar vor läuft vor nicht annehmbar = graues "!"), Art des Bildes nach m_nTopic der Quest
#   trace()           Quest-Verfolgung: sichtbare Quests der obersten Ebene mit dem laufenden Teil; Ziele mit Links
#                     (goals: Monster / Gegenstand, Z3; Methode 11: das NPC, das die gesuchte Quest vergibt, B17),
#                     erreichtes Ziel mit Abgabe-NPC (back)
#   format_text()     Platzhalter wie CDlgTask::FormatTaskText (&name&, &level&, &race&, &item:ID& ...);
#                     Koordinaten-Links &pos:(x,y,z,Welt)Name& werden zu POS_OPEN x,y,z,Welt POS_MID Name
#                     POS_CLOSE (hud.gd macht daraus grüne Links mit Autoroute)
#   item_count        Callable(ID) -> Anzahl in der Tasche (Ziele "Gegenstände sammeln": Name 0/1)
#   my_buffs          Callable() -> eigene Effekte [[ID, Stapel, ...]] (Effekt-Bedingungen m_PremBuff)
#   npc_pos           Orte der Quest-NPCs aus data\task_npc.data (angelica_tasks.gd npc_positions)
# Annehmbar heißt hier wie auf dem Server (quests.gd can_deliver): Stufe (levels: Mindeststufe aus den Server-Daten),
# Rasse, Klasse, Geschlecht, Vorquests (13008 gilt als erfüllt), Vorbedingungs-Gegenstände (m_PremItems), Ausschluss, Mit-Quests (m_ulPremise_Cotask, m_ulCoTaskCond 1 = alle), Effekte (m_PremBuff),
# nicht laufend, erledigt nur wiederholbar, keine noch nicht geprüfte Vorbedingung (angelica_tasks.gd UNSUPPORTED), dazu
# need_buffs aus den Server-Daten (B20). Sichtbar (can_show) wie ATaskTempl::CanShowTask: die Bedingungen mit m_bShowBy*-Schalter
# nur, wenn er gesetzt ist - so zeigt z.B. das Grab des Werwolf-Gottes "Lauscht dem Ruf" grau, bis der Blut-Effekt da ist.
# Methode 11 "Quest mehrmals erfüllen": Ziel "<Quest> n/Anzahl" nach dem Fortschritt n des Servers.
# Belohnung im Quest-Fenster (log_entries): EXP (Z5), Goldmünzen und Seelenmünzen (Z4) wie der Server (stats.gd task_money:
# m_bGoldRevise -> * Faktor der Figurenstufe aus PLAYER_TALENT_CONFIG der elements.data), Text über money_text.
# ====================================================

const TASKS = "res://addons/PWE-Manager/Data/angelica_tasks.gd"
const FILES = "res://addons/PWE-Manager/Data/angelica_files.gd"
const LUA = "res://addons/PWE-Manager/Data/angelica_lua.gd"
# Stufen der Quests: die Mindeststufe fehlt in der tasks.data des Clients (immer 0), der Server liest sie aus seiner
# tasks.data (tools/server_data/quest_templates.gd) - der Client nimmt dieselben Werte aus dem Plugin
const SERVER_QUESTS = "res://addons/PWE-Manager/Server/quest_templates.json"
const DONE_BY_DEFAULT = {13008: true} # Fenster-Quest "Prüfungs-Essenz erhalten" gilt als erfüllt (wie quests.gd)
const ICON_SET = "ingame\\QuestList.tga"
const POS_OPEN = "\uE000"
const POS_MID = "\uE001"
const POS_CLOSE = "\uE002"
# CECNPCTaskInfo: Art des Eintrags
const QBT_CAN_NOT_GET = 1
const QBT_CAN_NOT_FINISH = 2
const QBT_CAN_GET = 3
const QBT_CAN_FINISH = 4
const TOPIC_ELSE = 4
# Gesprächsoptionen mit Sonderbedeutung (SERVICE_TYPE in ExpTypes.h)
const NPC_GIVE_TASK = 0x80000006
const NPC_COMPLETE_TASK = 0x80000007
const TALK_RETURN = 0x80000011
const TALK_EXIT = 0x80000012
const TALK_GIVEUP_TASK = 0x80000015
const METHOD_TALK = 3
const METHOD_WAIT = 5
const METHOD_FINISH_TASK = 11

var tasks = null # angelica_tasks.gd (Index)
var elements = null # angelica_elements.gd (npc_data.gd)
var active = {} # ID -> Fortschritt (vom Server)
var done = {} # ID -> true (erfüllt, oberste Ebene)
var player = {} # name, level, race, class, gender
var icons = {} # [Art, Thema] -> Name des Bildes (NPCTaskInfo.lua)
var icon_rects = {} # Name des Bildes -> Rect2 im Bildersatz
var icon_texture: Texture2D
var strings = {} # Texttabelle der Oberfläche (2201 ... Geschlecht, 120 + Rasse)
var warnings: Array = []
var npc_pos = {} # NPC-Vorlage -> [Welt, Vector3] (task_npc.data, Ziele der Autoroute)
var item_count: Callable = func(_id): return 0
var my_buffs: Callable = func(): return []
var money_text: Callable = func(copper): return str(copper) # Kupfer -> "x Gold y Silber z Kupfer" (hud.gd)
var _money_factors = null # [task_money_factor, task_bind_money_factor, task_factor] (PLAYER_TALENT_CONFIG)
var _services = {} # NPC-Vorlage -> [Ausgabe, Annahme]
var levels = {} # Quest (oberste Ebene) -> [Mindest-, Höchststufe] aus SERVER_QUESTS
var limited = {} # Quest (oberste Ebene) -> true: mit Höchstzahl (max_fin), erledigt dann nicht mehr grau anzeigen
var need_buffs = {} # Quest -> [[Effekt, Mindest-Stufe, muss haben]] zur Vergabe (SERVER_QUESTS, Wunsch des Spielers B20)


# Im Thread: tasks.data der Sprache indizieren -> "" oder Fehlertext
func open(data_root: String, language: String) -> String:
	var files = load(FILES).new(data_root)
	var script = load(TASKS)
	var path: String = script.locate(files, language)
	if path == "":
		return "tasks.data fehlt"
	tasks = script.new()
	var err = tasks.open(path, files)
	if err != "":
		return err
	tasks.index_all()
	_read_server()
	npc_pos = script.npc_positions(files, language)
	_read_icons(files, language)
	return ""

func _read_server() -> void:
	levels = {}
	limited = {}
	need_buffs = {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SERVER_QUESTS)) if FileAccess.file_exists(SERVER_QUESTS) else null
	if not d is Dictionary:
		warnings.append("Quest-Stufen fehlen (%s), Mindeststufen unbekannt" % SERVER_QUESTS)
		return
	var all: Dictionary = d.get("tasks", {})
	for k in all:
		var t: Dictionary = all[k]
		if t.has("p"):
			continue
		if t.has("lv"):
			levels[int(k)] = [int(t["lv"][0]), int(t["lv"][1])]
		if t.has("max_fin"):
			limited[int(k)] = true
		if t.has("need_buffs"):
			need_buffs[int(k)] = t["need_buffs"]

# Stufen einer Quest [min, max] (0 = ohne Grenze)
func level_range(t: Dictionary) -> Array:
	return levels.get(int(t["id"]), [int(t["level_min"]), int(t["level_max"])])

# Bilder und Symbole (NPCTaskInfo.lua, QuestList.txt); aui: aui_manager.gd für Texturen
func set_ui(aui) -> void:
	strings = aui.strings
	icon_texture = aui.texture(ICON_SET)

func _read_icons(files, language: String) -> void:
	var dir = ""
	for base in [language + "/script", "resources/" + language + "/script"]:
		if files.resolve(base) != "":
			dir = files.resolve(base)
			break
	var lua = load(LUA).new(files)
	var p = files.resolve("npctaskinfo.lua", dir) if dir != "" else ""
	if p != "" and lua.run_file(p) == "":
		var info = lua.value("NPCTaskInfo")
		if info is Dictionary:
			for qbt in info:
				for topic in info[qbt]:
					icons[[int(qbt), int(topic)]] = str(info[qbt][topic].get("icon", ""))
	else:
		warnings.append("NPCTaskInfo.lua nicht lesbar")
	lua.close()
	# QuestList.txt: Breite, Höhe, Zeilen, Spalten, dann die Namen zeilenweise (CECImageSet::Init)
	var txt = ""
	for base in [language + "/surfaces", "resources/" + language + "/surfaces", "surfaces"]:
		var tp = files.resolve(base + "/ingame/questlist.txt")
		if tp != "":
			txt = files.get_bytes(tp).get_string_from_ascii()
			break
	var lines = txt.replace("\r", "").split("\n")
	if lines.size() < 4:
		warnings.append("QuestList.txt nicht lesbar")
		return
	var w = int(lines[0])
	var h = int(lines[1])
	var rows = int(lines[2])
	var cols = int(lines[3])
	for i in rows * cols:
		if 4 + i < lines.size() and lines[4 + i].strip_edges() != "":
			icon_rects[lines[4 + i].strip_edges().to_lower()] = Rect2((i % cols) * w, (i / cols) * h, w, h)

func task(id: int) -> Dictionary:
	return tasks.get_task(id) if tasks != null else {}

func set_state(d: Dictionary) -> void:
	active = {}
	for e in d.get("active", []):
		active[int(e[0])] = e[1] if e.size() > 1 else {}
	done = {}
	for id in d.get("done", []):
		done[int(id)] = true


# ====================================================
# BEDINGUNGEN
# ====================================================
func is_active(id: int) -> bool:
	return active.has(id)

func can_deliver(id: int) -> bool:
	var t = task(id)
	return _base_ok(id) and _level_ok(t) and _occ_ok(t) and _gender_ok(t) and _pre_ok(t) and _items_ok(t) and _cotask_ok(t) \
		and buffs_ok(need_buffs.get(id, []), true)

# Sichtbar wie ATaskTempl::CanShowTask, soweit der Client es prüfen kann: oberste Ebene, nicht laufend, erledigt nur
# wiederholbar (mit Höchstzahl max_fin nicht mehr: die Zählung kennt nur der Server), Rasse, Ausschluss, Effekte
# (m_PremBuff); Stufe, Klasse, Geschlecht, Vorquests, Gegenstände und Mit-Quests nur mit ihrem m_bShowBy*-Schalter.
# Sichtbar, aber nicht annehmbar: graues "!" (QBT_CAN_NOT_GET) und grauer Eintrag im NPC-Fenster (talk_unqualified)
func can_show(id: int) -> bool:
	var t = task(id)
	if not _base_ok(id) or (done.has(id) and limited.has(id)):
		return false
	return (not tasks.field(t, "m_bShowByLev") or _level_ok(t)) and (not tasks.field(t, "m_bShowByOccup") or _occ_ok(t)) \
		and (not tasks.field(t, "m_bShowByGender") or _gender_ok(t)) and (not tasks.field(t, "m_bShowByPreTask") or _pre_ok(t)) \
		and (not tasks.field(t, "m_bShowByItems") or _items_ok(t)) and (not tasks.field(t, "m_bShowByCoTask") or _cotask_ok(t))

# Bedingungen, die Annehmen und Anzeigen gemeinsam haben (CanShowTask prüft sie immer)
func _base_ok(id: int) -> bool:
	var t = task(id)
	if t.is_empty() or t["parent"] != 0 or active.has(id) or not tasks.unsupported(t).is_empty():
		return false
	if done.has(id) and not t["can_redo"]:
		return false
	if not t["races"].is_empty() and not int(player.get("race", 0)) in t["races"]:
		return false
	for m in tasks.field(t, "m_ulMutexTasks"):
		if int(m) != 0 and (active.has(int(m)) or done.has(int(m))):
			return false
	return buffs_ok(tasks.buff_list(tasks.field(t, "m_PremBuff"), int(tasks.field(t, "m_ulPremBuffCnt"))), bool(tasks.field(t, "m_bPremBuffCond")))

func _level_ok(t: Dictionary) -> bool:
	var lv = int(player.get("level", 1))
	var range = level_range(t)
	return not ((range[0] != 0 and lv < range[0]) or (range[1] != 0 and lv > range[1]))

func _occ_ok(t: Dictionary) -> bool:
	return t["occupations"].is_empty() or int(player.get("class", 0)) in t["occupations"]

func _gender_ok(t: Dictionary) -> bool:
	var g = int(t["gender"])
	return not ((g == 1 and int(player.get("gender", 0)) != 0) or (g == 2 and int(player.get("gender", 0)) != 1))

func _pre_ok(t: Dictionary) -> bool:
	for pre in t["premise_tasks"]:
		if not done.has(int(pre)) and not DONE_BY_DEFAULT.has(int(pre)):
			return false
	return true

func _items_ok(t: Dictionary) -> bool:
	for it in t.get("premise_items", []): # Gegenstände in der Tasche (z.B. Prüfungs-Essenzen für den Tausch)
		if int(item_count.call(int(it["id"]))) < int(it["num"]):
			return false
	return true

func _cotask_ok(t: Dictionary) -> bool:
	var co = int(tasks.field(t, "m_ulPremise_Cotask_Cnt"))
	if co <= 0:
		return true
	var ids = (tasks.field(t, "m_ulPremise_Cotask") as Array).slice(0, co).filter(func(x): return int(x) != 0)
	var running = ids.filter(func(x): return active.has(int(x))).size()
	return not ((running < ids.size()) if int(tasks.field(t, "m_ulCoTaskCond")) != 0 else running == 0)

# Zustand einer Fenster-Quest für Shylias Markt (wie GameApi.GetTaskStatus): 2 annehmbar, 4 erledigt (nicht wiederholbar),
# 1 sonst
func award_state(id: int) -> int:
	if id == 0 or tasks == null:
		return 1
	if can_deliver(id):
		return 2
	var t = task(id)
	return 4 if done.has(id) and not t.is_empty() and not t["can_redo"] else 1

# Effekt-Bedingung [[ID, Mindest-Stufe, muss haben]] gegen die eigenen Effekte (wie quests.gd buffs_ok)
func buffs_ok(list: Array, all: bool) -> bool:
	if list.is_empty():
		return true
	var mine: Array = my_buffs.call()
	var hits = 0
	for e in list:
		var has = mine.any(func(b): return int(b[0]) == int(e[0]) and (int(e[1]) == 0 or int(b[1]) >= int(e[1])))
		if has == bool(e[2]):
			hits += 1
	return hits == list.size() if all else hits > 0

# Kann der laufende Teil hier abgeschlossen werden? (NPC ansprechen; Warten vorbei)
func can_finish(id: int) -> bool:
	var t = task(id)
	if t.is_empty() or not active.has(id) or not t["subs"].is_empty():
		return false
	match int(t["method"]):
		METHOD_TALK:
			return true
		METHOD_WAIT:
			return Time.get_unix_time_from_system() >= float(active[id].get("until", 0))
		1:
			return _monsters_done(t)
		2:
			return t["items"].all(func(i): return int(item_count.call(int(i["id"]))) >= maxi(1, int(i["num"])))
		METHOD_FINISH_TASK:
			return _finished_times(t) >= maxi(1, int(tasks.field(t, "m_ulFinishTaskTimes"))) \
				and buffs_ok(tasks.buff_list(tasks.field(t, "m_FinBuff"), int(tasks.field(t, "m_ulFinBuffCnt"))), bool(tasks.field(t, "m_bFinBuffCond")))
	return false

# Methode 11: wie oft die gesuchte Quest schon erfüllt wurde, seit diese läuft (Fortschritt n des Servers)
func _finished_times(t: Dictionary) -> int:
	var prog = active.get(int(t["id"]), {})
	return int(prog.get("n", 0)) if prog is Dictionary else 0

# Monster-Ziel erreicht? (Beute in der Tasche bzw. Kills laut Fortschritt)
func _monsters_done(t: Dictionary) -> bool:
	if t["monsters"].is_empty():
		return false
	var prog = active.get(int(t["id"]), {})
	var k = prog.get("k", {}) if prog is Dictionary else {}
	for m in t["monsters"]:
		if int(m.get("drop_item", 0)) != 0:
			if int(item_count.call(int(m["drop_item"]))) < int(m["drop_count"]):
				return false
		elif int(k.get(str(int(m["id"])), 0)) < int(m["num"]):
			return false
	return true

func hidden(t: Dictionary) -> bool:
	return tasks.field(t, "m_bHidden") == true

func topic(t: Dictionary) -> int:
	var root = top_of(t)
	return clampi(int(tasks.field(root, "m_nTopic")), 0, TOPIC_ELSE)

func top_of(t: Dictionary) -> Dictionary:
	var r = t
	while not r.is_empty() and r["parent"] != 0:
		r = task(r["parent"])
	return r


# ====================================================
# NPC
# ====================================================
# Quest-Dienste einer NPC-Vorlage: [Ausgabe, Annahme]
func services(tid: int) -> Array:
	if _services.has(tid):
		return _services[tid]
	var out = []
	var inn = []
	var r: Dictionary = elements.get_record(tid) if elements != null else {}
	for k in [["id_task_out_service", out], ["id_task_in_service", inn]]:
		var sid = int(r.get(k[0], 0))
		if sid != 0:
			for x in elements.get_record(sid).get("id_tasks", []):
				if int(x) != 0:
					k[1].append(int(x))
	_services[tid] = [out, inn]
	return _services[tid]

# Einträge des NPC-Fensters: [{id, kind, talk, title}]
func npc_entries(tid: int) -> Array:
	var sv = services(tid)
	var finish = []
	var get = []
	var running = []
	var seen = {}
	for id in sv[1]:
		if can_finish(id) and _award_npc_ok(id, tid):
			finish.append(_entry(id, QBT_CAN_FINISH, "talk_award"))
			seen[id] = true
	for id in sv[0]:
		if seen.has(id):
			continue
		var t = task(id)
		if t.is_empty() or hidden(t):
			continue
		if active.has(id):
			if not can_finish(id):
				running.append(_entry(id, QBT_CAN_NOT_FINISH, "talk_execute"))
		elif can_deliver(id):
			get.append(_entry(id, QBT_CAN_GET, "talk_deliver"))
		elif can_show(id): # CDlgNPC: sichtbar, aber nicht annehmbar -> grau mit dem Text "nicht erfüllt" (GetUnqualifiedTalk)
			var e = _entry(id, QBT_CAN_GET, "talk_unqualified")
			e["grey"] = true
			get.append(e)
	var out = []
	for e in finish + get + running:
		var tk: Dictionary = e["talk"]
		var wins: Array = tk.get("windows", [])
		if wins.size() > 1 or (wins.size() == 1 and str(wins[0]["text"]) != ""):
			out.append(e)
	return out

func _award_npc_ok(id: int, tid: int) -> bool:
	var t = task(id)
	return int(t.get("award_npc", 0)) == 0 or int(t["award_npc"]) == tid or id in services(tid)[1]

func _entry(id: int, kind: int, talk_key: String) -> Dictionary:
	var t = task(id)
	var root = top_of(t)
	var lv = int(tasks.field(root, "m_ulSuitableLevel"))
	var title = ("[%d]" % lv if lv != 0 else "") + str(root["name"])
	if t["id"] != root["id"]:
		title += " - " + str(t["name"])
	return {"id": id, "kind": kind, "talk": t.get(talk_key, {}), "title": title, "topic": topic(t)}

# Symbol über dem NPC (Name im Bildersatz) oder ""
func head_icon(tid: int) -> String:
	var sv = services(tid)
	var kind = 0
	var top_topic = TOPIC_ELSE
	for id in sv[1]:
		if active.has(id) and can_finish(id):
			kind = QBT_CAN_FINISH
			top_topic = mini(top_topic, topic(task(id)))
	if kind == 0:
		for id in sv[0]:
			var t = task(id)
			if not t.is_empty() and not hidden(t) and not active.has(id) and can_deliver(id):
				kind = QBT_CAN_GET
				top_topic = mini(top_topic, topic(t))
	if kind == 0:
		for id in sv[1] + sv[0]:
			if active.has(id) and not can_finish(id) and task(id).get("subs", [1]).is_empty():
				kind = QBT_CAN_NOT_FINISH
				top_topic = mini(top_topic, topic(task(id)))
	if kind == 0:
		for id in sv[0]: # graues "!": sichtbar, aber (noch) nicht annehmbar
			var t = task(id)
			if not t.is_empty() and not hidden(t) and can_show(id):
				kind = QBT_CAN_NOT_GET
				top_topic = mini(top_topic, topic(t))
	if kind == 0:
		return ""
	return icons.get([kind, top_topic], icons.get([kind, 0], ""))

func icon_atlas(icon_name: String) -> AtlasTexture:
	var r = icon_rects.get(icon_name.to_lower())
	if r == null or icon_texture == null:
		return null
	var at = AtlasTexture.new()
	at.atlas = icon_texture
	at.region = r
	return at


# ====================================================
# VERFOLGUNG UND TEXTE
# ====================================================
# Sichtbare Quests der obersten Ebene: [{id, name, part (laufender Teil), goal}]
func trace(npc_name: Callable) -> Array:
	var out = []
	for id in active:
		var t = task(id)
		if t.is_empty() or t["parent"] != 0 or hidden(t):
			continue
		var leaf = _running_leaf(t)
		var talk = int(leaf.get("method", 0)) == METHOD_TALK
		var done = not talk and can_finish(leaf.get("id", 0))
		out.append({"id": id, "name": t["name"], "part": leaf.get("name", "") if leaf != t else "",
			"goal": goal_text(leaf, npc_name), "goals": goal_parts(leaf), "talk": talk,
			"npc": int(leaf.get("award_npc", 0)) if talk else 0,
			"where": first_pos(str(leaf.get("description", ""))) if not talk else [],
			"done": done,
			# Ziel erreicht und beim NPC abzuschließen: "Zurück zu <NPC>" (Link)
			"back": int(leaf.get("award_npc", 0)) if done and int(leaf.get("finish_type", 0)) != 0 else 0,
			"back_name": str(npc_name.call(int(leaf.get("award_npc", 0)))) if done and int(leaf.get("award_npc", 0)) != 0 else ""})
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return out

# Einträge des Quest-Fensters: trace() dazu Beschreibung, Belohnung (Text) und ob aufgebbar
func log_entries(npc_name: Callable, texts: Dictionary) -> Array:
	var out = trace(npc_name)
	for e in out:
		var t = task(e["id"])
		e["description"] = format_text(str(t.get("description", "")))
		var a: Dictionary = t.get("award", {})
		var parts = []
		var xp = award_exp(a)
		if xp != 0:
			parts.append("%d EXP" % xp)
		var cash = award_money(a)
		if cash[0] > 0:
			parts.append(texts.get("money", "%s") % money_text.call(cash[0]))
		if cash[1] > 0:
			parts.append(texts.get("bind", "%s") % money_text.call(cash[1]))
		for g in a.get("items", []):
			for it in g.get("items", []):
				parts.append("%s x%d" % [_name(int(it["id"])), maxi(1, int(it["num"]))])
		e["award"] = ", ".join(parts)
		e["giveup"] = t.get("can_give_up", false)
	return out

# Geld einer Belohnung (AWARD_DATA aus angelica_tasks.gd) für die eigene Stufe -> [Goldmünzen, Seelenmünzen] in Kupfer
func award_money(a: Dictionary) -> Array:
	var out = [int(a.get("gold", 0)), int(a.get("bind_money", 0))]
	if not a.get("gold_revise", false):
		return out
	var i = mini(int(player.get("level", 1)), maxi(1, int(a.get("gold_revise_lev", 1)))) - 1
	for k in 2:
		out[k] = int(out[k] * _factor(k, i) + 1e-6)
	return out

# EXP einer Belohnung für die eigene Stufe (wie stats.gd task_exp: m_bExpRevise bis Stufe exp_revise_lev, m_bExpFix genau sie)
func award_exp(a: Dictionary) -> int:
	var xp = int(a.get("exp", 0))
	if xp == 0 or not (a.get("exp_revise", false) or a.get("exp_fix", false)):
		return xp
	var lev = maxi(1, int(a.get("exp_revise_lev", 1)))
	var i = (lev if a.get("exp_fix", false) else mini(int(player.get("level", 1)), lev)) - 1
	return int(xp * _factor(2, i) + 1e-6)

# Faktor je Stufe aus PLAYER_TALENT_CONFIG: 0 Gold, 1 Seelenmünzen, 2 EXP (task_factor); i = Stufe - 1
func _factor(k: int, i: int) -> float:
	if _money_factors == null:
		_money_factors = [[], [], []]
		var li = elements.list_of("PLAYER_TALENT_CONFIG") if elements != null else -1
		if li >= 0 and int(elements.lists[li]["count"]) > 0:
			var r: Dictionary = elements.record(li, 0)
			_money_factors = [r.get("task_money_factor", []), r.get("task_bind_money_factor", []), r.get("task_factor", [])]
	var f: Array = _money_factors[k]
	return float(f[i]) if i >= 0 and i < f.size() else 1.0

func _running_leaf(t: Dictionary) -> Dictionary:
	for s in t["subs"]:
		if active.has(s["id"]):
			return _running_leaf(s)
	return t

# Ziel eines Teils als Text (NPC ansprechen: Name des NPCs)
func goal_text(t: Dictionary, npc_name: Callable) -> String:
	if t.is_empty():
		return ""
	match int(t["method"]):
		METHOD_TALK:
			return npc_name.call(int(t["award_npc"])) if int(t["award_npc"]) != 0 else ""
		1:
			return ", ".join(t["monsters"].map(_monster_goal.bind(int(t.get("id", 0)))))
		2:
			return ", ".join(t["items"].map(_item_goal))
		METHOD_FINISH_TASK:
			var want = int(tasks.field(t, "m_ulFinishTaskID"))
			var need = maxi(1, int(tasks.field(t, "m_ulFinishTaskTimes")))
			var wt = task(want)
			return "%s %d/%d" % [wt.get("name", str(want)), mini(_finished_times(t), need), need] if want != 0 else ""
	return ""

# Ziel-Teile mit Link für die Autoroute (Z3): Monster "mon:<Vorlage>:<Quest>" (auch Beute-Ziele: das Monster, das sie
# fallen lässt), Gegenstände "item:<ID>:<Quest>" (Sammelpunkt; den Ort weiß der Server, Anfrage quest_where) -> [{text, link}]
func goal_parts(t: Dictionary) -> Array:
	if t.is_empty():
		return []
	var id = int(t.get("id", 0))
	match int(t["method"]):
		1:
			return t["monsters"].map(func(m): return {"text": _monster_goal(m, id), "link": "mon:%d:%d" % [int(m["id"]), id]})
		2:
			return t["items"].map(func(i): return {"text": _item_goal(i), "link": "item:%d:%d" % [int(i["id"]), id]})
		METHOD_FINISH_TASK:
			# "Quest erfüllen" (z.B. 15358 "Segen des Wolfs" wartet auf 15396 "Lauscht dem Ruf"): solange die gesuchte Quest
			# nicht läuft, führt der Link zum NPC, das sie vergibt (Grab des Werwolf-Gottes, m_bCanSeekOut); läuft sie, steht
			# sie mit ihren eigenen Zielen in der Verfolgung
			var want = int(tasks.field(t, "m_ulFinishTaskID"))
			var npc = int(task(want).get("delv_npc", 0)) if want != 0 else 0
			if npc != 0 and not active.has(want) and not can_finish(id):
				return [{"text": goal_text(t, func(_x): return ""), "link": "npc:%d" % npc}]
	return []

# Monster-Ziel: Beute in der Tasche ("Beute 3/10") bzw. Kills laut Fortschritt ("Wildschwein 2/5")
func _monster_goal(m: Dictionary, id: int) -> String:
	if int(m.get("drop_item", 0)) != 0:
		var need = int(m["drop_count"])
		return "%s %d/%d" % [_name(int(m["drop_item"])), mini(int(item_count.call(int(m["drop_item"]))), need), need]
	var prog = active.get(id, {})
	var k = prog.get("k", {}) if prog is Dictionary else {}
	var num = int(m["num"])
	return "%s %d/%d" % [_name(int(m["id"])), mini(int(k.get(str(int(m["id"])), 0)), num), num]

# Gesuchter Gegenstand mit Anzahl in der Tasche: "Name 0/1"
func _item_goal(i: Dictionary) -> String:
	var need = int(i["num"])
	return "%s %d/%d" % [_name(int(i["id"])), mini(int(item_count.call(int(i["id"]))), need), need]

func _name(id: int) -> String:
	return elements.name_of(id) if elements != null else str(id)

# Platzhalter wie CDlgTask::FormatTaskText
func format_text(text: String) -> String:
	if not text.contains("&"):
		return text
	var parts = (text + "&").split("&")
	var out = ""
	for i in parts.size():
		if i % 2 == 0:
			out += parts[i]
			continue
		var key: String = parts[i]
		if i == parts.size() - 1:
			break
		match key:
			"":
				out += "^&"
			"name":
				out += str(player.get("name", ""))
			"level":
				out += str(player.get("level", 1))
			"sex1", "sex2", "sex3":
				out += str(strings.get({"sex1": 2201, "sex2": 2203, "sex3": 2205}[key] + int(player.get("gender", 0)), ""))
			"race":
				out += str(strings.get(120 + int(player.get("race", 1)), ""))
			_:
				if key.begins_with("item:"):
					out += _name(key.substr(5).to_int())
				elif key.begins_with("pos:"):
					var p = _parse_pos(key)
					out += POS_OPEN + "%s,%s,%s,%d" % [p[0], p[1], p[2], p[3]] + POS_MID + p[4] + POS_CLOSE if not p.is_empty() else key
	return out

# &pos:(x,y,z,Welt)Name& -> [x, y, z, Welt, Name], [] wenn kein Link
static func _parse_pos(key: String) -> Array:
	var open = key.find("(")
	var close = key.find(")")
	if open < 0 or close < open:
		return []
	var nums = key.substr(open + 1, close - open - 1).split(",")
	if nums.size() < 3:
		return []
	return [nums[0].to_float(), nums[1].to_float(), nums[2].to_float(), nums[3].to_int() if nums.size() > 3 else 0,
		key.substr(close + 1)]

# Erster Koordinaten-Link eines Textes -> [x, y, z, Welt, Name] oder []
static func first_pos(text: String) -> Array:
	var at = text.find("&pos:")
	if at < 0:
		return []
	var end = text.find("&", at + 1)
	return _parse_pos(text.substr(at + 1, end - at - 1)) if end > at else []
