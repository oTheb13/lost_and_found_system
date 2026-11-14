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
