CREATE TABLE IF NOT EXISTS nord_vehicle_keys (
  id INT NOT NULL AUTO_INCREMENT,
  plate VARCHAR(20) NOT NULL,
  holder VARCHAR(64) NOT NULL,
  granted_by VARCHAR(64) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_plate (plate),
  INDEX idx_holder (holder),
  UNIQUE KEY uniq_plate_holder (plate, holder)
);

CREATE TABLE IF NOT EXISTS nord_vehicle_key_logs (
  id INT NOT NULL AUTO_INCREMENT,
  action VARCHAR(32) NOT NULL,
  plate VARCHAR(20) NOT NULL,
  actor VARCHAR(64) NULL,
  target VARCHAR(64) NULL,
  details TEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_plate (plate),
  INDEX idx_action (action)
);