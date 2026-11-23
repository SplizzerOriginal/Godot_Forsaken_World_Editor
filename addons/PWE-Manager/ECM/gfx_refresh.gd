@tool
extends RefCounted

# ====================================================
# Stand der GFX-Erzeugung und Neubau veralteter GFX zur Laufzeit (Bug-Fahrplan B10, Teil 4).
# Der Import backt die GFX-Shader in die Szenen (Modelle mit ihren CoGfx unter ECM_Import/models, Karten-Effekte unter
# ECM_Import/gfx). Ändert sich danach der Code, der die GFX baut, zeigen alte Importe noch den alten Stand. Darum trägt
# jede importierte Modell- und GFX-Szene den Stempel STAMP_META = Prüfsumme über die Skripte und Shader der GFX
# (GFX/*.gd, *.gdshader, *.gdshaderinc und ECM/ecm_cogfx.gd). Der Client vergleicht ihn (outdated) und baut veraltete
# GFX mit dem aktuellen Code im Speicher neu:
#   refresh_model  Modell-Szene: alte CoGfx weg, neu aus der .ecm (Meta ecm_path) mit ecm_cogfx.gd, die GFX als Instanzen
#                  aus gfx_scene (z.B. attack_fx.gd _scene: je Datei einmal gebaut); Skelett, Netze, Aktionen bleiben
#   add_cogfx      CoGfx an ein Modell ohne sie (auch für Modelle, die der Client ohne Import baut)
#   gfx_path       Szene eines Karten-Effekts -> GfxPath (relativ zu gfx\) für den Neubau
# Szenen ohne Stempel (Importe vor diesem Stand) gelten als veraltet.
# ====================================================

const STAMP_META = "gfx_code"
const CoGfx = preload("ecm_cogfx.gd")
const GFX_DIR_SCRIPT = preload("../GFX/gfx_parser.gd") # Ordner GFX/
const CODE_EXT = ["gd", "gdshader", "gdshaderinc"]
const IMPORT_GFX_DIR = "res://ECM_Import/gfx/" # ecm_importer.gd OUT_ROOT + gfx/

static var _stamp = ""


# Prüfsumme des GFX-Codes (einmal je Programmlauf berechnet)
static func stamp() -> String:
	if _stamp != "":
		return _stamp
	if OS.has_feature("template"):
		_stamp = "export" # exportiertes Spiel: ohne Quelltext; die Szenen sind mit dem Export umgewandelt (outdated)
		return _stamp
	var gfx_script: Script = GFX_DIR_SCRIPT # über eine Variable: an der Konstante sucht GDScript resource_path als Klassen-Mitglied
	var cogfx_script: Script = CoGfx
	var dir = gfx_script.resource_path.get_base_dir()
	var paths: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in CODE_EXT:
			paths.append(dir.path_join(f))
	paths.sort()
	paths.append(cogfx_script.resource_path)
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for p in paths:
		ctx.update(p.get_file().to_utf8_buffer())
		ctx.update(FileAccess.get_file_as_bytes(p))
	_stamp = ctx.finish().hex_encode()
	return _stamp

# Stempel einer Szene (Meta ihrer Wurzel), ohne sie zu instanzieren; "" = keiner
static func scene_stamp(packed: PackedScene) -> String:
	return str(_root_meta(packed, STAMP_META, ""))

# Szene vor dem aktuellen GFX-Code gebaut?
static func outdated(packed: PackedScene) -> bool:
	if OS.has_feature("template"):
		return false # exportiertes Spiel: alle Szenen kommen frisch aus dem Export (Leiste EXPORT)
	return packed != null and scene_stamp(packed) != stamp()

# Meta der Wurzel aus dem Szenen-Zustand
static func _root_meta(packed: PackedScene, key: String, def):
	var st = packed.get_state() if packed != null else null
	if st == null or st.get_node_count() == 0:
		return def
	var want = "metadata/" + key
	for i in st.get_node_property_count(0):
		if st.get_node_property_name(0, i) == want:
			return st.get_node_property_value(0, i)
	return def

# Modell-Szene mit veralteten CoGfx -> neue Szene im Speicher (CoGfx mit dem aktuellen Code); ohne .ecm bzw. bei
# Fehlern die alte. importer: ecm_importer.gd (read_ecm), gfx_scene: FxFilePath -> PackedScene.
# -> {"scene": PackedScene, "gfx": Anzahl neu gebauter GFX, "removed": Anzahl entfernter alter}
static func refresh_model(importer, packed: PackedScene, gfx_scene: Callable, ecm_path: String = "") -> Dictionary:
	if ecm_path == "":
		ecm_path = str(_root_meta(packed, "ecm_path", ""))
	var out = {"scene": packed, "gfx": 0, "removed": 0}
	if packed == null or ecm_path == "" or importer == null:
		return out
	var ecm: Dictionary = importer.read_ecm(ecm_path)
	if ecm.has("error"):
		return out
	var root = packed.instantiate()
	var sk = root.get_node_or_null("Skeleton3D") as Skeleton3D
	var old: Array = []
	for c in root.get_children():
		if is_gfx(c):
			old.append(c)
	if sk != null:
		for att in sk.get_children():
			if att is BoneAttachment3D and str(att.name).begins_with(CoGfx.ATTACH_PREFIX):
				for c in att.get_children():
					if is_gfx(c):
						old.append(c)
	for n in old:
		n.get_parent().remove_child(n)
		n.free()
	out["removed"] = old.size()
	out["gfx"] = add_cogfx(importer, root, ecm, gfx_scene)
	var neu = PackedScene.new()
	var err = neu.pack(root)
	root.free()
	if err == OK:
		out["scene"] = neu
	return out

# CoGfx einer .ecm (read_ecm) an ein Modell ohne sie hängen (Haken = Bones des Skeletts, ohne Groß / Klein), Stempel
# setzen; auch für Modelle, die der Client ohne Import baut (ecm_importer.gd build_ecm). -> Anzahl der GFX
static func add_cogfx(importer, root: Node3D, ecm: Dictionary, gfx_scene: Callable) -> int:
	var sk = root.get_node_or_null("Skeleton3D") as Skeleton3D
	var entries: Array = ecm.get("cogfx", [])
	var n = 0
	if sk != null and not entries.is_empty():
		var hook_bones = {}
		for i in sk.get_bone_count():
			var k = sk.get_bone_name(i).to_lower()
			if not hook_bones.has(k):
				hook_bones[k] = i
		var cogfx = CoGfx.new(importer.files, importer.warnings)
		n = cogfx.build(root, sk, hook_bones, entries, gfx_scene)
	root.set_meta(STAMP_META, stamp())
	return n

# Datei-Node einer GFX (gfx_data_node.gd)?
static func is_gfx(n: Node) -> bool:
	var s = n.get_script() as Script
	return s != null and s.resource_path.get_file() == "gfx_data_node.gd"

# Importierte GFX-Szene (ECM_Import/gfx/<Pfad>.scn, ältere .tscn) -> GfxPath "<Pfad>.gfx" relativ zu gfx\, "" = keine
static func gfx_path(scene_path: String) -> String:
	if not scene_path.begins_with(IMPORT_GFX_DIR):
		return ""
	return scene_path.substr(IMPORT_GFX_DIR.length()).get_basename() + ".gfx"
