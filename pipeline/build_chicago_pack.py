#!/usr/bin/env python3
"""Build the compact, deterministic AIC Chicago beta SQLite pack."""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import sqlite3
import tempfile
import time
from typing import Any, Iterable, Iterator, Sequence
import urllib.error
import urllib.parse
import urllib.request


CRIME_DATASET_ID = "ijzp-q8t2"
BOUNDARY_DATASET_ID = "igwz-8jzy"
IUCR_DATASET_ID = "c7ck-438e"
SOCRATA_DOMAIN = "https://data.cityofchicago.org"
CRIME_RESOURCE_URL = f"{SOCRATA_DOMAIN}/resource/{CRIME_DATASET_ID}.json"
BOUNDARY_RESOURCE_URL = f"{SOCRATA_DOMAIN}/resource/{BOUNDARY_DATASET_ID}.json"
IUCR_RESOURCE_URL = f"{SOCRATA_DOMAIN}/resource/{IUCR_DATASET_ID}.json"
CRIME_SOURCE_URL = f"{SOCRATA_DOMAIN}/d/{CRIME_DATASET_ID}"
BOUNDARY_SOURCE_URL = f"{SOCRATA_DOMAIN}/d/{BOUNDARY_DATASET_ID}"
IUCR_SOURCE_URL = f"{SOCRATA_DOMAIN}/d/{IUCR_DATASET_ID}"
DISCLAIMER = (
    "Cooked Score is a historical data index that compares reported-incident "
    "concentration around this location with eligible Chicago comparison locations. "
    "It is not a live safety assessment or personal-risk prediction."
)
SOURCE_LIMITATION = (
    "Chicago Police Department data reflects reported incidents, is preliminary, "
    "may be revised, may contain errors or omissions, and does not capture "
    "unreported incidents. Source-map locations are approximate."
)
CATEGORY_BY_PRIMARY = {
    "ASSAULT": "assault_battery",
    "BATTERY": "assault_battery",
    "ROBBERY": "robbery",
    "THEFT": "theft",
    "MOTOR VEHICLE THEFT": "motor_vehicle_theft",
}
CATEGORY_ORDER = (
    "assault_battery",
    "robbery",
    "theft",
    "motor_vehicle_theft",
)
ALLOWED_CATEGORIES = CATEGORY_ORDER
SCHEMA_VERSION = 3
# The source is released as a complete monthly snapshot. A pack remains marked
# fresh for 38 days after its source-through date, leaving one week after a
# typical month-end refresh, and scans fail closed at that boundary. The 60-day
# expiry is a hard distribution and cleanup limit for the already-disabled pack.
FRESH_UNTIL_DAYS_AFTER_SOURCE_THROUGH = 38
EXPIRES_AT_DAYS_AFTER_SOURCE_THROUGH = 60
PACK_FILENAME = "chicago_beta.sqlite"
MANIFEST_FILENAME = "chicago_beta.manifest.json"
COMPRESSED_FILENAME = f"{PACK_FILENAME}.gz"
CHECKSUM_FILENAME = "chicago_beta.checksums.sha256"
PARITY_FILENAME = "chicago_beta.parity.json"
EARTH_RADIUS_M = 6_371_008.8
GRID_ANCHOR_LAT = 41.60
GRID_ANCHOR_LON = -87.95
QUERY_NODE_SPACING_M = 100.0
REFERENCE_SPACING_M = 500.0
AGGREGATE_CELL_SIZE_M = 250.0
AGGREGATE_BAND_SIZE = 5
SCAN_COORDINATE_SNAP_M = 1.0
OVERLAP_SUBCELLS_PER_AXIS = 10
OVERLAP_SUBCELL_SIZE_M = AGGREGATE_CELL_SIZE_M / OVERLAP_SUBCELLS_PER_AXIS
DECIMETERS_PER_METER = 10
CELL_SIZE_DM = int(AGGREGATE_CELL_SIZE_M * DECIMETERS_PER_METER)
RADIUS_DM = 500 * DECIMETERS_PER_METER
SUBCELL_SIZE_DM = int(OVERLAP_SUBCELL_SIZE_M * DECIMETERS_PER_METER)
SUBCELL_CENTER_OFFSET_DM = SUBCELL_SIZE_DM // 2
OVERLAP_SAMPLE_COUNT = OVERLAP_SUBCELLS_PER_AXIS**2
MAX_JSON_RESPONSE_BYTES = 64 * 1024 * 1024
MAX_INCIDENT_RECORDS = 1_000_000
MAX_INCIDENT_PAGES = 20
EXPECTED_COMMUNITY_AREA_IDS = frozenset(range(1, 78))
MAX_BOUNDARY_POINTS = 250_000
MAX_BOUNDARY_RINGS = 2_000
MAX_CITY_GRID_CELLS = 1_000_000
CHICAGO_LATITUDE_RANGE = (41.5, 42.1)
CHICAGO_LONGITUDE_RANGE = (-88.0, -87.4)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_reproducible_gzip(source: Path, destination: Path) -> None:
    with source.open("rb") as input_handle, destination.open("wb") as raw_output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw_output, mtime=0, compresslevel=9) as output:
            for chunk in iter(lambda: input_handle.read(1024 * 1024), b""):
                output.write(chunk)


def request_json(url: str, params: dict[str, str] | None = None, retries: int = 4) -> Any:
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json",
            "User-Agent": "AIC-Chicago-Pack/1.0 (local beta build)",
        },
    )
    last_error: Exception | None = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                payload = response.read(MAX_JSON_RESPONSE_BYTES + 1)
                if len(payload) > MAX_JSON_RESPONSE_BYTES:
                    raise RuntimeError(
                        f"JSON response exceeds {MAX_JSON_RESPONSE_BYTES} bytes: {url}"
                    )
                return json.loads(payload)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            last_error = error
            if attempt + 1 < retries:
                time.sleep(2**attempt)
    raise RuntimeError(f"request failed after {retries} attempts: {url}: {last_error}")


def parse_socrata_date(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def first_day_of_month(value: dt.datetime | dt.date) -> dt.date:
    return dt.date(value.year, value.month, 1)


def shift_months(value: dt.date, months: int) -> dt.date:
    month_index = value.year * 12 + (value.month - 1) + months
    return dt.date(month_index // 12, month_index % 12 + 1, 1)


def derive_freshness_dates(source_through_date: str) -> tuple[str, str]:
    try:
        source_through = dt.date.fromisoformat(source_through_date)
    except (TypeError, ValueError) as error:
        raise RuntimeError("source_through_date must use YYYY-MM-DD") from error
    if source_through.isoformat() != source_through_date:
        raise RuntimeError("source_through_date must use canonical YYYY-MM-DD")
    fresh_until = source_through + dt.timedelta(days=FRESH_UNTIL_DAYS_AFTER_SOURCE_THROUGH)
    expires_at = source_through + dt.timedelta(days=EXPIRES_AT_DAYS_AFTER_SOURCE_THROUGH)
    return fresh_until.isoformat(), expires_at.isoformat()


def validate_freshness_metadata(metadata: dict[str, str]) -> tuple[str, str]:
    source_through = metadata.get("source_through_date")
    fresh_until = metadata.get("fresh_until_date")
    expires_at = metadata.get("expires_at_date")
    if not source_through or not fresh_until or not expires_at:
        raise RuntimeError(
            "source_through_date, fresh_until_date, and expires_at_date are required"
        )
    expected_fresh_until, expected_expires_at = derive_freshness_dates(source_through)
    if fresh_until != expected_fresh_until or expires_at != expected_expires_at:
        raise RuntimeError(
            "freshness dates do not match the documented source-through policy"
        )
    return fresh_until, expires_at


def derive_period(max_source_date: str, months: int) -> tuple[dt.date, dt.date]:
    if months < 1:
        raise ValueError("months must be positive")
    end_exclusive = first_day_of_month(parse_socrata_date(max_source_date))
    return shift_months(end_exclusive, -months), end_exclusive


def derive_pinned_period(
    max_source_date: str,
    requested_period_end: str,
    months: int,
) -> tuple[dt.date, dt.date]:
    if months < 1:
        raise ValueError("months must be positive")
    try:
        end_exclusive = dt.date.fromisoformat(requested_period_end)
    except (TypeError, ValueError) as error:
        raise ValueError("--period-end must use YYYY-MM-DD") from error
    if end_exclusive.isoformat() != requested_period_end or end_exclusive.day != 1:
        raise ValueError("--period-end must be the first day of a month in YYYY-MM-DD format")

    max_observed_date = parse_socrata_date(max_source_date).date()
    latest_complete_end_exclusive = first_day_of_month(max_observed_date)
    if end_exclusive > latest_complete_end_exclusive:
        raise ValueError(
            f"--period-end {requested_period_end} would include an incomplete or "
            f"unobserved month; latest allowed value is "
            f"{latest_complete_end_exclusive.isoformat()} based on observed source "
            f"maximum {max_observed_date.isoformat()}"
        )
    return shift_months(end_exclusive, -months), end_exclusive


def load_frozen_iucr_mapping(path: Path) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("schema_version") != 1:
        raise RuntimeError("unsupported frozen IUCR mapping schema")
    mapping: dict[str, dict[str, Any]] = {}
    for entry in document.get("codes", []):
        code = str(entry.get("iucr", ""))
        if len(code) != 4 or code in mapping:
            raise RuntimeError(f"invalid or duplicate frozen IUCR code: {code!r}")
        if entry.get("category") not in ALLOWED_CATEGORIES:
            raise RuntimeError(f"invalid category for frozen IUCR {code}")
        expected_category = CATEGORY_BY_PRIMARY.get(str(entry.get("official_primary_description")))
        if entry.get("category") != expected_category:
            raise RuntimeError(f"frozen IUCR {code} is not mutually consistent with its official primary type")
        mapping[code] = entry
    if not mapping:
        raise RuntimeError("frozen IUCR mapping is empty")
    return mapping, document


def iucr_where(iucr_codes: Iterable[str]) -> str:
    quoted = ",".join(f"'{value}'" for value in sorted(iucr_codes))
    return f"iucr IN ({quoted})"


def primary_type_where(primary_types: Iterable[str]) -> str:
    quoted = ",".join(f"'{value}'" for value in sorted(primary_types))
    return f"primary_type IN ({quoted})"


def period_where(start: dt.date, end_exclusive: dt.date) -> str:
    return (
        f"date >= '{start.isoformat()}T00:00:00' AND "
        f"date < '{end_exclusive.isoformat()}T00:00:00'"
    )


def discover_max_date(iucr_codes: Iterable[str]) -> str:
    rows = request_json(
        CRIME_RESOURCE_URL,
        {"$select": "max(date) AS max_date", "$where": iucr_where(iucr_codes)},
    )
    if not rows or not rows[0].get("max_date"):
        raise RuntimeError("official crime dataset did not return a maximum date")
    return str(rows[0]["max_date"])


def fetch_dataset_metadata(dataset_id: str) -> dict[str, Any]:
    data = request_json(f"{SOCRATA_DOMAIN}/api/views/{dataset_id}")
    return {
        "id": data.get("id"),
        "name": data.get("name"),
        "description": data.get("description"),
        "rows_updated_at_epoch": data.get("rowsUpdatedAt"),
        "metadata": data.get("metadata", {}).get("custom_fields", {}).get("Metadata", {}),
    }


def count_query(where: str) -> int:
    rows = request_json(
        CRIME_RESOURCE_URL,
        {"$select": "count(*) AS n", "$where": where},
    )
    return int(rows[0]["n"])


def iucr_count_query(where: str) -> list[dict[str, Any]]:
    rows = request_json(
        CRIME_RESOURCE_URL,
        {
            "$select": "iucr,primary_type,count(*) AS n",
            "$where": where,
            "$group": "iucr,primary_type",
            "$order": "iucr,primary_type",
            "$limit": "5000",
        },
    )
    return [
        {"iucr": str(row["iucr"]), "primary_type": str(row["primary_type"]), "count": int(row["n"])}
        for row in rows
    ]


def normalized_display_name(name: str) -> str:
    return name.title().replace("Mckinley", "McKinley")


def download_incident_snapshot(
    destination: Path,
    start: dt.date,
    end_exclusive: dt.date,
    iucr_codes: Iterable[str],
    refresh: bool,
) -> tuple[list[dict[str, Any]], str]:
    where = f"{period_where(start, end_exclusive)} AND {iucr_where(iucr_codes)} AND latitude IS NOT NULL AND longitude IS NOT NULL"
    query = "$select=id,date,iucr,primary_type,latitude,longitude&$where=" + where + "&$order=id"
    if destination.exists() and not refresh:
        records: list[dict[str, Any]] = []
        with gzip.open(destination, "rt", encoding="utf-8") as handle:
            for line in handle:
                records.append(json.loads(line))
        return records, query

    records = []
    offset = 0
    limit = 50_000
    previous_page_signature: tuple[str, str] | None = None
    page_count = 0
    while True:
        page = request_json(
            CRIME_RESOURCE_URL,
            {
                "$select": "id,date,iucr,primary_type,latitude,longitude",
                "$where": where,
                "$order": "id",
                "$limit": str(limit),
                "$offset": str(offset),
            },
        )
        if not isinstance(page, list):
            raise RuntimeError("official crime dataset returned a non-list page")
        page_count += 1
        if page_count > MAX_INCIDENT_PAGES:
            raise RuntimeError(f"incident download exceeded {MAX_INCIDENT_PAGES} pages")
        if page:
            first_id = str(page[0].get("id", ""))
            last_id = str(page[-1].get("id", ""))
            if not first_id or not last_id:
                raise RuntimeError("incident page omits ordered source IDs")
            signature = (first_id, last_id)
            if signature == previous_page_signature:
                raise RuntimeError("incident pagination made no progress")
            previous_page_signature = signature
        if len(records) + len(page) > MAX_INCIDENT_RECORDS:
            raise RuntimeError(
                f"incident download exceeds {MAX_INCIDENT_RECORDS} records"
            )
        records.extend(page)
        if len(page) < limit:
            break
        offset += limit

    records.sort(key=lambda record: int(record["id"]))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as raw_output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw_output, mtime=0, compresslevel=9) as zipped:
            for record in records:
                zipped.write((canonical_json(record) + "\n").encode("utf-8"))
    return records, query


def download_boundaries(destination: Path, refresh: bool) -> list[dict[str, Any]]:
    if destination.exists() and not refresh:
        with gzip.open(destination, "rt", encoding="utf-8") as handle:
            return json.load(handle)
    rows = request_json(
        BOUNDARY_RESOURCE_URL,
        {
            "$select": "area_numbe,community,the_geom",
            "$order": "area_numbe",
            "$limit": "100",
        },
    )
    rows.sort(key=lambda row: int(float(row["area_numbe"])))
    destination.parent.mkdir(parents=True, exist_ok=True)
    payload = canonical_json(rows).encode("utf-8")
    with destination.open("wb") as raw_output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw_output, mtime=0, compresslevel=9) as zipped:
            zipped.write(payload)
    return rows


def download_official_iucr_source(destination: Path, refresh: bool) -> tuple[list[dict[str, Any]], str]:
    selected_primary = ",".join(f"'{value}'" for value in sorted(CATEGORY_BY_PRIMARY))
    where = f"primary_description IN ({selected_primary})"
    query = (
        "$select=iucr,primary_description,secondary_description,index_code,active"
        f"&$where={where}&$order=primary_description,iucr&$limit=5000"
    )
    if destination.exists() and not refresh:
        with gzip.open(destination, "rt", encoding="utf-8") as handle:
            return json.load(handle), query
    rows = request_json(
        IUCR_RESOURCE_URL,
        {
            "$select": "iucr,primary_description,secondary_description,index_code,active",
            "$where": where,
            "$order": "primary_description,iucr",
            "$limit": "5000",
        },
    )
    rows.sort(key=lambda row: str(row["iucr"]))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as raw_output:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw_output, mtime=0, compresslevel=9) as zipped:
            zipped.write(canonical_json(rows).encode("utf-8"))
    return rows, query


def validate_frozen_iucr_mapping(
    mapping: dict[str, dict[str, Any]],
    official_rows: Sequence[dict[str, Any]],
) -> None:
    official: dict[str, dict[str, Any]] = {}
    for row in official_rows:
        code = str(row.get("iucr", ""))
        if code in official:
            raise RuntimeError(f"official IUCR source contains duplicate selected code {code}")
        official[code] = row
    if set(mapping) != set(official):
        missing = sorted(set(official) - set(mapping))
        removed = sorted(set(mapping) - set(official))
        raise RuntimeError(
            f"frozen IUCR set differs from official source; review required; new={missing}, absent={removed}"
        )
    for code, frozen in mapping.items():
        current = official[code]
        checks = {
            "official_primary_description": str(current.get("primary_description", "")),
            "official_secondary_description": str(current.get("secondary_description", "")),
            "index_code": str(current.get("index_code", "")),
            "active": bool(current.get("active", False)),
        }
        for field, current_value in checks.items():
            if frozen.get(field) != current_value:
                raise RuntimeError(
                    f"official IUCR {code} changed {field}: frozen={frozen.get(field)!r}, current={current_value!r}"
                )


def validated_polygon_rings(
    geometry: dict[str, Any],
) -> list[Sequence[Sequence[float]]]:
    if not isinstance(geometry, dict):
        raise ValueError("geometry must be an object")
    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates")
    if geometry_type == "Polygon":
        polygons = [coordinates]
    elif geometry_type == "MultiPolygon":
        polygons = coordinates
    else:
        raise ValueError(f"unsupported geometry type: {geometry_type!r}")
    if not isinstance(polygons, list) or not polygons:
        raise ValueError("geometry contains no polygons")

    rings: list[Sequence[Sequence[float]]] = []
    point_count = 0
    for polygon in polygons:
        if not isinstance(polygon, list) or not polygon:
            raise ValueError("geometry contains an empty polygon")
        for ring in polygon:
            if not isinstance(ring, list) or len(ring) < 4:
                raise ValueError("geometry ring must contain at least four points")
            point_count += len(ring)
            if len(rings) + 1 > MAX_BOUNDARY_RINGS or point_count > MAX_BOUNDARY_POINTS:
                raise ValueError("geometry exceeds boundary complexity limits")
            for point in ring:
                if not isinstance(point, list) or len(point) < 2:
                    raise ValueError("geometry point must contain longitude and latitude")
                longitude = float(point[0])
                latitude = float(point[1])
                if not math.isfinite(longitude) or not math.isfinite(latitude):
                    raise ValueError("geometry coordinates must be finite")
                if not CHICAGO_LONGITUDE_RANGE[0] <= longitude <= CHICAGO_LONGITUDE_RANGE[1]:
                    raise ValueError("geometry longitude is outside the Chicago envelope")
                if not CHICAGO_LATITUDE_RANGE[0] <= latitude <= CHICAGO_LATITUDE_RANGE[1]:
                    raise ValueError("geometry latitude is outside the Chicago envelope")
            if ring[0][:2] != ring[-1][:2]:
                raise ValueError("geometry ring must be closed")
            rings.append(ring)
    return rings


def iter_points(geometry: dict[str, Any]) -> Iterator[tuple[float, float]]:
    for ring in validated_polygon_rings(geometry):
        for point in ring:
            yield float(point[0]), float(point[1])


def geometry_bbox(geometry: dict[str, Any]) -> tuple[float, float, float, float]:
    points = list(iter_points(geometry))
    if not points:
        raise ValueError("empty geometry")
    longitudes = [point[0] for point in points]
    latitudes = [point[1] for point in points]
    return min(latitudes), max(latitudes), min(longitudes), max(longitudes)


def point_in_ring(longitude: float, latitude: float, ring: Sequence[Sequence[float]]) -> bool:
    inside = False
    previous = ring[-1]
    for current in ring:
        x1, y1 = float(previous[0]), float(previous[1])
        x2, y2 = float(current[0]), float(current[1])
        intersects = ((y1 > latitude) != (y2 > latitude)) and (
            longitude < (x2 - x1) * (latitude - y1) / ((y2 - y1) or 1e-300) + x1
        )
        if intersects:
            inside = not inside
        previous = current
    return inside


def point_in_geometry(longitude: float, latitude: float, geometry: dict[str, Any]) -> bool:
    coordinates = geometry.get("coordinates", [])
    polygons = [coordinates] if geometry.get("type") == "Polygon" else coordinates
    for polygon in polygons:
        if not polygon or not point_in_ring(longitude, latitude, polygon[0]):
            continue
        if any(point_in_ring(longitude, latitude, hole) for hole in polygon[1:]):
            continue
        return True
    return False


def polygon_centroid(ring: Sequence[Sequence[float]]) -> tuple[float, float, float]:
    area_twice = 0.0
    longitude_sum = 0.0
    latitude_sum = 0.0
    for index in range(len(ring) - 1):
        x1, y1 = float(ring[index][0]), float(ring[index][1])
        x2, y2 = float(ring[index + 1][0]), float(ring[index + 1][1])
        cross = x1 * y2 - x2 * y1
        area_twice += cross
        longitude_sum += (x1 + x2) * cross
        latitude_sum += (y1 + y2) * cross
    if abs(area_twice) < 1e-18:
        points = [(float(point[0]), float(point[1])) for point in ring]
        return (
            sum(point[0] for point in points) / len(points),
            sum(point[1] for point in points) / len(points),
            0.0,
        )
    return longitude_sum / (3.0 * area_twice), latitude_sum / (3.0 * area_twice), abs(area_twice / 2.0)


def geometry_centroid(geometry: dict[str, Any]) -> tuple[float, float]:
    coordinates = geometry.get("coordinates", [])
    polygons = [coordinates] if geometry.get("type") == "Polygon" else coordinates
    candidates: list[tuple[float, float, float]] = []
    for polygon in polygons:
        if polygon:
            candidates.append(polygon_centroid(polygon[0]))
    if not candidates:
        raise ValueError("empty geometry")
    total_area = sum(candidate[2] for candidate in candidates)
    if total_area:
        longitude = sum(candidate[0] * candidate[2] for candidate in candidates) / total_area
        latitude = sum(candidate[1] * candidate[2] for candidate in candidates) / total_area
    else:
        longitude, latitude = candidates[0][0], candidates[0][1]
    if point_in_geometry(longitude, latitude, geometry):
        return latitude, longitude
    largest = max(candidates, key=lambda candidate: candidate[2])
    if point_in_geometry(largest[0], largest[1], geometry):
        return largest[1], largest[0]
    min_lat, max_lat, min_lon, max_lon = geometry_bbox(geometry)
    # Concave or disjoint community areas can have a mathematical centroid
    # outside the geometry. Pick the closest deterministic interior point from
    # a dense bbox lattice so the fallback label point remains truthful.
    target_lon, target_lat = longitude, latitude
    interior: list[tuple[float, float, float]] = []
    divisions = 40
    for row in range(1, divisions):
        candidate_lat = min_lat + (max_lat - min_lat) * row / divisions
        for column in range(1, divisions):
            candidate_lon = min_lon + (max_lon - min_lon) * column / divisions
            if point_in_geometry(candidate_lon, candidate_lat, geometry):
                distance_squared = (candidate_lon - target_lon) ** 2 + (candidate_lat - target_lat) ** 2
                interior.append((distance_squared, candidate_lat, candidate_lon))
    if not interior:
        raise ValueError("could not find an interior representative point")
    _, representative_lat, representative_lon = min(interior)
    return representative_lat, representative_lon


def prepare_neighborhoods(rows: Sequence[dict[str, Any]]) -> list[dict[str, Any]]:
    neighborhoods = []
    seen_ids: set[int] = set()
    for row in rows:
        neighborhood_id = int(float(row["area_numbe"]))
        if neighborhood_id not in EXPECTED_COMMUNITY_AREA_IDS or neighborhood_id in seen_ids:
            raise ValueError(f"invalid or duplicate community area ID: {neighborhood_id}")
        seen_ids.add(neighborhood_id)
        geometry = row["the_geom"]
        min_lat, max_lat, min_lon, max_lon = geometry_bbox(geometry)
        centroid_lat, centroid_lon = geometry_centroid(geometry)
        neighborhoods.append(
            {
                "id": neighborhood_id,
                "name": normalized_display_name(str(row["community"])),
                "geometry": geometry,
                "min_lat": min_lat,
                "max_lat": max_lat,
                "min_lon": min_lon,
                "max_lon": max_lon,
                "centroid_lat": centroid_lat,
                "centroid_lon": centroid_lon,
            }
        )
    neighborhoods.sort(key=lambda item: item["id"])
    if seen_ids != EXPECTED_COMMUNITY_AREA_IDS:
        raise ValueError("community area IDs must be exactly 1 through 77")
    return neighborhoods


def containing_neighborhood(
    longitude: float,
    latitude: float,
    neighborhoods: Sequence[dict[str, Any]],
) -> dict[str, Any] | None:
    for neighborhood in neighborhoods:
        if not (
            neighborhood["min_lat"] <= latitude <= neighborhood["max_lat"]
            and neighborhood["min_lon"] <= longitude <= neighborhood["max_lon"]
        ):
            continue
        if point_in_geometry(longitude, latitude, neighborhood["geometry"]):
            return neighborhood
    return None


def local_xy(latitude: float, longitude: float) -> tuple[float, float]:
    x = math.radians(longitude - GRID_ANCHOR_LON) * EARTH_RADIUS_M * math.cos(math.radians(GRID_ANCHOR_LAT))
    y = math.radians(latitude - GRID_ANCHOR_LAT) * EARTH_RADIUS_M
    return x, y


def local_latlon(x: float, y: float) -> tuple[float, float]:
    latitude = GRID_ANCHOR_LAT + math.degrees(y / EARTH_RADIUS_M)
    longitude = GRID_ANCHOR_LON + math.degrees(x / (EARTH_RADIUS_M * math.cos(math.radians(GRID_ANCHOR_LAT))))
    return latitude, longitude


def destination_point(latitude: float, longitude: float, distance_m: float, bearing_radians: float) -> tuple[float, float]:
    angular = distance_m / EARTH_RADIUS_M
    lat1 = math.radians(latitude)
    lon1 = math.radians(longitude)
    lat2 = math.asin(
        math.sin(lat1) * math.cos(angular)
        + math.cos(lat1) * math.sin(angular) * math.cos(bearing_radians)
    )
    lon2 = lon1 + math.atan2(
        math.sin(bearing_radians) * math.sin(angular) * math.cos(lat1),
        math.cos(angular) - math.sin(lat1) * math.sin(lat2),
    )
    return math.degrees(lat2), math.degrees(lon2)


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    lat1_r, lat2_r = math.radians(lat1), math.radians(lat2)
    delta_lat = lat2_r - lat1_r
    delta_lon = math.radians(lon2 - lon1)
    hav = math.sin(delta_lat / 2) ** 2 + math.cos(lat1_r) * math.cos(lat2_r) * math.sin(delta_lon / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(min(1.0, math.sqrt(hav)))


def generate_city_grid(
    neighborhoods: Sequence[dict[str, Any]],
    spacing_m: float,
) -> dict[tuple[int, int], dict[str, Any]]:
    min_lat = min(item["min_lat"] for item in neighborhoods)
    max_lat = max(item["max_lat"] for item in neighborhoods)
    min_lon = min(item["min_lon"] for item in neighborhoods)
    max_lon = max(item["max_lon"] for item in neighborhoods)
    min_x, min_y = local_xy(min_lat, min_lon)
    max_x, max_y = local_xy(max_lat, max_lon)
    col_min = math.floor(min_x / spacing_m)
    col_max = math.ceil(max_x / spacing_m)
    row_min = math.floor(min_y / spacing_m)
    row_max = math.ceil(max_y / spacing_m)
    candidate_cell_count = (row_max - row_min + 1) * (col_max - col_min + 1)
    if candidate_cell_count > MAX_CITY_GRID_CELLS:
        raise ValueError(
            f"city grid exceeds {MAX_CITY_GRID_CELLS} candidate cells"
        )

    points: dict[tuple[int, int], dict[str, Any]] = {}
    for row in range(row_min, row_max + 1):
        for column in range(col_min, col_max + 1):
            latitude, longitude = local_latlon(column * spacing_m, row * spacing_m)
            neighborhood = containing_neighborhood(longitude, latitude, neighborhoods)
            if neighborhood is None:
                continue
            points[(row, column)] = {
                "grid_row": row,
                "grid_column": column,
                "latitude": latitude,
                "longitude": longitude,
                "community_area_number": int(neighborhood["id"]),
                "community_area": str(neighborhood["name"]),
            }
    return points


def generate_eligible_query_nodes(
    neighborhoods: Sequence[dict[str, Any]],
    spacing_m: float,
    radius_m: float,
) -> tuple[list[dict[str, Any]], int, int]:
    city_grid = generate_city_grid(neighborhoods, spacing_m)
    radius_steps = math.ceil(radius_m / spacing_m)
    disk_offsets = [
        (row_offset, column_offset)
        for row_offset in range(-radius_steps, radius_steps + 1)
        for column_offset in range(-radius_steps, radius_steps + 1)
        if math.hypot(row_offset * spacing_m, column_offset * spacing_m) <= radius_m + 1e-9
    ]
    eligible = [
        point
        for key, point in sorted(city_grid.items())
        if all((key[0] + row_offset, key[1] + column_offset) in city_grid for row_offset, column_offset in disk_offsets)
    ]
    return eligible, len(city_grid), len(disk_offsets)


def select_reference_nodes(
    query_nodes: Sequence[dict[str, Any]],
    query_spacing_m: float,
    reference_spacing_m: float,
) -> list[dict[str, Any]]:
    ratio = reference_spacing_m / query_spacing_m
    factor = round(ratio)
    if factor < 1 or not math.isclose(ratio, factor, rel_tol=0, abs_tol=1e-9):
        raise ValueError("reference spacing must be an integer multiple of query-node spacing")
    return [
        node
        for node in query_nodes
        if int(node["grid_row"]) % factor == 0 and int(node["grid_column"]) % factor == 0
    ]


def build_spatial_hash(
    incidents: Sequence[dict[str, Any]],
    iucr_mapping: dict[str, dict[str, Any]],
    cell_size_m: float,
) -> dict[tuple[int, int], list[tuple[float, float, str]]]:
    spatial: dict[tuple[int, int], list[tuple[float, float, str]]] = collections.defaultdict(list)
    for incident in incidents:
        x, y = local_xy(float(incident["latitude"]), float(incident["longitude"]))
        spatial[(math.floor(x / cell_size_m), math.floor(y / cell_size_m))].append(
            (
                float(incident["latitude"]),
                float(incident["longitude"]),
                str(iucr_mapping[str(incident["iucr"])]["category"]),
            )
        )
    return spatial


def count_nearby(
    latitude: float,
    longitude: float,
    spatial: dict[tuple[int, int], list[tuple[float, float, str]]],
    radius_m: float,
) -> dict[str, int]:
    x, y = local_xy(latitude, longitude)
    cell_size = radius_m
    center_col, center_row = math.floor(x / cell_size), math.floor(y / cell_size)
    counts = {category: 0 for category in ALLOWED_CATEGORIES}
    for column in range(center_col - 1, center_col + 2):
        for row in range(center_row - 1, center_row + 2):
            for incident_lat, incident_lon, category in spatial.get((column, row), []):
                if haversine_m(latitude, longitude, incident_lat, incident_lon) <= radius_m:
                    counts[category] += 1
    return counts


def attach_node_counts(
    nodes: Sequence[dict[str, Any]],
    incidents: Sequence[dict[str, Any]],
    iucr_mapping: dict[str, dict[str, Any]],
    radius_m: float,
) -> None:
    spatial = build_spatial_hash(incidents, iucr_mapping, radius_m)
    for node in nodes:
        counts = count_nearby(node["latitude"], node["longitude"], spatial, radius_m)
        for category in ALLOWED_CATEGORIES:
            node[f"{category}_count"] = counts[category]
        node["total_count"] = sum(counts.values())


def round_half_away_from_zero(value: float) -> int:
    if value >= 0:
        return math.floor(value + 0.5)
    return math.ceil(value - 0.5)


def quantize_to_nearest_five(value: int) -> int:
    if value < 0:
        raise ValueError("aggregate values cannot be negative")
    return AGGREGATE_BAND_SIZE * math.floor(value / AGGREGATE_BAND_SIZE + 0.5)


def aggregate_cell_key(latitude: float, longitude: float) -> tuple[int, int]:
    x, y = local_xy(latitude, longitude)
    return math.floor(y / AGGREGATE_CELL_SIZE_M), math.floor(x / AGGREGATE_CELL_SIZE_M)


def aggregate_cell_bounds(
    neighborhoods: Sequence[dict[str, Any]],
) -> tuple[int, int, int, int]:
    projected = [
        local_xy(latitude, longitude)
        for neighborhood in neighborhoods
        for longitude, latitude in iter_points(neighborhood["geometry"])
    ]
    min_x = min(point[0] for point in projected)
    max_x = max(point[0] for point in projected)
    min_y = min(point[1] for point in projected)
    max_y = max(point[1] for point in projected)
    return (
        math.floor(min_y / AGGREGATE_CELL_SIZE_M),
        math.floor(max_y / AGGREGATE_CELL_SIZE_M),
        math.floor(min_x / AGGREGATE_CELL_SIZE_M),
        math.floor(max_x / AGGREGATE_CELL_SIZE_M),
    )


def build_aggregate_cells(
    incidents: Sequence[dict[str, Any]],
    iucr_mapping: dict[str, dict[str, Any]],
    neighborhoods: Sequence[dict[str, Any]],
) -> tuple[
    dict[tuple[int, int], tuple[int, int, int, int]],
    dict[tuple[int, int], tuple[int, int, int, int]],
    dict[str, Any],
    list[dict[str, Any]],
]:
    row_min, row_max, column_min, column_max = aggregate_cell_bounds(neighborhoods)
    category_index = {category: index for index, category in enumerate(ALLOWED_CATEGORIES)}
    raw: dict[tuple[int, int], list[int]] = {
        (row, column): [0] * len(ALLOWED_CATEGORIES)
        for row in range(row_min, row_max + 1)
        for column in range(column_min, column_max + 1)
    }
    outside_city: collections.Counter[str] = collections.Counter()
    used = 0
    usable_records: list[dict[str, Any]] = []
    for incident in incidents:
        latitude = float(incident["latitude"])
        longitude = float(incident["longitude"])
        category = str(iucr_mapping[str(incident["iucr"])]["category"])
        if containing_neighborhood(longitude, latitude, neighborhoods) is None:
            outside_city[category] += 1
            continue
        key = aggregate_cell_key(latitude, longitude)
        if key not in raw:
            raise RuntimeError(f"inside-city incident mapped outside fixed aggregate domain: {key}")
        raw[key][category_index[category]] += 1
        used += 1
        usable_records.append(incident)

    raw_frozen = {key: tuple(values) for key, values in raw.items()}
    bands = {
        key: tuple(quantize_to_nearest_five(value) for value in values)
        for key, values in raw_frozen.items()
    }
    positive_band_minimums: dict[str, int | None] = {}
    low_count_profile: dict[str, dict[str, int]] = {}
    for index, category in enumerate(ALLOWED_CATEGORIES):
        raw_values = [values[index] for values in raw_frozen.values()]
        band_values = [values[index] for values in bands.values()]
        positives = [raw_value for raw_value, band_value in zip(raw_values, band_values) if band_value > 0]
        positive_band_minimums[category] = min(positives) if positives else None
        low_count_profile[category] = {
            "zero_cells": sum(value == 0 for value in raw_values),
            "singleton_cells": sum(value == 1 for value in raw_values),
            "two_incident_cells": sum(value == 2 for value in raw_values),
            "three_to_four_incident_cells": sum(3 <= value <= 4 for value in raw_values),
            "positive_released_cells": sum(value > 0 for value in band_values),
        }
    disclosure = {
        "aggregate_domain": {
            "row_min": row_min,
            "row_max": row_max,
            "column_min": column_min,
            "column_max": column_max,
            "cells": len(raw_frozen),
        },
        "usable_source_rows": used,
        "outside_city_coordinates_excluded": sum(outside_city.values()),
        "outside_city_by_category": dict(sorted(outside_city.items())),
        "event_influence_max_cells": 1,
        "event_influence_max_categories": 1,
        "subcell_position_used_in_release": False,
        "zero_band_true_range": "0-2 incidents per category and cell",
        "five_band_true_range": "3-7 incidents per category and cell",
        "positive_band_minimum_raw_count": positive_band_minimums,
        "low_count_profile": low_count_profile,
        "exact_or_residual_total_released": False,
    }
    return raw_frozen, bands, disclosure, usable_records


def overlap_weights_for_snapped_dm(
    center_x_dm: int,
    center_y_dm: int,
) -> list[tuple[int, int, int]]:
    column_min = (center_x_dm - RADIUS_DM) // CELL_SIZE_DM
    column_max = (center_x_dm + RADIUS_DM) // CELL_SIZE_DM
    row_min = (center_y_dm - RADIUS_DM) // CELL_SIZE_DM
    row_max = (center_y_dm + RADIUS_DM) // CELL_SIZE_DM
    weights: list[tuple[int, int, int]] = []
    radius_squared = RADIUS_DM**2
    for row in range(row_min, row_max + 1):
        for column in range(column_min, column_max + 1):
            hits = 0
            cell_x = column * CELL_SIZE_DM
            cell_y = row * CELL_SIZE_DM
            for subcell_row in range(OVERLAP_SUBCELLS_PER_AXIS):
                sample_y = cell_y + SUBCELL_CENTER_OFFSET_DM + subcell_row * SUBCELL_SIZE_DM
                delta_y = sample_y - center_y_dm
                for subcell_column in range(OVERLAP_SUBCELLS_PER_AXIS):
                    sample_x = cell_x + SUBCELL_CENTER_OFFSET_DM + subcell_column * SUBCELL_SIZE_DM
                    delta_x = sample_x - center_x_dm
                    if delta_x * delta_x + delta_y * delta_y <= radius_squared:
                        hits += 1
            if hits:
                weights.append((row, column, hits))
    return weights


def estimate_from_aggregate_cells(
    aggregate_cells: dict[tuple[int, int], tuple[int, int, int, int]],
    x_m: float,
    y_m: float,
) -> tuple[tuple[int, int, int, int], int]:
    center_x_dm = round_half_away_from_zero(x_m / SCAN_COORDINATE_SNAP_M) * int(
        SCAN_COORDINATE_SNAP_M * DECIMETERS_PER_METER
    )
    center_y_dm = round_half_away_from_zero(y_m / SCAN_COORDINATE_SNAP_M) * int(
        SCAN_COORDINATE_SNAP_M * DECIMETERS_PER_METER
    )
    numerators = [0] * len(ALLOWED_CATEGORIES)
    for row, column, hits in overlap_weights_for_snapped_dm(center_x_dm, center_y_dm):
        bands = aggregate_cells.get((row, column))
        if bands is None:
            continue
        for index, value in enumerate(bands):
            numerators[index] += value * hits
    total = (sum(numerators) + OVERLAP_SAMPLE_COUNT // 2) // OVERLAP_SAMPLE_COUNT
    return tuple(numerators), total


def attach_aggregate_estimates(
    nodes: Sequence[dict[str, Any]],
    aggregate_cells: dict[tuple[int, int], tuple[int, int, int, int]],
) -> None:
    weight_cache: dict[tuple[int, int], list[tuple[int, int, int]]] = {}
    for node in nodes:
        x_m = int(node["grid_column"]) * QUERY_NODE_SPACING_M
        y_m = int(node["grid_row"]) * QUERY_NODE_SPACING_M
        center_x_dm = int(x_m * DECIMETERS_PER_METER)
        center_y_dm = int(y_m * DECIMETERS_PER_METER)
        residue = (center_x_dm % CELL_SIZE_DM, center_y_dm % CELL_SIZE_DM)
        relative = weight_cache.get(residue)
        base_column = center_x_dm // CELL_SIZE_DM
        base_row = center_y_dm // CELL_SIZE_DM
        if relative is None:
            absolute = overlap_weights_for_snapped_dm(center_x_dm, center_y_dm)
            relative = [
                (row - base_row, column - base_column, hits)
                for row, column, hits in absolute
            ]
            weight_cache[residue] = relative
        numerators = [0] * len(ALLOWED_CATEGORIES)
        for row_delta, column_delta, hits in relative:
            bands = aggregate_cells.get((base_row + row_delta, base_column + column_delta))
            if bands is None:
                continue
            for index, value in enumerate(bands):
                numerators[index] += value * hits
        node["estimated_category_numerators"] = tuple(numerators)
        node["estimated_total_count"] = (
            sum(numerators) + OVERLAP_SAMPLE_COUNT // 2
        ) // OVERLAP_SAMPLE_COUNT


def percentile_for_count(incident_count: int, distribution: dict[int, int]) -> float:
    total = sum(distribution.values())
    if total <= 0:
        raise ValueError("reference distribution is empty")
    less = sum(sample_count for count, sample_count in distribution.items() if count < incident_count)
    equal = int(distribution.get(incident_count, 0))
    return 100.0 * (less + 0.5 * equal) / total


def round_score_to_nearest_five(percentile: float) -> int:
    bounded = max(0.0, min(100.0, percentile))
    return int(min(100, 5 * math.floor(bounded / 5.0 + 0.5)))


def empirical_quantile(values: Sequence[float | int], probability: float) -> float:
    if not values:
        raise ValueError("quantile input is empty")
    ordered = sorted(float(value) for value in values)
    position = (len(ordered) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] * (upper - position) + ordered[upper] * (position - lower)


def metric_summary(values: Sequence[float | int]) -> dict[str, float]:
    return {
        "mean": sum(float(value) for value in values) / len(values),
        "p50": empirical_quantile(values, 0.50),
        "p90": empirical_quantile(values, 0.90),
        "p95": empirical_quantile(values, 0.95),
        "p99": empirical_quantile(values, 0.99),
        "max": max(float(value) for value in values),
    }


def build_validation_metrics(
    nodes: Sequence[dict[str, Any]],
    references: Sequence[dict[str, Any]],
    aggregate_cells: dict[tuple[int, int], tuple[int, int, int, int]],
) -> dict[str, Any]:
    exact_distribution: collections.Counter[int] = collections.Counter(
        int(reference["total_count"]) for reference in references
    )
    estimated_distribution: collections.Counter[int] = collections.Counter(
        int(reference["estimated_total_count"]) for reference in references
    )
    count_errors: list[int] = []
    score_errors: list[int] = []
    exact_scores: list[int] = []
    estimated_scores: list[int] = []
    dominant_matches = 0
    for node in nodes:
        exact_total = int(node["total_count"])
        estimated_total = int(node["estimated_total_count"])
        count_errors.append(abs(estimated_total - exact_total))
        exact_score = round_score_to_nearest_five(percentile_for_count(exact_total, exact_distribution))
        estimated_score = round_score_to_nearest_five(
            percentile_for_count(estimated_total, estimated_distribution)
        )
        exact_scores.append(exact_score)
        estimated_scores.append(estimated_score)
        score_errors.append(abs(estimated_score - exact_score))
        exact_categories = [int(node[f"{category}_count"]) for category in ALLOWED_CATEGORIES]
        estimated_categories = list(node["estimated_category_numerators"])
        if max(range(len(ALLOWED_CATEGORIES)), key=exact_categories.__getitem__) == max(
            range(len(ALLOWED_CATEGORIES)), key=estimated_categories.__getitem__
        ):
            dominant_matches += 1

    node_keys = {(int(node["grid_row"]), int(node["grid_column"])) for node in nodes}
    interior = [
        node
        for node in nodes
        if all(
            (int(node["grid_row"]) + row_delta, int(node["grid_column"]) + column_delta)
            in node_keys
            for row_delta in (-1, 0, 1)
            for column_delta in (-1, 0, 1)
        )
    ]
    sampled = interior[:: max(1, len(interior) // 500)][:500]
    movement: dict[str, Any] = {}
    for distance in (10, 25, 50):
        deltas: list[int] = []
        for node in sampled:
            x = int(node["grid_column"]) * QUERY_NODE_SPACING_M
            y = int(node["grid_row"]) * QUERY_NODE_SPACING_M
            _, base_count = estimate_from_aggregate_cells(aggregate_cells, x, y)
            base_score = round_score_to_nearest_five(
                percentile_for_count(base_count, estimated_distribution)
            )
            for delta_x, delta_y in ((distance, 0), (-distance, 0), (0, distance), (0, -distance)):
                _, moved_count = estimate_from_aggregate_cells(
                    aggregate_cells, x + delta_x, y + delta_y
                )
                moved_score = round_score_to_nearest_five(
                    percentile_for_count(moved_count, estimated_distribution)
                )
                deltas.append(abs(moved_score - base_score))
        movement[f"{distance}m"] = {
            **metric_summary(deltas),
            "samples": len(deltas),
            "over_10_fraction": sum(value > 10 for value in deltas) / len(deltas),
        }

    return {
        "benchmark": (
            "All eligible 100 m evaluation nodes; exact source points and exact node counts exist "
            "only in build memory and are not shipped."
        ),
        "evaluation_nodes": len(nodes),
        "estimated_count_absolute_error": metric_summary(count_errors),
        "dominant_category_agreement": dominant_matches / len(nodes),
        "cooked_score_absolute_error": {
            **metric_summary(score_errors),
            "exact_fraction": sum(error == 0 for error in score_errors) / len(score_errors),
            "within_5_fraction": sum(error <= 5 for error in score_errors) / len(score_errors),
            "within_10_fraction": sum(error <= 10 for error in score_errors) / len(score_errors),
            "over_10_fraction": sum(error > 10 for error in score_errors) / len(score_errors),
        },
        "movement_score_absolute_error": movement,
    }


def balanced_round_category_numerators(numerators: Sequence[int]) -> tuple[int, ...]:
    floors = [max(0, int(value)) // OVERLAP_SAMPLE_COUNT for value in numerators]
    target = (sum(max(0, int(value)) for value in numerators) + OVERLAP_SAMPLE_COUNT // 2) // OVERLAP_SAMPLE_COUNT
    remainder = max(0, min(len(floors), target - sum(floors)))
    ranked = sorted(
        range(len(floors)),
        key=lambda index: (-(int(numerators[index]) % OVERLAP_SAMPLE_COUNT), index),
    )
    result = list(floors)
    for index in ranked[:remainder]:
        result[index] += 1
    return tuple(result)


def build_parity_fixtures(
    references: Sequence[dict[str, Any]],
    distribution: dict[int, int],
    source_through_date: str,
) -> dict[str, Any]:
    ordered = sorted(references, key=lambda node: (node["grid_row"], node["grid_column"]))
    indexes = [len(ordered) // 4, len(ordered) // 2, (3 * len(ordered)) // 4]
    fixtures = []
    for fixture_index, node_index in enumerate(indexes, start=1):
        node = ordered[node_index]
        numerators = tuple(int(value) for value in node["estimated_category_numerators"])
        estimated_total = int(node["estimated_total_count"])
        percentile = percentile_for_count(estimated_total, distribution)
        fixtures.append(
            {
                "id": f"eligible_reference_{fixture_index}",
                "coverage_eligible": True,
                "grid_row": int(node["grid_row"]),
                "grid_column": int(node["grid_column"]),
                "latitude": float(node["latitude"]),
                "longitude": float(node["longitude"]),
                "community_area": str(node["community_area"]),
                "category_numerators": list(numerators),
                "category_estimates": [value / OVERLAP_SAMPLE_COUNT for value in numerators],
                "display_category_counts": list(balanced_round_category_numerators(numerators)),
                "estimated_total_count": estimated_total,
                "percentile": percentile,
                "cooked_score": round_score_to_nearest_five(percentile),
                "source_through_date": source_through_date,
            }
        )
    return {
        "schema_version": SCHEMA_VERSION,
        "methodology_version": "beta-cell250-q5-area-v3",
        "category_order": list(ALLOWED_CATEGORIES),
        "numerator_denominator": OVERLAP_SAMPLE_COUNT,
        "fixtures_are_aggregate_reference_points_not_incident_locations": True,
        "fixtures": fixtures,
    }


def create_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        f"""
        PRAGMA page_size=4096;
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        PRAGMA locking_mode=EXCLUSIVE;
        PRAGMA application_id=1095320387;
        PRAGMA user_version={SCHEMA_VERSION};

        CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        ) WITHOUT ROWID;

        CREATE TABLE aggregate_cells (
            cell_row INTEGER NOT NULL,
            cell_column INTEGER NOT NULL,
            assault_battery_band INTEGER NOT NULL CHECK(
                assault_battery_band >= 0 AND assault_battery_band % 5 = 0
            ),
            robbery_band INTEGER NOT NULL CHECK(
                robbery_band >= 0 AND robbery_band % 5 = 0
            ),
            theft_band INTEGER NOT NULL CHECK(
                theft_band >= 0 AND theft_band % 5 = 0
            ),
            motor_vehicle_theft_band INTEGER NOT NULL CHECK(
                motor_vehicle_theft_band >= 0 AND motor_vehicle_theft_band % 5 = 0
            ),
            PRIMARY KEY(cell_row, cell_column)
        ) WITHOUT ROWID;

        CREATE TABLE reference_distribution (
            estimated_count INTEGER PRIMARY KEY CHECK(estimated_count >= 0),
            sample_count INTEGER NOT NULL CHECK(sample_count > 0)
        );

        CREATE TABLE neighborhood_centroids (
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            name TEXT NOT NULL UNIQUE
        );

        CREATE TABLE neighborhoods (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            min_lat REAL NOT NULL,
            max_lat REAL NOT NULL,
            min_lon REAL NOT NULL,
            max_lon REAL NOT NULL,
            geometry_json TEXT NOT NULL
        );
        CREATE INDEX idx_neighborhood_bbox ON neighborhoods(min_lat, max_lat, min_lon, max_lon);

        CREATE TABLE city_boundary (
            id INTEGER PRIMARY KEY CHECK(id = 1),
            min_lat REAL NOT NULL,
            max_lat REAL NOT NULL,
            min_lon REAL NOT NULL,
            max_lon REAL NOT NULL,
            geometry_json TEXT NOT NULL
        );
        """
    )


def combined_city_geometry(neighborhoods: Sequence[dict[str, Any]]) -> dict[str, Any]:
    polygons: list[Any] = []
    for neighborhood in neighborhoods:
        geometry = neighborhood["geometry"]
        if geometry.get("type") == "Polygon":
            polygons.append(geometry["coordinates"])
        elif geometry.get("type") == "MultiPolygon":
            polygons.extend(geometry["coordinates"])
        else:
            raise ValueError(f"unsupported boundary geometry type: {geometry.get('type')}")
    return {"type": "MultiPolygon", "coordinates": polygons}


def build_pack(
    output_path: Path,
    aggregate_cells: dict[tuple[int, int], tuple[int, int, int, int]],
    neighborhoods: Sequence[dict[str, Any]],
    distribution: dict[int, int],
    metadata: dict[str, str],
) -> None:
    validate_freshness_metadata(metadata)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = output_path.with_suffix(".tmp.sqlite")
    temporary.unlink(missing_ok=True)
    connection = sqlite3.connect(temporary)
    try:
        create_schema(connection)
        connection.executemany(
            "INSERT INTO metadata(key,value) VALUES (?,?)",
            sorted(metadata.items()),
        )
        connection.executemany(
            """INSERT INTO aggregate_cells(
                   cell_row,cell_column,assault_battery_band,robbery_band,
                   theft_band,motor_vehicle_theft_band
               ) VALUES (?,?,?,?,?,?)""",
            [
                (
                    int(key[0]),
                    int(key[1]),
                    int(values[0]),
                    int(values[1]),
                    int(values[2]),
                    int(values[3]),
                )
                for key, values in sorted(aggregate_cells.items())
            ],
        )
        connection.executemany(
            "INSERT INTO reference_distribution(estimated_count,sample_count) VALUES (?,?)",
            sorted((int(count), int(samples)) for count, samples in distribution.items()),
        )
        connection.executemany(
            "INSERT INTO neighborhood_centroids(latitude,longitude,name) VALUES (?,?,?)",
            [
                (
                    float(neighborhood["centroid_lat"]),
                    float(neighborhood["centroid_lon"]),
                    str(neighborhood["name"]),
                )
                for neighborhood in neighborhoods
            ],
        )
        connection.executemany(
            """INSERT INTO neighborhoods(
                   id,name,min_lat,max_lat,min_lon,max_lon,geometry_json
               ) VALUES (?,?,?,?,?,?,?)""",
            [
                (
                    int(neighborhood["id"]),
                    str(neighborhood["name"]),
                    float(neighborhood["min_lat"]),
                    float(neighborhood["max_lat"]),
                    float(neighborhood["min_lon"]),
                    float(neighborhood["max_lon"]),
                    canonical_json(neighborhood["geometry"]),
                )
                for neighborhood in neighborhoods
            ],
        )
        city_geometry = combined_city_geometry(neighborhoods)
        min_lat, max_lat, min_lon, max_lon = geometry_bbox(city_geometry)
        connection.execute(
            "INSERT INTO city_boundary(id,min_lat,max_lat,min_lon,max_lon,geometry_json) VALUES (1,?,?,?,?,?)",
            (min_lat, max_lat, min_lon, max_lon, canonical_json(city_geometry)),
        )
        connection.commit()
        connection.execute("VACUUM")
        connection.commit()
    finally:
        connection.close()
    os.replace(temporary, output_path)


def build_manifest(
    pack_path: Path,
    compressed_path: Path,
    source_info: dict[str, Any],
    metadata: dict[str, str],
    distribution: dict[int, int],
    neighborhoods: Sequence[dict[str, Any]],
    aggregate_cells: dict[tuple[int, int], tuple[int, int, int, int]],
    evaluation_nodes: Sequence[dict[str, Any]],
    references: Sequence[dict[str, Any]],
    disclosure: dict[str, Any],
    validation_metrics: dict[str, Any],
    parity_path: Path,
    query: str,
    source_snapshot_path: Path,
    boundary_snapshot_path: Path,
    iucr_snapshot_path: Path,
    iucr_source_query: str,
    frozen_mapping_path: Path,
    frozen_mapping: dict[str, dict[str, Any]],
    city_grid_count: int,
    coverage_sample_count: int,
) -> dict[str, Any]:
    observed_iucr = sorted(
        {str(row["iucr"]) for row in source_info["selected_counts_by_iucr"] if int(row["count"]) > 0}
    )
    return {
        "schema_version": SCHEMA_VERSION,
        "pack": {
            "filename": pack_path.name,
            "sha256": sha256_file(pack_path),
            "size_bytes": pack_path.stat().st_size,
            "compressed_filename": compressed_path.name,
            "compressed_sha256": sha256_file(compressed_path),
            "compressed_size_bytes": compressed_path.stat().st_size,
        },
        "cross_language_parity": {
            "filename": parity_path.name,
            "sha256": sha256_file(parity_path),
            "fixture_count": 3,
        },
        "period": {
            "start": metadata["period_start"],
            "end_exclusive": metadata["period_end_exclusive"],
            "source_through_date": metadata["source_through_date"],
            "fresh_until_date": metadata["fresh_until_date"],
            "expires_at_date": metadata["expires_at_date"],
            "months": int(metadata["period_months"]),
        },
        "sources": {
            "crime": {
                "dataset_id": CRIME_DATASET_ID,
                "official_url": CRIME_SOURCE_URL,
                "resource_url": CRIME_RESOURCE_URL,
                "retrieved_at": source_info["retrieved_at"],
                "source_rows_updated_at_epoch": source_info["crime_metadata"].get("rows_updated_at_epoch"),
                "query": query,
                "snapshot_sha256": sha256_file(source_snapshot_path),
            },
            "community_areas": {
                "dataset_id": BOUNDARY_DATASET_ID,
                "official_url": BOUNDARY_SOURCE_URL,
                "resource_url": BOUNDARY_RESOURCE_URL,
                "retrieved_at": source_info["retrieved_at"],
                "source_rows_updated_at_epoch": source_info["boundary_metadata"].get("rows_updated_at_epoch"),
                "query": "$select=area_numbe,community,the_geom&$order=area_numbe&$limit=100",
                "snapshot_sha256": sha256_file(boundary_snapshot_path),
            },
            "iucr_codes": {
                "dataset_id": IUCR_DATASET_ID,
                "official_url": IUCR_SOURCE_URL,
                "resource_url": IUCR_RESOURCE_URL,
                "retrieved_at": source_info["retrieved_at"],
                "source_rows_updated_at_epoch": source_info["iucr_metadata"].get("rows_updated_at_epoch"),
                "query": iucr_source_query,
                "snapshot_sha256": sha256_file(iucr_snapshot_path),
            },
        },
        "iucr_mapping": {
            "frozen_file": str(frozen_mapping_path.as_posix()),
            "frozen_file_sha256": sha256_file(frozen_mapping_path),
            "frozen_code_count": len(frozen_mapping),
            "observed_code_count": len(observed_iucr),
            "observed_codes": observed_iucr,
            "unobserved_frozen_codes": sorted(set(frozen_mapping) - set(observed_iucr)),
            "selection_rule": "IUCR code must appear exactly once in the frozen mapping; primary_type must match the frozen official primary description.",
            "mutual_exclusivity_verified": True,
        },
        "row_counts": {
            "all_source_rows_in_period": source_info["all_rows"],
            "all_geocoded_source_rows_in_period": source_info["all_geocoded_rows"],
            "selected_source_rows": source_info["selected_rows"],
            "selected_geocoded_rows": source_info["selected_geocoded_rows"],
            "selected_missing_coordinates_excluded": source_info["selected_rows"] - source_info["selected_geocoded_rows"],
            "unsupported_categories_excluded": source_info["all_rows"] - source_info["chosen_primary_rows"],
            "selected_iucr_rows_unmapped": source_info["selected_iucr_rows_unmapped"],
            "outside_official_boundary_coordinates_excluded": disclosure[
                "outside_city_coordinates_excluded"
            ],
            "temporary_source_incidents_used_to_aggregate": disclosure["usable_source_rows"],
            "shipped_incident_rows": 0,
            "aggregate_cells": len(aggregate_cells),
            "aggregate_cells_with_any_positive_band": sum(
                any(value > 0 for value in values) for values in aggregate_cells.values()
            ),
            "evaluation_nodes_not_shipped": len(evaluation_nodes),
            "eligible_reference_locations": len(references),
            "reference_distribution_buckets": len(distribution),
            "community_areas": len(neighborhoods),
        },
        "estimator": {
            "radius_m": float(metadata["radius_m"]),
            "aggregate_cell_size_m": AGGREGATE_CELL_SIZE_M,
            "aggregate_band_size": AGGREGATE_BAND_SIZE,
            "aggregate_band_rounding": "nearest five, half values upward, independently per category",
            "scan_coordinate_snap_m": SCAN_COORDINATE_SNAP_M,
            "overlap_subcells_per_axis": OVERLAP_SUBCELLS_PER_AXIS,
            "overlap_subcell_size_m": OVERLAP_SUBCELL_SIZE_M,
            "area_weighting": (
                "Snap local x/y to the nearest whole metre half-away-from-zero. Divide each "
                "250 m cell into a fixed 10 by 10 lattice of 25 m subcells. The cell weight is "
                "the number of subcell centers within the inclusive 500 m Euclidean disk divided "
                "by 100. Sum band times hit-count with integer decimetre geometry, divide by 100, "
                "and round the total to the nearest integer half-up."
            ),
            "integer_geometry": {
                "unit": "decimetre",
                "cell_size": CELL_SIZE_DM,
                "radius": RADIUS_DM,
                "subcell_size": SUBCELL_SIZE_DM,
                "subcell_center_offset": SUBCELL_CENTER_OFFSET_DM,
                "radius_squared_inclusive": RADIUS_DM**2,
            },
            "reference_spacing_m": float(metadata["reference_spacing_m"]),
            "grid_anchor": {"latitude": GRID_ANCHOR_LAT, "longitude": GRID_ANCHOR_LON},
            "city_center_nodes_before_coverage_gate": city_grid_count,
            "coverage_disk_lattice_samples": coverage_sample_count,
            "eligibility": (
                "Every 100 m lattice point within 500 m of the query node must be inside the "
                "union of official Chicago community-area polygons; nodes failing this discrete "
                "coverage gate are ineligible. The coverage lattice is a conservative discrete "
                "approximation, not a proof that every point in the continuous disk is inside."
            ),
            "percentile": "empirical midrank: 100 * (references below + 0.5 * references tied) / N",
            "display_rounding": "nearest five, half values round upward, clamped to 0...100",
            "count_semantics": "privacy-coarsened estimated contributing incidents, never an exact circle count",
        },
        "privacy": {
            "shipped_incident_rows": 0,
            "source_points_shipped": False,
            "aggregate_cell_columns": [
                "cell_row",
                "cell_column",
                "assault_battery_band",
                "robbery_band",
                "theft_band",
                "motor_vehicle_theft_band",
            ],
            "all_fixed_domain_cells_shipped_including_zero": True,
            "nonoverlapping_cells": True,
            "each_source_event_influences_at_most_one_cell_and_one_category": True,
            "all_subcell_positions_for_an_eligible_record_within_the_same_cell_and_category_are_release_equivalent": True,
            "exact_or_residual_total_released": False,
            "zero_band_true_range": "0-2 incidents per category and cell",
            "five_band_true_range": "3-7 incidents per category and cell",
            "prohibited_fields_absent": [
                "incident-level coordinates",
                "source incident ID",
                "case number",
                "date or timestamp",
                "block or address",
                "description",
                "arrest",
                "victim information",
            ],
            "network_rule": "The app must never upload scan coordinates, query-node coordinates, or geographic cells.",
        },
        "disclosure_validation": disclosure,
        "utility_validation": validation_metrics,
        "display": {
            "product_name": "Cooked Score",
            "methodology_name": "Reported Incident Exposure Index",
            "disclaimer": DISCLAIMER,
            "source_limitation": SOURCE_LIMITATION,
        },
    }


def verify_download_counts(
    records: Sequence[dict[str, Any]],
    expected_count: int,
    iucr_mapping: dict[str, dict[str, Any]],
    start: dt.date | None = None,
    end_exclusive: dt.date | None = None,
) -> tuple[dict[str, int], list[dict[str, Any]]]:
    source_ids = [int(record["id"]) for record in records]
    if len(source_ids) != len(set(source_ids)):
        raise RuntimeError("source snapshot contains duplicate incident IDs")
    if len(records) != expected_count:
        raise RuntimeError(f"downloaded {len(records)} selected rows; Socrata count query returned {expected_count}")
    category_counts: collections.Counter[str] = collections.Counter()
    iucr_counts: collections.Counter[tuple[str, str]] = collections.Counter()
    for record in records:
        if start is not None and end_exclusive is not None:
            if not record.get("date"):
                raise RuntimeError("source snapshot omits occurrence date required for window audit")
            occurred = parse_socrata_date(str(record["date"])).date()
            if not (start <= occurred < end_exclusive):
                raise RuntimeError(
                    f"source incident {record.get('id')} falls outside frozen period: {occurred}"
                )
        code = str(record.get("iucr", ""))
        if code not in iucr_mapping:
            raise RuntimeError(f"included incident has unmapped IUCR code {code!r}")
        expected_primary = str(iucr_mapping[code]["official_primary_description"])
        actual_primary = str(record.get("primary_type", ""))
        if actual_primary != expected_primary:
            raise RuntimeError(
                f"incident IUCR {code} primary_type mismatch: expected {expected_primary!r}, got {actual_primary!r}"
            )
        category_counts[str(iucr_mapping[code]["category"])] += 1
        iucr_counts[(code, actual_primary)] += 1
        latitude = float(record["latitude"])
        longitude = float(record["longitude"])
        if not (41.0 <= latitude <= 43.0 and -89.0 <= longitude <= -86.0):
            raise RuntimeError(f"selected incident has implausible Chicago coordinate: {latitude},{longitude}")
    grouped = [
        {"iucr": code, "primary_type": primary_type, "count": count}
        for (code, primary_type), count in sorted(iucr_counts.items())
    ]
    return dict(category_counts), grouped


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("data"))
    parser.add_argument("--cache-dir", type=Path, default=Path("pipeline/.cache"))
    parser.add_argument("--iucr-mapping", type=Path, default=Path("pipeline/iucr_mapping.json"))
    parser.add_argument("--months", type=int, default=12)
    parser.add_argument("--period-end", help="exclusive YYYY-MM-01; default derives from newest source record")
    parser.add_argument("--radius-m", type=float, default=500.0)
    parser.add_argument("--query-node-spacing-m", type=float, default=QUERY_NODE_SPACING_M)
    parser.add_argument("--reference-spacing-m", type=float, default=REFERENCE_SPACING_M)
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()

    if not math.isclose(args.radius_m, 500.0, rel_tol=0, abs_tol=1e-9):
        raise SystemExit("schema v3 fixes --radius-m at 500")
    if not math.isclose(args.query_node_spacing_m, 100.0, rel_tol=0, abs_tol=1e-9):
        raise SystemExit("schema v3 fixes --query-node-spacing-m at 100 for evaluation/coverage")
    if not math.isclose(args.reference_spacing_m, 500.0, rel_tol=0, abs_tol=1e-9):
        raise SystemExit("schema v3 fixes --reference-spacing-m at 500")

    iucr_mapping, _mapping_document = load_frozen_iucr_mapping(args.iucr_mapping)
    max_date = discover_max_date(iucr_mapping)
    try:
        if args.period_end:
            start, end_exclusive = derive_pinned_period(
                max_date,
                args.period_end,
                args.months,
            )
        else:
            start, end_exclusive = derive_period(max_date, args.months)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    source_through = end_exclusive - dt.timedelta(days=1)
    fresh_until, expires_at = derive_freshness_dates(source_through.isoformat())
    period_slug = f"{start.isoformat()}_{end_exclusive.isoformat()}"
    incident_snapshot = args.cache_dir / f"incidents_iucr_v3_{period_slug}.jsonl.gz"
    boundary_snapshot = args.cache_dir / "community_areas.json.gz"
    iucr_snapshot = args.cache_dir / "iucr_selected_codes_v2.json.gz"
    source_info_path = args.cache_dir / f"source_info_iucr_v3_{period_slug}.json"

    records, query = download_incident_snapshot(
        incident_snapshot,
        start,
        end_exclusive,
        iucr_mapping,
        args.refresh,
    )
    boundary_rows = download_boundaries(boundary_snapshot, args.refresh)
    official_iucr_rows, iucr_source_query = download_official_iucr_source(iucr_snapshot, args.refresh)
    validate_frozen_iucr_mapping(iucr_mapping, official_iucr_rows)

    period_clause = period_where(start, end_exclusive)
    selected_clause = f"{period_clause} AND {iucr_where(iucr_mapping)}"
    selected_geocoded_clause = f"{selected_clause} AND latitude IS NOT NULL AND longitude IS NOT NULL"
    all_geocoded_clause = f"{period_clause} AND latitude IS NOT NULL AND longitude IS NOT NULL"
    chosen_primary_clause = f"{period_clause} AND {primary_type_where(CATEGORY_BY_PRIMARY)}"
    unmapped_clause = (
        f"{chosen_primary_clause} AND (iucr IS NULL OR NOT ({iucr_where(iucr_mapping)}))"
    )
    if source_info_path.exists() and not args.refresh:
        source_info = json.loads(source_info_path.read_text(encoding="utf-8"))
    else:
        source_info = {
            "retrieved_at": utc_now(),
            "max_observed_source_date": max_date,
            "crime_metadata": fetch_dataset_metadata(CRIME_DATASET_ID),
            "boundary_metadata": fetch_dataset_metadata(BOUNDARY_DATASET_ID),
            "iucr_metadata": fetch_dataset_metadata(IUCR_DATASET_ID),
            "all_rows": count_query(period_clause),
            "all_geocoded_rows": count_query(all_geocoded_clause),
            "selected_rows": count_query(selected_clause),
            "selected_geocoded_rows": count_query(selected_geocoded_clause),
            "chosen_primary_rows": count_query(chosen_primary_clause),
            "selected_iucr_rows_unmapped": count_query(unmapped_clause),
            "selected_counts_by_iucr": iucr_count_query(selected_geocoded_clause),
        }
        source_info_path.parent.mkdir(parents=True, exist_ok=True)
        write_json(source_info_path, source_info)

    _category_counts, downloaded_iucr_counts = verify_download_counts(
        records,
        int(source_info["selected_geocoded_rows"]),
        iucr_mapping,
        start,
        end_exclusive,
    )
    if downloaded_iucr_counts != source_info["selected_counts_by_iucr"]:
        raise RuntimeError("downloaded IUCR counts do not reconcile with the Socrata aggregate query")
    if int(source_info["selected_iucr_rows_unmapped"]) != 0:
        raise RuntimeError(
            "chosen source categories contain IUCR codes outside the frozen mapping; review required"
        )
    if int(source_info["chosen_primary_rows"]) != int(source_info["selected_rows"]):
        raise RuntimeError("chosen primary-type total does not reconcile with mapped IUCR total")
    neighborhoods = prepare_neighborhoods(boundary_rows)
    if len(neighborhoods) != 77:
        raise RuntimeError(f"expected 77 official Chicago community areas, got {len(neighborhoods)}")
    query_nodes, city_grid_count, coverage_sample_count = generate_eligible_query_nodes(
        neighborhoods,
        spacing_m=args.query_node_spacing_m,
        radius_m=args.radius_m,
    )
    if not query_nodes:
        raise RuntimeError("query-node grid is empty")
    _raw_cells, aggregate_cells, disclosure, usable_records = build_aggregate_cells(
        records, iucr_mapping, neighborhoods
    )
    attach_node_counts(query_nodes, usable_records, iucr_mapping, args.radius_m)
    attach_aggregate_estimates(query_nodes, aggregate_cells)
    references = select_reference_nodes(
        query_nodes,
        query_spacing_m=args.query_node_spacing_m,
        reference_spacing_m=args.reference_spacing_m,
    )
    if not references:
        raise RuntimeError("reference grid is empty")
    distribution: collections.Counter[int] = collections.Counter(
        int(reference["estimated_total_count"]) for reference in references
    )
    validation_metrics = build_validation_metrics(query_nodes, references, aggregate_cells)
    domain = disclosure["aggregate_domain"]

    metadata = {
        "schema_version": str(SCHEMA_VERSION),
        "city": "Chicago",
        "state": "IL",
        "country": "US",
        "product_name": "Cooked Score",
        "methodology_name": "Reported Incident Exposure Index",
        "methodology_version": "beta-cell250-q5-area-v3",
        "period_start": start.isoformat(),
        "period_end_exclusive": end_exclusive.isoformat(),
        "source_through_date": source_through.isoformat(),
        "fresh_until_date": fresh_until,
        "expires_at_date": expires_at,
        "period_months": str(args.months),
        "source_dataset_id": CRIME_DATASET_ID,
        "source_url": CRIME_SOURCE_URL,
        "boundary_dataset_id": BOUNDARY_DATASET_ID,
        "boundary_source_url": BOUNDARY_SOURCE_URL,
        "iucr_dataset_id": IUCR_DATASET_ID,
        "iucr_source_url": IUCR_SOURCE_URL,
        "frozen_iucr_mapping_sha256": sha256_file(args.iucr_mapping),
        "source_retrieved_at": source_info["retrieved_at"],
        "source_max_observed_date": source_info["max_observed_source_date"],
        "radius_m": str(args.radius_m),
        "aggregate_cell_size_m": str(AGGREGATE_CELL_SIZE_M),
        "aggregate_band_size": str(AGGREGATE_BAND_SIZE),
        "aggregate_band_rounding": "nearest_5_half_up",
        "aggregate_row_min": str(domain["row_min"]),
        "aggregate_row_max": str(domain["row_max"]),
        "aggregate_column_min": str(domain["column_min"]),
        "aggregate_column_max": str(domain["column_max"]),
        "aggregate_cell_count": str(len(aggregate_cells)),
        "scan_coordinate_snap_m": str(SCAN_COORDINATE_SNAP_M),
        "overlap_subcells_per_axis": str(OVERLAP_SUBCELLS_PER_AXIS),
        "overlap_subcell_size_m": str(OVERLAP_SUBCELL_SIZE_M),
        "circle_estimator": "area_weighted_10x10_subcell_midpoint_integer_dm",
        "estimated_count_rounding": "nearest_integer_half_up",
        "grid_anchor_latitude": str(GRID_ANCHOR_LAT),
        "grid_anchor_longitude": str(GRID_ANCHOR_LON),
        "earth_radius_m": str(EARTH_RADIUS_M),
        "reference_spacing_m": str(args.reference_spacing_m),
        "reference_eligible_count": str(len(references)),
        "aggregate_input_record_count": str(len(usable_records)),
        "community_area_count": str(len(neighborhoods)),
        "percentile_method": "empirical_midrank",
        "display_rounding": "nearest_5_half_up",
        "reference_eligibility": "all_100m_disk_lattice_points_inside_official_city_union",
        "coverage_disk_lattice_samples": str(coverage_sample_count),
        "distance_method": "local_tangent_integer_decimetre_midpoint_area_estimator",
        "disclaimer": DISCLAIMER,
        "source_limitation": SOURCE_LIMITATION,
        "ordinary_scan_network_policy": "local_only_no_coordinates_query_nodes_or_geographic_cells_uploaded",
        "pack_privacy": "nonoverlapping_250m_cells_independent_q5_bands_no_exact_or_residual_total",
        "count_semantics": "privacy_coarsened_estimated_contributing_incidents",
    }

    args.output_dir.mkdir(parents=True, exist_ok=True)
    pack_path = args.output_dir / PACK_FILENAME
    compressed_path = args.output_dir / COMPRESSED_FILENAME
    manifest_path = args.output_dir / MANIFEST_FILENAME
    parity_path = args.output_dir / PARITY_FILENAME
    checksum_path = args.output_dir / CHECKSUM_FILENAME
    build_pack(pack_path, aggregate_cells, neighborhoods, distribution, metadata)
    write_reproducible_gzip(pack_path, compressed_path)
    write_json(
        parity_path,
        build_parity_fixtures(references, distribution, source_through.isoformat()),
    )
    manifest = build_manifest(
        pack_path,
        compressed_path,
        source_info,
        metadata,
        distribution,
        neighborhoods,
        aggregate_cells,
        query_nodes,
        references,
        disclosure,
        validation_metrics,
        parity_path,
        query,
        incident_snapshot,
        boundary_snapshot,
        iucr_snapshot,
        iucr_source_query,
        args.iucr_mapping,
        iucr_mapping,
        city_grid_count,
        coverage_sample_count,
    )
    write_json(manifest_path, manifest)
    checksum_lines = [
        f"{sha256_file(pack_path)}  {pack_path.name}",
        f"{sha256_file(compressed_path)}  {compressed_path.name}",
        f"{sha256_file(parity_path)}  {parity_path.name}",
        f"{sha256_file(manifest_path)}  {manifest_path.name}",
    ]
    checksum_path.write_text("\n".join(checksum_lines) + "\n", encoding="ascii")

    print(
        json.dumps(
            {
                "pack": str(pack_path),
                "pack_size_bytes": pack_path.stat().st_size,
                "compressed_size_bytes": compressed_path.stat().st_size,
                "period_start": start.isoformat(),
                "source_through_date": source_through.isoformat(),
                "source_records_aggregated": len(usable_records),
                "aggregate_cells": len(aggregate_cells),
                "evaluation_nodes_not_shipped": len(query_nodes),
                "eligible_references": len(references),
                "community_areas": len(neighborhoods),
                "sha256": sha256_file(pack_path),
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
