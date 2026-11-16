extends SceneTree

# ====================================================
# Test der Statuseffekte (server/buffs.gd, Fertigkeiten-Fahrplan F3) ohne Server, mit eigener Uhr:
#   godot --headless --path <Projekt> -s res://game/tests/buff_test.gd
# Prüft mit den echten Effekt-Vorlagen (Plugin Server/state_templates.json): Brennen (583) aus dem Feuerball
# tickt fünfmal 30 Schaden im Sekundentakt und endet nach 5 s, Meldungen buffs / hit an einen Zuschauer;
# "unabhängig" (583): je Zaubernder ein Effekt; Vorzeichen (646 Abwehr -10 mit Parameter 0) und with_mods;
# Stapeln (Regel 6) bis max_stack; sofortige Heilung (120) ohne bleibenden Effekt; Höchst-Leben (871) und
# zurück beim Ablauf; verzögerter Beginn (869); Zeit < 500 ms, Erfolg 0 %, Immunität, -1 (wie zuletzt);
# Tod entfernt OVER_DEATH-Effekte; Brennen tötet und gibt den Abschuss dem Zaubernden.
# Kontrolle (F5): Betäuben (365) setzt die Siegel idle / root / silent / melee, meldet seal, bricht das Zaubern ab
# und beendet den Normalangriff, am Ende wieder frei; Wurzeln (90) hält ein laufendes Monster an; Unterbrechen (73)
# fragt die Chance der laufenden Prozedur ab; Entwaffnen (361); Unverwundbar (269) schützt vor Brennen (Klasse
# 1024) und Schaden; Bannen (187, Maske 8) entfernt Schlaf (2156); clearFilter (509) entfernt einen Effekt per ID;
# Spott (67) lenkt ein Monster auf den Zaubernden.
# F7: passiver Dauer-Effekt (1183 Leben +3 %) bleibt über Tod und Bannen, remove_passive nimmt ihn zurück; Schalter-
# Effekte (2093: 88 ohne Ende, 1166 3 s) melden skill_switch an (einmal), beim Ablauf des letzten aus, switch_off.
# Z2: Gebet (1113) bannt Betäuben, gibt Mana und 4,2 s Immunität (GFX light 16); Segen der Menschen (1237) Leben + alle
# Meisterschaften, Segen der Steinmenschen (1241) absorbiert Schaden, Segen der Werwölfe (2880) Tempo und Krit.
# Ende: "STATUSEFFEKTE-TEST OK" (Exit 0) oder "STATUSEFFEKTE-TEST FEHLER" (Exit 1).
# ====================================================

const Buffs = preload("../server/buffs.gd")
const Combat = preload("../server/combat.gd")
const Quests = preload("../server/quests.gd")
const Stats = preload("../server/stats.gd")
const Proto = preload("../common/protocol.gd")

class FakeNet:
	var pushed: Array = []
	func push(peer, what, data) -> void:
		pushed.append([peer, what, data])

class FakeWorld:
	var players = {}
	var npc_maps = {"s9": FakeMap.new()}

class FakeMap:
	var moves: Array = []
	var terrain = null

class FakeCasting:
	var cancelled: Array = [] # Figuren-IDs
	var interrupted: Array = []
	func cancel(_peer, p, _force, _why = "") -> void:
		cancelled.append(int(p["id"]))
		p.erase("cast")
	func interrupt(_peer, p) -> bool:
		interrupted.append(int(p["id"]))
		return true

class FakeCombat:
	var killed: Array = [] # [Opfer, Zaubernder]
	func player_killed(p) -> void:
		killed.append([int(p["id"]), 0])
	func monster_killed(src, _map_name, o) -> void:
		killed.append([int(o["id"]), int(src)])
	var stopped: Array = [] # Normalangriff beendet (Siegel melee)
	func stop(p) -> void:
		stopped.append(int(p["id"]))

var checks = 0
var failures = 0
var now = 1000000
var net = FakeNet.new()
var world = FakeWorld.new()
var combat = FakeCombat.new()
var casting = FakeCasting.new()
var buffs


func _initialize() -> void:
	buffs = Buffs.new(world, net, func(_s): pass)
	buffs.combat = combat
	buffs.casting = casting
	buffs.clock = func(): return now
	var err = buffs.load_templates()
	_check("Vorlagen geladen (%d Effekte) %s" % [buffs.states.size(), err], err == "" and buffs.states.size() > 3000)
	if err != "":
		_end()
		return
	world.players[7] = {"id": 7, "map": "s9", "pos": Vector3.ZERO} # Zuschauer
	var mage = {"id": 11, "name": "Magier", "map": "s9", "pos": Vector3.ZERO}
	var other = {"id": 12, "name": "Zweiter", "map": "s9", "pos": Vector3.ZERO}
	_burn(mage, other)
	_modifiers(mage)
	_stack(mage)
	_instant_and_hp(mage)
	_rules(mage)
	_kill(mage)
	_control(mage)
	_passive_switch()
	_race_skills()
	_base_values()
	_end()

func _monster(hp: int) -> Dictionary:
	return {"id": Proto.NPC_ID_BASE + randi() % 100000, "hp": hp, "max_hp": hp, "mp": 0, "max_mp": 0, "level": 1,
		"pos": Vector3(1, 0, 0), "fight": false, "target": 0}

func _advance(ms: int) -> void:
	var end = now + ms
	while now < end:
		now = mini(end, now + 100)
		buffs.tick()

func _pushes(what: String, from: int) -> Array:
	return net.pushed.slice(from).filter(func(e): return e[1] == what).map(func(e): return e[2])

# Brennen: 5 Ticks à 30, Ende nach 5 s; unabhängig je Zaubernder
func _burn(mage: Dictionary, other: Dictionary) -> void:
	var o = _monster(500)
	var n0 = net.pushed.size()
	var ok = buffs.apply(o, "s9", 583, [30.0], 5000, 100, mage)
	var lst = buffs.list_of(o)
	_check("Brennen (583) angelegt: %s (Sichtbar-Index 8 = Flammen-GFX), Meldung buffs an den Zuschauer" % str(lst), ok
		and lst.size() == 1 and lst[0][0] == 583 and lst[0][2] == 5000 and lst[0].size() == 5 and lst[0][4] == 8
		and _pushes("buffs", n0).size() == 1 and int(_pushes("buffs", n0)[0]["id"]) == int(o["id"]))
	_advance(999)
	var hp_before = int(o["hp"])
	_advance(1)
	var hits = _pushes("hit", n0)
	_check("nach 1 s ein Tick: 30 Schaden (hit mit buff 583, src Magier) - %d HP" % int(o["hp"]), hp_before == 500 and int(o["hp"]) == 470
		and hits.size() == 1 and int(hits[0]["buff"]) == 583 and int(hits[0]["dmg"]) == 30 and int(hits[0]["src"]) == 11)
	_check("getroffenes Monster greift den Zaubernden an? (kein Spieler online: target bleibt 0)", int(o["target"]) == 0)
	_advance(3999)
	var still = buffs.list_of(o).size()
	_advance(1)
	hits = _pushes("hit", n0)
	var last: Dictionary = _pushes("buffs", n0)[-1]
	_check("nach 5 s: 5 Ticks (%d HP), Effekt weg (%d vorher), letzte Meldung leer" % [int(o["hp"]), still], int(o["hp"]) == 350
		and hits.size() == 5 and still == 1 and buffs.list_of(o).is_empty() and last["list"].is_empty())
	# unabhängig (Regel 5): je Zaubernder einer
	buffs.apply(o, "s9", 583, [30.0], 5000, 100, mage)
	buffs.apply(o, "s9", 583, [20.0], 5000, 100, other)
	buffs.apply(o, "s9", 583, [30.0], 5000, 100, mage)
	_check("Regel 5 (unabhängig): zwei Zaubernde -> zwei Brände, derselbe ersetzt seinen (%d)" % buffs.list_of(o).size(),
		buffs.list_of(o).size() == 2)
	var hp0 = int(o["hp"])
	_advance(1000)
	_check("beide Brände ticken (%d -> %d)" % [hp0, int(o["hp"])], hp0 - int(o["hp"]) == 50)
	buffs.on_death(o)
	_check("Tod entfernt OVER_DEATH-Effekte", buffs.list_of(o).is_empty())

# Werte: 646 (modifyPhyDefense, Parameter 0) zieht ab
func _modifiers(mage: Dictionary) -> void:
	var o = _monster(500)
	var ok = buffs.apply(o, "s9", 646, [10.0, 0.0], 20000, 100, mage)
	var m = Buffs.mods_of(o)
	var w = Buffs.with_mods({"dmg": [100, 120], "def": 100, "hit": 50, "eva": 10, "crit": 5.0}, o)
	_check("646 Abwehr -10 (Vorzeichen über den Parameter): mods %s, with_mods def %s" % [str(m), str(w.get("def"))], ok
		and is_equal_approx(float(m.get("def", 0)), -10.0) and is_equal_approx(float(w["def"]), 90.0))

# Stapeln (Regel 6): erster Effekt mit Regel 6, max_stack >= 3 und einer Werte-Wirkung
func _stack(mage: Dictionary) -> void:
	var sid = 0
	for id in buffs.states:
		var st: Dictionary = buffs.states[id]
		if int(st["cover"]) == 6 and int(st["max_stack"]) >= 3 and int(st["time_type"]) == 1 and str(st["begin"][0]) == "1" \
				and not st["effects"].is_empty() and Buffs.MODS.has(buffs.kinds.get(int(st["effects"][0]["hs"]), {}).get("name", "")):
			sid = id
			break
	if sid == 0:
		_check("Effekt mit Regel 6 gefunden", false)
		return
	var st: Dictionary = buffs.states[sid]
	var o = _monster(500)
	o["level"] = maxi(1, int(st["min_level"]))
	for i in int(st["max_stack"]) + 1:
		buffs.apply(o, "s9", sid, [5.0, 5.0, 5.0, 5.0, 5.0], 10000, 100, mage)
	var lst = buffs.list_of(o)
	var key = Buffs.MODS[buffs.kinds[int(st["effects"][0]["hs"])]["name"]]
	var v = absf(float(Buffs.mods_of(o).get(key, 0)))
	var unit = 100.0 if key in Buffs.TO_PERCENT else (1000.0 if key in Buffs.PERMILLE else 1.0)
	_check("Regel 6 (stapeln) %d %s: %d x angelegt -> Stapel %s von %d, Wert %s" % [sid, st["name"], int(st["max_stack"]) + 1,
		str(lst[0][1]) if not lst.is_empty() else "-", int(st["max_stack"]), str(v)], lst.size() == 1 and int(lst[0][1]) == int(st["max_stack"])
		and is_equal_approx(v, 5.0 * unit * int(st["max_stack"])))

# Sofort-Heilung (120), Höchst-Leben (871), verzögerter Beginn (869)
func _instant_and_hp(mage: Dictionary) -> void:
	var p = {"id": 5, "name": "Priester", "map": "s9", "pos": Vector3.ZERO, "hp": 100, "max_hp": 1000, "mp": 0, "max_mp": 100,
		"level": 1, "class": 6, "race": 1}
	var n0 = net.pushed.size()
	var ok = buffs.apply(p, "s9", 120, [967.0], 0, 100, mage)
	var heals = _pushes("heal", n0)
	_check("120 sofortige Heilung: %d HP, heal %s (ganzer Betrag), kein bleibender Effekt" % [int(p["hp"]), str(heals.map(func(h): return h["amount"]))],
		ok and int(p["hp"]) == 1000 and heals.size() == 1 and int(heals[0]["amount"]) == 967 and buffs.list_of(p).is_empty())
	n0 = net.pushed.size()
	buffs.apply(p, "s9", 120, [250.0], 0, 100, mage)
	heals = _pushes("heal", n0)
	_check("120 bei vollem Leben: heal %s (Betrag sichtbar wie im Spiel), Leben bleibt %d" % [str(heals.map(func(h): return h["amount"])), int(p["hp"])],
		heals.size() == 1 and int(heals[0]["amount"]) == 250 and int(p["hp"]) == 1000)
	ok = buffs.apply(p, "s9", 871, [100.0, 0.01], 2000, 100, mage)
	var hp_max = int(p["max_hp"])
	_advance(2000)
	_check("871 Höchst-Leben -100 und -1 %%: %d, nach Ablauf wieder %d" % [hp_max, int(p["max_hp"])], ok and hp_max == 890
		and int(p["max_hp"]) == 1000 and int(p["hp"]) == 890)
	var st: Dictionary = buffs.states.get(869, {})
	var delay = str(st.get("begin_param", ["0"])[0]).to_int()
	p["hp"] = 500
	ok = buffs.apply(p, "s9", 869, [30.0], 1000 + delay, 100, mage)
	var before = int(p["hp"])
	_advance(delay + 100)
	_check("869 verzögerter Beginn (%d ms): Heilung erst danach (%d -> %d)" % [delay, before, int(p["hp"])], ok and before == 500
		and int(p["hp"]) == 530)

# Bedingungen: zu kurz, 0 %, -1, Immunität
func _rules(mage: Dictionary) -> void:
	var o = _monster(500)
	var short = buffs.apply(o, "s9", 583, [30.0], 400, 100, mage)
	var zero = buffs.apply(o, "s9", 583, [30.0], 5000, 0, mage)
	var after_fail = buffs.apply(o, "s9", 583, [30.0], 5000, -1, mage)
	buffs.apply(o, "s9", 583, [30.0], 5000, 100, mage)
	var after_ok = buffs.apply(o, "s9", 583, [30.0], 5000, -1, mage)
	o["immune"] = int(buffs.states[646]["bag"])
	var immune = buffs.apply(o, "s9", 646, [10.0], 5000, 100, mage)
	_check("Zeit < 500 ms (%s), Erfolg 0 %% (%s), -1 nach Fehlschlag (%s) / nach Erfolg (%s), Immunität (%s)" % [short, zero, after_fail,
		after_ok, immune], not short and not zero and not after_fail and after_ok and (not immune or int(buffs.states[646]["bag"]) == 0))

# Brennen tötet: Abschuss für den Zaubernden
func _kill(mage: Dictionary) -> void:
	var o = _monster(20)
	buffs.apply(o, "s9", 583, [30.0], 5000, 100, mage)
	_advance(1000)
	_check("Brennen tötet (%d HP): Abschuss an den Magier %s" % [int(o["hp"]), str(combat.killed)], int(o["hp"]) == 0
		and combat.killed.has([int(o["id"]), 11]))

# Kontrolle (F5)
func _control(mage: Dictionary) -> void:
	world.players[31] = mage # Zaubernder in der Welt (Spott, Rückstoß)
	var p = {"id": 21, "name": "Bot", "map": "s9", "pos": Vector3.ZERO, "hp": 1000, "max_hp": 1000, "mp": 100, "max_mp": 100,
		"level": 1, "race": 1, "class": 1, "cast": {"id": 154}}
	world.players[30] = p
	var n0 = net.pushed.size()
	var ok = buffs.apply(p, "s9", 365, [], 2000, 100, mage)
	var s = Buffs.seals_of(p)
	var seal_msgs = net.pushed.slice(n0).filter(func(e): return e[1] == "seal" and e[0] == 30)
	_check("Betäuben (365): %s, seal an die Figur (%d), Zaubern abgebrochen, Normalangriff beendet" % [str(s), seal_msgs.size()],
		ok and s["idle"] and s["root"] and s["silent"] and s["melee"] and not s["disarm"] and seal_msgs.size() == 1
		and seal_msgs[0][2]["root"] and casting.cancelled.has(21) and combat.stopped.has(21) and not p.has("cast"))
	n0 = net.pushed.size()
	_advance(2100)
	seal_msgs = net.pushed.slice(n0).filter(func(e): return e[1] == "seal" and e[0] == 30)
	_check("nach 2 s wieder frei: seal ohne Siegel", seal_msgs.size() == 1 and not seal_msgs[0][2].values().has(true)
		and not Buffs.sealed(p, "root"))
	var o = _monster(500)
	o["to"] = Vector3(5, 0, 0)
	buffs.apply(o, "s9", 90, [], 3000, 100, mage)
	_check("Wurzeln (90) hält ein laufendes Monster an (Ziel weg, npc_move)", Buffs.sealed(o, "root") and o["to"] == null
		and world.npc_maps["s9"].moves.has(o["id"]))
	p["cast"] = {"id": 154}
	buffs.apply(p, "s9", 73, [], 2500, 100, mage)
	_check("Unterbrechen (73) fragt das Zaubern ab (interrupt)", casting.interrupted.has(21))
	p.erase("cast")
	buffs.apply(p, "s9", 361, [], 3000, 100, mage)
	_check("Entwaffnen (361): Siegel disarm, sonst keins", Buffs.sealed(p, "disarm") and not Buffs.sealed(p, "silent"))
	var o2 = _monster(500)
	buffs.apply(o2, "s9", 269, [], 5000, 100, mage)
	var burned = buffs.apply(o2, "s9", 583, [30.0], 5000, 100, mage)
	_advance(1100)
	_check("Unverwundbar (269): Siegel invincible, Immunität 1024 wehrt Brennen ab (%s), kein Schaden (%d HP)" % [str(burned), int(o2["hp"])],
		Buffs.sealed(o2, "invincible") and int(o2.get("buff_immune", 0)) == 1024 and not burned and int(o2["hp"]) == 500)
	var o3 = _monster(500)
	buffs.apply(o3, "s9", 2156, [], 10000, 100, mage)
	var slept = Buffs.sealed(o3, "idle")
	buffs.apply(o3, "s9", 187, [], 1000, 100, mage)
	_check("Bannen (187, Maske 8) entfernt Schlaf (2156): vorher betäubt %s, danach %s" % [str(slept), str(Buffs.sealed(o3, "idle"))],
		slept and not Buffs.sealed(o3, "idle") and not buffs.list_of(o3).any(func(e): return int(e[0]) == 2156))
	buffs.apply(o3, "s9", 646, [10.0], 10000, 100, mage)
	buffs.apply(o3, "s9", 509, [646.0], 1000, 100, mage)
	_check("clearFilter (509) entfernt Effekt 646 per ID", not buffs.list_of(o3).any(func(e): return int(e[0]) == 646))
	var o4 = _monster(500)
	buffs.apply(o4, "s9", 67, [], 3000, 100, mage)
	_check("Spott (67): Monster greift den Zaubernden an (Ziel %d)" % int(o4["target"]), int(o4["target"]) == 11 and o4["fight"])
	world.players.erase(31)
	world.players.erase(30)

func _check(what: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("STATUSEFFEKTE-TEST: ", "ok      " if ok else "FEHLER  ", what)

func _end() -> void:
	print("STATUSEFFEKTE-TEST %s (%d Prüfungen)" % ["OK" if failures == 0 else "FEHLER", checks])
	quit(0 if failures == 0 else 1)

# Rassen-Fertigkeiten (Zwischen-Fahrplan Z2): Gebet (1113: Bannen, Mana, Immunität), Segen der Menschen (1237: Leben,
# alle Meisterschaften), Steinmenschen (1241: Schaden absorbieren), Werwölfe (2880: Reittier- / Flugtempo ohne Meldung)
func _race_skills() -> void:
	var logs = []
	buffs.log_line = func(t): logs.append(t)
	var p = {"id": 31, "name": "Mensch", "map": "s9", "pos": Vector3.ZERO, "hp": 1000, "max_hp": 1000, "mp": 20, "max_mp": 100,
		"level": 10, "class": 1, "race": 1}
	world.players[31] = p
	buffs.apply(p, "s9", 365, [], 3000, 100, p)
	_advance(100)
	var stunned = Buffs.sealed(p, "root") and Buffs.sealed(p, "silent")
	var ok = buffs.apply(p, "s9", 1113, [0.0, 25.0], 4200, 100, p) # Gebet Stufe 1: 25 % von 100 Mana
	_advance(100)
	var again = buffs.apply(p, "s9", 365, [], 3000, 100, p)
	var ids = buffs.list_of(p).map(func(x): return int(x[0]))
	var light = buffs.list_of(p).filter(func(x): return int(x[0]) == 1113).map(func(x): return int(x[4]))
	_check("Gebet (1113) löst das Betäuben (vorher %s), Mana 20 -> %d, Immunität (Maske %d) wehrt neues Betäuben ab (%s), Effekte %s, GFX light %s" % [
		str(stunned), int(p["mp"]), int(p.get("buff_immune", 0)), str(again), str(ids), str(light)],
		stunned and ok and int(p["mp"]) == 45 and int(p.get("buff_immune", 0)) & 1 != 0 and not again and ids == [1113]
		and not Buffs.sealed(p, "root") and light == [16])
	_advance(4300)
	var after = buffs.apply(p, "s9", 365, [], 1000, 100, p)
	_check("nach 4,2 s ist die Immunität weg: Betäuben greift wieder (%s)" % str(after), after and int(p.get("buff_immune", 0)) == 0)
	_advance(1100)
	buffs.apply(p, "s9", 1237, [0.03, 25.0], 1800000, 100, p) # Segen der Menschen (Spieltext, Z6: +3 % Leben, Meisterschaft +25)
	_advance(100)
	var mas: Array = Quests.attr_of(p)["mas"]
	_check("Segen der Menschen (1237): Leben 1000 -> %d, Meisterschaften %s (physisch bis Dunkel +25, PvE nicht)" % [int(p["max_hp"]), str(mas)],
		int(p["max_hp"]) == 1030 and mas == [25, 25, 25, 25, 25, 25, 25, 0])
	var elf = {"id": 32, "name": "Elf", "map": "s9", "pos": Vector3.ZERO, "hp": 500, "max_hp": 500, "mp": 1000, "max_mp": 1000,
		"level": 10, "class": 5, "race": 2, "attr": {"dmg": [10, 20], "def": 50, "hit": 100, "eva": 30, "crit": 1.0, "crit_dmg": 150.0,
		"anti_crit": 0.0, "anti_crit_dmg": 0.0, "mas": [0, 0, 5, 9, 7, 0, 0, 0], "res": [1, 2, 5, -3, 7, 0, 0, 0]}}
	world.players[32] = elf
	var before: Dictionary = Quests.attr_of(elf)
	buffs.apply(elf, "s9", 1238, [0.01, 25.0, 25.0], 1800000, 100, elf) # Segen der Elfen (Spieltext: Mana +1 %, Genauigkeit +25, Widerstände +25)
	_advance(100)
	var ea: Dictionary = Quests.attr_of(elf)
	_check("Segen der Elfen (1238): Mana 1000 -> %d, Genauigkeit im C-Fenster %d -> %d, Widerstände %s -> %s (Grundwert + 25, PvE 0)" % [
		int(elf["max_mp"]), int(before["hit"]), int(ea["hit"]), str(before["res"]), str(ea["res"])], int(elf["max_mp"]) == 1010
		and int(before["hit"]) == 100 and int(ea["hit"]) == 125 and before["res"] == [1, 2, 5, -3, 7, 0, 0, 0]
		and ea["res"] == [26, 27, 30, 22, 32, 25, 25, 0] and ea["mas"] == [0, 0, 5, 9, 7, 0, 0, 0])
	buffs.forget(elf)
	world.players.erase(32)
	buffs.apply(p, "s9", 1241, [0.01, 0.01], 1800000, 100, p) # Segen der Steinmenschen
	_advance(100)
	var att = {"level": 10, "hit": 100000, "crit": 0, "dmg": [1000, 1000]}
	var plain = Combat.damage(att, {"level": 10, "def": 0})
	var guarded = Combat.damage(att, Buffs.with_mods({"level": 10, "def": 0}, p))
	_check("Segen der Steinmenschen (1241): Schaden absorbieren %.2f, 1000 -> %d (ohne %d)" % [float(p["buff_mod"].get("absorb", 0)),
		int(guarded["dmg"]), int(plain["dmg"])], int(plain["dmg"]) == 1000 and int(guarded["dmg"]) == 990)
	logs.clear()
	buffs.apply(p, "s9", 2880, [0.01, 0.12, 0.18, 0.18], 1800000, 100, p) # Segen der Werwölfe
	_advance(100)
	_check("Segen der Werwölfe (2880): Tempo +%.2f, Krit +%.1f, Reittier-/Flugtempo ohne Meldung (%s)" % [float(p.get("speed_add", 0)),
		float(p["buff_mod"].get("crit", 0)), str(logs)], absf(float(p.get("speed_add", 0)) - 0.12) < 0.001
		and absf(float(p["buff_mod"].get("crit", 0)) - 1.0) < 0.001 and not logs.any(func(t): return str(t).contains("noch nicht")))
	buffs.forget(p)
	world.players.erase(31)
	buffs.log_line = func(_t): pass

# Grundwerte (Z6) mit den echten Klassen-Daten (Plugin Server/class_templates.json, player_template::BuildBaseProp):
# Meisterschaft / Widerstand = Grundwert + Zuwachs * Stufe (abgeschnitten) + mas_res_modify; Krieger Stufe 1: physisch 8.3 + 0.3
# = 8, Wind 7.5 + 0.3 = 7; Widerstände 7.6 / 3.2 / 2.3 / 1.5 / 6.3 + 0.1 - 0.3; Treffer / Ausweichen ab Stufe 4 +1 (hit_jouk_modify),
# Angriff / Verteidigung ab Stufe 21 (dmg_def_modify)
func _base_values() -> void:
	var st = Stats.new()
	if not st.loaded():
		_check("class_templates.json geladen", false)
		return
	var a1: Dictionary = st.attributes(1, 1, {})
	var a3: Dictionary = st.attributes(1, 3, {})
	var a4: Dictionary = st.attributes(1, 4, {})
	_check("Krieger Stufe 1: Meisterschaft %s, Widerstand %s" % [str(a1["mas"]), str(a1["res"])], a1["mas"] == [8, 0, 0, 0, 7, 0, 0, 0]
		and a1["res"] == [7, 3, 2, 1, 6, 0, 0, 0])
	_check("Stufen-Zuschlag Treffer / Ausweichen: Stufe 3 -> 4 Treffer %d -> %d, Ausweichen %d -> %d (hit_jouk_modify %s)" % [
		int(a3["hit"]), int(a4["hit"]), int(a3["eva"]), int(a4["eva"]), str(st.hit_jouk_modify.slice(0, 4))],
		st.hit_jouk_modify.slice(0, 4).map(func(x): return int(x)) == [0, 0, 0, 1] and int(a4["hit"]) - int(a3["hit"]) == _class_step(st, "attack", 3) + 1
		and int(a4["eva"]) - int(a3["eva"]) == _class_step(st, "armor", 3) + 1)
	var a20: Dictionary = st.attributes(1, 20, {})
	var a21: Dictionary = st.attributes(1, 21, {})
	_check("Stufen-Zuschlag Angriff / Verteidigung ab Stufe 21 (dmg_def_modify[20] = %d): Verteidigung %d -> %d" % [int(st.dmg_def_modify[20]),
		int(a20["def"]), int(a21["def"])], int(st.dmg_def_modify[19]) == 0 and int(st.dmg_def_modify[20]) == 1 and int(a21["def"]) > int(a20["def"]))

# Zuwachs des abgeschnittenen Krieger-Grundwerts key von Stufe lv auf lv + 1 (ohne Stufen-Zuschlag)
static func _class_step(st, key: String, lv: int) -> int:
	var c: Dictionary = st.classes["1"]
	var at = func(l: int) -> int: return int(float(c[key]) + float(c["lvlup_" + key]) * (l - int(c["require_level"])) + 1e-5)
	return at.call(lv + 1) - at.call(lv)

# Passive Fertigkeiten und Schalter (F7)
func _passive_switch() -> void:
	var p = {"id": 21, "name": "Krieger", "map": "s9", "pos": Vector3.ZERO, "hp": 1000, "max_hp": 1000, "mp": 100, "max_mp": 100,
		"level": 10, "class": 1, "race": 1}
	world.players[21] = p
	var ok = buffs.apply(p, "s9", 1183, [0.03], 0, 100, p, false, {"passive": 131})
	var hp1 = int(p["max_hp"])
	buffs.on_death(p)
	var after_death = buffs.list_of(p).size()
	buffs._dispel(p, {}, func(_x): return true, false)
	var after_dispel = buffs.list_of(p).size()
	var n = buffs.remove_passive(p, 131)
	_check("passiv 131 (1183 Leben +3 %%): %d -> %d HP, Rest %s, bleibt nach Tod (%d) und Bannen (%d), remove_passive %d -> %d HP" % [1000,
		hp1, "ohne Ende", after_death, after_dispel, n, int(p["max_hp"])],
		ok and hp1 == 1030 and after_death == 1 and after_dispel == 1 and n == 1 and int(p["max_hp"]) == 1000)
	var n0 = net.pushed.size()
	buffs.apply(p, "s9", 1166, [], 3000, 100, p, false, {"switch": 2093})
	var on = _pushes("skill_switch", n0)
	_advance(3100)
	var all = _pushes("skill_switch", n0)
	_check("Schalter 2093 (1166, 3 s): an %s, nach dem Ablauf aus %s" % [str(on), str(all.slice(1))],
		on.size() == 1 and int(on[0]["id"]) == 2093 and on[0]["on"] and all.size() == 2 and not all[1]["on"]
		and not buffs.is_switched(p, 2093))
	n0 = net.pushed.size()
	buffs.apply(p, "s9", 88, [], 0, 100, p, false, {"switch": 2093})
	buffs.apply(p, "s9", 1166, [], 3000, 100, p, false, {"switch": 2093})
	var lst = buffs.list_of(p).map(func(x): return int(x[0]))
	buffs.switch_off(p, 2093)
	all = _pushes("skill_switch", n0)
	_check("Schalter 2093 mit zwei Effekten %s: einmal an, switch_off -> aus und beide weg (%s)" % [str(lst), str(buffs.list_of(p))],
		lst == [88, 1166] and all.size() == 2 and all[0]["on"] and not all[1]["on"] and buffs.list_of(p).is_empty())
	world.players.erase(21)
