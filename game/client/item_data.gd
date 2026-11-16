extends RefCounted

# ====================================================
# Gegenstände im Client (Schritt 10b), je Vorlage einmal gelesen aus der elements.data der Sprache
# (npc_data.gd elements):
#   info(id)    {id, name, type, quality, icon, mask, lv, race, prof, gender, hp, mp, dmg [min, max],
#               def, hit, range, pile, price, equip}
#   icon(id)    Symbol: file_icon -> path.data nennt eine Datei (z.B. surfaces\武器图标\x.dds), die es
#               einzeln nicht gibt - sie steht in den Symbol-Atlanten surfaces\iconset\iconlist_ivtr0 - 2
#               (.dds + .txt wie CECGameUIMan: Breite, Höhe, Zeilen, Spalten, dann die Dateinamen; Symbol i
#               in Spalte i % Spalten, Zeile i / Spalten); erst im Sprachordner, dann in resources\
#   model(id, Rasse, Klasse, Geschlecht[, links])  Modell der Ausrüstung an der Figur (models[]: Eintrag
#               zu Rasse und Klasse, file_model_male / _female -> .ski = Kleidung, .ecm = Waffe; links:
#               file_model_male_l / _female_l, die Waffe der linken Hand, z.B. der zweite Dolch), "" wenn keins
#   tooltip(id, Anzahl, Spieler, Texte)  BBCode wie das Original (Bug-Fahrplan B1): desc (Plugin Data/angelica_itemdesc.gd)
#               führt LuaItemDesc:GetItemDesc der Spieldaten mit den Werten aus desc_values aus (Schlüssel wie
#               CECIvtrItem / CECIvtrEquip LuaParam_*), dahinter der Zusatztext aus item_ext_desc.txt; Symbol des
#               Gegenstands, Münzen (gebunden = Seelenmünzen, sonst Goldmünzen) und Bewertungs-Sterne als Bilder aus den
#               Atlanten (iconlist_ivtr*, iconlist_hint). Ohne desc (Skripte fehlen) die einfache Fassung: Name in der
#               Qualitätsfarbe, Platz, Werte, Bedingungen (nicht erfüllte rot), Stapel, Verkaufspreis.
#   Bilder im BBCode: [img] lädt über den ResourceLoader - die Texturen bekommen deshalb einen Pfad unter RUNTIME
#               (take_over_path, nur im Speicher; der ResourceCache liefert sie)
#   destroyable(id) false bei proc_type-Bit 0x400 (PROC_NOT_DESTROYABLE); usable(id) Rechtsklick benutzt (Quest-Würfel)
# Qualitätsfarben wie STRING_TABLE.ITEMQUALITY_COL_0 - 9 (script\global_string.lua,
# CLuaResource::GetItemQualityColor).
# ====================================================

const QUALITY_COLORS = ["a1a3a4", "ffffff", "00ff00", "006eff", "9800cd", "f7cc00", "ff0000", "ff0000", "1eb0ff", "b468ff"]
const RED = "ff4040"
const GREY = "c8c8c8"
const ICON_SETS = ["iconlist_ivtr0", "iconlist_ivtr1", "iconlist_ivtr2"]
const HINT_SET = "iconlist_hint" # kleine Symbole der Texte (Münzen, Sterne)
const RUNTIME = "res://__pwe_runtime/"
const PROC_NOT_DESTROYABLE = 0x400
const ICON_MARK = "\uE000I\uE001" # Platzhalter in den Lua-Werten (Zeichen privater Nutzung), to_bbcode macht daraus Bilder
const COIN_KEYS = {"icon_crystal": "水晶", "icon_gold": "金币", "icon_silver": "银币", "icon_copper": "铜币"}
const STAR_FILE = "评星.tga"

var elements = null # angelica_elements.gd
var files = null # angelica_files.gd (Symbol-Atlanten)
var language = "Deu"
var _cache = {}
var _icons = {}
var _atlas_index = {} # Dateiname klein -> [Atlas, Symbol]
var _atlases: Array = [] # [{tex, w, h, cols}]
var _atlas_loaded = false
var desc = null # Plugin Data/angelica_itemdesc.gd (geöffnet), sonst die einfache Beschreibung
var _hint = {} # Dateiname klein -> AtlasTexture (iconlist_hint)
var _hint_loaded = false
var _paths = {} # Textur -> Pfad unter RUNTIME


func info(id: int) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var r: Dictionary = elements.get_record(id) if elements != null else {}
	var t = str(r.get("_type", ""))
	var out = {"id": id, "name": _clean(r.get("name", str(id))), "type": t, "quality": int(r.get("item_quality", 1)),
		"icon": elements.path_of(int(r.get("file_icon", 0))) if r.has("file_icon") and elements != null else "",
		"pile": maxi(1, int(r.get("pile_num_max", 1))), "price": int(r.get("shop_price", r.get("price", 0))),
		"equip": t == "EQUIPMENT_ESSENCE", "models": r.get("models", []),
		# Quest-Würfel (EXP-Cocktail ...): Rechtsklick benutzt ihn (Z5), Leiste mit progress_desc ("Trinken")
		"use": t == "TASKDICE_ESSENCE", "use_desc": _clean(r.get("progress_desc", "")), "proc": int(r.get("proc_type", 0))}
	if out["equip"]:
		out["mask"] = int(r.get("equip_mask", 0))
		out["lv"] = int(r.get("require_level", 0))
		out["race"] = int(r.get("mask_race", 0))
		out["prof"] = int(r.get("character_combo_id", 0))
		out["gender"] = int(r.get("require_gender", 2))
		out["hp"] = int(r.get("hp", 0))
		out["mp"] = int(r.get("mp", 0))
		out["dmg"] = [int(r.get("min_dmg", 0)), int(r.get("min_dmg", 0)) + int(r.get("dmg_val", 0))]
		out["def"] = int(r.get("defence", 0))
		out["hit"] = int(r.get("attack", 0))
		out["range"] = float(r.get("attack_range", 0.0))
		out["action_type"] = int(r.get("action_type", 0))
	_cache[id] = out
	return out

func icon(id: int) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	_load_atlases()
	var key = info(id)["icon"].replace("\\", "/").get_file().to_lower()
	var at: Array = _atlas_index.get(key, [])
	var tex: AtlasTexture = null
	if not at.is_empty():
		var a: Dictionary = _atlases[at[0]]
		tex = AtlasTexture.new()
		tex.atlas = a["tex"]
		tex.region = Rect2((at[1] % a["cols"]) * a["w"], (at[1] / a["cols"]) * a["h"], a["w"], a["h"])
	_icons[id] = tex
	return tex

func _load_atlases() -> void:
	if _atlas_loaded or files == null:
		return
	_atlas_loaded = true
	for n in ICON_SETS:
		var txt = ""
		for base in [language + "/surfaces/iconset", "resources/" + language + "/surfaces/iconset", "resources/surfaces/iconset"]:
			txt = files.resolve("%s/%s.txt" % [base, n])
			if txt != "":
				break
		if txt == "":
			continue
		var lines: PackedStringArray = files.read_lines(txt)
		var img = files.load_image(txt.get_basename() + ".dds") if lines.size() > 4 else null
		if img == null:
			continue
		var ai = _atlases.size()
		_atlases.append({"tex": ImageTexture.create_from_image(img), "w": lines[0].to_int(), "h": lines[1].to_int(),
			"cols": maxi(1, lines[3].to_int())})
		for i in range(4, lines.size()):
			var key = lines[i].strip_edges().to_lower()
			if key != "" and not _atlas_index.has(key):
				_atlas_index[key] = [ai, i - 4]

func destroyable(id: int) -> bool:
	return int(info(id).get("proc", 0)) & PROC_NOT_DESTROYABLE == 0

# Symbol aus iconlist_hint (z.B. "金币.tga"), null wenn es fehlt
func hint_icon(file_name: String) -> Texture2D:
	if not _hint_loaded and files != null:
		_hint_loaded = true
		var txt = ""
		for base in [language + "/surfaces/iconset", "resources/" + language + "/surfaces/iconset", "resources/surfaces/iconset"]:
			txt = files.resolve("%s/%s.txt" % [base, HINT_SET])
			if txt != "":
				break
		var lines: PackedStringArray = files.read_lines(txt) if txt != "" else PackedStringArray()
		var img = files.load_image(txt.get_basename() + ".dds") if lines.size() > 4 else null
		if img != null:
			var atlas = ImageTexture.create_from_image(img)
			var w = lines[0].to_int()
			var h = lines[1].to_int()
			var cols = maxi(1, lines[3].to_int())
			for i in range(4, lines.size()):
				var key = lines[i].strip_edges().to_lower()
				if key != "" and not _hint.has(key):
					var at = AtlasTexture.new()
					at.atlas = atlas
					at.region = Rect2(((i - 4) % cols) * w, ((i - 4) / cols) * h, w, h)
					_hint[key] = at
	return _hint.get(file_name.to_lower())

# Pfad, unter dem [img] die Textur findet ("" ohne Textur)
func image_path(tex: Texture2D) -> String:
	if tex == null:
		return ""
	if not _paths.has(tex):
		var p = RUNTIME + "img%d.tex" % _paths.size()
		tex.take_over_path(p)
		_paths[tex] = p
	return _paths[tex]

# Erster Platz (EQUIP_INDEX_*) einer Ausrüstung, -1 wenn keine
func slot_of(id: int) -> int:
	var mask = int(info(id).get("mask", 0))
	for i in 32:
		if mask & (1 << i):
			return i
	return -1

func model(id: int, race: int, prof: int, gender: int, left: bool = false) -> String:
	if elements == null:
		return ""
	var any = ""
	var field = ("file_model_female" if gender == 1 else "file_model_male") + ("_l" if left else "")
	for m in info(id)["models"]:
		var f = int(m.get(field, 0))
		if f == 0:
			continue
		if int(m.get("race", 0)) == race and int(m.get("profession", 0)) == prof:
			return elements.path_of(f)
		if any == "" and int(m.get("race", 0)) == race:
			any = elements.path_of(f)
	return any

# Bedingungen für die Figur p ({level, race, class, gender}) -> [Stufe ok, Rasse ok, Klasse ok, Geschlecht ok]
func fits(id: int, p: Dictionary) -> Array:
	var i = info(id)
	if not i["equip"]:
		return [true, true, true, true]
	var race = int(i["race"])
	var prof = int(i["prof"])
	return [int(i["lv"]) <= int(p.get("level", 1)), race == 0 or (race & (1 << int(p.get("race", 0)))) != 0,
		prof == 0 or (prof & (1 << int(p.get("class", 0)))) != 0, int(i["gender"]) == 2 or int(i["gender"]) == int(p.get("gender", 0))]

# Werte für LuaItemDesc:GetItemDesc (Kontext 0 = Tasche) wie LuaParam_Common / _LevelReq / _RaceReqMask / _ProfReqMask /
# _GeneralMask / _EquipName / _Equip / _EquipEvaluation; Werte eines einzelnen Stücks (Haltbarkeit, Verstärkung, Zufalls-
# Eigenschaften, Edelsteine) gibt es noch nicht: Haltbarkeit fehlt (keine Zeile), alles andere wie bei einem neuen Stück
func desc_values(id: int, count: int, p: Dictionary) -> Dictionary:
	var r: Dictionary = elements.get_record(id) if elements != null else {}
	var i = info(id)
	var bind = int(r.get("sell_for_bind_money", 0)) != 0
	var v = {"context": 0, "iconpath": ICON_MARK, "name": i["name"], "quality": int(i["quality"]), "color_idx": 0,
		"count": maxi(1, count), "bound": false, "boundafterequip": false, "fromshop": false, "is_locked": false,
		"is_unlocking": false, "expire_time": 0, "shop_sell_price": int(r.get("shop_price", 0)),
		"shop_buy_price": int(r.get("price", 0)), "bind_money": bind}
	for k in COIN_KEYS:
		v[k] = _mark(k)
	var proc = int(r.get("proc_type", 0))
	for b in 32:
		if proc & (1 << b):
			v["proc_mask_%d" % (b + 1)] = true
	if not i["equip"]:
		return v
	v["level"] = int(p.get("level", 1))
	v["req_level"] = int(i["lv"])
	v["race"] = int(p.get("race", 0))
	for b in range(1, 16):
		if int(i["race"]) & (1 << b):
			v["race_req_mask_%d" % b] = true
	v["profession"] = int(p.get("class", 0))
	for b in range(1, 16):
		if int(i["prof"]) & (1 << b):
			v["prof_req_mask_%d" % b] = true
	for key in [["equip_pos_mask_%d", "equip_mask"], ["equip_hide_mask_%d", "hide_equip_mask"], ["equip_show_mask_%d", "show_mask"],
			["equip_disable_show_mask_%d", "disable_show_mask"]]:
		var m = int(r.get(key[1], 0))
		for b in 32:
			if m & (1 << b):
				v[key[0] % b] = true
	v["equip_template_name"] = i["name"]
	v["equip_type"] = int(r.get("equip_type", 0))
	v["req_gender"] = int(i["gender"])
	v["gender"] = int(p.get("gender", 0))
	v["equip_ess_quality"] = int(i["quality"])
	v["refine_level"] = 0
	v["mark_type"] = 0
	v["marked_name"] = ""
	v["equip_atk_distance"] = float(i["range"])
	v["equip_hit"] = int(i["hit"])
	v["equip_dodge"] = int(r.get("armor", 0))
	v["refine_max_level"] = int(r.get("refine_max_level", 0))
	v["gfx_req_luster"] = int(r.get("show_gfx_need_gem_value", 0))
	v["repair_count"] = 0
	v["can_decompose"] = int(r.get("can_decompose", 0)) != 0
	v["can_upgrade"] = int(r.get("equip_transform_cfg_id", 0)) != 0
	v["vip_limit"] = int(r.get("require_vip_level", 0))
	v["vip_level"] = 0
	v["attrib_evaluation"] = 0
	v["forbid_transfer_ehance"] = int(r.get("is_forbid_transfer_ehance", 0)) != 0
	v["quench_quality"] = int(i["quality"])
	var d: Array = i["dmg"]
	v["equip_minattack"] = int(d[0])
	v["equip_maxattack"] = int(d[1])
	v["equip_defence"] = int(i["def"])
	v["equip_max_hp"] = int(i["hp"])
	v["equip_max_mp"] = int(i["mp"])
	for k in ["attack", "defence", "hp", "mp", "hit", "jouk"]:
		v["equip_potential_" + k] = -1 # kein Potenzial (die Zeilen entfallen)
	v["icon_evalu_star"] = _mark("icon_evalu_star")
	if int(r.get("useful_in_judge", 0)) == 0:
		v["default_evalu_star"] = int(r.get("base_star_level", 0))
	else:
		v["evalu_sum_score"] = 0
	return v

static func _mark(key: String) -> String:
	return "\uE000%s\uE001" % key

# Bilder der Platzhalter für to_bbcode: Symbol des Gegenstands, Münzen (gebunden: Seelenmünzen), Stern
func _images(id: int, bind: bool) -> Dictionary:
	var out = {}
	var ip = image_path(icon(id))
	if ip != "":
		out[ICON_MARK] = ip
	for k in COIN_KEYS:
		var hp = image_path(hint_icon(("绑定" if bind else "") + COIN_KEYS[k] + ".tga"))
		if hp != "":
			out[_mark(k)] = hp
	var sp = image_path(hint_icon(STAR_FILE))
	if sp != "":
		out[_mark("icon_evalu_star")] = sp
	return out

# tx: hud.gd texts() (Platz-Namen, Beschriftungen); class_label: Callable(Klasse) -> Name
func tooltip(id: int, count: int, p: Dictionary, tx: Dictionary, class_label: Callable) -> String:
	if desc != null and desc.ready():
		var r: Dictionary = elements.get_record(id) if elements != null else {}
		var aui: String = desc.describe(desc.icid_of(str(r.get("_type", ""))), desc_values(id, count, p))
		var ext: String = desc.ext_desc(id)
		if ext != "":
			aui = aui.strip_edges(false, true) + "\r\r" + ext # wie AddExtDescText (_StringTrimRight)
		if aui != "":
			var images = _images(id, int(r.get("sell_for_bind_money", 0)) != 0)
			var icon_path = str(images.get(ICON_MARK, ""))
			images.erase(ICON_MARK)
			var bb: String = desc.to_bbcode(aui.replace(ICON_MARK, ""), images)
			return ("[img=32x32]%s[/img] " % icon_path if icon_path != "" else "") + bb
	var i = info(id)
	var q = clampi(int(i["quality"]), 0, QUALITY_COLORS.size() - 1)
	var lines = ["[color=#%s]%s[/color]" % [QUALITY_COLORS[q], _bb(i["name"])]]
	if i["equip"]:
		var slots: Array = tx["slots"]
		var s = slot_of(id)
		if s >= 0 and s < slots.size() and slots[s] != "":
			lines.append("[color=#%s]%s[/color]" % [GREY, slots[s]])
		var ok = fits(id, p)
		var d: Array = i["dmg"]
		if d[1] > 0:
			lines.append(tx["item_dmg"] % [d[0], d[1]])
		if i["def"] > 0:
			lines.append(tx["item_def"] % i["def"])
		if i["hp"] > 0:
			lines.append(tx["item_hp"] % i["hp"])
		if i["mp"] > 0:
			lines.append(tx["item_mp"] % i["mp"])
		if i["hit"] > 0:
			lines.append(tx["item_hit"] % i["hit"])
		if i["range"] > 0.0:
			lines.append(tx["item_range"] % i["range"])
		if i["lv"] > 0:
			lines.append(_req(tx["item_lv"] % i["lv"], ok[0]))
		if i["prof"] != 0:
			var names = []
			for c in range(1, 16):
				if i["prof"] & (1 << c):
					names.append(class_label.call(c))
			lines.append(_req(tx["item_prof"] % ", ".join(names), ok[2]))
		if i["gender"] != 2:
			lines.append(_req(tx["item_gender"] % tx["genders"][clampi(i["gender"], 0, 1)], ok[3]))
		if not ok[1]:
			lines.append(_req(tx["item_race"], false))
	if i["pile"] > 1:
		lines.append(tx["item_pile"] % [count, i["pile"]])
	if i["price"] > 0:
		lines.append("[color=#%s]%s[/color]" % [GREY, tx["item_price"] % i["price"]])
	return "\n".join(lines)

static func _req(s: String, ok: bool) -> String:
	return s if ok else "[color=#%s]%s[/color]" % [RED, s]

static func _bb(s: String) -> String:
	return s.replace("[", "[lb]")

static func _clean(s) -> String:
	var t = str(s)
	return load("res://addons/PWE-Manager/Data/angelica_elements.gd").strip_codes(t).strip_edges() if t.contains("^") else t.strip_edges()
