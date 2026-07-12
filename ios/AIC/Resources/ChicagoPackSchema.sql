-- The production artifact is generated outside the app and copied into this
-- resource directory as chicago_beta.sqlite. The app opens it read-only.
CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE aggregate_cells (
  cell_row INTEGER NOT NULL,
  cell_column INTEGER NOT NULL,
  assault_battery_band INTEGER NOT NULL CHECK (assault_battery_band >= 0 AND assault_battery_band % 5 = 0),
  robbery_band INTEGER NOT NULL CHECK (robbery_band >= 0 AND robbery_band % 5 = 0),
  theft_band INTEGER NOT NULL CHECK (theft_band >= 0 AND theft_band % 5 = 0),
  motor_vehicle_theft_band INTEGER NOT NULL CHECK (motor_vehicle_theft_band >= 0 AND motor_vehicle_theft_band % 5 = 0),
  PRIMARY KEY (cell_row, cell_column)
) WITHOUT ROWID;
CREATE TABLE reference_distribution (
  estimated_count INTEGER PRIMARY KEY,
  sample_count INTEGER NOT NULL CHECK (sample_count > 0)
);
CREATE TABLE neighborhood_centroids (
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  name TEXT NOT NULL
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
CREATE TABLE city_boundary (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  min_lat REAL NOT NULL,
  max_lat REAL NOT NULL,
  min_lon REAL NOT NULL,
  max_lon REAL NOT NULL,
  geometry_json TEXT NOT NULL
);
