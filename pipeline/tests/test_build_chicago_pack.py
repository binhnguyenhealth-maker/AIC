from __future__ import annotations

import collections
import datetime as dt
import json
from pathlib import Path
import random
import sqlite3
import sys
import tempfile
import unittest
from unittest import mock


PIPELINE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PIPELINE_DIR))

import build_chicago_pack as builder  # noqa: E402


def square_geometry(min_lon: float, min_lat: float, max_lon: float, max_lat: float):
    return {
        "type": "MultiPolygon",
        "coordinates": [[[[min_lon, min_lat], [max_lon, min_lat], [max_lon, max_lat], [min_lon, max_lat], [min_lon, min_lat]]]],
    }


class ChicagoPackTests(unittest.TestCase):
    def test_boundary_geometry_rejects_unsupported_nonfinite_and_out_of_domain_input(self):
        valid = square_geometry(-87.90, 41.60, -87.50, 42.05)
        self.assertEqual(5, len(list(builder.iter_points(valid))))

        invalid_type = {"type": "GeometryCollection", "coordinates": []}
        with self.assertRaisesRegex(ValueError, "unsupported geometry type"):
            list(builder.iter_points(invalid_type))

        nonfinite = square_geometry(-87.90, 41.60, -87.50, float("inf"))
        with self.assertRaisesRegex(ValueError, "finite"):
            list(builder.iter_points(nonfinite))

        outside_chicago = square_geometry(-120.0, 41.60, -119.0, 42.05)
        with self.assertRaisesRegex(ValueError, "Chicago envelope"):
            list(builder.iter_points(outside_chicago))

    def test_boundary_geometry_rejects_excessive_complexity(self):
        ring = [[-87.7, 41.8]] * (builder.MAX_BOUNDARY_POINTS + 1)
        geometry = {"type": "Polygon", "coordinates": [ring]}
        with self.assertRaisesRegex(ValueError, "complexity limits"):
            list(builder.iter_points(geometry))

    def test_incident_pagination_rejects_repeated_full_page(self):
        repeated_page = [
            {
                "id": str(index + 1),
                "date": "2026-01-01T00:00:00.000",
                "iucr": "0560",
                "primary_type": "ASSAULT",
                "latitude": "41.8",
                "longitude": "-87.7",
            }
            for index in range(50_000)
        ]
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(
            builder, "request_json", side_effect=[repeated_page, repeated_page]
        ):
            with self.assertRaisesRegex(RuntimeError, "made no progress"):
                builder.download_incident_snapshot(
                    Path(directory) / "incidents.jsonl.gz",
                    dt.date(2025, 7, 1),
                    dt.date(2026, 7, 1),
                    ["0560"],
                    refresh=True,
                )

    def test_period_excludes_month_containing_newest_record(self):
        start, end = builder.derive_period("2026-07-02T00:00:00.000", 12)
        self.assertEqual("2025-07-01", start.isoformat())
        self.assertEqual("2026-07-01", end.isoformat())

    def test_exact_category_mapping(self):
        mapping, document = builder.load_frozen_iucr_mapping(PIPELINE_DIR / "iucr_mapping.json")
        self.assertEqual(86, len(mapping))
        self.assertEqual("assault_battery", mapping["0560"]["category"])
        self.assertEqual("robbery", mapping["031A"]["category"])
        self.assertEqual("theft", mapping["0870"]["category"])
        self.assertEqual("motor_vehicle_theft", mapping["0910"]["category"])
        self.assertEqual(len(mapping), len(set(mapping)))
        self.assertEqual(1, document["schema_version"])

    def test_included_iucr_must_match_frozen_primary_type(self):
        mapping, _ = builder.load_frozen_iucr_mapping(PIPELINE_DIR / "iucr_mapping.json")
        records = [
            {
                "id": "1", "date": "2026-01-15T12:30:00.000", "iucr": "0560",
                "primary_type": "ASSAULT", "latitude": "41.88", "longitude": "-87.63",
            }
        ]
        categories, grouped = builder.verify_download_counts(
            records, 1, mapping, dt.date(2025, 7, 1), dt.date(2026, 7, 1)
        )
        self.assertEqual({"assault_battery": 1}, categories)
        self.assertEqual([{"iucr": "0560", "primary_type": "ASSAULT", "count": 1}], grouped)
        records[0]["primary_type"] = "THEFT"
        with self.assertRaisesRegex(RuntimeError, "primary_type mismatch"):
            builder.verify_download_counts(records, 1, mapping)

    def test_occurrence_date_is_required_and_must_be_in_window(self):
        mapping, _ = builder.load_frozen_iucr_mapping(PIPELINE_DIR / "iucr_mapping.json")
        record = {
            "id": "1", "iucr": "0560", "primary_type": "ASSAULT",
            "latitude": "41.88", "longitude": "-87.63",
        }
        with self.assertRaisesRegex(RuntimeError, "omits occurrence date"):
            builder.verify_download_counts(
                [record], 1, mapping, dt.date(2025, 7, 1), dt.date(2026, 7, 1)
            )
        record["date"] = "2026-07-01T00:00:00.000"
        with self.assertRaisesRegex(RuntimeError, "outside frozen period"):
            builder.verify_download_counts(
                [record], 1, mapping, dt.date(2025, 7, 1), dt.date(2026, 7, 1)
            )

    def test_polygon_hole_membership(self):
        geometry = {
            "type": "Polygon",
            "coordinates": [
                [[0, 0], [4, 0], [4, 4], [0, 4], [0, 0]],
                [[1, 1], [3, 1], [3, 3], [1, 3], [1, 1]],
            ],
        }
        self.assertTrue(builder.point_in_geometry(0.5, 0.5, geometry))
        self.assertFalse(builder.point_in_geometry(2, 2, geometry))
        self.assertFalse(builder.point_in_geometry(5, 5, geometry))

    def test_percentile_and_nearest_five_are_deterministic(self):
        distribution = {0: 1, 10: 2, 20: 1}
        self.assertEqual(12.5, builder.percentile_for_count(0, distribution))
        self.assertEqual(50.0, builder.percentile_for_count(10, distribution))
        self.assertEqual(100.0, builder.percentile_for_count(999, distribution))
        self.assertEqual(70, builder.round_score_to_nearest_five(72.49))
        self.assertEqual(75, builder.round_score_to_nearest_five(72.5))
        self.assertEqual(0, builder.round_score_to_nearest_five(-1))
        self.assertEqual(100, builder.round_score_to_nearest_five(101))

    def test_haversine_radius_is_inclusive(self):
        destination = builder.destination_point(41.88, -87.63, 500, 0)
        distance = builder.haversine_m(41.88, -87.63, *destination)
        self.assertAlmostEqual(500.0, distance, places=5)

    def test_independent_nearest_five_bands_hide_singletons(self):
        self.assertEqual([0, 0, 0, 5, 5, 5, 5, 5, 10], [
            builder.quantize_to_nearest_five(value) for value in range(9)
        ])
        self.assertEqual(
            builder.quantize_to_nearest_five(0),
            builder.quantize_to_nearest_five(1),
        )
        self.assertEqual(
            builder.quantize_to_nearest_five(1),
            builder.quantize_to_nearest_five(2),
        )

    def test_subcell_positions_are_release_equivalent(self):
        first_lat, first_lon = builder.local_latlon(34 * 250 + 1, 12 * 250 + 1)
        moved_lat, moved_lon = builder.local_latlon(34 * 250 + 249, 12 * 250 + 249)
        cell = builder.aggregate_cell_key(first_lat, first_lon)
        self.assertEqual(cell, builder.aggregate_cell_key(moved_lat, moved_lon))
        first = {cell: (1, 0, 0, 0)}
        relocated = {builder.aggregate_cell_key(moved_lat, moved_lon): (1, 0, 0, 0)}
        first_bands = {key: tuple(builder.quantize_to_nearest_five(v) for v in values) for key, values in first.items()}
        relocated_bands = {key: tuple(builder.quantize_to_nearest_five(v) for v in values) for key, values in relocated.items()}
        self.assertEqual(first_bands, relocated_bands)
        self.assertEqual((0, 0, 0, 0), first_bands[cell])

        rng = random.Random(20260710)
        for _ in range(1_000):
            x = 34 * 250 + rng.uniform(0.001, 249.999)
            y = 12 * 250 + rng.uniform(0.001, 249.999)
            latitude, longitude = builder.local_latlon(x, y)
            self.assertEqual(cell, builder.aggregate_cell_key(latitude, longitude))

    def test_area_estimator_uses_fixed_integer_subcell_midpoints(self):
        # A 500 m circle around the center of a 250 m cell contains all 100
        # subcell midpoints in that cell, so its released band contributes fully.
        cells = {(0, 0): (5, 0, 0, 0)}
        numerators, total = builder.estimate_from_aggregate_cells(cells, 125.0, 125.0)
        self.assertEqual((500, 0, 0, 0), numerators)
        self.assertEqual(5, total)
        weights = builder.overlap_weights_for_snapped_dm(1250, 1250)
        self.assertEqual(100, dict(((row, column), hits) for row, column, hits in weights)[(0, 0)])

    def test_shipped_schema_is_private_and_pack_is_deterministic(self):
        geometry = square_geometry(-87.90, 41.60, -87.50, 42.05)
        neighborhood = {
            "id": 1,
            "name": "Fixture",
            "geometry": geometry,
            "min_lat": 41.60,
            "max_lat": 42.05,
            "min_lon": -87.90,
            "max_lon": -87.50,
            "centroid_lat": 41.825,
            "centroid_lon": -87.70,
        }
        aggregate_cells = {
            (1, 2): (0, 5, 10, 15),
            (1, 3): (0, 0, 0, 0),
        }
        distribution = collections.Counter({2: 1})
        metadata = {
            "schema_version": "1",
            "source_retrieved_at": "2026-07-10T00:00:00Z",
            "period_start": "2025-07-01",
            "period_end_exclusive": "2026-07-01",
            "source_through_date": "2026-06-30",
        }
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.sqlite"
            second = Path(directory) / "second.sqlite"
            builder.build_pack(first, aggregate_cells, [neighborhood], distribution, metadata)
            builder.build_pack(second, aggregate_cells, [neighborhood], distribution, metadata)
            self.assertEqual(builder.sha256_file(first), builder.sha256_file(second))
            connection = sqlite3.connect(first)
            try:
                tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                self.assertNotIn("incidents", tables)
                self.assertNotIn("reference_points", tables)
                columns = [row[1] for row in connection.execute("PRAGMA table_info(aggregate_cells)")]
                self.assertEqual(
                    [
                        "cell_row", "cell_column", "assault_battery_band", "robbery_band",
                        "theft_band", "motor_vehicle_theft_band",
                    ],
                    columns,
                )
                self.assertNotIn("total_count", columns)
                self.assertNotIn("percentile", columns)
                self.assertEqual(
                    0,
                    connection.execute(
                        """SELECT count(*) FROM aggregate_cells WHERE
                           assault_battery_band % 5 != 0 OR robbery_band % 5 != 0 OR
                           theft_band % 5 != 0 OR motor_vehicle_theft_band % 5 != 0"""
                    ).fetchone()[0],
                )
                schema = "\n".join(row[0] or "" for row in connection.execute("SELECT sql FROM sqlite_master"))
                for forbidden in ("case_number", "incident_id", "source_id", "address", "block", "timestamp", "incident_date"):
                    self.assertNotIn(forbidden, schema.lower())
                serialized = json.dumps(connection.execute("SELECT * FROM aggregate_cells").fetchall())
                self.assertNotIn("source-id", serialized)
                self.assertEqual(1, connection.execute("SELECT count(*) FROM city_boundary").fetchone()[0])
            finally:
                connection.close()

    def test_canonical_category_order_lands_in_named_sqlite_columns(self):
        min_lat, min_lon = builder.local_latlon(2_000, 2_000)
        max_lat, max_lon = builder.local_latlon(4_000, 4_000)
        geometry = square_geometry(min_lon, min_lat, max_lon, max_lat)
        neighborhood = {
            "id": 1,
            "name": "Fixture",
            "geometry": geometry,
            "min_lat": min_lat,
            "max_lat": max_lat,
            "min_lon": min_lon,
            "max_lon": max_lon,
            "centroid_lat": (min_lat + max_lat) / 2,
            "centroid_lon": (min_lon + max_lon) / 2,
        }
        mapping = {
            "A001": {"category": "assault_battery"},
            "R001": {"category": "robbery"},
            "T001": {"category": "theft"},
            "M001": {"category": "motor_vehicle_theft"},
        }
        records = []
        for code, column in (("A001", 10), ("R001", 11), ("T001", 12), ("M001", 13)):
            latitude, longitude = builder.local_latlon(column * 250 + 125, 10 * 250 + 125)
            for index in range(3):
                records.append(
                    {
                        "id": f"{code}-{index}",
                        "iucr": code,
                        "latitude": latitude,
                        "longitude": longitude,
                    }
                )
        _, bands, _, _ = builder.build_aggregate_cells(records, mapping, [neighborhood])
        expected = {
            (10, 10): (5, 0, 0, 0),
            (10, 11): (0, 5, 0, 0),
            (10, 12): (0, 0, 5, 0),
            (10, 13): (0, 0, 0, 5),
        }
        for key, values in expected.items():
            self.assertEqual(values, bands[key])

        with tempfile.TemporaryDirectory() as directory:
            pack = Path(directory) / "order.sqlite"
            builder.build_pack(pack, bands, [neighborhood], {0: 1}, {"schema_version": "3"})
            connection = sqlite3.connect(pack)
            try:
                for key, values in expected.items():
                    actual = connection.execute(
                        """SELECT assault_battery_band,robbery_band,theft_band,
                                  motor_vehicle_theft_band FROM aggregate_cells
                           WHERE cell_row=? AND cell_column=?""",
                        key,
                    ).fetchone()
                    self.assertEqual(values, actual)
            finally:
                connection.close()


if __name__ == "__main__":
    unittest.main()
