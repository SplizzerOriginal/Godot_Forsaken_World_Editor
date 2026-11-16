extends SceneTree

# ====================================================
# Test der Quest-Regeln (server/quests.gd, Zwischen-Fahrplan Z1) ohne Server, mit den echten Quest-Daten
# (Plugin Server/quest_templates.json) und Attrappen für Datenbank, Netz, Tasche und Fertigkeiten:
#   godot --headless --path <Projekt> -s res://game/tests/quest_test.gd
# Prüft:
#   Rassen-Segen       versteckte Automatik-Quests, die nur eine Fertigkeit geben (grant_list 8702 - 8706, 15800 - 15802):
#                      jede Rasse bekommt ab Stufe 10 (Server-tasks.data) beim ersten auto_deliver genau ihren Segen (Stufe 1),
#                      auf Stufe 1 noch nicht; die Quest ist erfüllt und läuft nicht; ein zweites auto_deliver vergibt nichts mehr
#   Werwolf-Kette      15358 "Segen des Wolfs" händigt 44134 aus (given); 15396 "Lauscht dem Ruf" ist nur mit laufender
#                      Mit-Quest 15358 annehmbar (cotask); ihr Warte-Teil 15791 "Werwolfanbetung" endet erst mit den Effekten
#                      2885 / 2886 (fin_buffs; im Spiel aus 4571 / 4572, hier gesetzt), die Folgequest 15766 ist mit dem
#                      ausgehändigten Gegenstand sofort erfüllt; 15358 zählt das Erfüllen von 15396 (Methode 11, n 1/1) und
#                      lässt sich am NPC 43384 abschließen: Mondnebel 4582, danach versteckt die Verwandlung nach Geschlecht
#                      (männlich 4215, nicht 4216)
#   Kindred-Kette      6967 "Erste Begegnung" kommt erst mit laufender 6921 UND Effekt 914 (buffs, Auslöser buffs.gd on_gain);
#                      Abschluss am NPC 17894 nur mit dem Effekt (fin_buffs), dann Vampirischer Kuss 1960 statt 1889 und
#                      6921 (Methode 11 auf 6967) ist abschließbar
#   buffs_ok           muss haben / darf nicht haben, alle / einer, Mindest-Stufe (Stapel)
#   Seelenmünzen (Z4)  5681 "Ein schlimmer Dienst" (bind 9, money_lev 3) gibt 9 * Faktor der Stufe (Attrappe 0.5 / 2 / 3),
#                      ab Stufe 3 nicht mehr; mit den echten Faktoren (class_templates.json): Stufe 3 -> 2 Kupfer, 5695
#                      (17, bis Stufe 8) auf Stufe 8 -> 72; höchstens MONEY_MAX
#   Z5                 Quest-EXP mit Stufenfaktor (5678: 40 * 3 auf Stufe 1, * 6 auf Stufe 3); Essenz-Geschenke je Stufe
#                      (grant_list, Vorquest 13008 gilt als erfüllt; Stufe 3 -> 12692 = 1 Essenz, Stufe 4 -> 12693, kein
#                      zweites Mal); Tausch 12784 (Fenster-Quest ohne NPC): ohne Essenz nicht annehmbar, mit Essenz
#                      angenommen, Essenz eingezogen, Orangener Cocktail 9056 in der Tasche, nach 5 am Tag QUEST_LIMIT;
#                      12785 erst ab Stufe 20; Würfel-Quest 4218 gibt 40 * 3 EXP, 4219 erst ab Stufe 20; eine NPC-Quest
#                      ohne NPC -> QUEST_NOT_HERE
# Ende: "QUEST-TEST OK" (Exit 0) oder "QUEST-TEST FEHLER" (Exit 1).
# ====================================================

const Quests = preload("../server/quests.gd")
const Stats = preload("../server/stats.gd")
const Proto = preload("../common/protocol.gd")
const BLESS_LEVEL = 10 # Mindeststufe der Rassen-Segen (Server-tasks.data, Z5)
const BLESSINGS = {1: [8702, 2497], 2: [8703, 2498], 3: [8705, 2500], 4: [8706, 2501], 5: [8704, 2499], 6: [15802, 4214]}

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

class FakeStats:
	var task_money_factor = []
	var task_bind_money_factor = [0.5, 2.0, 3.0] # Stufe 1 - 3
	var task_factor = [3.0, 5.0, 6.0] # Quest-EXP, Stufe 1 - 3 (wie die echten Werte)
	func exp_next(_level) -> int:
		return 100000000

class FakeInventory:
	var bags = {} # Figur -> {Gegenstand: Anzahl}
	var quests = null
	func count_of(p, id) -> int:
		return int(bags.get(p["id"], {}).get(int(id), 0))
	func can_add(_p, _list) -> bool:
		return true
	func add(p, id, count) -> Array:
		var b: Dictionary = bags.get(p["id"], {})
		b[int(id)] = int(b.get(int(id), 0)) + int(count)
		bags[p["id"]] = b
		return [[0, count]]
	func remove(p, id, count) -> int:
		var b: Dictionary = bags.get(p["id"], {})
		var n = mini(int(b.get(int(id), 0)), int(count))
		b[int(id)] = int(b.get(int(id), 0)) - n
		return n
	func push(_peer, _p) -> void:
		pass
	func apply_stats(_p) -> void:
		pass

class FakeSkills:
	var learned: Array = [] # [Figur, ID, Stufe]
	var forgotten: Array = [] # [Figur, ID]
	func learn(_peer, p, id, level = 1) -> void:
		p["skills"][int(id)] = int(level)
		learned.append([p["id"], int(id), int(level)])
	func forget(_peer, p, id) -> void:
		p["skills"].erase(int(id))
		forgotten.append([p["id"], int(id)])

var q
var inv: FakeInventory
var sk: FakeSkills
var checks = 0
var failures = 0
var _next_id = 1


func _initialize() -> void:
	q = Quests.new(FakeDb.new(), FakeNet.new(), func(_s): pass, FakeStats.new())
	inv = FakeInventory.new()
	sk = FakeSkills.new()
	q.inventory = inv
	q.skills = sk
	var err = q.load_templates()
	_check("Quest-Daten geladen %s" % err, err == "")
	if err != "":
		_end()
		return
	_blessings()
	_werewolf()
	_kindred()
	_buff_rules()
	_soul_coins()
	_z5()
	_end()

func _player(race: int, gender: int = 0) -> Dictionary:
	_next_id += 1
	return {"id": _next_id, "name": "Probe%d" % _next_id, "race": race, "gender": gender, "class": 1, "level": 1, "exp": 0,
		"hp": 100, "max_hp": 100, "mp": 100, "max_mp": 100, "money": 0, "pos": Vector3.ZERO, "skills": {}, "buffs": [],
		"quests": {"active": {}, "done": {}}}

func _learned(p: Dictionary) -> Array:
	return sk.learned.filter(func(e): return e[0] == p["id"]).map(func(e): return e[1])

# Rassen-Segen ab Stufe 1 (versteckte Automatik-Quests)
func _blessings() -> void:
	var grants = q.grant_list.filter(func(id): return Quests._skill_only(q.task(id).get("award", {})))
	grants.sort()
	_check("versteckt vergebene Fertigkeiten-Quests: %s" % str(grants), grants == [8702, 8703, 8704, 8705, 8706, 15800, 15801, 15802])
	for race in BLESSINGS:
		var p = _player(race)
		q.auto_deliver(1, p)
		var early = _learned(p)
		p["level"] = BLESS_LEVEL
		q.auto_deliver(1, p)
		var quest = int(BLESSINGS[race][0])
		var skill = int(BLESSINGS[race][1])
		var got = _learned(p)
		var done: Dictionary = p["quests"]["done"].get(quest, {})
		q.auto_deliver(1, p)
		_check("Rasse %d: Stufe 1 ohne Segen (%s); Stufe %d: Segen %d (Stufe %s) aus Quest %d, erfüllt und nicht laufend; zweites auto_deliver gibt nichts (gelernt %s)" % [
			race, str(early), BLESS_LEVEL, skill, str(p["skills"].get(skill, "-")), quest, str(got)],
			early.is_empty() and got == [skill] and int(p["skills"].get(skill, 0)) == 1 and done.get("ok", false)
			and not p["quests"]["active"].has(quest) and _learned(p) == [skill])

# Werwolf: Mit-Quest, ausgehändigter Gegenstand, Methode 11, Verwandlung nach Geschlecht
func _werewolf() -> void:
	var p = _player(6, 0)
	p["level"] = BLESS_LEVEL
	q.auto_deliver(1, p) # Segen
	p["quests"]["done"][15357] = {"ok": true, "times": 1, "t": 0}
	var other = _player(6, 0)
	other["quests"]["done"][15357] = {"ok": true, "times": 1, "t": 0}
	_check("15396 ohne laufende Mit-Quest 15358 nicht annehmbar", q.can_deliver(other, 15396) == Proto.Code.QUEST_CONDITIONS)
	_check("15358 annehmbar nach 15357", q.can_deliver(p, 15358) == Proto.Code.OK)
	q.deliver(1, p, 15358)
	_check("15358 händigt 44134 aus (Tasche %d)" % inv.count_of(p, 44134), inv.count_of(p, 44134) == 1)
	_check("15358 noch nicht erfüllt (n 0/1)", not q._goal_reached(p, 15358))
	_check("15396 mit laufender Mit-Quest 15358 annehmbar", q.can_deliver(p, 15396) == Proto.Code.OK)
	q.deliver(1, p, 15396)
	for i in 3:
		q.tick(1, p) # Warte-Teil 15790, dann 15791 (1 s)
	_wait_over(p, 15791)
	q.tick(1, p)
	_check("15791 'Werwolfanbetung' wartet ohne die Effekte 2885 / 2886 (fin_buffs)", p["quests"]["active"].has(15791)
		and not p["quests"]["done"].has(15396))
	p["buffs"] = [{"id": 2885, "stack": 1}, {"id": 2886, "stack": 1}] # später: Blut des Werwolfgottes (4572), Grab (4571)
	q.tick(1, p)
	var n = int(p["quests"]["active"].get(15358, {}).get("p", {}).get("n", 0))
	_check("mit beiden Effekten: 15396 erfüllt, Folgequest 15766 mit 44134 sofort erfüllt, 15358 zählt mit (n %d)" % n,
		p["quests"]["done"].get(15396, {}).get("ok", false) and p["quests"]["done"].get(15766, {}).get("ok", false) and n == 1)
	var npc = {"tid": 43384, "pos": p["pos"]}
	var r = q.complete(1, p, npc, 15358)
	var got = _learned(p)
	_check("15358 am NPC 43384 abgeschlossen (%s): Mondnebel 4582, Verwandlung männlich 4215, nicht 4216 (gelernt %s)" % [
		Proto.text(r[0]), str(got)], r[0] == Proto.Code.OK and got.has(4582) and got.has(4215) and not got.has(4216)
		and p["quests"]["done"].get(15800, {}).get("ok", false))

# Warten (Methode 5) sofort vorbei
func _wait_over(p: Dictionary, id: int) -> void:
	if p["quests"]["active"].has(id):
		p["quests"]["active"][id]["p"]["until"] = 0

# Kindred: Effekt-Bedingung (Vergabe und Abschluss) und Methode 11
func _kindred() -> void:
	var p = _player(5, 1)
	p["level"] = BLESS_LEVEL
	q.auto_deliver(1, p)
	p["skills"][1889] = 1 # aus 6954 "Verwirrung"
	p["quests"]["done"][6920] = {"ok": true, "times": 1, "t": 0}
	q.deliver(1, p, 6921)
	_check("6967 ohne Effekt 914 nicht vergeben", not p["quests"]["active"].has(6967))
	p["buffs"].append({"id": 914, "stack": 1})
	q.auto_deliver(1, p) # wie buffs.gd on_gain
	_check("6967 mit laufender 6921 und Effekt 914 vergeben", p["quests"]["active"].has(6967))
	var npc = {"tid": 17894, "pos": p["pos"]}
	p["buffs"] = []
	var r0 = q.complete(1, p, npc, 6967)
	_check("6967 ohne den Effekt nicht abschließbar (%s)" % Proto.text(r0[0]), r0[0] == Proto.Code.QUEST_NOT_DONE)
	p["buffs"].append({"id": 914, "stack": 1})
	var r1 = q.complete(1, p, npc, 6967)
	var forgot = sk.forgotten.filter(func(e): return e[0] == p["id"]).map(func(e): return e[1])
	_check("6967 abgeschlossen (%s): Vampirischer Kuss 1960 gelernt, 1889 vergessen (%s / %s)" % [Proto.text(r1[0]), str(_learned(p)), str(forgot)],
		r1[0] == Proto.Code.OK and p["skills"].has(1960) and forgot == [1889] and not p["skills"].has(1889))
	var r2 = q.complete(1, p, npc, 6921)
	_check("6921 (Methode 11 auf 6967) abgeschlossen (%s)" % Proto.text(r2[0]), r2[0] == Proto.Code.OK and p["quests"]["done"].get(6921, {}).get("ok", false))

func _buff_rules() -> void:
	var p = _player(1)
	p["buffs"] = [{"id": 10, "stack": 2}]
	_check("muss haben: da", Quests.buffs_ok(p, [[10, 0, true]], true))
	_check("darf nicht haben: da -> nein", not Quests.buffs_ok(p, [[10, 0, false]], true))
	_check("Mindest-Stufe 3 bei Stapel 2 -> nein", not Quests.buffs_ok(p, [[10, 3, true]], true))
	_check("alle: einer fehlt -> nein", not Quests.buffs_ok(p, [[10, 0, true], [11, 0, true]], true))
	_check("einer: einer da -> ja", Quests.buffs_ok(p, [[10, 0, true], [11, 0, true]], false))
	_check("darf nicht haben: fehlt -> ja", Quests.buffs_ok(p, [[11, 0, false]], true))

# Seelenmünzen einer Quest-Belohnung mit Stufenfaktor (Z4)
func _soul_coins() -> void:
	var t = q.task(5681)
	_check("5681: bind 9, money_lev 3 (%s)" % str(t.get("award", {})), int(t.get("award", {}).get("bind", 0)) == 9
		and int(t["award"].get("money_lev", 0)) == 3)
	var got = []
	for level in [1, 3, 5]:
		var p = _player(1)
		p["level"] = level
		var out = q._award(1, p, t)
		got.append([int(out.get("bind", 0)), int(p.get("bind_money", 0)), int(p.get("money", 0))])
	_check("5681 auf Stufe 1 / 3 / 5: Seelenmünzen %s (erwartet 4, 27, 27; Gold bleibt 0)" % str(got),
		got == [[4, 4, 0], [27, 27, 0], [27, 27, 0]])
	var real = Stats.new()
	var a = Stats.task_money(9, 3, 3, real.task_bind_money_factor)
	var b = Stats.task_money(17, 8, 8, real.task_bind_money_factor)
	var c = Stats.task_money(4, 1, 1, real.task_bind_money_factor)
	_check("echte Faktoren: 9 auf Stufe 3 -> %d (2), 17 auf Stufe 8 -> %d (72), 4 auf Stufe 1 -> %d (0)" % [a, b, c],
		a == 2 and b == 72 and c == 0)
	var rich = _player(1)
	rich["bind_money"] = Quests.MONEY_MAX - 5
	var add = Quests.add_money(rich, "bind_money", 100)
	_check("Obergrenze: +100 bei MONEY_MAX - 5 -> +%d" % add, add == 5 and int(rich["bind_money"]) == Quests.MONEY_MAX)

# Z5: Quest-EXP mit Faktor, Essenz-Geschenke, Tausch-Quests, Würfel-Quests
func _z5() -> void:
	var p = _player(1)
	var out1 = q._award(1, p, q.task(5678))
	p["level"] = 3
	var out3 = q._award(1, p, q.task(5678))
	_check("5678 EXP mit Stufenfaktor: Stufe 1 -> %d (120), Stufe 3 -> %d (240)" % [int(out1.get("exp", 0)), int(out3.get("exp", 0))],
		int(out1.get("exp", 0)) == 120 and int(out3.get("exp", 0)) == 240)
	var gifts = q.grant_list.filter(func(id): return id >= 12690 and id <= 12759)
	_check("Essenz-Geschenke in der Vergabeliste: %d (12692 - 12759 ohne Lücken: %s)" % [gifts.size(), str(gifts.has(12692) and gifts.has(12759))],
		gifts.size() >= 68 and gifts.has(12699))
	var g = _player(2)
	var ess = func(pl): return inv.count_of(pl, 36667)
	q.auto_deliver(1, g)
	var at1 = ess.call(g)
	g["level"] = 3
	q.auto_deliver(1, g)
	var at3 = ess.call(g)
	g["level"] = 4
	q.auto_deliver(1, g)
	q.auto_deliver(1, g)
	var at4 = ess.call(g)
	_check("Essenzen: Stufe 1 %d, Stufe 3 %d (12692), Stufe 4 %d (12693, nur einmal)" % [at1, at3, at4], at1 == 0 and at3 == 1 and at4 == 2
		and g["quests"]["done"].has(12692) and g["quests"]["done"].has(12693))
	# Tausch: Fenster-Quest 12784 (1 Essenz -> Orangener EXP-Cocktail 9056), 5 am Tag
	var x = _player(3)
	var none = q.accept(1, x, {}, 12784)
	var codes = []
	for i in 6:
		inv.add(x, 36667, 1)
		codes.append(q.accept(1, x, {}, 12784)[0])
	_check("Tausch 12784: ohne Essenz %s; sechsmal mit Essenz %s; Cocktails %d, Essenzen übrig %d" % [Proto.text(none[0]), str(codes),
		inv.count_of(x, 9056), ess.call(x)], none[0] == Proto.Code.QUEST_CONDITIONS
		and codes == [0, 0, 0, 0, 0, Proto.Code.QUEST_LIMIT] and inv.count_of(x, 9056) == 5 and ess.call(x) == 1)
	inv.add(x, 36667, 2)
	var low = q.accept(1, x, {}, 12785)
	x["level"] = 20
	var high = q.accept(1, x, {}, 12785)
	_check("Tausch 12785 (2 Essenzen, Gelber Cocktail): Stufe 1 %s, Stufe 20 %s, Cocktail %d" % [Proto.text(low[0]), Proto.text(high[0]),
		inv.count_of(x, 9057)], low[0] == Proto.Code.QUEST_CONDITIONS and high[0] == Proto.Code.OK and inv.count_of(x, 9057) == 1)
	var d = _player(4)
	var before = int(d["exp"])
	var c1 = q.dice(1, d, 4218)
	var c2 = q.dice(1, d, 4219)
	_check("Würfel 4218: %s, +%d EXP (120); 4219 auf Stufe 1: %s" % [Proto.text(c1), int(d["exp"]) - before, Proto.text(c2)],
		c1 == Proto.Code.OK and int(d["exp"]) - before == 120 and c2 == Proto.Code.QUEST_CONDITIONS)
	var npcq = q.accept(1, _player(1), {}, 5680)
	_check("NPC-Quest 5680 ohne NPC: %s" % Proto.text(npcq[0]), npcq[0] == Proto.Code.QUEST_NOT_HERE)

func _check(what: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("QUEST-TEST: ", "ok      " if ok else "FEHLER  ", what)

func _end() -> void:
	print("QUEST-TEST %s (%d Prüfungen)" % ["OK" if failures == 0 else "FEHLER", checks])
	quit(0 if failures == 0 else 1)
