#!/usr/bin/env python3
"""Verify an AIC schema-v3 Chicago pack against its manifest and privacy contract."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
from pathlib import Path
import sqlite3
from typing import Any

import build_chicago_pack as builder


EXPECTED_AGGREGATE_COLUMNS = [
    "cell_row",
    "cell_column",
    "assault_battery_band",
    "robbery_band",
    "theft_band",
    "motor_vehicle_theft_band",
]
EXPECTED_DISCLAIMER = (
    "Cooked Score is a historical data index that compares reported-incident "
    "concentration around this location with eligible Chicago comparison locations. "
    "It is not a live safety assessment or personal-risk prediction."
)
EXPECTED_PRIVACY = "nonoverlapping_250m_cells_independent_q5_bands_no_exact_or_residual_total"
PROHIBITED_AGGREGATE_FRAGMENTS = (
    "incident",
    "source",
    "case",
    "date",
    "time",
    "address",
    "block",
    "description",
    "victim",
    "arrest",
    "latitude",
    "longitude",
    "total",
    "percentile",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def required_metadata(connection: sqlite3.Connection, key: str) -> str:
    row = connection.execute("SELECT value FROM metadata WHERE key=?", (key,)).fetchone()
    if row is None or not str(row[0]):
        raise RuntimeError(f"required metadata is missing: {key}")
    return str(row[0])


def load_neighborhoods(connection: sqlite3.Connection) -> list[dict[str, Any]]:
    centroids = {
        name: (latitude, longitude)
        for latitude, longitude, name in connection.execute(
            "SELECT latitude,longitude,name FROM neighborhood_centroids"
        )
    }
    result = []
    for row in connection.execute(
        "SELECT id,name,min_lat,max_lat,min_lon,max_lon,geometry_json FROM neighborhoods ORDER BY id"
    ):
        centroid = centroids.get(row[1])
        if centroid is None:
            raise RuntimeError(f"community area centroid is missing: {row[1]}")
        result.append(
            {
                "id": int(row[0]),
                "name": str(row[1]),
                "min_lat": float(row[2]),
                "max_lat": float(row[3]),
                "min_lon": float(row[4]),
                "max_lon": float(row[5]),
                "geometry": json.loads(row[6]),
                "centroid_lat": float(centroid[0]),
                "centroid_lon": float(centroid[1]),
            }
        )
    return result


def verify(pack_path: Path, manifest_path: Path) -> dict[str, object]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    parity_path = manifest_path.parent / manifest["cross_language_parity"]["filename"]
    if not parity_path.exists() or sha256_file(parity_path) != manifest["cross_language_parity"]["sha256"]:
        raise RuntimeError("cross-language parity fixture hash does not match manifest")
    parity = json.loads(parity_path.read_text(encoding="utf-8"))
    if parity.get("schema_version") != 3 or parity.get("category_order") != list(builder.ALLOWED_CATEGORIES):
        raise RuntimeError("cross-language parity fixture category/schema contract is invalid")
    actual_sha = sha256_file(pack_path)
    if actual_sha != manifest["pack"]["sha256"]:
        raise RuntimeError("pack SHA-256 does not match manifest")
    if pack_path.stat().st_size != manifest["pack"]["size_bytes"]:
        raise RuntimeError("pack size does not match manifest")

    connection = sqlite3.connect(f"file:{pack_path}?mode=ro", uri=True)
    try:
        if connection.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise RuntimeError("SQLite integrity check failed")
        if connection.execute("PRAGMA user_version").fetchone()[0] != 3:
            raise RuntimeError("SQLite user_version is not schema v3")
        tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        forbidden_tables = {"incidents", "query_nodes", "reference_points"} & tables
        if forbidden_tables:
            raise RuntimeError(f"privacy-prohibited tables present: {sorted(forbidden_tables)}")
        required_tables = {
            "aggregate_cells",
            "reference_distribution",
            "metadata",
            "neighborhood_centroids",
            "neighborhoods",
            "city_boundary",
        }
        if not required_tables.issubset(tables):
            raise RuntimeError(f"required tables missing: {sorted(required_tables - tables)}")

        columns = [row[1] for row in connection.execute("PRAGMA table_info(aggregate_cells)")]
        if columns != EXPECTED_AGGREGATE_COLUMNS:
            raise RuntimeError(f"aggregate-cell schema violates contract: {columns}")
        prohibited = [
            column
            for column in columns
            if any(fragment in column.lower() for fragment in PROHIBITED_AGGREGATE_FRAGMENTS)
        ]
        if prohibited:
            raise RuntimeError(f"prohibited aggregate-cell columns present: {prohibited}")

        invalid_bands = connection.execute(
            """SELECT count(*) FROM aggregate_cells WHERE
               assault_battery_band < 0 OR assault_battery_band % 5 != 0 OR
               robbery_band < 0 OR robbery_band % 5 != 0 OR
               theft_band < 0 OR theft_band % 5 != 0 OR
               motor_vehicle_theft_band < 0 OR motor_vehicle_theft_band % 5 != 0"""
        ).fetchone()[0]
        if invalid_bands:
            raise RuntimeError("aggregate-cell bands are not independent nonnegative multiples of five")

        row_min = int(required_metadata(connection, "aggregate_row_min"))
        row_max = int(required_metadata(connection, "aggregate_row_max"))
        column_min = int(required_metadata(connection, "aggregate_column_min"))
        column_max = int(required_metadata(connection, "aggregate_column_max"))
        expected_cells = (row_max - row_min + 1) * (column_max - column_min + 1)
        actual_cells = connection.execute("SELECT count(*) FROM aggregate_cells").fetchone()[0]
        out_of_domain = connection.execute(
            """SELECT count(*) FROM aggregate_cells
               WHERE cell_row NOT BETWEEN ? AND ? OR cell_column NOT BETWEEN ? AND ?""",
            (row_min, row_max, column_min, column_max),
        ).fetchone()[0]
        if actual_cells != expected_cells or out_of_domain:
            raise RuntimeError("fixed aggregate domain is incomplete or contains out-of-domain rows")
        extrema = connection.execute(
            "SELECT min(cell_row),max(cell_row),min(cell_column),max(cell_column) FROM aggregate_cells"
        ).fetchone()
        if extrema != (row_min, row_max, column_min, column_max):
            raise RuntimeError("aggregate-domain extrema do not match metadata")

        expected_metadata = {
            "schema_version": "3",
            "methodology_version": "beta-cell250-q5-area-v3",
            "radius_m": "500.0",
            "aggregate_cell_size_m": "250.0",
            "aggregate_band_size": "5",
            "aggregate_band_rounding": "nearest_5_half_up",
            "scan_coordinate_snap_m": "1.0",
            "overlap_subcells_per_axis": "10",
            "overlap_subcell_size_m": "25.0",
            "circle_estimator": "area_weighted_10x10_subcell_midpoint_integer_dm",
            "estimated_count_rounding": "nearest_integer_half_up",
            "percentile_method": "empirical_midrank",
            "display_rounding": "nearest_5_half_up",
            "pack_privacy": EXPECTED_PRIVACY,
            "count_semantics": "privacy_coarsened_estimated_contributing_incidents",
        }
        for key, expected in expected_metadata.items():
            if required_metadata(connection, key) != expected:
                raise RuntimeError(f"metadata mismatch for {key}")
        freshness_metadata = {
            key: required_metadata(connection, key)
            for key in ("source_through_date", "fresh_until_date", "expires_at_date")
        }
        builder.validate_freshness_metadata(freshness_metadata)
        manifest_period = manifest.get("period")
        if not isinstance(manifest_period, dict):
            raise RuntimeError("manifest period metadata is missing")
        for key, value in freshness_metadata.items():
            if manifest_period.get(key) != value:
                raise RuntimeError(f"manifest period metadata mismatch for {key}")
        if required_metadata(connection, "disclaimer") != EXPECTED_DISCLAIMER:
            raise RuntimeError("required disclaimer text does not match")

        distribution = dict(
            connection.execute("SELECT estimated_count,sample_count FROM reference_distribution")
        )
        reference_total = sum(distribution.values())
        if reference_total != manifest["row_counts"]["eligible_reference_locations"]:
            raise RuntimeError("reference count does not match manifest")
        neighborhoods = load_neighborhoods(connection)
        if len(neighborhoods) != 77 or connection.execute("SELECT count(*) FROM city_boundary").fetchone()[0] != 1:
            raise RuntimeError("official boundary rows are incomplete")

        aggregate_cells = {
            (int(row[0]), int(row[1])): tuple(int(value) for value in row[2:6])
            for row in connection.execute(
                """SELECT cell_row,cell_column,assault_battery_band,robbery_band,
                          theft_band,motor_vehicle_theft_band FROM aggregate_cells"""
            )
        }
        evaluation_nodes, _, _ = builder.generate_eligible_query_nodes(
            neighborhoods, builder.QUERY_NODE_SPACING_M, 500.0
        )
        references = builder.select_reference_nodes(
            evaluation_nodes, builder.QUERY_NODE_SPACING_M, builder.REFERENCE_SPACING_M
        )
        builder.attach_aggregate_estimates(references, aggregate_cells)
        reconstructed = collections.Counter(
            int(reference["estimated_total_count"]) for reference in references
        )
        if reconstructed != collections.Counter(distribution):
            raise RuntimeError("reference distribution does not reproduce from aggregate cells")

        reference_keys = {
            (int(reference["grid_row"]), int(reference["grid_column"])) for reference in references
        }
        for fixture in parity.get("fixtures", []):
            key = (int(fixture["grid_row"]), int(fixture["grid_column"]))
            if key not in reference_keys or not fixture.get("coverage_eligible"):
                raise RuntimeError(f"parity fixture is not an eligible reference: {fixture.get('id')}")
            x_m, y_m = builder.local_xy(float(fixture["latitude"]), float(fixture["longitude"]))
            numerators, estimated_total = builder.estimate_from_aggregate_cells(
                aggregate_cells, x_m, y_m
            )
            percentile = builder.percentile_for_count(estimated_total, distribution)
            if list(numerators) != fixture["category_numerators"]:
                raise RuntimeError(f"parity category numerator mismatch: {fixture.get('id')}")
            if list(builder.balanced_round_category_numerators(numerators)) != fixture["display_category_counts"]:
                raise RuntimeError(f"parity display-category mismatch: {fixture.get('id')}")
            if estimated_total != int(fixture["estimated_total_count"]):
                raise RuntimeError(f"parity estimated-total mismatch: {fixture.get('id')}")
            if abs(percentile - float(fixture["percentile"])) > 1e-12:
                raise RuntimeError(f"parity percentile mismatch: {fixture.get('id')}")
            if builder.round_score_to_nearest_five(percentile) != int(fixture["cooked_score"]):
                raise RuntimeError(f"parity score mismatch: {fixture.get('id')}")

        if actual_cells != manifest["row_counts"]["aggregate_cells"]:
            raise RuntimeError("aggregate-cell count does not match manifest")
        if manifest["row_counts"]["shipped_incident_rows"] != 0:
            raise RuntimeError("manifest claims shipped incident rows")
        if manifest["privacy"]["exact_or_residual_total_released"]:
            raise RuntimeError("manifest claims an exact or residual total is released")
    finally:
        connection.close()

    return {
        "integrity": "ok",
        "sha256": actual_sha,
        "schema_version": 3,
        "aggregate_cell_columns": EXPECTED_AGGREGATE_COLUMNS,
        "aggregate_cells": actual_cells,
        "all_fixed_domain_cells_present": True,
        "bands_are_independent_multiples_of_five": True,
        "exact_or_residual_total_released": False,
        "eligible_references": reference_total,
        "reference_distribution_reproduced": True,
        "cross_language_parity_fixtures": len(parity["fixtures"]),
        "community_areas": len(neighborhoods),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack", type=Path)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.pack, args.manifest), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
