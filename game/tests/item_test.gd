extends SceneTree

# ====================================================
# Test der Gegenstände auf dem Server (Bug-Fahrplan B1: Benutzen, Zerstören, Sammel-Werkzeuge) ohne Server, mit dem echten
# Inventar (server/inventory.gd) und den echten Quests (server/quests.gd, Plugin-Daten item_templates.json /
# quest_templates.json / class_templates.json); Attrappen für Datenbank, Netz und die Sammelpunkte der Map:
#   godot --headless --path <Projekt> -s res://game/tests/item_test.gd
# Prüft:
#   Fackel-Kette    "Erste Mission" 5694 (Menschen-Startgebiet s9): am NPC 14435 angenommen, händigt sie die Ungezündete
#                   Fackel 15030 aus und startet 5740 "Das Feuer entzünden"; das Lagerfeuer 14554 ohne Fackel ->
#                   GATHER_NEED_TOOL, mit Fackel: nach dem Sammeln Leuchtende Fackel 14556 in der Tasche, 15030 verbraucht;
#                   5740 beim NPC 14435 abschließbar; dann läuft 5741 "Zentaurenkanone anzünden": die Kanone 14553 nimmt
#                   14556 (verbraucht) und gibt 14607 -> 5741 sofort erfüllt, 5853 läuft
#   Zerstören       ganzer Stapel weg (Orangener EXP-Cocktail x3); falsche ID -> ITEM_INVALID; Fackel und Prüfungs-Essenz
#                   (proc 0x400) -> ITEM_NOT_DESTROYABLE, bleiben
#   Benutzen        Quest-Gegenstand -> ITEM_NOT_USABLE; EXP-Cocktail 9056: Benutzungszeit 2 s, danach ein Stück weg
#                   und EXP (40 * Stufenfaktor)
#   Werwolf-Kette   (Bug-Fahrplan B17, dazu die echten Effekte server/buffs.gd und das echte Zaubern server/skill_cast.gd mit
#                   skill_templates.json / state_templates.json) 15358 "Segen des Wolfs" händigt das Blut des Werwolfgottes
#                   44134 aus; das Blut per Rechtsklick (item_use): wirkt 4572 (Zaubern 500 ms, Antwort mit skill / time),
#                   während des Zauberns SKILL_BUSY, danach Effekt 2886, das Blut bleibt (permenent); 15396 "Lauscht dem Ruf"
#                   am Grab erst damit annehmbar (B20, need_buffs: vorher QUEST_CONDITIONS, der Client zeigt ein graues "!");
#                   der Warte-Teil 15790 "Wunsch der Ahnen" belohnt mit der Fertigkeit 4571 (award buff, DeliverBuff) ->
#                   Effekt 2885; mit beiden erfüllt 15791 "Werwolfanbetung" -> 15396 (Belohnung 4573: Effekt 2887),
#                   Folgequest 15766 nimmt das Blut, 15358 zählt 1/1. Vorher (B19) der Hänger: läuft der Blut-Effekt ab,
#                   bevor 2885 kommt, bleibt 15791 hängen (die Buff-Prüfung wiederholt sich nur, wie im Original); Aufgeben
#                   geht nur oben (Teil 15791 -> QUEST_NOT_ACTIVE, 15358 -> QUEST_NO_GIVEUP), 15396 gilt dann als gescheitert,
#                   das Blut bleibt, 15396 ist mit neuem Blut-Effekt wieder annehmbar. Weiter (B20) bis "Segen von Eyrda"
#                   15361: der Samen 43953 (Quest-Würfel, 3 s) gilt nur in s31 in seiner Box (B22: sonst ITEM_NOT_USABLE)
#                   und vergibt 15411 "Segen der Erde (Säen)", 15708 "Ausbreitung des Lebens" (Methode 11, Abschluss sofort)
#                   ist damit erfüllt: Effekt 2888, weiter mit 15415; 15411 belohnt mit 4575 (genMob): ein Setzling 43954
#                   an der Figur, nach 600 s weg, kein Respawn (auch nicht nach dem Tod); ein alter Spielstand mit 15708
#                   bei 1/1 schließt im nächsten Takt ab
#   Aufgeben        (B19) zieht die Gegenstände der Quest ein wie RecursiveClearTask: mitgegebene Quest-Gegenstände (2612
#                   "Ausdruck senden": 8988), mit clear gesammelte Quest-Gegenstände (5353 "Tödliche Herausforderung": 13818);
#                   giveup_clear (3574 "Des Geistes Klage") löscht die Quest ganz, ohne Misserfolg im Verlauf
# Ende: "GEGENSTAENDE-TEST OK" (Exit 0) oder "GEGENSTAENDE-TEST FEHLER" (Exit 1).
# ====================================================

const Quests = preload("../server/quests.gd")
const Inventory = preload("../server/inventory.gd")
const Stats = preload("../server/stats.gd")
const Buffs = preload("../server/buffs.gd")
const SkillCast = preload("../server/skill_cast.gd")
const Npcs = preload("../server/npcs.gd")
const Proto = preload("../common/protocol.gd")
const WOLF_BLESSING = 15358
const WOLF_CALL = 15396
const WOLF_WISH = 15790
const WOLF_WORSHIP = 15791
const WOLF_NEXT = 15766
const WOLF_BLOOD = 44134
const WISH_STATE = 2885
const BLOOD_STATE = 2886
const GOD_STATE = 2887
const EYRDA_1 = 15359 # "Segen von Eyrda" (Edward Olgen, Mondterrasse)
const SEEDS = 15360 # "Die Samen"
const SEED_DROP = 44135
const EYRDA_2 = 15361 # "Segen von Eyrda": gibt den Samen
const SEED = 43953 # Quest-Würfel -> 15411
const SOW = 15411 # "Segen der Erde (Säen)"
const SPREAD = 15708 # "Ausbreitung des Lebens" (Methode 11, fin 15411)
const EYRDA_2_NEXT = 15415 # "Eine zweite Antike Steintafel"
const EARTH_STATE = 2888 # Effekt aus 4574
const SAPLING = 43954 # Setzling: genMob von 4575 (15411 "Segen der Erde (Säen)")
const MISSION = 5694
const FIRE_QUEST = 5740
const CANNON_QUEST = 5741
const NEXT_SUB = 5853
const MISSION_NPC = 14435
const UNLIT = 15030
const LIT = 14556
const CANNON_ITEM = 14607
const CAMPFIRE = 14554
const CANNON = 14553
const ESSENCE = 36667
const COCKTAIL = 9056
const LETTER_QUEST = 2612 # giveup, mitgegebener Quest-Gegenstand
const LETTER = 8988
const DUEL_QUEST = 5353 # giveup, Methode 2 mit clear, gesuchter Quest-Gegenstand (dep)
const DUEL_ITEM = 13818
const GHOST_QUEST = 3574 # giveup_clear

class FakeDb:
	var last_error = ""
	func run(_sql, _args = []) -> bool:
		return true
	func query(_sql, _args = []):
		return []

class FakeNet:
	var pushed: Array = []
	func push(peer, what, data) -> void:
		pushed.append([peer, what, data])

# Sammelpunkte einer Map (npcs.gd): objects, busy / lock / unlock / harvest
class FakeWorld:
	var players = {}
	var npc_maps = {}

# Kampfwerte für die Formeln der Fertigkeiten (skill_cast.gd _ctx) und Rückrufe der Effekte (buffs.gd)
class FakeCombat:
	func player_props(_p) -> Dictionary:
		return {"dmg": [10, 12], "hit": 50, "eva": 10, "def": 10, "crit": 5, "crit_dmg": 150}
	func player_range(_p) -> float:
		return 2.0
	func monster_props(_nm, _o) -> Dictionary:
		return {"size": 1.0}
	func player_killed(_p) -> void:
		pass
	func monster_killed(_src, _map_name, _o) -> void:
		pass
	func stop(_p) -> void:
		pass

class FakeMap:
	var objects = {}
	func busy(_id) -> bool:
		return false
	func lock(_id, _pid) -> void:
		pass
	func unlock(_id, _pid) -> void:
		pass
	func harvest(_id, _now) -> void:
		pass

var q
var inv
var net: FakeNet
var world
var buffs
var casting
var checks = 0
var failures = 0
var clock_ms = [100000] # Uhr der Effekte (Werwolf-Kette: 20 s Ablauf überspringen)


func _initialize() -> void:
	net = FakeNet.new()
	var stats = Stats.new()
	q = Quests.new(FakeDb.new(), net, func(_s): pass, stats)
	inv = Inventory.new(FakeDb.new(), net, func(_s): pass, stats)
	q.inventory = inv
	inv.quests = q
	var err = q.load_templates()
	var ierr = inv.load_templates()
	_check("Daten geladen (Quests '%s', Gegenstände '%s', Klassen %s)" % [err, ierr, stats.loaded()], err == "" and ierr == "" and stats.loaded())
	if err != "" or ierr != "":
		_end()
		return
	_torch_chain()
	_destroy()
	_use()
	_werewolf()
	_abandon_items()
	_end()

func _player() -> Dictionary:
	var p = {"id": 7, "name": "Probe", "race": 1, "gender": 0, "class": 1, "level": 5, "exp": 0, "hp": 100, "max_hp": 100,
		"mp": 100, "max_mp": 100, "money": 0, "bind_money": 0, "pos": Vector3(10, 80, 100), "skills": {}, "buffs": [],
		"npc_seen": {}, "map": "s9"}
	inv.load_player(p)
	q.load_player(p)
	return p

func _count(p: Dictionary, id: int) -> int:
	return inv.count_of(p, id)

# Sammeln bis zum Ende (die Dauer übersprungen)
func _gather(p: Dictionary, nm: FakeMap, obj: int) -> Array:
	var r = inv.gather(1, p, nm, obj)
	if r[0] == Proto.Code.OK:
		p["gather"]["end"] = 0
		inv.tick(1, p, nm)
	return r

func _torch_chain() -> void:
	var p = _player()
	p["quests"]["done"][5870] = {"ok": true, "times": 1, "t": 0} # Vorquest
	var npc = {"tid": MISSION_NPC, "pos": p["pos"]}
	var r = q.accept(1, p, npc, MISSION)
	var active: Dictionary = p["quests"]["active"]
	_check("5694 'Erste Mission' am NPC %d angenommen (%s): Ungezündete Fackel %d, 5740 läuft %s" % [MISSION_NPC, _code(r[0]),
		_count(p, UNLIT), active.has(FIRE_QUEST)], r[0] == Proto.Code.OK and _count(p, UNLIT) == 1 and active.has(FIRE_QUEST) and not active.has(CANNON_QUEST))
	var nm = FakeMap.new()
	nm.objects[1] = {"id": 1, "tid": CAMPFIRE, "mine": true, "pos": p["pos"] + Vector3(1, 0, 0)}
	nm.objects[2] = {"id": 2, "tid": CANNON, "mine": true, "pos": p["pos"] + Vector3(0, 0, 1)}
	p["npc_seen"] = {1: true, 2: true}
	_check("Lagerfeuer %d verlangt die Fackel (tools %s)" % [CAMPFIRE, str(inv.mines[CAMPFIRE].get("tools"))],
		str(inv.mines[CAMPFIRE].get("tools")) == str([[UNLIT, 1, 1.0]]))
	inv.remove(p, UNLIT, 1)
	r = inv.gather(1, p, nm, 1)
	_check("ohne Fackel: %s" % _code(r[0]), r[0] == Proto.Code.GATHER_NEED_TOOL and p["gather"].is_empty())
	inv.add(p, UNLIT, 1)
	r = _gather(p, nm, 1)
	_check("mit Fackel gesammelt (%s): Leuchtende Fackel %d, Ungezündete %d" % [_code(r[0]), _count(p, LIT), _count(p, UNLIT)],
		r[0] == Proto.Code.OK and _count(p, LIT) == 1 and _count(p, UNLIT) == 0)
	r = q.complete(1, p, npc, FIRE_QUEST)
	_check("5740 beim NPC abgeschlossen (%s), 5741 läuft %s" % [_code(r[0]), active.has(CANNON_QUEST)],
		r[0] == Proto.Code.OK and not active.has(FIRE_QUEST) and active.has(CANNON_QUEST))
	r = _gather(p, nm, 2)
	_check("Kanone %d angezündet (%s): Leuchtende Fackel verbraucht (%d), 5741 erfüllt %s, 5853 läuft %s" % [CANNON, _code(r[0]),
		_count(p, LIT), not active.has(CANNON_QUEST), active.has(NEXT_SUB)], r[0] == Proto.Code.OK and _count(p, LIT) == 0
		and not active.has(CANNON_QUEST) and active.has(NEXT_SUB) and active.has(MISSION))

func _destroy() -> void:
	var p = _player()
	inv.add(p, COCKTAIL, 3)
	inv.add(p, LIT, 1)
	inv.add(p, ESSENCE, 2)
	var pos = _pos_of(p, COCKTAIL)
	var r = inv.destroy(1, p, pos, COCKTAIL + 1)
	_check("Zerstören mit falscher ID: %s" % _code(r[0]), r[0] == Proto.Code.ITEM_INVALID and _count(p, COCKTAIL) == 3)
	r = inv.destroy(1, p, pos, COCKTAIL)
	_check("Orangener EXP-Cocktail x3 zerstört (%s), Rest %d" % [_code(r[0]), _count(p, COCKTAIL)], r[0] == Proto.Code.OK and _count(p, COCKTAIL) == 0)
	r = inv.destroy(1, p, _pos_of(p, LIT), LIT)
	var r2 = inv.destroy(1, p, _pos_of(p, ESSENCE), ESSENCE)
	_check("Leuchtende Fackel / Prüfungs-Essenz (proc 0x400): %s / %s, bleiben %d / %d" % [_code(r[0]), _code(r2[0]), _count(p, LIT),
		_count(p, ESSENCE)], r[0] == Proto.Code.ITEM_NOT_DESTROYABLE and r2[0] == Proto.Code.ITEM_NOT_DESTROYABLE and _count(p, LIT) == 1
		and _count(p, ESSENCE) == 2)

func _use() -> void:
	var p = _player()
	inv.add(p, CANNON_ITEM, 1)
	var r = inv.use(1, p, _pos_of(p, CANNON_ITEM))
	_check("Quest-Gegenstand benutzen: %s" % _code(r[0]), r[0] == Proto.Code.ITEM_NOT_USABLE)
	inv.add(p, COCKTAIL, 2)
	var exp0 = int(p["exp"])
	r = inv.use(1, p, _pos_of(p, COCKTAIL))
	var secs = int(r[1].get("time", 0))
	p["use"]["end"] = 0
	inv.tick(1, p, null)
	_check("EXP-Cocktail benutzt (%s, %d s): noch %d, EXP %d -> %d" % [_code(r[0]), secs, _count(p, COCKTAIL), exp0, int(p["exp"])],
		r[0] == Proto.Code.OK and secs == 2 and _count(p, COCKTAIL) == 1 and int(p["exp"]) > exp0)

# Werwolf-Kette (B17) mit echten Effekten und echtem Zaubern
func _werewolf() -> void:
	world = FakeWorld.new()
	var fc = FakeCombat.new()
	buffs = Buffs.new(world, net, func(_s): pass)
	buffs.clock = func(): return clock_ms[0]
	buffs.combat = fc
	casting = SkillCast.new(world, net, func(_s): pass, fc)
	casting.buffs = buffs
	buffs.casting = casting
	buffs.on_gain = q.auto_deliver
	q.casting = casting
	q.buffs = buffs
	inv.casting = casting
	casting.item_used = inv.use_up
	var berr = buffs.load_templates()
	var serr = casting.load_templates()
	_check("Effekte und Fertigkeiten geladen ('%s', '%s'): 4571 / 4572 / 4573 da" % [berr, serr], berr == "" and serr == ""
		and casting.templates.has(4571) and casting.templates.has(4572) and casting.templates.has(4573))
	if berr != "" or serr != "":
		return
	var p = _player()
	p["race"] = 6
	p["class"] = 3
	p["level"] = 3
	p["map"] = "s31"
	p["max_hp"] = 1000
	p["hp"] = 1000
	world.players[1] = p
	p["quests"]["done"][15357] = {"ok": true, "times": 1, "t": 0}
	q.deliver(1, p, WOLF_BLESSING)
	_check("15358 'Segen des Wolfs' händigt das Blut %d aus (%d)" % [WOLF_BLOOD, _count(p, WOLF_BLOOD)], _count(p, WOLF_BLOOD) == 1)
	var blood = _pos_of(p, WOLF_BLOOD)
	var active: Dictionary = p["quests"]["active"]
	# B20: am Grab erst mit dem Blut-Effekt 2886 (need_buffs, Wunsch des Spielers; der Client zeigt bis dahin ein graues "!")
	var no_blood = q.can_deliver(p, WOLF_CALL)
	var c = _cast_blood(p, blood)
	var r: Array = c[0]
	_check("Blut per Rechtsklick (%s): wirkt %s, %d ms; währenddessen erneut -> %s" % [_code(r[0]), str(r[1].get("skill")),
		int(r[1].get("time", 0)), _code(c[1][0])], r[0] == Proto.Code.OK and int(r[1].get("skill", 0)) == 4572
		and int(r[1].get("time", 0)) == 500 and int(r[1].get("id", 0)) == WOLF_BLOOD and c[1][0] == Proto.Code.SKILL_BUSY)
	_check("Zaubern fertig (skill_end ok %s): Effekt %d da, das Blut bleibt (permenent, %d); 15396 am Grab vorher %s, jetzt %s" % [
		str(c[2]), BLOOD_STATE, _count(p, WOLF_BLOOD), _code(no_blood), _code(q.can_deliver(p, WOLF_CALL))], c[2] == true
		and _has_state(p, BLOOD_STATE) and _count(p, WOLF_BLOOD) == 1 and no_blood == Proto.Code.QUEST_CONDITIONS
		and q.can_deliver(p, WOLF_CALL) == Proto.Code.OK)
	# B19: der Blut-Effekt läuft ab, bevor "Wunsch der Ahnen" (2885) kommt -> 15791 hängt (im Original genauso); nur Aufgeben hilft
	q.deliver(1, p, WOLF_CALL)
	clock_ms[0] += 21000
	buffs.tick()
	for i in 3:
		q.tick(1, p)
		_wait_over(p)
	var had_wish = _has_state(p, WISH_STATE)
	clock_ms[0] += 21000
	buffs.tick()
	for i in 3:
		q.tick(1, p)
	_check("Blut-Effekt vorher abgelaufen: Effekt %d erst da (%s), nach 20 s weg; 15791 hängt (%s), 15396 läuft" % [WISH_STATE,
		had_wish, active.has(WOLF_WORSHIP)], had_wish and not _has_state(p, WISH_STATE) and not _has_state(p, BLOOD_STATE)
		and active.has(WOLF_WORSHIP) and active.has(WOLF_CALL) and not p["quests"]["done"].has(WOLF_CALL))
	var sub = q.abandon(1, p, WOLF_WORSHIP)
	var top = q.abandon(1, p, WOLF_BLESSING)
	var gave_up = q.abandon(1, p, WOLF_CALL)
	_check("Aufgeben: Teil 15791 %s, 15358 %s, 15396 %s -> gescheitert, Teile weg, Blut bleibt (%d), 15396 ohne Blut-Effekt %s" % [
		_code(sub[0]), _code(top[0]), _code(gave_up[0]), _count(p, WOLF_BLOOD), _code(q.can_deliver(p, WOLF_CALL))],
		sub[0] == Proto.Code.QUEST_NOT_ACTIVE and top[0] == Proto.Code.QUEST_NO_GIVEUP and gave_up[0] == Proto.Code.OK
		and not active.has(WOLF_CALL) and not active.has(WOLF_WORSHIP) and active.has(WOLF_BLESSING)
		and p["quests"]["done"].get(WOLF_CALL, {}).get("ok", true) == false and _count(p, WOLF_BLOOD) == 1
		and q.can_deliver(p, WOLF_CALL) == Proto.Code.QUEST_CONDITIONS)
	c = _cast_blood(p, blood)
	var again = q.can_deliver(p, WOLF_CALL)
	q.deliver(1, p, WOLF_CALL)
	for i in 3:
		q.tick(1, p) # Warte-Teil 15790 (0 s): Belohnung 4571 -> 2885; mit 2886 erfüllt 15791 gleich
		_wait_over(p)
	var n = int(active.get(WOLF_BLESSING, {}).get("p", {}).get("n", 0))
	_check("Blut erneut (%s), 15396 wieder annehmbar (%s): 15790 + 15791 und 15396 erfüllt (Belohnung 4573: Effekt %d), 15766 nimmt das Blut (%d), 15358 %d/1" % [
		str(c[2]), _code(again), GOD_STATE, _count(p, WOLF_BLOOD), n], c[2] == true and again == Proto.Code.OK
		and p["quests"]["done"].get(WOLF_CALL, {}).get("ok", false) and p["quests"]["done"].get(WOLF_NEXT, {}).get("ok", false)
		and _has_state(p, GOD_STATE) and _count(p, WOLF_BLOOD) == 0 and n == 1)
	_eyrda(p)
	world.players.clear()

# Blut des Werwolfgottes per Rechtsklick bis zum Ende zaubern -> [Antwort, Antwort währenddessen, skill_end ok]
func _cast_blood(p: Dictionary, blood: int) -> Array:
	var from = net.pushed.size()
	var r = inv.use(1, p, blood)
	var busy = inv.use(1, p, blood)
	for i in 5:
		if not p.has("cast"):
			break
		p["cast"]["next"] = 0
		casting.tick()
	var ended = net.pushed.slice(from).filter(func(m): return m[1] == "skill_end" and int(m[2]["id"]) == 4572)
	return [r, busy, ended[-1][2]["ok"] if not ended.is_empty() else null]

# B20: weiter bis "Segen von Eyrda" 15361 - der Samen 43953 (Quest-Würfel) vergibt 15411 "Segen der Erde (Säen)"; die zählt für
# 15708 "Ausbreitung des Lebens" (Methode 11, Abschluss sofort), die jetzt gleich erfüllt ist: Segen 4574 -> Effekt 2888, weiter
# mit 15415. Dazu ein Spielstand von vor B20 (15708 stand bei 1/1): der nächste Takt schließt ab
func _eyrda(p: Dictionary) -> void:
	var active: Dictionary = p["quests"]["active"]
	var done: Dictionary = p["quests"]["done"]
	done[WOLF_BLESSING] = {"ok": true, "times": 1, "t": 0} # 15358 beim NPC abgegeben
	active.erase(WOLF_BLESSING)
	q.deliver(1, p, EYRDA_1)
	for sub in [EYRDA_1 + 491, EYRDA_1 + 492]: # 15850 Silberflügelherzog, 15851 Mondterrasse (NPC ansprechen)
		if active.has(sub):
			q.finish(1, p, sub, true)
	q.deliver(1, p, SEEDS)
	inv.add(p, SEED_DROP, 10)
	active[SEEDS]["p"]["k"] = {"43705": 5}
	q.finish(1, p, SEEDS, true)
	q.deliver(1, p, EYRDA_2)
	var seed = _pos_of(p, SEED)
	# B22: der Samen nur in s31 in der Box um (20 | 200 | 238), halbe Kanten 20 / 200 / 20 (item_taskdice::OnUse)
	var at: Array = inv.item(SEED).get("at", []).map(func(x): return int(x))
	p["pos"] = Vector3(20, 90, 150) # südlich der Box
	var far = inv.use(1, p, seed)
	p["map"] = "s9"
	p["pos"] = Vector3(20, 90, 238)
	var other_map = inv.use(1, p, seed)
	p["map"] = "s31"
	# Monster der Fertigkeit (genMob): eine echte Map s31 ohne Spawns, mit den Vorlagen aus npc_templates.json
	var nm = Npcs.new("s31", JSON.parse_string(FileAccess.get_file_as_string("res://addons/PWE-Manager/Server/npc_templates.json")),
		{"next": 1 << 30})
	world.npc_maps["s31"] = nm
	var r = inv.use(1, p, seed)
	if not p.get("use", {}).is_empty():
		p["use"]["end"] = 0
		inv.tick(1, p, null)
	_check("Samen-Ort %s: südlich der Box %s, auf s9 %s, in der Box %s" % [str(at), _code(far[0]), _code(other_map[0]), _code(r[0])],
		at == [31, 20, 200, 238, 20, 200, 20] and far[0] == Proto.Code.ITEM_NOT_USABLE and other_map[0] == Proto.Code.ITEM_NOT_USABLE
		and r[0] == Proto.Code.OK)
	_check("15359 und 15360 erfüllt, 15361 gibt den Samen (%s), Benutzen (%s, %d s) -> 15411 erfüllt (%s), 15708 erfüllt (%s): Effekt %d, weiter mit 15415 (%s)" % [
		seed >= 0, _code(r[0]), int(r[1].get("time", 0)), done.get(SOW, {}).get("ok", false), not active.has(SPREAD), EARTH_STATE,
		active.has(EYRDA_2_NEXT)], done.get(EYRDA_1, {}).get("ok", false) and done.get(SEEDS, {}).get("ok", false) and seed >= 0
		and r[0] == Proto.Code.OK and int(r[1].get("time", 0)) == 3 and done.get(SOW, {}).get("ok", false) and not active.has(SPREAD)
		and _has_state(p, EARTH_STATE) and active.has(EYRDA_2_NEXT) and _count(p, SEED) == 0)
	# genMob: 15411 belohnt mit 4575 (Effekt 2889 "genMob", Tabelle skillmob: 1 x 43954 für 600 s an der Figur)
	var minis = nm.objects.values().filter(func(o): return int(o["tid"]) == SAPLING)
	var sap: Dictionary = minis[0] if minis.size() == 1 else {}
	var now = Time.get_ticks_msec() / 1000.0
	var life = float(sap.get("life_end", 0.0)) - now
	nm.tick(now + 300.0, 0.1, [])
	var still = nm.objects.has(int(sap.get("id", 0)))
	nm.tick(now + 601.0, 0.1, [])
	_check("Säen erzeugt %d Setzling(e) %d an der Figur (%s), Lebensdauer %.0f s, nach 300 s noch da (%s), nach 600 s weg (%s), kein Respawn" % [
		minis.size(), SAPLING, str(sap.get("pos", "")), life, still, not nm.objects.has(int(sap.get("id", 0)))], minis.size() == 1
		and Vector2(sap["pos"].x - p["pos"].x, sap["pos"].z - p["pos"].z).length() < 0.01 and absf(life - 600.0) < 2.0 and still
		and not nm.objects.has(int(sap["id"])) and nm._respawns.is_empty())
	# getötet: kommt ebenfalls nicht wieder
	var id2 = nm.spawn_minor(SAPLING, p["pos"], 600.0, now)
	nm.kill(id2, now)
	_check("getöteter Setzling (%d) kommt nicht wieder (Respawns %d)" % [id2, nm._respawns.size()], id2 != 0
		and not nm.objects.has(id2) and nm._respawns.is_empty())
	world.npc_maps.erase("s31")
	# Spielstand von vor B20: 15708 läuft mit n = 1
	active.erase(EYRDA_2_NEXT)
	active[SPREAD] = {"p": {"n": 1}, "t": 0}
	p["buffs"] = p["buffs"].filter(func(b): return int(b["id"]) != EARTH_STATE)
	q.tick(1, p)
	_check("alter Spielstand (15708 bei 1/1): der nächste Takt schließt ab (%s), Effekt %d, weiter mit 15415 (%s)" % [
		not active.has(SPREAD), EARTH_STATE, active.has(EYRDA_2_NEXT)], not active.has(SPREAD) and _has_state(p, EARTH_STATE)
		and active.has(EYRDA_2_NEXT))

# Aufgeben (B19): Gegenstände der Quest eingezogen, giveup_clear ohne Spur im Verlauf
func _abandon_items() -> void:
	var p = _player()
	var done: Dictionary = p["quests"]["done"]
	q.deliver(1, p, LETTER_QUEST)
	var had = _count(p, LETTER)
	var r = q.abandon(1, p, LETTER_QUEST)
	_check("2612 aufgegeben (%s): mitgegebener Brief %d -> %d, gescheitert, wieder annehmbar (%s)" % [_code(r[0]), had, _count(p, LETTER),
		_code(q.can_deliver(p, LETTER_QUEST))], r[0] == Proto.Code.OK and had == 1 and _count(p, LETTER) == 0
		and done.get(LETTER_QUEST, {}).get("ok", true) == false and not p["quests"]["active"].has(LETTER_QUEST))
	q.deliver(1, p, DUEL_QUEST)
	inv.add(p, DUEL_ITEM, 2)
	var have = _count(p, DUEL_ITEM)
	r = q.abandon(1, p, DUEL_QUEST)
	_check("5353 aufgegeben (%s): gesammelter Quest-Gegenstand %d -> %d" % [_code(r[0]), have, _count(p, DUEL_ITEM)],
		r[0] == Proto.Code.OK and have == 2 and _count(p, DUEL_ITEM) == 0)
	q.deliver(1, p, GHOST_QUEST)
	var was = p["quests"]["active"].has(GHOST_QUEST)
	var events = net.pushed.size()
	r = q.abandon(1, p, GHOST_QUEST)
	var failed = net.pushed.slice(events).any(func(m): return m[1] == "quest_event" and str(m[2].get("kind", "")) == "failed")
	_check("3574 (giveup_clear) aufgegeben (%s): lief %s, jetzt weder laufend noch im Verlauf, keine Misserfolg-Meldung" % [
		_code(r[0]), was], r[0] == Proto.Code.OK and was and not p["quests"]["active"].has(GHOST_QUEST) and not done.has(GHOST_QUEST)
		and not failed)

func _has_state(p: Dictionary, id: int) -> bool:
	return p.get("buffs", []).any(func(b): return int(b["id"]) == id)

# Warten (Methode 5) der laufenden Quests sofort vorbei
func _wait_over(p: Dictionary) -> void:
	for id in p["quests"]["active"]:
		var e: Dictionary = p["quests"]["active"][id]
		if e["p"].has("until"):
			e["p"]["until"] = 0

func _pos_of(p: Dictionary, id: int) -> int:
	for pos in p["bag"]:
		if int(p["bag"][pos][0]) == id:
			return pos
	return -1

static func _code(c: int) -> String:
	var i = Proto.Code.values().find(c)
	return Proto.Code.keys()[i] if i >= 0 else str(c)

func _check(what: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("GEGENSTAENDE-TEST: ", "ok      " if ok else "FEHLER  ", what)

func _end() -> void:
	if q != null:
		q.inventory = null # Kreis Quests <-> Inventar lösen (sonst Lecks beim Beenden)
		q.casting = null
		q.buffs = null
	if inv != null:
		inv.quests = null
		inv.casting = null
	if casting != null:
		casting.buffs = null
		casting.item_used = Callable()
		casting.world = null
		casting.combat = null
	if buffs != null:
		buffs.casting = null
		buffs.on_gain = Callable()
		buffs.world = null
		buffs.combat = null
		buffs._holders.clear()
	print("GEGENSTAENDE-TEST %s (%d Prüfungen)" % ["OK" if failures == 0 else "FEHLER", checks])
	quit(0 if failures == 0 else 1)
