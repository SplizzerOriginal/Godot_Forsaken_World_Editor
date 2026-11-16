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
# Ende: "GEGENSTAENDE-TEST OK" (Exit 0) oder "GEGENSTAENDE-TEST FEHLER" (Exit 1).
# ====================================================

const Quests = preload("../server/quests.gd")
const Inventory = preload("../server/inventory.gd")
const Stats = preload("../server/stats.gd")
const Proto = preload("../common/protocol.gd")
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
var checks = 0
var failures = 0


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
	if inv != null:
		inv.quests = null
	print("GEGENSTAENDE-TEST %s (%d Prüfungen)" % ["OK" if failures == 0 else "FEHLER", checks])
	quit(0 if failures == 0 else 1)
