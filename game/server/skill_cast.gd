extends RefCounted

# ====================================================
# Einsetzen der Fertigkeiten (Fertigkeiten-Fahrplan F2) nach wskill SkillWrapper::StartSkill / Run /
# CheckCondition, Skill::FirstRun / Run / CheckRange und PlayerWrapper::FillAttackMsg / SetPerform.
# Daten: Plugin Server/skill_templates.json (tools/server_data/skill_templates.py aus der Editor-
# Datenbank), Formeln über skill_expr.gd mit den Werten der Figur (_ctx: level = Stufe der Fertigkeit,
# player.*, t0..t15 = Talent-Formeln, range = Reichweite der Waffe).
# Ablauf (skill_cast):
#   Prüfen   tot, bekannt, schon umgesetzt (usable), zaubert schon, Abklingzeit, Ziel (sichtbares, lebendes
#            Monster), Mana (mp), Weite: Abstand > Größen + pray_max -> OUT_OF_RANGE, < pray_min -> TOO_CLOSE
#   Zaubern  Zauberzeit = Summe der Prozedur-Zeiten (total_time, wie GetTotalCastTime);
#            Prozeduren nacheinander: Prozedur 1 rechnet sofort (calc) und dauert time ms, dann jede
#            weitere: calc, time ms (mindestens MIN_TIME); setzt calc player.perform = 1, wirkt die
#            Fertigkeit (Perform): Mana ab, Abklingzeit beginnt (DoCost), Schaden auf das Ziel, wenn es
#            noch in effect_dist + Größen steht: Waffenschaden * ratio + damage, Treffer + attack,
#            Krit + crit, Krit-Schaden + critdamage (Standard ratio 1, sonst 0), dann wie der
#            Normalangriff (combat.gd damage / hit_monster, Meldung hit mit skill und elapsed).
#            Statuseffekte (buffs.gd): eigene Plätze beim Wirken, Ziel-Plätze nur bei einem Treffer (vor dem
#            Schaden), Erfolg / Dauer / Werte aus den Formeln. Element (damagetype), Meisterschaft / Widerstand fehlen.
#   Abbruch  Bewegen (moved, waagrecht > MOVE_CANCEL) oder skill_cancel, solange die laufende Prozedur abbrechbar ist (cancel,
#            Prozedur 1 meist "1"); Tod; Ziel gestorben / verschwunden vor der Wirkung; Schweigen / Betäuben (buffs.gd);
#            Effekt break (interrupt) mit der Chance break der laufenden Prozedur in %.
#   Siegel   schweigend / betäubt nur Fertigkeiten mit dizzy_usable, entwaffnet nur mit handfree_usable (Formeln,
#            SkillStub dizzyusable / handfreeusable) -> sonst SKILL_SEALED; ein unverwundbares Ziel nimmt weder Schaden
#            noch Ziel-Effekte (hit mit immune).
# Umgesetzt (usable): Angriff / Fluch (type 1 / 3) auf ein Monster (approach 0 / 11), Stärkung (type 2) auf einen
# Spieler bzw. sich selbst (approach 0) oder nur sich selbst (approach 5 Punkt), von Hand (use 2), ohne Bewegung
# (move_mode 0) oder mit Ansturm zum Ziel (move_mode 1). Der Normalangriff pausiert während des Zauberns.
# Ziel (_resolve, wie CECHostPlayer beim Einsetzen): Stärkungen treffen den gewählten Spieler in Sicht, ohne ihn
# (kein Ziel, ein Monster, Zielart 5) die eigene Figur; sie machen keinen Schaden, ihre Ziel-Effekte gehen ohne
# Treffer-Wurf auf das Ziel. Flüche, deren Formeln weder ratio noch damage setzen (64 von 68 im Dump), machen keinen
# Schaden: nur Treffer-Wurf und Effekte (hit mit nodmg). Ansturm (Skill::GetMoveMode 1 / SkillMove): beim Wirken
# läuft der Zaubernde in der Zeit der Prozedur bis vor das Ziel (Meldung skill_move an alle in Sicht); MOVE des
# Clients bis kurz danach zählt nur als Drehung (world.gd dash_until).
# Abklingzeiten nur im Speicher (gehen beim Verlassen der Welt verloren).
# Passiv (use 6, F7): nicht einsetzbar (SKILL_PASSIVE), Dauer-Effekte über apply_passive(s). Schalter (use 7,
# SwitchOn / TrySwitchOff): einsetzen wie eine Stärkung; seine Effekte auf der eigenen Figur halten ihn an (buffs.gd
# switch, Meldung skill_switch); erneut eingesetzt schaltet er aus, ohne Kosten und auch in der Abklingzeit.
# Meldungen: skill_start an die anderen in Sicht, skill_end an alle (auch den Zaubernden), cooldown an
# den Zaubernden, stats nach dem Mana-Abzug.
# ====================================================

const Proto = preload("../common/protocol.gd")
const Expr = preload("skill_expr.gd")
const Buffs = preload("buffs.gd")
const PLUGIN_SERVER = "res://addons/PWE-Manager/Server/"
const MIN_TIME = 50 # ms je Prozedur (Skill::FirstRun / Run)
# Fertigkeiten ohne Aktion im Client: Gebet (1958) hat im Dump 2013 dieselbe Aktion 祈祷_* wie Segen der Menschen (2497,
# Grundaktion 法师_异度空间 mit 人类种族技能_祈祷.gfx). Im Spiel (neuerer Client) zeigt Gebet keine eigene Aktion, nur das
# GFX seines Effekts 1113 (light 16 = 策划联入/免疫控制技.gfx an den Füßen: der kleine blaue Kreis, 4,2 s) - Aussage des
# Spielers (Zwischen-Fahrplan Z2); die Figur läuft dabei weiter.
const NO_ACTION = {1958: true}
const SLACK = 1.0 # m Spielraum für die Weite (Position des Clients ist bis 0,1 s alt)
const MOVE_CANCEL = 0.3 # m: so weit bewegt bricht das Zaubern ab
const PLAYER_RADIUS = 0.5
const DASH_GRACE = 300 # ms nach dem Ansturm, in denen MOVE des Clients noch nicht zählt
const SETS_DAMAGE = "(^|[^.\\w])(ratio|damage)\\s*=[^=]" # Formel setzt Schaden (Flüche meist nicht)
const DEFAULTS = {"ratio": 1.0, "damage": 0.0, "crit": 0.0, "critdamage": 0.0, "toukonratio": 1.0, "damagetype": 0,
	"attack": 0, "player.perform": 0, "player.pray": 0}

var world # world.gd
var net
var log_line: Callable
var combat # combat.gd
var buffs = null # buffs.gd: Statuseffekte der Fertigkeit
var stats_push: Callable # (peer, p) -> Meldung stats
var templates = {} # ID -> Fertigkeit


func _init(p_world, p_net, p_log: Callable, p_combat) -> void:
	world = p_world
	net = p_net
	log_line = p_log
	combat = p_combat

func load_templates() -> String:
	var path = PLUGIN_SERVER + "skill_templates.json"
	if not FileAccess.file_exists(path):
		return "%s fehlt" % path
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return "%s ist kein JSON" % path
	for s in d.get("skills", []):
		templates[int(s["id"])] = s
	return ""

# Lässt sich die Fertigkeit schon einsetzen (Umfang F2)?
func usable(sk: Dictionary) -> bool:
	var t = int(sk["type"])
	var a = int(sk["range"]["approach"])
	var m = int(sk["move_mode"])
	return int(sk["use"]) in [2, 7] and sk["procs"].size() > 0 and ((t in [1, 3] and a in [0, 11] and m in [0, 1])
		or (t == 2 and a in [0, 5, 8] and m == 0))

# Werte einer bekannten Fertigkeit für den Client (Tooltip-Prüfungen, Zauberbalken, Annäherung)
func info(p: Dictionary, id: int) -> Dictionary:
	var sk: Dictionary = templates.get(id, {})
	if sk.is_empty():
		return {}
	var ctx = _ctx(p, sk, int(p.get("skills", {}).get(id, 1)))
	return {"mp": _mp(sk, ctx), "time": total_time(sk, ctx), "cool": maxi(0, int(Expr.value(sk["cool"], ctx))),
		"cast": float(Expr.value(sk["cast_dist"], ctx)), "range": float(Expr.value(sk["pray_max"], ctx)),
		"min": float(Expr.value(sk["pray_min"], ctx)), "type": int(sk["type"]), "approach": int(sk["range"]["approach"]),
		"instant": int(sk["time_type"]) == 2, "act": act_of(sk, ctx),
		"auto": int(sk["autoattack"]) == 0, "usable": usable(sk), "dizzy": _flag(sk, "dizzy_usable", ctx, 0),
		"handfree": _flag(sk, "handfree_usable", ctx, 1), "bless": int(sk["type"]) == 2,
		"self": int(sk["type"]) == 2 and int(sk["range"]["approach"]) in [5, 8], "move": int(sk["move_mode"]),
		"passive": int(sk["use"]) == 6, "switch": int(sk["use"]) == 7}

func infos(p: Dictionary) -> Dictionary:
	var out = {}
	for id in p.get("skills", {}):
		var i = info(p, id)
		if not i.is_empty():
			out[str(id)] = i
	return out

# Restliche Abklingzeiten {ID: ms}
func cooldowns(p: Dictionary) -> Dictionary:
	var out = {}
	var now = Time.get_ticks_msec()
	for id in p.get("cooldowns", {}):
		if int(p["cooldowns"][id]) > now:
			out[str(id)] = int(p["cooldowns"][id]) - now
	return out

# Aktion, die der Client spielt (NO_ACTION: keine)
static func act_of(sk: Dictionary, ctx: Dictionary) -> String:
	if NO_ACTION.has(int(sk["id"])):
		return ""
	return action_name(str(sk["actions"].get("0", "")), int(ctx.get("player.action", 0)))

# Aktion aus der Formel der Fertigkeit ("player.action==1?神族_X:(player.action==2?魔族_X:X)")
static func action_name(e: String, action: int) -> String:
	e = e.strip_edges()
	while e.begins_with("(") and e.ends_with(")"):
		e = e.substr(1, e.length() - 2).strip_edges()
	var q = e.find("?")
	if q < 0:
		return e
	var rest = e.substr(q + 1)
	var depth = 0
	for i in rest.length():
		var c = rest[i]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
		elif c == ":" and depth == 0:
			var ok = int(Expr.value(e.substr(0, q), {"player.action": action})) != 0
			return action_name(rest.substr(0, i) if ok else rest.substr(i + 1), action)
	return e


# ====================================================
# ANFRAGEN -> [Code, Daten]
# ====================================================
func cast(peer: int, p: Dictionary, id, target) -> Array:
	if not id is int or not target is int:
		return [Proto.Code.BAD_REQUEST, {}]
	if p.get("dead", false):
		return [Proto.Code.YOU_ARE_DEAD, {}]
	if not p.get("skills", {}).has(id):
		return [Proto.Code.SKILL_UNKNOWN, {}]
	var sk: Dictionary = templates.get(id, {})
	if not sk.is_empty() and int(sk["use"]) == 6:
		return [Proto.Code.SKILL_PASSIVE, {}]
	if not sk.is_empty() and int(sk["use"]) == 7 and buffs != null and buffs.is_switched(p, id):
		if p.has("cast"):
			return [Proto.Code.SKILL_BUSY, {}]
		buffs.switch_off(p, id) # TrySwitchOff: vor allen Prüfungen, ohne Kosten und Abklingzeit
		log_line.call("Fertigkeit: %s schaltet %d (%s) aus" % [p["name"], id, sk["name"]])
		return [Proto.Code.OK, {"id": id, "time": 0, "off": true}]
	if sk.is_empty() or not usable(sk):
		return [Proto.Code.SKILL_NOT_YET, {}]
	var level = int(p["skills"][id])
	var ctx = _ctx(p, sk, level)
	if (Buffs.sealed(p, "silent") and not _flag(sk, "dizzy_usable", ctx, 0)) \
			or (Buffs.sealed(p, "disarm") and not _flag(sk, "handfree_usable", ctx, 1)):
		return [Proto.Code.SKILL_SEALED, {}]
	if p.has("cast"):
		return [Proto.Code.SKILL_BUSY, {}]
	var now = Time.get_ticks_msec()
	if int(p.get("cooldowns", {}).get(id, 0)) > now:
		return [Proto.Code.SKILL_COOLDOWN, {}]
	var tr = _resolve(p, sk, target)
	if tr.is_empty():
		return [Proto.Code.NO_TARGET, {}]
	var cost = _mp(sk, ctx)
	if int(p["mp"]) < cost:
		return [Proto.Code.NO_MANA, {}]
	var o: Dictionary = tr[1]
	if tr[0] != "self":
		var dist = p["pos"].distance_to(o["pos"])
		var reach = PLAYER_RADIUS + float(tr[2]) * 0.5
		if dist > reach + float(Expr.value(sk["pray_max"], ctx)) + SLACK:
			return [Proto.Code.OUT_OF_RANGE, {}]
		if dist < float(Expr.value(sk["pray_min"], ctx)):
			return [Proto.Code.TOO_CLOSE, {}]
	var nm = world.npc_maps.get(p["map"])
	target = int(o["id"])
	var total = total_time(sk, ctx)
	var c = {"id": id, "level": level, "target": target, "kind": tr[0], "start": now, "pos": p["pos"], "idx": 0, "ctx": ctx,
		"cost": cost, "cool": maxi(0, int(Expr.value(sk["cool"], ctx))), "done": false}
	for k in DEFAULTS:
		ctx[k] = DEFAULTS[k]
	p["cast"] = c
	c["next"] = now + _run_proc(sk, c, 0)
	var a: Dictionary = p.get("attack", {})
	if not a.is_empty():
		a["next"] = maxf(float(a.get("next", 0.0)), (now + total) / 1000.0)
	var act = act_of(sk, ctx)
	_to_viewers(p, p["pos"], "skill_start", {"src": p["id"], "id": id, "dst": target, "time": total, "act": act}, false)
	log_line.call("Fertigkeit: %s setzt %d (%s) auf %d ein, %d ms" % [p["name"], id, sk["name"], target, total])
	if c["done"]:
		_perform(peer, p, sk, c, nm, o)
	return [Proto.Code.OK, {"id": id, "time": total}]

func cancel_request(peer: int, p: Dictionary) -> Array:
	cancel(peer, p, false, "Anfrage")
	return [Proto.Code.OK, {}]

# Zaubern abbrechen; force = auch nicht abbrechbare Prozeduren (Tod, Ziel weg)
func cancel(_peer: int, p: Dictionary, force: bool, why: String = "") -> void:
	var c: Dictionary = p.get("cast", {})
	if c.is_empty():
		return
	var sk: Dictionary = templates.get(int(c["id"]), {})
	if not force:
		var proc: Dictionary = sk["procs"][mini(int(c["idx"]), sk["procs"].size() - 1)]
		if int(Expr.value(str(proc.get("cancel", "")), c["ctx"])) == 0:
			return
	p.erase("cast")
	_to_viewers(p, p["pos"], "skill_end", {"src": p["id"], "id": c["id"], "ok": false}, true)
	log_line.call("Fertigkeit: %s bricht %d ab (%s)" % [p["name"], c["id"], why])

# Bewegung (world.gd move): waagrecht weiter als MOVE_CANCEL vom Ort des Zauberbeginns -> abbrechen
func moved(peer: int, p: Dictionary) -> void:
	var c: Dictionary = p.get("cast", {})
	if c.is_empty():
		return
	var d = Vector2(p["pos"].x - c["pos"].x, p["pos"].z - c["pos"].z).length()
	if d > MOVE_CANCEL:
		cancel(peer, p, false, "bewegt %.2f m" % d)


# Effekt break (BreakSession): unterbricht mit der Chance break (%) der laufenden Prozedur; leer = 0
func interrupt(peer: int, p: Dictionary) -> bool:
	var c: Dictionary = p.get("cast", {})
	if c.is_empty():
		return false
	var procs: Array = templates.get(int(c["id"]), {}).get("procs", [])
	var f = str(procs[mini(int(c["idx"]), procs.size() - 1)].get("break", "")) if not procs.is_empty() else ""
	var prob = int(Expr.value(f, c["ctx"], 0)) if f.strip_edges() != "" else 0
	if randi() % 100 >= prob:
		return false
	cancel(peer, p, true, "unterbrochen (%d %%)" % prob)
	return true


# ====================================================
# TAKT (world.gd, vor dem Kampf-Takt)
# ====================================================
func tick() -> void:
	var now = Time.get_ticks_msec()
	for peer in world.players.keys():
		var p = world.players.get(peer)
		if p == null or not p.has("cast"):
			continue
		if p.get("dead", false):
			cancel(peer, p, true, "tot")
			continue
		var c: Dictionary = p["cast"]
		if now < int(c["next"]):
			continue
		var sk: Dictionary = templates[int(c["id"])]
		var idx = int(c["idx"]) + 1
		if idx >= sk["procs"].size():
			p.erase("cast")
			_to_viewers(p, p["pos"], "skill_end", {"src": p["id"], "id": c["id"], "ok": true}, true)
			log_line.call("Fertigkeit: %s fertig mit %d" % [p["name"], c["id"]])
			continue
		var nm = world.npc_maps.get(p["map"])
		var o = _target_of(p, c)
		if not c["done"] and (o == null or int(o["hp"]) <= 0):
			cancel(peer, p, true, "Ziel weg") # vor der Wirkung gestorben / verschwunden
			continue
		c["next"] = now + _run_proc(sk, c, idx)
		if c["done"] and not c.get("performed", false):
			_perform(peer, p, sk, c, nm, o)

# Prozedur idx: rechnen, -> Dauer ms; player.perform = 1 markiert die Wirkung (done)
func _run_proc(sk: Dictionary, c: Dictionary, idx: int) -> int:
	c["idx"] = idx
	var proc: Dictionary = sk["procs"][idx]
	var ctx: Dictionary = c["ctx"]
	ctx["player.perform"] = 0
	Expr.value(str(proc["calc"]), ctx)
	if int(ctx.get("player.perform", 0)) == 1:
		c["done"] = true
	return maxi(MIN_TIME, int(Expr.value(str(proc["time"]), ctx)))

# Wirkung: Mana, Abklingzeit, Schaden
func _perform(peer: int, p: Dictionary, sk: Dictionary, c: Dictionary, nm, o) -> void:
	c["performed"] = true
	var now = Time.get_ticks_msec()
	p["mp"] = maxi(0, int(p["mp"]) - int(c["cost"]))
	if int(c["cool"]) > 0:
		if not p.has("cooldowns"):
			p["cooldowns"] = {}
		p["cooldowns"][int(c["id"])] = now + int(c["cool"])
		net.push(peer, "cooldown", {"id": c["id"], "ms": c["cool"]})
	if stats_push.is_valid():
		stats_push.call(peer, p)
	var ctx: Dictionary = c["ctx"]
	_states(p, p, sk, ctx, true, false) # BlessMe: auf sich, unabhängig vom Treffer
	if o == null or int(o["hp"]) <= 0:
		return
	var monster = c.get("kind", "monster") == "monster"
	var size = float(combat.monster_props(nm, o)["size"]) if monster else PLAYER_RADIUS * 2.0
	var reach = PLAYER_RADIUS + size * 0.5 + float(Expr.value(str(sk["range"]["effect_dist"]), ctx, 0.0))
	if o != p and p["pos"].distance_to(o["pos"]) > reach + SLACK:
		_to_viewers(p, p["pos"], "skill_end", {"src": p["id"], "id": c["id"], "ok": false}, true)
		p.erase("cast")
		log_line.call("Fertigkeit: %s - %d verfehlt, Ziel außer Reichweite" % [p["name"], c["id"]])
		return
	if not monster: # Stärkung: Treffer (für das Treffer-GFX), Ziel-Effekte auf den Spieler bzw. sich selbst, kein Schaden
		_to_viewers(p, p["pos"], "hit", {"src": p["id"], "dst": o["id"], "dmg": 0, "miss": false, "crit": false, "bless": true,
			"hp": o["hp"], "max_hp": o["max_hp"], "skill": c["id"], "elapsed": now - int(c["start"])}, true)
		_states(p, o, sk, ctx, false, false)
		return
	var mprop = combat.monster_props(nm, o)
	if int(sk["move_mode"]) == 1:
		_charge(p, o, size, maxi(0, int(c["next"]) - now))
	var att: Dictionary = combat.player_props(p).duplicate()
	var ratio = float(ctx.get("ratio", 1.0))
	var plus = float(ctx.get("damage", 0.0))
	var d: Array = att["dmg"]
	att["dmg"] = [float(d[0]) * ratio + plus, float(d[1]) * ratio + plus]
	att["hit"] = float(att.get("hit", 0)) + float(ctx.get("attack", 0))
	att["crit"] = float(att.get("crit", 0)) + 100.0 * float(ctx.get("crit", 0.0))
	att["crit_dmg"] = float(att.get("crit_dmg", 100)) + 100.0 * float(ctx.get("critdamage", 0.0))
	if Buffs.sealed(o, "invincible"):
		combat.hit_monster(peer, p, nm, o, {"dmg": 0, "miss": false, "crit": false, "immune": true}, now / 1000.0,
			{"skill": c["id"], "elapsed": now - int(c["start"])})
		return
	var r = combat.damage(att, Buffs.with_mods(mprop, o))
	if int(sk["type"]) == 3 and not _sets_damage(sk):
		r = {"dmg": 0, "miss": r["miss"], "crit": false, "nodmg": true} # Fluch ohne Schaden: nur Treffer und Effekte
	if not r["miss"]:
		_states(p, o, sk, ctx, false, r["crit"]) # StateAttack: nur bei Treffer, vor dem Schaden
	combat.hit_monster(peer, p, nm, o, r, now / 1000.0, {"skill": c["id"], "elapsed": now - int(c["start"])})

# Statuseffekte der Fertigkeit (SkillStub BuildSkillState): Ziel-Plätze (self false) bzw. eigene; Erfolg, Dauer
# und Werte aus den Formeln; ohne Erfolgs-Formel 0 % (StateFilter _succeedparam)
func _states(p: Dictionary, target: Dictionary, sk: Dictionary, ctx: Dictionary, self_slots: bool, crit: bool) -> void:
	if buffs == null:
		return
	for e in sk["states"]:
		if bool(e["self"]) != self_slots or str(e["chance"]).strip_edges() == "":
			continue
		var chance = int(Expr.value(str(e["chance"]), ctx, 0))
		if chance == 0:
			continue
		var values = []
		for x in e["data"]:
			values.append(float(Expr.value(str(x), ctx, 0.0)) if str(x).strip_edges() != "" else 0.0)
		# Schalter: seine Effekte auf der eigenen Figur halten ihn an (StateFilter SWITCH_BUFF)
		var extra = {"switch": int(sk["id"])} if int(sk["use"]) == 7 and target == p else {}
		buffs.apply(target, p["map"], int(e["id"]), values, int(Expr.value(str(e["time"]), ctx, 0)), chance, p, crit, extra)


# ====================================================
# PASSIVE FERTIGKEITEN (F7, SkillStub::OnLearnPassiveSkill)
# ====================================================
# Dauer-Effekte einer passiven Fertigkeit (use 6) mit ihrer Stufe auf die Figur: beim Betreten der Welt (passive_event
# 1 = EVENT_RESET, dann unabhängig von der Klasse) und beim Lernen; eine neue Stufe ersetzt die alte (UndoEffect,
# TakeEffect). Ohne Erfolgs-Formel 100 %. -> Anzahl angelegter Effekte
func apply_passive(p: Dictionary, id: int) -> int:
	var sk: Dictionary = templates.get(id, {})
	if sk.is_empty() or int(sk["use"]) != 6 or buffs == null or not p.get("skills", {}).has(id):
		return 0
	var had = buffs.remove_passive(p, id, false)
	var ctx = _ctx(p, sk, int(p["skills"][id]))
	var n = 0
	for e in sk["states"]:
		var f = str(e["chance"]).strip_edges()
		var chance = 100 if f == "" else int(Expr.value(f, ctx, 0))
		if chance == 0:
			continue
		var values = []
		for x in e["data"]:
			values.append(float(Expr.value(str(x), ctx, 0.0)) if str(x).strip_edges() != "" else 0.0)
		var t = int(Expr.value(str(e["time"]), ctx, 0)) if str(e["time"]).strip_edges() != "" else 0
		if buffs.apply(p, p["map"], int(e["id"]), values, t, chance, p, false, {"passive": id}):
			n += 1
	if had > 0 and n == 0:
		buffs._changed(p)
	return n

# Alle passiven Fertigkeiten der Figur (Betreten der Welt) -> Anzahl Effekte
func apply_passives(p: Dictionary) -> int:
	var n = 0
	for id in p.get("skills", {}):
		n += apply_passive(p, int(id))
	return n


# ====================================================
# HILFEN
# ====================================================
# Werte für die Formeln (PlayerWrapper / skill.og); Talente t0..t15 = (int) Formel
func _ctx(p: Dictionary, sk: Dictionary, level: int) -> Dictionary:
	var a: Dictionary = combat.player_props(p)
	var dmg: Array = a.get("dmg", [1, 1])
	var ctx = {"id": int(sk["id"]), "level": level, "showlevel": level, "playerlevel": int(p["level"]), "rand": randi() % 100,
		"range": combat.player_range(p), "player.level": int(p["level"]), "player.hp": int(p["hp"]), "player.maxhp": int(p["max_hp"]),
		"player.mp": int(p["mp"]), "player.maxmp": int(p["max_mp"]), "player.damagelow": int(dmg[0]), "player.damagehigh": int(dmg[1]),
		"player.attack": int(a.get("hit", 0)), "player.armor": int(a.get("eva", 0)), "player.defence": int(a.get("def", 0)),
		"player.critrate": float(a.get("crit", 0)) / 100.0, "player.critdmg": float(a.get("crit_dmg", 100)) / 100.0,
		"player.race": int(p["race"]), "player.runspeed": Proto.RUN_SPEED, "player.action": 0,
		"player.skilllevel": p.get("skills", {}), "player.bufflevel": {}, "player.buffnum": {}, "player.rune": {}}
	for i in 16:
		var k = "t%d" % i
		if sk["talents"].has(k):
			ctx[k] = int(Expr.value(str(sk["talents"][k]), ctx))
	return ctx

# Zauberzeit = Summe der Prozedur-Zeiten (SkillStub::GetTotalCastTime; exetime ist nur ein Anzeigewert)
# Zauberzeit für Client und Anzeige: Summe der Prozeduren (ohne MIN_TIME, das nur den Takt bestimmt: Sofort-Fertigkeiten
# wie Gebet melden 0 und zeigen keinen Zauberbalken)
static func total_time(sk: Dictionary, ctx: Dictionary) -> int:
	var t = 0
	for proc in sk["procs"]:
		t += maxi(0, int(Expr.value(str(proc["time"]), ctx)))
	return t

# Ziel -> [Art, Objekt, Größe]: Angriff / Fluch ein sichtbares, lebendes Monster ("monster"); Stärkung der gewählte
# Spieler in Sicht ("player"), sonst die eigene Figur ("self"); [] = kein gültiges Ziel
func _resolve(p: Dictionary, sk: Dictionary, target: int) -> Array:
	if int(sk["type"]) == 2:
		# Zielart 5 (Punkt) und 8 (um sich, Auren: ohne Gruppe nur die eigene Figur) -> immer sich selbst
		if not int(sk["range"]["approach"]) in [5, 8] and target != int(p["id"]) and p.get("seen", {}).has(target):
			var o = _player_by_id(target)
			if o != null and not o.get("dead", false):
				return ["player", o, PLAYER_RADIUS * 2.0]
		return ["self", p, 0.0]
	var nm = world.npc_maps.get(p["map"])
	var o = nm.objects.get(target) if nm != null and p["npc_seen"].has(target) else null
	if o == null or o["npc"] or o.get("mine", false) or not o["select"] or int(o["hp"]) <= 0:
		return []
	return ["monster", o, float(combat.monster_props(nm, o)["size"])]

func _target_of(p: Dictionary, c: Dictionary):
	match str(c.get("kind", "monster")):
		"self":
			return p
		"player":
			return _player_by_id(int(c["target"]))
	var nm = world.npc_maps.get(p["map"])
	return nm.objects.get(int(c["target"])) if nm != null else null

func _player_by_id(id: int):
	for q in world.players.values():
		if int(q["id"]) == id:
			return q
	return null

# Ansturm: in ms bis vor das Ziel (Größen), Meldung skill_move an alle in Sicht (auch den Zaubernden)
func _charge(p: Dictionary, o: Dictionary, size: float, ms: int) -> void:
	var flat = Vector2(o["pos"].x - p["pos"].x, o["pos"].z - p["pos"].z)
	var stop = PLAYER_RADIUS + size * 0.5
	if flat.length() <= stop:
		return
	var dir = flat.normalized()
	var to = Vector3(o["pos"].x - dir.x * stop, o["pos"].y, o["pos"].z - dir.y * stop)
	var now = Time.get_ticks_msec()
	p["pos"] = to
	p["dir"] = atan2(dir.x, dir.y)
	p["t"] = now
	p["dash_until"] = now + ms + DASH_GRACE
	_to_viewers(p, to, "skill_move", {"id": p["id"], "pos": [to.x, to.y, to.z], "time": ms}, true)
	log_line.call("Fertigkeit: %s stürmt %.1f m zum Ziel" % [p["name"], flat.length() - stop])

# Setzt eine Formel der Fertigkeit ratio oder damage (sonst macht ein Fluch keinen Schaden)?
func _sets_damage(sk: Dictionary) -> bool:
	if not sk.has("_sets_damage"):
		var re = RegEx.create_from_string(SETS_DAMAGE)
		sk["_sets_damage"] = sk["procs"].any(func(pr): return re.search(str(pr.get("calc", ""))) != null)
	return sk["_sets_damage"]

# Ja / Nein-Feld einer Fertigkeit (Zahl oder Formel), leer = Standard
static func _flag(sk: Dictionary, key: String, ctx: Dictionary, default: int) -> bool:
	var f = str(sk.get(key, "")).strip_edges()
	return int(Expr.value(f, ctx, default)) != 0 if f != "" else default != 0

func _mp(sk: Dictionary, ctx: Dictionary) -> int:
	return maxi(0, int(Expr.value(str(sk["mp"]), ctx)))

# Meldung an alle Spieler in Sicht des Ortes; self_too = auch an den Zaubernden
func _to_viewers(p: Dictionary, pos: Vector3, what: String, data: Dictionary, self_too: bool) -> void:
	for peer in world.players:
		var o = world.players[peer]
		if (o != p or self_too) and o["map"] == p["map"] and o["pos"].distance_to(pos) <= Proto.VIEW_RANGE:
			net.push(peer, what, data)
