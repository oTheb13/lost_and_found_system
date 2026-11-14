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
