"""The edition's playable region (the Off the Beaten Track edition: the countries its maps cover), the server's side
of the mod's region.lua: the same polygons (regiondata.json, built with regiondata.lua by tools/build_region.py) and
the same rule. The level select's "Random location" picks only towns inside it (randomplace.towns).

    enabled()          -> True when the edition limits where the player can go
    contains(lat, lon) -> True inside one of the countries or within MARGIN_KM of one (always True when not enabled)
    name()             -> the region's name ('' when not enabled)

A polygon is its outer ring then its holes (South Africa's hole is Lesotho, its own polygon): inside one polygon
(even-odd over its rings) is inside the region. No regiondata.json, or no polygons in it: the whole planet is open.
"""
import json
import logging
import math
import os
import sys

log = logging.getLogger("earthd.region")

ROOT = getattr(sys, "_MEIPASS", None) or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "regiondata.json")   # (beside the modules, as
                                                                                     # bridgetypes.DB_PATH: build_app.py)
MARGIN_KM = 5.0     # region.lua's MARGIN_KM: the simplified edge is a little generous, never short
KM_LAT = 111.32

_data = None
_polys = None       # [(rings, (s, w, n, e))], rings: [[lat, lon, ...]]


def _load(data=None):
    global _data, _polys
    if data is None:
        try:
            with open(DATA, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError) as e:
            log.info("region: none (%s: %s): the whole planet is open", type(e).__name__, e)
            data = {"name": "", "countries": [], "polygons": []}
    polys = []
    for p in data.get("polygons", []):
        rings = p.get("rings") or []
        if rings and len(rings[0]) >= 6:
            la, lo = rings[0][0::2], rings[0][1::2]
            polys.append((rings, (min(la), min(lo), max(la), max(lo))))
    _data, _polys = data, polys


def _polygons():
    if _polys is None:
        _load()
    return _polys


def set_data(data=None):
    """Another region (tests); None: back to regiondata.json."""
    _load(data)


def enabled():
    return bool(_polygons())


def name():
    return _data.get("name", "") if enabled() else ""


def countries():
    return list(_data.get("countries", [])) if enabled() else []


def _in_ring(r, lat, lon):
    inside = False
    j_lat, j_lon = r[-2], r[-1]
    for i in range(0, len(r) - 1, 2):
        i_lat, i_lon = r[i], r[i + 1]
        if (i_lat > lat) != (j_lat > lat) and lon < (j_lon - i_lon) * (lat - i_lat) / (j_lat - i_lat) + i_lon:
            inside = not inside
        j_lat, j_lon = i_lat, i_lon
    return inside


def _ring_dist_km(r, lat, lon):
    kx = KM_LAT * math.cos(math.radians(lat))
    best = math.inf
    ax, ay = (r[-1] - lon) * kx, (r[-2] - lat) * KM_LAT
    for i in range(0, len(r) - 1, 2):
        bx, by = (r[i + 1] - lon) * kx, (r[i] - lat) * KM_LAT
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy
        t = max(0.0, min(1.0, -(ax * dx + ay * dy) / L2)) if L2 > 0 else 0.0
        best = min(best, (ax + t * dx) ** 2 + (ay + t * dy) ** 2)
        ax, ay = bx, by
    return math.sqrt(best)


def contains(lat, lon):
    polys = _polygons()
    if not polys:
        return True
    for rings, (s, w, n, e) in polys:
        if s <= lat <= n and w <= lon <= e and sum(_in_ring(r, lat, lon) for r in rings) % 2 == 1:
            return True
    m_lat = MARGIN_KM / KM_LAT
    m_lon = MARGIN_KM / (KM_LAT * max(math.cos(math.radians(lat)), 0.05))
    for rings, (s, w, n, e) in polys:
        if s - m_lat <= lat <= n + m_lat and w - m_lon <= lon <= e + m_lon and \
                _ring_dist_km(rings[0], lat, lon) <= MARGIN_KM:
            return True
    return False
