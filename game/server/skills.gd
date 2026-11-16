extends RefCounted

# ====================================================
# Fertigkeiten der Figuren (wie SkillWrapper): bekannte Fertigkeiten mit Stufe (Tabelle skills) und
# Schnellleisten (Tabelle shortcuts).
#   Startfertigkeiten: die der Startvorlage (Plugin Server/start_roles.json skills_raw = clsconfig
#   GRoleStatus.skills im Format von SkillWrapper::LoadDatabase: Version (1 Byte), bei Version 1 der
#   Talentzweig (1 Byte), Anzahl (4 Byte), je ID (4 Byte) und Stufe (1 Byte)); eine Figur ohne
#   gespeicherte Fertigkeit bekommt sie beim Betreten der Welt, als "neu". Dazu kennt jede Figur
#   DEFAULT_SKILLS (120 Stadtportal, wie LoadDatabase mit MASK_DEFAULT_SKILL; nicht gespeichert).
#   Neue Fertigkeiten (new) zeigt der Client im Fenster "Neue Fertigkeiten" (Win_NewSKill), bis er sie
#   mit skill_seen weglegt (CECHostPlayer::RemoveNewSkill); learn() gibt weitere (Meldung skill_new).
#   Schnellleisten: Leiste 0 unten (Win_QuickBar0), 1 rechts (Win_QuickBar1), je SLOTS Plätze; nur
#   bekannte Fertigkeiten.
#   load_player(p, Vorlage), state_of(p) -> {skills: [[ID, Stufe]], new: [IDs], shortcuts: [[Leiste, Platz, ID]]}
#   seen(p, ids), set_shortcut(p, Leiste, Platz, ID) -> [Code, Daten]
#   Einsetzen und Werte (info, Meldung skill_info): skill_cast.gd
#   Lernen (F8, SkillStub::LearnCondition / Learn): Klassen-Fertigkeiten (from 1 = ORIGIN_LEARN, Klasse und Rasse der
#   Figur, require_level je Lernstufe, höchstens max_learn, Voraussetzung pre_skill auf pre_level) kommen bis
#   AUTO_LEARN_LEVEL von selbst (beim Betreten der Welt und beim Stufenaufstieg: auto_learn); darüber lernt die Figur
#   mit learn_request gegen Gold: cost_money * learn_money_factor[benötigte Stufe - 1] (class_templates.json).
#   catalog(p) -> [[ID, nächste Stufe (0 = ausgelernt), benötigte Stufe, Kosten Kupfer, max_learn, type, use, Stufe der
#   ersten Lernstufe]] für das K-Fenster (auch noch nicht gelernte: Reihenfolge, passiv / Schalter, ab welcher Stufe);
#   Rassen- und andere Fertigkeiten kommen aus Quests (quests.gd award skill / del_skill: learn / forget).
#   race_skills(p) -> [[ID, type, use]]: die Rassen-Fertigkeiten der Figur (RACE_SKILLS) für den K-Reiter "Rasse", auch
#   noch nicht erhaltene.
# ====================================================

const Proto = preload("../common/protocol.gd")
const DEFAULT_SKILLS = {120: 1}
const AUTO_LEARN_LEVEL = 20 # bis zu dieser Figurenstufe lernt die Figur ihre Klassen-Fertigkeiten von selbst
# Rassen-Fertigkeiten je Rasse (1 Mensch, 2 Elf, 3 Zwerg, 4 Steinmensch, 5 Kindred, 6 Werwolf), Segen zuerst.
# Quelle: Quest-Belohnungen (quest_templates.json award skill) - Segen aus den versteckten Automatik-Quests 8702 - 8706 /
# 15802, die übrigen aus den Startketten (5680 Gebet, 7670, 5688, 7605 / 7612, 6967, 15358 Mondnebel, 15800 / 15801
# Verwandlung). Werwolf-Verwandlung je Geschlecht: [männlich, weiblich].
const RACE_SKILLS = {1: [2497, 1958], 2: [2498, 1959], 3: [2500, 1961], 4: [2501, 1962, 2510], 5: [2499, 1960],
	6: [4214, 4582, [4215, 4216]]}
const BARS = 2
const SLOTS = 10

var db
var net
var log_line: Callable
var info_of: Callable # (p, ID) -> Werte der Fertigkeit (skill_cast.gd info), Meldung skill_info beim Lernen
var on_learn: Callable # (p, ID) nach dem Lernen / einer neuen Stufe (skill_cast.gd apply_passive: Dauer-Effekte, F7)
var templates = {} # ID -> Fertigkeit (skill_cast.gd templates, setzt der Server)
var learn_factor: Array = [] # class_templates.json learn_money_factor (je Figurenstufe)
var stats_push: Callable # (peer, p): Geld nach dem Lernen


func _init(p_db, p_net, p_log: Callable) -> void:
	db = p_db
	net = p_net
	log_line = p_log

# Fertigkeiten und Leisten aus der DB; ohne gespeicherte die der Startvorlage (neu)
func load_player(p: Dictionary, template: Dictionary) -> void:
	var known = {}
	var fresh = {}
	var rows = db.query("SELECT skill_id, level, new FROM skills WHERE character_id = ?", [p["id"]])
	for r in (rows if rows != null else []):
		known[int(r["skill_id"])] = int(r["level"])
		if int(r["new"]) != 0:
			fresh[int(r["skill_id"])] = true
	if known.is_empty() and rows != null:
		for e in start_skills(str(template.get("skills_raw", ""))):
			if _save(p, e[0], e[1], true):
				known[e[0]] = e[1]
				fresh[e[0]] = true
		if not known.is_empty():
			log_line.call("Fertigkeiten: %s bekommt die Startfertigkeiten %s" % [p["name"], str(known.keys())])
	for id in DEFAULT_SKILLS:
		if not known.has(id):
			known[id] = DEFAULT_SKILLS[id]
	var bars = {}
	var srows = db.query("SELECT bar, slot, skill_id FROM shortcuts WHERE character_id = ?", [p["id"]])
	for r in (srows if srows != null else []):
		bars[Vector2i(int(r["bar"]), int(r["slot"]))] = int(r["skill_id"])
	p["skills"] = known
	p["skills_new"] = fresh
	p["shortcuts"] = bars

func state_of(p: Dictionary) -> Dictionary:
	var sk = []
	var known: Dictionary = p.get("skills", {})
	var ids = known.keys()
	ids.sort()
	for id in ids:
		sk.append([id, known[id]])
	var sc = []
	for k in p.get("shortcuts", {}):
		sc.append([k.x, k.y, p["shortcuts"][k]])
	return {"skills": sk, "new": p.get("skills_new", {}).keys(), "shortcuts": sc, "race": race_skills(p)}

# Rassen-Fertigkeiten der Figur (RACE_SKILLS, nach Geschlecht) -> [[ID, type, use]] (Art / passiv für die Liste)
func race_skills(p: Dictionary) -> Array:
	var out = []
	for e in RACE_SKILLS.get(int(p.get("race", 0)), []):
		var id = int(e[clampi(int(p.get("gender", 0)), 0, 1)]) if e is Array else int(e)
		var sk: Dictionary = templates.get(id, {})
		out.append([id, int(sk.get("type", 2)), int(sk.get("use", 2))])
	return out

# Startfertigkeiten aus skills_raw (hex) -> [[ID, Stufe], ...]
static func start_skills(raw: String) -> Array:
	var b = raw.hex_decode()
	var out = []
	if b.size() < 5:
		return out
	var p = 1 + (1 if b[0] == 1 else 0)
	var n = b.decode_u32(p)
	p += 4
	for i in n:
		if p + 5 > b.size():
			break
		out.append([b.decode_u32(p), b[p + 4]])
		p += 5
	return out

# Aus dem Fenster "Neue Fertigkeiten" weggelegt (gezogen oder Fenster geschlossen)
func seen(p: Dictionary, ids) -> Array:
	if not ids is Array:
		return [Proto.Code.BAD_REQUEST, {}]
	var fresh: Dictionary = p.get("skills_new", {})
	for v in ids:
		if (v is int or v is float) and fresh.has(int(v)):
			fresh.erase(int(v))
			db.run("UPDATE skills SET new = 0 WHERE character_id = ? AND skill_id = ?", [p["id"], int(v)])
	return [Proto.Code.OK, {"new": fresh.keys()}]

# Platz einer Schnellleiste belegen (id 0 = leeren)
func set_shortcut(p: Dictionary, bar, slot, id) -> Array:
	if not bar is int or not slot is int or not id is int:
		return [Proto.Code.BAD_REQUEST, {}]
	if bar < 0 or bar >= BARS or slot < 0 or slot >= SLOTS:
		return [Proto.Code.SHORTCUT_INVALID, {}]
	if id != 0 and not p.get("skills", {}).has(id):
		return [Proto.Code.SKILL_UNKNOWN, {}]
	var key = Vector2i(bar, slot)
	if id == 0:
		p["shortcuts"].erase(key)
		db.run("DELETE FROM shortcuts WHERE character_id = ? AND bar = ? AND slot = ?", [p["id"], bar, slot])
	else:
		p["shortcuts"][key] = id
		db.run("INSERT OR REPLACE INTO shortcuts (character_id, bar, slot, skill_id) VALUES (?, ?, ?, ?)", [p["id"], bar, slot, id])
	return [Proto.Code.OK, {"bar": bar, "slot": slot, "id": id}]

# Fertigkeit lernen bzw. Stufe setzen; neu gelernte meldet skill_new (Popup im Client)
func learn(peer: int, p: Dictionary, id: int, level: int = 1) -> void:
	var known: Dictionary = p.get("skills", {})
	var is_new = not known.has(id)
	if _save(p, id, level, is_new):
		known[id] = level
		if is_new:
			p["skills_new"][id] = true
		net.push(peer, "skill_new" if is_new else "skill_level", {"id": id, "level": level})
		if info_of.is_valid():
			net.push(peer, "skill_info", {"id": id, "info": info_of.call(p, id)})
		log_line.call("Fertigkeiten: %s lernt %d (Stufe %d)" % [p["name"], id, level])
		if on_learn.is_valid():
			on_learn.call(p, id)

func _save(p: Dictionary, id: int, level: int, is_new: bool) -> bool:
	if db.run("INSERT OR REPLACE INTO skills (character_id, skill_id, level, new) VALUES (?, ?, ?, ?)", [p["id"], id, level, 1 if is_new else 0]):
		return true
	log_line.call("FEHLER Datenbank: " + db.last_error)
	return false


# ====================================================
# LERNEN (F8)
# ====================================================
# Klassen-Fertigkeiten, die die Figur lernen kann (wie LearnCondition ohne Stufe / Geld), nach ID
func class_skills(p: Dictionary) -> Array:
	var out = []
	for id in templates:
		var s: Dictionary = templates[id]
		var req: Array = s.get("require_level", [])
		if int(s["from"]) == 1 and int(s["class"]) == int(p["class"]) and int(s["race"]) in [0, int(p["race"])] \
				and int(s.get("max_learn", 0)) > 0 and not req.is_empty() and int(req[0]) > 0:
			out.append(int(id))
	out.sort()
	return out

# Nächste Lernstufe [Stufe, benötigte Figurenstufe, Kosten Kupfer]; [0, 0, 0] = ausgelernt
func next_learn(p: Dictionary, id: int) -> Array:
	var s: Dictionary = templates.get(id, {})
	var next = int(p.get("skills", {}).get(id, 0)) + 1
	var req: Array = s.get("require_level", [])
	if s.is_empty() or next > mini(int(s.get("max_learn", 0)), req.size()):
		return [0, 0, 0]
	var need = int(req[next - 1])
	return [next, need, cost_of(s, next, need)]

# Kupfer für eine Lernstufe: cost_money (ein Wert oder einer je Stufe, "a,b,c") * Faktor der benötigten Stufe
func cost_of(s: Dictionary, next: int, need: int) -> int:
	var parts = str(s.get("cost_money", "")).split(",", false)
	if parts.is_empty():
		return 0
	var base = float(parts[mini(next - 1, parts.size() - 1)])
	var f = float(learn_factor[need - 1]) if need >= 1 and need <= learn_factor.size() else 0.0
	return int(base * f)

func _prereq_ok(p: Dictionary, s: Dictionary) -> bool:
	var pre = int(s.get("pre_skill", 0))
	return pre == 0 or int(p.get("skills", {}).get(pre, 0)) >= int(s.get("pre_level", 1))

func catalog(p: Dictionary) -> Array:
	var out = []
	for id in class_skills(p):
		var n = next_learn(p, id)
		var s: Dictionary = templates[id]
		out.append([id, n[0], n[1], n[2], int(s.get("max_learn", 0)), int(s["type"]), int(s["use"]), int(s["require_level"][0])])
	return out

# Bis AUTO_LEARN_LEVEL: alle Lernstufen, deren Figurenstufe erreicht ist, kostenlos (neu -> "Neue Fertigkeiten")
# -> gelernte [[ID, Stufe]]
func auto_learn(peer: int, p: Dictionary) -> Array:
	var cap = mini(int(p.get("level", 1)), AUTO_LEARN_LEVEL)
	var out = []
	for round in 2: # Voraussetzungen, die erst in dieser Runde gelernt werden
		for id in class_skills(p):
			var s: Dictionary = templates[id]
			if not _prereq_ok(p, s):
				continue
			var level = int(p.get("skills", {}).get(id, 0))
			var target = level
			var n = next_learn(p, id)
			while n[0] != 0 and int(n[1]) <= cap:
				target = int(n[0])
				p["skills"][id] = target # nur für next_learn; learn() speichert und meldet
				n = next_learn(p, id)
			if target > level:
				if level == 0:
					p["skills"].erase(id)
				else:
					p["skills"][id] = level
				learn(peer, p, id, target)
				out.append([id, target])
	if not out.is_empty() and peer >= 0:
		net.push(peer, "skill_catalog", {"list": catalog(p)})
	return out

# Lernen (über AUTO_LEARN_LEVEL; der Client fragt über das K-Fenster) -> [Code, {id, level, cost, bind, gold}].
# Bezahlt wird mit Seelenmünzen; reichen sie nicht, deckt Gold den Rest nur mit use_gold (der Client fragt vorher,
# wie das Original: "Nicht genug Seelenmünzen ... Goldmünzen verwenden?"), sonst NOT_ENOUGH_BIND_MONEY.
func learn_request(peer: int, p: Dictionary, id, use_gold: bool = false) -> Array:
	if not id is int or not templates.has(id) or not id in class_skills(p):
		return [Proto.Code.SKILL_NOT_LEARNABLE, {}]
	var s: Dictionary = templates[id]
	var n = next_learn(p, id)
	if int(n[0]) == 0:
		return [Proto.Code.SKILL_MAXED, {}]
	if int(p.get("level", 1)) < int(n[1]):
		return [Proto.Code.SKILL_LEVEL_LOW, {"need": n[1]}]
	if not _prereq_ok(p, s):
		return [Proto.Code.SKILL_PREREQ, {"skill": int(s["pre_skill"]), "level": int(s.get("pre_level", 1))}]
	var cost = int(n[2])
	var bind = int(p.get("bind_money", 0))
	var gold = int(p.get("money", 0))
	if bind < cost and bind + gold < cost:
		return [Proto.Code.NOT_ENOUGH_MONEY, {"cost": cost}]
	if bind < cost and not use_gold:
		return [Proto.Code.NOT_ENOUGH_BIND_MONEY, {"cost": cost, "bind": bind}]
	var from_bind = mini(bind, cost)
	p["bind_money"] = bind - from_bind
	p["money"] = gold - (cost - from_bind)
	if not db.run("UPDATE characters SET money = ?, bind_money = ? WHERE id = ?", [p["money"], p["bind_money"], p["id"]]):
		log_line.call("FEHLER Datenbank: " + db.last_error)
	learn(peer, p, id, int(n[0]))
	if stats_push.is_valid():
		stats_push.call(peer, p)
	net.push(peer, "skill_catalog", {"list": catalog(p)})
	log_line.call("Fertigkeiten: %s lernt %d Stufe %d für %d Kupfer (%d Seelen-, %d Goldmünzen)" % [p["name"], id, n[0], cost,
		from_bind, cost - from_bind])
	return [Proto.Code.OK, {"id": id, "level": n[0], "cost": cost, "bind": from_bind, "gold": cost - from_bind}]

# Fertigkeit vergessen (Quest-Belohnung del_skill, z.B. eine Rassen-Fertigkeit wird durch eine andere ersetzt)
func forget(peer: int, p: Dictionary, id: int) -> void:
	var known: Dictionary = p.get("skills", {})
	if not known.has(id):
		return
	known.erase(id)
	p.get("skills_new", {}).erase(id)
	db.run("DELETE FROM skills WHERE character_id = ? AND skill_id = ?", [p["id"], id])
	for k in p.get("shortcuts", {}).keys():
		if int(p["shortcuts"][k]) == id:
			p["shortcuts"].erase(k)
			db.run("DELETE FROM shortcuts WHERE character_id = ? AND bar = ? AND slot = ?", [p["id"], k.x, k.y])
	net.push(peer, "skill_forget", {"id": id})
	log_line.call("Fertigkeiten: %s vergisst %d" % [p["name"], id])
