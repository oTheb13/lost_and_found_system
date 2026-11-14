-- LFMS schema (MySQL 8 / MariaDB 10.5+). Rebuilds the DB from scratch: DEV ONLY.
DROP DATABASE IF EXISTS lfms;
CREATE DATABASE lfms CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE lfms;

CREATE TABLE app_user (
  user_id       INT AUTO_INCREMENT PRIMARY KEY,
  first_name    VARCHAR(50)  NOT NULL,
  last_name     VARCHAR(50)  NOT NULL,
  email         VARCHAR(100) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role          ENUM('student','faculty','staff','personnel','admin') NOT NULL DEFAULT 'student'
);

CREATE TABLE category (
  category_id   INT AUTO_INCREMENT PRIMARY KEY,
  category_name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE location (
  location_id      INT AUTO_INCREMENT PRIMARY KEY,
  location_name    VARCHAR(100) NOT NULL UNIQUE,
  building_or_zone VARCHAR(100) NOT NULL
);

CREATE TABLE storage_location (
  storage_id   INT AUTO_INCREMENT PRIMARY KEY,
  office_name  VARCHAR(100) NOT NULL UNIQUE,
  contact_info VARCHAR(100)
);

CREATE TABLE lost_report (
  lost_id                 INT AUTO_INCREMENT PRIMARY KEY,
  user_id                 INT NOT NULL,
  category_id             INT NOT NULL,
  location_id             INT NOT NULL,
  item_name               VARCHAR(100) NOT NULL,
  description             TEXT,
  distinguishing_features TEXT,                      -- PRIVATE: never in public views
  color                   VARCHAR(30),
  brand                   VARCHAR(50),
  date_lost               DATETIME NOT NULL,
  photo_url               VARCHAR(255),
  status                  ENUM('Lost','Matched','Resolved') NOT NULL DEFAULT 'Lost',
  created_at              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id)     REFERENCES app_user(user_id),
  FOREIGN KEY (category_id) REFERENCES category(category_id),
  FOREIGN KEY (location_id) REFERENCES location(location_id),
  INDEX idx_lost_status (status),
  INDEX idx_lost_date (date_lost),
  INDEX idx_lost_cat_loc (category_id, location_id)
);

CREATE TABLE found_report (
  found_id        INT AUTO_INCREMENT PRIMARY KEY,
  finder_user_id  INT NOT NULL,
  category_id     INT NOT NULL,
  location_id     INT NOT NULL,
  storage_id      INT NULL,                          -- NULL until item is turned in
  description     TEXT,                              -- PRIVATE
  color           VARCHAR(30),
  brand           VARCHAR(50),
  date_found      DATETIME NOT NULL,
  photo_url       VARCHAR(255),
  status          ENUM('Reported','Stored','Claimed','Returned') NOT NULL DEFAULT 'Reported',
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (finder_user_id) REFERENCES app_user(user_id),
  FOREIGN KEY (category_id)    REFERENCES category(category_id),
  FOREIGN KEY (location_id)    REFERENCES location(location_id),
  FOREIGN KEY (storage_id)     REFERENCES storage_location(storage_id),
  INDEX idx_found_status (status),
  INDEX idx_found_date (date_found),
  INDEX idx_found_cat_loc (category_id, location_id)
);

CREATE TABLE claim (
  claim_id              INT AUTO_INCREMENT PRIMARY KEY,
  found_id              INT NOT NULL,
  lost_id               INT NULL,
  claimant_user_id      INT NOT NULL,
  proof_of_ownership    TEXT NOT NULL,
  status                ENUM('Pending','Approved','Rejected') NOT NULL DEFAULT 'Pending',
  reviewed_by_admin_id  INT NULL,
  claimed_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  released_at           DATETIME NULL,
  FOREIGN KEY (found_id)             REFERENCES found_report(found_id),
  FOREIGN KEY (lost_id)              REFERENCES lost_report(lost_id),
  FOREIGN KEY (claimant_user_id)     REFERENCES app_user(user_id),
  FOREIGN KEY (reviewed_by_admin_id) REFERENCES app_user(user_id),
  CONSTRAINT chk_release CHECK (released_at IS NULL OR status = 'Approved'),
  INDEX idx_claim_status (status)
);

-- ERD calls this MATCH, but MATCH is a reserved word in MySQL.
CREATE TABLE item_match (
  match_id    INT AUTO_INCREMENT PRIMARY KEY,
  lost_id     INT NOT NULL,
  found_id    INT NOT NULL,
  match_score DECIMAL(5,2) NOT NULL,
  status      ENUM('Suggested','Confirmed','Dismissed') NOT NULL DEFAULT 'Suggested',
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_pair (lost_id, found_id),
  FOREIGN KEY (lost_id)  REFERENCES lost_report(lost_id),
  FOREIGN KEY (found_id) REFERENCES found_report(found_id)
);

CREATE TABLE verification_question (
  question_id   INT AUTO_INCREMENT PRIMARY KEY,
  found_id      INT NOT NULL,
  question_text VARCHAR(255) NOT NULL,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (found_id) REFERENCES found_report(found_id)
);

CREATE TABLE verification_answer (
  answer_id    INT AUTO_INCREMENT PRIMARY KEY,
  claim_id     INT NOT NULL,
  question_id  INT NOT NULL,
  answer_text  VARCHAR(500) NOT NULL,
  submitted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_answer (claim_id, question_id),
  FOREIGN KEY (claim_id)    REFERENCES claim(claim_id),
  FOREIGN KEY (question_id) REFERENCES verification_question(question_id)
);

CREATE TABLE notification (
  notification_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id         INT NOT NULL,
  message         VARCHAR(255) NOT NULL,
  is_read         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES app_user(user_id),
  INDEX idx_notif_user (user_id, is_read)
);

CREATE TABLE activity_log (
  log_id               INT AUTO_INCREMENT PRIMARY KEY,
  entity_type          ENUM('lost_report','found_report','claim','item_match') NOT NULL,
  entity_id            INT NOT NULL,
  action_taken         VARCHAR(100) NOT NULL,
  performed_by_user_id INT NULL,
  logged_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,   -- ERD: "timestamp"
  FOREIGN KEY (performed_by_user_id) REFERENCES app_user(user_id),
  INDEX idx_log_entity (entity_type, entity_id)
);
USE lfms;

-- PUBLIC listings: no description / color / brand / distinguishing features
CREATE OR REPLACE VIEW v_public_found AS
SELECT f.found_id, c.category_name, l.location_name, f.date_found, f.photo_url, f.status
FROM found_report f
JOIN category c ON c.category_id = f.category_id
JOIN location l ON l.location_id = f.location_id
WHERE f.status IN ('Reported','Stored');

CREATE OR REPLACE VIEW v_public_lost AS
SELECT r.lost_id, r.item_name, c.category_name, l.location_name, r.date_lost, r.photo_url, r.status
FROM lost_report r
JOIN category c ON c.category_id = r.category_id
JOIN location l ON l.location_id = r.location_id
WHERE r.status <> 'Resolved';

-- ADMIN dashboard
CREATE OR REPLACE VIEW v_admin_summary AS
SELECT
  (SELECT COUNT(*) FROM lost_report)                                        AS total_lost,
  (SELECT COUNT(*) FROM found_report)                                       AS total_found,
  (SELECT COUNT(*) FROM found_report WHERE status IN ('Reported','Stored')) AS unclaimed_items,
  (SELECT COUNT(*) FROM claim WHERE status = 'Pending')                     AS pending_claims,
  (SELECT COUNT(*) FROM found_report WHERE status = 'Returned')             AS returned_items;

CREATE OR REPLACE VIEW v_pending_claims AS
SELECT cl.claim_id, cl.found_id, CONCAT(u.first_name,' ',u.last_name) AS claimant,
       cl.proof_of_ownership, cl.claimed_at
FROM claim cl JOIN app_user u ON u.user_id = cl.claimant_user_id
WHERE cl.status = 'Pending';

CREATE OR REPLACE VIEW v_top_locations AS
SELECT l.location_name, COUNT(*) AS report_count
FROM (SELECT location_id FROM lost_report UNION ALL SELECT location_id FROM found_report) x
JOIN location l ON l.location_id = x.location_id
GROUP BY l.location_id, l.location_name
ORDER BY report_count DESC;

CREATE OR REPLACE VIEW v_top_categories AS
SELECT c.category_name, COUNT(*) AS report_count
FROM (SELECT category_id FROM lost_report UNION ALL SELECT category_id FROM found_report) x
JOIN category c ON c.category_id = x.category_id
GROUP BY c.category_id, c.category_name
ORDER BY report_count DESC;

-- Monthly analytics: recovery rate + avg hours from report to release
CREATE OR REPLACE VIEW v_monthly_recovery AS
SELECT DATE_FORMAT(f.created_at, '%Y-%m') AS month,
       COUNT(*) AS found_reports,
       SUM(f.status = 'Returned') AS returned,
       ROUND(100 * SUM(f.status = 'Returned') / COUNT(*), 1) AS recovery_rate_pct,
       ROUND(AVG(TIMESTAMPDIFF(HOUR, f.created_at, c.released_at)), 1) AS avg_hours_to_return
FROM found_report f
LEFT JOIN claim c ON c.found_id = f.found_id AND c.released_at IS NOT NULL
GROUP BY DATE_FORMAT(f.created_at, '%Y-%m');
USE lfms;
DELIMITER $$

-- Weighted score (max 100): category 40, location 25/10, date 15/8, color 10, brand 10
-- Suggest found items for ONE lost report
CREATE PROCEDURE sp_suggest_matches_for_lost(IN p_lost_id INT, IN p_min_score DECIMAL(5,2))
BEGIN
  INSERT INTO item_match (lost_id, found_id, match_score)
  SELECT lost_id, found_id, score FROM (
    SELECT r.lost_id, f.found_id,
      (CASE WHEN f.category_id = r.category_id THEN 40 ELSE 0 END)
    + (CASE WHEN f.location_id = r.location_id THEN 25
            WHEN lf.building_or_zone = lr.building_or_zone THEN 10 ELSE 0 END)
    + (CASE WHEN DATEDIFF(f.date_found, r.date_lost) <= 3 THEN 15
            WHEN DATEDIFF(f.date_found, r.date_lost) <= 7 THEN 8 ELSE 0 END)
    + (CASE WHEN r.color IS NOT NULL AND LOWER(r.color) = LOWER(f.color) THEN 10 ELSE 0 END)
    + (CASE WHEN r.brand IS NOT NULL AND LOWER(r.brand) = LOWER(f.brand) THEN 10 ELSE 0 END) AS score
    FROM lost_report r
    JOIN found_report f ON f.date_found >= DATE(r.date_lost)
                       AND f.status IN ('Reported','Stored')
    JOIN location lr ON lr.location_id = r.location_id
    JOIN location lf ON lf.location_id = f.location_id
    WHERE r.lost_id = p_lost_id AND r.status IN ('Lost','Matched')
  ) s
  WHERE score >= p_min_score
  ON DUPLICATE KEY UPDATE match_score = VALUES(match_score);
END$$

-- Same logic for ONE new found report vs all open lost reports
CREATE PROCEDURE sp_suggest_matches_for_found(IN p_found_id INT, IN p_min_score DECIMAL(5,2))
BEGIN
  INSERT INTO item_match (lost_id, found_id, match_score)
  SELECT lost_id, found_id, score FROM (
    SELECT r.lost_id, f.found_id,
      (CASE WHEN f.category_id = r.category_id THEN 40 ELSE 0 END)
    + (CASE WHEN f.location_id = r.location_id THEN 25
            WHEN lf.building_or_zone = lr.building_or_zone THEN 10 ELSE 0 END)
    + (CASE WHEN DATEDIFF(f.date_found, r.date_lost) <= 3 THEN 15
            WHEN DATEDIFF(f.date_found, r.date_lost) <= 7 THEN 8 ELSE 0 END)
    + (CASE WHEN r.color IS NOT NULL AND LOWER(r.color) = LOWER(f.color) THEN 10 ELSE 0 END)
    + (CASE WHEN r.brand IS NOT NULL AND LOWER(r.brand) = LOWER(f.brand) THEN 10 ELSE 0 END) AS score
    FROM found_report f
    JOIN lost_report r ON f.date_found >= DATE(r.date_lost)
                      AND r.status IN ('Lost','Matched')
    JOIN location lr ON lr.location_id = r.location_id
    JOIN location lf ON lf.location_id = f.location_id
    WHERE f.found_id = p_found_id
  ) s
  WHERE score >= p_min_score
  ON DUPLICATE KEY UPDATE match_score = VALUES(match_score);
END$$

DELIMITER ;
USE lfms;
-- App should run `SET @current_user_id = <id>;` on its connection so the audit trail knows who acted.
DELIMITER $$

-- ---------- LOST REPORT ----------
CREATE TRIGGER trg_lost_ai AFTER INSERT ON lost_report FOR EACH ROW
BEGIN
  INSERT INTO activity_log (entity_type, entity_id, action_taken, performed_by_user_id)
  VALUES ('lost_report', NEW.lost_id, 'Lost report submitted', NEW.user_id);
  CALL sp_suggest_matches_for_lost(NEW.lost_id, 40);
END$$

CREATE TRIGGER trg_lost_au AFTER UPDATE ON lost_report FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    INSERT INTO activity_log (entity_type, entity_id, action_taken, performed_by_user_id)
    VALUES ('lost_report', NEW.lost_id, CONCAT('Status: ', OLD.status, ' -> ', NEW.status), @current_user_id);
    INSERT INTO notification (user_id, message)
    VALUES (NEW.user_id, CONCAT('Your lost report #', NEW.lost_id, ' is now ', NEW.status));
  END IF;
END$$

-- ---------- FOUND REPORT ----------
CREATE TRIGGER trg_found_ai AFTER INSERT ON found_report FOR EACH ROW
BEGIN
  INSERT INTO activity_log (entity_type, entity_id, action_taken, performed_by_user_id)
  VALUES ('found_report', NEW.found_id, 'Found report submitted', NEW.finder_user_id);
  CALL sp_suggest_matches_for_found(NEW.found_id, 40);
END$$

CREATE TRIGGER trg_found_au AFTER UPDATE ON found_report FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    INSERT INTO activity_log (entity_type, entity_id, action_taken, performed_by_user_id)
    VALUES ('found_report', NEW.found_id, CONCAT('Status: ', OLD.status, ' -> ', NEW.status), @current_user_id);
  END IF;
END$$

-- ---------- MATCH ----------
CREATE TRIGGER trg_match_ai AFTER INSERT ON item_match FOR EACH ROW
BEGIN
  INSERT INTO activity_log (entity_type, entity_id, action_taken)
  VALUES ('item_match', NEW.match_id, CONCAT('Match suggested (score ', NEW.match_score, ')'));
  INSERT INTO notification (user_id, message)
  SELECT user_id, CONCAT('Possible match found for your lost report #', NEW.lost_id)
  FROM lost_report WHERE lost_id = NEW.lost_id;
END$$

CREATE TRIGGER trg_match_au AFTER UPDATE ON item_match FOR EACH ROW
BEGIN
  IF NEW.status = 'Confirmed' AND OLD.status <> 'Confirmed' THEN
    UPDATE lost_report SET status = 'Matched' WHERE lost_id = NEW.lost_id AND status = 'Lost';
  END IF;
END$$

-- ---------- CLAIM ----------
CREATE TRIGGER trg_claim_ai AFTER INSERT ON claim FOR EACH ROW
BEGIN
  INSERT INTO activity_log (entity_type, entity_id, action_taken, performed_by_user_id)
  VALUES ('claim', NEW.claim_id, 'Claim submitted', NEW.claimant_user_id);
END$$

CREATE TRIGGER trg_claim_au AFTER UPDATE ON claim FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    INSERT INTO activity_log (entity_type, entity_id, action_taken, performed_by_user_id)
    VALUES ('claim', NEW.claim_id, CONCAT('Claim ', NEW.status), NEW.reviewed_by_admin_id);
    INSERT INTO notification (user_id, message)
    VALUES (NEW.claimant_user_id, CONCAT('Your claim #', NEW.claim_id, ' was ', LOWER(NEW.status)));
    IF NEW.status = 'Approved' THEN
      UPDATE found_report SET status = 'Claimed' WHERE found_id = NEW.found_id;
    END IF;
  END IF;

  IF OLD.released_at IS NULL AND NEW.released_at IS NOT NULL THEN
    INSERT INTO activity_log (entity_type, entity_id, action_taken, performed_by_user_id)
    VALUES ('claim', NEW.claim_id, 'Item released to owner', NEW.reviewed_by_admin_id);
    UPDATE found_report SET status = 'Returned' WHERE found_id = NEW.found_id;
    IF NEW.lost_id IS NOT NULL THEN
      UPDATE lost_report SET status = 'Resolved' WHERE lost_id = NEW.lost_id;
    END IF;
  END IF;
END$$

DELIMITER ;
USE lfms;
-- SAMPLE DATA ONLY. Replace locations with the official UP Mindanao list.

INSERT INTO category (category_name) VALUES
('Gadgets'),('IDs & Cards'),('Clothing'),('Accessories'),('Bags'),('Books & Stationery'),('Keys'),('Wallets'),('Umbrellas'),('Others');

INSERT INTO location (location_name, building_or_zone) VALUES
('Library','Academic Zone'),
('Administration Building','Admin Zone'),
('Canteen','Common Areas'),
('Gymnasium','Sports Zone'),
('Lecture Hall 1','Academic Zone');

INSERT INTO storage_location (office_name, contact_info) VALUES
('Security Office','local 101'),
('Office of Student Affairs','local 102');

INSERT INTO app_user (first_name,last_name,email,password_hash,role) VALUES
('Ana','Admin','admin@example.com','CHANGE_ME','admin'),
('Juan','Dela Cruz','juan@example.com','CHANGE_ME','student'),
('Maria','Santos','maria@example.com','CHANGE_ME','student'),
('Pedro','Reyes','pedro@example.com','CHANGE_ME','faculty');

-- Lost: black umbrella near library (the proposal's example)
INSERT INTO lost_report (user_id,category_id,location_id,item_name,description,distinguishing_features,color,brand,date_lost)
VALUES (2,9,1,'Black umbrella','Foldable umbrella','Initials JD on the handle','Black','Fulton','2026-11-10 14:00:00'),
       (3,1,3,'Phone','Smartphone with cracked corner','Anime sticker on case','Blue','Samsung','2026-11-09 12:30:00');

-- Found: matches the umbrella (should score high), plus an unrelated item
INSERT INTO found_report (finder_user_id,category_id,location_id,storage_id,description,color,brand,date_found,status)
VALUES (4,9,1,1,'Foldable umbrella, initials on handle','Black','Fulton','2026-11-11 09:00:00','Stored'),
       (4,7,4,2,'Set of keys with red lanyard','Silver',NULL,'2026-11-11 16:00:00','Stored');

INSERT INTO verification_question (found_id,question_text) VALUES
(1,'What initials are on the handle?'),
(1,'What brand is the umbrella?');
