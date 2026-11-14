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
