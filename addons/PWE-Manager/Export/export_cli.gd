extends SceneTree

# ====================================================
# "Client Export for Linux" ohne Editor (Tests, Terminal), derselbe Ablauf wie der Knopf der Leiste EXPORT:
#   godot --headless --path <Projekt> -s res://addons/PWE-Manager/Export/export_cli.gd -- [--maps=s9,s31] [--neu]
#         [--ram=12] [--root=res://Stock-PWE-Client] [--ohne-export] [--ohne-aufraeumen] [--ohne-figuren] [--ohne-tabellen] [--ohne-oberflaeche] [--ohne-klaenge]
# Rückgabewert 0 = alles fertig, 1 = ein Schritt fehlgeschlagen.
# ====================================================

const ClientExport = preload("client_export.gd")

var _last = ""


func _initialize() -> void:
	var args = {}
	for a in OS.get_cmdline_user_args():
		var kv = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var ex = ClientExport.new()
	root.add_child(ex)
	ex.line.connect(_on_line)
	ex.progress.connect(_on_progress)
	ex.finished.connect(_on_finished)
	var err = ex.start({
		"root": str(args.get("root", "res://Stock-PWE-Client")),
		"maps": Array(str(args.get("maps", "")).split(",", false)),
		"force": args.has("neu"),
		"ram_gb": float(args.get("ram", "12")),
		"assets": not args.has("ohne-figuren"),
		"tables": not args.has("ohne-tabellen"),
		"ui": not args.has("ohne-oberflaeche"),
		"sounds": not args.has("ohne-klaenge"),
		"cleanup": not args.has("ohne-aufraeumen"),
		"export": not args.has("ohne-export"),
	})
	if err != "":
		print("CLIENT-EXPORT FEHLER ", err)
		quit(1)

func _on_line(text: String) -> void:
	print(text)

# Nur neue Schritte melden (der Fortschritt kommt alle 0,25 s)
func _on_progress(fraction: float, text: String) -> void:
	var s = "%3d %% %s" % [int(fraction * 100.0), text.get_slice(":", 0)]
	if s != _last:
		_last = s
		print(s)

func _on_finished(ok: bool, summary: String) -> void:
	print("CLIENT-EXPORT ", "OK " if ok else "FEHLER ", summary)
	quit(0 if ok else 1)
