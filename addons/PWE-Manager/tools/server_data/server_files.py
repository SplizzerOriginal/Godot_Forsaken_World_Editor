#!/usr/bin/env python3
# Kopiert die Map-Dateien, die der Godot-Server je Server-Ordner braucht, aus den entpackten
# Server-Daten (FW_496 server-fw/gamed/config/<Ordner>/) nach Server/data/<Ordner>/ des Plugins:
#   map.bht       Kollision (Brushes, Server/brushes.gd; der Client baut daraus die Gebäude)
#   terrain.cfg   Raster des Terrains (Zeilen / Spalten der Teilkarten, Größe, Höhenbereich)
#   map/<n>.hmap  Höhen je Teilkarte (Server/heightmap.gd), nur die nRow * nCol, die terrain.cfg
#                 nennt (manche Ordner haben übrige Dateien)
#   movemaps/     mit --client: die Wegekarte der Client-Map, die zu diesem Ordner gehört (Server/maps.json; pfmap.cfg,
#                 <Ebene>.prmap / .pdhmap, MAP/angelica_movemap.gd) - der Server setzt damit Spawns in Gelände-Gebieten
#                 wie path_finding::GetValidPos auf die begehbare Ebene (Höhlen- und Stadtböden über dem Gelände, Bug-
#                 Fahrplan B2). Die Wegekarten des Servers (PfMap.cfg, .rmap / .dhmap) haben ein älteres Format.
# Aufruf: python3 server_files.py <config-Ordner> <Server/data> s9 s10 s11 s31 [--client=<Stock-PWE-Client>]
import json
import os
import re
import shutil
import sys


def needed_hmaps(cfg_text):
    rows = int(re.search(r"nRow\s*=\s*(\d+)", cfg_text).group(1))
    cols = int(re.search(r"nCol\s*=\s*(\d+)", cfg_text).group(1))
    return ["%d.hmap" % (i + 1) for i in range(rows * cols)]


def copy_folder(src_root, dst_root, folder):
    src = os.path.join(src_root, folder)
    dst = os.path.join(dst_root, folder)
    if not os.path.isdir(src):
        print("%s: nicht gefunden" % src)
        return 0
    os.makedirs(os.path.join(dst, "map"), exist_ok=True)
    total = 0
    names = ["map.bht", "terrain.cfg"]
    cfg = os.path.join(src, "terrain.cfg")
    if os.path.exists(cfg):
        with open(cfg, encoding="latin-1") as f:
            names += ["map/" + h for h in needed_hmaps(f.read())]
    for name in names:
        s = os.path.join(src, name)
        if not os.path.exists(s):
            print("%s: %s fehlt" % (folder, name))
            continue
        shutil.copyfile(s, os.path.join(dst, name))
        total += os.path.getsize(s)
    print("%s: %s (%.1f MB)" % (folder, ", ".join(names), total / 1e6))
    return total


MOVEMAP_EXT = (".prmap", ".pdhmap")


def copy_movemaps(client_root, dst_root, folder, maps_json):
    with open(maps_json, encoding="utf-8") as f:
        maps = json.load(f)["maps"]
    names = [m for m, src in maps.items() if src and src[0]["folder"] == folder]
    for m in sorted(names):
        src = os.path.join(client_root, "maps", m, "movemaps")
        if not os.path.isdir(src):
            continue
        dst = os.path.join(dst_root, folder, "movemaps")
        os.makedirs(dst, exist_ok=True)
        total = 0
        for name in sorted(os.listdir(src)):
            low = name.lower()
            if low == "pfmap.cfg" or low.endswith(MOVEMAP_EXT):
                shutil.copyfile(os.path.join(src, name), os.path.join(dst, name))
                total += os.path.getsize(os.path.join(src, name))
        print("%s: Wegekarte der Client-Map %s (%.1f MB)" % (folder, m, total / 1e6))
        return total
    print("%s: keine Client-Map mit Wegekarte" % folder)
    return 0


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    if len(args) < 3:
        print(__doc__ or "python3 server_files.py <config-Ordner> <Server/data> <Ordner> ... [--client=<Ordner>]")
        sys.exit(1)
    total = sum(copy_folder(args[0], args[1], f) for f in args[2:])
    if "client" in opts:
        maps_json = os.path.join(os.path.dirname(os.path.abspath(args[1])), "maps.json")
        total += sum(copy_movemaps(opts["client"], args[1], f, maps_json) for f in args[2:])
    print("zusammen %.1f MB" % (total / 1e6))


if __name__ == "__main__":
    main()
