extends CharacterBody3D

# ====================================================
# Eigene Spielfigur in der Welt (vereinfacht nach EC_HostMove / EC_CameraCtrl):
#   W / S / A / D oder Pfeiltasten  laufen relativ zur Kamera (A / D seitlich)
#   Umschalt gedrückt  gehen statt rennen (elements.data: 1,35 / 4,0 m/s)
#   Leertaste  springen;  linke Maustaste auf den Boden  dorthin laufen, auf eine Figur (NPC,
#   Monster, anderer Spieler: Auswahl-Kapsel auf Ebene PICK_LAYER)  Signal picked(ID) statt laufen
#   rechte Maustaste ziehen  Kamera drehen (auch hoch / runter);  Mausrad  Abstand
# Autoroute: follow_path(Wegpunkte, Halteabstand) läuft einen Weg der Wegfindung ab (rennend);
# Bewegungstasten oder ein Klick brechen ab (route_finished(false)), am Ziel route_finished(true);
# kommt die Figur ROUTE_STUCK_TIME s lang kaum voran, route_stuck (world_screen.gd sucht neu).
# Kampf: play_attack (普通攻击<1-3>_<suffix>, Reihenfolge zufällig wie CECPlayer::PlayAttackEffect),
# play_hurt (受伤_通用, nur im Stehen), die (死亡_通用, dann liegen 死亡循环_通用), revive; manual_move
# meldet Bewegungstasten / Klick auf den Boden (beendet den Normalangriff, bricht das Zaubern ab);
# play_skill(Aktion) spielt die Aktion einer Fertigkeit einmal (z.B. 法师_火球术).
# Schwerkraft und Kollision (Terrain und Gebäude, world_screen.gd), Stufen bis STEP_HEIGHT werden beim Laufen hinauf
# genommen (CECPlayer fStepHei 0,8 m, CDR FullGroundMove: hoch, vor, auf den Boden dahinter), die Kamera weicht Wänden aus
# (SpringArm3D). Position = Füße wie im Spiel; Richtung = Drehung der Figur um Y (0 = Blick +Z).
# Animationen: Stehen, Gehen, Rennen, Springen (Start, Schleife, Landen).
# Gewurzelt / betäubt (rooted, Siegel root vom Server wie LIES_ROOT): keine Bewegung, kein Sprung; Klickziel und
# Autoroute enden (route_finished(false)). Ansturm: dash(Ziel, s) gleitet in der Zeit dorthin (Eingaben ruhen).
# Schleifen-Aktionen einer Fertigkeit (Name mit 循环, z.B. das Stadtportal) laufen bis stop_once; mehrteilige Aktionen
# (Sammeln: Start, Schleife, Ende) über play_segment / end_segment.
# Kampfzustand (wie CECPlayer::SetIsFighting(true, 6000)): mark_fight() bei Angriff und Treffer, bis
# FIGHT_TIME s nach dem letzten; dann hängen die Waffen in der Hand (angelica_player.gd place_weapons),
# Stehen / Rennen sind 战斗站立 / 战斗奔跑_<Waffenart>; danach wieder Rücken bzw. Gürtel.
# ====================================================

const Proto = preload("../common/protocol.gd")
const PICK_LAYER = 4 # Ebene 3: Auswahl-Kapseln (world_npc.gd, remote_player.gd)
const GRAVITY = 20.0
const JUMP_SPEED = 7.0
const TURN_RATE = 12.0
const CAM_MIN = 2.0
const CAM_MAX = 20.0
const CAM_START = 7.0
const MOUSE_TURN = 0.006
const PITCH_MIN = -1.35
const PITCH_MAX = 0.6
const ARRIVE = 0.3
const SNAP_UP = 1.0 # m: so weit darf ein Punkt des Servers unter dem Boden liegen (Stadtpunkte: ganze Meter)
const SNAP_DOWN = 50.0 # m: so weit unter dem Punkt wird der Boden gesucht
const WAYPOINT_REACHED = 0.6 # m: nächster Wegpunkt
const ROUTE_STUCK_TIME = 1.2 # s
const ROUTE_STUCK_MOVE = 0.3 # m in dieser Zeit
const STEP_HEIGHT = 0.8 # m: höchste Stufe, die die Figur beim Laufen nimmt (m_MoveConst.fStepHei)
const COLLISION_EXTENTS = Vector3(0.3, 0.76, 0.3) # halbe Maße der Kollisionsbox (PlayerUtil::vPlayerAABBOrgExts)
const ANIM = {"stand": "站立_通用", "walk": "行走_通用", "run": "奔跑_通用", "jump_start": "跳跃起_通用",
	"jump_loop": "跳跃循环_通用", "land": "跳跃落地_通用"}
const FIGHT_ANIM = {"stand": "战斗站立_%s", "run": "战斗奔跑_%s"} # Waffenart
const FIGHT_TIME = 6.0 # s
const PLAYER_MODEL = "res://addons/PWE-Manager/ECM/angelica_player.gd"

signal picked(id: int)
signal route_finished(arrived: bool)
signal route_stuck
signal manual_move

var model: Node3D # Figur aus angelica_player.gd
var anim: AnimationPlayer
var camera: Camera3D
var cam_yaw: Node3D
var cam_pitch: Node3D
var arm: SpringArm3D
var height = 1.8
var radius = 0.3 # Kapsel (setup, COLLISION_EXTENTS.x)
var target = null # Klickziel (Vector3) oder null
var state = Proto.MOVE_STAND
var input_enabled = true
var dead = false
var suffix = "空手" # Endung der Kampf-Aktionen (Waffenart)
var fighting = false
var speed_add = 0.0 # m/s aus Tempo-Effekten (stats speed_add)
var rooted = false # Siegel root (Meldung seal): stehen bleiben
var _dash = {} # Ansturm: {from, to, t, time}
var _fight_until = 0 # ms
var _once = "" # laufende Einmal-Aktion (Angriff, Treffer)
var _seg_loop = "" # Schleife einer mehrteiligen Aktion (Sammeln: Start, Schleife, Ende), die auf ihren Start folgt
var _attack_seq = 1
var _was_moving = false
var path = PackedVector3Array() # Autoroute: Wegpunkte (x, z zählen)
var path_index = 0
var path_stop = 0.0 # m vor dem letzten Punkt anhalten
var _stuck_t = 0.0
var _stuck_from = Vector3.ZERO
var _jump = false
var _airborne = false
var _turning = false
var _last_floor = Vector3.ZERO


func setup(p_model: Node3D, p_height: float) -> void:
	model = p_model
	height = p_height
	add_child(model)
	anim = model.get_node_or_null("AnimationPlayer")
	# Kollision wie das Original: feste Box PlayerUtil::vPlayerAABBOrgExts (halbe Maße 0,3 / 0,76 / 0,3 = 0,6 x 1,52 m,
	# CECHostPlayer m_pCDRInfo->vExtent), unabhängig von der Modellhöhe - hier als Kapsel gleicher Breite und Höhe. Mit der
	# Modellhöhe (~1,8 - 2 m) stieß die Figur unter niedrigen Balken an (Bude litmodel_2750 am Wiederbelebungspunkt von s9,
	# Unterkante 1,83 m), wo die Wegekarte des Servers begehbar sagt -> Autoroute steckte fest (Bug-Fahrplan B2)
	var capsule = CapsuleShape3D.new()
	capsule.radius = COLLISION_EXTENTS.x
	capsule.height = COLLISION_EXTENTS.y * 2.0
	radius = capsule.radius
	var cs = CollisionShape3D.new()
	cs.shape = capsule
	cs.position.y = COLLISION_EXTENTS.y
	add_child(cs)
	collision_layer = 2 # Ebene 1 = Terrain und Gebäude (Bodenstrahlen der NPCs)
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(55)
	cam_yaw = Node3D.new()
	cam_yaw.name = "KameraDrehung"
	cam_yaw.position.y = height * 0.85
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_pitch.rotation.x = -0.3
	cam_yaw.add_child(cam_pitch)
	arm = SpringArm3D.new()
	arm.spring_length = CAM_START
	arm.margin = 0.2
	arm.add_excluded_object(get_rid())
	cam_pitch.add_child(arm)
	camera = Camera3D.new()
	camera.far = 2000.0
	camera.fov = 60.0
	arm.add_child(camera)
	camera.current = true
	_play("stand")

# -> gespielte Aktion (für die Angriffs-Effekte)
func play_attack() -> String:
	var act = "普通攻击%d_%s" % [_attack_seq, suffix]
	_attack_seq = randi() % 3 + 1
	if anim == null or not anim.has_animation(act):
		act = "普通攻击1_空手"
	_play_once(act)
	return act

# Aktion einer Fertigkeit einmal abspielen -> Länge s (0 = Figur hat sie nicht)
func play_skill(act: String) -> float:
	if anim == null or act == "" or not anim.has_animation(act) or dead:
		return 0.0
	if act.contains("循环"):
		anim.get_animation(act).loop_mode = Animation.LOOP_LINEAR # bis zum Ende des Zauberns (stop_once)
	anim.play(act, 0.1)
	_once = act
	return anim.get_animation(act).length

# Laufende Einmal-Aktion beenden (Zaubern abgebrochen)
func stop_once() -> void:
	_once = ""
	_seg_loop = ""
	_animate()

# Mehrteilige Aktion wie CECPlayer::PlaySegmentedAction (B10, Sammeln: 采矿开始 -> 采矿循环 ...): Start einmal, dann die
# Schleife bis end_segment / stop_once; fehlt der Start, gleich die Schleife -> false ohne Schleife
func play_segment(start: String, loop: String) -> bool:
	if anim == null or dead or loop == "" or not anim.has_animation(loop):
		return false
	anim.get_animation(loop).loop_mode = Animation.LOOP_LINEAR
	_seg_loop = loop
	if start != "" and anim.has_animation(start):
		anim.play(start, 0.15)
		anim.queue(loop)
		_once = start
	else:
		anim.play(loop, 0.15)
		_once = loop
	return true

# Ende der mehrteiligen Aktion (Sammeln fertig): Ende einmal, danach wieder Stehen
func end_segment(end: String) -> void:
	_seg_loop = ""
	if anim != null and not dead and end != "" and anim.has_animation(end):
		anim.play(end, 0.15)
		_once = end
	else:
		stop_once()

func play_hurt() -> void:
	if state == Proto.MOVE_STAND and _once == "" and not dead:
		_play_once("受伤_通用")

func die() -> void:
	dead = true
	stop_route(false)
	target = null
	_once = ""
	if anim != null and anim.has_animation("死亡_通用"):
		anim.play("死亡_通用", 0.1)
		if anim.has_animation("死亡循环_通用"):
			anim.queue("死亡循环_通用")

func revive() -> void:
	dead = false
	_once = ""
	set_fighting(false)
	_play("stand")

# Angriff / Treffer: FIGHT_TIME s im Kampf
func mark_fight() -> void:
	_fight_until = Time.get_ticks_msec() + int(FIGHT_TIME * 1000.0)
	if not fighting:
		set_fighting(true)

func set_fighting(on: bool) -> void:
	fighting = on
	load(PLAYER_MODEL).place_weapons(model, on)
	if not dead and _once == "":
		_animate()

func _play_once(act: String) -> void:
	if anim != null and anim.has_animation(act) and not dead:
		anim.play(act, 0.1)
		_once = act

# Zu einem Punkt drehen (Sammeln)
func face(p: Vector3) -> void:
	var d = p - global_position
	if model != null and Vector2(d.x, d.z).length() > 0.05:
		model.rotation.y = atan2(d.x, d.z)

# Neues Modell (andere Ausrüstung): Richtung und laufende Animation bleiben
func replace_model(p_model: Node3D) -> void:
	var dir = direction()
	var act = anim.current_animation if anim != null else ""
	if model != null:
		model.queue_free()
	model = p_model
	add_child(model)
	model.rotation.y = dir
	anim = model.get_node_or_null("AnimationPlayer")
	load(PLAYER_MODEL).place_weapons(model, fighting)
	if anim != null and act != "" and anim.has_animation(act):
		anim.play(act)

# Weg der Wegfindung ablaufen (stop_dist m vor dem Ende anhalten)
func follow_path(points: PackedVector3Array, stop_dist: float = 0.0) -> void:
	path = points
	path_stop = stop_dist
	path_index = 0
	# Punkte überspringen, die schon erreicht sind
	while path_index < path.size() - 1 and _flat(path[path_index]) < WAYPOINT_REACHED:
		path_index += 1
	target = path[path_index] if not path.is_empty() else null
	_stuck_t = 0.0
	_stuck_from = global_position

func following() -> bool:
	return not path.is_empty()

func stop_route(arrived: bool) -> void:
	if path.is_empty():
		return
	path = PackedVector3Array()
	target = null
	route_finished.emit(arrived)

func _flat(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

# Wegpunkt erreicht? Ende? Steckt die Figur fest?
func _follow(delta: float) -> void:
	var last = path_index == path.size() - 1
	var d = _flat(path[path_index])
	if last and d <= maxf(ARRIVE, path_stop):
		stop_route(true)
		return
	if not last and d < WAYPOINT_REACHED:
		path_index += 1
		target = path[path_index]
	_stuck_t += delta
	if _stuck_t >= ROUTE_STUCK_TIME:
		var moved = Vector2(global_position.x - _stuck_from.x, global_position.z - _stuck_from.z).length()
		_stuck_t = 0.0
		_stuck_from = global_position
		if moved < ROUTE_STUCK_MOVE:
			route_stuck.emit()

# Server setzt die Figur zurück (pos_correct) oder an den Start
func place(pos: Vector3, dir: float) -> void:
	global_position = on_floor(pos)
	velocity = Vector3.ZERO
	stop_route(false)
	target = null
	if model != null:
		model.rotation.y = dir
	if cam_yaw != null:
		cam_yaw.rotation.y = dir + PI # Kamera hinter der Figur
	_last_floor = pos

func direction() -> float:
	return model.rotation.y if model != null else 0.0

# Boden unter einem Punkt (gesucht ab SNAP_UP darüber), sonst der Punkt: die Stadtpunkte der Startvorlagen sind auf
# ganze Meter gerundet und liegen teils knapp unter dem Gelände (Werwolf s31: 254 unter 254,5), unter dem nichts mehr
# ist; ohne das fiele die Figur nach dem Stadtportal / Wiederbeleben durch die Welt
func on_floor(pos: Vector3) -> Vector3:
	if not is_inside_tree():
		return pos
	var q = PhysicsRayQueryParameters3D.create(pos + Vector3(0, SNAP_UP, 0), pos - Vector3(0, SNAP_DOWN, 0), 1)
	q.exclude = [get_rid()]
	q.hit_back_faces = false # nur Flächen, die nach oben zeigen
	var hit = get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else pos

# Ansturm (Meldung skill_move): in secs nach to gleiten
func dash(to: Vector3, secs: float) -> void:
	stop_route(false)
	target = null
	_dash = {"from": global_position, "to": to, "t": 0.0, "time": maxf(0.05, secs)}
	var d = to - global_position
	if model != null and Vector2(d.x, d.z).length() > 0.05:
		model.rotation.y = atan2(d.x, d.z)

func _physics_process(delta: float) -> void:
	if not _dash.is_empty():
		_dash["t"] = float(_dash["t"]) + delta
		var f = clampf(float(_dash["t"]) / float(_dash["time"]), 0.0, 1.0)
		global_position = (_dash["from"] as Vector3).lerp(_dash["to"], f)
		velocity = Vector3.ZERO
		state = Proto.MOVE_RUN if f < 1.0 else Proto.MOVE_STAND
		if f >= 1.0:
			_dash = {}
			_last_floor = global_position
		_animate()
		return
	var wish = Vector2.ZERO
	if input_enabled and not rooted:
		wish.x = _axis(KEY_D, KEY_RIGHT) - _axis(KEY_A, KEY_LEFT)
		wish.y = _axis(KEY_S, KEY_DOWN) - _axis(KEY_W, KEY_UP)
	if rooted:
		stop_route(false)
		target = null
		_jump = false
	var yaw = cam_yaw.global_rotation.y
	var forward = Vector3(-sin(yaw), 0, -cos(yaw))
	var right = Vector3(cos(yaw), 0, -sin(yaw))
	var move = Vector3.ZERO
	if wish != Vector2.ZERO:
		stop_route(false)
		target = null
		move = forward * -wish.y + right * wish.x
		if not _was_moving:
			manual_move.emit()
	elif not path.is_empty():
		_follow(delta)
	_was_moving = wish != Vector2.ZERO
	if wish == Vector2.ZERO and target != null:
		var to: Vector3 = target - global_position
		to.y = 0
		if to.length() < ARRIVE and path.is_empty():
			target = null
		elif to.length() >= 0.05:
			move = to
	var walking = input_enabled and Input.is_physical_key_pressed(KEY_SHIFT) and path.is_empty()
	var speed = Proto.WALK_SPEED if walking else maxf(0.5, Proto.RUN_SPEED + speed_add)
	if move != Vector3.ZERO:
		move = move.normalized() * speed
		model.rotation.y = lerp_angle(model.rotation.y, atan2(move.x, move.z), clampf(TURN_RATE * delta, 0.0, 1.0))
	velocity.x = move.x
	velocity.z = move.z
	if is_on_floor():
		_last_floor = global_position
		if _jump:
			velocity.y = JUMP_SPEED
			_airborne = true
			_play("jump_start")
	else:
		velocity.y -= GRAVITY * delta
	_jump = false
	var was_air = _airborne
	var was_floor = is_on_floor()
	move_and_slide()
	if was_floor and move != Vector3.ZERO and velocity.y <= 0.0:
		_step_up(Vector3(move.x, 0.0, move.z) * delta)
	if global_position.y < -500.0: # durch die Welt gefallen
		place(_last_floor + Vector3(0, 1, 0), direction())
	var flat = Vector2(velocity.x, velocity.z).length()
	if is_on_floor():
		if was_air and velocity.y <= 0.0:
			_airborne = false
			_play("land")
		state = Proto.MOVE_STAND if flat < 0.1 else (Proto.MOVE_WALK if walking else Proto.MOVE_RUN)
	else:
		_airborne = true
		state = Proto.MOVE_JUMP
	if fighting and Time.get_ticks_msec() > _fight_until and not dead:
		set_fighting(false)
	_animate()

# Stufe hinauf: stößt die Figur beim Laufen an eine Kante, prüfen, ob sie STEP_HEIGHT höher und ein Stück weiter (mindestens
# der halbe Radius) frei steht und darunter ein begehbarer Boden ist - dann steht sie dort
func _step_up(motion: Vector3) -> void:
	if motion.length() < 0.0001 or not is_on_wall():
		return
	var ahead = motion.normalized() * maxf(motion.length(), radius * 0.5)
	var up = Vector3(0, STEP_HEIGHT, 0)
	var t = global_transform
	if test_move(t, up):
		return # Decke
	var t2 = t.translated(up)
	if test_move(t2, ahead):
		return # auch oben eine Wand
	var t3 = t2.translated(ahead)
	var col = KinematicCollision3D.new()
	if not test_move(t3, -up, col):
		return # dahinter kein Boden in Stufenhöhe (Abgrund: normal weiterlaufen)
	if col.get_normal().angle_to(Vector3.UP) > floor_max_angle or col.get_travel().length() < 0.02:
		return # zu steil bzw. keine Stufe
	global_position = t3.origin + col.get_travel()
	velocity.y = 0.0

func _animate() -> void:
	if anim == null or dead:
		return
	if _once != "":
		if _seg_loop != "" and _once != _seg_loop and anim.current_animation == _seg_loop and state == Proto.MOVE_STAND:
			_once = _seg_loop # Start fertig, die Schleife läuft
		if anim.current_animation == _once and anim.is_playing() and state == Proto.MOVE_STAND:
			return
		_once = ""
		_seg_loop = ""
	var current = anim.current_animation
	if state == Proto.MOVE_JUMP:
		if current != ANIM["jump_start"] or not anim.is_playing():
			_play("jump_loop")
	elif current == ANIM["land"] and anim.is_playing() and state == Proto.MOVE_STAND:
		return
	else:
		_play({Proto.MOVE_STAND: "stand", Proto.MOVE_WALK: "walk", Proto.MOVE_RUN: "run"}[state])

func _play(key: String) -> void:
	var a = _anim_name(key)
	if anim == null or not anim.has_animation(a):
		return
	if anim.current_animation != a:
		anim.play(a, 0.15)

# Aktion zu einem Zustand, im Kampf die der Waffenart (falls die Figur sie hat)
func _anim_name(key: String) -> String:
	if fighting and FIGHT_ANIM.has(key) and anim != null and anim.has_animation(FIGHT_ANIM[key] % suffix):
		return FIGHT_ANIM[key] % suffix
	return ANIM[key]

func _axis(a: Key, b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	var mb = event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_turning = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			arm.spring_length = maxf(CAM_MIN, arm.spring_length * 0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			arm.spring_length = minf(CAM_MAX, arm.spring_length * 1.1)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_click_move(mb.position)
		return
	var mm = event as InputEventMouseMotion
	if mm != null and _turning:
		cam_yaw.rotation.y -= mm.relative.x * MOUSE_TURN
		cam_pitch.rotation.x = clampf(cam_pitch.rotation.x - mm.relative.y * MOUSE_TURN, PITCH_MIN, PITCH_MAX)
		return
	var k = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == KEY_SPACE:
		_jump = true

# Linksklick: Figur unter dem Mauszeiger auswählen, sonst den Boden als Ziel
func _click_move(screen: Vector2) -> void:
	var from = camera.project_ray_origin(screen)
	var to = from + camera.project_ray_normal(screen) * 500.0
	var pq = PhysicsRayQueryParameters3D.create(from, to, PICK_LAYER)
	pq.collide_with_areas = true
	pq.collide_with_bodies = false
	var pick = get_world_3d().direct_space_state.intersect_ray(pq)
	if not pick.is_empty() and pick["collider"].has_meta("pick_id"):
		# nur wenn kein Gebäude / Boden davor liegt
		var wq = PhysicsRayQueryParameters3D.create(from, pick["position"], 1)
		if get_world_3d().direct_space_state.intersect_ray(wq).is_empty():
			picked.emit(int(pick["collider"].get_meta("pick_id")))
			return
	var q = PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit = get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		stop_route(false)
		target = hit["position"]
		manual_move.emit()
