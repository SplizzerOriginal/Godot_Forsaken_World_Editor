@tool
extends RefCounted

# ====================================================
# Beschreibung (Tooltip) eines Gegenstands wie im Client: CECIvtrItem::GetLuaDesc ruft LuaItemDesc:GetItemDesc(Klasse,
# Werte) der Skripte <Sprache>\script\itemdesc\ (itemdesc.lua, itemdescutility.lua = Modul ModUtility, itemdesctext.lua
# mit Texten und Farben) mit STRING_TABLE aus <Sprache>\script\global_string.lua. Das Ergebnis ist AUI-Text: ^RRGGBB
# Farbe, ^Onnn Schriftgröße (^O057 groß für den Namen), Zeilenumbruch als \r oder als die zwei Zeichen "\r" (der Client
# ersetzt sie); danach hängt AddExtDescText die Beschreibung aus configs\item_ext_desc.txt an (UTF-16, <ID> "Text").
# Die Skripte laufen in angelica_lua.gd (Bytecode, module / package.seeall).
#   var d = ItemDesc.new(files, "Deu");  d.open() -> "" oder Fehler (~0,2 s, im Thread möglich)
#   d.describe(icid, werte) -> AUI-Text   icid_of(Listen-Typ) -> Klasse (ICID_*)   d.ext_desc(ID) -> Zusatztext
#   d.text("DESTORY_ITEM_KEY") -> Text aus STRING_TABLE ("" wenn es ihn nicht gibt)
#   to_bbcode(AUI-Text, Bilder {Marke: Pfad einer Textur}) -> BBCode für ein RichTextLabel
# Die Werte heißen wie die LuaParam_*-Schlüssel des Clients (context, iconpath, name, quality, count, bound,
# shop_buy_price = Verkauf an den Händler, shop_sell_price = Preis im Laden, bind_money, icon_gold ..., proc_mask_N,
# Ausrüstung: level / req_level, race / race_req_mask_N, profession / prof_req_mask_N, equip_pos_mask_N, equip_type,
# equip_minattack / maxattack / defence / max_hp / max_mp / hit / dodge ...); der Spiel-Client (item_data.gd) füllt sie.
# Nur Ausrüstung (ICID_EQUIP) und Quest-Gegenstände (ICID_TASKITEM) bekommen ihre eigene Beschreibung - die übrigen
# Klassen brauchen Werte, die es noch nicht gibt (Heiltrank-Wirkung, Abklingzeiten ...), und laufen als einfacher
# Gegenstand (GetBaseitemDesc: Name, Bindung, Preis).
# ====================================================

const Lua = preload("angelica_lua.gd")
const ICID_ITEM = -100
const ICID_EQUIP = 4
const ICID_TASKITEM = 38
const SCRIPTS = ["global_string.lua", "itemdesc/itemdesctext.lua", "itemdesc/itemdescutility.lua", "itemdesc/itemdesc.lua"]
const EXT_DESC = "item_ext_desc.txt"
const SIZE_BIG = "057" # ITEM_SIZE_DESC.Size12 (Name)
const FONT_BIG = 15
const FONT_NORMAL = 12

var files # angelica_files.gd
var language = "Deu"
var errors: Array = []
var _lua = null
var _fn = null # LuaItemDesc.GetItemDesc
var _self = null # LuaItemDesc
var _strings = {} # STRING_TABLE
var _ext = {} # ID -> Zusatztext (item_ext_desc.txt)
var _mutex = Mutex.new()


func _init(p_files, p_language: String = "Deu") -> void:
	files = p_files
	language = p_language

func open() -> String:
	var dir = ""
	for base in [language + "/script", "resources/" + language + "/script"]:
		if files.resolve(base) != "":
			dir = files.resolve(base)
			break
	if dir == "":
		return "%s/script fehlt" % language
	_lua = Lua.new(files)
	for s in SCRIPTS:
		var p = files.resolve(s, dir)
		if p == "":
			return s + " fehlt"
		var err = _lua.run_file(p)
		if err != "":
			return "%s: %s" % [s, err]
	errors.append_array(_lua.errors)
	_self = _lua.value("LuaItemDesc")
	_fn = _self.get("GetItemDesc") if _self is Dictionary else null
	var st = _lua.value("STRING_TABLE")
	_strings = st if st is Dictionary else {}
	_read_ext()
	return "" if _fn != null else "LuaItemDesc.GetItemDesc fehlt"

func close() -> void:
	if _lua != null:
		_lua.close()
	_lua = null
	_fn = null
	_self = null

func ready() -> bool:
	return _fn != null

# Listen-Typ der elements.data -> Klasse für GetItemDesc
static func icid_of(type: String) -> int:
	match type:
		"EQUIPMENT_ESSENCE":
			return ICID_EQUIP
		"TASKMATTER_ESSENCE":
			return ICID_TASKITEM
	return ICID_ITEM

# AUI-Text der Beschreibung ("" wenn die Skripte fehlen); Zusatztext (ext_desc) hängt der Aufrufer an
func describe(icid: int, values: Dictionary) -> String:
	if _fn == null:
		return ""
	_mutex.lock()
	var r = _lua._call(_fn, [_self, icid, values])
	_mutex.unlock()
	return str(r[0]) if not r.is_empty() and r[0] is String else ""

func ext_desc(id: int) -> String:
	return str(_ext.get(id, ""))

func text(key: String) -> String:
	var v = _strings.get(key)
	return str(v) if v != null else ""

# configs\item_ext_desc.txt: UTF-16 LE mit BOM, <ID> "Text" (mehrzeilig möglich) nach #_begin
func _read_ext() -> void:
	var p = ""
	for base in ["resources/configs", "configs"]:
		p = files.resolve("%s/%s" % [base, EXT_DESC])
		if p != "" and files.file_exists(p):
			break
		p = ""
	if p == "":
		errors.append(EXT_DESC + " fehlt")
		return
	var b: PackedByteArray = files.get_bytes(p)
	var t = b.slice(2).get_string_from_utf16() if b.size() > 1 and b[0] == 0xFF and b[1] == 0xFE else files.decode(b)
	var at = t.find("#_begin")
	var re = RegEx.create_from_string("(?m)^\\s*(\\d+)\\s+\"([^\"]*)\"")
	for m in re.search_all(t, maxi(0, at)):
		_ext[m.get_string(1).to_int()] = m.get_string(2).replace("\r\n", "\r")

# AUI-Text -> BBCode: Farben ^RRGGBB, Größe ^O057 (sonst normal), Zeilen \r / "\r"; Marken aus images (z.B. die
# Münz-Symbole, die als Werte icon_gold ... in den Text kamen) werden zu [img]; [ wird geschützt
static func to_bbcode(aui: String, images: Dictionary = {}) -> String:
	var s = aui.replace("\\r", "\r").replace("\r\n", "\r")
	var out = ""
	var color = ""
	var size = ""
	var run = ""
	var i = 0
	while i < s.length():
		var ch = s[i]
		if ch == "^" and i + 7 <= s.length() and _is_hex(s.substr(i + 1, 6)):
			out += _run_bb(run, color, size, images)
			run = ""
			color = s.substr(i + 1, 6).to_lower()
			i += 7
			continue
		if ch == "^" and i + 5 <= s.length() and s[i + 1] == "O" and s.substr(i + 2, 3).is_valid_int():
			out += _run_bb(run, color, size, images)
			run = ""
			size = s.substr(i + 2, 3)
			i += 5
			continue
		run += ch
		i += 1
	out += _run_bb(run, color, size, images)
	return out.strip_edges()

static func _run_bb(run: String, color: String, size: String, images: Dictionary) -> String:
	if run == "":
		return ""
	var t = run.replace("[", "[lb]").replace("\r", "\n")
	for mark in images:
		t = t.replace(str(mark).replace("[", "[lb]"), "[img=16x16]%s[/img]" % images[mark])
	if size == SIZE_BIG:
		t = "[font_size=%d]%s[/font_size]" % [FONT_BIG, t]
	if color != "":
		t = "[color=#%s]%s[/color]" % [color, t]
	return t

static func _is_hex(t: String) -> bool:
	if t.length() != 6:
		return false
	for c in t:
		if not "0123456789abcdefABCDEF".contains(c):
			return false
	return true
