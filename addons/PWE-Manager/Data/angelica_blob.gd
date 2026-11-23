@tool
extends Resource

# ====================================================
# Umgewandelte Spieldaten als Godot-Ressource (Leiste EXPORT, Performance-Fahrplan P2f3; angelica_store.gd):
#   bytes        Inhalt einer Datei der Spieldaten (Lua, Quest-Teile, Wegekarten, Konfigurationen ...) bzw. einer Liste
#                von elements.data
#   table        Verzeichnis des Speichers, Kopf von elements.data (Listen, IDs je Liste), Quest-Index ...
#   source_size  Größe der Quelldatei beim Umwandeln
# ====================================================

@export var bytes: PackedByteArray
@export var table: Dictionary
@export var source_size: int = 0
