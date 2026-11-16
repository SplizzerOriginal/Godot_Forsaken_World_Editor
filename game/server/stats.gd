extends RefCounted

# ====================================================
# Werte der Figuren wie der gs (player_template::BuildBaseProp, npc_template::BuildBaseProp), aus
# dem Plugin: Server/class_templates.json (Klassen, EXP-Kurve, Stufen-Zuschläge) und den
# Monster-Vorlagen in Server/npc_templates.json.
#   Spieler  max. HP = hp + lvlup_hp * (Stufe - require_level) + hp_mp_modify[Stufe - 1], MP ebenso
#            EXP bis zur nächsten Stufe = level_exp[Stufe]
#   Monster  max. HP = hp + lvlup.hp * (Stufe - level[0]), MP ebenso (NPCs: ihr Quell-Monster)
# Ohne class_templates.json gelten die Werte der Startvorlage (hp / mp) als Maximum.
#   Kampfwerte (attributes, Charakter-Fenster): Grundwert + lvlup_* * (Stufe - require_level) der
#            Klasse (abgeschnitten) + Stufen-Zuschlag (LEVELUP_MODIFY_CONFIG: dmg_def_modify für Angriff /
#            Verteidigung, hit_jouk_modify für Treffer / Ausweichen, je [Stufe - 1]), dazu die Ausrüstung (inventory.gd
#            bonus): Angriff dmg + min_dmg .. dmg + min_dmg + dmg_val, Verteidigung + defence, Treffer + attack;
#            Krit-Werte in Prozent; mas / res je Element [physisch, Erde, Wasser, Feuer, Wind, Licht, Dunkel, ohne]
#            = mastery / resistance + lvlup_* * (Stufe - require_level), abgeschnitten, + mas_res_modify (Z6)
# ====================================================

const PLUGIN_SERVER = "res://addons/PWE-Manager/Server/"

var classes = {} # Klasse (String) -> Werte
var level_exp: Array = []
var hp_mp_modify: Array = []
var dmg_def_modify: Array = [] # Stufen-Zuschlag Angriff / Verteidigung (je Stufe - 1)
var hit_jouk_modify: Array = [] # Treffer / Ausweichen
var mas_res_modify: Array = [] # Meisterschaft / Widerstand
var learn_money_factor: Array = [] # Lernkosten je Figurenstufe (skills.gd cost_of)
var task_money_factor: Array = [] # Quest-Gold je Figurenstufe (quests.gd, award money_lev)
var task_bind_money_factor: Array = [] # Quest-Seelenmünzen je Figurenstufe
var task_factor: Array = [] # Quest-EXP je Figurenstufe (award exp_lev / exp_fix)


func _init() -> void:
	var path = PLUGIN_SERVER + "class_templates.json"
	var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if d is Dictionary:
		classes = d.get("classes", {})
		level_exp = d.get("level_exp", [])
		learn_money_factor = d.get("learn_money_factor", [])
		task_money_factor = d.get("task_money_factor", [])
		task_bind_money_factor = d.get("task_bind_money_factor", [])
		task_factor = d.get("task_factor", [])
		hp_mp_modify = d.get("hp_mp_modify", [])
		dmg_def_modify = d.get("dmg_def_modify", [])
		hit_jouk_modify = d.get("hit_jouk_modify", [])
		mas_res_modify = d.get("mas_res_modify", [])

# EXP einer Quest-Belohnung (CTaskAwardExp): exp_fix -> * Faktor der Stufe exp_lev; sonst mit exp_lev (m_bExpRevise)
# * Faktor der Figurenstufe, höchstens Stufe exp_lev; ohne exp_lev der Wert selbst (abgeschnitten)
static func task_exp(amount: int, exp_lev: int, fix: bool, level: int, factors: Array) -> int:
	if exp_lev <= 0 or amount == 0:
		return amount
	var i = (exp_lev if fix else mini(level, exp_lev)) - 1
	var f = float(factors[i]) if i >= 0 and i < factors.size() else 1.0
	return int(amount * f + 1e-6)

# Geld einer Quest-Belohnung (Kupfer): ohne money_lev der Wert selbst, sonst * Faktor der Stufe der Figur,
# höchstens Stufe money_lev (CTaskAwardGold / CTaskAwardBindMoney mit m_bGoldRevise; abgeschnitten)
static func task_money(amount: int, money_lev: int, level: int, factors: Array) -> int:
	if money_lev <= 0 or amount == 0:
		return amount
	var i = mini(level, money_lev) - 1
	var f = float(factors[i]) if i >= 0 and i < factors.size() else 1.0
	return int(amount * f + 1e-6)

func loaded() -> bool:
	return not classes.is_empty()

func max_hp(cls: int, level: int, fallback: int = 1) -> int:
	return _player(cls, level, "hp", fallback)

func max_mp(cls: int, level: int, fallback: int = 1) -> int:
	return _player(cls, level, "mp", fallback)

# EXP bis zur nächsten Stufe (0 = höchste Stufe)
func exp_next(level: int) -> int:
	return int(level_exp[level]) if level >= 0 and level < level_exp.size() else 0

func _player(cls: int, level: int, key: String, fallback: int) -> int:
	var c = classes.get(str(cls))
	if c == null:
		return maxi(1, fallback)
	var modify = int(hp_mp_modify[level - 1]) if level >= 1 and level <= hp_mp_modify.size() else 0
	return maxi(1, int(float(c[key]) + float(c["lvlup_" + key]) * (level - int(c["require_level"])) + 1e-5) + modify)

# Stufen-Zuschlag aus einer LEVELUP_MODIFY_CONFIG-Liste (Index Stufe - 1, wie _level_modify_table[Stufe])
static func _modify(list: Array, level: int) -> int:
	return int(list[level - 1]) if level >= 1 and level <= list.size() else 0

# Kampfwerte: {dmg: [min, max], def, hit, eva, crit, crit_dmg, anti_crit, anti_crit_dmg, mas [8], res [8]}
func attributes(cls: int, level: int, bonus: Dictionary) -> Dictionary:
	var c = classes.get(str(cls), {})
	var up = level - int(c.get("require_level", 0))
	var v = func(key: String) -> float: return float(c.get(key, 0.0)) + float(c.get("lvlup_" + key, 0.0)) * up
	var dmg = v.call("dmg")
	var d: Array = bonus.get("dmg", [0, 0])
	var dd = _modify(dmg_def_modify, level)
	var hj = _modify(hit_jouk_modify, level)
	var mr = _modify(mas_res_modify, level)
	var m: Array = c.get("mastery", [])
	var r: Array = c.get("resistance", [])
	var mu: Array = c.get("lvlup_mastery", [])
	var ru: Array = c.get("lvlup_resistance", [])
	var mas = []
	var res = []
	for i in 8:
		mas.append(int((float(m[i]) if i < m.size() else 0.0) + (float(mu[i]) if i < mu.size() else 0.0) * up + 1e-5) + mr)
		res.append(int((float(r[i]) if i < r.size() else 0.0) + (float(ru[i]) if i < ru.size() else 0.0) * up + 1e-5) + mr)
	return {"dmg": [int(dmg + d[0] + 1e-5) + dd, int(dmg + d[1] + 1e-5) + dd], "def": int(v.call("defense") + 1e-5) + dd + int(bonus.get("def", 0)),
		"hit": int(v.call("attack") + 1e-5) + hj + int(bonus.get("hit", 0)), "eva": int(v.call("armor") + 1e-5) + hj, "mas": mas, "res": res,
		"crit": snappedf(v.call("crit_rate"), 0.1), "crit_dmg": snappedf(v.call("crit_damage"), 0.1),
		"anti_crit": snappedf(v.call("anti_crit_rate"), 0.1), "anti_crit_dmg": snappedf(v.call("anti_crit_damage"), 0.1)}

# Monster-Vorlage (npc_templates.json "monsters") auf Stufe level: [max. HP, max. MP]
static func monster_hp_mp(t: Dictionary, level: int) -> Array:
	if t.is_empty():
		return [1, 0]
	var levels: Array = t.get("level", [level])
	var base_level = int(levels[0]) if not levels.is_empty() else level
	var up: Dictionary = t.get("lvlup", {})
	var hp = int(float(t.get("hp", 1)) + float(up.get("hp", 0)) * (level - base_level))
	var mp = int(float(t.get("mp", 0)) + float(up.get("mp", 0)) * (level - base_level))
	return [maxi(1, hp), maxi(0, mp)]
