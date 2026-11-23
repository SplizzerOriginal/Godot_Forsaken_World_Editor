extends SceneTree

# ====================================================
# Test der Spielwelt (client/world_screen.gd) gegen einen laufenden Server; die Startmap s9 muss
# importiert sein (maps_root, Standard res://ECM_Import/maps):
#   godot [--headless | --rendering-driver vulkan | --rendering-method gl_compatibility] --path <Projekt>
#         -s res://game/tests/world_test.gd -- --port=29000 [--shots=<Ordner>]
# Legt ein Konto mit einem Menschen-Krieger an, betritt s9 und prüft: Figur steht auf dem Boden am
# Start, "W" läuft nach vorn, ein zweiter Spieler (eigene Sitzung im selben Prozess) erscheint mit
# Namen und läuft sichtbar mit, der zweite sieht die eigene Figur an ihrer Position, Esc öffnet das
# Systemmenü, "Wechseln" führt zur Figurenauswahl, erneutes "Start" setzt die Figur an die gelaufene
# Stelle.
# Fertigkeiten: das Fenster "Neue Fertigkeiten" zeigt Hieb und Überfall (Tooltip), Ziehen in die Leiste unten, K
# zeigt sie (Tooltip mit Beschreibung), Ziehen in die Leiste rechts, Verschieben, Herausziehen leert,
# Schließen legt den Rest weg, Esc; nach dem Wiedereintritt liegt Hieb noch in der Leiste.
# HUD (Schritt 8): eigener Kopf mit 1500/1500 HP und 500/500 MP, Name der Map auf der Minimap, Tab
# wählt ein Monster (Ziel-Fenster, Ring), Klick auf Lady Vestry wählt sie, F1 die eigene Figur, Esc
# wählt ab; Chat: Enter öffnet die Eingabe, "W" läuft dabei nicht, Enter sendet, beide Seiten sehen
# die Nachricht; Systemmenü: "Fenster wechseln" baut das HUD im anderen Skin und zurück.
# Quests (Schritt 10): Verfolgung zeigt "Zerrüttete Zuflucht" mit "Sprecht mit Lady Vestry", Symbol
# über Lady Vestry, zweiter Klick öffnet ihr Fenster, Gespräch bis "abschließen" durchklicken,
# Belohnung (120 EXP = 40 * Stufenfaktor, Rüstung; Stufe 2) im Chat und im EXP-Balken, Folgequest "Greift zu den Waffen!" bei Lady
# Vestry annehmen.
# Autoroute: Klick auf den Quest-Titel der Verfolgung öffnet Win_QuestMinionDes mit Beschreibung und
# NPC-Link, "-" klappt ein, der grüne Link "Adam" führt die Figur über die Wegfindung um die Plattform
# zu Adam, dort geht sein Fenster auf, der Link "Lady Vestry" zurück; NPC in einem anderen Gebiet (laut Server,
# quest_where "npc") -> Meldung, ein NPC, den nur die neuere task_npc.data des Clients woanders hat -> Autoroute (B19);
# Klick auf die Minimap startet eine Autoroute (Ziel-Marke), W bricht sie ab.
# Quest-Popups (B19): Rechtsklick auf eine Quest im Quest-Fenster (Win_QuestOption) bzw. in der Verfolgung
# (Win_QuestMinionOption) an der Maus, Aufgeben fragt erst (gameui.stf 236), "Ansehen" wählt die Quest im Quest-Fenster,
# ein Klick daneben schließt; 5679 (ohne giveup) lehnt der Server ab.
# Shylias Markt (Z5): Geschenk-Knopf, Reiter, Tausch gegen Essenz, Cocktail per Rechtsklick trinken (Leiste, EXP im Chat).
# Gegenstände (Bug-Fahrplan B1): Tooltips wie das Original (LuaItemDesc: Rüstung mit Werten, Essenz mit Preis-Symbol und
# Zusatztext), Zerstören über Btn_Destroy + Klick (Meldungsfenster, OK -> weg, Chat "%d %s zerstört"), die Essenz ist nicht
# zerstörbar (Hinweis), ein Rechtsklick auf sie bewirkt nichts. Fertigkeits-Gegenstand (B17): das Blut des Werwolfgottes
# (Testbefehl debug_item) zaubert per Rechtsklick (Balken mit seinem Namen), danach liegt Effekt 2886 an, das Blut bleibt;
# die Verfolgung von 15358 "Segen des Wolfs" (Methode 11) verlinkt das Grab des Werwolf-Gottes, das 15396 vergibt; das Grab
# zeigt 15396 ohne den Blut-Effekt mit grauem "!" und mit ihm gelb (B20, als Werwolf geprüft). Quest-Würfel mit Ort (B22):
# die Giftige Bombe außerhalb ihres Orts nennt per Rechtsklick die Richtung, ohne sie zu benutzen; Richtungen an mehreren
# Stellen, Hinweis-Modell in der Nähe, der Samen (s31) auf s9 "nicht auf dieser Karte".
# GFX (B10): im Feuerball zeichnet das Warp-Element zuerst, der Kern zuletzt, der Warp zeigt nur das verschobene Bild;
# der Treffer einer Sofort-Fertigkeit spielt keine gemerkte Aktion einer anderen Fertigkeit ab; das Überfall-GFX bekommt die
# Lage-Geschichte; das Waffenregal glitzert, solange seine Quest läuft, Sammeln spielt die Aktion der Vorlage (am Boden, Art
# 0: nur die Schleife); Stufenaufstieg mit GFX und Klang; die Blitzschläger-Klinge tauscht U / V erst nach dem Bild der Folge,
# der Drachen-Blitz rechnet seinen Ausschlag in Weltmaßen; GFX aus alten Importen baut der Client mit dem aktuellen Code neu
# (künstlich veraltete Modell-Szene, getauschter Karten-Effekt); GFX-Shader der Map aus gemeinsamen Dateien, gleicher Text =
# ein Objekt, Vorwärmen nur mit GL (Performance-Fahrplan P1); Gebäude-Kollision aus der beim Import gespeicherten Datei (P2b).
# Seelenmünzen (Z4): Inventar-Zeile Lab_BindMoney / Txt_BindMoney0..3 sichtbar (Hinweis aus dem XML), Wert aufgeteilt
# wie das Gold; Chatmeldung bei kill mit bind.
# Inventar und Ausrüstung (Schritt 10b): B öffnet das Inventar mit der Rüstung (Symbol, Belegung,
# Tooltip), Rechtsklick legt sie an (anderes Modell), C zeigt sie und Verteidigung 94; über den Link
# "Johnny" zu ihm (Teil 7994), die Verfolgung zeigt "Novizen-Langschwert 0/1 (Waffenregal)", der Link
# führt zum Regal, Klick darauf sammelt (Fortschrittsbalken), das Schwert liegt in der Tasche,
# Ziehen auf den Waffenplatz legt es an (Waffe außerhalb des Kampfes auf dem Rücken der Figur und im Figurenbild, Angriff
# 301-321 auf Stufe 2), Rechtsklick legt ab und wieder an, Johnny schließt 5679 ab (Stufe 3).
# Kampf (Schritt 9): Johnny gibt 5680, die Verfolgung zählt die Beute; zweiter Klick auf ein Wildschwein
# läuft hin und greift an (Angriffs-Aktion, schwebende Zahlen, Leben im Ziel-Fenster), W beendet den
# Angriff, das Wildschwein schlägt zurück, stirbt sichtbar, Chat "6 EXP"; zehn Stück, 5680 bei Lady
# Vestry abschließen; jeder Treffer zeigt beim Einschlag (Angriffspunkt der Aktion) sein Treffer-GFX, erst
# dann die Zahl; ein Magier schießt seinen Energieball (Flug-GFX) und die Wirkung kommt mit dem Einschlag;
# im Kampf hängt das Schwert in der Hand, 6 s danach wieder auf dem Rücken; ein
# Assassine trägt zwei Dolche (Gürtel, im Kampf in beiden Händen, der linke wirbelt im Angriff 1);
# Statuseffekte (F3): Client merkt sich buffs, zeigt Brand-Schaden / Heilung als Zahlen; Anzeige (F4): eigene
# Effekte in Win_Buff (Symbol, Restzeit, Stapel, Reihen), Brennen im Ziel-Fenster, Tooltips, Flammen-GFX am Monster;
# Kontrolle (F5): mit gemeldeten Siegeln (seal) bewegt W die Figur nicht, Taste 2 und ein Angriff werden mit Meldung
# abgewiesen, das Hieb-Symbol ist dunkel; danach wieder frei; Startfertigkeiten (F6): Ansturm (skill_move) lässt die
# Figur gleiten, das Stadtportal (120) zaubert 9,85 s mit Balken und Schleifen-Aktion und bringt sie zum Stadtpunkt;
# Passiv / Schalter (F7, Testbefehl debug_skill): eine passive Fertigkeit erscheint im K-Fenster, kommt auf keine Leiste,
# einsetzen -> Meldung; ein Schalter (2093) bekommt eingeschaltet einen hellen Rahmen, erneut eingesetzt ist er aus;
# K-Fenster (F8): Reiter Grundlagen / Klasse / Rasse / Beruf / Talent / Seele, Klasse mit allen Klassen-Fertigkeiten (noch
# nicht gelernte "ab Lv"), Rasse mit dem Stadtportal, Grundlagen mit Symbolen, Talent / Seele nur Hinweis (Stufe zu
# niedrig); C (Z6): Rdo_Reputation zeigt Win_CharacterDetail an derselben Stelle (Win_Character aus) mit den Grundwerten
# der Klasse (Meisterschaft / Widerstand je Element wie der Server, Platz 07 PvE = 0), Rdo_Title wieder zurück;
# Fertigkeiten (F2): Taste 2 ohne Ziel -> Meldung, Hieb auf ein Wildschwein (hinlaufen, Aktion, Zauberbalken,
# Treffer, Mana, Abklingzeit-Uhr, gleich wieder -> "noch nicht bereit", nach 3 s bereit); Magier-Feuerball
# an einer gebauten Figur (Aktion nachgebaut, Feuer in der Hand, Feuerball fliegt mit elapsed sofort);
# ohne Ausrüstung bei den Giftjagdhunden sterben (Win_Message4), "Wiederbeleben"
# bringt die Figur zum Wiederbelebungspunkt.
# NPCs und Monster: erscheinen mit Modell (importiert oder, wenn nicht, zur Laufzeit gebaut), Lady Vestry
# mit Namen in NPC-Farbe, alle stehen auf dem Boden des Clients, der zweite Spieler kennt sie an
# derselben Stelle, ein umherlaufendes Monster kommt genau am Ziel des Servers an.
# Ende: "WELT-TEST OK" (Exit 0) oder "WELT-TEST FEHLER" (Exit 1), nach 420 s Abbruch (Exit 2).
# ====================================================

const Settings = preload("../common/settings.gd")
const Proto = preload("../common/protocol.gd")
const Net = preload("../common/net.gd")
const Session = preload("../client/session.gd")
const LoginScreen = preload("../client/login_screen.gd")
const NpcData = preload("../client/npc_data.gd")
const VESTRY = 14429
const ADAM = 14432
const JOHNNY = 21041
const RACK = 13533
const SWORD = 15612
const ARMOR = 15613
const BOAR = 14563
const BOAR_LOOT = 14533
const DAGGER = 15436 # Novizen-Assassinenklinge
const STAFF = 15452 # Novizen-Magiestab
const BLOOD = 44134 # Blut des Werwolfgottes (Fertigkeits-Gegenstand, B17)
const BLOOD_STATE = 2886 # sein Effekt (Fertigkeit 4572)
const WOLF_BLESSING = 15358 # "Segen des Wolfs" (Methode 11: 15396 erfüllen)
const WOLF_TOMB = 43385 # Grab des Werwolf-Gottes (vergibt 15396)
const WOLF_CALL = 15396 # "Lauscht dem Ruf" (B20: erst mit dem Blut-Effekt annehmbar)
const BOMB = 14548 # Giftige Bombe: Quest-Würfel mit Ort in s9 (B22)
const SEED = 43953 # Samen: Quest-Würfel mit Ort in s31
const HOUNDS_AT = Vector3(20.0, 82.0, 84.0)
const PASSWORD = "geheim-123"
const LOOK = {"face": 0, "mask": 0, "hair": 1, "skin": 0, "hair_color": 0x902E1E}

var shots = ""
var port = Proto.DEFAULT_PORT
var ls
var checks = 0
var failures = 0
var other_pushes = []
var _corrections = 0
var _sk_cool = false # Hieb: Meldung cooldown gesehen
var _sk_mp = [-1, -1] # Mana vor / nach der Wirkung (stats vor bzw. direkt nach cooldown)


func _initialize() -> void:
	var args = Settings.user_args()
	shots = str(args.get("shots", ""))
	port = int(args.get("port", str(Proto.DEFAULT_PORT)))
	var game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	create_timer(1000.0).timeout.connect(func(): _end(2))
	_run.call_deferred(game)

func _run(game: Node) -> void:
	await _frames(5)
	ls = game.get_node_or_null("Login")
	if ls == null:
		_check("Login im Spielstil", false)
		_end(1)
		return
	# Konto und Figur über die Sitzung des Clients, dann "Start" wie im Spiel
	var acc = "Wt_%05d" % (randi() % 100000)
	await ls.session.register(acc, PASSWORD)
	ls.dlg_login.set_text("DEFAULT_Txt_Account", acc)
	ls.dlg_login.set_text("Txt_PassWord", PASSWORD)
	ls._on_login_command("Btn_Login")
	await _until(func(): return ls.state == LoginScreen.State.SELECT_CHAR and ls.chars.dlg_list.visible)
	var hero = "Wanderer%03d" % (randi() % 1000)
	var r = await ls.session.create_char(hero, 1, 1, 0, LOOK)
	_check("Figur %s angelegt" % hero, r["code"] == Proto.Code.OK)
	await ls.chars.refresh()
	ls.chars.show_list()
	ls.chars._on_enter_command("Btn_EnterWorld")
	await _until(func(): return ls.world != null and ls.world.ready_in_world, 90.0)
	var w = ls.world
	ls.session.net.pushed.connect(func(what, _d): if what == "pos_correct": _corrections += 1)
	_check("Welt s9 geladen (%s)" % ", ".join(w.warnings if w != null else []), w != null and w.ready_in_world and w.map_root != null)
	if w == null or not w.ready_in_world:
		_end(1)
		return
	_check("Map hat Licht (%s)" % ("aus dem Import" if w.light_added == "" else "ergänzt: " + w.light_added),
		w.map_root.get_node_or_null("Sun") is DirectionalLight3D and w.map_root.get_node_or_null("Environment") is WorldEnvironment)
	await _physics(20)
	var p = w.player
	var start = p.global_position
	_check("Figur steht auf dem Boden am Start", p.is_on_floor() and Vector2(start.x + 144.556, start.z - 34.636).length() < 1.5)
	await _shot("1_world")

	# zweiter Spieler
	var other = await _second_player()
	_check_ok("zweiter Spieler in der Welt", other != null)
	if other == null:
		_end(1)
		return
	await _until(func(): return not w.remotes.is_empty(), 5.0)
	_check("zweiter Spieler erscheint mit Namen", w.remotes.size() == 1 and w.remotes.values()[0].label.text.begins_with("Gast"))
	await _npcs(w)
	_gfx_refresh(w)
	_shader_pool(w)
	_check("Gebäude-Kollision vorab beim Map-Import gespeichert und geladen (P2b): %s" % str(w.collision_info),
		str(w.collision_info.get("source", "")).ends_with("(vorab)") and int(w.collision_info.get("hulls", 0)) > 10000 and w._buildings != null)
	await _skills(w) # schließt das Fenster "Neue Fertigkeiten" (es läge sonst über der Welt)
	await _hud(w, other)
	await _quests(w)
	var seen_me = []
	other.net.state_received.connect(func(entries): seen_me.append(entries))

	# "W" 1,5 s halten
	_key(KEY_W, true)
	await create_timer(1.5).timeout
	_key(KEY_W, false)
	await _physics(10)
	await _until(func(): return p.state == Proto.MOVE_STAND, 3.0) # am Hang: erst landen
	var moved = p.global_position
	_check("W läuft (%.1f m)" % Vector2(moved.x - start.x, moved.z - start.z).length(), Vector2(moved.x - start.x, moved.z - start.z).length() > 3.0)
	_check("Lauf-Animation lief, jetzt Stehen", p.state == Proto.MOVE_STAND)
	# zweiter Spieler läuft 2 m zur Seite
	var o_pos: Vector3 = other.get_meta("pos")
	for i in 10:
		o_pos.x += 0.2
		other.send_move(o_pos, 1.5, Proto.MOVE_RUN)
		await create_timer(0.1).timeout
	other.send_move(o_pos, 1.5, Proto.MOVE_STAND)
	await create_timer(0.8).timeout
	var remote = w.remotes.values()[0]
	_check("zweiter Spieler läuft sichtbar mit", remote.position.distance_to(o_pos) < 0.3)
	var me = func():
		for entries in seen_me:
			for e in entries:
				if absf(e[1] - moved.x) < 0.5 and absf(e[3] - moved.z) < 0.5:
					return true
		return false
	_check("der zweite sieht die eigene Figur dort", await _until_ok(me, 3.0))
	await _shot("2_moved")

	# Esc -> Systemmenü -> "Wechseln" -> Figurenauswahl, dann wieder hinein
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _until(func(): return w.hud.menu_open())
	_check("Esc öffnet das Systemmenü", w.hud.menu_open())
	await _shot("5_menu")
	w.hud.dlg("Quit").send("Btn_Return")
	await _until(func(): return ls.state == LoginScreen.State.SELECT_CHAR and ls.chars.dlg_list.visible, 10.0)
	_check("zurück in der Figurenauswahl", ls.state == LoginScreen.State.SELECT_CHAR and ls.world == null)
	ls.chars._on_enter_command("Btn_EnterWorld")
	await _until(func(): return ls.world != null and ls.world.ready_in_world, 90.0)
	await _physics(10)
	var again = ls.world.player.global_position if ls.world != null and ls.world.player != null else Vector3.ZERO
	_check("wieder an der gelaufenen Stelle", Vector2(again.x - moved.x, again.z - moved.z).length() < 0.5)
	var h2 = ls.world.hud if ls.world != null else null
	# "Wetzt Eure Knochen" (5680, schon erledigt) lehrt die Menschen-Fertigkeit 1958 (Quest-Belohnung, F8): nur sie ist neu
	_check("nach dem Wiedereintritt: Hieb auf Platz 2 unten, 'Neue Fertigkeiten' nur mit der Quest-Fertigkeit 1958 (Leiste %s, neu %s)" % [
		str([h2.skill_at("bar0", 0), h2.skill_at("bar0", 1)]) if h2 != null else "-", str(h2.skill_state["new"]) if h2 != null else "-"],
		h2 != null and h2.skill_at("bar0", 1) == 122 and h2.skill_at("bar0", 0) == 0 and h2.skill_state["new"] == [1958]
		and h2.new_skills_shown())
	if h2 != null and h2.new_skills_shown():
		h2.dlg(h2.NEW_SKILLS).send("Btn_Close")
	if ls.world != null and h2 != null:
		await _prayer(ls.world) # erst hier: vorher würde der Testbefehl Gebet vor der Quest-Belohnung lehren
		await _market(ls.world)
	other.close()
	_end(0 if failures == 0 else 1)

# Fertigkeiten: Fenster "Neue Fertigkeiten" mit den Startfertigkeiten, Ziehen in die Leisten, K, Tooltips,
# Verschieben in der Leiste, Herausziehen leert, Schließen legt den Rest weg
func _skills(w) -> void:
	var h = w.hud
	var sd = w.skill_data
	_check("Fertigkeiten-Skripte geladen", sd != null)
	if sd == null:
		return
	await _until(func(): return h.new_skills_shown(), 3.0)
	var pop = h.dlg(h.NEW_SKILLS)
	var icons = [0, 1].map(func(i): return h.skill_control("new", i).get_node("Symbol").texture != null)
	_check("Fenster 'Neue Fertigkeiten' mit Hieb und Überfall (Segen der Menschen erst ab Stufe 10) (Symbole %s, neu %s)" % [str(icons), str(h.skill_state["new"])],
		h.new_skills_shown() and h.skill_state["new"] == [122, 1581] and icons == [true, true])
	h._on_skill_hover("new", 0)
	_check("Tooltip im Fenster: %s" % h.tooltip_text().get_slice("\n", 0).strip_edges(), h.tooltip_text().contains(sd.skill_name(122)))
	await _shot("3_new_skills")
	h._skill_drop(Vector2.ZERO, {"skill": 122, "from": "new", "idx": 0}, "bar0", 0)
	await _until(func(): return h.skill_at("bar0", 0) == 122, 3.0)
	_check("Hieb in die Leiste unten gezogen, im Fenster bleibt Überfall", h.skill_at("bar0", 0) == 122
		and h.skill_control("bar0", 0).get_node("Symbol").texture != null and h.skill_state["new"] == [1581])
	_key(KEY_K, true)
	_key(KEY_K, false)
	await _until(func(): return h.window_open(h.SKILLS), 3.0)
	var d = h.dlg(h.SKILLS)
	var names = [1, 2].map(func(i): return str(d.get_text("Name_%d" % i)))
	_check("K öffnet die Fertigkeiten, Reiter Klasse: %s" % str(names), h.window_open(h.SKILLS) and h.skill_tab == "class"
		and names == [Hud_plain(sd.skill_name(122)), Hud_plain(sd.skill_name(1581))]
		and h.skill_control("skill", 0).get_node("Symbol").texture != null)
	h._on_skill_hover("skill", 0)
	var tip = h.tooltip_text()
	_check("Tooltip mit Beschreibung (%d Zeilen)" % tip.count("\n"), tip.contains(sd.skill_name(122)) and tip.count("\n") >= 4)
	await _shot("3_skills")
	h._skill_drop(Vector2.ZERO, {"skill": 1581, "from": "skill", "idx": 2}, "bar1", 2)
	await _until(func(): return h.skill_at("bar1", 2) == 1581, 3.0)
	_check("Überfall aus K in die Leiste rechts gezogen", h.skill_at("bar1", 2) == 1581)
	h._on_skill_hover("bar1", 2)
	_check("Tooltip in der Leiste", h.tooltip_text().contains(sd.skill_name(1581)))
	h._skill_drop(Vector2.ZERO, {"skill": 122, "from": "bar0", "idx": 0}, "bar0", 1)
	await _until(func(): return h.skill_at("bar0", 1) == 122 and h.skill_at("bar0", 0) == 0, 3.0)
	_check("in der Leiste verschoben (Platz 1 -> 2)", h.skill_at("bar0", 1) == 122 and h.skill_at("bar0", 0) == 0)
	h._drag_shortcut = Vector2i(1, 2) # wie _skill_drag aus der Leiste rechts, Platz 3
	h._notification(Node.NOTIFICATION_DRAG_END) # nirgends abgelegt
	await _until(func(): return h.skill_at("bar1", 2) == 0, 3.0)
	_check("aus der Leiste herausgezogen: Platz leer", h.skill_at("bar1", 2) == 0)
	pop.send("Btn_Close")
	await _until(func(): return not h.new_skills_shown(), 3.0)
	_check("Schließen legt die übrigen neuen weg", not h.new_skills_shown() and h.skill_state["new"].is_empty())
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _until(func(): return not h.window_open(h.SKILLS), 3.0)
	_check("Esc schließt die Fertigkeiten", not h.window_open(h.SKILLS))
	h.hide_tooltip()

# Zweite Sitzung mit eigenem Konto und Figur neben dem Start
func _second_player():
	var branch = Node.new()
	branch.name = "Zweiter"
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var g = Node.new()
	g.name = "Game"
	branch.add_child(g)
	var n = Net.new()
	n.name = "Net"
	g.add_child(n)
	var s = Session.new()
	s.name = "Session"
	s.port = port
	g.add_child(s)
	var acc = "Wg_%05d" % (randi() % 100000)
	await s.register(acc, PASSWORD)
	var r = await s.login(acc, PASSWORD)
	if r["code"] != Proto.Code.OK:
		return null
	s.net.pushed.connect(func(what, data): other_pushes.append([what, data]))
	r = await s.create_char("Gast%04d" % (randi() % 10000), 1, 6, 1, LOOK)
	r = await s.enter_char(r["data"].get("char", {}).get("id", 0))
	if r["code"] != Proto.Code.OK:
		return null
	var pos: Array = r["data"]["pos"]
	r = await s.world_ready()
	if r["code"] != Proto.Code.OK:
		return null
	s.set_meta("pos", Vector3(pos[0], pos[1], pos[2]))
	return s


# NPCs und Monster in der Welt
func _npcs(w) -> void:
	await _until(func(): return w.npcs.size() > 20, 5.0)
	var with_model = w.npcs.values().filter(func(n): return n.anim != null).size()
	_check("NPCs und Monster erscheinen (%d, %d mit Modell; %d Modelle nicht importiert, %d gebaut)" % [w.npcs.size(),
		with_model, w.missing_models.size(), w.built_models],
		w.npcs.size() > 20 and with_model >= w.npcs.size() - 2)
	var vestry = null
	for n in w.npcs.values():
		if n.tid == VESTRY:
			vestry = n
	_check("Lady Vestry mit Namen in NPC-Farbe (%s)" % (vestry.label.text.replace("\n", " ") if vestry != null else "fehlt"),
		vestry != null and vestry.label.text.length() > 2 and not vestry.label.text.is_valid_int()
		and vestry.label.modulate.is_equal_approx(NpcData._argb(NpcData.NPC_COLOR)))
	await _physics(2)
	var off = []
	for n in w.npcs.values():
		if not n.is_moving():
			var g = n._ground(n.position.x, n.position.y, n.position.z)
			if absf(g - n.position.y) > 0.15:
				off.append("%d %.2f" % [n.tid, g - n.position.y])
	_check("stehen auf dem Boden des Clients (%d daneben %s)" % [off.size(), off.slice(0, 4)], off.size() <= 2)
	# der zweite Spieler kennt sie an derselben Stelle (Ziel, wenn sie laufen)
	var known = {}
	for e in other_pushes:
		if e[0] == "npc_enter":
			for x in e[1]["list"]:
				known[x[0]] = Vector2(x[7][0], x[7][2]) if x[7].size() == 4 else Vector2(x[2], x[4])
		elif e[0] == "npc_move" and known.has(e[1]["id"]):
			known[e[1]["id"]] = Vector2(e[1]["to"][0], e[1]["to"][2])
	var same = 0
	var differ = []
	for id in w.npcs:
		if known.has(id):
			var n = w.npcs[id]
			var at: Vector3 = n.target if n.is_moving() else n.position
			if Vector2(at.x, at.z).distance_to(known[id]) < 0.01:
				same += 1
			else:
				differ.append(id)
	_check("zweiter Spieler: %d an derselben Stelle, %d anders" % [same, differ.size()], same > 20 and differ.is_empty())
	await _shot("2_npcs")
	await _until(func(): return w.npcs.values().any(func(n): return n.is_moving()), 12.0)
	# das nächste laufende (weiter außen kann es während des Gangs aus der Sicht laufen)
	var walker = null
	var best = INF
	for n in w.npcs.values():
		var d = n.position.distance_to(w.player.global_position)
		if n.is_moving() and d < best:
			walker = n
			best = d
	var tid = walker.tid if walker != null else 0
	var goal: Vector3 = walker.target if walker != null else Vector3.ZERO
	if walker != null:
		var end = Time.get_ticks_msec() + 20000
		while is_instance_valid(walker) and walker.is_moving() and Time.get_ticks_msec() < end:
			goal = walker.target # bekommt es unterwegs ein neues Ziel (npc_move), zählt das
			await process_frame
		await _frames(2)
	var arrived = walker != null and is_instance_valid(walker) and not walker.is_moving() \
		and Vector2(walker.position.x - goal.x, walker.position.z - goal.z).length() < 0.01
	_check("Monster läuft umher und hält am Ziel des Servers (%s, %.0f m entfernt)" % [str(tid) if tid != 0 else "keins", best], arrived)


# HUD: Werte, Ziel (Tab, Klick, F1, Esc), Chat, Skin-Wechsel
func _hud(w, other) -> void:
	var h = w.hud
	_check("HUD gebaut (Skin %d, %s)" % [h.skin if h != null else 0, ", ".join(h.warnings) if h != null else "fehlt"],
		h != null and h.aui.visible and h.dlg("CharHead") != null and h.dlg("CharHead").visible)
	if h == null:
		return
	var head = h.dlg("CharHead")
	_check("Kopf: Name, Stufe 1, 1500/1500 HP, 500/500 MP (%s, %s, %s, %s)" % [head.get_text("Txt_Name"), head.get_text("Txt_Lv0"),
		head.get_text("Txt_HP"), head.get_text("Txt_MP")], head.get_text("Txt_Name") == w.info["char"]["name"]
		and head.get_text("Txt_Lv0") == "1" and head.get_text("Txt_HP") == "1500/1500" and head.get_text("Txt_MP") == "500/500")
	var title = h.dlg("MiniMap").get_text("Btn_Bar")
	_check("Minimap: %s mit Kartenbild" % title, title == h.map_title and title != "s9" and (title == "Morgenrotland" or ls.language != "Deu")
		and h._radar != null and h._radar.material.get_shader_parameter("has_map"))
	# Tab: Regel aus SelectTargetRule.lua (höchstens R m); am Start steht keins so nah -> nichts gewählt
	var p = w.player.global_position
	var cam_dir = -w.player.camera.global_basis.z
	var expect: Array = w.tab_candidates(p, cam_dir)
	_check("Tab-Regel aus SelectTargetRule.lua (r %s, R %s, Winkel %s)" % [h.tab_rule["r"], h.tab_rule["R"], h.tab_rule["angle"]],
		h.tab_rule["R"] == 20.0 and h.tab_rule["r"] == 5.0)
	_key(KEY_TAB, true)
	_key(KEY_TAB, false)
	await _until(func(): return w.target_id != 0, 2.0)
	_check("Tab am Start: %d Monster in Reichweite, gewählt %d" % [expect.size(), w.target_id],
		(expect.is_empty() and w.target_id == 0) or (not expect.is_empty() and w.target_id == expect[0]) and not h.chat_focused())
	# Kandidaten neben einem Tab-wählbaren Monster: es kommt zuerst, auch hinter der Kamera bis r
	var monster = null
	for n in w.npcs.values():
		var i = w.npc_data.info(n.tid)
		if not i["npc"] and i["tab"]:
			monster = n
	var near: Array = w.tab_candidates(monster.global_position + Vector3(3, 0, 0), Vector3(1, 0, 0)) if monster != null else []
	var far: Array = w.tab_candidates(monster.global_position + Vector3(-15, 0, 0), Vector3(-1, 0, 0)) if monster != null else []
	_check("Tab-Kandidaten: 3 m daneben dabei, 15 m hinter der Kamera nicht", monster != null and monster.id in near
		and not monster.id in far)
	# Monster wie mit Tab auswählen (Server, Fenster, Ring)
	if monster != null:
		w.select_target(monster.id)
	await _until(func(): return w.target_kind == "monster", 3.0)
	_check("Monster als Ziel (%s, Stufe %s)" % [h.dlg("TargetMonster").get_text("Txt_Name"), h.dlg("TargetMonster").get_text("Txt_LV")],
		w.target_kind == "monster" and h.dlg("TargetMonster").visible and h.dlg("TargetMonster").get_text("Txt_LV") == str(monster.level))
	await _frames(2)
	_check("Ring unter dem Ziel", w._ring != null and w._ring.visible and w._ring.global_position.distance_to(w._target_node().global_position) < 0.2)
	await _shot("3_target")
	# Klick auf Lady Vestry (Kamera zu ihr gedreht)
	var vestry = null
	for n in w.npcs.values():
		if n.tid == VESTRY:
			vestry = n
	if vestry != null:
		var d: Vector3 = vestry.global_position - w.player.global_position
		w.player.cam_yaw.rotation.y = atan2(-d.x, -d.z)
		await _frames(3)
		var at = vestry.global_position + Vector3(0, vestry.height * 0.6, 0)
		var screen = w.player.camera.unproject_position(at)
		_click(screen)
		await _until(func(): return w.target_id == vestry.id, 3.0)
	_check("Klick wählt Lady Vestry (NPC-Fenster: %s)" % (h.dlg("TargetNPC").get_text("Txt_Name") if h.dlg("TargetNPC") != null else "-"),
		vestry != null and w.target_id == vestry.id and w.target_kind == "npc" and h.dlg("TargetNPC").visible
		and not h.dlg("TargetMonster").visible)
	_check("Klick auf eine Figur läuft nicht", w.player.target == null)
	_key(KEY_F1, true)
	_key(KEY_F1, false)
	await _until(func(): return w.target_id == w.my_id, 3.0)
	_check("F1 wählt die eigene Figur (%s)" % h.dlg("TargetPlayer").get_text("Txt_Name"), w.target_kind == "player"
		and h.dlg("TargetPlayer").visible and h.dlg("TargetPlayer").get_text("Txt_Name") == w.info["char"]["name"])
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check("Esc wählt ab", w.target_id == 0 and not h.dlg("TargetPlayer").visible and not h.menu_open())
	# Chat
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await _frames(2)
	_check("Enter öffnet die Chat-Eingabe", h.chat_focused())
	var before = w.player.global_position
	_key(KEY_W, true)
	await create_timer(0.5).timeout
	_key(KEY_W, false)
	await _physics(3)
	_check("W läuft beim Tippen nicht", w.player.global_position.distance_to(before) < 0.05)
	h._chat_edit.text = "Hallo aus dem Welt-Test!"
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	var mine = func(): return h.chat_lines.any(func(l): return l.contains("Hallo aus dem Welt-Test!"))
	_check("Enter sendet, eigene Nachricht im Verlauf", await _until_ok(mine, 3.0) and not h.chat_focused())
	var heard = func(): return other_pushes.any(func(e): return e[0] == "chat" and e[1]["text"] == "Hallo aus dem Welt-Test!")
	_check("zweiter Spieler hört sie", await _until_ok(heard, 3.0))
	await other.say("Hallo zurück vom Gast")
	var theirs = func(): return h.chat_lines.any(func(l): return l.contains("Hallo zurück vom Gast") and l.contains("Gast"))
	_check("Nachricht des zweiten im Verlauf", await _until_ok(theirs, 3.0))
	await _shot("4_chat")
	# Skin wechseln und zurück
	var lines = h.chat_lines.size()
	var skin0 = h.skin
	h.open_menu()
	h.dlg("Quit").send("Btn_ChangeUI")
	await _until(func(): return w.hud != h and w.hud.skin != h.skin, 5.0)
	var h1 = w.hud
	_check("Fenster wechseln: Skin %d, Kopf und Verlauf da" % h1.skin, h1.aui.visible and h1.dlg("CharHead").visible
		and h1.dlg("CharHead").get_text("Txt_HP") == "1500/1500" and h1.chat_lines.size() == lines)
	await _shot("4b_skin%d" % h1.skin)
	h1.open_menu()
	h1.dlg("Quit").send("Btn_ChangeUI")
	await _until(func(): return w.hud != h1, 5.0)
	_check("und zurück zu Skin %d" % w.hud.skin, w.hud.skin == skin0 and w.hud.dlg("CharHead").visible)

# Erste Menschen-Quest über die Oberfläche
func _quests(w) -> void:
	var h = w.hud
	var vestry = null
	var adam = null
	for n in w.npcs.values():
		if n.tid == VESTRY:
			vestry = n
		elif n.tid == ADAM:
			adam = n
	var trace: Array = h.trace_items()
	var vname = w.npc_data.info(VESTRY)["name"]
	_check("Verfolgung: %s" % str(trace), not trace.is_empty() and trace[0].size() >= 3 and trace[0][2].contains(vname))
	_check("Symbol über Lady Vestry (abschließbar)", vestry != null and vestry.quest_icon != null and vestry.quest_icon.visible)
	await _shot("6_quest_icon")
	# zweimal wählen = ansprechen
	w.select_target(vestry.id)
	await _until(func(): return w.target_id == vestry.id, 3.0)
	w.select_target(vestry.id)
	await _until(func(): return h.npc_open(), 5.0)
	var entries: Array = h.npc_entries
	_check("Fenster von Lady Vestry mit 'Aufwachen' (%s)" % str(entries.map(func(e): return e["title"])),
		h.npc_open() and entries.any(func(e): return e["id"] == 5699))
	await _shot("7_npc")
	_check("Teil 1 über das Gespräch abgeschlossen", await _talk_through(w, 5699, 5700))
	_check("Verfolgung: weiter mit 'Was ist passiert?' bei Adam (%s)" % str(h.trace_items()),
		h.trace_items()[0].any(func(l): return l.contains(w.npc_data.info(ADAM)["name"])))
	# Verfolgung: Titel öffnet die Beschreibung, "-" klappt ein / aus, NPC als grüner Link
	var qid = int(h.trace_entries[0]["id"])
	var text: String = h._trace_label.text
	_check("Verfolgung: Adam als grüner Link (%s)" % text.replace("\n", " | "), text.contains("[url=npc:%d][color=%s][u]" % [ADAM, h.LINK_COLOR])
		and text.contains("[url=quest:%d]" % qid) and text.contains("[url=fold:%d]-" % qid))
	h._trace_label.meta_clicked.emit("quest:%d" % qid)
	await _frames(2)
	var des = h.dlg("QuestMinionDes")
	_check("Klick auf den Titel öffnet die Beschreibung links daneben (%s)" % (des.get_text("Txt_Content").left(40) if des != null else "-"),
		h.des_open() and des.get_text("Txt_Content").length() > 20 and des.item("Txt_QuestItem").text.contains("npc:%d" % ADAM)
		and des.position.x + des.size.x <= h.dlg("QuestMinion").position.x + 1.0)
	await _shot("7b_quest_des")
	h._trace_label.meta_clicked.emit("quest:%d" % qid)
	await _frames(2)
	_check("zweiter Klick schließt sie", not h.des_open())
	h._trace_label.meta_clicked.emit("fold:%d" % qid)
	await _frames(1)
	var folded: String = h._trace_label.text
	h._trace_label.meta_clicked.emit("fold:%d" % qid)
	await _frames(1)
	_check("'-' klappt die Quest ein, '+' wieder aus", not folded.contains("npc:%d" % ADAM) and folded.contains("[url=fold:%d]+" % qid)
		and h._trace_label.text == text)
	# zu Adam über den Link: zwischen ihm und Lady Vestry steht eine Plattform
	var from = w.player.global_position
	h._trace_label.meta_clicked.emit("npc:%d" % ADAM)
	await _until(func(): return w.player.following(), 3.0)
	var path: PackedVector3Array = w.player.path
	_check("Link startet die Autoroute (%d Wegpunkte, Ziel-Marke auf der Minimap)" % path.size(), w.routing() and path.size() >= 3
		and h.route_target != null)
	var bends = path.size() >= 3 and _off_line(path, from, adam.global_position) > 1.5
	_check("Weg führt um die Plattform herum", bends)
	await _until(func(): return h.npc_open(), 40.0)
	_check("Figur läuft zu Adam, sein Fenster geht auf (%.1f m)" % w.player.global_position.distance_to(adam.global_position),
		h.npc_open() and w.talk_npc == adam.id and not w.routing() and h.route_target == null)
	await _shot("7c_adam")
	_check("Teil 2 bei Adam", await _talk_through(w, 5700, 5701))
	_check("Verfolgung: zurück zu Lady Vestry als Link", h._trace_label.text.contains("[url=npc:%d]" % VESTRY))
	h._trace_label.meta_clicked.emit("npc:%d" % VESTRY)
	await _until(func(): return h.npc_open(), 40.0)
	_check("zurück bei Lady Vestry über den Link", h.npc_open() and w.talk_npc == vestry.id)
	var done = await _talk_through(w, 5701, 0)
	await _until(func(): return h.chat_lines.any(func(l): return l.contains("120 EXP")), 3.0)
	var lines = h.chat_lines.filter(func(l): return l.contains("ffff00"))
	_check("Quest erfüllt: Meldung, 120 EXP (40 * Stufenfaktor 3), Gegenstand im Chat (%d Zeilen)" % lines.size(), done and lines.size() >= 3
		and h.chat_lines.any(func(l): return l.contains("120 EXP")))
	_check("Werte: Stufe 2, 50 / 140 EXP (Balken %.0f %%)" % h.dlg("QuickBar0").item("Pro_Exp").value, w.info.get("exp") == 50
		and int(h.stats.get("level", 1)) == 2 and absf(h.dlg("QuickBar0").item("Pro_Exp").value - 100.0 * 50 / 140) < 1.0)
	await _until(func(): return vestry.quest_icon != null and vestry.quest_icon.visible, 3.0)
	_check("Lady Vestry bietet die Folgequest an (Symbol)", vestry.quest_icon != null and vestry.quest_icon.visible)
	# Folgequest annehmen
	w.select_target(vestry.id)
	await _until(func(): return h.npc_open(), 5.0)
	_check("Folgequest 'Greift zu den Waffen!' im Fenster", h.npc_entries.any(func(e): return e["id"] == 5679))
	_check("Folgequest angenommen", await _talk_through(w, 5679, 7994))
	_check("Verfolgung: 5679 (%s)" % str(h.trace_items()), h.trace_items().any(func(t): return t[0].contains(Hud_plain(w.quest_data.task(5679)["name"]))))
	await _shot("8_quest_done")
	# Quest-Fenster (Q)
	_key(KEY_Q, true)
	_key(KEY_Q, false)
	await _until(func(): return h.quest_open(), 3.0)
	var ql: Array = h.quest_list
	_check("Q öffnet das Quest-Fenster mit 5679, Beschreibung, nicht aufgebbar (%s)" % str(ql.map(func(e): return e["name"])),
		h.quest_open() and ql.any(func(e): return e["id"] == 5679 and str(e["description"]).length() > 20)
		and h.quest_selected != 0 and h.dlg("Quest").item("Btn_Abandon").disabled)
	var qc = h.dlg("Quest").item("Txt_Content")
	var qsub = h.dlg("Quest").item("Sub_QuestContent")
	_check("Q: Beschreibung rollt (Mausrad, Leiste) und endet im Unterdialog (%s, Höhe %.0f von %.0f, Inhalt %d)" % [
		str(qc.scroll_active) if qc is RichTextLabel else "-", qc.position.y + qc.size.y if qc != null else -1.0,
		qsub.size.y if qsub != null else -1.0, qc.get_content_height() if qc is RichTextLabel else -1],
		qc is RichTextLabel and qc.scroll_active and qc.mouse_filter == Control.MOUSE_FILTER_STOP and qsub != null
		and qc.position.y + qc.size.y <= qsub.size.y + 0.5)
	await _shot("9_quests")
	await _quest_popups(w)
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check("Esc schließt das Quest-Fenster", not h.quest_open())
	await _inventory(w)
	await _combat(w)
	# NPC in einem anderen Gebiet: den Ort sagt der Server (quest_where "npc", B19); die task_npc.data des Clients ist neuer und
	# hat manche NPCs dieser Welt schon woanders (Werwolf-NPCs in s43) - so einer bekommt trotzdem eine Autoroute
	var far_tid = 0
	var moved_tid = 0
	for tid in w.quest_data.npc_pos:
		if int(w.quest_data.npc_pos[tid][0]) == int(w.info.get("world", 0)) or (far_tid != 0 and moved_tid != 0):
			continue
		var wr = await w.session.quest_where("npc", tid, 0)
		await create_timer(0.025).timeout # höchstens 40 Anfragen / s: der Server trennt ab 60 / s (Flutbremse, mit den Positionen)
		var ww = int(wr.get("data", {}).get("world", 0))
		if wr["code"] == Proto.Code.OK and ww == -1 and far_tid == 0:
			far_tid = tid
		elif wr["code"] == Proto.Code.OK and ww == int(w.info.get("world", 0)) and moved_tid == 0:
			moved_tid = tid
	var lines_far = h.chat_lines.size()
	w.route_npc(far_tid)
	var far_name = Hud_plain(str(w.npc_data.info(far_tid)["name"]))
	await _until(func(): return h.chat_lines.size() > lines_far, 3.0)
	_check("NPC-Link in ein anderes Gebiet: Meldung (%s)" % far_name, far_tid != 0 and not w.routing()
		and h.chat_lines.back().contains(far_name))
	h.chat_lines.pop_back() # keine Fehlermeldung der Quests
	if moved_tid != 0:
		var moved_name = Hud_plain(str(w.npc_data.info(moved_tid)["name"]))
		var lines_moved = h.chat_lines.size()
		w.route_npc(moved_tid)
		var moved_routes = await _until_ok(func(): return w.routing(), 5.0)
		var far_text = Hud_plain(h.texts()["route_far"] % moved_name)
		_check("NPC %d (%s) laut Client-Daten in Welt %d, laut Server hier: Autoroute statt 'anderes Gebiet' (%s)" % [moved_tid,
			moved_name, int(w.quest_data.npc_pos[moved_tid][0]), moved_routes], moved_routes
			and not h.chat_lines.slice(lines_moved).any(func(l): return Hud_plain(l).contains(far_text)))
		w.cancel_route()
		await _frames(3)
	# Klick auf die Minimap: rechts / links / unten / oben der Mitte, der erste begehbare Punkt (Karte
	# gespiegelt: rechts = Welt -x)
	var area: Control = h._radar_marks
	var off = Vector2.ZERO
	for r in [20, 10, 30, 40]:
		for a in 8:
			var o = Vector2(r, 0).rotated(a * PI / 4.0).round()
			var wp = h.radar_to_world(o)
			var c = w.movemap.cell_of(wp.x, wp.y) if w.movemap != null else Vector2i.ZERO
			if off == Vector2.ZERO and w.movemap != null and w.movemap.passable(0, c.x, c.y):
				off = o
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = area.size / 2.0 + off
	var expect = h.radar_to_world(off)
	var me_pos = w.player.global_position
	area.gui_input.emit(ev)
	await _until(func(): return w.player.following(), 3.0)
	var mirrored = (off.x > 0 and expect.x < me_pos.x) or (off.x < 0 and expect.x > me_pos.x) or (off.y > 0 and expect.y < me_pos.z) \
		or (off.y < 0 and expect.y > me_pos.z)
	_check("Klick auf die Minimap %s startet die Autoroute (Ziel %s, gespiegelt)" % [off, expect], off != Vector2.ZERO and w.routing()
		and h.route_target != null and Vector2(h.route_target.x, h.route_target.z).distance_to(expect) < 0.01 and mirrored)
	await _shot("9b_route")
	_key(KEY_W, true)
	await _physics(3)
	_key(KEY_W, false)
	await _physics(3)
	_check("W bricht die Autoroute ab", not w.routing() and not w.player.following() and h.route_target == null)
	_check("keine Rücksetzung durch den Server beim Laufen (%d)" % _corrections, _corrections == 0)
	var errs = h.chat_lines.filter(func(l): return l.begins_with("^" + h.SYSTEM_COLOR))
	_check("keine Fehlermeldung der Quests im Chat (%s)" % str(errs), errs.is_empty())
	w.select_target(0)
	await _frames(3)

# Inventar, Charakter, Waffenregal, Schwert anlegen, 5679 abschließen
func _inventory(w) -> void:
	var h = w.hud
	var bag_pos = func(id: int) -> int:
		for pos in h.inventory["bag"]:
			if h.inventory["bag"][pos][0] == id:
				return pos
		return -1
	_key(KEY_B, true)
	_key(KEY_B, false)
	await _until(func(): return h.window_open(h.INVENTORY), 3.0)
	var inv = h.dlg(h.INVENTORY)
	var apos = bag_pos.call(ARMOR)
	var slot: Control = inv.item("Item_%02d" % apos) if apos >= 0 else null
	_check("B öffnet das Inventar: Rüstung mit Symbol, Belegung %s" % inv.get_text("Txt_BagNum"), h.window_open(h.INVENTORY)
		and slot != null and slot.get_node("Symbol").texture != null and inv.get_text("Txt_BagNum") == "1/24"
		and inv.item("Item_30").get_node("Sperre").visible)
	h._on_slot_hover("bag", apos)
	var tip: String = h.tooltip_text()
	var armor_name = Hud_plain(w.item_data.info(ARMOR)["name"])
	_check("Tooltip wie das Original (LuaItemDesc %s): %s" % [w.item_data.desc != null and w.item_data.desc.ready(), tip.replace("\n", " | ")],
		w.item_data.desc != null and w.item_data.desc.ready() and tip.contains(armor_name) and tip.contains("34")
		and h._tooltip_text.text.contains("[img"))
	# Seelenmünzen (Z4): Zeile über den Goldmünzen sichtbar, mit Hinweis aus dem XML; Wert aufgeteilt wie das Gold
	var bind_before = int(h.stats.get("bind_money", 0))
	w._on_pushed("stats", {"bind_money": 1234567})
	var hint_node: Control = inv.item("Img_FrameBindMoney_Back_1")
	var row = [inv.get_text("Txt_BindMoney0"), inv.get_text("Txt_BindMoney1"), inv.get_text("Txt_BindMoney2"), inv.get_text("Txt_BindMoney3")]
	_check("Inventar: Seelenmünzen-Zeile '%s' %s, Hinweis '%s'" % [inv.get_text("Lab_BindMoney"), str(row),
		hint_node.tooltip_text.get_slice("\n", 0) if hint_node != null else "-"], inv.is_shown("Lab_BindMoney") and inv.is_shown("Txt_BindMoney3")
		and inv.is_shown("Img_FrameBindMoney") and row == ["1", "23", "45", "67"] and inv.get_text("Lab_BindMoney") != ""
		and hint_node != null and hint_node.tooltip_text.contains(inv.get_text("Lab_BindMoney").substr(0, 4))) # Eng: "Soul Coin(s)"
	var gain = h.texts()["gain_bind"] % h.money_text(321)
	w._on_pushed("kill", {"id": 0, "tid": 0, "exp": 0, "bind": 321})
	_check("Chat: '%s'" % gain, h.chat_lines.any(func(l): return l.contains(gain)) and gain.contains("3"))
	await _shot("10_inventory")
	w._on_pushed("stats", {"bind_money": bind_before})
	h.hide_tooltip()
	var body_before = _skin(w.player.model, "body")
	_right_click(slot)
	await _until(func(): return h.inventory["equip"].get(3, 0) == ARMOR, 3.0)
	await _frames(3)
	_check("Rechtsklick legt die Rüstung an, die Figur trägt sie (neuer Körper-Skin)", h.inventory["equip"].get(3, 0) == ARMOR
		and bag_pos.call(ARMOR) < 0 and _skin(w.player.model, "body") != null and _skin(w.player.model, "body") != body_before)
	_key(KEY_C, true)
	_key(KEY_C, false)
	await _until(func(): return h.window_open(h.CHARACTER), 3.0)
	var ch = h.dlg(h.CHARACTER)
	await _frames(5)
	var figure = ch.is_shown("Img_Male") != ch.is_shown("Img_Female")
	_check("C öffnet das Charakter-Fenster: Rüstung, Verteidigung %s, Mana %s, %s (Figur als Bild wie im Original %s, kein 3D-Bild)" % [
		ch.get_text("Txt_Defense"), ch.get_text("Txt_Mp"), ch.get_text("Txt_Prof1"), str(figure)], h.window_open(h.CHARACTER)
		and ch.item("Equip_03").get_node("Symbol").texture != null and ch.get_text("Txt_Defense") == "96" and ch.get_text("Txt_Mp").ends_with("/587")
		and ch.get_text("Txt_Damage") == "201-201" and figure and not "preview" in h and h.find_child("Figurenbild", true, false) == null)
	await _shot("11_character")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check("Esc schließt Inventar und Charakter", not h.window_open(h.INVENTORY) and not h.window_open(h.CHARACTER))
	# zu Johnny über den Link in der Verfolgung
	_check("Verfolgung: Johnny als Link", h._trace_label.text.contains("[url=npc:%d]" % JOHNNY))
	h._trace_label.meta_clicked.emit("npc:%d" % JOHNNY)
	await _until(func(): return h.npc_open(), 60.0)
	var johnny = w.npcs.get(w.talk_npc)
	_check("Autoroute zu Johnny, sein Fenster geht auf", h.npc_open() and johnny != null and johnny.tid == JOHNNY)
	_check("Teil 7994 bei Johnny", await _talk_through(w, 7994, 8366))
	var text: String = h._trace_label.text
	var sword_name = Hud_plain(w.item_data.info(SWORD)["name"])
	_check("Verfolgung: %s 0/1 mit Link zum Waffenregal" % sword_name, text.contains(sword_name + " 0/1") and text.contains("[url=pos:"))
	var rack_where = await w.session.quest_where("item", SWORD, 8366) # Ziel-Link des Gegenstands (Z3): Sammelpunkt der Quest
	_check("Verfolgung: %s als Ziel-Link (item:%d:8366), Server kennt den Sammelpunkt (%s)" % [sword_name, SWORD, Proto.text(rack_where["code"])],
		text.contains("[url=item:%d:8366]" % SWORD) and rack_where["code"] == Proto.Code.OK)
	var at = text.find("[url=pos:")
	var meta = text.substr(at + 5, text.find("]", at) - at - 5)
	h._trace_label.meta_clicked.emit(meta)
	await _until(func(): return w.player.following(), 3.0)
	_check("Koordinaten-Link startet die Autoroute (%s)" % meta, w.routing())
	await _until(func(): return not w.routing(), 40.0)
	var rack = null
	for n in w.npcs.values():
		if n.tid == RACK:
			rack = n
	_check("am Waffenregal angekommen (%.1f m)" % (w.player.global_position.distance_to(rack.global_position) if rack != null else -1.0),
		rack != null and w.player.global_position.distance_to(rack.global_position) < 8.0 and rack.model != null)
	var rp: Array = rack_where["data"].get("pos", [0, 0, 0])
	_check("quest_where nannte dieses Waffenregal (%.1f m daneben)" % (Vector3(rp[0], rp[1], rp[2]).distance_to(rack.global_position) if rack != null else -1.0),
		rack != null and Vector3(rp[0], rp[1], rp[2]).distance_to(rack.global_position) < 1.0)
	await _shot("12_rack")
	var rinfo: Dictionary = w.npc_data.info(RACK)
	var glow_before = rack.get_node_or_null("Quest_Glitzer") != null
	w.select_target(rack.id)
	await _until(func(): return h.progress_shown(), 10.0)
	_check("Klick auf das Regal: Sammeln mit Fortschrittsbalken (%s)" % h.dlg(h.PROGRESS).get_text("Txt_info"), h.progress_shown())
	# B10: Quest-Sammelpunkt glitzert (task_in läuft), Sammel-Aktion der Vorlage (Start / Schleife in der Waffen-Variante)
	var acts: Array = w.gathering.get("acts", [])
	var cur = str(w.player.anim.current_animation) if w.player.anim != null else ""
	_check("Waffenregal (task_in %d) glitzert vor dem Sammeln (%s); Sammel-Aktion %s (Art %d '%s'), läuft '%s'" % [int(rinfo.get("task", 0)),
		glow_before, str(acts), int(rinfo.get("act_type", 0)), str(rinfo.get("action", "")), cur], glow_before
		and (acts.is_empty() if w.gather_acts(rinfo).is_empty() else (cur == acts[0] or cur == acts[1])))
	# Sammeln am Boden (Art 0, z.B. Lagerfeuer 14554, Kürbis 21072): nur die Schleife <action>_<Waffe> wie PlayVocationAction
	var fire_acts = w.gather_acts(w.npc_data.info(14554))
	var pump_acts = w.gather_acts(w.npc_data.info(21072))
	_check("Sammeln am Boden (Art 0, nur Schleife): Lagerfeuer %s, Kürbis %s" % [str(fire_acts), str(pump_acts)],
		fire_acts.size() == 3 and fire_acts[0] == "" and fire_acts[2] == "" and str(fire_acts[1]).begins_with("开锁循环")
		and pump_acts.size() == 3 and pump_acts[0] == "" and pump_acts[2] == "" and str(pump_acts[1]).begins_with("采摘循环"))
	await _shot("13_gather")
	await _until(func(): return bag_pos.call(SWORD) >= 0 and not h.progress_shown(), 10.0)
	await _until(func(): return w.quest_data.is_active(7997), 3.0)
	_check("Schwert in der Tasche (Chat), 8366 erfüllt, weiter mit 7997", bag_pos.call(SWORD) >= 0 and w.quest_data.is_active(7997)
		and h.chat_lines.any(func(l): return l.contains(sword_name)))
	_check("nach dem Sammeln kein Glitzer mehr am Waffenregal", not is_instance_valid(rack) or rack.get_node_or_null("Quest_Glitzer") == null)
	# Ziehen auf den Waffenplatz
	_key(KEY_B, true)
	_key(KEY_B, false)
	_key(KEY_C, true)
	_key(KEY_C, false)
	await _frames(3)
	var drag = {"kind": "bag", "idx": bag_pos.call(SWORD), "id": SWORD}
	_check("Waffenplatz nimmt das Schwert an, der Körperplatz nicht", h._slot_can_drop(Vector2.ZERO, drag, "equip", 0)
		and not h._slot_can_drop(Vector2.ZERO, drag, "equip", 3))
	h._slot_drop(Vector2.ZERO, drag, "equip", 0)
	await _until(func(): return h.inventory["equip"].get(0, 0) == SWORD, 3.0)
	await _frames(5)
	var weapon = w.player.model.get_node_or_null("Skeleton3D/Waffe")
	_check("Schwert angelegt: an der Figur (außerhalb des Kampfes auf dem Rücken: %s), Angriff %s, Leben %s" % [
		weapon.bone_name if weapon != null else "-", ch.get_text("Txt_Damage"), ch.get_text("Txt_Hp")],
		h.inventory["equip"].get(0, 0) == SWORD and weapon != null and weapon.get_child_count() > 0 and weapon.bone_name == "HH_背_巨剑"
		and ch.get_text("Txt_Damage") == "301-321" and ch.get_text("Txt_Hp").ends_with("/1730"))
	await _shot("14_sword")
	_right_click(ch.item("Equip_00"))
	await _until(func(): return bag_pos.call(SWORD) >= 0, 3.0)
	await _frames(3)
	_check("Rechtsklick legt das Schwert ab (wieder in der Tasche, keine Waffe an der Figur)", bag_pos.call(SWORD) >= 0
		and w.player.model.get_node_or_null("Skeleton3D/Waffe") == null)
	_right_click(inv.item("Item_%02d" % bag_pos.call(SWORD)))
	await _until(func(): return h.inventory["equip"].get(0, 0) == SWORD, 3.0)
	_check("und wieder angelegt", h.inventory["equip"].get(0, 0) == SWORD)
	h.close_window(h.INVENTORY)
	h.close_window(h.CHARACTER)
	h._trace_label.meta_clicked.emit("npc:%d" % JOHNNY)
	await _until(func(): return h.npc_open(), 40.0)
	var done = await _talk_through(w, 7997, 0)
	await _until(func(): return int(h.stats.get("level", 1)) == 3, 3.0)
	await _frames(2)
	_check("Stufenaufstieg (B10): Klang 升级音效 spielt (%s), GFX 角色升级 am Modell" % str(w.get_node_or_null("Stufenaufstieg") != null),
		w.get_node_or_null("Stufenaufstieg") != null and w.player.model.find_children("*", "Node3D", false, false).any(func(c): return c.has_method("player_length_ms")))
	_check("5679 bei Johnny abgeschlossen: Stufe 3 (40 * 5 EXP)", done and int(h.stats.get("level", 1)) == 3
		and w.quest_data.task(5679) != {} and not w.quest_data.is_active(5679))

# Kampf: 5680 (zehn Wildschweine), Treffer, Tod, EXP; Tod und Wiederbeleben bei den Giftjagdhunden
func _combat(w) -> void:
	var h = w.hud
	var me = w.my_id
	var hits_on_me = [0]
	var my_hits = [0]
	var first_hit_ms = [0] # Zeit der ersten eigenen Treffer-Meldung
	var first_hit = {} # ihre Daten (verfehlt: Leben bleibt)
	ls.session.net.pushed.connect(func(what, d): if what == "hit" and int(d["dst"]) == me: hits_on_me[0] += 1)
	ls.session.net.pushed.connect(func(what, d): if what == "hit" and int(d["src"]) == me: my_hits[0] += 1)
	ls.session.net.pushed.connect(func(what, d): if what == "hit" and int(d["src"]) == me and first_hit.is_empty(): first_hit.merge(d))
	ls.session.net.pushed.connect(func(what, d): if what == "hit" and int(d["src"]) == me and first_hit_ms[0] == 0: first_hit_ms[0] = Time.get_ticks_msec())
	await create_timer(0.5).timeout
	w.route_npc(JOHNNY)
	await _until(func(): return h.npc_open(), 40.0)
	_check("Johnny bietet 5680 'Wetzt Eure Knochen' an", h.npc_open() and h.npc_entries.any(func(e): return e["id"] == 5680))
	_check("5680 angenommen", await _talk_through(w, 5680, 5680))
	var loot_name = Hud_plain(w.item_data.info(BOAR_LOOT)["name"])
	_check("Verfolgung: %s 0/10" % loot_name, h._trace_label.text.contains(loot_name + " 0/10"))
	# Ziel-Link (Z3): Beute-Ziel -> das Monster, das sie fallen lässt; der Server nennt das nächste lebende Wildschwein
	var mon_link = "mon:%d:5680" % BOAR
	var linked = h._trace_label.text.contains("[url=%s]" % mon_link)
	h._trace_label.meta_clicked.emit(mon_link)
	await _until(func(): return w.routing(), 5.0)
	var goal = w.route.get("goal", Vector3.INF)
	var near_boar = INF
	for n in w.npcs.values():
		if n.tid == BOAR and not n.dead and goal is Vector3:
			near_boar = minf(near_boar, Vector2(n.global_position.x - goal.x, n.global_position.z - goal.z).length())
	var boar_name = Hud_plain(w.npc_data.display_name(w.npc_data.info(BOAR), 0))
	_check("Verfolgung: Wildschwein-Link (%s) startet die Autoroute zu '%s' (%s), %.1f m vom nächsten Wildschwein" % [str(linked),
		str(w.route.get("label", "")), boar_name, near_boar], linked and w.routing() and str(w.route.get("label", "")) == boar_name
		and near_boar < 12.0)
	w.cancel_route()
	var killed = 0
	var back_checked = false # Gegenangriff geprüft (stirbt das erste am ersten Schlag - Krit -, zählen die übrigen)
	for k in 10:
		var boar = _nearest(w, BOAR)
		if boar == null:
			break
		var bid: int = boar.id # das Modell wird nach dem Tod freigegeben
		w.select_target(bid)
		await _until(func(): return w.target_id == bid, 3.0)
		w.select_target(bid)
		var started = func(): return w.attacking == bid or (k == 0 and my_hits[0] > 0) # Krit kann es sofort töten
		await _until(started, 30.0)
		if k == 0:
			_check("zweiter Klick auf das Wildschwein: hinlaufen und angreifen", started.call())
			await _until(func(): return my_hits[0] > 0, 6.0)
			await _frames(1)
			var early = w.get_children().filter(func(c): return c is Label3D).size()
			await _until(func(): return w.get_children().any(func(c): return c is Label3D), 3.0)
			var delay = Time.get_ticks_msec() - first_hit_ms[0]
			var hit_fx = w.attack_fx.get_children().size()
			_check("Einschlag: Treffer-GFX am Wildschwein (%d), Zahl erst danach (%d ms nach der Meldung, vorher %d)" % [hit_fx, delay, early],
				hit_fx > 0 and early == 0 and delay >= 250)
			var act = str(w.player.anim.current_animation)
			var bar = h.dlg("TargetMonster").item("Prg_HP")
			# die erste Zahl kann auch der Gegenschlag sein: auf das Leben im Ziel-Fenster warten (der erste Einschlag baut
			# sein GFX, unter Vulkan samt Shadern, das kann dauern); eine Zahl lebt nur FLOAT_TIME: mitzählen, solange gewartet wird
			var seen = [0]
			await _until(_hit_shown.bind(w, seen, bar, first_hit), 6.0)
			_check("Treffer: Aktion %s, %d schwebende Zahlen, Leben im Ziel-Fenster %.0f %%%s" % [act, seen[0], bar.value if bar != null else -1.0,
				" (verfehlt)" if first_hit.get("miss", false) else (" (erster Schlag tödlich)" if _one_shot(first_hit) else "")],
				my_hits[0] > 0 and seen[0] > 0 and bar != null
				and (bar.value < 100.0 or first_hit.get("miss", false) or _one_shot(first_hit)) and act.begins_with("普通攻击"))
			var held = w.player.model.get_node_or_null("Skeleton3D/Waffe")
			_check("im Kampf: Schwert in der Hand (%s)" % (held.bone_name if held != null else "-"), w.player.fighting and held != null
				and held.bone_name == "HH_righthandweapon")
			await _shot("15_attack")
			_key(KEY_W, true)
			await _physics(2)
			_key(KEY_W, false)
			await _physics(2)
			_check("W beendet den Angriff", w.attacking == 0)
			if w.npcs.has(bid) and not w.npcs[bid].dead:
				await _until(func(): return hits_on_me[0] > 0, 6.0)
				_check("das Wildschwein schlägt zurück (%d Treffer, Leben %s)" % [hits_on_me[0], h.stats.get("hp")], hits_on_me[0] > 0)
				back_checked = true
				w.select_target(bid)
				await _until(func(): return w.attacking == bid, 20.0)
		await _until(func(): return not w.npcs.has(bid), 20.0)
		if w.npcs.has(bid):
			break
		killed += 1
		if k == 0:
			var boar_ref = weakref(boar) # das Modell kann schon freigegeben sein (Lambda mit freigegebenem Objekt = Fehler)
			await _until(_gone_or_dead.bind(boar_ref), 3.0) # nach dem Einschlag
			var dead_boar = boar_ref.get_ref()
			# erster Schlag tödlich: das Modell kann nach dem Sterben schon freigegeben sein
			_check("Wildschwein stirbt sichtbar, Chat: 6 EXP%s" % (" (erster Schlag tödlich)" if _one_shot(first_hit) else ""),
				((dead_boar != null and dead_boar.dead) or (dead_boar == null and _one_shot(first_hit)))
				and h.chat_lines.any(func(l): return l.contains("6 EXP")))
			await _shot("16_dead_boar")
	if not back_checked:
		_check("die Wildschweine schlagen zurück (%d Treffer; das erste starb am ersten Schlag)" % hits_on_me[0], hits_on_me[0] > 0)
	await _until(func(): return h._trace_label.text.contains(loot_name + " 10/10"), 3.0)
	_check("zehn Wildschweine (%d), Verfolgung %s 10/10" % [killed, loot_name], killed == 10 and h._trace_label.text.contains(loot_name + " 10/10"))
	var vestry_name = Hud_plain(w.npc_data.info(VESTRY)["name"])
	var back_line = h.texts()["return_to"] % vestry_name
	_check("Ziel erreicht: '%s' als Link (npc:%d) in der Verfolgung" % [back_line, VESTRY], h.trace_items().any(func(t): return t.has(back_line))
		and h._trace_label.text.contains("[url=npc:%d]" % VESTRY))
	w.route_npc(VESTRY)
	await _until(func(): return h.npc_open(), 60.0)
	_check("5680 bei Lady Vestry abgeschlossen (Beute eingezogen)", await _talk_through(w, 5680, 0)
		and w._bag_count(BOAR_LOOT) == 0)
	await _until(func(): return not w.player.fighting, 8.0)
	var back = w.player.model.get_node_or_null("Skeleton3D/Waffe")
	_check("6 s nach dem Kampf: Schwert wieder auf dem Rücken, Stehen %s" % str(w.player.anim.current_animation), not w.player.fighting
		and back != null and back.bone_name == "HH_背_巨剑" and not str(w.player.anim.current_animation).begins_with("战斗"))
	await _skill_cast(w)
	_dual_daggers(w)
	await _mage_projectile(w)
	await _mage_fireball(w)
	# Tod: ohne Ausrüstung bei den Giftjagdhunden
	for slot in [0, 3]:
		h.unequip_requested.emit(slot, -1)
		await _until(func(): return not h.inventory["equip"].has(slot), 3.0)
	var stuck_at = []
	var hound_from = w.player.global_position
	var on_stuck = func(): stuck_at.append(w.player.global_position.snapped(Vector3(0.1, 0.1, 0.1)))
	w.player.route_stuck.connect(on_stuck)
	w.route_to(HOUNDS_AT, "Giftjagdhunde")
	await _until(func(): return not w.routing(), 90.0)
	w.player.route_stuck.disconnect(on_stuck)
	var hound_route = "Weg von %s, steckte bei %s, angekommen bei %s, gesperrte Felder %d (Kollision %s)" % [hound_from.snapped(Vector3(0.1, 0.1, 0.1)),
		str(stuck_at), w.player.global_position.snapped(Vector3(0.1, 0.1, 0.1)), w.blocked_cells, str(w.collision_info)]
	print("WELT-TEST: Giftjagdhunde: ", hound_route)
	for i in 3:
		var hound = _nearest(w, 14578)
		if hound == null or w.player.dead:
			break
		w.select_target(hound.id)
		await _until(func(): return w.target_id == hound.id, 3.0)
		w.select_target(hound.id)
		var hits_before = my_hits[0]
		await _until(func(): return my_hits[0] > hits_before or w.player.dead, 25.0)
		w.stop_attack()
		w.select_target(0)
	await _until(func(): return w.player.dead, 90.0)
	await _frames(5)
	_check("ohne Ausrüstung bei den Giftjagdhunden gestorben: Win_Message4, Sterbe-Aktion, keine Steuerung (%s)" % hound_route,
		w.player.dead and h.revive_shown() and not w.player.input_enabled and str(w.player.anim.current_animation).begins_with("死亡"))
	await _shot("17_dead")
	var corrections = _corrections
	h.dlg("Message4").send("Btn_Decide")
	await _until(func(): return not w.player.dead, 5.0)
	await _frames(5)
	_corrections = corrections # das Wiederbeleben setzt die Figur absichtlich um (pos_correct)
	await _physics(5)
	var p = w.player.global_position
	_check("Wiederbeleben: am Wiederbelebungspunkt (%.0f, %.0f), %s HP" % [p.x, p.z, h.stats.get("hp")], not w.player.dead
		and not h.revive_shown() and Vector2(p.x + 151.0, p.z - 42.0).length() < 2.0 and int(h.stats.get("hp", 0)) < int(h.stats.get("max_hp", 0)))
	for e in h.bag_items():
		if e[1] == SWORD or e[1] == ARMOR:
			h.equip_requested.emit(e[0])
	await _until(func(): return h.inventory["equip"].has(0) and h.inventory["equip"].has(3), 5.0)

func _nearest(w, tid: int):
	var best = null
	for n in w.npcs.values():
		if n.tid == tid and not n.dead and (best == null or n.global_position.distance_to(w.player.global_position) < best.global_position.distance_to(w.player.global_position)):
			best = n
	return best

func _skin(model: Node3D, slot: String):
	var sk = model.get_node_or_null("Skeleton3D") if model != null else null
	if sk == null:
		return null
	for c in sk.get_children():
		if c is MeshInstance3D and c.get_meta("slot", "") == slot:
			return c.mesh
	return null

# Popups der Quests (B19): Rechtsklick auf 5679 im Quest-Fenster -> Win_QuestOption an der Maus (Verfolgen gesperrt),
# Aufgeben fragt (gameui.stf 236), Abbrechen lässt die Quest; Rechtsklick auf ihre Zeile in der Verfolgung ->
# Win_QuestMinionOption, "Ansehen" wählt sie im Quest-Fenster; Aufgeben mit OK -> der Server lehnt ab (5679 ohne giveup),
# Meldung im Chat, die Quest läuft weiter; ein Klick daneben schließt ein Popup
func _quest_popups(w) -> void:
	var h = w.hud
	var tree = h.dlg("Quest").item("Tv_Quest") as Tree
	var item: TreeItem = null
	for it in tree.get_root().get_children():
		if int(it.get_metadata(0)) == 5679:
			item = it
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = tree.get_item_area_rect(item).get_center() if item != null else Vector2.ZERO
	ev.global_position = tree.get_global_transform() * ev.position
	tree.gui_input.emit(ev)
	await _frames(2)
	var pop = h.dlg(h.QUEST_OPTION)
	_check("Rechtsklick im Quest-Fenster: Win_QuestOption für 5679 (%s, %d), Verfolgen gesperrt" % [h.quest_option_open(),
		h.option_quest], item != null and h.quest_option_open() == h.QUEST_OPTION and h.option_quest == 5679
		and pop.item("Btn_Focus").disabled and not pop.item("Btn_Abandon").disabled
		and pop.get_global_rect().has_point(ev.global_position + Vector2(1, 1)))
	await _shot("9a_quest_option")
	pop.send("Btn_Abandon")
	await _until(func(): return h.aui.has_message_box(), 3.0)
	var box = h.aui._top.get_child(h.aui._top.get_child_count() - 1) if h.aui.has_message_box() else null
	var ask = Hud_plain(box.get_text("Txt_Message")) if box != null else ""
	if box != null:
		box.send("IDCANCEL")
	await _frames(10)
	_check("Aufgeben fragt '%s' (gameui.stf 236, übersetzt), Abbrechen: 5679 läuft weiter, Popup zu" % ask,
		ask == Hud_plain(h.aui.text(h.STF_ABANDON_ASK)) and ask != "" and not h._has_cjk(ask) and w.quest_data.is_active(5679)
		and h.quest_option_open() == "")
	h.close_quests()
	await _frames(2)
	var line = h._trace_line_quest.find(5679)
	var y = h._trace_label.get_paragraph_offset(line) + 3.0 if line >= 0 else -1.0
	var rc = InputEventMouseButton.new()
	rc.button_index = MOUSE_BUTTON_RIGHT
	rc.pressed = true
	rc.position = Vector2(20, y)
	rc.global_position = h._trace_label.get_global_transform() * rc.position
	h._trace_label.gui_input.emit(rc)
	await _frames(2)
	var mpop = h.dlg(h.QUEST_MINION_OPTION)
	_check("Rechtsklick in der Verfolgung (Zeile %d): Win_QuestMinionOption für 5679 (%s, %d), Verfolgung abbrechen gesperrt" % [
		line, h.quest_option_open(), h.option_quest], line >= 0 and h.quest_option_open() == h.QUEST_MINION_OPTION
		and h.option_quest == 5679 and mpop.item("Btn_Delete").disabled)
	await _shot("9b_trace_option")
	mpop.send("Btn_Info")
	await _frames(3)
	_check("'Ansehen' öffnet das Quest-Fenster mit 5679 (%d)" % h.quest_selected, h.quest_open() and h.quest_selected == 5679
		and h.quest_option_open() == "")
	h._trace_label.gui_input.emit(rc)
	await _frames(2)
	var outside = InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	outside.position = Vector2(2, 2)
	outside.global_position = Vector2(2, 2)
	var was_open = h.quest_option_open()
	h._input(outside)
	await _frames(2)
	_check("Klick neben das Popup schließt es (%s -> '%s')" % [was_open, h.quest_option_open()], was_open == h.QUEST_MINION_OPTION
		and h.quest_option_open() == "")
	h._trace_label.gui_input.emit(rc)
	await _frames(2)
	var lines = h.chat_lines.size()
	mpop.send("Btn_Abandon")
	await _until(func(): return h.aui.has_message_box(), 3.0)
	box = h.aui._top.get_child(h.aui._top.get_child_count() - 1) if h.aui.has_message_box() else null
	var asked = box != null
	if asked:
		box.send("IDOK") # danach freigegeben
	await _until(func(): return h.chat_lines.size() > lines, 3.0)
	var said = h.chat_lines.slice(lines).map(func(l): return Hud_plain(l))
	_check("Aufgeben mit OK bei 5679 (ohne giveup): Server lehnt ab %s, 5679 läuft weiter" % str(said), asked
		and said.any(func(l): return l.contains(Proto.text(Proto.Code.QUEST_NO_GIVEUP, w.login.language)))
		and w.quest_data.is_active(5679))
	while h.chat_lines.size() > lines: # erwartete Ablehnung, keine Fehlermeldung der Quests
		h.chat_lines.pop_back()

func _right_click(c: Control) -> void:
	if c == null:
		return
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	c.gui_input.emit(ev)

# Größter Abstand der Wegpunkte von der geraden Linie a -> b (x / z)
static func _off_line(path: PackedVector3Array, a: Vector3, b: Vector3) -> float:
	var a2 = Vector2(a.x, a.z)
	var d = Vector2(b.x, b.z) - a2
	var n = Vector2(-d.y, d.x).normalized()
	var best = 0.0
	for p in path:
		best = maxf(best, absf((Vector2(p.x, p.z) - a2).dot(n)))
	return best

static func Hud_plain(s: String) -> String:
	return load("res://game/client/hud.gd")._plain(s)

# Eintrag id im offenen NPC-Fenster wählen und jeweils die erste Option klicken, bis das Fenster
# zugeht; danach muss next_id laufen (0 = id ist nicht mehr da)
func _talk_through(w, id: int, next_id: int) -> bool:
	var h = w.hud
	var idx = -1
	for i in h._npc_options.size():
		if h._npc_options[i][0] == "entry" and int(h._npc_options[i][1]["id"]) == id:
			idx = i
	if idx < 0:
		return false
	h._on_npc_list(idx)
	for step in 12:
		await _frames(1)
		if not h.npc_open():
			break
		h._on_npc_list(0)
	var ok = func(): return (next_id == 0 and not w.quest_data.is_active(id)) or w.quest_data.is_active(next_id)
	await _until(ok, 3.0)
	return ok.call() and not h.npc_open()

func _click(screen: Vector2) -> void:
	for pressed in [true, false]:
		var ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = screen
		ev.global_position = screen
		Input.parse_input_event(ev)


# ====================================================
# HILFEN
# ====================================================
# Magier (Mensch, Klasse 5) mit dem Novizen-Magiestab greift das nächste Monster an (nur Effekte, ohne
# Server): der Angriffspunkt (750 ms, 法系普攻3.att) schießt den Energieball (Flug-GFX) von der Brust
# zum Ziel, beim Einschlag Treffer-GFX und erst dann die Wirkung
func _mage_projectile(w) -> void:
	var eq = w.equip_models({0: STAFF}, 1, 5, 0)
	var err = w.factory.build(1, 0, 5, LOOK, w._actions({0: STAFF}), eq)
	var mage: Node3D = w.factory.detach() if err == "" else null
	var target = _nearest(w, BOAR)
	if target == null:
		target = _nearest(w, 14578)
	if mage == null or target == null:
		_check("Magier gebaut, Ziel da (%s)" % err, false)
		return
	var holder = Node3D.new()
	w.add_child(holder)
	holder.add_child(mage)
	var to = target.global_position
	var away = Vector3(to.x - w.player.global_position.x, 0, to.z - w.player.global_position.z).normalized()
	holder.global_position = to - (away if away.length() > 0.1 else Vector3.FORWARD) * 10.0
	var pts = w.attack_fx.points_of(mage, "普通攻击1_法杖")
	var t0 = Time.get_ticks_msec()
	var hit_at = [0]
	mage.get_node("AnimationPlayer").play("普通攻击1_法杖")
	w.attack_fx.play(holder, mage, "普通攻击1_法杖", target, func(): hit_at[0] = Time.get_ticks_msec())
	var flew = await _until_ok(func(): return not w.attack_fx._flying.is_empty(), 3.0)
	var fly_ms = Time.get_ticks_msec() - t0
	await _until(func(): return hit_at[0] > 0, 3.0)
	_check("Magier: Angriffspunkt %s, Energieball fliegt ab %d ms, Einschlag nach %d ms (Wirkung erst dann)" % [str(pts), fly_ms,
		hit_at[0] - t0], pts.size() == 1 and str(pts[0][1]).ends_with("法系普攻3.att") and flew and fly_ms >= 600
		and hit_at[0] - t0 > fly_ms and w.attack_fx.importer.written.is_empty())
	holder.queue_free()
	_gfx_order(w)

# GFX-Reihenfolge und Warp (B10): im Feuerball 飞火球 zeichnet das Warp-Element (云团03, Warp 1) zuerst, die übrigen in der
# Reihenfolge der Datei - der Kern (101 火球, letztes Element, Priority 0) zuletzt statt unter den Wolken; der Warp-Shader zeigt
# nur das verschobene Bild (Formel des Originals, ohne Mip-Wahl), nie die Farbe der Textur; Partikel-Größe mit dem GFX-Maßstab
# Alte Importe (B10 Teil 4): beim Laden neu gebaute Modelle / Karten-Effekte zählen, Warteschlange leer; dazu der Weg selbst
# an einer künstlich veralteten Modell-Szene (Stempel entfernt: CoGfx neu, Stempel aktuell) und einem getauschten Karten-Effekt
func _gfx_refresh(w) -> void:
	var R = w._gfx_refresh
	if R == null:
		_check("gfx_refresh.gd fehlt", false)
		return
	var model_ok = false
	var info = "kein Modell mit CoGfx"
	var have_orig = DirAccess.dir_exists_absolute(w.attack_fx.importer.data_root) # ohne Original-Daten (P2f6) gibt es keine .ecm
	for path in (w._scenes if have_orig else {}):
		var sc: PackedScene = w._scenes[path]
		if sc == null or w._stale.has(path):
			continue
		var ecm: Dictionary = w.attack_fx.importer.read_ecm(str(R._root_meta(sc, "ecm_path", "")))
		if ecm.get("cogfx", []).filter(func(e): return int(e.get("type", 0)) == 100).is_empty():
			continue
		var inst = sc.instantiate()
		inst.remove_meta(R.STAMP_META)
		var stale = PackedScene.new()
		stale.pack(inst)
		inst.free()
		var r: Dictionary = R.refresh_model(w.attack_fx.importer, stale, w.attack_fx._scene)
		info = "%s: veraltet %s -> %s, GFX %d neu / %d alt" % [str(path).get_file(), R.outdated(stale), R.outdated(r["scene"]), r["gfx"], r["removed"]]
		model_ok = R.outdated(stale) and not R.outdated(r["scene"]) and r["gfx"] > 0 and r["gfx"] == r["removed"]
		break
	var swap_ok = false
	var swap_info = "kein Karten-Effekt"
	for n in w.map_root.find_children("*", "Node3D", true, false):
		var p: String = n.scene_file_path
		if p == "" or n.owner != w.map_root or R.gfx_path(p) == "" or not n.has_meta("valid_time"):
			continue
		var parent = n.get_parent()
		var nm = n.name
		var xf: Transform3D = n.transform
		var vt = n.get_meta("valid_time")
		var old_id = n.get_instance_id()
		w._map_gfx[p] = [n]
		w._refresh_map_gfx(p)
		var neu = parent.get_node_or_null(NodePath(nm))
		swap_info = "%s: getauscht %s, Lage gleich %s, Tageszeit %s" % [nm, neu != null and neu.get_instance_id() != old_id,
			neu != null and neu.transform.is_equal_approx(xf), str(neu.get_meta("valid_time", "-")) if neu != null else "-"]
		swap_ok = neu != null and neu.get_instance_id() != old_id and neu.transform.is_equal_approx(xf) and neu.get_meta("valid_time", -1) == vt \
			and not R.outdated(w.attack_fx._scene(R.gfx_path(p)))
		break
	if swap_info == "kein Karten-Effekt" and w.refreshed_gfx > 0:
		# alter Import: der Client hat schon alle Karten-Effekte getauscht -> einer davon trägt den aktuellen Stand und die Tageszeit
		for n in w.map_root.find_children("*", "Node3D", true, false):
			if n.has_meta("valid_time") and R.is_gfx(n) and n.scene_file_path == "" and str(n.get_meta(R.STAMP_META, "")) == R.stamp():
				swap_info = "%s schon beim Laden getauscht (aktueller Stand, Tageszeit %s)" % [n.name, str(n.get_meta("valid_time"))]
				swap_ok = true
				break
	if not model_ok and info == "kein Modell mit CoGfx" and not have_orig:
		# ohne Original-Daten (P2f6) gibt es keine .ecm, aus der ein veraltetes Modell neu gebaut würde - und keine alten Importe
		info = "ohne Original-Daten nicht prüfbar"
		model_ok = true
	_check("Alte Importe: beim Laden neu gebaut %d Modelle / %d Karten-Effekte, Warteschlange leer (%d); %s; %s" % [w.refreshed_models,
		w.refreshed_gfx, w._gfx_queue.size(), info, swap_info], w._gfx_queue.is_empty() and model_ok and swap_ok)

# Performance-Fahrplan P1: GFX-Materialien der Map verweisen auf gemeinsame Shader-Dateien (ECM_Import/shaders), gleicher
# Text = dasselbe Shader-Objekt über alle Szenen; Vorwärmen hinter dem Ladebildschirm nur mit GL
func _shader_pool(w) -> void:
	var by_code = {}
	var files = 0
	var total = 0
	var split = 0
	for gi in w.map_root.find_children("*", "GeometryInstance3D", true, false):
		var m = gi.material_override as ShaderMaterial
		if m == null or m.shader == null or not R_is_gfx_material(gi):
			continue
		total += 1
		if m.shader.resource_path.begins_with("res://ECM_Import/shaders/"):
			files += 1
		var c: String = m.shader.code
		if by_code.has(c) and by_code[c] != m.shader:
			split += 1
		by_code[c] = m.shader
	var gl = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	_check("Shader-Vorrat (P1): %d GFX-Materialien der Map, %d mit Shader-Datei, %d Texte, doppelte Objekte %d, Vorrat %d; vorgewärmt %d (GL %s)" % [
		total, files, by_code.size(), split, w._gfx_parser.shader_pool_size(), w.prewarmed, gl],
		total > 0 and split == 0 and (files == total or w.refreshed_gfx > 0) and ((w.prewarmed > 0) == gl))

static func R_is_gfx_material(gi: Node) -> bool:
	var el = gi.get_parent()
	return el != null and typeof(el.get("parsed_data")) == TYPE_DICTIONARY

func _gfx_order(w) -> void:
	var sc: PackedScene = w.attack_fx._scene("人物/飞行/飞火球.gfx")
	var n = sc.instantiate() if sc != null else null
	var prio = {}
	var warp_code = ""
	var core = -999
	var warp_prio = 999
	var scaled = false
	if n != null:
		for mi in n.find_children("*", "GeometryInstance3D", true, false):
			var m = mi.material_override as ShaderMaterial
			var el = mi.get_parent()
			if m == null or m.shader == null or el == null:
				continue
			var d = el.get("parsed_data")
			var warp = typeof(d) == TYPE_DICTIONARY and str(d.get("Warp", "0")).strip_edges() == "1"
			prio[str(el.name)] = m.render_priority
			if warp:
				warp_prio = m.render_priority
				warp_code = m.shader.code
			if str(el.name).ends_with("_ID_101"):
				core = m.render_priority
			if "g_scale" in m.shader.code:
				scaled = true
		n.free()
	var others = prio.values().filter(func(v): return v != warp_prio)
	# Lage-Geschichte (B10): das Überfall-GFX 加速 am Rücken bekommt sie für seine ungebundenen Partikel
	var wind = w.attack_fx.attach(w.player, w.player.model, "策划联入/加速.gfx", "HH_Spine")
	var drivers = wind.find_children("Lage_Geschichte", "", true, false).size() if wind != null else 0
	if wind != null:
		wind.queue_free()
	_check("Überfall-GFX 加速 an der Figur: %d ungebundene Partikel-Netze mit Lage-Geschichte" % drivers, drivers >= 3)
	_check("Feuerball: Warp zeichnet zuerst (%d), Kern 101 zuletzt (%d von %s), Warp zeigt nur das verschobene Bild, Partikel mit GFX-Maßstab (%s)" % [
		warp_prio, core, str(prio.values()), scaled], sc != null and warp_prio == Material.RENDER_PRIORITY_MIN and not others.is_empty()
		and core == others.max() and "textureLod(screen_texture" in warp_code and not "normal_map" in warp_code and scaled)
	# Blitzschläger-Klinge 闪电剑刀效果 (Decal 100, 闪电.dds 1 x 4 mit UVExchg): Tausch erst nach dem Bild der Folge, sonst vier
	# Blitze nebeneinander ("Dreizack"); Drachen-Blitz 黑龙王BOOS闪电连接 (gerade, Endpunkte an Haken): Ausschlag in Weltmaßen
	var uv_ok = false
	var blade: PackedScene = w.attack_fx._scene("人物/技能/战士/闪电剑刀效果.gfx")
	if blade != null:
		var bn = blade.instantiate()
		for mi in bn.find_children("*", "GeometryInstance3D", true, false):
			var m = mi.material_override as ShaderMaterial
			if m != null and m.shader != null and str(mi.get_parent().name).begins_with("Element_1_0_ID_100"):
				var c: String = m.shader.code
				uv_ok = c.find("frame_y / f_rows") > 0 and c.find("final_uv = final_uv.yx") > c.find("frame_y / f_rows")
		bn.free()
	var amp_ok = false
	var ltn: PackedScene = w.attack_fx._scene("怪物/怪物身上效果/黑龙王BOOS闪电连接.gfx")
	if ltn != null:
		var ln = ltn.instantiate()
		for mi in ln.find_children("Lightning_GFX", "GeometryInstance3D", true, false):
			var m = mi.material_override as ShaderMaterial
			amp_ok = m != null and m.shader != null and "amp /= w_scale;" in m.shader.code
		ln.free()
	elif not DirAccess.dir_exists_absolute(w.attack_fx.importer.data_root):
		amp_ok = true # ohne Original-Daten (P2f6) nur, wenn die Map des Drachen mit umgewandelt ist
	_check("Blitzschläger-Klinge: UV-Tausch nach dem Bild der Folge (%s); Drachen-Blitz mit Ausschlag in Weltmaßen (%s)" % [uv_ok, amp_ok],
		uv_ok and amp_ok)

# Fertigkeit einsetzen (Fertigkeiten-Fahrplan F2): Taste 2 (Hieb, Leiste unten Platz 2) ohne Ziel -> Meldung;
# auf ein Wildschwein: hinlaufen, zaubern (Aktion 战士_斩击, Zauberbalken mit dem Namen), Treffer mit Zahl,
# Mana weniger, Abklingzeit-Uhr auf dem Platz; gleich noch einmal -> "noch nicht bereit"
func _skill_cast(w) -> void:
	var h = w.hud
	var me = w.my_id
	var skill_name = Hud_plain(w.skill_data.skill_name(122))
	w.select_target(0)
	await _until(func(): return w.target_id == 0, 3.0)
	var lines = h.chat_lines.size()
	_key(KEY_2, true)
	_key(KEY_2, false)
	await _until(func(): return h.chat_lines.size() > lines, 3.0)
	_check("Taste 2 ohne Ziel: %s" % (h.chat_lines[-1] if h.chat_lines.size() > lines else "-"), h.chat_lines.size() > lines
		and h.chat_lines[-1].contains(Proto.text(Proto.Code.NO_TARGET, ls.language)))
	if h.chat_lines.size() > lines:
		h.chat_lines.pop_back() # erwartete Meldung (die Quests prüfen später: keine Fehlermeldung im Chat)
	var boar = _nearest(w, BOAR)
	if boar == null:
		_check("Wildschwein für Hieb", false)
		return
	var bid: int = boar.id
	w.select_target(bid)
	await _until(func(): return w.target_id == bid, 3.0)
	var mp0 = int(h.stats.get("mp", 0))
	_sk_mp = [mp0, -1]
	ls.session.net.pushed.connect(_skill_push)
	var hit = {}
	ls.session.net.pushed.connect(func(what, d): if what == "hit" and int(d["src"]) == me and int(d.get("skill", 0)) == 122 and hit.is_empty(): hit.merge(d))
	_key(KEY_2, true)
	_key(KEY_2, false)
	await _until(func(): return w.casting.has("end"), 60.0) # das nächste Wildschwein steht gut 80 m weit
	await _frames(3)
	var act = str(w.player.anim.current_animation)
	var bar_text = str(h.dlg(h.PROGRESS).get_text("Txt_info")) if h.progress_shown() else ""
	_check("Taste 2: hinlaufen und Hieb zaubern (Aktion %s, Zauberbalken '%s'%s)" % [act, bar_text,
		"" if w.casting.has("end") else ", Chat: " + (h.chat_lines[-1] if not h.chat_lines.is_empty() else "-")],
		w.casting.has("end") and act == "战士_斩击" and bar_text.contains(skill_name))
	await _shot("18_skill")
	await _until(func(): return not hit.is_empty() and w.casting.is_empty(), 5.0)
	await _until(func(): return _sk_mp[1] >= 0, 2.0)
	ls.session.net.pushed.disconnect(_skill_push)
	var slot = h.skill_control("bar0", 1)
	var cool = slot.get_node_or_null("Cool") if slot != null else null
	await _frames(2)
	_check("Hieb trifft (%s Schaden%s), Mana %d -> %d, Balken weg, Abklingzeit-Uhr auf Platz 2 (%.2f)" % [str(hit.get("dmg")),
		", verfehlt" if hit.get("miss", false) else "", _sk_mp[0], _sk_mp[1], cool._left if cool != null else -1.0],
		not hit.is_empty() and _sk_mp[1] == _sk_mp[0] - 18 and not h.progress_shown() and cool != null and cool._left > 0.0
		and h.cool_fraction(122) > 0.0)
	await _shot("19_cooldown")
	lines = h.chat_lines.size()
	_key(KEY_2, true)
	_key(KEY_2, false)
	await _until(func(): return h.chat_lines.size() > lines, 3.0)
	_check("gleich noch einmal: %s" % (h.chat_lines[-1] if h.chat_lines.size() > lines else "-"), h.chat_lines.size() > lines
		and h.chat_lines[-1].contains(Proto.text(Proto.Code.SKILL_COOLDOWN, ls.language)))
	if h.chat_lines.size() > lines:
		h.chat_lines.pop_back()
	await _until(func(): return h.cool_fraction(122) == 0.0, 5.0)
	await _frames(2)
	_check("nach 3 s ist Hieb wieder bereit (Uhr weg)", h.cool_fraction(122) == 0.0 and cool != null and cool._left <= 0.0)
	# B26: die Aktion einer Fertigkeit läuft einmal (nachgeladene Aktionen der umgewandelten Figur liefen als Schleife weiter)
	var slash = w.player.anim.get_animation("战士_斩击") if w.player.anim.has_animation("战士_斩击") else null
	_check("Hieb-Aktion lief einmal (Schleife %s, jetzt '%s')" % [str(slash.loop_mode) if slash != null else "-",
		w.player.anim.current_animation], slash != null and slash.loop_mode == Animation.LOOP_NONE
		and w.player.anim.current_animation != "战士_斩击")
	# P3: GFX und Klänge der Fertigkeit lagen schon beim Betreten im Speicher (sonst ruckelt das erste Zaubern)
	var hieb_files = _action_files(w, "战士_斩击")
	var hieb_late = _late_loads(w, hieb_files)
	_check("Hieb ohne Nachladen: %d GFX / Klänge der Aktion vorab geladen, beim Zaubern nachgeladen %s" % [hieb_files.size(),
		str(hieb_late)], not hieb_files.is_empty() and hieb_late.is_empty())
	w.stop_attack()
	w.select_target(0)
	# Statuseffekte (F3) im Client: Meldungen buffs, hit mit buff (nur Zahl, sofort), heal (grüne Zahl)
	var mob = _nearest(w, BOAR)
	if mob != null:
		var mid: int = mob.id
		var labels = func(): return w.get_children().filter(func(c): return c is Label3D).size()
		var l0 = labels.call()
		w._on_pushed("buffs", {"id": mid, "list": [[583, 1, 5000, 5000]]})
		w._on_pushed("hit", {"src": me, "dst": mid, "dmg": 30, "miss": false, "crit": false, "buff": 583, "hp": 100, "max_hp": 426})
		w._on_pushed("heal", {"src": me, "dst": me, "amount": 50, "buff": 120, "hp": int(h.stats.get("hp", 1)), "max_hp": int(h.stats.get("max_hp", 1))})
		var l1 = labels.call()
		var b: Array = w.buffs.get(mid, [])
		var left = int(b[0][2]) - Time.get_ticks_msec() if not b.is_empty() else -1
		_check("Client merkt sich Brennen am Monster (Rest %d ms), Brand-Schaden und Heilung als Zahlen sofort (%d neu)" % [left, l1 - l0],
			not b.is_empty() and int(b[0][0]) == 583 and left > 4500 and left <= 5000 and l1 - l0 == 2)
		w._on_pushed("buffs", {"id": mid, "list": []})
		_check("leere Liste: Effekte weg", not w.buffs.has(mid))
		await _buff_display(w, mob)
		await _seal_display(w, mob)
		await _start_skills(w)
		await _passive_switch(w)
		await _skill_window(w)

# Anzeige der Statuseffekte (F4) mit Meldungen wie vom Server: Mentaler Fokus (64, Stärkung, 2 min) und 3 x
# Verteidigung reduziert (646, Schwächung, 15 s) an der eigenen Figur, Brennen (583, Sichtbar-Index 8) am gewählten
# Wildschwein
func _buff_display(w, mob) -> void:
	var h = w.hud
	var me = w.my_id
	var d = h.dlg(h.BUFF)
	var bd = w.buff_data
	if d == null or bd == null or not is_instance_valid(mob):
		_check("Win_Buff und Effekt-Daten da", false)
		return
	var mid: int = mob.id
	w.select_target(mid)
	await _until(func(): return w.target_id == mid and h.target_shown(), 3.0)
	w._on_pushed("buffs", {"id": me, "list": [[64, 1, 120000, 120000, -1], [646, 3, 15000, 15000, -1]]})
	w._on_pushed("buffs", {"id": mid, "list": [[583, 1, 5000, 5000, 8]]})
	await _frames(3)
	var b1: TextureRect = d.item("Img_Buff1")
	var b10: TextureRect = d.item("Img_Buff10")
	var stack = (b10.get_node("Stack") as Label).text
	_check("Win_Buff: Mentaler Fokus auf Platz 1 (%s), 3 x Verteidigung reduziert in der Schwächungs-Reihe auf Platz 10 (%s, Stapel %s), lang: %s" % [
		d.get_text("Txt_Time1"), d.get_text("Txt_Time10"), stack, d.get_text("Txt_Buff_Long")], b1.visible and b1.texture != null
		and b1.texture == bd.icon(64) and d.get_text("Txt_Time1") == "2 m" and b10.visible and b10.texture == bd.icon(646)
		and d.get_text("Txt_Time10") == "15 s" and stack == "3" and d.get_text("Txt_Buff_Long") == "0"
		and d.is_shown("Img_Debuff_Back_Sign_2") and not d.item("Img_Buff2").visible and d.is_shown("Img_Buff0"))
	var red = (d.item("Txt_Time10") as Label).get_theme_color("font_color")
	var normal = (d.item("Txt_Time1") as Label).get_theme_color("font_color")
	_check("Restzeit unter 30 s rot (%s), sonst in der Farbe des Dialogs (%s)" % [red, normal], red == Color(1, 0, 0) and normal != red)
	var td = h.dlg(h.TARGETS["monster"])
	var deb: TextureRect = td.item("debuff_1") if td != null else null
	var st: TextureRect = td.item("st_1") if td != null else null
	_check("Ziel-Fenster: Brennen in debuff_1 (%s), st_1 leer" % (str(deb.size) if deb != null else "-"), deb != null and st != null
		and deb.texture != null and deb.texture == bd.icon(583) and deb.size == Vector2(22, 22) and st.texture == null)
	b10.mouse_entered.emit()
	var tip = h.tooltip_text()
	b10.mouse_exited.emit()
	deb.mouse_entered.emit()
	var tip2 = h.tooltip_text()
	deb.mouse_exited.emit()
	var left = h.texts()["buff_left"].replace("%s", "")
	_check("Tooltips mit Text und Restzeit: '%s' / '%s'" % [tip.replace("\n", " | "), tip2.replace("\n", " | ")], tip.contains(bd.title(646))
		and tip.contains(left) and tip2.contains(bd.title(583)) and tip2.contains(left) and bd.title(583) != "")
	var nodes: Dictionary = w._buff_gfx.get(mid, {}).get("nodes", {})
	var fire = nodes.get(8)
	_check("Flammen-GFX (Sichtbar-Index 8, %s) am Wildschwein (%s)" % [str(bd.gfx(0, 0, 8)), fire.get_class() if fire != null else "-"],
		fire != null and is_instance_valid(fire) and mob.is_ancestor_of(fire) and fire.get_child_count() > 0)
	await _shot("21_buffs")
	w._on_pushed("buffs", {"id": me, "list": []})
	w._on_pushed("buffs", {"id": mid, "list": []})
	await _frames(2)
	_check("leere Listen: Win_Buff und Ziel-Fenster ohne Effekte, GFX weg", not b1.visible and not b10.visible and deb.texture == null
		and not w._buff_gfx.has(mid) and not is_instance_valid(fire))
	w.select_target(0)

# Kontrolle (F5) im Client mit einer Meldung seal wie vom Server: betäubt (root, silent, melee, idle)
func _seal_display(w, mob) -> void:
	var h = w.hud
	var p = w.player
	var all = {"root": true, "silent": true, "melee": true, "idle": true, "diet": false, "disarm": false, "invincible": false}
	w._on_pushed("seal", all)
	await _physics(3)
	var from = p.global_position
	_key(KEY_W, true)
	await create_timer(0.5).timeout
	_key(KEY_W, false)
	await _physics(3)
	var moved = Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length()
	var lines = h.chat_lines.size()
	_key(KEY_2, true)
	_key(KEY_2, false)
	await _until(func(): return h.chat_lines.size() > lines, 2.0)
	var skill_msg = h.chat_lines[-1] if h.chat_lines.size() > lines else "-"
	var cool = h.skill_control("bar0", 1).get_node_or_null("Cool")
	await _frames(2)
	var dim = cool != null and cool._dim
	lines = h.chat_lines.size()
	if is_instance_valid(mob):
		w.attack_target(mob.id)
	await _until(func(): return h.chat_lines.size() > lines, 2.0)
	var attack_msg = h.chat_lines[-1] if h.chat_lines.size() > lines else "-"
	_check("betäubt: W bewegt nicht (%.2f m), Taste 2 -> '%s', Hieb-Symbol dunkel (%s), Angriff -> '%s'" % [moved, skill_msg, str(dim), attack_msg],
		p.rooted and moved < 0.05 and skill_msg.contains(Proto.text(Proto.Code.SKILL_SEALED, ls.language)) and dim
		and attack_msg.contains(Proto.text(Proto.Code.ATTACK_SEALED, ls.language)) and w.attacking == 0)
	for i in 2:
		if not h.chat_lines.is_empty() and (h.chat_lines[-1].contains(Proto.text(Proto.Code.SKILL_SEALED, ls.language))
				or h.chat_lines[-1].contains(Proto.text(Proto.Code.ATTACK_SEALED, ls.language))):
			h.chat_lines.pop_back() # erwartete Meldungen (die Quests prüfen später: keine Fehlermeldung im Chat)
	var none = {}
	for k in all:
		none[k] = false
	w._on_pushed("seal", none)
	await _physics(2)
	from = p.global_position
	_key(KEY_W, true)
	await create_timer(0.4).timeout
	_key(KEY_W, false)
	await _physics(3)
	await _frames(2)
	moved = Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length()
	_check("wieder frei: W läuft (%.2f m), Hieb-Symbol hell" % moved, not p.rooted and moved > 0.5 and cool != null and not cool._dim)

# Startfertigkeiten (F6) im Client: Ansturm-Bewegung (Meldung skill_move wie vom Server) und das echte Stadtportal
func _start_skills(w) -> void:
	var h = w.hud
	var p = w.player
	var me = w.my_id
	var from = p.global_position
	var to = from + Vector3(4.0, 0.0, 0.0)
	w._on_pushed("skill_move", {"id": me, "pos": [to.x, to.y, to.z], "time": 400})
	await create_timer(0.2).timeout
	var mid_way = Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length()
	await create_timer(0.5).timeout
	var left = Vector2(p.global_position.x - to.x, p.global_position.z - to.z).length()
	_check("Ansturm (skill_move): die Figur gleitet in 0,4 s 4 m weit (nach 0,2 s %.1f m, am Ende %.2f m daneben)" % [mid_way, left],
		mid_way > 0.5 and mid_way < 3.9 and left < 0.3)
	await _physics(5)
	# kombinierte Aktionen (.ecm CombineActName -> BaseActName): jede eigene Fertigkeit hat ihre Aktion am Modell
	var acts = []
	var missing = []
	for k in w.skill_info:
		var a = str(w.skill_info[k].get("act", ""))
		if a != "":
			acts.append(w._weapon_act(a))
			if not p.anim.has_animation(acts[-1]):
				missing.append(acts[-1])
	_check("Aktionen aller eigenen Fertigkeiten gebaut (%s)" % ", ".join(acts), not acts.is_empty() and missing.is_empty())
	# Stadtpunkte auf ganze Meter gerundet (Werwolf s31 0,5 m unter dem Gelände): place setzt auf den Boden
	var ground = p.global_position
	var snapped = p.on_floor(ground - Vector3(0, 0.5, 0))
	_check("Aufsetzen: Punkt 0,5 m unter dem Boden -> %.2f m (Boden %.2f m)" % [snapped.y, ground.y], absf(snapped.y - ground.y) < 0.1)
	# Rückkehrstadt im Stadtportal-Text (GameApi.GetHostTownName, Gebiet am Stadtpunkt aus precinct.clt)
	var desc = Hud_plain(w.skill_data.bbcode(w.skill_data.desc(120, 1)))
	var town_name = str(w.skill_data.host_town)
	_check("Stadtportal-Text nennt die Rückkehrstadt '%s' (Stadtpunkte %s)" % [town_name, str(w.towns)],
		town_name != "" and desc.contains(town_name) and not desc.contains("nil") and w.towns.has(Vector3(-151.0, 102.0, 42.0)))
	var name = Hud_plain(w.skill_data.skill_name(120))
	var n0 = h.chat_lines.size()
	var corrections = _corrections
	w.use_skill(120)
	await _until(func(): return w.casting.has("end"), 3.0)
	await _frames(3)
	var bar = str(h.dlg(h.PROGRESS).get_text("Txt_info")) if h.progress_shown() else ""
	var act = str(p.anim.current_animation)
	var loop = p.anim.has_animation(act) and p.anim.get_animation(act).loop_mode != Animation.LOOP_NONE
	var events = p.model.get_meta("action_events", {}).get(act, []).map(func(e): return str(e["files"][0]).get_file())
	await create_timer(5.0).timeout
	var fx_mid = w.attack_fx._event_nodes.get(p.get_instance_id(), []).filter(func(n): return is_instance_valid(n)).size()
	await _until(func(): return w.casting.is_empty(), 13.0)
	await _physics(5)
	var fx_after = w.attack_fx._event_nodes.get(p.get_instance_id(), []).filter(func(n): return is_instance_valid(n) and not n.is_queued_for_deletion()).size()
	var town = Vector3(-151.0, 102.0, 42.0)
	var dist = Vector2(p.global_position.x - town.x, p.global_position.z - town.z).length()
	_corrections = corrections # das Portal versetzt per pos_correct (erwartet)
	_check("Stadtportal: Balken '%s', Aktion %s (Schleife %s), danach am Stadtpunkt (%.1f m)" % [bar, act, str(loop), dist],
		bar.contains(name) and act.begins_with("回城") and loop and dist < 1.5 and h.chat_lines.size() == n0)
	_check("Stadtportal-GFX: %s, nach 5 s noch %d laufend, am Ende %d" % [str(events), fx_mid, fx_after],
		events.has("回城循环.gfx") and fx_mid > 0 and fx_after == 0)
	await _shot("22_portal")

# Treffer sichtbar: Leben im Ziel-Fenster gesunken (bzw. verfehlt); zählt nebenbei die meisten schwebenden Zahlen
func _hit_shown(w, seen: Array, bar, first_hit: Dictionary) -> bool:
	seen[0] = maxi(int(seen[0]), w.get_children().filter(func(c): return c is Label3D).size())
	return bar == null or bar.value < 100.0 or first_hit.get("miss", false) or _one_shot(first_hit)

# Der erste Schlag hat das Wildschwein gleich getötet (Krit: 426 Leben): kein sinkender Balken, das Modell kann schon weg sein
static func _one_shot(first_hit: Dictionary) -> bool:
	return first_hit.has("hp") and int(first_hit["hp"]) <= 0

# K-Fenster mit Reitern (F8) und C-Abschnitt Meisterschaft / Widerstand
const TAB_X_EXPECTED = [19.0, 92.0, 165.0, 238.0, 311.0, 384.0]

func _skill_window(w) -> void:
	var h = w.hud
	var t = h.texts()
	h.close_window(h.SKILLS)
	h.skill_tab = "class"
	h.open_window(h.SKILLS)
	await _frames(3)
	var d = h.dlg(h.SKILLS)
	var radios = ["Rdo_Produce", "Rdo_MainInitiative", "Rdo_Race", "Rdo_SkillScience", "Rdo_Tree", "Rdo_Belief"]
	var labels = radios.map(func(n): return str(d.get_text(n)))
	var want = ["basic", "class", "race", "jobs", "talent", "soul"].map(func(k): return str(t["tab_" + k]))
	var xs = radios.map(func(n): return d.item(n).position.x if d.item(n) != null else -1.0)
	var ordered = xs == TAB_X_EXPECTED
	var lists = h.tab_skills("class")
	var all_class = lists[0] + lists[1]
	var shown = []
	var unknown_lv = ""
	for i in h._view_slots:
		if d.item("Name_%d" % (i + 1)).visible:
			shown.append(h.skill_at("skill", i))
			if not h.skill_state["skills"].has(h.skill_at("skill", i)) and unknown_lv == "":
				unknown_lv = d.get_text("Lv_%d" % (i + 1))
	_check("K: Reiter %s an %s, Klasse: %d Fertigkeiten (%d gezeigt), noch nicht gelernt: '%s'" % [str(labels), str(xs),
		all_class.size(), shown.size(), unknown_lv], labels == want and ordered and d.visible and all_class.size() >= 13
		and shown.size() == all_class.size() and shown.has(122) and unknown_lv == t["skill_from"] % 10
		and d.item("Lv_%d" % (shown.find(124) + 1)).get_theme_color("font_color") == h.SKILL_NEED_COLOR) # noch nicht gelernt: rot
	(d.item("Rdo_Race") as BaseButton).button_pressed = true # der kopierte Reiter schaltet selbst um
	await _frames(2)
	var race_ids = h._view_ids.filter(func(x): return int(x) != 0)
	var lv_bless = d.get_text("Lv_%d" % (h._view_ids.find(2497) + 1)) if h._view_ids.has(2497) else "-"
	var lv_prayer = d.get_text("Lv_%d" % (h._view_ids.find(1958) + 1)) if h._view_ids.has(1958) else "-"
	var prayer_known = h.skill_state["skills"].has(1958)
	_check("Reiter Rasse: %s - Segen der Menschen zuerst ('%s', erst ab Stufe 10), Gebet ('%s'), dann Stadtportal (Z1)" % [str(race_ids), lv_bless, lv_prayer],
		h.skill_tab == "race" and race_ids.slice(0, 2) == [2497, 1958] and race_ids.has(120) and not race_ids.has(122)
		and lv_bless == t["skill_quest"] and lv_prayer == (t["skill_lv"] % 1 if prayer_known else t["skill_quest"]))
	h.select_tab("basic")
	await _frames(2)
	var b = h.dlg(h.BASE_SKILLS)
	var icon = b.item("Cmd_01").get_node_or_null("Symbol") if b != null and b.item("Cmd_01") != null else null
	_check("Reiter Grundlagen: '%s' mit Symbol %s, Win_Skill aus" % [b.get_text("Txt_01") if b != null else "-", str(icon != null and icon.texture != null)],
		b != null and b.visible and not d.visible and b.get_text("Txt_01") == t["basic_attack"] and icon != null and icon.texture != null)
	h.select_tab("talent")
	await _frames(2)
	var hint = h.dlg(h.TALENT_HINT)
	var talent_text = hint.get_text("Lab_Explain") if hint != null else "-"
	var talent_ok = hint != null and hint.visible and talent_text.contains("20") and h.skill_tab == "basic"
	hint.send("Btn_Close")
	h.select_tab("soul")
	await _frames(2)
	var soul_text = hint.get_text("Lab_Explain")
	_check("Talent / Seele unter der Stufe: '%s' / '%s', Reiter bleibt %s" % [talent_text, soul_text, h.skill_tab],
		talent_ok and hint.visible and soul_text.contains("60") and h.skill_tab == "basic")
	await _shot("24_skills")
	h.close_window(h.SKILLS)
	await _frames(1)
	var closed = not h.window_open(h.SKILLS) and not hint.visible
	h.open_window(h.CHARACTER)
	await _frames(2)
	var c = h.dlg(h.CHARACTER)
	var cd = h.dlg(h.CHARACTER_DETAIL)
	var at = c.position
	(c.item("Rdo_Reputation") as BaseButton).button_pressed = true
	await _frames(2)
	var page = cd != null and cd.visible and not c.visible and cd.position == at and h.window_open(h.CHARACTER) \
		and (cd.item("Rdo_Reputation") as BaseButton).button_pressed
	# Grundwerte wie der Server (stats.gd: Klasse, Stufe, mas_res_modify) - Krieger: physisch und Wind > 0, Feuer 0, PvE 0
	var a: Dictionary = h.stats.get("attr", {})
	var mas = range(8).map(func(i): return cd.get_text("Txt_Mas%02d" % i) if cd != null else "-")
	var res = range(8).map(func(i): return cd.get_text("Txt_Res%02d" % i) if cd != null else "-")
	var want_mas = (a.get("mas", []) as Array).map(func(x): return str(int(x)))
	var want_res = (a.get("res", []) as Array).map(func(x): return str(int(x)))
	await _shot("25_character_detail")
	(cd.item("Rdo_Title") as BaseButton).button_pressed = true
	await _frames(2)
	var back = c.visible and not cd.visible and c.position == at
	_check("C: Rdo_Reputation -> Win_CharacterDetail an derselben Stelle %s, Meisterschaft %s, Widerstand %s (Server %s / %s), zurück %s; K geschlossen %s" % [
		str(page), str(mas), str(res), str(want_mas), str(want_res), str(back), str(closed)], page and back and closed and mas == want_mas
		and res == want_res and int(mas[0]) > 0 and int(mas[4]) > 0 and mas[3] == "0" and mas[7] == "0" and res[7] == "0")
	h.close_window(h.CHARACTER)

# Neu gelernte (Testbefehl) gleich weglegen, wie Ziehen aus "Neue Fertigkeiten": sonst öffnet sich das Fenster
func _seen(h, ids: Array) -> void:
	h.skills_seen(ids)
	h.skills_seen_requested.emit(ids)

# Passive Fertigkeiten und Schalter (F7) im Client; Lernen per Testbefehl (der Testserver erlaubt debug_commands)
func _passive_switch(w) -> void:
	var h = w.hud
	var r = await w.session.debug_skill(131, 2) # Krieger: Stärken (passiv, Leben +2 %)
	await _until(func(): return w.skill_info.has("131") and h.skill_state["skills"].has(131), 3.0)
	_seen(h, [131])
	var listed = h.skill_list().has(131)
	var drop = h._skill_can_drop(Vector2.ZERO, {"skill": 131, "from": "skill", "idx": 0}, "bar0", 9)
	var lines = h.chat_lines.size()
	w.use_skill(131)
	await _frames(2)
	var said = h.chat_lines[-1] if h.chat_lines.size() > lines else "-"
	if h.chat_lines.size() > lines:
		h.chat_lines.remove_at(h.chat_lines.size() - 1) # gewollte Meldung: zählt nicht für "keine Fehlermeldung im Chat"
	_check("Passiv 131: im K-Fenster %s, auf eine Leiste %s, einsetzen: %s" % [str(listed), str(drop), said],
		r["code"] == Proto.Code.OK and w.skill_info["131"].get("passive", false) and listed and not drop
		and said.contains(Proto.text(Proto.Code.SKILL_PASSIVE, ls.language)))
	r = await w.session.debug_skill(2093, 1) # Schalter Wirkungstreffer-Zeit (Schütze; Effekte ohne Klassen-Grenze)
	await _until(func(): return w.skill_info.has("2093") and h.skill_state["skills"].has(2093), 3.0)
	_seen(h, [2093])
	h.shortcut_requested.emit(0, 9, 2093)
	await _until(func(): return h.skill_at("bar0", 9) == 2093, 3.0)
	var cool = h.skill_control("bar0", 9).get_node_or_null("Cool")
	w.use_skill(2093)
	await _until(func(): return h.switched.has(2093), 3.0)
	await _frames(3)
	var framed = cool != null and cool._on
	var buffs_on = w.buffs.get(w.my_id, []).map(func(x): return int(x[0]))
	await _until(func(): return w.casting.is_empty(), 3.0)
	w.use_skill(2093) # erneut: aus (auch in der Abklingzeit)
	await _until(func(): return not h.switched.has(2093), 3.0)
	await _frames(3)
	_check("Schalter 2093: an mit Rahmen %s (Effekte %s), erneut eingesetzt aus (Rahmen %s, Abklingzeit %.0f %%)" % [str(framed),
		str(buffs_on), str(cool._on if cool != null else null), h.cool_fraction(2093) * 100.0],
		r["code"] == Proto.Code.OK and framed and buffs_on.has(88) and not h.switched.has(2093) and cool != null and not cool._on)
	h.shortcut_requested.emit(0, 9, 0)
	await _shot("23_switch")

# Gebet (Z2) im Laufen: kein Zauberbalken, keine Aktion, die Figur läuft weiter; Mana +25 %, Effekt 1113 mit dem GFX
# light 16 (免疫控制技.gfx: der blaue Kreis an den Füßen)
func _gone_or_dead(ref: WeakRef) -> bool:
	var n = ref.get_ref()
	return n == null or n.dead

func _prayer(w) -> void:
	await _stale_cast_hit(w)
	var h = w.hud
	var r = await w.session.debug_skill(1958, 1)
	await _until(func(): return w.skill_info.has("1958") and h.skill_state["skills"].has(1958), 3.0)
	_seen(h, [1958])
	await w.session.debug_state(1102, 0, 1000, [100000]) # Mana leeren
	await _until(func(): return int(h.stats.get("mp", -1)) == 0, 3.0)
	await _until(func(): return w.casting.is_empty(), 3.0)
	var p = w.player
	# auf einer Autoroute (Wegfindung, ohne Hindernis-Stau) zu einem bekannten NPC laufen, der entfernteste zuerst; kommt
	# die Figur von hier aus nicht los (Route ohne Fortschritt), das nächste Ziel
	var goals = []
	for tid in [VESTRY, ADAM, JOHNNY]:
		var wh: Array = w.quest_data.npc_pos.get(tid, [])
		if wh.size() == 2 and int(wh[0]) == int(w.info.get("world", 0)):
			goals.append([(wh[1] as Vector3).distance_to(p.global_position), wh[1], tid])
	goals.sort_custom(func(a, b): return a[0] > b[0])
	var far = 0.0
	var tries = []
	for g in goals:
		w.route_to(g[1], "Gebet-Test")
		var chat_n = w.hud.chat_lines.size()
		var follows = await _until_ok(func(): return p.following(), 5.0)
		var start = p.global_position
		var moves = await _until_ok(func(): return start.distance_to(p.global_position) > 1.0, 3.0)
		var keys = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT].filter(func(k): return Input.is_physical_key_pressed(k))
		var said = w.hud.chat_lines.slice(chat_n).map(func(l): return Hud_plain(l))
		tries.append("%d: %.0f m, Weg %s, läuft %s%s" % [g[2], g[0], str(follows), str(moves), "" if moves else
			" [gewurzelt %s, Tasten %s, tot %s, Zauber %s, Boden %s, bei %s, Chat %s]" % [str(p.rooted), str(keys), str(p.dead),
			str(w.casting), str(p.is_on_floor()), str(p.global_position.snapped(Vector3.ONE * 0.1)), str(said)]])
		if moves:
			far = g[0]
			break
		w.cancel_route()
		await _frames(2)
	# erst zaubern, wenn die Figur sicher unterwegs ist (3 m oder hinter dem 2. Wegpunkt) - früher blieb sie am Wiederbelebungspunkt
	# von s9 unter dem Balken einer Bude hängen (Kollision höher als im Original, B2; behoben 22.11.)
	# und nur, wenn sie gerade wirklich läuft: an der Seitenwand derselben Bude stand sie schon bei Wegpunkt 2 still (23.11., die
	# Wegekarte kennt die dünne Wand nicht) - der Ausweichschritt kommt erst nach ROUTE_STUCK_TIME (1,2 s), darum bis 6 s warten
	var go_from = p.global_position
	var t_go = Time.get_ticks_msec() + 6000
	var recent: Array = []
	while Time.get_ticks_msec() < t_go:
		await process_frame
		recent.append(p.global_position)
		if recent.size() > 10:
			recent.pop_front()
		if not p.following():
			break
		var moving = recent.size() >= 10 and Vector2(recent[-1].x - recent[0].x, recent[-1].z - recent[0].z).length() > 0.3
		if moving and (p.path_index >= 2 or Vector2(p.global_position.x - go_from.x, p.global_position.z - go_from.z).length() >= 3.0):
			break
	var from = p.global_position
	w.use_skill(1958)
	await _frames(3)
	var bar = h.progress_shown()
	var act = str(p.anim.current_animation) if p.anim != null else "-"
	# 0,6 s beobachten: Sprünge (pos_correct des Servers), Stillstand (Diagnose für den alten Wackler)
	var t_end = Time.get_ticks_msec() + 600
	var last_pos = p.global_position
	var jump = 0.0
	var still_frames = 0
	var frames_n = 0
	while Time.get_ticks_msec() < t_end:
		await process_frame
		var step = Vector2(p.global_position.x - last_pos.x, p.global_position.z - last_pos.z).length()
		jump = maxf(jump, step)
		if step < 0.001:
			still_frames += 1
		frames_n += 1
		last_pos = p.global_position
	var hits = []
	for k in p.get_slide_collision_count():
		var col = p.get_slide_collision(k).get_collider()
		var nm = (str(col.name) + " (" + col.get_class() + ")") if col != null else "-"
		if not nm in hits:
			hits.append(nm)
	var diag = "Zustand %s, Tempo %.2f, verwurzelt %s, Weg %s (Punkt %d / %d), Ziel %s, Zaubern %s, Einmal '%s', größter Schritt %.2f m, still %d von %d Bildern, stößt an %s, bei %s" % [
		str(p.state), Vector2(p.velocity.x, p.velocity.z).length(), str(p.rooted), str(p.following()), int(p.path_index), p.path.size(),
		str(p.target != null), str(w.casting.keys()), str(p._once), jump, still_frames, frames_n, str(hits), str(p.global_position.snapped(Vector3.ONE * 0.1))]
	var moved = Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length()
	var still_target = w.routing()
	var mine = w.buffs.get(w.my_id, []).filter(func(x): return int(x[0]) == 1113)
	var gfx = w._buff_gfx.get(w.my_id, {}).get("nodes", {}).has(16)
	var mp = int(h.stats.get("mp", 0))
	var max_mp = int(h.stats.get("max_mp", 1))
	w.cancel_route()
	_check("Gebet im Laufen (Autoroute, %.0f m; %s): %s, Zauberbalken %s, Aktion '%s', weitergelaufen %.1f m (Route bleibt %s), Effekt 1113 %s, GFX 16 %s, Mana 0 -> %d / %d%s" % [
		far, " / ".join(tries), Proto.text(r["code"]), str(bar), act, moved, str(still_target), str(not mine.is_empty()), str(gfx), mp, max_mp,
		(" (Ausweichschritte %d)" % w.escapes) if moved > 1.0 else " [" + diag + ", Ausweichschritte %d, Wandsperren %d]" % [w.escapes, w.blocked_contacts]],
		r["code"] == Proto.Code.OK and not bar and not act.begins_with("祈祷") and moved > 1.0 and still_target and not mine.is_empty() and gfx
		and mp >= int(max_mp * 0.25))
	# P3: das GFX des Statuseffekts (16) lag schon beim Betreten im Speicher
	var c: Dictionary = w.info["char"]
	var g16: Array = w.buff_data.gfx(int(c["race"]), int(c["class"]), 16) if w.buff_data != null else []
	var g16_late = _late_loads(w, [str(g16[0])] if not g16.is_empty() else [])
	_check("Gebet ohne Nachladen: GFX des Statuseffekts %s vorab geladen (nachgeladen %s)" % [str(g16[0]).get_file() if not g16.is_empty() else "-",
		str(g16_late)], not g16.is_empty() and w.attack_fx._gfx.has(str(g16[0])) and g16_late.is_empty())
	await _shot("24_prayer")

# Z5: Geschenk-Knopf öffnet Shylias Markt auf "Erhalten"; Reiter mit den Texten des Spiels; "Gratis EXP": Orangener Cocktail
# (12784) annehmbar, Gelber (12785, Stufe 20) gesperrt, Essenz-Anzahl; Knopf tauscht (Cocktail in der Tasche, eine Essenz
# weniger); Rechtsklick auf den Cocktail: Leiste "Trinken", danach EXP im Chat
func _market(w) -> void:
	var h = w.hud
	var count = func(id: int) -> int:
		var n = 0
		for pos in h.inventory["bag"]:
			if int(h.inventory["bag"][pos][0]) == id:
				n += int(h.inventory["bag"][pos][1])
		return n
	var ess0 = count.call(h.ESSENCE)
	h.dlg("WinMain3").send("Btn_Gift_Lua")
	await _frames(3)
	var d = h.dlg(h.LVUP)
	var tabs = h.LVUP_TABS.map(func(n): return d.get_text("Rdo_1_%d" % n) if d != null else "")
	_check("Geschenk-Knopf öffnet Shylias Markt auf 'Erhalten' (Reiter %s, %d Einträge, Essenzen %d)" % [str(tabs),
		h._lvup_entries.size(), ess0], h.lvup_open() and h.lvup_tab == h.LVUP_OPEN_TAB and tabs.all(func(x): return str(x) != "")
		and not h._lvup_entries.is_empty() and ess0 >= 1 and h.dlg("WinMain3").is_shown("Btn_Gift_Lua"))
	d.send("Rdo_1_3")
	await _frames(2)
	var ids = h._lvup_entries.map(func(e): return int(e.get("taskid", 0)))
	var orange = ids.find(12784) + 1
	var yellow = ids.find(12785) + 1
	var warn = d.get_text("Warning")
	_check("Reiter 3 ('%s'): Quests %s, Orangener Cocktail '%s' annehmbar, Gelber gesperrt (Stufe 20), Anzeige '%s'" % [
		d.get_text("Rdo_1_3"), str(ids), d.get_text("Name_%d" % orange) if orange > 0 else "-", warn], orange > 0 and yellow > 0
		and d.is_shown("Name_%d" % orange) and (d.item("Btn_%d" % orange) as BaseButton).disabled == false
		and (d.item("Btn_%d" % yellow) as BaseButton).disabled and warn.ends_with(str(ess0)))
	await _shot("25_market")
	d.send("Btn_%d" % orange)
	await _until(func(): return count.call(9056) == 1, 5.0)
	_check("Tausch: Cocktail in der Tasche (%d), Essenzen %d -> %d, Anzeige '%s'" % [count.call(9056), ess0, count.call(h.ESSENCE),
		d.get_text("Warning")], count.call(9056) == 1 and count.call(h.ESSENCE) == ess0 - 1 and d.get_text("Warning").ends_with(str(ess0 - 1)))
	d.send("Btn_Close")
	var pos = -1
	for p in h.inventory["bag"]:
		if int(h.inventory["bag"][p][0]) == 9056:
			pos = p
	var exp_lines = h.chat_lines.size()
	_right_click(h._slot_control("bag", pos)) # Rechtsklick in der Tasche (echter Weg über hud._on_slot_input)
	await _until(func(): return h.progress_shown(), 3.0)
	var desc = str(w.using.get("desc", ""))
	var bar = h.progress_shown()
	await _until(func(): return count.call(9056) == 0 and not h.progress_shown(), 6.0)
	var gained = h.chat_lines.slice(exp_lines).filter(func(l): return l.contains("EXP"))
	_check("Rechtsklick: Leiste '%s' (%s), danach Cocktail weg, Chat %s" % [desc, str(bar), str(gained.map(func(l): return Hud_plain(l)))],
		bar and desc != "" and not h.progress_shown() and count.call(9056) == 0 and not gained.is_empty() and not h.lvup_open())
	await _items(w)

# Gegenstände (B1): Essenz-Tooltip, nicht zerstörbar, Rechtsklick ohne Wirkung; zweiter Cocktail aus dem Markt wird über
# Btn_Destroy + Klick zerstört (Meldungsfenster mit dem Namen, OK)
func _items(w) -> void:
	var h = w.hud
	var pos_of = func(id: int) -> int:
		for p in h.inventory["bag"]:
			if int(h.inventory["bag"][p][0]) == id:
				return p
		return -1
	var epos = pos_of.call(h.ESSENCE)
	if not h.window_open(h.INVENTORY):
		h.open_window(h.INVENTORY)
	h._on_slot_hover("bag", epos)
	var tip: String = h.tooltip_text()
	var ess_name = Hud_plain(w.item_data.info(h.ESSENCE)["name"])
	var ext = Hud_plain(w.item_data.desc.ext_desc(h.ESSENCE)) if w.item_data.desc != null else ""
	_check("Essenz-Tooltip: Name, Preis mit Münz-Symbol, Zusatztext (%s)" % tip.replace("\n", " | "), epos >= 0 and tip.contains(ess_name)
		and h._tooltip_text.text.count("[img") >= 2 and ext != "" and tip.contains(ext.replace("\\r", "\r").get_slice("\r", 0).strip_edges())) # Zeilen als "\\r" (item_ext_desc.txt)
	h.hide_tooltip()
	var n_ess = int(h.inventory["bag"].get(epos, [0, 0])[1])
	var lines = h.chat_lines.size()
	h.ask_destroy(epos) # wie Ziehen in die Welt / auf Btn_Destroy
	_right_click(h._slot_control("bag", epos))
	await _frames(10)
	var said = h.chat_lines.slice(lines).map(func(l): return Hud_plain(l))
	_check("Essenz nicht zerstörbar: Hinweis %s, kein Fenster, Rechtsklick ohne Wirkung (Anzahl %d)" % [str(said), n_ess],
		not h.aui.has_message_box() and not h.destroy_open() and said.any(func(l): return l.contains(h.texts()["cant_destroy"]))
		and int(h.inventory["bag"].get(epos, [0, 0])[1]) == n_ess and h.inventory["bag"].get(epos, [0])[0] == h.ESSENCE)
	# zweiter Cocktail aus dem Markt, dann zerstören
	h.open_lvup(3)
	await _frames(2)
	var ids = h._lvup_entries.map(func(e): return int(e.get("taskid", 0)))
	var orange = ids.find(12784) + 1
	if orange > 0:
		h.dlg(h.LVUP).send("Btn_%d" % orange)
	await _until(func(): return pos_of.call(9056) >= 0, 5.0)
	h.close_lvup()
	var cpos = pos_of.call(9056)
	var inv = h.dlg(h.INVENTORY)
	inv.send("Btn_Destroy")
	var mode = h.destroy_mode
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	h._slot_control("bag", cpos).gui_input.emit(click)
	await _until(func(): return h.aui.has_message_box(), 3.0)
	var box = h.aui._top.get_child(h.aui._top.get_child_count() - 1) if h.aui.has_message_box() else null
	var text = Hud_plain(box.get_text("Txt_Message")) if box != null else ""
	var cname = Hud_plain(w.item_data.info(9056)["name"])
	await _shot("26_destroy")
	lines = h.chat_lines.size()
	if box != null:
		box.send("IDOK")
	await _until(func(): return pos_of.call(9056) < 0, 5.0)
	await _frames(5)
	said = h.chat_lines.slice(lines).map(func(l): return Hud_plain(l))
	_check("Btn_Destroy (Modus %s) + Klick: Frage '%s', OK -> Cocktail weg, Chat %s, Modus aus" % [mode, text, str(said)], cpos >= 0
		and mode and text.contains(cname) and not h.destroy_mode and pos_of.call(9056) < 0
		and said.any(func(l): return l.contains(cname)))
	# Fertigkeits-Gegenstand (B17): Blut des Werwolfgottes per Rechtsklick wirkt 4572 (Zauberbalken mit dem Namen), dann
	# Effekt 2886 an der eigenen Figur, das Blut bleibt (permenent)
	var grey_icon = _tomb_icon(w)
	var gave = await ls.session.debug_item(BLOOD, 1)
	await _until(func(): return pos_of.call(BLOOD) >= 0, 5.0)
	var bpos = pos_of.call(BLOOD)
	var bname = Hud_plain(w.item_data.info(BLOOD)["name"])
	_right_click(h._slot_control("bag", bpos))
	await _until(func(): return w.casting.has("end"), 3.0)
	var bar = str(w.casting.get("name", ""))
	var has_state = func(): return w.buffs.get(w.my_id, []).any(func(b): return int(b[0]) == BLOOD_STATE)
	await _until(func(): return w.casting.is_empty() and has_state.call(), 5.0)
	_check("Blut des Werwolfgottes (%s, Platz %d): Rechtsklick zaubert '%s', danach Effekt %d, Blut bleibt" % [
		Proto.text(gave["code"]), bpos, bar, BLOOD_STATE], gave["code"] == Proto.Code.OK and w.item_data.info(BLOOD).get("use", false)
		and bar == bname and has_state.call() and pos_of.call(BLOOD) == bpos)
	# B20: das Grab zeigt "Lauscht dem Ruf" grau, bis der Blut-Effekt da ist (need_buffs), dann gelb (wie CECNPCServer)
	var qd = w.quest_data
	var topic = qd.topic(qd.task(WOLF_CALL))
	var yellow_icon = _tomb_icon(w)
	_check("Grab des Werwolf-Gottes (Werwolf, 15358 läuft): ohne Blut-Effekt '%s' (graues !), mit '%s' (gelbes !)" % [grey_icon,
		yellow_icon], grey_icon != "" and grey_icon == str(qd.icons.get([qd.QBT_CAN_NOT_GET, topic], "-"))
		and yellow_icon == str(qd.icons.get([qd.QBT_CAN_GET, topic], "-")))
	await _dice_place(w, ls, pos_of)
	# Verfolgung einer "Quest erfüllen"-Quest (Methode 11): 15358 "Segen des Wolfs" verlinkt das Grab des Werwolf-Gottes
	# (vergibt 15396 "Lauscht dem Ruf"), solange 15396 nicht läuft
	var parts = w.quest_data.goal_parts(w.quest_data.task(WOLF_BLESSING))
	_check("15358 'Segen des Wolfs': Ziel %s führt zum Grab des Werwolf-Gottes (npc:%d)" % [str(parts), WOLF_TOMB],
		parts.size() == 1 and parts[0]["link"] == "npc:%d" % WOLF_TOMB and str(parts[0]["text"]).ends_with("0/1"))

# Quest-Würfel mit Ort (B22): die Giftige Bombe 14548 gilt nur in s9 in der Box um (80 | 83 | 103), halbe Kanten 10. Außerhalb
# nennt der Client per Rechtsklick die Richtung (DEST_* der Spieldaten, dazu der Abstand) und schickt nichts; die Richtung an
# einigen Stellen (Figur dafür kurz versetzt, ohne Bild dazwischen); in 50 m Nähe das Hinweis-Modell an der Mitte; der Samen
# 43953 (s31) meldet auf s9 "nicht auf dieser Karte"
func _dice_place(w, ls, pos_of: Callable) -> void:
	var h = w.hud
	var gave = await ls.session.debug_item(BOMB, 1)
	await _until(func(): return pos_of.call(BOMB) >= 0, 5.0)
	var bpos = pos_of.call(BOMB)
	var before = h.chat_lines.size()
	_right_click(h._slot_control("bag", bpos))
	await _frames(10)
	var said = h.chat_lines.slice(before).map(func(l): return Hud_plain(l))
	var dest = func(key): return str(h.game_text(key))
	var real_text = w.dice_place_text(w.item_data.info(BOMB))
	_check("Giftige Bombe (%s) per Rechtsklick außerhalb ihres Orts: Chat %s, kein Benutzen (%s), Bombe bleibt" % [
		Proto.text(gave["code"]), str(said), w.using.is_empty()], gave["code"] == Proto.Code.OK and real_text != ""
		and said.any(func(l): return l.contains(real_text.left(12))) and w.using.is_empty() and pos_of.call(BOMB) == bpos
		and not real_text.unicode_at(0) >= 0x3000)
	var info = w.item_data.info(BOMB)
	var keep: Vector3 = w.player.global_position
	var at = func(v: Vector3) -> String:
		w.player.global_position = v
		var t = w.dice_place_text(info)
		w.player.global_position = keep
		return t
	var north = at.call(Vector3(80, 83, 60))
	var ne = at.call(Vector3(30, 83, 50))
	var sw = at.call(Vector3(130, 83, 150))
	var down = at.call(Vector3(80, 120, 103))
	var inside = at.call(Vector3(80, 83, 103))
	var hint = w._dice_hint.get("node")
	w._update_dice_hint()
	var d = Vector2(keep.x - 80.0, keep.z - 103.0).length()
	var other = w.dice_place_text(w.item_data.info(SEED))
	_check("Richtungen: Norden '%s', Nordosten '%s', Südwesten '%s', darunter '%s', in der Box '%s'; Samen auf s9 '%s'" % [north, ne,
		sw, down, inside, other], dest.call("DEST_NORTH") != "" and north == dest.call("DEST_NORTH") + h.texts()["dest_dist"] % 43
		and ne.begins_with(dest.call("DEST_NORTHEAST")) and sw.begins_with(dest.call("DEST_SOUTHWEST"))
		and down == dest.call("DEST_DOWNSIDE") and inside == "" and other == dest.call("DEST_ERRINSTANCE"))
	_check("Hinweis-Modell %s an der Mitte (80 | 83 | 103): %s, sichtbar %s, Maßstab %.2f (2 + %.0f / 120 * 4)" % [
		str(hint.name) if is_instance_valid(hint) else "-", str(hint.global_position) if is_instance_valid(hint) else "-",
		hint.visible if is_instance_valid(hint) else false, hint.scale.x if is_instance_valid(hint) else 0.0, d],
		is_instance_valid(hint) and hint.global_position.distance_to(Vector3(80, 83, 103)) < 0.01 and hint.visible == (d < 120.0)
		and absf(hint.scale.x - (2.0 + d / 120.0 * 4.0)) < 0.01)

# Symbol über dem Grab des Werwolf-Gottes, als wäre die Figur ein Werwolf mit laufendem 15358 (Zustand nur für diese
# Probe, ohne await dazwischen wieder hergestellt); Effekte sind die echten der eigenen Figur
func _tomb_icon(w) -> String:
	var qd = w.quest_data
	var keep = [qd.player, qd.active, qd.done]
	qd.player = keep[0].duplicate()
	qd.player["race"] = 6
	qd.active = {WOLF_BLESSING: {}}
	qd.done = {15355: true, 15357: true}
	var icon = qd.head_icon(WOLF_TOMB)
	qd.player = keep[0]
	qd.active = keep[1]
	qd.done = keep[2]
	return icon

# Treffer einer Sofort-Fertigkeit (B10): der Treffer von Gebet 1958 kommt vor der Antwort aufs Zaubern; die gemerkte Aktion
# einer anderen Fertigkeit (hier eine mit Angriffspunkten) darf dann nicht abgespielt werden - vorher bekam der Magier nach
# dem Feuerball beim Gebet einen Feuerball-Treffer ab
func _stale_cast_hit(w) -> void:
	var pts: Dictionary = w.player.model.get_meta("attack_points", {}) if w.player.model != null else {}
	var stale = ""
	for a in pts:
		if not (pts[a] as Array).is_empty():
			stale = str(a)
			break
	var spawned = []
	var watch = func(n): spawned.append(n)
	w.attack_fx.child_entered_tree.connect(watch)
	var keep = w._casts.get(w.my_id, {})
	w._casts[w.my_id] = {"act": stale, "start": Time.get_ticks_msec(), "skill": 122}
	w._on_hit({"src": w.my_id, "dst": w.my_id, "skill": 1958, "bless": true, "dmg": 0, "hp": int(w.hud.stats.get("hp", 1)),
		"max_hp": int(w.hud.stats.get("max_hp", 1))})
	await _physics(90)
	w.attack_fx.child_entered_tree.disconnect(watch)
	w._casts[w.my_id] = keep
	_check("Sofort-Treffer (Gebet) mit gemerkter Aktion '%s' einer anderen Fertigkeit: keine Angriffs-GFX (%d)" % [stale, spawned.size()],
		stale != "" and spawned.is_empty())

# Mana vor der Wirkung (letztes stats davor, auch Regeneration) und direkt danach (stats nach cooldown)
func _skill_push(what: String, d: Dictionary) -> void:
	if what == "cooldown" and int(d.get("id", 0)) == 122:
		_sk_cool = true
	elif what == "stats" and d.has("mp"):
		if not _sk_cool:
			_sk_mp[0] = int(d["mp"])
		elif _sk_mp[1] < 0:
			_sk_mp[1] = int(d["mp"])

# Magier-Fertigkeit Feuerball an einer gebauten Figur: angelica_player.gd add_actions baut die Aktion 法师_火球术
# nach, ihre Ereignisse (Feuer in der Hand am Haken HH_shouR, Klänge) und der Angriffspunkt (675 ms) kommen
# mit; play_events hängt das Hand-GFX an den Haken, play mit elapsed 750 ms schießt den Feuerball sofort ab
func _mage_fireball(w) -> void:
	var eq = w.equip_models({0: STAFF}, 1, 5, 0)
	var err = w.factory.build(1, 0, 5, LOOK, w._actions({0: STAFF}), eq)
	var mage: Node3D = w.factory.detach() if err == "" else null
	var target = _nearest(w, BOAR)
	if target == null:
		target = _nearest(w, 14578)
	if mage == null or target == null:
		_check("Magier gebaut, Ziel da (%s)" % err, false)
		return
	var act = "法师_火球术"
	var anim: AnimationPlayer = mage.get_node("AnimationPlayer")
	var before = anim.has_animation(act)
	var n = w.factory.add_actions(mage, [act])
	var pts = w.attack_fx.points_of(mage, act)
	var evs: Array = mage.get_meta("action_events", {}).get(act, [])
	var hand = evs.filter(func(e): return int(e["type"]) == 100 and str(e["hook"]) == "HH_shouR")
	_check("Feuerball nachgebaut (vorher %s, %d neu): Angriffspunkt %s, %d Ereignisse, Hand-GFX %s" % [str(before), n, str(pts), evs.size(),
		str(hand.map(func(e): return str(e["files"][0]).get_file()))], not before and n == 1 and anim.has_animation(act)
		and pts.size() == 1 and int(pts[0][0]) == 675 and str(pts[0][1]).ends_with("火球术.att") and hand.size() == 1
		and evs.any(func(e): return int(e["type"]) == 101))
	var holder = Node3D.new()
	w.add_child(holder)
	holder.add_child(mage)
	var to = target.global_position
	var away = Vector3(to.x - w.player.global_position.x, 0, to.z - w.player.global_position.z).normalized()
	holder.global_position = to - (away if away.length() > 0.1 else Vector3.FORWARD) * 12.0
	anim.play(act)
	w.attack_fx.play_events(holder, mage, act, anim.get_animation(act).length)
	await _frames(3)
	var sk: Skeleton3D = mage.get_node("Skeleton3D")
	var bound = sk.get_children().filter(func(c): return c is BoneAttachment3D and c.bone_name.to_lower() == "hh_shour" and c.get_child_count() > 0)
	var hit_at = [0]
	var t0 = Time.get_ticks_msec()
	w.attack_fx.play(holder, mage, act, target, func(): hit_at[0] = Time.get_ticks_msec(), 750)
	var flew = await _until_ok(func(): return not w.attack_fx._flying.is_empty(), 1.0)
	var fly_ms = Time.get_ticks_msec() - t0
	await _until(func(): return hit_at[0] > 0, 3.0)
	_check("Feuer in der Hand (%d am Haken), Feuerball fliegt nach %d ms ab (Treffer 750 ms nach Beginn), Einschlag nach %d ms" % [bound.size(),
		fly_ms, hit_at[0] - t0], bound.size() == 1 and flew and fly_ms < 300 and hit_at[0] > t0)
	await _shot("20_fireball")
	holder.queue_free()

# Assassine (Mensch, Klasse 3) mit der Novizen-Assassinenklinge: zwei Dolche (models[] file_model_male_l),
# in Ruhe am Gürtel, im Kampf in beiden Händen; der linke wirbelt im ersten Normalangriff (Knochen 左武器)
func _dual_daggers(w) -> void:
	var eq = w.equip_models({0: DAGGER}, 1, 3, 0)
	var err = w.factory.build(1, 0, 3, LOOK, w._actions({0: DAGGER}), eq)
	var fig: Node3D = w.factory.detach() if err == "" else null
	if fig == null:
		_check("Assassine gebaut (%s)" % err, false)
		return
	var r = fig.get_node_or_null("Skeleton3D/Waffe")
	var l = fig.get_node_or_null("Skeleton3D/Waffe links")
	_check("Assassine: zwei Dolche am Gürtel (%s / %s)" % [r.bone_name if r != null else "-", l.bone_name if l != null else "-"], r != null and l != null
		and r.bone_name == "HH_腰_右匕首" and l.bone_name == "HH_腰_左匕首")
	w._player_script.place_weapons(fig, true)
	var sk: Skeleton3D = fig.get_node("Skeleton3D")
	var anim: AnimationPlayer = fig.get_node("AnimationPlayer")
	var hand = w._player_script._bone(sk, "Bip01 L Hand")
	var hook = w._player_script._bone(sk, "HH_lefthandweapon")
	var a: Animation = anim.get_animation("普通攻击1_匕首") if anim.has_animation("普通攻击1_匕首") else null
	var spin = 0.0
	if a != null and hand >= 0 and hook >= 0:
		w.add_child(fig)
		anim.play("普通攻击1_匕首")
		var prev = null
		var t = 0.0
		while t <= a.length:
			anim.seek(t, true)
			sk.force_update_all_bone_transforms()
			var rel: Basis = (sk.get_bone_global_pose(hand).basis.inverse() * sk.get_bone_global_pose(hook).basis).orthonormalized()
			if prev != null:
				spin += rad_to_deg((prev.inverse() * rel).get_rotation_quaternion().get_angle())
			prev = rel
			t += 1.0 / 30.0
	_check("im Kampf beide in der Hand, der linke wirbelt im Angriff 1 (%.0f Grad)" % spin, r != null and l != null
		and r.bone_name == "HH_righthandweapon" and l.bone_name == "HH_lefthandweapon" and spin > 360.0)
	fig.queue_free()

func _key(code: Key, pressed: bool) -> void:
	var ev = InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _physics(n: int) -> void:
	for i in n:
		await physics_frame

func _until(cond: Callable, seconds: float = 10.0) -> void:
	var end = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < end:
		await process_frame
	await _frames(2)

func _until_ok(cond: Callable, seconds: float) -> bool:
	await _until(cond, seconds)
	return cond.call()

# GFX / Klänge einer Aktion der eigenen Figur (Ereignisse und .att der Angriffspunkte)
func _action_files(w, act: String) -> Array:
	var out = []
	var m = w.player.model
	for e in m.get_meta("action_events", {}).get(act, []):
		if not e["files"].is_empty():
			out.append(str(e["files"][0]))
	for p in m.get_meta("attack_points", {}).get(act, []):
		for g in w.attack_fx.importer.att_gfx(w.attack_fx._att_of(str(p[1]))):
			out.append(g)
	return out

# Von diesen Dateien die, die erst beim Abspielen geladen wurden: [[Datei, ms], ...]
func _late_loads(w, files: Array) -> Array:
	return w.attack_fx.late_loads.filter(func(l): return str(l[0]) in files)

func _shot(shot_name: String) -> void:
	await _frames(3)
	if shots == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots)
	root.get_texture().get_image().save_png(shots.path_join(shot_name + ".png"))

func _check_ok(what: String, ok: bool) -> void:
	_check(what, ok)

func _check(what: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("WELT-TEST: ", "ok      " if ok else "FEHLER  ", what)

func _end(code: int) -> void:
	if ls != null and ls.session != null:
		ls.session.close()
	if ls != null and ls.world != null:
		ls.world.stop_sounds()
		await _frames(3)
	if code == 2:
		print("WELT-TEST FEHLER: Zeitlimit (%d Prüfungen bis dahin)" % checks)
	elif failures == 0:
		print("WELT-TEST OK (%d Prüfungen)" % checks)
	else:
		print("WELT-TEST FEHLER: %d von %d Prüfungen" % [failures, checks])
	quit(code)
