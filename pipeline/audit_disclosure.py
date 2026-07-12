#!/usr/bin/env python3
"""Empirically verify schema-v3 subcell/individual disclosure properties."""

from __future__ import annotations

import argparse
import gzip
import json
from pathlib import Path
import sqlite3

import build_chicago_pack as builder


def load_json_gzip(path: Path):
    with gzip.open(path, "rt", encoding="utf-8") as handle:
        return json.load(handle)


def load_json_lines_gzip(path: Path) -> list[dict[str, object]]:
    with gzip.open(path, "rt", encoding="utf-8") as handle:
        return [json.loads(line) for line in handle]


def audit(
    pack_path: Path,
    incident_snapshot: Path,
    boundary_snapshot: Path,
    mapping_path: Path,
) -> dict[str, object]:
    mapping, _ = builder.load_frozen_iucr_mapping(mapping_path)
    records = load_json_lines_gzip(incident_snapshot)
    neighborhoods = builder.prepare_neighborhoods(load_json_gzip(boundary_snapshot))
    raw_cells, expected_bands, disclosure, usable_records = builder.build_aggregate_cells(
        records, mapping, neighborhoods
    )

    connection = sqlite3.connect(f"file:{pack_path}?mode=ro", uri=True)
    try:
        columns = [row[1] for row in connection.execute("PRAGMA table_info(aggregate_cells)")]
        forbidden = [
            column
            for column in columns
            if any(fragment in column.lower() for fragment in ("total", "latitude", "longitude", "incident"))
        ]
        if forbidden:
            raise RuntimeError(f"prohibited disclosure columns present: {forbidden}")
        actual_bands = {
            (int(row[0]), int(row[1])): tuple(int(value) for value in row[2:6])
            for row in connection.execute(
                """SELECT cell_row,cell_column,assault_battery_band,robbery_band,
                          theft_band,motor_vehicle_theft_band FROM aggregate_cells"""
            )
        }
    finally:
        connection.close()
    if actual_bands != expected_bands:
        raise RuntimeError("shipped bands do not match the independently recomputed cell/category histogram")

    relocation_trials = 0
    for record in usable_records:
        original = builder.aggregate_cell_key(float(record["latitude"]), float(record["longitude"]))
        row, column = original
        for x_offset, y_offset in ((1.0, 1.0), (249.0, 249.0)):
            latitude, longitude = builder.local_latlon(
                column * builder.AGGREGATE_CELL_SIZE_M + x_offset,
                row * builder.AGGREGATE_CELL_SIZE_M + y_offset,
            )
            if builder.aggregate_cell_key(latitude, longitude) != original:
                raise RuntimeError("within-cell relocation changed the released cell")
            relocation_trials += 1

    singleton_cells = 0
    singleton_cells_released_as_zero = 0
    two_incident_cells = 0
    two_incident_cells_released_as_zero = 0
    positive_band_below_three = 0
    for key, raw_values in raw_cells.items():
        band_values = actual_bands[key]
        for index, raw_value in enumerate(raw_values):
            if raw_value == 1:
                singleton_cells += 1
                singleton_cells_released_as_zero += band_values[index] == 0
            if raw_value == 2:
                two_incident_cells += 1
                two_incident_cells_released_as_zero += band_values[index] == 0
            if band_values[index] > 0 and raw_value < 3:
                positive_band_below_three += 1
            if band_values[index] != builder.quantize_to_nearest_five(raw_value):
                raise RuntimeError(
                    f"band mismatch at {key} category {builder.ALLOWED_CATEGORIES[index]}"
                )

    if singleton_cells_released_as_zero != singleton_cells:
        raise RuntimeError("a singleton cell is distinguishable from a true zero")
    if two_incident_cells_released_as_zero != two_incident_cells:
        raise RuntimeError("a two-incident cell is distinguishable from a true zero")
    if positive_band_below_three:
        raise RuntimeError("a positive band reveals fewer than three incidents")

    return {
        "status": "pass",
        "source_events": len(usable_records),
        "fixed_domain_cells": len(actual_bands),
        "event_influence_max_cells": 1,
        "event_influence_max_categories": 1,
        "subcell_relocation_trials": relocation_trials,
        "all_post_eligibility_subcell_relocations_release_equivalent": True,
        "singleton_cells": singleton_cells,
        "singleton_cells_released_as_zero": singleton_cells_released_as_zero,
        "two_incident_cells": two_incident_cells,
        "two_incident_cells_released_as_zero": two_incident_cells_released_as_zero,
        "positive_band_minimum_true_count": 3,
        "exact_or_residual_total_released": False,
        "categories": list(builder.ALLOWED_CATEGORIES),
        "outside_official_boundary_coordinates_excluded": disclosure[
            "outside_city_coordinates_excluded"
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack", type=Path)
    parser.add_argument("incident_snapshot", type=Path)
    parser.add_argument("boundary_snapshot", type=Path)
    parser.add_argument("mapping", type=Path)
    args = parser.parse_args()
    print(
        json.dumps(
            audit(args.pack, args.incident_snapshot, args.boundary_snapshot, args.mapping),
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
