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
