extends Node

# ====================================================
# Spiel-Oberfläche in der Welt (Fahrplan Schritt 8) nach CECGameUIMan, DlgHost, DlgTarget, DlgChat,
# DlgMiniMap und DlgWinTop: die Dialoge der Liste <Skin>gameui (.dcf / .stf der Spieldaten; Skin 2 =
# neuere Oberfläche, 1 = ältere, Einstellung ui_skin; fehlt die Liste, gilt die andere) auf einer
# eigenen AUI-Ebene (ui/aui_manager.gd):
#   Win_CharHead     eigener Kopf: Name, Stufe, Klasse (Pic_Prof0 Bild Klasse - 1), HP / MP mit Zahlen,
#                    XP 0/100 (DlgHost::RefreshHostStats)
#   Win_Target*      Ziel (Monster / NPC / Spieler): Name in der Namensfarbe, Stufe, HP / MP, Statuseffekte
#                    (st_1..8 Stärkungen, debuff_1..8 Schwächungen: Symbol, Stapel; CDlgTarget)
#   Win_Buff         eigene Statuseffekte oben rechts (CDlgBuff::UpdateBuff): Img_Buff0 = lange Stärkungen
#                    (Gesamtdauer ab 30 min; Anzahl, Liste im Tooltip), ab Img_Buff1 die übrigen Stärkungen,
#                    Schwächungen ab der nächsten vollen Reihe (je 10, rechts beginnend); Restzeit Txt_Time
#                    (h / m / s, unter 30 s rot), Stapel auf dem Symbol, Sammelplätze bei zu vielen. Art / Symbol /
#                    Text aus Plugin Data/angelica_buffs.gd (setzt die Welt); Tooltip: Text des Effekts und Restzeit
#   Win_QuickBar0/1  Schnellleisten (0 unten, 1 rechts, je 10 Plätze Sc_1..10 mit Fertigkeiten), EXP-Balken
#                    Pro_Exp (EXP / EXP bis zur Stufe)
#   Win_BaseSkill    Fertigkeiten (K / Knopf): 15 je Seite (Cmd_01.. Symbol, Txt_01.. Name und Stufe), Tooltip mit
#                    der Beschreibung (SkillDesc, Kontext Fenster), Ziehen in eine Schnellleiste
#   Win_NewSKill     neu gelernte Fertigkeiten (Img_Skill1..16, wie CDlgSkill_learnNew): zum Ziehen in die
#                    Leisten; gezogene und beim Schließen alle gelten als weggelegt (skill_seen)
#   Schnellleisten: Ziehen zwischen Plätzen tauscht, aus der Leiste heraus leert; Tooltip (Kontext Leiste);
#                    Tasten 1 - 0 bzw. Linksklick setzen die Fertigkeit ein (Signal skill_use_requested);
#                    Abklingzeit-Uhr (CoolOverlay, Meldung cooldown) auf Leisten und K-Fenster, Symbol
#                    dunkler ohne genug Mana; Zauberbalken: Win_Prgs mit dem Namen der Fertigkeit
#   Win_Chat         Eingabe "Sagen": Enter öffnet und sendet, Esc schließt
#   Win_ChatInfo     Verlauf (Name: Text; Meldungen des Systems rot), höchstens CHAT_LINES Zeilen
#   Win_MiniMap      Kartenbild um die eigene Figur (Lua InstanceWorld.lua: Instance[Welt][0] MiniMap /
#                    rectMap; 512 m * MapZoom 0,5 Durchmesser wie DEFAULT_RADAR_DIAMETER), rund maskiert
#                    (InGame\MiniMapMask.tga), Pfeil der Figur (InGame\MiniMapDir.tga), NPCs, Monster
#                    und Spieler als Marken (InGame\MiniMapMark\*.tga), Ziel der Autoroute (AutoMove.tga);
#                    Linksklick auf die Karte = Autoroute dorthin (Signal map_route_requested); Name der
#                    Map aus InstanceStr.lua.
#                    Die Maps behalten die Angelica-Koordinaten, in Godot ist die Welt dadurch gespiegelt
#                    (Blick nach +Z: +X links): Bild und Marken sind deshalb waagrecht gespiegelt, damit
#                    die Minimap zur sichtbaren Welt passt
#   Win_Inventory    Inventar (B oder Knopf "Inventar", CDlgInventory): Plätze Item_00 - 47 (ab der Größe
#                    der Tasche gesperrt), Symbole mit Anzahl, Goldmünzen und Seelenmünzen (Z4; Diamant / Gold / Silber / Kupfer wie
#                    SetMoneyTextCtrl), Belegung; Rechtsklick benutzt (Quest-Würfel wie der EXP-Cocktail) bzw. legt
#                    Ausrüstung an (Signal use_requested), Ziehen verschiebt bzw. legt an (auf einen Platz im
#                    Charakter-Fenster); Tooltip wie das Original (item_data.gd, LuaItemDesc). Zerstören wie
#                    CDlgInventory / CDlgDragDrop: Btn_Destroy schaltet den Zerstören-Modus (Linksklick auf einen Platz),
#                    Ziehen auf Btn_Destroy oder aus dem Fenster in die Welt; nicht zerstörbar (proc 0x400) -> Hinweis;
#                    Qualität 4 - 7 und 9 fragt Win_Destroy (Schlüsselwort DESTORY_ITEM_KEY eintippen, sonst
#                    INPUT_CONFIRM_ERR), die übrigen ein Meldungsfenster (gameui.stf 987, übersetzt; fehlt er, die
#                    erste Zeile von DESTORY_ITEM_CONFIRM); dann Signal destroy_requested
#   Win_Character    Charakter (C oder Knopf "Figur", CDlgCharacter): Ausrüstungsplätze Equip_NN (NN =
#                    EQUIP_INDEX_*), Rechtsklick / Ziehen in die Tasche legt ab; Name, Klasse und Stufe,
#                    Leben / Mana, Angriff, Verteidigung, Treffer, Ausweichen, Krit-Werte (stats.attr des
#                    Servers, mit den Effekten); Figur als Bild Img_Male / Img_Female wie im Original (Z6: kein 3D-Bild)
#   Win_CharacterDetail  zweite Seite des Charakters (Z6, CDlgCharacter::OnCommand_Page): eigenes Fenster an derselben
#                    Stelle, Reiter Rdo_Title (Grundwerte) / Rdo_Reputation (Meisterschaft / Widerstand) schalten um;
#                    Txt_Mas00..06 / Txt_Res00..06 je Element, Platz 07 PvE-Intensität / -Zähigkeit (UpdateInfoEx,
#                    negative Widerstände rot), Ausrüstungsplätze wie Win_Character
#   Win_Prgs         Fortschritt beim Sammeln (Text des Sammelpunkts) und beim Zaubern (Name der Fertigkeit)
#   Win_Message4     "Ihr seid gestorben!" (CDlgRevive): Wiederbeleben (Btn_Decide, am nächsten Punkt) -
#                    Signal revive_requested; die übrigen Arten (durch andere, mit Gegenstand, perfekt)
#                    gibt es noch nicht
#   Win_QuestMinion  Quest-Verfolgung (CDlgTask "Win_QuestMinion"): je Quest Titel, laufender Teil,
#                    Ziel; NPC-Namen grün unterstrichen als Link (Klick = Autoroute, Signal
#                    route_npc_requested), Klick auf den Titel öffnet links daneben Win_QuestMinionDes
#                    (Ziel, Beschreibung, Belohnung), "-" / "+" klappt die Quest ein / aus. Statt der
#                    AUI-Baumansicht ein RichTextLabel an ihrer Stelle (die Godot-Baumansicht kennt keine
#                    Links im Text). Rechtsklick auf eine Zeile -> Popup Win_QuestMinionOption ("Ansehen" öffnet
#                    das Quest-Fenster mit der Quest, "Aufgeben" fragt nach)
#   Win_Quest        Quest-Fenster (Q oder Knopf "Quest"): Tv_Quest mit den laufenden Quests, rechts
#                    (Win_QuestContent) Ziel (NPC als Link), Beschreibung und Belohnung, "Aufgeben"
#                    (nur mit giveup); Rechtsklick auf eine Quest -> Popup Win_QuestOption ("Aufgeben").
#                    Aufgeben fragt immer erst (gameui.stf 236, Signal quest_abandon_requested erst nach OK)
#   Win_NPC          NPC-Fenster (CDlgNPC): Gruß des NPCs, Quest-Einträge (quest_data.gd npc_entries)
#                    mit Symbol (nicht annehmbare grau, NPC_GREY), "Gespräch beenden"; ein Eintrag zeigt sein Gespräch (talk_proc: Fenster
#                    mit Text und Optionen; Option = nächstes Fenster bzw. Sonderbefehl: Quest geben /
#                    abschließen / aufgeben -> Signal npc_option, zurück, beenden), "Zurück" zur Übersicht
#   Win_Main1 - 4    Leisten oben; Knopf "System" öffnet das Systemmenü, die übrigen melden im Chat,
#                    dass es sie noch nicht gibt
#   Win_Quit         Systemmenü (Esc): Wechseln = zurück zur Figurenauswahl, Verlassen = Spiel beenden,
#                    Zurück / Schließen, Fenster wechseln = anderer Skin, Einstellung (noch nicht da)
# Lage: wie in der Liste, dazu CECGameUIMan::RearrangeWindows: Ziel-Fenster rechts neben dem Kopf,
# Chatverlauf über der Eingabe; die Schnellleiste mit dem EXP-Balken unten in der Mitte (die
# v260-Quellen ordnen nur Skin 1, in Skin 2 steht sie in der Liste mittig).
# Ausgeblendet wird, was das Spiel ohne die zugehörigen Systeme verbirgt (Hilfe-Pfeile, Effekte, Glaube
# Shen / Mo, VIP, Werbung, Belohnungen ...): HIDE_RE für alle Dialoge, HIDE je Dialog.
# Tasten (world_screen.gd fragt handle_key): Enter Chat, Esc schließt Chat / Ziel / Systemmenü bzw.
# öffnet es, Tab nächstes Monster, F1 eigene Figur, 1 - 0 untere Schnellleiste. Signale an world_screen.gd: target_requested,
# say_requested, leave_requested, quit_requested, skin_requested.
# ====================================================

const AuiManager = preload("ui/aui_manager.gd")
const Proto = preload("../common/protocol.gd")
const LUA = "res://addons/PWE-Manager/Data/angelica_lua.gd"
const FILES = "res://addons/PWE-Manager/Data/angelica_files.gd"
const SHOWN = ["CharHead", "Chat", "ChatInfo", "MiniMap", "QuickBar0", "QuickBar1", "WinMain1", "WinMain3",
	"WinMain4", "QuestMinion", "Buff"]
const TARGETS = {"monster": "TargetMonster", "npc": "TargetNPC", "player": "TargetPlayer"}
const MENU = "Quit"
const NPC = "NPC"
const QUEST = "Quest"
const QUEST_DES = "QuestMinionDes"
const QUEST_OPTION = "QuestOption" # Win_QuestOption: Rechtsklick auf eine Quest im Quest-Fenster (CDlgQuestOption)
const QUEST_MINION_OPTION = "QuestMinionOption" # Win_QuestMinionOption: Rechtsklick in der Verfolgung (CDlgQuestMinionOption)
const STF_ABANDON_ASK = 236 # gameui.stf "Wollt Ihr den ausgewählten Quest wirklich aufgeben?" (Game_AbortTask)
const INVENTORY = "Inventory"
const DESTROY = "Destroy" # Win_Destroy: Zerstören mit Schlüsselwort (CDlgDestroyItemConfirm)
const DESTROY_ASK_QUALITY = [4, 5, 6, 7, 9] # diese Qualitäten fragen mit Schlüsselwort (CDlgDragDrop)
const STF_DESTROY_ASK = 987 # gameui.stf "Wirklich %s zerstören?"
const STF_CANT_DESTROY = 988
const CHARACTER = "Character"
const CHARACTER_DETAIL = "CharacterDetail" # Win_CharacterDetail: zweite Seite (Meisterschaft / Widerstand)
const CHAR_DETAIL_HIDE = ["Btn_Holy_Stone", "Btn_Magic_Stone", "Txt_Help_1", "Btn_Increase", "Txt_Help_JingTong"] # Steigern (fehlt)
const RES_RED = Color(1, 0, 0) # negative Widerstände (UpdateInfoEx)
const PROGRESS = "Progress"
const REVIVE = "Message4"
const SKILLS = "Skill" # Win_Skill (K): Reiter Klasse / Rasse / Beruf, Liste Sub_Skill (Win_Skill_View)
const BASE_SKILLS = "BaseSkill" # Win_BaseSkill: Reiter Grundlagen (Grundaktionen)
const TALENT_HINT = "Talent00" # Win_Talent00: "Talente verfügbar ab Lv20" (auch für die Seele)
const TALENT_LEVEL = 20 # Talentbaum ab dieser Stufe
const SOUL_LEVEL = 60 # Seelenkraft ab dieser Stufe
const VIEW_ROW = 80.0 # px je Reihe der Liste (3 Plätze)
const TAB_ORDER = ["basic", "class", "race", "jobs", "talent", "soul"]
const TAB_RADIOS = {"basic": "Rdo_Produce", "race": "Rdo_Race", "jobs": "Rdo_SkillScience", "talent": "Rdo_Tree",
	"soul": "Rdo_Belief"} # Klasse: Rdo_MainInitiative (Win_Skill, Talentbaum) bzw. Rdo_Initiative (Win_BaseSkill)
const TAB_X = [19, 92, 165, 238, 311, 384]
const TAB_W = 72 # breiter als im Original (62): "Grundlagen" passt sonst nicht
const SKILL_LV_COLOR = Color(0.33, 0.62, 1.0) # Stufe einer gelernten Fertigkeit (wie im Spiel blau)
const SKILL_NEED_COLOR = Color(1.0, 0.3, 0.3) # benötigte Stufe einer noch nicht gelernten
# Talentbaum je Rasse_Klasse (Win_TalentNN_New: Titel "Human Warrior" ...)
const TALENT_TREES = {"1_1": 1, "2_1": 2, "4_2": 3, "1_3": 4, "5_3": 5, "3_4": 6, "5_7": 7, "2_8": 8, "1_5": 9,
	"5_5": 10, "1_6": 11, "2_6": 12, "6_6": 13, "6_3": 14, "5_9": 15, "6_9": 16}
# Grundaktionen (Win_BaseSkill Cmd_NN): Name, Symbole in iconlist_action (Normalangriff je Klasse)
const BASIC_ACTIONS = [["attack", ["普通攻击_%d", "普通攻击_1"]], ["walk", ["走跑转换"]], ["assist", ["协助攻击"]],
	["pickup", ["拾取"]], ["invite", ["邀请加入"]], ["leave", ["脱离队伍"]], ["trade", ["交易命令"]], ["stall", ["摆摊卖"]],
	["interrupt", ["中断施法"]]]
const NEW_SKILLS = "Skill_LearnNew" # Win_NewSKill
const SKILL_SLOTS = 15
const NEW_SLOTS = 16
const BAR_DIALOGS = ["QuickBar0", "QuickBar1"] # Leiste 0 unten, 1 rechts
const BAR_SLOTS = 10
const BUFF = "Buff" # Win_Buff
const BUFF_SLOTS = 40 # Img_Buff0 - 39 (CDlgBuff BUFF_COUNT)
const BUFF_PER_LINE = 10
const TARGET_BUFF_SLOTS = 8 # st_1..8 / debuff_1..8 (CDLGTARGET_ST_MAX)
const LONG_BUFF_MINUTES = 30 # Stärkungen ab dieser Gesamtdauer zählen in Img_Buff0
const BUFF_RED_SECONDS = 30 # Restzeit darunter rot
const BUFF_REFRESH = 0.25 # s
const BUFF_TYPE_BUFF = 0 # SKILL_BUFF_TYPE_* (angelica_buffs.gd)
const BUFF_TYPE_DEBUFF = 1
const BUFF_TYPE_BUFF_NO_TIME = 3
const BUFF_TYPE_DEBUFF_NO_TIME = 4
# Shylias Markt (Win_LvupAward, Geschenk-Knopf Btn_Gift_Lua in WinMain3, Z5): Einträge aus GameUI.Var.LvupItemAward
# (script\interfaces\gameui.lua, Texte aus designer_string.lua); jeder Eintrag ist eine Fenster-Quest (taskid: Tausch
# gegen Prüfungs-Essenzen bzw. Geschenk), der Knopf nimmt sie an (GameApi.AcceptTask); Knopf-Text nach Quest-Zustand
# (2 annehmbar, 4 erledigt, sonst gesperrt) wie lvup_award.lua Tick
const LVUP = "lvup_award"
const LVUP_SLOTS = 12
const LVUP_TABS = [2, 3, 4, 5, 8] # Unterreiter Rdo_1_N = Rdo_1.Table_N (1, 6, 7 blendet das Original aus)
const LVUP_OPEN_TAB = 8 # der Geschenk-Knopf öffnet "Erhalten" (winmain3.lua OnBtnGift)
const LVUP_ITEMS = ["Name_", "Img_icon_", "Price_", "Level_", "Other_", "Btn_", "Warning_", "Img_Iconback_", "Edt_Back_",
	"Edt_Name_", "Lab_", "Txt_", "Edt_Title_", "Edt_Level_", "Edt_Other_", "Edt_Warning_", "Edt_Price_"] # ohne Img_ (aus)
const ESSENCE = 36667 # Prüfungs-Essenz (Txt_Order des Originals fehlt in dieser XML: Anzahl in "Warning")
const BAG_SLOTS = 48 # Item_00 - 47
const EQUIP_SLOTS = 29 # Equip_00 - 28
const STF_CLASS = 101 # + Klasse, Texttabelle loginui (gameui hat dort nur Chinesisch)
const SLOT_LOCKED = Color(0, 0, 0, 0.55)
const LINK_COLOR = "#00ff00" # Koordinaten-Links (enumEICoord) grün unterstrichen
const TRACE_TITLE_HEX = "#ffdb59" # Quest-Titel in der Verfolgung
const NPC_GIVE_TASK = 0x80000006
const NPC_COMPLETE_TASK = 0x80000007
const TALK_RETURN = 0x80000011
const TALK_EXIT = 0x80000012
const TALK_GIVEUP_TASK = 0x80000015
const STF_END_TALK = 503 # "Gespräch beenden" (CDlgNPC::PopupNPCDialog)
const NPC_GREY = Color8(128, 128, 128) # Quest-Eintrag im NPC-Fenster: sichtbar, aber nicht annehmbar (CDlgNPC)
const INFO_COLOR = "ffff00"
const BOOK_TITLE = Color(0.45, 0.2, 0.0) # Quest-Buch: dunkle Schrift auf Pergament
const BOOK_COLORS = {"title": "6e2f00", "part": "2a1a0a", "goal": "1d5c1d", "award": "6e2f00", "link": "#0a8f0a"} # Pergament
const TRACE_MAX = 25
const HIDE_RE = "(?i)(help|arrow|^gfx|^img_gfx|_gfx|(_shen|_mo)$|^skillnew_|promotion|^img_pk_|^txt_pk_|^img_icon_\\d|facebook|weibo|rune|pvpsoul|^txt_lowhp|^edt_expredeem|^txt_gua$|^pic_prof\\w*_(dark|light)$)"
const HIDE = {
	"CharHead": ["Btn_Add", "Img_TalentAdd", "Img_Combat_Fight", "Img_Combat_Rest", "Btn_Exp", "Img_Monster",
		"Chk_Optimize", "Img_Server", "Img_Server_1", "Btn_VIP", "Pic_Prof0_Dark", "Pic_Prof0_Light", "Pro_Soul_1",
		"Pro_Soul_2", "Pro_Soul_3", "Pro_Soul_4", "Pro_Soul_5", "Pro_Soul_6", "Txt_LowHP2", "Btn_HuoDong"],
	"TargetMonster": ["Img_MonsterLevel4", "Img_MonsterPetType1", "Img_MonsterPetType2", "Img_MonsterPetType3",
		"Edt_EggHelp", "Txt_EggHelp", "Txt_EggHelp2", "Txt_EggHelp3", "Edt_EggArrow", "Img_MonsterTrueLevel"],
	"TargetNPC": ["Img_MonsterLevel4"],
	"TargetPlayer": ["Prg_Stun", "Img_Belief", "Img_VIP", "Btn_GuildBattle"],
	"QuickBar0": ["Img_Godback", "Img_God", "Pro_Exp2", "Pro_Exp3", "Img_Exppass"],
	"MiniMap": ["Dlg_Back_TaiWan", "Edt_HideModelBack", "Btn_Radio", "Btn_Lua", "Btn_New", "Btn_Back", "Img_Mail",
		"Btn_Ranking", "Btn_Daily"],
	"WinMain3": ["Edt_GainPoint", "Img_GainPointMouse", "Txt_TimeTable", "Txt_GuildContent", "Edt_GuildFrame",
		"Txt_GainEquip2", "Edt_GainEquip", "Txt_GainEquip1", "Txt_GainPoint1", "Txt_GainPoint2",
		"Img_GainEquipMouse", "Txt_Team", "Txt_Skill", "Btn_Team_2", "Btn_Pet_Work"],
	"Buff": ["Img_Korea_Logo_1", "Img_Korea_Logo_2", "Img_Captivation"], # Korea-Hinweis, Jugendschutz (TickWallow aus)
	"QuestMinion": ["Img_Alpha", "Img_Alpha1"], # Hintergrund mit einstellbarer Deckkraft (iTaskAlphaOption 0)
	"WinMain4": ["Img_AstrologyReverse", "Img_Combat_as01", "Img_Combat_as02", "Img_Combat_as03", "Img_Combat_as04"],
	"Quest": ["Btn_SearchQuest", "Btn_Focus", "Txt_AutoHelp3", "Txt_AutoHelp2", "Btn_Delete", "Chk_Tree",
		"Chk_FocusAll", "Btn_FindTask", "Btn_FindTask_1", "Lab_Guid", "Img_Guid"],
	"Inventory": ["Rdo_TaskItem", "Rdo_BusinessItem", "Btn_Booth", "Btn_Arrange", "Btn_Seperate",
		"Lab_Expand", "Scl_Item", "Img_FrameRealMoney", "Txt_RealMoney",
		"Img_FrameBindMoney_Back", "Edt_Back", "Txt_GainSth", "Img_Packfull", "Edt_PackFull", "Txt_PackFull", "Btn_Setting",
		"Btn_Lock", "Btn_Lua", "Btn_Storage", "Btn_QShopPack", "Img_FrameRealMoney_Bound", "Txt_RealMoney_Bound",
		"Rdo_Type1", "Rdo_Type2", "Rdo_Type3", "Rdo_Type4", "Rdo_Type5", "Rdo_Type6", "Rdo_Type7", "Rdo_Type8", "Line"],
	"Character": ["Img_Plate_Back", "Img_Soul_Back", "Equip_Plate_Back", "Equip_XP_Back", "Equip_Soul_Back_1",
		"Equip_Soul_Back_2", "Img_WereWolf_female", "Img_WereWolf_male", "Img_Titan", "Img_atomy_male",
		"Img_atomy_female", "Btn_LeftTurn", "Btn_RightTurn", "Rdo_03", "Rdo_04", "Rdo_05", "Rdo_Detail", "Rdo_FashDress",
		"Rdo_Equip", "Rdo_Achieve", "Chk_HideHead", "Chk_HideHand", "Rdo_Equip_Fashion_1",
		"Rdo_Equip_Fashion_2", "Img_Star", "Txt_constellation", "Img_PK", "Txt_PK", "Btn_Ranklist", "Prgs_Vitality",
		"Prgs_Vigour", "Txt_Vigour", "Txt_Vitality", "Lab_Vigour", "Lab_Vitality", "Edt_VitalityBack", "Txt_Title",
		"Btn_Exp", "Btn_Achievement", "Btn_Credit", "Btn_PVP", "Btn_Marry", "Btn_Stone", "Btn_GOD", "Btn_Belial",
		"Lab_Belief_God", "Lab_Belief_Mo", "Lab_Belief_Value", "Txt_Belief_God", "Txt_Belief_Mo", "Txt_Belief_Value",
		"Edt_Belief_God", "Edt_Belief_Mo", "Edt_Belief_Value", "Prs_Belief_Value", "Lab_Energy", "Edt_EnergyBack",
		"Prgs_Energy", "Lab_FlyTime", "Txt_Energy", "Prgs_FlyTimeBack", "Edt_FlyTimeBack", "Txt_FlyTimeBack", "Img_Fly",
		"Txt_Fly", "Edt_VigourBack", "Lab_Hint_1", "Lab_Hint_2", "Btn_Vitality", "Btn_Vigour", "Btn_Equip_Soul_1",
		"Btn_Equip_Soul_2", "Btn_XP_Equip", "Rdo_Equip_Fashion_3", "Btn_ChangeEquip", "Rdo_Pet", "Rdo_Other", "Rdo_Kingdom",
		"Img_Prof_Dark", "Img_Prof_Light", "Equip_28"],
	"BaseSkill": ["Rdo_Transfer"],
	"Skill": ["Rdo_Transfer", "Rdo_SkillEdit"],
	LVUP: ["Rdo_2", "Rdo_3", "Rdo_4", "Rdo_5", "Rdo_6", "Rdo_7", "Rdo_8", "Rdo_1_1", "Rdo_1_7", "Btn_LvupAward_TaskCount",
		"Txt_MainTaskNum"],
	"Message4": ["Btn_Accept", "Btn_Revive", "Btn_ReLive", "Txt_Time", "Prgs_Time", "Txt_Time_Storm", "Btn_Back"],
	"Quit": ["Lab_Dai_Exp", "Txt_Dai_Exp", "Img_1", "Img_2", "Img_3", "Lab_ShengYu_Exp", "Txt_ShengYu_Exp",
		"Lab_Total_Exp", "Txt_Total_Exp", "Lab_Info_1", "Lab_Info_2", "Edt_Back", "Prgs_Total", "Prgs_Dai",
		"Prgs_ShengYu", "Lab_Info", "Btn_BBS", "Title2", "Txt_Exp_Max", "DEFAULT_Exp", "Lab_1", "Slider_Exp",
		"Lab_Zero", "Txt_Number", "Txt_BindMoney0", "Txt_BindMoney1", "Txt_BindMoney2", "Txt_BindMoney3",
		"Img_FrameMoney_Back", "Img_FrameBindMoney", "Lab_Hotkey", "Lab_ExpRedeem", "Btn_Redeem", "Chk_Exchange",
		"Sub_Content", "Btn_Confirm", "Sub_Content2", "Img_Line", "Lab_BindMoney", "Title_Login"],
}
# Menü-Knöpfe der Leisten ohne Funktion (Win_Main3: DlgWinTop)
const MENU_BUTTONS = ["Btn_Team", "Btn_Friend", "Btn_Qshop", "Btn_SubProf", "Btn_Pet", "Btn_Guild",
	"Btn_Daily"]
const RADAR_DIAMETER = 512.0 # m bei MapZoom 1 (DlgMiniMap DEFAULT_RADAR_DIAMETER)
const MAP_ZOOM = 0.5 # Voreinstellung uils.fMapZoom
const MARKS = {"npc": "InGame\\MiniMapMark\\NPC.tga", "monster": "InGame\\MiniMapMark\\Monster.tga",
	"player": "InGame\\MiniMapMark\\TeamMate.tga", "target": "InGame\\MiniMapMark\\Target.tga",
	"route": "InGame\\MiniMapMark\\AutoMove.tga"}
const CHAT_LINES = 200
const CHAT_NAME_COLOR = "ffde5a"
const CHAT_TEXT_COLOR = "ffffff"
const SYSTEM_COLOR = "ff6a6a"
const NAME_COLOR = Color(1, 1, 1)
const TEXTS = {
	"Deu": {"skill_learned": "Gelernt: %s Stufe %d", "skills_title": "Fertigkeiten", "tab_basic": "Grundlagen", "tab_class": "Klasse", "tab_race": "Rasse",
		"tab_jobs": "Beruf", "tab_talent": "Talent", "tab_soul": "Seele", "skill_lv": "Lv%d", "skill_from": "Lv%d", "skill_quest": "Quest",
		"kind_1": "Angriff", "kind_2": "Stärkung", "kind_3": "Fluch", "kind_passive": "Passiv", "kind_switch": "Schalter",
		"learn_next": "^ffcb4aStufe %d lernen", "learn_need": "Benötigt Stufe %d", "learn_cost": "Seelenmünzen: %s", "learn_gold": "^ffcb4a(Nicht genug Seelenmünzen, Goldmünzen können den Rest decken.)",
		"learn_poor": "^ff6a6a(Nicht genug Seelen- und Goldmünzen.)", "learn_ask": "Nicht genug Seelenmünzen. Die fehlenden %s mit Goldmünzen ausgleichen?",
		"money_gsc": "%d Gold %d Silber %d Kupfer", "money_sc": "%d Silber %d Kupfer", "money_c": "%d Kupfer",
		"talent_hint": "Talente verfügbar ab Lv%d", "soul_hint": "Seelenkraft verfügbar ab Lv%d",
		"basic_attack": "Normaler Angriff", "basic_walk": "Gehen / Laufen", "basic_assist": "Unterstützen",
		"basic_pickup": "Aufheben", "basic_invite": "Einladen", "basic_leave": "Gruppe verlassen", "basic_trade": "Handeln",
		"basic_stall": "Verkaufsstand", "basic_interrupt": "Zaubern abbrechen",
		"skill_level": "Stufe %d", "not_yet": "Noch nicht verfügbar.", "self": "Ihr", "end_talk": "Gespräch beenden", "talk_to": "Sprecht mit %s", "return_to": "Zurück zu %s",
		"quest_new": "Neue Quest: %s", "quest_done": "Quest erfüllt: %s", "quest_failed": "Quest gescheitert: %s", "abandon_ask": "Wollt Ihr den ausgewählten Quest wirklich aufgeben?",
		"gain_exp": "Ihr erhaltet %d EXP.", "gain_item": "Ihr erhaltet: %s x%d", "gain_gold": "Goldmünzen erhalten: %s.", "gain_bind": "Seelenmünzen erhalten: %s.",
		"level_up": "Ihr habt Stufe %d erreicht!", "done_mark": "(erfüllt)", "quests_title": "Quests",
		"desc": "Beschreibung:", "goal": "Ziel: %s", "award": "Belohnung: %s", "money": "Goldmünzen: %s", "bind": "Seelenmünzen: %s",
		"route_start": "Autoroute zu %s (%d m).", "route_failed": "Kein Weg gefunden (%s).",
		"route_stuck": "Autoroute abgebrochen: hier geht es nicht weiter.", "route_far": "%s ist in einem anderen Gebiet.",
		"route_unknown": "Der Ort von %s ist unbekannt.", "map_point": "Kartenpunkt",
		"slots": ["Waffe", "Handgelenk", "Schultern", "Körper", "Taille", "Beine", "Kopf", "Füße", "Hals", "Hilfswaffe",
			"Ring", "Ring"], "item_dmg": "Angriff: %d - %d", "item_def": "Verteidigung: %d", "item_hp": "Leben: +%d",
		"item_mp": "Mana: +%d", "item_hit": "Treffer: +%d", "item_range": "Reichweite: %.1f m", "item_lv": "Benötigt Stufe %d",
		"item_prof": "Klasse: %s", "item_gender": "Geschlecht: %s", "genders": ["männlich", "weiblich"],
		"item_race": "Eure Rasse kann das nicht tragen", "item_pile": "Anzahl: %d / %d", "item_price": "Verkaufswert: %d",
		"gather": "Sammeln", "use": "Benutzen", "dest_dist": " (ca. %d m)", "gather_none": "Nichts gefunden.", "prof_level": "%s  Stufe %d", "bag_full_quest": "Euer Inventar ist voll.",
		"races": ["", "Mensch", "Elf", "Zwerg", "Steinmensch", "Kindred", "Werwolf"], "miss": "Verfehlt",
		"skill_stopped": "Fertigkeit unterbrochen.", "immune": "Immun", "buff_time": ["%d h", "%d m", "%d s"], "buff_left": "Restzeit: %s",
		"cant_destroy": "Dieser Gegenstand kann nicht zerstört werden."},
	"Eng": {"skill_learned": "Learned: %s level %d", "skills_title": "Skills", "tab_basic": "Basic", "tab_class": "Class", "tab_race": "Race",
		"tab_jobs": "Jobs", "tab_talent": "Talent", "tab_soul": "Soul", "skill_lv": "Lv%d", "skill_from": "Lv%d", "skill_quest": "Quest",
		"kind_1": "Attack", "kind_2": "Blessing", "kind_3": "Curse", "kind_passive": "Passive", "kind_switch": "Toggle",
		"learn_next": "^ffcb4aLearn level %d", "learn_need": "Requires level %d", "learn_cost": "Soul Coins: %s", "learn_gold": "^ffcb4a(Not enough Soul Coins, Gold Coins can cover the rest.)",
		"learn_poor": "^ff6a6a(Not enough Soul Coins and Gold Coins.)", "learn_ask": "Not enough Soul Coins. Pay the missing %s with Gold Coins?",
		"money_gsc": "%d gold %d silver %d copper", "money_sc": "%d silver %d copper", "money_c": "%d copper",
		"talent_hint": "Talents available from Lv%d", "soul_hint": "Soul Power available from Lv%d",
		"basic_attack": "Normal attack", "basic_walk": "Walk / Run", "basic_assist": "Assist",
		"basic_pickup": "Pick up", "basic_invite": "Invite", "basic_leave": "Leave group", "basic_trade": "Trade",
		"basic_stall": "Stall", "basic_interrupt": "Interrupt casting",
		"skill_level": "Level %d", "not_yet": "Not available yet.", "self": "You", "end_talk": "End conversation", "talk_to": "Talk to %s", "return_to": "Return to %s",
		"quest_new": "New quest: %s", "quest_done": "Quest completed: %s", "quest_failed": "Quest failed: %s", "abandon_ask": "Do you really want to abandon the selected quest?",
		"gain_exp": "You receive %d EXP.", "gain_item": "You receive: %s x%d", "gain_gold": "Gold Coins received: %s.", "gain_bind": "Soul Coins received: %s.",
		"level_up": "You have reached level %d!", "done_mark": "(done)", "quests_title": "Quests",
		"desc": "Description:", "goal": "Goal: %s", "award": "Reward: %s", "money": "Gold Coins: %s", "bind": "Soul Coins: %s",
		"route_start": "Auto route to %s (%d m).", "route_failed": "No path found (%s).",
		"route_stuck": "Auto route stopped: cannot get through here.", "route_far": "%s is in another area.",
		"route_unknown": "The location of %s is unknown.", "map_point": "map point",
		"slots": ["Weapon", "Wrist", "Shoulders", "Body", "Waist", "Legs", "Head", "Feet", "Neck", "Off-hand", "Ring",
			"Ring"], "item_dmg": "Attack: %d - %d", "item_def": "Defense: %d", "item_hp": "Health: +%d", "item_mp": "Mana: +%d",
		"item_hit": "Accuracy: +%d", "item_range": "Range: %.1f m", "item_lv": "Requires level %d", "item_prof": "Class: %s",
		"item_gender": "Gender: %s", "genders": ["male", "female"], "item_race": "Your race cannot wear this",
		"item_pile": "Count: %d / %d", "item_price": "Sell value: %d", "gather": "Gathering", "use": "Using", "dest_dist": " (approx. %d m)", "gather_none": "Nothing found.",
		"prof_level": "%s  Level %d", "bag_full_quest": "Your inventory is full.",
		"races": ["", "Human", "Elf", "Dwarf", "Stoneman", "Kindred", "Lycan"], "miss": "Miss",
		"skill_stopped": "Skill interrupted.", "immune": "Immune", "buff_time": ["%d h", "%d m", "%d s"], "buff_left": "Time left: %s",
		"cant_destroy": "This item cannot be destroyed."},
	"Franz": {"skill_learned": "Appris : %s niveau %d", "skills_title": "Compétences", "tab_basic": "Base", "tab_class": "Classe", "tab_race": "Race",
		"tab_jobs": "Métier", "tab_talent": "Talent", "tab_soul": "Âme", "skill_lv": "Niv%d", "skill_from": "Niv%d", "skill_quest": "Quête",
		"kind_1": "Attaque", "kind_2": "Bénédiction", "kind_3": "Malédiction", "kind_passive": "Passive", "kind_switch": "Bascule",
		"learn_next": "^ffcb4aApprendre le niveau %d", "learn_need": "Niveau requis : %d", "learn_cost": "Écus psy : %s", "learn_gold": "^ffcb4a(Écus psy insuffisants, les écus d'or peuvent payer le reste.)",
		"learn_poor": "^ff6a6a(Pas assez d'écus psy ni d'écus d'or.)", "learn_ask": "Écus psy insuffisants. Payer les %s manquants avec des écus d'or ?",
		"money_gsc": "%d or %d argent %d cuivre", "money_sc": "%d argent %d cuivre", "money_c": "%d cuivre",
		"talent_hint": "Talents disponibles dès le niv %d", "soul_hint": "Puissance de l'âme disponible dès le niv %d",
		"basic_attack": "Attaque normale", "basic_walk": "Marcher / Courir", "basic_assist": "Assister",
		"basic_pickup": "Ramasser", "basic_invite": "Inviter", "basic_leave": "Quitter le groupe", "basic_trade": "Échanger",
		"basic_stall": "Échoppe", "basic_interrupt": "Interrompre le sort",
		"skill_level": "Niveau %d", "not_yet": "Pas encore disponible.", "self": "Vous", "end_talk": "Terminer la conversation",
		"talk_to": "Parlez à %s", "return_to": "Retournez voir %s", "quest_new": "Nouvelle quête : %s", "quest_done": "Quête accomplie : %s",
		"quest_failed": "Quête échouée : %s", "abandon_ask": "Voulez-vous vraiment abandonner la quête sélectionnée ?", "gain_exp": "Vous recevez %d EXP.", "gain_item": "Vous recevez : %s x%d",
		"gain_gold": "Écus d'or reçus : %s.", "gain_bind": "Écus psy reçus : %s.", "level_up": "Vous avez atteint le niveau %d !", "done_mark": "(accomplie)",
		"quests_title": "Quêtes", "desc": "Description :", "goal": "Objectif : %s", "award": "Récompense : %s",
		"money": "Écus d'or : %s", "bind": "Écus psy : %s", "route_start": "Itinéraire automatique vers %s (%d m).",
		"route_failed": "Aucun chemin trouvé (%s).", "route_stuck": "Itinéraire interrompu : passage impossible.",
		"route_far": "%s se trouve dans une autre zone.", "route_unknown": "La position de %s est inconnue.",
		"map_point": "point de la carte",
		"slots": ["Arme", "Poignets", "Épaules", "Torse", "Taille", "Jambes", "Tête", "Pieds", "Cou", "Main gauche",
			"Bague", "Bague"], "item_dmg": "Attaque : %d - %d", "item_def": "Défense : %d", "item_hp": "PV : +%d",
		"item_mp": "PM : +%d", "item_hit": "Précision : +%d", "item_range": "Portée : %.1f m", "item_lv": "Niveau requis %d",
		"item_prof": "Classe : %s", "item_gender": "Sexe : %s", "genders": ["masculin", "féminin"],
		"item_race": "Votre race ne peut pas porter cet objet", "item_pile": "Nombre : %d / %d",
		"item_price": "Valeur de vente : %d", "gather": "Récolte", "use": "Utilisation", "dest_dist": " (env. %d m)", "gather_none": "Rien trouvé.", "prof_level": "%s  Niveau %d",
		"bag_full_quest": "Votre inventaire est plein.",
		"races": ["", "Humain", "Elfe", "Nain", "Homme de pierre", "Kindred", "Lycan"], "miss": "Raté",
		"skill_stopped": "Compétence interrompue.", "immune": "Immunisé", "buff_time": ["%d h", "%d m", "%d s"], "buff_left": "Temps restant : %s",
		"cant_destroy": "Cet objet ne peut pas être détruit."},
}
const RADAR_SHADER = """
shader_type canvas_item;
uniform sampler2D map_tex : filter_linear, repeat_disable;
uniform sampler2D mask_tex : filter_linear;
uniform vec2 center = vec2(0.5);
uniform vec2 half_size = vec2(0.25);
uniform bool has_map = true;
void fragment() {
	vec2 uv = center + (UV - vec2(0.5)) * 2.0 * half_size;
	vec4 c = vec4(0.05, 0.08, 0.1, 1.0);
	if (has_map && uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
		c = texture(map_tex, uv);
	}
	COLOR = vec4(c.rgb, texture(mask_tex, UV).a);
}
"""

signal target_requested(id: int)
signal say_requested(text: String)
signal leave_requested
signal quit_requested
signal skin_requested(skin: int)
signal npc_option(command: int, task: int) # NPC_GIVE_TASK / NPC_COMPLETE_TASK / TALK_GIVEUP_TASK
signal npc_closed
signal quest_abandon_requested(id: int)
signal award_task_requested(id: int) # Shylias Markt: Fenster-Quest annehmen (Z5)
signal route_npc_requested(tid: int) # NPC-Link angeklickt
signal map_route_requested(world: Vector2) # Klick auf die Minimap (x, z)
signal pos_route_requested(goal: Vector3, world_id: int, label: String) # Koordinaten-Link (&pos:...&)
signal target_route_requested(kind: String, id: int, quest: int) # Ziel-Link einer Quest (Z3): "mon" Monster / "item" Gegenstand
signal equip_requested(pos: int) # Taschenplatz anlegen (Ziehen auf einen Ausrüstungsplatz)
signal use_requested(pos: int) # Rechtsklick auf einen Taschenplatz: benutzen bzw. anlegen
signal destroy_requested(pos: int, id: int) # Zerstören bestätigt
signal unequip_requested(slot: int, pos: int) # Ausrüstungsplatz ablegen (pos -1 = erster freier)
signal move_item_requested(from: int, to: int)
signal revive_requested
signal shortcut_requested(bar: int, slot: int, id: int) # Platz einer Schnellleiste belegen (id 0 = leeren)
signal skills_seen_requested(ids: Array) # aus "Neue Fertigkeiten" weggelegt
signal skill_use_requested(id: int) # Taste 1 - 0 oder Klick auf einen Platz einer Schnellleiste
signal skill_learn_requested(id: int) # Plus-Knopf im K-Fenster: nächste Stufe lernen (F8)
signal basic_action_requested(action: String) # Grundaktion (Win_BaseSkill): attack, interrupt ...

# Abklingzeit-Uhr über einem Fertigkeiten-Platz (wie EC_ClockIcon): dunkles Tortenstück für die
# restliche Zeit, im Uhrzeigersinn ablaufend; ohne genug Mana oder gesperrt (Siegel) ist das Symbol dunkler
class CoolOverlay extends Control:
	var hud
	var _left = -1.0
	var _dim = false
	var _on = false # Schalter eingeschaltet: heller Rahmen (SNOTIFY_SWITCHON)
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
	func _process(_delta: float) -> void:
		var id = int(get_parent().get_meta("skill", 0))
		var f = hud.cool_fraction(id) if id != 0 else 0.0
		if absf(f - _left) > 0.002 or (f == 0.0 and _left != 0.0):
			_left = f
			queue_redraw()
		var on = id != 0 and hud.switched.has(id)
		if on != _on:
			_on = on
			queue_redraw()
		var dim = id != 0 and (not hud.mana_ok(id) or hud.skill_sealed(id))
		if dim != _dim:
			_dim = dim
			var sym = get_parent().get_node_or_null("Symbol")
			if sym != null:
				sym.modulate = Color(0.45, 0.45, 0.55) if dim else Color.WHITE
	func _draw() -> void:
		if _on:
			draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color(1.0, 0.86, 0.35), false, 2.0)
		if _left <= 0.0:
			return
		var c = size / 2.0
		var r = size.length()
		var pts = PackedVector2Array([c])
		var a0 = -PI / 2.0 + (1.0 - _left) * TAU
		var n = maxi(2, int(_left * 32))
		for i in n + 1:
			var a = a0 + (TAU - (a0 + PI / 2.0)) * i / n
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		var box = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
		for poly in Geometry2D.intersect_polygons(pts, box):
			draw_colored_polygon(poly, Color(0, 0, 0, 0.6))

# Marken auf der Minimap (Position im Radar, Art)
class RadarMarks extends Control:
	var marks: Array = [] # [Vector2, Texture2D]
	func _draw() -> void:
		for m in marks:
			var tex: Texture2D = m[1]
			if tex != null:
				draw_texture(tex, m[0] - tex.get_size() / 2.0)

var aui: AuiManager
var skin = 2
var language = "Deu"
var dialogs = {} # Kurzname ("CharHead") -> aui_dialog.gd
var map_name = ""
var map_title = ""
var target_id = 0
var target_kind = ""
var stats = {} # name, level, class, hp, max_hp, mp, max_mp, exp, exp_next
var chat_lines: Array = []
var warnings: Array = []
var _hide_re = RegEx.new()
var _chat_edit: LineEdit
var _radar: ColorRect
var _radar_marks: RadarMarks
var _arrow: TextureRect
var _map_rect = Rect2() # Welt: x links, z oben, Breite, Höhe (nach unten = -z)
var _mark_tex = {}
var quest_text: Callable = func(t): return t # Platzhalter (quest_data.gd format_text), setzt die Welt
var npc_entries: Array = []
var npc_task = 0 # Quest des laufenden Gesprächs
var _npc_hello = ""
var _npc_talk = {} # talk_proc des laufenden Gesprächs, {} = Übersicht
var _npc_options: Array = [] # zur Liste: ["entry", Eintrag] / ["option", Option] / ["exit"]
var quest_entries: Callable = func(): return [] # quest_data.gd log_entries, setzt die Welt
var quest_list: Array = [] # Einträge des offenen Quest-Fensters
var quest_selected = 0
var trace_entries: Array = [] # Einträge der Verfolgung (quest_data.gd trace)
var trace_folded = {} # Quest -> true (eingeklappt)
var des_quest = 0 # Quest in Win_QuestMinionDes
var option_quest = 0 # Quest des offenen Popups Win_QuestOption / Win_QuestMinionOption
var _trace_line_quest: Array = [] # je Zeile (Absatz) der Verfolgung ihre Quest
var route_target = null # Vector3: Ziel der Autoroute (Minimap)
var _trace_label: RichTextLabel
var _radar_pos = Vector3.ZERO
var _radar_scale = 1.0
var items = null # item_data.gd (setzt die Welt)
var award_state: Callable = func(_id): return 1 # Quest-Zustand für Shylias Markt (quest_data.gd award_state, setzt die Welt)
var item_count: Callable = func(_id): return 0 # Anzahl in der Tasche (setzt die Welt)
var lvup_tab = LVUP_OPEN_TAB
var _lvup = null # {tables: {N: [Einträge]}, tabs: {N: Text}, btn: {2: annehmen, 4: erledigt, 1: gesperrt}}
var _lvup_entries: Array = []
var skills = null # Plugin Data/angelica_skills.gd: Namen, Beschreibungen, Symbole (setzt die Welt)
var skill_state = {"skills": {}, "new": [], "shortcuts": {}} # ID -> Stufe, [IDs], Vector2i(Leiste, Platz) -> ID
var skill_info = {} # "ID" -> Werte vom Server (mp, time, cool, ...; setzt die Welt)
var cooldowns = {} # ID -> [Ende ms, Dauer ms]
var buffs = null # Plugin Data/angelica_buffs.gd: Art, Symbol, Text der Statuseffekte (setzt die Welt)
var seals = {} # eigene Siegel (Meldung seal, setzt die Welt): silent / disarm sperren Fertigkeiten
var switched = {} # eingeschaltete Schalter-Fertigkeiten (F7, Meldung skill_switch): ID -> true, Symbol mit Rahmen
var my_buffs: Array = [] # eigene Effekte [[ID, Stapel, Ende ms (0 = ohne Ende), Dauer ms, light]]
var target_buffs: Array = [] # Effekte des Ziels, gleiche Form
var _buff_lists = {} # Sammelplätze in Win_Buff: "long" / "more" / "more_debuff" -> Effekte
var _buff_hover = [] # [Art, Platz] unter der Maus (Tooltip mit laufender Restzeit)
var _buff_t = 0.0
var _skill_page = 0
var skill_tab = "class" # Reiter des K-Fensters (TAB_ORDER)
var catalog = {} # Klassen-Fertigkeiten (skills.catalog / skill_catalog): ID -> {next, req, cost, max, type, use, first}
var race_list: Array = [] # Rassen-Fertigkeiten der Figur (skills.race_skills), auch noch nicht erhaltene: IDs
var race_info = {} # ID -> {type, use} der Rassen-Fertigkeiten (Art in der Liste, passiv)
var _view_ids: Array = [] # Fertigkeit je Platz der Liste (0 = leer)
var _view_slots = 0 # Plätze in Win_Skill_View
var _view_scroll = 0.0
var _view_max = 0.0
var _talent_dlg = null # Talentbaum der Klasse (ab Stufe 20)
var _talent_hint_text = ""
var _action_atlas = {} # iconlist_action: tex, w, h, cols, index
var _action_icons = {}
var _new_page = 0
var _drag_shortcut = Vector2i(-1, -1) # aus einer Leiste gezogen: ohne Ziel leeren
var _drag_item = -1 # aus der Tasche gezogen: in die Welt fallen gelassen -> zerstören
var destroy_mode = false # Btn_Destroy: der nächste Linksklick auf einen Taschenplatz zerstört
var _destroy_pending = {} # Win_Destroy offen: {pos, id, key}
var me = {} # eigene Figur für Tooltips / Fenster: {name, level, race, class, gender, appearance}
var inventory = {"size": 24, "bag": {}, "equip": {}} # Platz -> [ID, Anzahl] / Platz -> ID
var equip_models: Callable = func(_e): return {} # {Platz: ID} -> {Platz: Modellpfad} (setzt die Welt)
var _data_root = ""
var _login_strings = {}
var _tooltip: PanelContainer
var _tooltip_text: RichTextLabel


# -> "" oder Fehlertext
func setup(data_root: String, p_language: String, p_skin: int, p_map: String, world_id: int) -> String:
	name = "HUD"
	language = p_language
	_data_root = data_root
	map_name = p_map
	_hide_re.compile(HIDE_RE)
	aui = AuiManager.new()
	aui.name = "HUD-Oberfläche"
	aui.keys_enabled = false
	add_child(aui)
	var err = aui.setup(data_root, language)
	if err != "":
		return err
	skin = p_skin
	if aui.load_layout("%dgameui" % skin) == 0:
		skin = 3 - skin
		if aui.load_layout("%dgameui" % skin) == 0:
			return "Dialog-Liste gameui fehlt"
	for short in SHOWN + TARGETS.values() + [MENU, NPC, QUEST, QUEST_DES, INVENTORY, CHARACTER, PROGRESS, REVIVE, SKILLS, NEW_SKILLS,
			BASE_SKILLS, TALENT_HINT, LVUP, DESTROY, CHARACTER_DETAIL, QUEST_OPTION, QUEST_MINION_OPTION]:
		var d = aui.dialog("%d%s.xml" % [skin, short])
		if d == null:
			warnings.append("Dialog %d%s.xml fehlt" % [skin, short])
			continue
		dialogs[short] = d
		_hide_items(short, d)
		# Knöpfe nehmen keinen Tastaturfokus (wie AUI): Tab / Enter / Esc bleiben beim Spiel
		for item in d._items.values():
			if item is BaseButton:
				item.focus_mode = Control.FOCUS_NONE
		d.command.connect(_on_command.bind(short))
	_arrange()
	for short in SHOWN:
		if dialogs.has(short):
			aui.show_dialog(dialogs[short])
	_setup_chat()
	close_chat.call_deferred() # DEFAULT_Txt_Speech bekäme sonst beim Zeigen den Fokus
	_setup_menu()
	_setup_npc()
	_setup_quest()
	_setup_trace()
	set_trace([])
	_login_strings = aui.ui.read_string_table("loginui")
	_setup_tooltip()
	_setup_inventory()
	_setup_character()
	_setup_skills()
	_setup_buffs()
	_read_map_data(data_root, world_id)
	_setup_minimap()
	for w in aui.warnings:
		warnings.append(w)
	return ""

func dlg(short: String):
	return dialogs.get(short)

func texts() -> Dictionary:
	return TEXTS.get(language, TEXTS["Deu"])

# Lage wie RearrangeWindows als Listen-Position (bleibt beim Ändern der Fenstergröße erhalten):
# unten bündig heißt y < -1, darüber liegende Fenster haben y = y des unteren - dessen Höhe
func _arrange() -> void:
	var q = dlg("QuickBar0")
	if q != null:
		q.layout_pos = Vector2i(-1, -2)
	var head = dlg("CharHead")
	if head != null:
		for short in TARGETS.values():
			if dialogs.has(short):
				dialogs[short].layout_pos = Vector2i(head.layout_pos.x + int(head.size.x), head.layout_pos.y)
	var below = dlg("Chat")
	for short in ["ChatInfo", "ChatInfo2"]:
		var d = dlg(short)
		if d != null and below != null and below.layout_pos.y < -1:
			d.layout_pos = Vector2i(below.layout_pos.x, below.layout_pos.y - int(below.size.y))
			below = d

func _hide_items(short: String, d) -> void:
	var hide: Array = HIDE.get(short, []) if short != CHARACTER_DETAIL else HIDE[CHARACTER] + CHAR_DETAIL_HIDE
	for item_name in d._items:
		if item_name in hide or _hide_re.search(item_name) != null:
			d.show_item(item_name, false)


# ====================================================
# EIGENE WERTE (Win_CharHead, Win_QuickBar0)
# ====================================================
func set_stats(s: Dictionary) -> void:
	stats.merge(s, true)
	if window_open(CHARACTER):
		refresh_character()
	if window_open(SKILLS) and (s.has("level") or s.has("money") or s.has("bind_money")):
		refresh_skills() # Plus-Knöpfe: Stufe / Geld
	if window_open(INVENTORY):
		refresh_inventory()
	if s.has("level"):
		refresh_lvup()
	var d = dlg("CharHead")
	if d != null:
		d.set_text("Txt_Name", str(stats.get("name", "")))
		d.set_color("Txt_Name", NAME_COLOR)
		d.set_text("Txt_Lv0", str(stats.get("level", 1)))
		var hp = int(stats.get("hp", 0))
		var max_hp = maxi(1, int(stats.get("max_hp", 1)))
		var mp = int(stats.get("mp", 0))
		var max_mp = maxi(1, int(stats.get("max_mp", 1)))
		d.set_progress("Prgs_HP", 100.0 * hp / max_hp)
		d.set_text("Txt_HP", "%d/%d" % [hp, max_hp])
		d.set_progress("Prgs_MP", 100.0 * mp / max_mp)
		d.set_text("Txt_MP", "%d/%d" % [mp, max_mp])
		d.set_frame("Pic_Prof0", int(stats.get("class", 1)) - 1)
		d.set_progress("Prgs_Xp", 0.0)
		d.set_text("Txt_XP", "0/100")
		d.set_frame("Img_Doubleexp", 0)
	var q = dlg("QuickBar0")
	if q != null:
		var nxt = int(stats.get("exp_next", 0))
		q.set_progress("Pro_Exp", 100.0 * int(stats.get("exp", 0)) / nxt if nxt > 0 else 100.0)


# ====================================================
# ZIEL (Win_TargetMonster / Win_TargetNPC / Win_TargetPlayer)
# ====================================================
# t: Antwort von "target" (kind, level, hp, max_hp, mp, max_mp); display_name / color vom Aufrufer
func show_target(t: Dictionary, display_name: String, color: Color) -> void:
	clear_target()
	target_id = int(t.get("id", 0))
	target_kind = str(t.get("kind", ""))
	var d = dlg(TARGETS.get(target_kind, ""))
	if d == null:
		return
	d.set_text("Txt_Name", display_name)
	d.set_color("Txt_Name", color)
	d.set_text("Txt_LV", str(t.get("level", "")))
	d.set_text("Lab_Level", str(t.get("level", ""))) # Win_TargetPlayer
	if t.has("class"):
		d.set_frame("Pic_Prof", int(t["class"]) - 1)
	d.set_progress("Prg_HP", 100.0 * int(t.get("hp", 0)) / maxi(1, int(t.get("max_hp", 1))))
	d.set_progress("Prg_MP", 100.0 * int(t.get("mp", 0)) / maxi(1, int(t.get("max_mp", 1))) if int(t.get("max_mp", 0)) > 0 else 0.0)
	aui.show_dialog(d)

# Leben / Mana des Ziels nach einem Treffer
func update_target(hp: int, max_hp: int) -> void:
	var d = dlg(TARGETS.get(target_kind, ""))
	if d != null and d.visible:
		d.set_progress("Prg_HP", 100.0 * hp / maxi(1, max_hp))

# "Ihr seid gestorben!" zeigen / schließen
func show_revive(on: bool) -> void:
	var d = dlg(REVIVE)
	if d == null:
		return
	if on:
		d_revive_enable(true)
		aui.show_dialog(d)
	else:
		aui.hide_dialog(d)

func revive_shown() -> bool:
	return window_open(REVIVE)

func d_revive_enable(on: bool) -> void:
	var d = dlg(REVIVE)
	if d != null:
		d.enable_item("Btn_Decide", on)

func clear_target() -> void:
	target_id = 0
	target_kind = ""
	for short in TARGETS.values():
		if dialogs.has(short):
			aui.hide_dialog(dialogs[short])
	target_buffs = []
	refresh_target_buffs()

func target_shown() -> bool:
	return target_id != 0


# ====================================================
# STATUSEFFEKTE (Win_Buff, st_ / debuff_ im Ziel-Fenster)
# ====================================================
func _setup_buffs() -> void:
	var d = dlg(BUFF)
	if d != null:
		for i in BUFF_SLOTS:
			_prep_buff(d.item("Img_Buff%d" % i), "own", i)
			var label = d.item("Txt_Time%d" % i)
			if label is Label:
				label.set_meta("color", label.get_theme_color("font_color"))
	for short in TARGETS.values():
		var td = dlg(short)
		if td == null:
			continue
		for i in TARGET_BUFF_SLOTS:
			_prep_buff(td.item("st_%d" % (i + 1)), "st", i)
			_prep_buff(td.item("debuff_%d" % (i + 1)), "debuff", i)
	refresh_buffs()
	refresh_target_buffs()

# Effekt-Platz: Bild des Dialogs merken (Sammelplätze zeigen es wieder), Stapelzahl unten rechts, Tooltip
func _prep_buff(c, kind: String, idx: int) -> void:
	if not c is TextureRect:
		return
	c.set_meta("default_tex", c.texture)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.tooltip_text = "" # Hint ^Dialog:Win_Buff_Hint (Img_Buff0) zeigt hier der eigene Tooltip
	var stack = Label.new()
	stack.name = "Stack"
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	stack.add_theme_font_size_override("font_size", 10)
	stack.add_theme_constant_override("outline_size", 3)
	stack.add_theme_color_override("font_outline_color", Color.BLACK)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(stack)
	c.mouse_entered.connect(_on_buff_hover.bind(kind, idx))
	c.mouse_exited.connect(_on_buff_exit)

func set_buffs(list: Array) -> void:
	my_buffs = list
	refresh_buffs()

func set_target_buffs(list: Array) -> void:
	target_buffs = list
	refresh_target_buffs()

func _buff_type(e: Array) -> int:
	return buffs.type(int(e[0])) if buffs != null else -1

# Wie CDlgBuff::UpdateBuff: Stärkungen ab Platz 1 (Platz 0 = lange), bei mehr als 28 ist Platz 1 der Sammelplatz;
# Schwächungen ab der nächsten vollen Reihe, passen sie nicht, ist deren erster Platz der Sammelplatz
func refresh_buffs() -> void:
	var d = dlg(BUFF)
	if d == null:
		return
	for i in BUFF_SLOTS:
		_buff_slot(d, i, null)
		d.show_item("Img_Buff%d" % i, false)
		d.show_item("Txt_Time%d" % i, false)
	for n in ["Txt_Buff", "Txt_Debuff_1", "Txt_Debuff_2", "Txt_Debuff_3", "Img_Buff_Back_Sign_2", "Img_Buff_Back_Sign_3",
			"Img_Debuff_Back_Sign_2", "Img_Debuff_Back_Sign_3", "Img_Debuff_Back_Sign_4"]:
		d.show_item(n, false)
	for n in ["Img_Buff0", "Txt_Buff_Long", "Img_Buff_Back_Sign_1"]:
		d.show_item(n, true)
	_buff_lists = {"long": [], "more": [], "more_debuff": []}
	var short = []
	var debuffs = []
	for e in my_buffs:
		var t = _buff_type(e)
		if t == BUFF_TYPE_BUFF and (int(e[3]) / 1000 - 1) / 60 + 1 >= LONG_BUFF_MINUTES:
			_buff_lists["long"].append(e)
		elif t == BUFF_TYPE_BUFF or t == BUFF_TYPE_BUFF_NO_TIME:
			short.append(e)
		elif t == BUFF_TYPE_DEBUFF or t == BUFF_TYPE_DEBUFF_NO_TIME:
			debuffs.append(e)
	_set_collector(d, 0, "long")
	var more = maxi(0, short.size() - (3 * BUFF_PER_LINE - 2))
	var slot = 1
	if more > 0:
		_buff_lists["more"] = short.slice(0, more)
		_set_collector(d, 1, "more")
		d.set_text("Txt_Buff", str(more))
		d.show_item("Txt_Buff", true)
		slot = 2
	for e in short.slice(more):
		_buff_slot(d, slot, e)
		slot += 1
	var first = 3 * BUFF_PER_LINE if more > 0 else (short.size() + BUFF_PER_LINE) / BUFF_PER_LINE * BUFF_PER_LINE
	var more_d = maxi(0, debuffs.size() - (BUFF_SLOTS - first - 1))
	slot = first
	if more_d > 0:
		_buff_lists["more_debuff"] = debuffs.slice(0, more_d)
		_set_collector(d, first, "more_debuff")
		d.set_text("Txt_Debuff_%d" % (first / BUFF_PER_LINE), str(more_d))
		d.show_item("Txt_Debuff_%d" % (first / BUFF_PER_LINE), true)
		slot = first + 1
	for e in debuffs.slice(more_d):
		_buff_slot(d, slot, e)
		slot += 1
	# Zeichen Stärkung / Schwächung rechts neben den Reihen
	var nd = debuffs.size()
	match first:
		10:
			d.show_item("Img_Debuff_Back_Sign_2", nd > 0)
			d.show_item("Img_Debuff_Back_Sign_3", nd > 10)
			d.show_item("Img_Debuff_Back_Sign_4", nd > 20)
		20:
			d.show_item("Img_Buff_Back_Sign_2", true)
			d.show_item("Img_Debuff_Back_Sign_3", nd > 0)
			d.show_item("Img_Debuff_Back_Sign_4", nd > 10)
		30:
			d.show_item("Img_Buff_Back_Sign_2", true)
			d.show_item("Img_Buff_Back_Sign_3", true)
			d.show_item("Img_Debuff_Back_Sign_4", nd > 0)
	d.set_text("Txt_Buff_Long", str(_buff_lists["long"].size()))
	_update_buff_times()

# Sammelplatz: Bild des Dialogs (Buff_Long / Buff_More / Debuff_More), Liste im Tooltip
func _set_collector(d, i: int, list: String) -> void:
	_buff_slot(d, i, null)
	var c = d.item("Img_Buff%d" % i)
	if c != null:
		c.set_meta("list", list)
		c.visible = true

# Platz i mit Effekt e (null = leeren); ohne Symbol bleibt er leer (CDlgBuff::SetBuff)
func _buff_slot(d, i: int, e) -> void:
	var c = d.item("Img_Buff%d" % i) as TextureRect
	var label = d.item("Txt_Time%d" % i)
	if c == null:
		return
	if label != null:
		label.set_meta("buff", null)
	c.remove_meta("list")
	if not _fill_buff(c, e):
		return
	c.visible = true
	var t = _buff_type(e)
	if label != null and (t == BUFF_TYPE_BUFF or t == BUFF_TYPE_DEBUFF):
		label.set_meta("buff", e)
		label.visible = true

# Symbol und Stapel eines Effekt-Platzes; false = leer (kein Effekt oder kein Symbol)
func _fill_buff(c: TextureRect, e) -> bool:
	var tex = buffs.icon(int(e[0])) if e != null and buffs != null else null
	var stack = c.get_node_or_null("Stack") as Label
	c.texture = tex if tex != null else c.get_meta("default_tex", null)
	c.set_meta("buff", e if tex != null else null)
	if stack != null:
		stack.text = str(int(e[1])) if tex != null and int(e[1]) > 1 else ""
	return tex != null

# Wie CDlgTarget: Stärkungen in st_1..8, Schwächungen in debuff_1..8 des sichtbaren Ziel-Fensters
func refresh_target_buffs() -> void:
	for short in TARGETS.values():
		var d = dlg(short)
		if d == null:
			continue
		var list = target_buffs if TARGETS.get(target_kind, "") == short else []
		for kind in ["st", "debuff"]:
			var j = 0
			for e in list:
				if j >= TARGET_BUFF_SLOTS:
					break
				var t = _buff_type(e)
				if (t == BUFF_TYPE_BUFF or t == BUFF_TYPE_BUFF_NO_TIME) if kind == "st" else (t == BUFF_TYPE_DEBUFF or t == BUFF_TYPE_DEBUFF_NO_TIME):
					var c = d.item("%s_%d" % [kind, j + 1])
					if c is TextureRect:
						_fill_buff(c, e)
					j += 1
			while j < TARGET_BUFF_SLOTS:
				var c = d.item("%s_%d" % [kind, j + 1])
				if c is TextureRect:
					_fill_buff(c, null)
				j += 1
	if not _buff_hover.is_empty() and _buff_hover[0] != "own":
		_on_buff_hover(_buff_hover[0], _buff_hover[1])

# Restzeit wie CDlgBuff::GetBuffTime -> [Text, rot]; ohne Ende / abgelaufen ""
func buff_time_text(end_ms: int) -> Array:
	if end_ms <= 0:
		return ["", false]
	var s = ceili((end_ms - Time.get_ticks_msec()) / 1000.0)
	if s <= 0:
		return ["", false]
	var f: Array = texts()["buff_time"]
	var text = f[0] % ((s - 1) / 3600 + 1) if s >= 3600 else (f[1] % ((s - 1) / 60 + 1) if s >= 60 else f[2] % s)
	return [text, s < BUFF_RED_SECONDS]

func _update_buff_times() -> void:
	var d = dlg(BUFF)
	if d == null:
		return
	for i in BUFF_SLOTS:
		var label = d.item("Txt_Time%d" % i) as Label
		if label == null or not label.visible or label.get_meta("buff", null) == null:
			continue
		var r = buff_time_text(int(label.get_meta("buff")[2]))
		d.set_text("Txt_Time%d" % i, r[0])
		label.add_theme_color_override("font_color", Color(1, 0, 0) if r[1] else label.get_meta("color", Color.WHITE))
	if not _buff_hover.is_empty():
		_on_buff_hover(_buff_hover[0], _buff_hover[1])

func _process(delta: float) -> void:
	_buff_t += delta
	if _buff_t >= BUFF_REFRESH:
		_buff_t = 0.0
		_update_buff_times()

# Platz-Control: own = Win_Buff Img_Buff<i>, st / debuff = Ziel-Fenster st_<i + 1> / debuff_<i + 1>
func buff_control(kind: String, idx: int) -> Control:
	if kind == "own":
		return dlg(BUFF).item("Img_Buff%d" % idx) if dlg(BUFF) != null else null
	var d = dlg(TARGETS.get(target_kind, ""))
	return d.item("%s_%d" % [kind, idx + 1]) if d != null else null

# Tooltip: Text des Effekts (buff_str) und Restzeit; Sammelplätze listen ihre Effekte mit Restzeit
func _on_buff_hover(kind: String, idx: int) -> void:
	_buff_hover = [kind, idx]
	var c = buff_control(kind, idx)
	if c == null or not c.is_visible_in_tree() or buffs == null:
		hide_tooltip()
		return
	var lines = []
	if c.has_meta("list"):
		for e in _buff_lists.get(str(c.get_meta("list")), []):
			lines.append("%s  %s" % [buffs.title(int(e[0])).replace("[", "[lb]"), buff_time_text(int(e[2]))[0]])
	elif c.get_meta("buff", null) != null:
		var e: Array = c.get_meta("buff")
		var text = buffs.desc(int(e[0]))
		lines.append(buffs.bbcode(text) if text != "" else str(int(e[0])))
		var left = buff_time_text(int(e[2]))[0]
		if left != "":
			lines.append(texts()["buff_left"] % left)
	if lines.is_empty():
		hide_tooltip()
		return
	show_tooltip("\n".join(lines))

func _on_buff_exit() -> void:
	_buff_hover = []
	hide_tooltip()


# ====================================================
# CHAT (Win_Chat, Win_ChatInfo)
# ====================================================
func _setup_chat() -> void:
	var d = dlg("Chat")
	if d == null:
		return
	_chat_edit = d.item("DEFAULT_Txt_Speech") as LineEdit
	if _chat_edit != null:
		_chat_edit.max_length = Proto.CHAT_MAX
		_chat_edit.gui_input.connect(_on_chat_input)
	var info = dlg("ChatInfo")
	if info != null:
		info.check_item("Btn_Set1", true)
		var content = info.item("Txt_Content")
		if content is RichTextLabel:
			content.scroll_following = true
		# Kanal der Eingabe: "Sagen" heißt im Verlauf wie der erste Reiter ("Normal")
		var way = d.item("Txt_Speakway")
		if way is OptionButton and info.get_text("Btn_Set1") != "":
			way.clear()
			way.add_item(info.get_text("Btn_Set1"))
			way.select(0)

func chat_focused() -> bool:
	return _chat_edit != null and _chat_edit.has_focus()

# Tippt der Spieler gerade in ein Textfeld (Chat, Schlüsselwort in Win_Destroy)? Dann keine Tasten fürs Spiel
func text_focused() -> bool:
	if chat_focused():
		return true
	var f = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return f is LineEdit or f is TextEdit

func open_chat() -> void:
	if _chat_edit != null:
		_chat_edit.grab_focus()

func close_chat() -> void:
	if _chat_edit != null:
		_chat_edit.release_focus()

func _on_chat_input(event: InputEvent) -> void:
	var k = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		_chat_edit.accept_event()
		close_chat()

func _send_chat() -> void:
	if _chat_edit == null:
		return
	var text = _chat_edit.text.strip_edges()
	_chat_edit.text = ""
	close_chat()
	if text != "":
		say_requested.emit(text)

# Nachricht eines Spielers im Verlauf
func add_chat(from_name: String, text: String) -> void:
	_add_line("^%s%s^%s: %s" % [CHAT_NAME_COLOR, _escape(from_name), CHAT_TEXT_COLOR, _escape(text)])

func add_system(text: String) -> void:
	_add_line("^%s%s" % [SYSTEM_COLOR, _escape(text)])

# Hinweis des Spiels (Quests, Belohnungen) in Gelb
func add_info(text: String) -> void:
	_add_line("^%s%s" % [INFO_COLOR, _escape(text)])

# Verlauf übernehmen (Skin-Wechsel)
func set_chat_lines(lines: Array) -> void:
	chat_lines = lines.duplicate()
	var info = dlg("ChatInfo")
	if info != null:
		info.set_text("Txt_Content", "\n".join(chat_lines))

func _add_line(line: String) -> void:
	chat_lines.append(line)
	if chat_lines.size() > CHAT_LINES:
		chat_lines = chat_lines.slice(chat_lines.size() - CHAT_LINES)
	var info = dlg("ChatInfo")
	if info != null:
		info.set_text("Txt_Content", "\n".join(chat_lines))

static func _escape(s: String) -> String:
	return s.replace("^", "^^")


# ====================================================
# SYSTEMMENÜ (Win_Quit)
# ====================================================
func _setup_menu() -> void:
	var d = dlg(MENU)
	if d != null:
		d.show_item("Title_Logout", true)

func menu_open() -> bool:
	return dialogs.has(MENU) and dialogs[MENU].visible

func open_menu() -> void:
	if dialogs.has(MENU):
		aui.show_dialog(dialogs[MENU])

func close_menu() -> void:
	if dialogs.has(MENU):
		aui.hide_dialog(dialogs[MENU])

func _on_command(cmd: String, short: String) -> void:
	match short:
		"Chat":
			if cmd == "speak":
				_send_chat()
		QUEST_DES:
			if cmd in ["Btn_Close", "IDCANCEL"]:
				close_des()
		LVUP:
			if cmd in ["Btn_Close", "IDCANCEL"]:
				close_lvup()
			elif cmd.begins_with("Rdo_1_") and cmd.substr(6).is_valid_int():
				lvup_tab = int(cmd.substr(6))
				refresh_lvup()
			elif cmd.begins_with("Btn_") and cmd.substr(4).is_valid_int():
				var i = int(cmd.substr(4)) - 1
				if i >= 0 and i < _lvup_entries.size():
					award_task_requested.emit(int(_lvup_entries[i].get("taskid", 0)))
		SKILLS, BASE_SKILLS, "Talent":
			if cmd in ["Btn_Close", "IDCANCEL"]:
				close_window(SKILLS)
			elif _tab_of(cmd) != "":
				select_tab(_tab_of(cmd))
			elif short == SKILLS and cmd.begins_with("Btn_") and cmd.substr(4).is_valid_int():
				_learn_slot(int(cmd.substr(4)) - 1)
		TALENT_HINT:
			if cmd in ["Btn_Close", "IDCANCEL", "IDOK"]:
				aui.hide_dialog(dialogs[TALENT_HINT])
		NEW_SKILLS:
			match cmd:
				"Btn_Close", "IDCANCEL":
					var ids: Array = skill_state["new"].duplicate()
					skills_seen(ids)
					if not ids.is_empty():
						skills_seen_requested.emit(ids)
				"Btn_PageDown":
					_new_page += 1
					refresh_new_skills()
				"Btn_PageUp":
					_new_page = maxi(0, _new_page - 1)
					refresh_new_skills()
		REVIVE:
			if cmd == "Btn_Decide":
				d_revive_enable(false)
				revive_requested.emit()
		INVENTORY:
			if cmd in ["Btn_Close", "IDCANCEL"]:
				close_window(INVENTORY)
			elif cmd == "Btn_Destroy":
				set_destroy_mode(not destroy_mode)
		DESTROY:
			if cmd == "Btn_Confirm":
				_confirm_destroy()
			elif cmd in ["Btn_Close", "IDCANCEL"]:
				close_destroy()
		CHARACTER, CHARACTER_DETAIL:
			if cmd in ["Btn_Close", "IDCANCEL"]:
				close_window(CHARACTER)
			elif cmd == "Rdo_Title":
				char_page(CHARACTER)
			elif cmd == "Rdo_Reputation":
				char_page(CHARACTER_DETAIL)
		QUEST:
			if cmd == "abandon" and quest_selected != 0:
				ask_abandon(quest_selected)
			elif cmd in ["IDCANCEL", "Btn_Close"]:
				close_quests()
		QUEST_OPTION, QUEST_MINION_OPTION:
			var id = option_quest
			close_quest_option()
			if cmd == "Btn_Abandon" and id != 0:
				ask_abandon(id)
			elif cmd == "Btn_Info" and id != 0:
				open_quests()
				select_quest(id)
		NPC:
			if cmd == "back":
				_npc_main()
			elif cmd in ["IDCANCEL", "Btn_Close", "Btn_Close2"]:
				close_npc()
		MENU:
			match cmd:
				"Btn_Return":
					close_menu()
					leave_requested.emit()
				"Btn_Quit":
					close_menu()
					quit_requested.emit()
				"Btn_Back", "Btn_Close", "IDCANCEL":
					close_menu()
				"Btn_ChangeUI":
					close_menu()
					skin_requested.emit(3 - skin)
				"Btn_Setting":
					add_system(texts()["not_yet"])
		"WinMain3":
			if cmd == "Btn_System":
				if menu_open():
					close_menu()
				else:
					open_menu()
			elif cmd == "Btn_Quest":
				toggle_quests()
			elif cmd == "Btn_Inventory":
				toggle_window(INVENTORY)
			elif cmd == "Btn_Character":
				toggle_window(CHARACTER)
			elif cmd == "Btn_Skill":
				toggle_window(SKILLS)
			elif cmd == "Btn_Gift_Lua":
				toggle_lvup()
			elif cmd in MENU_BUTTONS:
				add_system(texts()["not_yet"])


# ====================================================
# NPC-FENSTER (Win_NPC mit Unterdialog Win_NPCContent: Txt_Content, Lst_Main)
# ====================================================
func _setup_npc() -> void:
	var d = dlg(NPC)
	if d == null:
		return
	d.show_item("Btn_Confirm", false)
	var list = d.item("Lst_Main") as ItemList
	if list != null:
		list.item_clicked.connect(_on_npc_click)
		list.item_activated.connect(_on_npc_list)
		list.focus_mode = Control.FOCUS_NONE

func npc_open() -> bool:
	return dialogs.has(NPC) and dialogs[NPC].visible

# NPC-Fenster: Name, Gruß, Einträge [{id, kind, talk, title, icon}]
func open_npc(npc_name: String, hello: String, entries: Array) -> void:
	var d = dlg(NPC)
	if d == null:
		return
	d.set_text("Txt_npc", npc_name)
	_npc_hello = hello
	npc_entries = entries
	_npc_main()
	aui.show_dialog(d)

func close_npc() -> void:
	if npc_open():
		aui.hide_dialog(dialogs[NPC])
		npc_closed.emit()

# Übersicht: Gruß, Quest-Einträge, "Gespräch beenden"
func _npc_main() -> void:
	var d = dlg(NPC)
	_npc_talk = {}
	npc_task = 0
	d.set_text("Txt_Content", _npc_hello)
	var list = d.item("Lst_Main") as ItemList
	list.clear()
	_npc_options = []
	for e in npc_entries:
		var at = list.add_item(e["title"], e.get("icon"))
		if e.get("grey", false): # sichtbar, aber nicht annehmbar: grau wie CDlgNPC (A3DCOLORRGB(128, 128, 128))
			list.set_item_custom_fg_color(at, NPC_GREY)
		_npc_options.append(["entry", e])
	list.add_item(_end_talk())
	_npc_options.append(["exit"])
	d.show_item("Btn_Back", false)

# Fenster win_id des laufenden Gesprächs (-1 = erstes)
func _npc_window(win_id: int) -> void:
	var wins: Array = _npc_talk.get("windows", [])
	var win = wins[0] if not wins.is_empty() else {}
	for w in wins:
		if int(w["id"]) == win_id:
			win = w
	var d = dlg(NPC)
	d.set_text("Txt_Content", quest_text.call(str(win.get("text", ""))))
	var list = d.item("Lst_Main") as ItemList
	list.clear()
	_npc_options = []
	for o in win.get("options", []):
		list.add_item(_plain(quest_text.call(str(o["text"]))))
		_npc_options.append(["option", o])
	if _npc_options.is_empty():
		list.add_item(_end_talk())
		_npc_options.append(["exit"])
	d.show_item("Btn_Back", true)

# "Gespräch beenden" aus der Texttabelle (503, übersetzt aus gameui.stf: "Bis dann." / "See you." / "Au revoir."; die
# Skin-Tabelle allein hätte "再见。")
func _end_talk() -> String:
	var end = aui.text(STF_END_TALK)
	var re = RegEx.new()
	re.compile("[\\x{3000}-\\x{9fff}]")
	return end if end != "" and re.search(end) == null else texts()["end_talk"]

func _on_npc_click(index: int, _at: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_on_npc_list(index)

func _on_npc_list(index: int) -> void:
	if index < 0 or index >= _npc_options.size():
		return
	var o: Array = _npc_options[index]
	match o[0]:
		"exit":
			close_npc()
		"entry":
			_npc_talk = o[1]["talk"]
			npc_task = int(o[1]["id"])
			_npc_window(-1)
		"option":
			var id = int(o[1]["id"])
			var param = int(o[1].get("param", 0))
			if id < 0x80000000:
				_npc_window(id)
			elif id == NPC_GIVE_TASK or id == NPC_COMPLETE_TASK or id == TALK_GIVEUP_TASK:
				npc_option.emit(id, param if param != 0 else npc_task) # die Welt merkt sich dabei den NPC
				close_npc() # wie CDlgNPC: nach dem Befehl zu (kein zweites Mal)
			elif id == TALK_RETURN:
				_npc_main()
			elif id == TALK_EXIT:
				close_npc()
			else:
				add_system(texts()["not_yet"])

# Farbcodes für die Liste entfernen (ItemList kennt keine)
static func _plain(s: String) -> String:
	var re = RegEx.new()
	re.compile("\\^([0-9a-fA-F]{6}|O\\d{3}|[a-zA-Z])")
	return re.sub(s, "", true)


# ====================================================
# QUEST-FENSTER (Win_Quest mit Unterdialog Win_QuestContent)
# ====================================================
func _setup_quest() -> void:
	var d = dlg(QUEST)
	if d == null:
		return
	d.set_text("Title", texts()["quests_title"])
	d.set_text("Lab_Desc", texts()["desc"])
	d.set_text("Title2", map_title)
	var tree = d.item("Tv_Quest") as Tree
	if tree != null:
		tree.item_selected.connect(func(): _show_quest(int(tree.get_selected().get_metadata(0))))
		tree.focus_mode = Control.FOCUS_NONE
		tree.gui_input.connect(_on_quest_tree_input.bind(tree))
	_setup_quest_options()
	var head = d.item("Txt_QuestItem") as RichTextLabel
	if head != null:
		head.meta_clicked.connect(_on_link)
		head.meta_underlined = false
	for i in 4:
		d.show_item("Img_Item%d" % i, false)
	# Belohnungs-Bilder gibt es noch nicht: die Beschreibung bekommt ihren Platz bis zum Ende des Unterdialogs
	# Sub_QuestContent (abgeschnitten) und rollt mit Mausrad / Leiste
	var content = d.item("Txt_Content")
	var sub = d.item("Sub_QuestContent")
	var bottom = d.item("Img_Item0")
	if content != null and (sub != null or bottom != null):
		content.size.y = (sub.size.y if sub != null else bottom.position.y + bottom.size.y) - content.position.y
	if content is RichTextLabel:
		content.scroll_active = true
		content.mouse_filter = Control.MOUSE_FILTER_STOP # das Mausrad erreicht die Beschreibung

func quest_open() -> bool:
	return dialogs.has(QUEST) and dialogs[QUEST].visible

func toggle_quests() -> void:
	if quest_open():
		close_quests()
	else:
		open_quests()

func close_quests() -> void:
	if quest_open():
		aui.hide_dialog(dialogs[QUEST])

func open_quests() -> void:
	var d = dlg(QUEST)
	if d == null:
		return
	aui.show_dialog(d)
	refresh_quests()

# Liste neu (nach jeder Änderung, solange das Fenster offen ist)
func refresh_quests() -> void:
	var d = dlg(QUEST)
	if d == null or not d.visible:
		return
	quest_list = quest_entries.call()
	d.set_text("Txt_ShuLiang", "%d/%d" % [quest_list.size(), TRACE_MAX])
	var tree = d.item("Tv_Quest") as Tree
	tree.clear()
	var root = tree.create_item()
	var keep = null
	for e in quest_list:
		var it = tree.create_item(root)
		it.set_text(0, _plain(str(e["name"])))
		it.set_custom_color(0, BOOK_TITLE)
		it.set_metadata(0, e["id"])
		if str(e.get("part", "")) != "":
			var sub = tree.create_item(it)
			sub.set_text(0, _plain(str(e["part"])))
			sub.set_metadata(0, e["id"])
		if int(e["id"]) == quest_selected:
			keep = it
	if keep == null and root.get_child_count() > 0:
		keep = root.get_child(0)
	if keep != null:
		keep.select(0)
		_show_quest(int(keep.get_metadata(0)))
	else:
		_show_quest(0)

func _show_quest(id: int) -> void:
	var d = dlg(QUEST)
	quest_selected = id
	var e = {}
	for x in quest_list:
		if int(x["id"]) == id:
			e = x
	_set_rich(d.item("Txt_QuestItem"), _quest_head(e, BOOK_COLORS, true))
	var body = str(e.get("description", ""))
	if str(e.get("award", "")) != "":
		body += "\n\n^%s" % BOOK_COLORS["award"] + _escape(texts()["award"] % e["award"])
	d.set_text("Txt_Content", body)
	_link_markers(d.item("Txt_Content"), BOOK_COLORS["link"])
	d.enable_item("Btn_Abandon", e.get("giveup", false))

# Quest im offenen Quest-Fenster auswählen (CDlgTask::SelectTaskItem, z.B. "Ansehen" im Popup der Verfolgung)
func select_quest(id: int) -> void:
	var tree = dlg(QUEST).item("Tv_Quest") as Tree if dlg(QUEST) != null else null
	if tree == null or tree.get_root() == null:
		return
	for it in tree.get_root().get_children():
		if int(it.get_metadata(0)) == id:
			it.select(0)
			_show_quest(id)
			return

# Aufgeben erst nach Rückfrage (MessageBox "Game_AbortTask", gameui.stf 236), dann an den Server
func ask_abandon(id: int) -> void:
	if aui.has_message_box():
		return
	var ask = aui.text(STF_ABANDON_ASK)
	if await aui.message_box(_plain(ask if ask != "" else texts()["abandon_ask"]), AuiManager.MB_OKCANCEL) == "IDOK":
		quest_abandon_requested.emit(id)


# ====================================================
# POPUPS: Win_QuestOption (Rechtsklick im Quest-Fenster: Verfolgen, Aufgeben, Schließen) und Win_QuestMinionOption
# (Rechtsklick in der Verfolgung: Verfolgung abbrechen, Aufgeben, Ansehen, Schließen) - PopupDialog an der Maus, ein Klick
# daneben schließt. Verfolgen / Verfolgung abbrechen gibt es nur bei manueller Verfolgung (TRACE_MANUAL); wir verfolgen
# alle Quests (wie TRACE_AUTO), daher sind sie wie im Original dann gesperrt.
# ====================================================
func _setup_quest_options() -> void:
	for short in [QUEST_OPTION, QUEST_MINION_OPTION]:
		var d = dlg(short)
		if d == null:
			continue
		d.enable_item("Btn_Focus", false)
		d.enable_item("Btn_Delete", false)

func quest_option_open() -> String:
	for short in [QUEST_OPTION, QUEST_MINION_OPTION]:
		if dialogs.has(short) and dialogs[short].visible:
			return short
	return ""

func open_quest_option(short: String, id: int, at: Vector2) -> void:
	close_quest_option()
	var d = dlg(short)
	if d == null or id == 0:
		return
	option_quest = id
	aui.show_dialog(d)
	# an der Maus (SetPosEx(x, y)), ganz im Bild
	var local = (d.get_parent() as Control).get_global_transform().affine_inverse() * at
	var room = (d.get_parent() as Control).size - d.size
	d.position = Vector2(clampf(local.x, 0.0, maxf(0.0, room.x)), clampf(local.y, 0.0, maxf(0.0, room.y)))

func close_quest_option() -> void:
	for short in [QUEST_OPTION, QUEST_MINION_OPTION]:
		if dialogs.has(short) and dialogs[short].visible:
			aui.hide_dialog(dialogs[short])
	option_quest = 0

func _on_quest_tree_input(event: InputEvent, tree: Tree) -> void:
	var mb = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	var it = tree.get_item_at_position(mb.position)
	if it != null:
		open_quest_option(QUEST_OPTION, int(it.get_metadata(0)), mb.global_position)
		tree.accept_event()

# Rechtsklick auf eine Zeile der Verfolgung -> ihre Quest
func _on_trace_input(event: InputEvent) -> void:
	var mb = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	var id = trace_quest_at(mb.position.y)
	if id != 0:
		open_quest_option(QUEST_MINION_OPTION, id, mb.global_position)
		_trace_label.accept_event()

# Quest der Verfolgungszeile auf Höhe y (Pixel im Textfeld, mit Bildlauf) oder 0
func trace_quest_at(y: float) -> int:
	if _trace_label == null or _trace_line_quest.is_empty():
		return 0
	var at = y + _trace_label.get_v_scroll_bar().value
	var found = -1
	for i in mini(_trace_label.get_paragraph_count(), _trace_line_quest.size()):
		if _trace_label.get_paragraph_offset(i) <= at:
			found = i
		else:
			break
	return int(_trace_line_quest[found]) if found >= 0 else 0

# Klick neben ein offenes Popup schließt es (AUI PopupDialog)
func _close_popup_outside(mb: InputEventMouseButton) -> void:
	var short = quest_option_open()
	if short != "" and not dialogs[short].get_global_rect().has_point(mb.position):
		close_quest_option()


# ====================================================
# QUEST-VERFOLGUNG (Win_QuestMinion: Tv_TraceContent, Txt_ShuLiang) UND Win_QuestMinionDes
# ====================================================
# Text mit Links an der Stelle der Baumansicht (gleiche Schrift)
func _setup_trace() -> void:
	var d = dlg("QuestMinion")
	var tree = d.item("Tv_TraceContent") as Control if d != null else null
	if tree == null:
		return
	_trace_label = RichTextLabel.new()
	_trace_label.name = "Verfolgung"
	_trace_label.bbcode_enabled = true
	_trace_label.meta_underlined = false # nur NPC-Links sind unterstrichen ([u])
	_trace_label.position = tree.position
	_trace_label.size = tree.size
	_trace_label.scroll_active = true
	_trace_label.focus_mode = Control.FOCUS_NONE
	_trace_label.mouse_filter = Control.MOUSE_FILTER_PASS
	if tree.has_theme_font_override("font"):
		_trace_label.add_theme_font_override("normal_font", tree.get_theme_font("font"))
	if tree.has_theme_font_size_override("font_size"):
		_trace_label.add_theme_font_size_override("normal_font_size", tree.get_theme_font_size("font_size"))
	_trace_label.add_theme_color_override("default_color", Color(0.92, 0.92, 0.88))
	_trace_label.add_theme_constant_override("outline_size", 3)
	_trace_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_trace_label.meta_clicked.connect(_on_link)
	_trace_label.gui_input.connect(_on_trace_input)
	tree.get_parent().add_child(_trace_label)
	tree.visible = false
	var des = dlg(QUEST_DES)
	if des != null:
		for i in 4:
			des.show_item("Img_Item%d" % i, false)
		# Unterdialog (233 x 319) ist auf 215 Pixel Höhe abgeschnitten: Beschreibung bis dahin, rollbar
		var content = des.item("Txt_Content")
		var sub = des.item("Sub_Content")
		if content is RichTextLabel:
			content.size.y = (sub.size.y if sub != null else 215.0) - content.position.y
			content.scroll_active = true
			content.mouse_filter = Control.MOUSE_FILTER_STOP # Mausrad
		var head = des.item("Txt_QuestItem") as RichTextLabel
		if head != null:
			head.meta_clicked.connect(_on_link)
			head.meta_underlined = false

# entries: quest_data.gd trace() (id, name, part, goal, talk, npc, done)
func set_trace(entries: Array) -> void:
	trace_entries = entries
	var d = dlg("QuestMinion")
	if d == null:
		return
	d.set_text("Txt_ShuLiang", "%d/%d" % [entries.size(), TRACE_MAX])
	if _trace_label == null:
		return
	var lines = PackedStringArray()
	_trace_line_quest = []
	for e in entries:
		var id = int(e["id"])
		var folded = trace_folded.get(id, false)
		lines.append("[url=fold:%d]%s[/url] [url=quest:%d][color=%s]%s[/color][/url]" % [id, "+" if folded else "-", id,
			TRACE_TITLE_HEX, _bb(_plain(str(e["name"])))])
		if not folded:
			if str(e.get("part", "")) != "":
				lines.append("   " + _bb(_plain(str(e["part"]))) + ((" " + texts()["done_mark"]) if e.get("done", false) else ""))
			if str(e.get("goal", "")) != "":
				var where: Array = e.get("where", [])
				lines.append("   " + _goal_bb(e) + ((" (%s)" % _pos_link(where, LINK_COLOR)) if not where.is_empty() else ""))
			if int(e.get("back", 0)) != 0:
				lines.append("   " + _back_bb(e, LINK_COLOR))
		while _trace_line_quest.size() < lines.size():
			_trace_line_quest.append(id)
	_trace_label.text = "\n".join(lines)
	if des_open():
		_show_des(des_quest)

# Für Tests und Anzeige: je Quest [Titel, Teil, Ziel] als Text
func trace_items() -> Array:
	var out = []
	for e in trace_entries:
		var lines = [_plain(str(e["name"]))]
		if str(e.get("part", "")) != "":
			lines.append(_plain(str(e["part"])) + ((" " + texts()["done_mark"]) if e.get("done", false) else ""))
		if str(e.get("goal", "")) != "":
			lines.append(texts()["talk_to"] % e["goal"] if e.get("talk", false) else str(e["goal"]))
		if int(e.get("back", 0)) != 0:
			lines.append(texts()["return_to"] % str(e.get("back_name", "")))
		out.append(lines)
	return out

# Ziel erreicht: "Zurück zu <NPC>" mit grünem NPC-Link (Abgabe-NPC)
func _back_bb(e: Dictionary, link_color: String) -> String:
	var link = "[url=npc:%d][color=%s][u]%s[/u][/color][/url]" % [int(e["back"]), link_color, _bb(_plain(str(e.get("back_name", ""))))]
	return texts()["return_to"].replace("%s", link)

# Ziel als BBCode, NPC als grüner Link
func _goal_bb(e: Dictionary, prefix: bool = false, link_color: String = LINK_COLOR) -> String:
	var goal = str(e.get("goal", ""))
	if goal == "":
		return ""
	var g = _bb(goal)
	if e.get("talk", false):
		var link = "[url=npc:%d][color=%s][u]%s[/u][/color][/url]" % [int(e.get("npc", 0)), link_color, g] if int(e.get("npc", 0)) != 0 else g
		g = texts()["talk_to"].replace("%s", link)
	elif not e.get("goals", []).is_empty(): # Monster / Gegenstände als grüne Links (Autoroute, Z3)
		g = ", ".join(e["goals"].map(func(x): return "[url=%s][color=%s][u]%s[/u][/color][/url]" % [x["link"], link_color, _bb(str(x["text"]))]))
	return texts()["goal"].replace("%s", g) if prefix else g

# Kopf (Titel, Teil, Ziel mit Link) als BBCode für Win_Quest / Win_QuestMinionDes
func _quest_head(e: Dictionary, colors: Dictionary, prefix: bool) -> String:
	if e.is_empty():
		return ""
	var head = "[color=#%s]%s[/color]" % [colors["title"], _bb(_plain(str(e["name"])))]
	if str(e.get("part", "")) != "":
		head += "\n[color=#%s]%s[/color]" % [colors["part"], _bb(_plain(str(e["part"])))]
	if str(e.get("goal", "")) != "":
		head += "\n[color=#%s]%s[/color]" % [colors["goal"], _goal_bb(e, prefix, colors.get("link", LINK_COLOR))]
	if int(e.get("back", 0)) != 0:
		head += "\n[color=#%s]%s[/color]" % [colors["goal"], _back_bb(e, colors.get("link", LINK_COLOR))]
	return head

func _set_rich(c, bbcode: String) -> void:
	if c is RichTextLabel:
		c.text = bbcode

static func _bb(s: String) -> String:
	return s.replace("[", "[lb]")

# Koordinaten-Link [x, y, z, Welt, Name] als BBCode
static func _pos_link(p: Array, color: String) -> String:
	return "[url=pos:%s,%s,%s,%d:%s][color=%s][u]%s[/u][/color][/url]" % [p[0], p[1], p[2], int(p[3]), str(p[4]).uri_encode(), color,
		_bb(str(p[4]))]

# Marken von quest_data.gd format_text (Koordinaten-Links) im fertigen BBCode eines Textfelds ersetzen
func _link_markers(c, color: String) -> void:
	if not c is RichTextLabel or not c.text.contains("\uE000"):
		return
	var re = RegEx.new()
	re.compile("\uE000([^\uE001]*)\uE001([^\uE002]*)\uE002")
	var out = c.text
	for m in re.search_all(c.text):
		var n = m.get_string(1).split(",")
		if n.size() < 4:
			continue
		out = out.replace(m.get_string(0), _pos_link([n[0].to_float(), n[1].to_float(), n[2].to_float(), n[3].to_int(),
			m.get_string(2)], color))
	c.text = out
	if not c.meta_clicked.is_connected(_on_link):
		c.meta_clicked.connect(_on_link)
		c.meta_underlined = false

func _on_link(meta) -> void:
	var m = str(meta)
	var id = m.get_slice(":", 1).to_int()
	if m.begins_with("npc:"):
		route_npc_requested.emit(id)
	elif m.begins_with("mon:") or m.begins_with("item:"):
		target_route_requested.emit(m.get_slice(":", 0), id, m.get_slice(":", 2).to_int())
	elif m.begins_with("pos:"):
		var parts = m.substr(4).split(":", true, 1)
		var n = parts[0].split(",")
		if n.size() >= 4:
			pos_route_requested.emit(Vector3(n[0].to_float(), n[1].to_float(), n[2].to_float()), n[3].to_int(),
				parts[1].uri_decode() if parts.size() > 1 else "")
	elif m.begins_with("fold:"):
		trace_folded[id] = not trace_folded.get(id, false)
		set_trace(trace_entries)
	elif m.begins_with("quest:"):
		if des_open() and des_quest == id:
			close_des()
		else:
			open_des(id)

func des_open() -> bool:
	return dialogs.has(QUEST_DES) and dialogs[QUEST_DES].visible

func close_des() -> void:
	if des_open():
		aui.hide_dialog(dialogs[QUEST_DES])

# Beschreibung einer Quest links neben der Verfolgung (CDlgTask::OnEventLButtonDown_Trace)
func open_des(id: int) -> void:
	var d = dlg(QUEST_DES)
	var minion = dlg("QuestMinion")
	if d == null or minion == null:
		return
	# rechts bündig wie die Verfolgung: linke Kante der Verfolgung = rechte Kante der Beschreibung
	var x = minion.layout_pos.x - int(minion.size.x) if minion.layout_pos.x < -1 else maxi(0, int(minion.position.x - d.size.x))
	d.layout_pos = Vector2i(x, maxi(0, int(minion.position.y)))
	_show_des(id)
	aui.show_dialog(d)

func _show_des(id: int) -> void:
	var d = dlg(QUEST_DES)
	des_quest = id
	var e = {}
	for x in quest_entries.call():
		if int(x["id"]) == id:
			e = x
	if e.is_empty():
		close_des()
		return
	_set_rich(d.item("Txt_QuestItem"), _quest_head(e, BOOK_COLORS, true)) # auch Pergament
	var body = str(e.get("description", ""))
	if str(e.get("award", "")) != "":
		body += "\n\n^%s" % BOOK_COLORS["award"] + _escape(texts()["award"] % e["award"])
	d.set_text("Txt_Content", body)
	_link_markers(d.item("Txt_Content"), BOOK_COLORS["link"])


# ====================================================
# TASTEN -> true, wenn verbraucht
# ====================================================
# Mausrad über der Liste des K-Fensters: scrollen (statt die Kamera zu zoomen)
func _input(event: InputEvent) -> void:
	var mb = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_close_popup_outside(mb)
	if mb == null or not mb.pressed or not mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	var d = dlg(SKILLS)
	var sub = d.item("Sub_Skill") if d != null and d.visible else null
	if sub != null and sub.get_global_rect().has_point(mb.position):
		_scroll_view(-VIEW_ROW * 0.5 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else VIEW_ROW * 0.5)
		get_viewport().set_input_as_handled()

func handle_key(k: InputEventKey) -> bool:
	if aui.has_message_box():
		return false
	match k.keycode:
		KEY_Q:
			if not text_focused():
				toggle_quests()
				return true
		KEY_B:
			if not text_focused():
				toggle_window(INVENTORY)
				return true
		KEY_C:
			if not text_focused():
				toggle_window(CHARACTER)
				return true
		KEY_K:
			if not text_focused():
				toggle_window(SKILLS)
				return true
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0:
			if not text_focused() and not k.ctrl_pressed and not k.alt_pressed:
				var id = skill_at("bar0", 9 if k.keycode == KEY_0 else k.keycode - KEY_1)
				if id != 0:
					skill_use_requested.emit(id)
				return true
		KEY_ENTER, KEY_KP_ENTER:
			if not text_focused():
				open_chat()
				return true
		KEY_ESCAPE:
			if quest_option_open() != "":
				close_quest_option()
			elif destroy_open():
				close_destroy()
			elif destroy_mode:
				set_destroy_mode(false)
			elif chat_focused():
				close_chat()
			elif npc_open():
				close_npc()
			elif quest_open():
				close_quests()
			elif window_open(INVENTORY) or window_open(CHARACTER) or window_open(SKILLS):
				close_window(INVENTORY)
				close_window(CHARACTER)
				close_window(SKILLS)
			elif des_open():
				close_des()
			elif menu_open():
				close_menu()
			elif target_shown():
				target_requested.emit(0)
			else:
				open_menu()
			return true
	return false


# ====================================================
# SHYLIAS MARKT (Win_LvupAward, Z5)
# ====================================================
func lvup_open() -> bool:
	return dialogs.has(LVUP) and dialogs[LVUP].visible

func toggle_lvup() -> void:
	if lvup_open():
		close_lvup()
	else:
		open_lvup(LVUP_OPEN_TAB)

func open_lvup(tab: int) -> void:
	var d = dlg(LVUP)
	if d == null:
		return
	if _lvup == null:
		_load_lvup()
	lvup_tab = tab
	aui.show_dialog(d)
	refresh_lvup()

func close_lvup() -> void:
	if lvup_open():
		aui.hide_dialog(dialogs[LVUP])
		hide_tooltip()

# Einträge und Texte aus den Lua-Skripten der Sprache (einmal, ~0,15 s)
func _load_lvup() -> void:
	_lvup = {"tables": {}, "tabs": {}, "btn": {}}
	var files = load(FILES).new(_data_root)
	var dir = ""
	for base in [language + "/script", "resources/" + language + "/script"]:
		if files.resolve(base) != "":
			dir = files.resolve(base)
			break
	var lua = load(LUA).new(files)
	var p = files.resolve("designer_string.lua", dir) if dir != "" else ""
	var err = lua.run_file(p) if p != "" else "designer_string.lua fehlt"
	# gameui.lua: GameUI = UIManTemplate:new({...}) - ohne Oberflächen-Laufzeit genügt die übergebene Tabelle
	lua.globals["UIManTemplate"] = {"new": func(a): return [a[1] if a.size() > 1 else {}]}
	var g = files.resolve("interfaces/gameui.lua", dir) if dir != "" else ""
	if err == "":
		err = lua.run_file(g) if g != "" else "interfaces/gameui.lua fehlt"
	if err != "":
		warnings.append("Shylias Markt: " + err)
	for n in LVUP_TABS:
		var t = lua.value("GameUI.Var.LvupItemAward.Rdo_1.Table_%d" % n)
		var list = []
		if t is Dictionary:
			var keys = t.keys().filter(func(k): return k is int)
			keys.sort()
			for k in keys:
				if t[k] is Dictionary:
					list.append((t[k] as Dictionary).duplicate())
		_lvup["tables"][n] = list
		var label = lua.value("DESIGNER_STRING_TABLE.Gift_Rdo1_Table_String_%d" % n)
		if label != null:
			_lvup["tabs"][n] = str(label)
	for e in [[2, "TASK_AWARD_BTN_1_2"], [4, "MYKINGDOM_BTN1_OTHER"], [1, "MYKINGDOM_BTN2_0"]]:
		var v = lua.value("DESIGNER_STRING_TABLE." + e[1])
		_lvup["btn"][e[0]] = str(v) if v != null else ""
	lua.close()

func refresh_lvup() -> void:
	var d = dlg(LVUP)
	if d == null or not d.visible or _lvup == null:
		return
	for n in LVUP_TABS:
		var r = "Rdo_1_%d" % n
		if _lvup["tabs"].has(n):
			d.set_text(r, _lvup["tabs"][n])
		var rb = d.item(r)
		if rb is BaseButton:
			(rb as BaseButton).set_pressed_no_signal(n == lvup_tab)
	var r1 = d.item("Rdo_1")
	if r1 is BaseButton:
		(r1 as BaseButton).set_pressed_no_signal(true)
	_lvup_entries = _lvup["tables"].get(lvup_tab, [])
	for i in LVUP_SLOTS:
		var n = i + 1
		var e: Dictionary = _lvup_entries[i] if i < _lvup_entries.size() else {}
		for k in LVUP_ITEMS:
			d.show_item(k + str(n), not e.is_empty())
		d.show_item("Img_%d" % n, false)
		if e.is_empty():
			continue
		var id = int(e.get("itemid", 0))
		d.set_text("Name_%d" % n, _plain(str(e.get("Name", ""))))
		d.set_text("Price_%d" % n, _plain(str(e.get("Price", ""))))
		d.set_text("Level_%d" % n, str(e.get("level", "")))
		d.set_text("Other_%d" % n, _plain(str(e.get("other", ""))))
		d.set_text("Warning_%d" % n, _plain(str(e.get("warning", ""))))
		d.set_image("Img_icon_%d" % n, items.icon(id) if items != null and id != 0 else null)
		var icon = d.item("Img_icon_%d" % n)
		if icon != null and items != null and id != 0:
			icon.tooltip_text = "%s x%d" % [_plain(str(items.info(id)["name"])), maxi(1, int(e.get("Num", 1)))]
		var state = int(award_state.call(int(e.get("taskid", 0))))
		d.enable_item("Btn_%d" % n, state == 2)
		d.set_text("Btn_%d" % n, str(_lvup["btn"].get(state if state in [2, 4] else 1, "")))
	var essence = items.info(ESSENCE)["name"] if items != null else "Essenz"
	d.set_text("Warning", "%s: %d" % [_plain(str(essence)), int(item_count.call(ESSENCE))])


# ====================================================
# INVENTAR (Win_Inventory) UND CHARAKTER (Win_Character)
# ====================================================
func window_open(short: String) -> bool:
	if short == SKILLS:
		return skill_page() != null # K: eines seiner Fenster (Reiter)
	if short == CHARACTER:
		return char_shown() != null # C: eine seiner Seiten
	return dialogs.has(short) and dialogs[short].visible

func toggle_window(short: String) -> void:
	if window_open(short):
		close_window(short)
	else:
		open_window(short)

func open_window(short: String) -> void:
	var d = dlg(short)
	if d == null:
		return
	if short == SKILLS:
		if skill_tab in ["talent", "soul"] and (int(stats.get("level", 1)) < TALENT_LEVEL or _talent_dialog() == null):
			skill_tab = "class"
		var page = _page_for(skill_tab)
		aui.show_dialog(page if page != null else d)
		_check_tab(skill_tab)
		_refresh_basic_icons()
		refresh_skills()
		return
	aui.show_dialog(d)
	if short == CHARACTER:
		_check_char_tabs(d, CHARACTER)
		refresh_character()
	elif short == SKILLS:
		refresh_skills()
	else:
		refresh_inventory()

func close_window(short: String) -> void:
	if short == SKILLS:
		for page in [dlg(SKILLS), dlg(BASE_SKILLS), _talent_dlg, dlg(TALENT_HINT)]:
			if page != null and page.visible:
				aui.hide_dialog(page)
		hide_tooltip()
		return
	if short == INVENTORY and destroy_mode:
		set_destroy_mode(false) # Zerstören-Modus endet mit dem Inventar (Zeiger zurück)
	if short == CHARACTER:
		for page in [dlg(CHARACTER), dlg(CHARACTER_DETAIL)]:
			if page != null and page.visible:
				aui.hide_dialog(page)
		hide_tooltip()
		return
	if window_open(short):
		aui.hide_dialog(dialogs[short])
		hide_tooltip()

func class_name_of(c: int) -> String:
	return str(_login_strings.get(STF_CLASS + c, c))

func _setup_inventory() -> void:
	var d = dlg(INVENTORY)
	if d == null:
		return
	for item_name in d._items:
		var n = String(item_name)
		if n.begins_with("ItemNewGfx_") or n.begins_with("Img_Enhance") or n.to_lower().contains("fashdress"):
			d.show_item(n, false)
	for i in BAG_SLOTS:
		var c = d.item("Item_%02d" % i)
		if c != null:
			_prep_slot(c, "bag", i)
	var rdo = d.item("Rdo_NormalItem")
	if rdo is BaseButton:
		rdo.button_pressed = true
	var destroy = d.item("Btn_Destroy")
	if destroy != null:
		destroy.set_drag_forwarding(Callable(), func(_at, data): return data is Dictionary and data.get("kind", "") == "bag",
			func(_at, data): _drag_item = -1; ask_destroy(int(data["idx"])))
	var dd = dlg(DESTROY)
	var edit = dd.item("Edt_Input") if dd != null else null
	if edit is LineEdit:
		edit.text_submitted.connect(func(_t): _confirm_destroy())
		edit.gui_input.connect(_on_destroy_input)

func _setup_character() -> void:
	for short in [CHARACTER, CHARACTER_DETAIL]:
		var d = dlg(short)
		if d == null:
			continue
		for item_name in d._items:
			var n = String(item_name)
			if n.to_lower().contains("fashdress") or n.begins_with("Edt_Stone_") or n.begins_with("Prgs_Stone_") or n.begins_with("Txt_Grade") \
					or n.begins_with("Img_Enhance"):
				d.show_item(n, false)
		for i in EQUIP_SLOTS:
			var c = d.item("Equip_%02d" % i)
			if c != null and c.size.x > 4.0 and c.position.x >= 0.0 and c.position.x < d.size.x:
				_prep_slot(c, "equip", i)
		_check_char_tabs(d, short)

# Reiter der beiden Seiten: auf Win_Character ist Rdo_Title gedrückt, auf Win_CharacterDetail Rdo_Reputation
func _check_char_tabs(d, short: String) -> void:
	for r in [["Rdo_Title", CHARACTER], ["Rdo_Reputation", CHARACTER_DETAIL]]:
		if d.item(r[0]) is BaseButton:
			(d.item(r[0]) as BaseButton).set_pressed_no_signal(r[1] == short)

# Offene Seite des Charakters (Win_Character / Win_CharacterDetail) oder null
func char_shown():
	for short in [CHARACTER, CHARACTER_DETAIL]:
		if dialogs.has(short) and dialogs[short].visible:
			return dialogs[short]
	return null

# Seite wechseln wie CDlgCharacter::OnCommand_Page: die andere Seite an derselben Stelle zeigen, diese ausblenden
func char_page(short: String) -> void:
	var from = char_shown()
	var to = dlg(short)
	if to == null or from == to:
		if to != null:
			_check_char_tabs(to, short)
		return
	if from != null:
		to.layout_pos = from.layout_pos
		aui.hide_dialog(from)
	aui.show_dialog(to)
	if from != null:
		to.position = from.position
	_check_char_tabs(to, short)
	hide_tooltip()
	refresh_character()

# Platz vorbereiten: Symbol, Anzahl, Sperre; Maus (Rechtsklick, Tooltip, Ziehen)
func _prep_slot(c: Control, kind: String, idx: int) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var icon = TextureRect.new()
	icon.name = "Symbol"
	icon.size = c.size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(icon)
	var count = Label.new()
	count.name = "Anzahl"
	count.size = c.size - Vector2(3, 1)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_constant_override("outline_size", 3)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(count)
	var lock = ColorRect.new()
	lock.name = "Sperre"
	lock.size = c.size
	lock.color = SLOT_LOCKED
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.visible = false
	c.add_child(lock)
	c.gui_input.connect(_on_slot_input.bind(kind, idx))
	c.mouse_entered.connect(_on_slot_hover.bind(kind, idx))
	c.mouse_exited.connect(hide_tooltip)
	c.set_drag_forwarding(_slot_drag.bind(kind, idx), _slot_can_drop.bind(kind, idx), _slot_drop.bind(kind, idx))

func _slot_control(kind: String, idx: int) -> Control:
	var d = dlg(INVENTORY) if kind == "bag" else (char_shown() if char_shown() != null else dlg(CHARACTER))
	return d.item(("Item_%02d" if kind == "bag" else "Equip_%02d") % idx) if d != null else null

func _set_slot(c: Control, id: int, count: int, locked: bool) -> void:
	if c == null or c.get_node_or_null("Symbol") == null:
		return
	(c.get_node("Symbol") as TextureRect).texture = items.icon(id) if id != 0 and items != null else null
	(c.get_node("Anzahl") as Label).text = str(count) if count > 1 else ""
	c.get_node("Sperre").visible = locked
	c.set_meta("item", id)

# Inventar vom Server ({size, bag: [[Platz, ID, Anzahl]], equip: [[Platz, ID]]})
func set_inventory(state: Dictionary) -> void:
	var bag = {}
	for e in state.get("bag", []):
		bag[int(e[0])] = [int(e[1]), int(e[2])]
	var equip = {}
	for e in state.get("equip", []):
		equip[int(e[0])] = int(e[1])
	inventory = {"size": int(state.get("size", 24)), "bag": bag, "equip": equip}
	refresh_inventory()
	refresh_lvup()
	refresh_character()

func bag_items() -> Array:
	var out = []
	var keys = inventory["bag"].keys()
	keys.sort()
	for pos in keys:
		out.append([pos, inventory["bag"][pos][0], inventory["bag"][pos][1]])
	return out

func refresh_inventory() -> void:
	var d = dlg(INVENTORY)
	if d == null:
		return
	for i in BAG_SLOTS:
		var e = inventory["bag"].get(i, [0, 0])
		_set_slot(d.item("Item_%02d" % i), e[0], e[1], i >= inventory["size"])
	d.set_text("Txt_BagNum", "%d/%d" % [inventory["bag"].size(), inventory["size"]])
	for row in [["Txt_Money%d", "money"], ["Txt_BindMoney%d", "bind_money"]]: # Gold- und Seelenmünzen (Z4)
		var m = int(stats.get(row[1], 0))
		d.set_text(row[0] % 3, str(m % 100))
		d.set_text(row[0] % 2, str((m / 100) % 100))
		d.set_text(row[0] % 1, str((m / 10000) % 100))
		d.set_text(row[0] % 0, str(m / 1000000))

func refresh_character() -> void:
	var races: Array = texts()["races"]
	var female = int(me.get("gender", 0)) == 1
	var a: Dictionary = stats.get("attr", {})
	for short in [CHARACTER, CHARACTER_DETAIL]:
		var d = dlg(short)
		if d == null:
			continue
		for i in EQUIP_SLOTS:
			var c = d.item("Equip_%02d" % i)
			if c != null and c.has_node("Symbol"):
				_set_slot(c, int(inventory["equip"].get(i, 0)), 1, false)
		d.show_item("Img_Male", not female)
		d.show_item("Img_Female", female)
		d.set_text("Txt_Name", str(me.get("name", stats.get("name", ""))))
		d.set_text("Txt_Race", races[clampi(int(me.get("race", 1)), 0, races.size() - 1)])
		d.set_text("Txt_Prof1", texts()["prof_level"] % [class_name_of(int(stats.get("class", me.get("class", 0)))), int(stats.get("level", 1))])
		d.set_frame("Img_Prof", int(stats.get("class", 1)) - 1)
	var d = dlg(CHARACTER)
	if d != null:
		d.set_text("Txt_Hp", "%d/%d" % [int(stats.get("hp", 0)), int(stats.get("max_hp", 0))])
		d.set_text("Txt_Mp", "%d/%d" % [int(stats.get("mp", 0)), int(stats.get("max_mp", 0))])
		var dmg: Array = a.get("dmg", [0, 0])
		d.set_text("Txt_Damage", "%d-%d" % [int(dmg[0]), int(dmg[1])])
		d.set_text("Txt_Defense", str(int(a.get("def", 0))))
		d.set_text("Txt_Definition", str(int(a.get("hit", 0))))
		d.set_text("Txt_Evade", str(int(a.get("eva", 0))))
		d.set_text("Txt_Block", "0")
		d.set_text("Txt_BlockDef", "0")
		d.set_text("Txt_Critical", "%.1f%%" % float(a.get("crit", 0.0)))
		d.set_text("Txt_CriticalDamage", "%d%%" % int(a.get("crit_dmg", 0)))
		d.set_text("Txt_DesCritical", "%.1f%%" % float(a.get("anti_crit", 0.0)))
		d.set_text("Txt_DesCriticalDamage", "%.1f%%" % float(a.get("anti_crit_dmg", 0.0)))
	var dd = dlg(CHARACTER_DETAIL)
	if dd != null:
		var mas: Array = a.get("mas", [])
		var res: Array = a.get("res", [])
		for i in 8:
			dd.set_text("Txt_Mas%02d" % i, str(int(mas[i])) if i < mas.size() else "0")
			var r = int(res[i]) if i < res.size() else 0
			dd.set_text("Txt_Res%02d" % i, str(r))
			dd.set_color("Txt_Res%02d" % i, RES_RED if r < 0 else Color.WHITE) # self_modulate: weiß = Farbe des XML

func _on_slot_input(event: InputEvent, kind: String, idx: int) -> void:
	var mb = event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if destroy_mode:
		if mb.button_index == MOUSE_BUTTON_LEFT and kind == "bag" and inventory["bag"].has(idx):
			set_destroy_mode(false)
			ask_destroy(idx)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			set_destroy_mode(false)
		return
	if mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if kind == "bag" and inventory["bag"].has(idx):
		use_requested.emit(idx)
	elif kind == "equip" and inventory["equip"].has(idx):
		unequip_requested.emit(idx, -1)
	hide_tooltip()

func _slot_drag(_at: Vector2, kind: String, idx: int):
	var id = int(inventory["bag"].get(idx, [0, 0])[0]) if kind == "bag" else int(inventory["equip"].get(idx, 0))
	if id == 0:
		return null
	var pv = TextureRect.new()
	pv.texture = items.icon(id) if items != null else null
	pv.size = Vector2(36, 36)
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.stretch_mode = TextureRect.STRETCH_SCALE
	pv.modulate.a = 0.8
	var c = _slot_control(kind, idx)
	if c != null:
		c.set_drag_preview(pv)
	hide_tooltip()
	_drag_item = idx if kind == "bag" else -1
	return {"kind": kind, "idx": idx, "id": id}

func _slot_can_drop(_at: Vector2, data, kind: String, idx: int) -> bool:
	if not data is Dictionary or not data.has("kind"):
		return false
	if kind == "bag":
		return idx < inventory["size"] and not (data["kind"] == "bag" and data["idx"] == idx)
	return data["kind"] == "bag" and items != null and items.info(int(data["id"]))["equip"] \
		and (int(items.info(int(data["id"])).get("mask", 0)) & (1 << idx)) != 0

func _slot_drop(_at: Vector2, data, kind: String, idx: int) -> void:
	if kind == "bag":
		if data["kind"] == "bag":
			move_item_requested.emit(int(data["idx"]), idx)
		else:
			unequip_requested.emit(int(data["idx"]), idx)
	else:
		equip_requested.emit(int(data["idx"]))

# ====================================================
# FERTIGKEITEN (K: Win_Skill mit Reitern und der Liste Sub_Skill, Win_BaseSkill Grundlagen, Talentbaum der Klasse,
# Win_Talent00 Hinweis; Win_NewSKill; Schnellleisten Win_QuickBar0 / 1)
# ====================================================
func _setup_skills() -> void:
	var d = dlg(SKILLS)
	if d != null:
		while d.item("Skill_%d" % (_view_slots + 1)) != null:
			_view_slots += 1
		for i in _view_slots:
			var btn = d.item("Btn_%d" % (i + 1))
			if btn != null:
				btn.mouse_entered.connect(_on_learn_hover.bind(i))
				btn.mouse_exited.connect(hide_tooltip)
			for k in ["Name_%d", "Lv_%d", "Txt_%d", "Back_%d"]:
				var l = d.item(k % (i + 1))
				if l != null:
					l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var nm = d.item("Name_%d" % (i + 1)) as Label
			if nm != null: # lange Namen enden mit "…" vor der nächsten Spalte (eine Zeile)
				nm.autowrap_mode = TextServer.AUTOWRAP_OFF
				nm.clip_text = true
				nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				nm.size.x = 96
	for kind in ["skill", "new", "bar0", "bar1"]:
		for i in {"skill": _view_slots, "new": NEW_SLOTS}.get(kind, BAR_SLOTS):
			_prep_skill(skill_control(kind, i), kind, i)
	for short in [SKILLS, BASE_SKILLS]:
		_setup_tabs(dlg(short))
	_setup_basic()
	var h = dlg(TALENT_HINT)
	if h != null:
		_talent_hint_text = h.get_text("Lab_Explain")

func _prep_skill(c: Control, kind: String, idx: int) -> void:
	if c == null:
		return
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var icon = TextureRect.new()
	icon.name = "Symbol"
	icon.size = c.size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(icon)
	c.mouse_entered.connect(_on_skill_hover.bind(kind, idx))
	c.mouse_exited.connect(hide_tooltip)
	c.set_drag_forwarding(_skill_drag.bind(kind, idx), _skill_can_drop.bind(kind, idx), _skill_drop.bind(kind, idx))
	if kind != "new":
		var cool = CoolOverlay.new()
		cool.name = "Cool"
		cool.hud = self
		cool.size = c.size
		c.add_child(cool)
	if kind.begins_with("bar"):
		c.gui_input.connect(_on_skill_input.bind(kind, idx))

# Platz-Control wie in den Dialogen: Skill_1.. (K, Liste Win_Skill_View), Img_Skill1..16 (neu), Leiste 0 Sc_00..09,
# Leiste 1 Sc_10..19
func skill_control(kind: String, idx: int) -> Control:
	if kind == "skill":
		return dlg(SKILLS).item("Skill_%d" % (idx + 1)) if dlg(SKILLS) != null else null
	if kind == "new":
		return dlg(NEW_SKILLS).item("Img_Skill%d" % (idx + 1)) if dlg(NEW_SKILLS) != null else null
	var bar = int(kind.substr(3))
	var d = dlg(BAR_DIALOGS[bar])
	return d.item("Sc_%02d" % (bar * BAR_SLOTS + idx)) if d != null else null

# Bekannte Fertigkeiten (nach ID)
func skill_list() -> Array:
	var ids = skill_state["skills"].keys()
	ids.sort()
	return ids

# Fertigkeit an einem Platz, 0 = leer
func skill_at(kind: String, idx: int) -> int:
	match kind:
		"skill":
			return int(_view_ids[idx]) if idx < _view_ids.size() else 0
		"new":
			var i = _new_page * NEW_SLOTS + idx
			return skill_state["new"][i] if i < skill_state["new"].size() else 0
	return int(skill_state["shortcuts"].get(Vector2i(int(kind.substr(3)), idx), 0))

# Zustand vom Server (world_ready skills: {skills: [[ID, Stufe]], new: [IDs], shortcuts: [[Leiste, Platz, ID]],
# switched, catalog})
func set_skills(state: Dictionary) -> void:
	var known = {}
	for e in state.get("skills", []):
		known[int(e[0])] = int(e[1])
	var sc = {}
	for e in state.get("shortcuts", []):
		sc[Vector2i(int(e[0]), int(e[1]))] = int(e[2])
	skill_state = {"skills": known, "new": state.get("new", []).map(func(x): return int(x)), "shortcuts": sc}
	switched = {}
	for x in state.get("switched", []):
		switched[int(x)] = true
	if state.has("catalog"):
		set_catalog(state["catalog"])
	if state.has("race"):
		race_list = []
		race_info = {}
		for e in state["race"]:
			race_list.append(int(e[0]))
			race_info[int(e[0])] = {"type": int(e[1]), "use": int(e[2])}
	refresh_skills()
	refresh_bars()
	refresh_new_skills()

# Klassen-Fertigkeiten der Figur (catalog [[ID, nächste Stufe, benötigte Stufe, Kosten, max_learn, type, use, ab Stufe]])
func set_catalog(list: Array) -> void:
	catalog = {}
	for e in list:
		if e is Array and e.size() >= 8:
			catalog[int(e[0])] = {"next": int(e[1]), "req": int(e[2]), "cost": int(e[3]), "max": int(e[4]),
				"type": int(e[5]), "use": int(e[6]), "first": int(e[7])}
	refresh_skills()

func add_skill(id: int, level: int, is_new: bool) -> void:
	skill_state["skills"][id] = level
	if is_new and not id in skill_state["new"]:
		skill_state["new"].append(id)
	refresh_skills()
	refresh_bars()
	refresh_new_skills()

# Vergessen (Quest-Belohnung del_skill): weg aus Fenster, Leisten und "Neue Fertigkeiten"
func remove_skill(id: int) -> void:
	skill_state["skills"].erase(id)
	skill_state["new"].erase(id)
	for k in skill_state["shortcuts"].keys():
		if int(skill_state["shortcuts"][k]) == id:
			skill_state["shortcuts"].erase(k)
	refresh_skills()
	refresh_bars()
	refresh_new_skills()

func set_shortcut(bar: int, slot: int, id: int) -> void:
	if id == 0:
		skill_state["shortcuts"].erase(Vector2i(bar, slot))
	else:
		skill_state["shortcuts"][Vector2i(bar, slot)] = id
	refresh_bars()

func skills_seen(ids: Array) -> void:
	for id in ids:
		skill_state["new"].erase(int(id))
	refresh_new_skills()

# Fertigkeiten eines Reiters: [aktive, passive] (Klasse: alle Klassen-Fertigkeiten, auch noch nicht gelernte, nach der
# Stufe der ersten Lernstufe; Rasse: die übrigen gelernten - Rassen-Segen, Stadtportal ...; Beruf: noch keine)
func tab_skills(tab: String) -> Array:
	var active = []
	var passive = []
	match tab:
		"class":
			var ids = catalog.keys()
			ids.sort_custom(func(a, b): return [int(catalog[a]["first"]), a] < [int(catalog[b]["first"]), b])
			for id in ids:
				(passive if int(catalog[id]["use"]) == 6 else active).append(id)
		"race": # Rassen-Fertigkeiten (auch noch nicht erhaltene, grau), dann die übrigen bekannten außerhalb der Klasse
			var ids = race_list.duplicate()
			for id in skill_list():
				if not catalog.has(id) and not id in ids:
					ids.append(id)
			for id in ids:
				var pas = skill_info.get(str(id), {}).get("passive", false) or int(race_info.get(id, {}).get("use", 0)) == 6
				(passive if pas else active).append(id)
	return [active, passive]

func refresh_skills() -> void:
	var d = dlg(SKILLS)
	if d == null:
		return
	_view_ids = []
	for part in tab_skills(skill_tab):
		if part.is_empty():
			continue
		while _view_ids.size() % 3 != 0:
			_view_ids.append(0) # neuer Abschnitt (passive) in einer neuen Reihe
		_view_ids.append_array(part)
	var level = int(stats.get("level", 1))
	var money = int(stats.get("money", 0)) + int(stats.get("bind_money", 0)) # Gold deckt fehlende Seelenmünzen (nach Rückfrage)
	for i in _view_slots:
		var n = i + 1
		var id = int(_view_ids[i]) if i < _view_ids.size() else 0
		var known = skill_state["skills"].has(id)
		var c: Dictionary = catalog.get(id, {})
		for k in ["Back_%d", "Skill_%d", "Name_%d", "Lv_%d", "Txt_%d"]:
			d.show_item(k % n, id != 0)
		var slot = skill_control("skill", i)
		_set_skill_icon(slot, id)
		if slot != null and slot.get_node_or_null("Symbol") != null:
			slot.get_node("Symbol").modulate = Color.WHITE if known or id == 0 else Color(0.4, 0.4, 0.45)
		if id != 0 and skills != null:
			var nm = d.item("Name_%d" % n) as Label
			if nm != null: # direkt: set_text gäbe der gekürzten Beschriftung ihre Mindestbreite (0)
				nm.text = _plain(skills.skill_name(id))
				nm.size.x = 96
			var lv = d.item("Lv_%d" % n)
			if known:
				d.set_text("Lv_%d" % n, texts()["skill_lv"] % int(skill_state["skills"][id]))
			elif c.is_empty(): # Rassen-Fertigkeit, kommt aus einer Quest
				d.set_text("Lv_%d" % n, texts()["skill_quest"])
			else: # benötigte Stufe, rot
				d.set_text("Lv_%d" % n, texts()["skill_from"] % int(c.get("first", 1)))
			if lv != null:
				lv.add_theme_color_override("font_color", SKILL_LV_COLOR if known else SKILL_NEED_COLOR)
			d.set_text("Txt_%d" % n, kind_text(id))
		var learnable = id != 0 and not c.is_empty() and int(c["next"]) > 0 and known
		d.show_item("Btn_%d" % n, learnable)
		if learnable:
			d.enable_item("Btn_%d" % n, level >= int(c["req"]) and money >= int(c["cost"]))
	var sub = d.item("Sub_Skill")
	if sub != null and sub.get_child_count() > 0:
		var rows = ceili(_view_ids.size() / 3.0)
		_view_max = maxf(0.0, rows * VIEW_ROW + 30.0 - sub.size.y)
		_scroll_view(0.0)

# Art einer Fertigkeit für die Liste (Angriff, Stärkung, Fluch, Passiv, Schalter)
func kind_text(id: int) -> String:
	var c: Dictionary = catalog.get(id, race_info.get(id, {}))
	var i: Dictionary = skill_info.get(str(id), {})
	var use = int(c.get("use", 7 if i.get("switch", false) else (6 if i.get("passive", false) else 2)))
	var type = int(c.get("type", i.get("type", 1)))
	if use == 6:
		return texts()["kind_passive"]
	if use == 7:
		return texts()["kind_switch"]
	return texts()["kind_%d" % type] if texts().has("kind_%d" % type) else ""

func _scroll_view(delta: float) -> void:
	var d = dlg(SKILLS)
	var sub = d.item("Sub_Skill") if d != null else null
	if sub == null or sub.get_child_count() == 0:
		return
	_view_scroll = clampf(_view_scroll + delta, 0.0, _view_max)
	(sub.get_child(0) as Control).position.y = -_view_scroll

# Plus-Knopf eines Platzes: nächste Stufe lernen (über Stufe 20; bis dahin lernt die Figur von selbst)
func _learn_slot(idx: int) -> void:
	var id = skill_at("skill", idx)
	if id != 0:
		hide_tooltip()
		skill_learn_requested.emit(id)

func _on_learn_hover(idx: int) -> void:
	var id = skill_at("skill", idx)
	var c: Dictionary = catalog.get(id, {})
	if c.is_empty() or int(c["next"]) == 0:
		return
	var t = texts()
	var cost = int(c["cost"])
	var bind = int(stats.get("bind_money", 0))
	var lines = [t["learn_next"] % int(c["next"]), t["learn_need"] % int(c["req"]), t["learn_cost"] % money_text(cost)]
	if int(stats.get("level", 1)) < int(c["req"]):
		lines[1] = "^ff6a6a" + lines[1]
	if bind < cost:
		lines.append(t["learn_gold"] if bind + int(stats.get("money", 0)) >= cost else t["learn_poor"])
	show_tooltip(Hud_bbcode("\r".join(lines)))

# Kupfer als Gold / Silber / Kupfer
func money_text(copper: int) -> String:
	var g = copper / 10000
	var sv = (copper / 100) % 100
	var c = copper % 100
	var t = texts()
	if g > 0:
		return t["money_gsc"] % [g, sv, c]
	if sv > 0:
		return t["money_sc"] % [sv, c]
	return t["money_c"] % c

static func Hud_bbcode(s: String) -> String:
	var out = s.replace("[", "[lb]").replace("\r", "\n")
	var re = RegEx.create_from_string("\\^([0-9a-fA-F]{6})")
	return re.sub(out, "[color=#$1]", true)


# ====================================================
# REITER DES K-FENSTERS
# ====================================================
# Reiterleiste eines K-Fensters (Win_Skill, Win_BaseSkill, Talentbaum): deutsche Beschriftung, ein Reiter "Rasse" als
# Kopie des Klassen-Reiters, Reihenfolge TAB_ORDER; Erwachen (Rdo_Transfer) kommt später
func _setup_tabs(d) -> void:
	if d == null or d.item("Rdo_Race") != null:
		return
	var cls = d.item("Rdo_MainInitiative") if d.item("Rdo_MainInitiative") != null else d.item("Rdo_Initiative")
	if cls == null:
		return
	var race: BaseButton = cls.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	race.name = "Rdo_Race"
	race.set_meta("command", "Rdo_Race")
	race.button_pressed = false
	cls.get_parent().add_child(race)
	d._items["Rdo_Race"] = race
	race.toggled.connect(d._on_radio.bind("Rdo_Race"))
	race.focus_mode = Control.FOCUS_NONE
	for i in TAB_ORDER.size():
		var name = _tab_radio(d, TAB_ORDER[i])
		var r = d.item(name)
		if r != null:
			r.position.x = TAB_X[i]
			r.size.x = TAB_W
			d.set_text(name, texts()["tab_" + TAB_ORDER[i]])
	for n in ["Rdo_Transfer", "Rdo_SkillEdit"]:
		d.show_item(n, false)
	d.set_text("Title", texts()["skills_title"])

func _tab_radio(d, tab: String) -> String:
	if tab == "class":
		return "Rdo_MainInitiative" if d.item("Rdo_MainInitiative") != null else "Rdo_Initiative"
	return TAB_RADIOS[tab]

func _tab_of(cmd: String) -> String:
	if cmd in ["Rdo_MainInitiative", "Rdo_Initiative"]:
		return "class"
	for t in TAB_RADIOS:
		if TAB_RADIOS[t] == cmd:
			return t
	return ""

# Das sichtbare K-Fenster (Win_Skill, Win_BaseSkill oder der Talentbaum), sonst null
func skill_page():
	for d in [dlg(SKILLS), dlg(BASE_SKILLS), _talent_dlg]:
		if d != null and d.visible:
			return d
	return null

func _page_for(tab: String):
	if tab == "basic":
		return dlg(BASE_SKILLS)
	if tab == "talent":
		return _talent_dlg
	return dlg(SKILLS)

# Reiter wählen: Grundlagen / Talentbaum sind eigene Fenster an derselben Stelle; Talent unter Stufe 20 und Seele
# unter Stufe 60 zeigen nur den Hinweis (Win_Talent00), der Reiter bleibt
func select_tab(tab: String) -> void:
	var level = int(stats.get("level", 1))
	if tab == "talent" and (level < TALENT_LEVEL or _talent_dialog() == null):
		_level_hint(_talent_hint_text if _talent_hint_text != "" else texts()["talent_hint"] % TALENT_LEVEL)
		_check_tab(skill_tab)
		return
	if tab == "soul":
		_level_hint(texts()["soul_hint"] % SOUL_LEVEL)
		_check_tab(skill_tab)
		return
	var from = skill_page()
	var page = _page_for(tab)
	if page == null:
		return
	skill_tab = tab
	if from != null and from != page:
		page.position = from.position
		aui.hide_dialog(from)
	if not page.visible:
		aui.show_dialog(page)
	_check_tab(tab)
	hide_tooltip()
	refresh_skills()

func _check_tab(tab: String) -> void:
	for d in [dlg(SKILLS), dlg(BASE_SKILLS), _talent_dlg]:
		if d == null:
			continue
		var r = d.item(_tab_radio(d, tab))
		if r is BaseButton:
			(r as BaseButton).set_pressed_no_signal(true)
			for other in TAB_ORDER:
				var o = d.item(_tab_radio(d, other))
				if other != tab and o is BaseButton:
					(o as BaseButton).set_pressed_no_signal(false)

func _level_hint(text: String) -> void:
	var h = dlg(TALENT_HINT)
	if h == null:
		add_system(text)
		return
	h.set_text("Lab_Explain", text)
	var lab = h.item("Lab_Explain")
	if lab != null:
		lab.move_to_front() # in der Datei steht der Rahmen (Img_Back) danach und läge sonst darüber
	aui.show_dialog(h)

# Talentbaum der Rasse / Klasse (Win_TalentNN_New, ab Stufe 20; noch ohne Funktion)
func _talent_dialog():
	if _talent_dlg != null:
		return _talent_dlg
	var n = int(TALENT_TREES.get("%d_%d" % [int(me.get("race", 0)), int(stats.get("class", 0))], 0))
	if n == 0:
		return null
	_talent_dlg = aui.dialog("%dTalent%02d_New.xml" % [skin, n])
	if _talent_dlg != null:
		_setup_tabs(_talent_dlg)
		_talent_dlg.command.connect(_on_talent_command)
	return _talent_dlg

func _on_talent_command(cmd: String) -> void:
	_on_command(cmd, "Talent")

# Grundlagen (Win_BaseSkill): Grundaktionen mit Symbol (iconlist_action) und Namen; Normalangriff und Zaubern
# abbrechen gehen, die übrigen kommen mit Gruppe / Handel
func _setup_basic() -> void:
	var d = dlg(BASE_SKILLS)
	if d == null:
		return
	for i in range(1, 16):
		var on = i <= BASIC_ACTIONS.size()
		for k in ["Back_%02d", "Cmd_%02d", "Txt_%02d", "Gfx_New_%02d", "Gfx_Cold_%02d"]:
			d.show_item(k % i, on and not k.begins_with("Gfx"))
		if not on:
			continue
		var a: Array = BASIC_ACTIONS[i - 1]
		d.set_text("Txt_%02d" % i, texts()["basic_" + a[0]])
		var c = d.item("Cmd_%02d" % i)
		if c == null:
			continue
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		var icon = TextureRect.new()
		icon.name = "Symbol"
		icon.size = c.size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(icon)
		c.set_meta("action", a[0])
		c.mouse_entered.connect(_on_basic_hover.bind(i - 1))
		c.mouse_exited.connect(hide_tooltip)
		c.gui_input.connect(_on_basic_input.bind(i - 1))
	for n in ["Btn_Back", "Btn_Next", "Lab_Back", "Lab_Next", "Txt_Page", "Img_Help_1", "Img_Help_2", "Txt_Help",
			"Image_Buttoncompart", "Txt_09"]:
		d.show_item(n, false)
	_refresh_basic_icons()

func _refresh_basic_icons() -> void:
	var d = dlg(BASE_SKILLS)
	if d == null:
		return
	for i in BASIC_ACTIONS.size():
		var c = d.item("Cmd_%02d" % (i + 1))
		if c != null and c.get_node_or_null("Symbol") != null:
			var names: Array = BASIC_ACTIONS[i][1]
			var tex = null
			for nm in names:
				tex = action_icon(nm % clampi(int(stats.get("class", 1)), 1, 10) if nm.contains("%d") else nm)
				if tex != null:
					break
			c.get_node("Symbol").texture = tex

func _on_basic_hover(i: int) -> void:
	show_tooltip(Hud_bbcode(texts()["basic_" + BASIC_ACTIONS[i][0]]))

func _on_basic_input(event: InputEvent, i: int) -> void:
	var mb = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		basic_action_requested.emit(str(BASIC_ACTIONS[i][0]))

# Symbol einer Grundaktion aus surfaces/iconset/iconlist_action (Dateiname ohne Endung)
func action_icon(name: String) -> Texture2D:
	if _action_atlas.is_empty() and skills != null and skills.files != null:
		_action_atlas["loaded"] = true
		var files = skills.files
		var txt = ""
		for base in [language + "/surfaces/iconset", "resources/" + language + "/surfaces/iconset", "resources/surfaces/iconset"]:
			txt = files.resolve("%s/iconlist_action.txt" % base)
			if txt != "":
				break
		if txt != "":
			var lines: PackedStringArray = files.read_lines(txt)
			var img = files.load_image(txt.get_basename() + ".dds") if lines.size() > 4 else null
			if img != null:
				_action_atlas["tex"] = ImageTexture.create_from_image(img)
				_action_atlas["w"] = lines[0].to_int()
				_action_atlas["h"] = lines[1].to_int()
				_action_atlas["cols"] = maxi(1, lines[3].to_int())
				var index = {}
				for i in range(4, lines.size()):
					var k = lines[i].strip_edges().get_basename().to_lower()
					if k != "" and not index.has(k):
						index[k] = i - 4
				_action_atlas["index"] = index
	if not _action_atlas.has("index"):
		return null
	var key = name.to_lower()
	if _action_icons.has(key):
		return _action_icons[key]
	var tex: AtlasTexture = null
	var at = _action_atlas["index"].get(key, -1)
	if at >= 0:
		tex = AtlasTexture.new()
		tex.atlas = _action_atlas["tex"]
		var w = int(_action_atlas["w"])
		var h = int(_action_atlas["h"])
		tex.region = Rect2((at % int(_action_atlas["cols"])) * w, (at / int(_action_atlas["cols"])) * h, w, h)
	_action_icons[key] = tex
	return tex

func refresh_bars() -> void:
	for b in BAR_DIALOGS.size():
		for i in BAR_SLOTS:
			_set_skill_icon(skill_control("bar%d" % b, i), skill_at("bar%d" % b, i))

func refresh_new_skills() -> void:
	var d = dlg(NEW_SKILLS)
	if d == null:
		return
	var n = skill_state["new"].size()
	if n == 0:
		if d.visible:
			aui.hide_dialog(d)
			hide_tooltip()
		return
	_new_page = clampi(_new_page, 0, (n - 1) / NEW_SLOTS)
	for i in NEW_SLOTS:
		var id = skill_at("new", i)
		_set_skill_icon(skill_control("new", i), id)
		d.show_item("Img_Skill%d" % (i + 1), id != 0)
		d.show_item("Img_IconBack%d" % (i + 1), id != 0)
	d.show_item("Btn_PageDown", n > (_new_page + 1) * NEW_SLOTS)
	d.show_item("Btn_PageUp", _new_page > 0)
	if not d.visible:
		aui.show_dialog(d)

func new_skills_shown() -> bool:
	return window_open(NEW_SKILLS)

func _set_skill_icon(c: Control, id: int) -> void:
	if c == null or c.get_node_or_null("Symbol") == null:
		return
	(c.get_node("Symbol") as TextureRect).texture = skills.icon(id) if id != 0 and skills != null else null
	c.set_meta("skill", id)

# Linksklick (ohne Ziehen) auf einen Platz einer Schnellleiste: einsetzen
func _on_skill_input(event: InputEvent, kind: String, idx: int) -> void:
	var mb = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not get_viewport().gui_is_dragging():
		var id = skill_at(kind, idx)
		if id != 0:
			skill_use_requested.emit(id)

# Abklingzeit beginnt (Meldung cooldown)
func set_cooldown(id: int, ms: int) -> void:
	if ms > 0:
		cooldowns[id] = [Time.get_ticks_msec() + ms, ms]
	else:
		cooldowns.erase(id)

# Restliche Abklingzeit 0 - 1
func cool_fraction(id: int) -> float:
	var c = cooldowns.get(id)
	if c == null:
		return 0.0
	var left = int(c[0]) - Time.get_ticks_msec()
	if left <= 0:
		cooldowns.erase(id)
		return 0.0
	return clampf(float(left) / maxf(1.0, float(c[1])), 0.0, 1.0)

# Gesperrt durch ein Siegel (CECHostPlayer::IsSkillDisabled): schweigend / betäubt außer dizzy-fähigen,
# entwaffnet außer handfree-fähigen Fertigkeiten
func skill_sealed(id: int) -> bool:
	var i: Dictionary = skill_info.get(str(id), {})
	return (seals.get("silent", false) and not i.get("dizzy", false)) or (seals.get("disarm", false) and not i.get("handfree", true))

# Schalter an / aus (Meldung skill_switch, world_ready skills.switched)
func set_switched(id: int, on: bool) -> void:
	if on:
		switched[id] = true
	else:
		switched.erase(id)

func mana_ok(id: int) -> bool:
	return int(stats.get("mp", 0)) >= int(skill_info.get(str(id), {}).get("mp", 0))

func _on_skill_hover(kind: String, idx: int) -> void:
	var id = skill_at(kind, idx)
	if id == 0 or skills == null:
		hide_tooltip()
		return
	var context = 1 if kind.begins_with("bar") else 0 # SkillDesc.CONTEXT: QUICK_BAR / SKILL_INTERFACE
	var c: Dictionary = catalog.get(id, {})
	var next_req = int(c["req"]) if not c.is_empty() and int(c["next"]) > 0 else 9999
	show_tooltip(skills.bbcode(skills.desc(id, int(skill_state["skills"].get(id, 1)), context, next_req)))

func _skill_drag(_at: Vector2, kind: String, idx: int):
	var id = skill_at(kind, idx)
	if id == 0:
		return null
	var pv = TextureRect.new()
	pv.texture = skills.icon(id) if skills != null else null
	pv.size = Vector2(36, 36)
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.stretch_mode = TextureRect.STRETCH_SCALE
	pv.modulate.a = 0.8
	var c = skill_control(kind, idx)
	if c != null:
		c.set_drag_preview(pv)
	hide_tooltip()
	_drag_shortcut = Vector2i(int(kind.substr(3)), idx) if kind.begins_with("bar") else Vector2i(-1, -1)
	return {"skill": id, "from": kind, "idx": idx}

# Passive Fertigkeiten wirken von selbst und kommen auf keine Leiste
func _skill_can_drop(_at: Vector2, data, kind: String, _idx: int) -> bool:
	return kind.begins_with("bar") and data is Dictionary and data.has("skill") \
		and skill_state["skills"].has(int(data["skill"])) \
		and not skill_info.get(str(int(data["skill"])), {}).get("passive", false)

func _skill_drop(_at: Vector2, data, kind: String, idx: int) -> void:
	var bar = int(kind.substr(3))
	var id = int(data["skill"])
	var from = str(data["from"])
	_drag_shortcut = Vector2i(-1, -1)
	if from.begins_with("bar"):
		var src = Vector2i(int(from.substr(3)), int(data["idx"]))
		if src == Vector2i(bar, idx):
			return
		var other = int(skill_state["shortcuts"].get(Vector2i(bar, idx), 0))
		shortcut_requested.emit(bar, idx, id)
		shortcut_requested.emit(src.x, src.y, other) # tauschen bzw. leeren
		return
	shortcut_requested.emit(bar, idx, id)
	if from == "new":
		skills_seen([id])
		skills_seen_requested.emit([id])

# Aus einer Schnellleiste gezogen und nirgends abgelegt: Platz leeren
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_shortcut.x >= 0:
		var src = _drag_shortcut
		_drag_shortcut = Vector2i(-1, -1)
		if is_inside_tree() and not get_viewport().gui_is_drag_successful():
			shortcut_requested.emit(src.x, src.y, 0)
	if what == NOTIFICATION_DRAG_END and _drag_item >= 0:
		var from = _drag_item
		_drag_item = -1
		# in die Welt fallen gelassen (über keinem Fenster, wie CDlgDragDrop ohne pDlgOver): zerstören
		if is_inside_tree() and not get_viewport().gui_is_drag_successful() and not over_window(get_viewport().get_mouse_position()):
			ask_destroy(from)

# Liegt der Punkt (Bildschirm) über einem offenen Fenster der Oberfläche?
func over_window(at: Vector2) -> bool:
	for d in dialogs.values():
		if d.visible and d.get_global_rect().has_point(at):
			return true
	return _talent_dlg != null and _talent_dlg.visible and _talent_dlg.get_global_rect().has_point(at)


# ====================================================
# ZERSTÖREN (Btn_Destroy, Win_Destroy, CDlgDestroyItemConfirm)
# ====================================================
func set_destroy_mode(on: bool) -> void:
	destroy_mode = on
	Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN if on else Input.CURSOR_ARROW)

func destroy_open() -> bool:
	return dialogs.has(DESTROY) and dialogs[DESTROY].visible

# Text aus STRING_TABLE der Spieldaten (item_data.gd desc), "" ohne
func game_text(key: String) -> String:
	return str(items.desc.text(key)) if items != null and items.desc != null else ""

static func _has_cjk(s: String) -> bool:
	for c in s:
		if c.unicode_at(0) >= 0x3000:
			return true
	return false

func ask_destroy(pos: int) -> void:
	var e = inventory["bag"].get(pos)
	if e == null or items == null or destroy_open() or aui.has_message_box():
		return
	var id = int(e[0])
	if not items.destroyable(id):
		var no = aui.text(STF_CANT_DESTROY)
		add_system((no if no != "" and not _has_cjk(no) else texts()["cant_destroy"]).trim_prefix("#C"))
		return
	var i: Dictionary = items.info(id)
	var color = game_text("ITEMQUALITY_COL_%d" % int(i["quality"]))
	var shown = color + str(i["name"]) + ("^ffffff" if color != "" else "")
	var confirm = game_text("DESTORY_ITEM_CONFIRM")
	if int(i["quality"]) in DESTROY_ASK_QUALITY and confirm != "" and dialogs.has(DESTROY):
		var key = game_text("DESTORY_ITEM_KEY")
		_destroy_pending = {"pos": pos, "id": id, "key": key}
		var d = dialogs[DESTROY]
		d.set_text("Txt_Warning", confirm % [shown, key] if confirm.count("%s") >= 2 else confirm)
		var edit = d.item("Edt_Input")
		if edit is LineEdit:
			edit.text = ""
		aui.show_dialog(d)
		if edit is LineEdit:
			edit.grab_focus.call_deferred()
		return
	var ask = aui.text(STF_DESTROY_ASK)
	if ask == "" or _has_cjk(ask) or not ask.contains("%s"):
		ask = confirm.split("\r")[0] if confirm.contains("%s") else "%s ?"
	if await aui.message_box(_plain(ask % shown), AuiManager.MB_OKCANCEL) == "IDOK":
		var now = inventory["bag"].get(pos)
		if now != null and int(now[0]) == id:
			destroy_requested.emit(pos, id)

func _confirm_destroy() -> void:
	if _destroy_pending.is_empty() or not destroy_open():
		return
	var d = dialogs[DESTROY]
	var edit = d.item("Edt_Input")
	var typed = str(edit.text).strip_edges() if edit is LineEdit else ""
	if typed != str(_destroy_pending["key"]):
		add_system(game_text("INPUT_CONFIRM_ERR").trim_prefix("#C"))
		if edit is LineEdit:
			edit.text = ""
			edit.grab_focus()
		return
	var p = _destroy_pending
	close_destroy()
	var now = inventory["bag"].get(int(p["pos"]))
	if now != null and int(now[0]) == int(p["id"]):
		destroy_requested.emit(int(p["pos"]), int(p["id"]))

func close_destroy() -> void:
	_destroy_pending = {}
	if destroy_open():
		var edit = dialogs[DESTROY].item("Edt_Input")
		if edit is Control:
			edit.release_focus()
		aui.hide_dialog(dialogs[DESTROY])

func _on_destroy_input(event: InputEvent) -> void:
	var k = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_destroy()

# Tooltip: Fenster am Mauszeiger mit der Beschreibung (item_data.gd tooltip)
func _setup_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.name = "Tooltip"
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.9)
	sb.border_color = Color(0.55, 0.47, 0.3)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(6)
	_tooltip.add_theme_stylebox_override("panel", sb)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_text = RichTextLabel.new()
	_tooltip_text.bbcode_enabled = true
	_tooltip_text.fit_content = true
	_tooltip_text.scroll_active = false
	_tooltip_text.custom_minimum_size = Vector2(230, 0)
	_tooltip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_text.add_theme_font_size_override("normal_font_size", 12)
	_tooltip.add_child(_tooltip_text)
	_tooltip.visible = false
	_tooltip.z_index = 100
	aui.add_child(_tooltip)

func _on_slot_hover(kind: String, idx: int) -> void:
	var id = int(inventory["bag"].get(idx, [0, 0])[0]) if kind == "bag" else int(inventory["equip"].get(idx, 0))
	if id == 0 or items == null:
		hide_tooltip()
		return
	var count = int(inventory["bag"].get(idx, [0, 1])[1]) if kind == "bag" else 1
	show_tooltip(items.tooltip(id, count, me, texts(), class_name_of))

func show_tooltip(bbcode: String) -> void:
	_tooltip_text.text = bbcode
	_tooltip.reset_size()
	var at = aui.get_local_mouse_position() + Vector2(16, 16)
	var limit = aui.size - _tooltip.size
	_tooltip.position = Vector2(minf(at.x, limit.x), minf(at.y, limit.y)).max(Vector2.ZERO)
	_tooltip.visible = true

func hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false

func tooltip_text() -> String:
	return _tooltip_text.get_parsed_text() if _tooltip != null and _tooltip.visible else ""

# Fortschritt beim Sammeln (Win_Prgs): text, Anteil 0 - 1; text "" schließt
func set_progress(text: String, f: float) -> void:
	var d = dlg(PROGRESS)
	if d == null:
		return
	if text == "":
		aui.hide_dialog(d)
		return
	d.set_progress("Prgs", 100.0 * clampf(f, 0.0, 1.0))
	d.set_text("Txt_info", "%s  %d%%" % [text, roundi(100.0 * clampf(f, 0.0, 1.0))])
	if not d.visible:
		aui.show_dialog(d)

func progress_shown() -> bool:
	return window_open(PROGRESS)


# ====================================================
# MINIMAP (Win_MiniMap)
# ====================================================
# Regel der Tab-Auswahl (SelectTargetRule.lua, Zone 0): R = höchstens so weit, bis r in jede Richtung,
# darüber nur innerhalb angle Grad um die Blickrichtung der Kamera (CECHostPlayer::CanSelectByTab)
var tab_rule = {"r": 5.0, "R": 20.0, "angle": 120.0}

# Kartenbild und Name aus den Lua-Skripten der Sprache (InstanceWorld.lua / InstanceStr.lua)
func _read_map_data(data_root: String, world_id: int) -> void:
	var files = load(FILES).new(data_root)
	var script_dir = ""
	for base in [language + "/script", "resources/" + language + "/script"]:
		var p = files.resolve(base)
		if p != "":
			script_dir = p
			break
	if script_dir == "":
		warnings.append("Lua-Skripte (%s/script) fehlen" % language)
		return
	var lua = load(LUA).new(files)
	var path = files.resolve("instanceworld.lua", script_dir)
	var err = lua.run_file(path) if path != "" else "InstanceWorld.lua fehlt"
	if err != "":
		warnings.append(err)
	var inst = lua.value("Instance")
	var w = inst.get(world_id) if inst is Dictionary else null
	if not w is Dictionary or str(w.get("path", "")).to_lower() != map_name.to_lower():
		# Welt-ID passt nicht: nach dem Map-Ordner suchen
		w = null
		if inst is Dictionary:
			for k in inst:
				if k is int and inst[k] is Dictionary and str(inst[k].get("path", "")).to_lower() == map_name.to_lower():
					w = inst[k]
					world_id = k
					break
	map_title = str(lua.value("Instance.Str.name_%d" % world_id)) if lua.value("Instance.Str.name_%d" % world_id) != null else map_name
	if w is Dictionary:
		var zone = w.get(0)
		if not zone is Dictionary:
			for k in w:
				if k is int and w[k] is Dictionary and w[k].has("MiniMap"):
					zone = w[k]
					break
		if zone is Dictionary:
			var r = zone.get("rectMap", {})
			if r is Dictionary and r.size() >= 4:
				_map_rect = Rect2(float(r[1]), float(r[2]), float(r[3]) - float(r[1]), float(r[4]) - float(r[2]))
			_mark_tex["map"] = aui.texture(str(zone.get("MiniMap", "")))
	lua.close()
	var rule_lua = load(LUA).new(files)
	var rule_path = files.resolve("selecttargetrule.lua", script_dir)
	if rule_path != "" and rule_lua.run_file(rule_path) == "":
		var rule = rule_lua.value("SelectTargetRule.0")
		if rule is Dictionary:
			for k in tab_rule:
				if rule.has(k):
					tab_rule[k] = float(rule[k])
	rule_lua.close()

func _setup_minimap() -> void:
	var d = dlg("MiniMap")
	if d == null:
		return
	d.set_text("Btn_Bar", map_title)
	var bar = d.item("Btn_Bar")
	if bar is Button:
		bar.clip_text = false
	var area = d.item("Hide_2")
	if area == null:
		return
	_radar = ColorRect.new()
	_radar.name = "Radar"
	_radar.size = area.size
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = RADAR_SHADER
	mat.shader = sh
	var map_tex = _mark_tex.get("map")
	mat.set_shader_parameter("map_tex", map_tex)
	mat.set_shader_parameter("has_map", map_tex != null and _map_rect.size.x != 0.0)
	mat.set_shader_parameter("mask_tex", aui.texture("InGame\\MiniMapMask.tga"))
	var half = RADAR_DIAMETER * MAP_ZOOM * 0.5
	if _map_rect.size.x != 0.0:
		mat.set_shader_parameter("half_size", Vector2(-half / absf(_map_rect.size.x), half / absf(_map_rect.size.y))) # gespiegelt
	_radar.material = mat
	area.add_child(_radar)
	_radar_marks = RadarMarks.new()
	_radar_marks.size = area.size
	_radar_marks.mouse_filter = Control.MOUSE_FILTER_STOP
	_radar_marks.gui_input.connect(_on_radar_input)
	area.add_child(_radar_marks)
	for k in MARKS:
		_mark_tex[k] = aui.texture(MARKS[k])
	_arrow = TextureRect.new()
	_arrow.texture = aui.texture("InGame\\MiniMapDir.tga")
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _arrow.texture != null:
		_arrow.size = _arrow.texture.get_size()
		_arrow.pivot_offset = _arrow.size / 2.0
		_arrow.position = (area.size - _arrow.size) / 2.0
	area.add_child(_arrow)

# Ziel der Autoroute (Vector3) oder null
func set_route_target(pos) -> void:
	route_target = pos

# Linksklick auf die Minimap -> Weltpunkt (gespiegelt wie die Anzeige)
func _on_radar_input(event: InputEvent) -> void:
	var mb = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var off = mb.position - _radar_marks.size / 2.0
	if off.length() <= _radar_marks.size.x / 2.0:
		map_route_requested.emit(radar_to_world(off))

# Abstand zur Mitte der Minimap (Pixel) -> Weltpunkt (x, z)
func radar_to_world(off: Vector2) -> Vector2:
	return Vector2(_radar_pos.x - off.x / _radar_scale, _radar_pos.z - off.y / _radar_scale)

# Jedes Bild: eigene Position / Richtung und die Figuren in der Nähe ([Vector3, Art], Art wie MARKS)
func update_minimap(pos: Vector3, dir: float, others: Array) -> void:
	if _radar == null:
		return
	if route_target != null:
		others = others + [[route_target, "route"]]
	if _map_rect.size.x != 0.0:
		var uv = Vector2((pos.x - _map_rect.position.x) / _map_rect.size.x, (pos.z - _map_rect.position.y) / _map_rect.size.y)
		_radar.material.set_shader_parameter("center", uv)
	_arrow.rotation = -dir # Blick +Z = nach oben, +X (in Godot links) = nach links
	var radius = _radar.size.x / 2.0
	var scale_px = radius / (RADAR_DIAMETER * MAP_ZOOM * 0.5)
	_radar_pos = pos
	_radar_scale = scale_px
	var marks = []
	for o in others:
		var p: Vector3 = o[0]
		var off = Vector2(-(p.x - pos.x), -(p.z - pos.z)) * scale_px
		if o[1] == "route" and off.length() >= radius - 8.0:
			off = off.limit_length(radius - 8.0) # Ziel außerhalb: am Rand in seiner Richtung
		if off.length() < radius - 3.0:
			marks.append([_radar.size / 2.0 + off, _mark_tex.get(o[1])])
	_radar_marks.marks = marks
	_radar_marks.queue_redraw()
