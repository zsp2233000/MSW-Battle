"""Convert the MOI 1140318 township ZIP into the world-map's compact source data.

Usage: python assets/worldmap/import_boundaries.py <archive.zip>
Requires pyshp and Shapely >= 2.1. Normal asset builds need only Node.
Source: https://data.gov.tw/dataset/7441 (Government Data Open License 1.0).
"""
import io
import json
import sys
import zipfile
from pathlib import Path

import shapefile
from shapely import box, coverage_is_valid, coverage_simplify, union_all
from shapely.geometry import MultiPolygon, shape

# Taiwan-main-island view. Qijin's coastal island is included; Dongsha/Nansha are off-map.
# Crop beyond the painted viewport so the crop edge never looks like a shoreline.
AREA = box(119.98, 22.35, 121.25, 23.62)
STEM = "TOWN_MOI_1140318"


def encode(geometry):
    polygons = [geometry] if geometry.geom_type == "Polygon" else geometry.geoms
    return [
        [[[round(x, 6), round(y, 6)] for x, y in ring.coords[:-1]]
         for ring in [polygon.exterior, *polygon.interiors]]
        for polygon in polygons if polygon.geom_type == "Polygon" and not polygon.is_empty
    ]


def main(archive):
    with zipfile.ZipFile(archive) as source:
        reader = shapefile.Reader(**{ext: io.BytesIO(source.read(f"{STEM}.{ext}"))
                                     for ext in ("shp", "shx", "dbf")})
        districts, land = [], []
        for entry in reader.iterShapeRecords():
            if not AREA.intersects(box(*entry.shape.bbox)):
                continue
            geometry = shape(entry.shape.__geo_interface__)
            if not AREA.intersects(geometry):
                continue
            land.append(geometry.intersection(AREA))
            row = entry.record
            if row.COUNTYCODE == "64000":
                parts = geometry.geoms if geometry.geom_type == "MultiPolygon" else [geometry]
                districts.append((row.TOWNCODE, row.TOWNNAME,
                                  MultiPolygon([part for part in parts if AREA.intersects(part)])))

    districts.sort(key=lambda row: row[0])
    geometries = [row[2] for row in districts]
    if len(districts) != 38 or not coverage_is_valid(geometries):
        raise ValueError("Expected 38 districts with shared, valid boundaries")
    simplified = coverage_simplify(geometries, 0.0006)
    records = [{"code": code, "name": name, "polygons": encode(geometry)}
               for (code, name, _), geometry in zip(districts, simplified)]
    # Keep one district per line, so the data stays compact and its names are reviewable.
    compact = lambda obj: json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    output = '{\n  "land":' + compact(encode(union_all(land).simplify(0.001))) + ',\n  "districts":[\n    '
    output += ',\n    '.join(map(compact, records)) + '\n  ]\n}\n'
    Path(__file__).with_name("kaohsiung_boundaries.json").write_text(output, encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1])
