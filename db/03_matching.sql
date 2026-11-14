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
