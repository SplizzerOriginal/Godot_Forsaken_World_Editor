@tool
extends RefCounted

# ====================================================
# .gfx-Parser und Node-Aufbau, gemeinsam für pwe_manager.gd ("GFX Ausführen": GFX_Load -> Szene)
# und create_id_200.gd (Container: Unter-GFX aus den Spieldaten über gfx_sources.gd).
# Die .gfx dürfen GBK (Spieldaten) oder UTF-8 (eigene in GFX_Load) sein.
# Ein Datei-Node sieht immer gleich aus:
#   <Datei> (gfx_data_node.gd, Kopfzeile)
#     Element_<n>_ID_<id> (gfx_element_<id>.gd)
#       Affectors / CtrlMethods
#         Affector_<n>_Type_<typ> / CtrlMethod_<n>_Type_<typ> (gfx_ctrl_<typ>.gd)
# parsed_data wird nicht mit der Szene gespeichert, die Erstell-Skripte lesen es beim Erstellen.
# ====================================================

const LOAD_DIR = "res://GFX_Load/" # wird mit "GFX Ausführen" in die Szene geladen

var _dir = ""
static var _text = null # angelica_files.gd, nur zum Dekodieren


func _init() -> void:
	_dir = get_script().resource_path.get_base_dir()

# Baut den Datei-Node einer .gfx (nicht in der Szene). skipped_ids sammelt unbekannte Element-IDs.
func build_file_node(file_path: String, node_name: String, skipped_ids: Array = []) -> Node3D:
	var parsed_file = _parse_full_gfx_file_chunked(file_path)
	var file_node = Node3D.new()
	file_node.name = node_name
	file_node.set_script(load(_dir.path_join("gfx_data_node.gd")))
	file_node.parsed_data = parsed_file["header"]
	# Herkunft, z.B. für die .gphy daneben (ID 220)
	file_node.parsed_data["_file_path"] = file_path
	# DedaultScale: A3DGFXEx::CalcActualScale = DefScale * Scale -> Scale des Datei-Nodes
	var def_scale = float(str(file_node.parsed_data.get("DedaultScale", "1")))
	if def_scale != 1.0:
		file_node.scale = Vector3.ONE * def_scale

	var element_count = 1
	for element_dict in parsed_file["elements"]:
		var raw_id = element_dict.get("_system_id", "Unknown")
		var script_path = _dir.path_join("gfx_element_" + raw_id + ".gd")
		if not ResourceLoader.exists(script_path):
			skipped_ids.append(raw_id)
			continue

		var element_node = Node3D.new()
		element_node.name = "Element_" + String.num(element_count) + "_ID_" + raw_id
		element_count += 1
		element_node.set_script(load(script_path))
		element_node.parsed_data = element_dict
		file_node.add_child(element_node)

		_spawn_ctrl_nodes("Affector", element_dict.get("_affectors", []), element_node)
		_spawn_ctrl_nodes("CtrlMethod", element_dict.get("_ctrl_methods", []), element_node)
	return file_node

static func _decoder():
	if _text == null:
		_text = preload("../Data/angelica_files.gd").new()
	return _text

# Den Dekodierer freigeben (Ende eines Imports, Plugin entladen): als statische Variable hielte er
# sonst die Skripte bis zum Beenden fest ("resources still in use at exit")
static func release_decoder() -> void:
	_text = null

# GFX-Alpha (Header / Container): GeometryInstance3D.transparency wirkt bei eigenen Shadern nicht,
# daher bekommt jeder erzeugte Shader ein Uniform, das ALPHA am Ende von fragment() multipliziert.
# Ein Material-Uniform, kein Instanz-Uniform: jede Instanz mit Instanz-Uniforms belegt 16 Plätze im
# globalen Puffer (Standard 65536), Maps mit tausenden GFX liefen über ("Too many instances using
# shader instance variables"). Header und Container haben ohnehin eigene Material-Kopien je GFX.
# ====================================================
# GEMEINSAMER SHADER-VORRAT (Performance-Fahrplan P1)
# Jedes Shader-Objekt kostet beim ersten Einhängen eines Materials eigene Arbeit (Vulkan ~12 ms je Objekt, auch wenn ein
# anderes Objekt denselben Text schon übersetzt hat; GL ~7 ms), ein geteiltes Objekt nichts. Die GFX-Texte sind fast alle
# im Aufbau verschieden (s9 + s31 + 110 NPC-Modelle: 446 Texte), aber dieselbe GFX steckt in vielen Szenen -> 1.259
# Objekte. Darum: gleicher Text = ein Objekt - beim Bauen (shared_shader) und beim Laden importierter Szenen, bevor sie
# eingehängt werden (share_scene). Kein Code darf den Text eines Shaders aus dem Vorrat nachträglich ändern.
# ====================================================
static var _shader_pool = {} # Text -> Shader

# Shader mit diesem Text aus dem Vorrat (neu angelegt, wenn es ihn noch nicht gibt)
static func shared_shader(code: String) -> Shader:
	var sh = _shader_pool.get(code)
	if sh == null:
		sh = Shader.new()
		sh.code = code
		_shader_pool[code] = sh
	return sh

# Shader eines Materials gegen das Objekt aus dem Vorrat tauschen (gleicher Text) -> true wenn getauscht; das erste Objekt
# eines Texts wird selbst zum Vorrat
static func share_material(m: Material) -> bool:
	var sm = m as ShaderMaterial
	if sm == null or sm.shader == null:
		return false
	var code = sm.shader.code
	var pooled = _shader_pool.get(code)
	if pooled == null:
		_shader_pool[code] = sm.shader
		return false
	if pooled == sm.shader:
		return false
	sm.shader = pooled
	return true

# Geladene Szene (vor dem Instanzieren): Materialien aller Knoten und eingebetteten Unter-Szenen auf den Vorrat umstellen,
# ohne zu instanzieren (Szenen-Zustand: die Material-Ressourcen dort sind dieselben, die jede Instanz bekommt). Jede Szene
# nur einmal (Meta). -> Anzahl getauschter Shader
static func share_scene(packed: PackedScene) -> int:
	if packed == null or packed.has_meta(SHARED_META):
		return 0
	packed.set_meta(SHARED_META, true)
	var st = packed.get_state()
	var n = 0
	for i in st.get_node_count():
		var sub = st.get_node_instance(i)
		if sub != null:
			n += share_scene(sub)
		for j in st.get_node_property_count(i):
			var v = st.get_node_property_value(i, j)
			if v is ShaderMaterial:
				n += 1 if share_material(v) else 0
			elif v is Mesh:
				for k in (v as Mesh).get_surface_count():
					n += 1 if share_material((v as Mesh).surface_get_material(k)) else 0
	return n

# Vorrat leeren (nach einem Import im Editor; zur Laufzeit bleibt er für die ganze Sitzung)
static func release_shader_pool() -> void:
	_shader_pool.clear()

static func shader_pool_size() -> int:
	return _shader_pool.size()

static func add_gfx_alpha(code: String) -> String:
	var at = code.find("void fragment()")
	if at < 0 or "GFX_Alpha" in code:
		return code
	# Funktionsende: "}" am Zeilenanfang (Blöcke darin sind eingerückt)
	var end = code.find("\n}", at)
	if end < 0:
		return code
	code = code.substr(0, end + 1) + "\tALPHA *= GFX_Alpha;\n" + code.substr(end + 1)
	return code.substr(0, at) + "// GFX-Alpha (Header / Container), je GFX gesetzt\nuniform float GFX_Alpha = 1.0;\n\n" + code.substr(at)

# Warp (Hitzeflimmern, B10) wie das Original (CECFullGlowRender::DoWarps mit dem spacewarp-Pixelshader der Spieldaten): die
# Textur des Elements ist eine Verschiebungs-Karte - (rot, grün) * 2 - 1, x gespiegelt, mal Alpha des Elements bzw. Partikels
# (A3DWARPVERTEX u3 / v3) mal Alpha der Textur verschieben die Bildkoordinaten; unter 5 % Textur-Alpha nichts (texkill); gezeigt
# wird nur das verschobene Bild, deckend, nie die Farbe der Textur (sonst der rosa Feuerball). Das Original verzerrt das fertige
# Bild samt aller GFX; Godots Bildschirm-Textur enthält nur das Undurchsichtige - deshalb zeichnen Warp-Elemente zuerst
# (WARP_PRIORITY) und die übrigen GFX darüber, sonst deckte der Warp sie mit dem bloßen Hintergrund zu (das Lagerfeuer).
const WARP_PRIORITY = Material.RENDER_PRIORITY_MIN
const SHARED_META = "shader_pool_shared" # an einer PackedScene: share_scene ist durch
const WARP_UNIFORM = "uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;\n"

# Zeichenreihenfolge der Elemente (B10) wie A3DGFXRenderSlotMan::Render: die Render-Slots laufen in der Reihenfolge ihrer
# Anmeldung (fortlaufender Schlüssel m_dwCurIndex, beim Laden einer GFX = Reihenfolge der Elemente in der Datei), die Ebenen
# RenderLayer BASE4 ... BASE1 davor, FRONT1 ... FRONT4 danach. "Priority" ist im Original keine Reihenfolge, sondern die
# Detailstufe (A3DGFXEx::Render überspringt Elemente über der Stufe des GFX-Managers, Standard 4 = alle) - als Reihenfolge
# gelesen lag z.B. der Kern des Feuerballs (letztes Element, Priority 0) unter seinen rosa Wolken (Priority 1 / 3)
const LAYER_RANK = {0: 0, 1: -1, 2: 1, 3: -2, 4: 2, 5: -3, 6: 3, 7: -4, 8: 4} # GFX_RENDER_LAYER_* -> Rang
const ORDER_STEP = 25 # Plätze je Ebene (weitere Elemente teilen sich den letzten)

static func element_priority(element: Node, parsed_data: Dictionary) -> int:
	var idx = element.get_index() if element != null and element.get_parent() != null else 0
	var name = str(element.name) if element != null else ""
	if name.begins_with("Element_"):
		var num = name.substr(8).get_slice("_", 0)
		if num.is_valid_int():
			idx = int(num) - 1
	var layer = int(str(parsed_data.get("RenderLayer", "0")).strip_edges())
	return clampi(int(LAYER_RANK.get(layer, 0)) * ORDER_STEP + clampi(idx, 0, ORDER_STEP - 1), WARP_PRIORITY + 1,
		Material.RENDER_PRIORITY_MAX)

# Lage-Geschichte der GFX in der Welt (B10, gfx_world_trail.gd füllt sie je Bild): Uniforms und trail_at(Alter in s) ->
# Drehung (Quaternion) und Verschiebung der Lage von damals im Raum von jetzt; TrailCount 0 = ohne Geschichte (feste GFX).
# Genutzt von ungebundenen Partikeln (create_id_120: IsBind 0) und Spuren (create_id_110: Bind 0, wie A3DTrail mit
# Weltpositionen - z.B. der Bogen hinter der Klinge beim Blitzschläger des Kriegers)
const TRAIL_SAMPLES = 16

static func trail_code() -> String:
	var n = str(TRAIL_SAMPLES)
	var c = "uniform int TrailCount = 0;\nuniform vec4 TrailPos[" + n + "];\nuniform vec4 TrailRot[" + n + "];\n\n"
	c += "vec3 trail_qrot(vec4 q, vec3 v) {\n\treturn v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);\n}\n"
	c += "// Lage der GFX vor age s im Raum von jetzt (Lage-Geschichte, sonst unverändert)\n"
	c += "vec4 trail_at(float age, out vec3 off) {\n"
	c += "\toff = vec3(0.0);\n"
	c += "\tif (TrailCount <= 0) return vec4(0.0, 0.0, 0.0, 1.0);\n"
	c += "\tint last = min(TrailCount, " + n + ") - 1;\n"
	c += "\tif (age <= TrailPos[0].w) { off = TrailPos[0].xyz; return TrailRot[0]; }\n"
	c += "\tfor (int k = 1; k < " + n + "; k++) {\n"
	c += "\t\tif (k > last) break;\n"
	c += "\t\tif (age <= TrailPos[k].w) {\n"
	c += "\t\t\tfloat f = (age - TrailPos[k - 1].w) / max(0.0001, TrailPos[k].w - TrailPos[k - 1].w);\n"
	c += "\t\t\toff = mix(TrailPos[k - 1].xyz, TrailPos[k].xyz, f);\n"
	c += "\t\t\tvec4 q1 = TrailRot[k];\n"
	c += "\t\t\tif (dot(TrailRot[k - 1], q1) < 0.0) q1 = -q1;\n"
	c += "\t\t\treturn normalize(mix(TrailRot[k - 1], q1, f));\n"
	c += "\t\t}\n"
	c += "\t}\n"
	c += "\toff = TrailPos[last].xyz;\n"
	c += "\treturn TrailRot[last];\n"
	c += "}\n\n"
	return c

# Fragment-Zeilen des Warps: tex = Texturfarbe (vec4), alpha = Ausdruck für das Alpha des Elements / Partikels
static func warp_fragment(tex: String, alpha: String, indent: String = "\t") -> String:
	var s = indent + "// --- WARP wie das Original: Textur = Verschiebung, gezeigt nur das verschobene Bild ---\n"
	s += indent + "if (%s.a < 0.05) {\n%s\tdiscard;\n%s}\n" % [tex, indent, indent]
	s += indent + "vec2 warp_off = vec2(1.0 - 2.0 * %s.r, %s.g * 2.0 - 1.0) * clamp(%s, 0.0, 1.0) * %s.a;\n" % [tex, tex, alpha, tex]
	s += indent + "ALBEDO = textureLod(screen_texture, SCREEN_UV + warp_off, 0.0).rgb;\n" # ohne Mip-Wahl: keine Ränder am discard
	s += indent + "ALPHA = 1.0;\n"
	return s

# Alpha der ganzen GFX an einem Node: GFX_Alpha, sonst transparency (StandardMaterial / ältere Shader)
static func set_gfx_alpha(g: GeometryInstance3D, a: float) -> void:
	var m = g.material_override
	if m is ShaderMaterial and m.shader != null and "GFX_Alpha" in m.shader.code:
		if "instance uniform float GFX_Alpha" in m.shader.code: # vor dem Umbau importierte Szenen
			g.set_instance_shader_parameter("GFX_Alpha", a)
		else:
			m.set_shader_parameter("GFX_Alpha", a)
	else:
		g.transparency = clampf(1.0 - a, 0.0, 1.0)

# 2DRender der GFX (Datei-Node über dem Element): A3DGFXEx::IsZTestEnable() = !2DRender
static func gfx_2d_render(element: Node) -> bool:
	var header = element.get_parent() if element != null else null
	var data = header.get("parsed_data") if header != null else null
	return typeof(data) == TYPE_DICTIONARY and str(data.get("2DRender", "0")).strip_edges() == "1"

# Tiefentest eines Elements: m_pGfx->IsZTestEnable() && m_bZEnable
static func z_test_enabled(element: Node, parsed_data: Dictionary) -> bool:
	var z = str(parsed_data.get("ZEnable", "1")).strip_edges().to_lower() in ["1", "true"]
	return z and not gfx_2d_render(element)

func _spawn_ctrl_nodes(group_name: String, data_list: Array, parent_node: Node) -> void:
	if data_list.is_empty(): return

	var container = Node3D.new()
	container.name = group_name + "s"
	parent_node.add_child(container)

	var count = 1
	for data in data_list:
		var type_id = data.get("CtrlType", "Unknown")
		var node = Node3D.new()
		node.name = group_name + "_" + str(count) + "_Type_" + type_id
		count += 1

		var script_path = _dir.path_join("gfx_ctrl_" + type_id + ".gd")
		if ResourceLoader.exists(script_path):
			node.set_script(load(script_path))
			node.parsed_data = data
		else:
			push_warning("PWE-Manager: Skript fehlt für CtrlType " + type_id)
		container.add_child(node)

# ---- DATEIEN SAMMELN ----
func get_all_gfx_files_recursively(current_dir: String, relative_path: String) -> Array:
	var result = []
	var d = DirAccess.open(current_dir)
	if not d: return result
	d.list_dir_begin()
	var item = d.get_next()
	while item != "":
		if not item in [".", ".."]:
			if d.current_is_dir(): result.append_array(get_all_gfx_files_recursively(current_dir+"/"+item, relative_path+item+"/"))
			elif item.get_extension().to_lower() == "gfx": result.append(relative_path+item)
		item = d.get_next()
	return result

func _parse_full_gfx_file_chunked(file_path: String) -> Dictionary:
	var result = {"header": {}, "elements": []}
	if not _decoder().file_exists(file_path): return result

	# Spieldaten sind GBK, eigene .gfx in GFX_Load oft UTF-8 (angelica_files.gd erkennt beides)
	var lines = []
	for raw_line in _decoder().read_lines(file_path):
		var line = raw_line.strip_edges()
		if not line.is_empty(): lines.append(line)
		
	var header_lines = []
	var elements_chunks = []
	var current_chunk = null
	
	for line in lines:
		if line.begins_with("GFXELEMENTID:"):
			current_chunk = []
			elements_chunks.append(current_chunk)
			current_chunk.append(line)
		else:
			if current_chunk != null: current_chunk.append(line)
			else: header_lines.append(line)
			
	var h_tracker = {}
	for line in header_lines:
		_parse_single_line(line, result["header"], h_tracker)
		
	for chunk in elements_chunks:
		result["elements"].append(_parse_element_chunk(chunk))
		
	return result

func _parse_element_chunk(lines: Array) -> Dictionary:
	var dict = {"_system_id": "", "_affectors": [], "_ctrl_methods": [], "_keypoints": [], "_ps_consts": []}
	var key_tracker = {}
	var i = 0
	
	while i < lines.size():
		var line = lines[i]
		
		# --- 1. ELEMENT ID KOPFDATEN ---
		if line.begins_with("GFXELEMENTID:"):
			var after_colon = line.split(":", true, 1)[1].strip_edges()
			var pure_number = ""
			for char in after_colon:
				if char >= "0" and char <= "9": pure_number += char
				else: break
			dict["_system_id"] = pure_number
			_parse_single_line(line, dict, key_tracker)
			i += 1
			continue
			
		# --- 2. PIXEL SHADER ARRAYS ---
		if line.begins_with("PSConstCount:"):
			_parse_single_line(line, dict, key_tracker)
			var ps_count = int(line.split(":", true, 1)[1].strip_edges())
			i += 1
			var ps_array = []
			for p in range(ps_count):
				if i >= lines.size(): break
				var ps_block = {"_targets": []}
				if i < lines.size() and lines[i].begins_with("PSConstIndex:"):
					ps_block["PSConstIndex"] = lines[i].split(":", true, 1)[1].strip_edges()
					i += 1
				if i < lines.size() and lines[i].begins_with("PSConstValue:"):
					ps_block["PSConstValue"] = lines[i].split(":", true, 1)[1].strip_edges()
					i += 1
				if i < lines.size() and lines[i].begins_with("PSLoopCount:"):
					ps_block["PSLoopCount"] = lines[i].split(":", true, 1)[1].strip_edges()
					i += 1
				if i < lines.size() and lines[i].begins_with("PSTargetCount:"):
					var t_count_str = lines[i].split(":", true, 1)[1].strip_edges()
					ps_block["PSTargetCount"] = t_count_str
					i += 1
					var target_count = int(t_count_str)
					for t in range(target_count):
						if i >= lines.size(): break
						var target_data = {}
						if i < lines.size() and lines[i].begins_with("PSInterval:"):
							target_data["PSInterval"] = lines[i].split(":", true, 1)[1].strip_edges()
							i += 1
						if i < lines.size() and lines[i].begins_with("PSConstValue:"):
							target_data["PSConstValue"] = lines[i].split(":", true, 1)[1].strip_edges()
							i += 1
						ps_block["_targets"].append(target_data)
				ps_array.append(ps_block)
			dict["_ps_consts"] = ps_array
			continue
			
		# --- 3. AFFECTORS ---
		if line.begins_with("AffectorCount:"):
			_parse_single_line(line, dict, key_tracker)
			var count = int(line.split(":", true, 1)[1].strip_edges())
			i += 1
			if count > 0:
				var current_ctrl = {}
				var ctrl_tracker = {}
				while i < lines.size():
					var sub_line = lines[i]
					# SCHRANKE: Bricht ab, wenn Fallback-Methoden oder der globale KeypointBlock startet:
					var is_kp_start = (sub_line.begins_with("StartTime:") and i+1 < lines.size() and lines[i+1].begins_with("KEYPOINTCOUNT:"))
					if sub_line.begins_with("CtrlMethodCount:") or is_kp_start:
						break
						
					if sub_line.begins_with("CtrlType:"):
						if not current_ctrl.is_empty(): dict["_affectors"].append(current_ctrl)
						current_ctrl = {}
						ctrl_tracker = {}
						_parse_single_line(sub_line, current_ctrl, ctrl_tracker)
					elif not current_ctrl.is_empty():
						_parse_single_line(sub_line, current_ctrl, ctrl_tracker)
					i += 1
				if not current_ctrl.is_empty(): dict["_affectors"].append(current_ctrl)
			continue
			
		# --- 4. KEYPOINTS (beinhaltet die eigenen CtrlMethods!) ---
		if line.begins_with("KEYPOINTCOUNT:"):
			_parse_single_line(line, dict, key_tracker)
			var kp_count = int(line.split(":", true, 1)[1].strip_edges())
			i += 1
			var kp_array = []
			for k in range(kp_count):
				if i >= lines.size(): break
				var kp_block = {"_ctrl_methods": []}
				var kp_tracker = {}
				
				while i < lines.size():
					var kp_line = lines[i]
					if kp_line.begins_with("CtrlMethodCount:"):
						kp_block["CtrlMethodCount"] = kp_line.split(":", true, 1)[1].strip_edges()
						i += 1
						var cm_count = int(kp_block["CtrlMethodCount"])
						if cm_count > 0:
							var current_ctrl = {}
							var ctrl_tracker = {}
							while i < lines.size():
								var cm_line = lines[i]
								# SCHRANKE: Bricht in der Methode NUR ab, wenn der nächste Keypoint anfängt!
								if cm_line.begins_with("InterpolateMode:"):
									break
									
								if cm_line.begins_with("CtrlType:"):
									if not current_ctrl.is_empty():
										kp_block["_ctrl_methods"].append(current_ctrl)
										dict["_ctrl_methods"].append(current_ctrl)
									current_ctrl = {}
									ctrl_tracker = {}
									_parse_single_line(cm_line, current_ctrl, ctrl_tracker)
								elif not current_ctrl.is_empty():
									_parse_single_line(cm_line, current_ctrl, ctrl_tracker)
								i += 1
							if not current_ctrl.is_empty():
								kp_block["_ctrl_methods"].append(current_ctrl)
								dict["_ctrl_methods"].append(current_ctrl)
						break # Das war das Ende DIESES Keypoints. Springe zum nächsten 'k'.
					else:
						_parse_single_line(kp_line, kp_block, kp_tracker)
						i += 1
				if not kp_block.is_empty():
					kp_array.append(kp_block)
			dict["_keypoints"] = kp_array
			continue

		# --- 5. STANDALONE CONTROL METHODS (Fallback für Elemente ohne Keypoints!) ---
		if line.begins_with("CtrlMethodCount:"):
			_parse_single_line(line, dict, key_tracker)
			var count = int(line.split(":", true, 1)[1].strip_edges())
			i += 1
			if count > 0:
				var current_ctrl = {}
				var ctrl_tracker = {}
				while i < lines.size():
					var sub_line = lines[i]
					# SCHRANKE: Bricht ab, wenn versehentlich danach noch Affectors oder Keypoints kommen!
					var is_kp_start = (sub_line.begins_with("StartTime:") and i+1 < lines.size() and lines[i+1].begins_with("KEYPOINTCOUNT:"))
					if sub_line.begins_with("AffectorCount:") or is_kp_start:
						break
						
					if sub_line.begins_with("CtrlType:"):
						if not current_ctrl.is_empty(): dict["_ctrl_methods"].append(current_ctrl)
						current_ctrl = {}
						ctrl_tracker = {}
						_parse_single_line(sub_line, current_ctrl, ctrl_tracker)
					elif not current_ctrl.is_empty():
						_parse_single_line(sub_line, current_ctrl, ctrl_tracker)
					i += 1
				if not current_ctrl.is_empty(): dict["_ctrl_methods"].append(current_ctrl)
			continue
		# --- 5.5 GRID ANIMATION LINES (Base64 Blöcke für 210/211) ---
		if line.begins_with("GridAnimationLines:"):
			var anim_count = int(line.split(":", true, 1)[1].strip_edges())
			i += 1
			
			# Wenn das Array noch nicht existiert, erstellen wir es
			if not dict.has("_grid_animations"):
				dict["_grid_animations"] = []
				
			# Wir lesen genau so viele Zeilen ein, wie 'anim_count' verlangt
			for a in range(anim_count):
				if i < lines.size():
					dict["_grid_animations"].append(lines[i])
					i += 1
			continue

		
		# --- 6. STANDARD PARAMETER (Der Rest) ---
		_parse_single_line(line, dict, key_tracker)
		i += 1
		
	return dict

func _parse_single_line(line: String, dict: Dictionary, tracker: Dictionary):
	var split = line.split(":", true, 1)
	if split.size() >= 2:
		var key = split[0].strip_edges()
		var val = split[1].strip_edges()
		if tracker.has(key):
			tracker[key] += 1
			dict[key + "_" + str(tracker[key])] = val
		else:
			tracker[key] = 1
			if key in ["Vec", "TexSpeed", "NoScale", "OrgPt"]: dict[key + "_1"] = val
			else: dict[key] = val
	else:
		var key = "GridVector"
		if tracker.has(key):
			tracker[key] += 1
			dict[key + "_" + str(tracker[key])] = line
		else:
			tracker[key] = 1
			dict[key + "_1"] = line
