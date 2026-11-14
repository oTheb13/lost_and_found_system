"""LFMS bare-bones Flask app. Run: python app.py  ->  http://127.0.0.1:5000"""
import os
import uuid
from datetime import datetime
from functools import wraps

import pymysql
from flask import (Flask, abort, flash, redirect, render_template, request,
                   session, url_for)

import db

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "dev-only-change-me")
app.config["MAX_CONTENT_LENGTH"] = 5 * 1024 * 1024          # 5 MB uploads
UPLOAD_DIR = os.path.join(app.root_path, "static", "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)
ALLOWED_EXT = {"png", "jpg", "jpeg", "gif", "webp"}
app.teardown_appcontext(db.close_db)


# ---------------------------------------------------------------- helpers
def parse_dt(value):
    """'2026-11-10T14:00' (HTML datetime-local) -> '2026-11-10 14:00:00', or None if invalid."""
    value = (value or "").strip().replace("T", " ")
    if len(value) == 16:
        value += ":00"
    try:
        datetime.strptime(value, "%Y-%m-%d %H:%M:%S")
        return value
    except ValueError:
        return None


def save_photo(file):
    """Save an uploaded image, return the path relative to /static (or None)."""
    if not file or not file.filename:
        return None
    ext = file.filename.rsplit(".", 1)[-1].lower()
    if ext not in ALLOWED_EXT:
        return None
    name = f"{uuid.uuid4().hex}.{ext}"
    file.save(os.path.join(UPLOAD_DIR, name))
    return f"uploads/{name}"


def lookups():
    return dict(
        cats=db.query("SELECT * FROM category ORDER BY category_name"),
        locs=db.query("SELECT * FROM location ORDER BY location_name"),
    )


def login_required(f):
    @wraps(f)
    def wrapper(*a, **k):
        if not session.get("user_id"):
            return redirect(url_for("login", next=request.path))
        return f(*a, **k)
    return wrapper


def admin_required(f):
    @wraps(f)
    def wrapper(*a, **k):
        if not session.get("user_id"):
            return redirect(url_for("login", next=request.path))
        if session.get("role") not in ("admin", "personnel"):
            abort(403)
        return f(*a, **k)
    return wrapper


@app.context_processor
def inject_user():
    uid = session.get("user_id")
    if not uid:
        return {"me": None, "unread": 0}
    me = db.query("SELECT user_id, first_name, role FROM app_user WHERE user_id=%s", (uid,), one=True)
    if not me:
        session.clear()
        return {"me": None, "unread": 0}
    n = db.query("SELECT COUNT(*) AS n FROM notification WHERE user_id=%s AND is_read=0", (uid,), one=True)["n"]
    return {"me": me, "unread": n}


@app.errorhandler(pymysql.err.IntegrityError)
def bad_data(e):
    db.get_db().rollback()
    return render_template("error.html", msg=f"Invalid data: {e.args[-1]}"), 400


@app.errorhandler(403)
def forbidden(e):
    return render_template("error.html", msg="Admins only."), 403


@app.errorhandler(404)
def not_found(e):
    return render_template("error.html", msg="Not found."), 404


# ------------------------------------------------------- auth (DEV STUB)
# Pick-a-user login so you can test every role. Replace with real login
# (check password_hash with werkzeug.security) before any real use.
@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        u = db.query("SELECT user_id, role FROM app_user WHERE user_id=%s", (request.form.get("user_id"),), one=True)
        if u:
            session["user_id"], session["role"] = u["user_id"], u["role"]
            nxt = request.args.get("next", "")
            return redirect(nxt if nxt.startswith("/") and not nxt.startswith("//") else url_for("index"))
    users = db.query("SELECT user_id, first_name, last_name, role FROM app_user ORDER BY user_id")
    return render_template("login.html", users=users)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("index"))


# ------------------------------------------- search + filtering (public)
@app.route("/")
def index():
    a = request.args
    sql = """
      SELECT * FROM (
        SELECT 'lost' AS kind, lost_id AS id, item_name AS title, category_name, location_name,
               date_lost AS event_date, photo_url, status FROM v_public_lost
        UNION ALL
        SELECT 'found', found_id, CONCAT(category_name, ' (found item)'), category_name, location_name,
               date_found, photo_url, status FROM v_public_found
      ) x WHERE 1=1"""
    args = []
    if a.get("kind") in ("lost", "found"):
        sql += " AND kind=%s"; args.append(a["kind"])
    if a.get("q", "").strip():
        # Found items: only PUBLIC fields are searchable. Searching the hidden description
        # would let someone guess private details by trial and error.
        like = f"%{a['q'].strip()}%"
        sql += " AND (title LIKE %s OR category_name LIKE %s OR location_name LIKE %s)"; args += [like] * 3
    if a.get("category"):
        sql += " AND category_name=%s"; args.append(a["category"])
    if a.get("location"):
        sql += " AND location_name=%s"; args.append(a["location"])
    if a.get("status"):
        sql += " AND status=%s"; args.append(a["status"])
    if a.get("date_from"):
        sql += " AND event_date >= %s"; args.append(a["date_from"])
    if a.get("date_to"):
        sql += " AND event_date < DATE_ADD(%s, INTERVAL 1 DAY)"; args.append(a["date_to"])
    sql += " ORDER BY event_date DESC"
    return render_template("index.html", items=db.query(sql, args), f=a, **lookups())


# --------------------------------------------------------- lost reports
@app.route("/lost/new", methods=["GET", "POST"])
@login_required
def lost_new():
    if request.method == "POST":
        f = request.form
        when = parse_dt(f.get("date_lost"))
        if not f.get("item_name", "").strip() or not when:
            flash("Item name and a valid date are required.")
        else:
            db.execute(
                """INSERT INTO lost_report (user_id, category_id, location_id, item_name, description,
                       distinguishing_features, color, brand, date_lost, photo_url)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                (session["user_id"], f["category_id"], f["location_id"], f["item_name"].strip(),
                 f.get("description"), f.get("distinguishing_features"),
                 f.get("color") or None, f.get("brand") or None, when,
                 save_photo(request.files.get("photo"))))
            db.commit()                      # trigger auto-suggests matches here
            flash("Lost report submitted. Possible matches appear under My items.")
            return redirect(url_for("my"))
    return render_template("lost_form.html", **lookups())


# -------------------------------------------------------- found reports
@app.route("/found/new", methods=["GET", "POST"])
@login_required
def found_new():
    if request.method == "POST":
        f = request.form
        when = parse_dt(f.get("date_found"))
        if not when:
            flash("A valid date is required.")
        else:
            storage = f.get("storage_id") or None
            fid = db.execute(
                """INSERT INTO found_report (finder_user_id, category_id, location_id, storage_id,
                       description, color, brand, date_found, photo_url, status)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                (session["user_id"], f["category_id"], f["location_id"], storage, f.get("description"),
                 f.get("color") or None, f.get("brand") or None, when,
                 save_photo(request.files.get("photo")), "Stored" if storage else "Reported"))
            for i in (1, 2, 3):              # verification questions the owner must answer
                q = f.get(f"question{i}", "").strip()
                if q:
                    db.execute("INSERT INTO verification_question (found_id, question_text) VALUES (%s,%s)", (fid, q))
            db.commit()
            flash("Found report submitted.")
            return redirect(url_for("my"))
    return render_template("found_form.html", storages=db.query("SELECT * FROM storage_location"), **lookups())


@app.route("/found/<int:found_id>")
def found_detail(found_id):
    item = db.query("SELECT * FROM v_public_found WHERE found_id=%s", (found_id,), one=True)   # public view only
    if not item:
        abort(404)
    questions = db.query("SELECT question_id, question_text FROM verification_question WHERE found_id=%s ORDER BY question_id", (found_id,))
    mine = []
    if session.get("user_id"):
        mine = db.query("SELECT lost_id, item_name FROM lost_report WHERE user_id=%s AND status IN ('Lost','Matched')", (session["user_id"],))
    return render_template("found_detail.html", item=item, questions=questions, mine=mine)


@app.route("/found/<int:found_id>/claim", methods=["POST"])
@login_required
def claim_submit(found_id):
    uid, f = session["user_id"], request.form
    item = db.query("SELECT finder_user_id, status FROM found_report WHERE found_id=%s", (found_id,), one=True)
    if not item or item["status"] not in ("Reported", "Stored"):
        abort(404)
    back = redirect(url_for("found_detail", found_id=found_id))
    if item["finder_user_id"] == uid:
        flash("You can't claim an item you reported as found."); return back
    if db.query("SELECT 1 FROM claim WHERE found_id=%s AND claimant_user_id=%s AND status='Pending'", (found_id, uid)):
        flash("You already have a pending claim on this item."); return back
    questions = db.query("SELECT question_id FROM verification_question WHERE found_id=%s", (found_id,))
    answers = {q["question_id"]: f.get(f"answer_{q['question_id']}", "").strip() for q in questions}
    if not f.get("proof", "").strip() or not all(answers.values()):
        flash("Proof of ownership and all verification answers are required."); return back
    lost_id = f.get("lost_id") or None
    if lost_id and not db.query("SELECT 1 FROM lost_report WHERE lost_id=%s AND user_id=%s", (lost_id, uid)):
        lost_id = None
    cid = db.execute("INSERT INTO claim (found_id, lost_id, claimant_user_id, proof_of_ownership) VALUES (%s,%s,%s,%s)",
                     (found_id, lost_id, uid, f["proof"].strip()))
    for qid, ans in answers.items():
        db.execute("INSERT INTO verification_answer (claim_id, question_id, answer_text) VALUES (%s,%s,%s)", (cid, qid, ans))
    db.commit()
    flash("Claim submitted. An administrator will review it.")
    return redirect(url_for("my"))


# ---------------------------------------------------------------- my items
@app.route("/my")
@login_required
def my():
    uid = session["user_id"]
    data = dict(
        lost=db.query("SELECT lost_id, item_name, status, date_lost FROM lost_report WHERE user_id=%s ORDER BY created_at DESC", (uid,)),
        found=db.query("""SELECT f.found_id, c.category_name, f.status, f.date_found FROM found_report f
                          JOIN category c ON c.category_id=f.category_id WHERE f.finder_user_id=%s ORDER BY f.created_at DESC""", (uid,)),
        matches=db.query("""SELECT m.match_id, m.match_score, r.item_name, pf.found_id, pf.category_name,
                                   pf.location_name, pf.date_found
                            FROM item_match m JOIN lost_report r ON r.lost_id=m.lost_id
                            JOIN v_public_found pf ON pf.found_id=m.found_id
                            WHERE r.user_id=%s AND m.status='Suggested' ORDER BY m.match_score DESC""", (uid,)),
        claims=db.query("SELECT claim_id, found_id, status, claimed_at, released_at FROM claim WHERE claimant_user_id=%s ORDER BY claimed_at DESC", (uid,)),
        notes=db.query("SELECT message, is_read, created_at FROM notification WHERE user_id=%s ORDER BY notification_id DESC LIMIT 30", (uid,)),
    )
    db.execute("UPDATE notification SET is_read=1 WHERE user_id=%s AND is_read=0", (uid,))
    db.commit()
    return render_template("my.html", **data)


@app.route("/match/<int:match_id>/<action>", methods=["POST"])
@login_required
def match_action(match_id, action):
    if action not in ("confirm", "dismiss"):
        abort(404)
    m = db.query("""SELECT m.match_id FROM item_match m JOIN lost_report r ON r.lost_id=m.lost_id
                    WHERE m.match_id=%s AND r.user_id=%s""", (match_id, session["user_id"]), one=True)
    if not m:
        abort(404)
    db.execute("UPDATE item_match SET status=%s WHERE match_id=%s",
               ("Confirmed" if action == "confirm" else "Dismissed", match_id))
    db.commit()
    return redirect(url_for("my"))


# ------------------------------------------------------------------- admin
@app.route("/admin")
@admin_required
def admin():
    return render_template(
        "admin.html",
        summary=db.query("SELECT * FROM v_admin_summary", one=True),
        top_locs=db.query("SELECT * FROM v_top_locations LIMIT 5"),
        top_cats=db.query("SELECT * FROM v_top_categories LIMIT 5"),
        monthly=db.query("SELECT * FROM v_monthly_recovery ORDER BY month DESC"),
        pending=db.query("SELECT * FROM v_pending_claims ORDER BY claimed_at"),
        to_release=db.query("""SELECT cl.claim_id, cl.found_id, CONCAT(u.first_name,' ',u.last_name) AS claimant
                               FROM claim cl JOIN app_user u ON u.user_id=cl.claimant_user_id
                               WHERE cl.status='Approved' AND cl.released_at IS NULL"""),
        unstored=db.query("""SELECT f.found_id, c.category_name, l.location_name, f.date_found
                             FROM found_report f JOIN category c ON c.category_id=f.category_id
                             JOIN location l ON l.location_id=f.location_id WHERE f.status='Reported'"""),
        storages=db.query("SELECT * FROM storage_location"),
        log=db.query("SELECT * FROM activity_log ORDER BY log_id DESC LIMIT 15"),
    )


@app.route("/admin/claim/<int:claim_id>")
@admin_required
def claim_review(claim_id):
    claim = db.query("""SELECT cl.*, CONCAT(u.first_name,' ',u.last_name) AS claimant,
                               f.description AS found_description, f.color AS found_color,
                               f.brand AS found_brand, f.status AS found_status
                        FROM claim cl JOIN app_user u ON u.user_id=cl.claimant_user_id
                        JOIN found_report f ON f.found_id=cl.found_id WHERE cl.claim_id=%s""", (claim_id,), one=True)
    if not claim:
        abort(404)
    qa = db.query("""SELECT q.question_text, a.answer_text FROM verification_question q
                     LEFT JOIN verification_answer a ON a.question_id=q.question_id AND a.claim_id=%s
                     WHERE q.found_id=%s ORDER BY q.question_id""", (claim_id, claim["found_id"]))
    lost = db.query("SELECT * FROM lost_report WHERE lost_id=%s", (claim["lost_id"],), one=True) if claim["lost_id"] else None
    return render_template("claim_review.html", c=claim, qa=qa, lost=lost)


@app.route("/admin/claim/<int:claim_id>/decide", methods=["POST"])
@admin_required
def claim_decide(claim_id):
    decision = request.form.get("decision")
    if decision not in ("Approved", "Rejected"):
        abort(400)
    claim = db.query("""SELECT cl.status, f.status AS found_status FROM claim cl
                        JOIN found_report f ON f.found_id=cl.found_id WHERE cl.claim_id=%s""", (claim_id,), one=True)
    if not claim or claim["status"] != "Pending":
        flash("That claim is not pending.")
    elif decision == "Approved" and claim["found_status"] not in ("Reported", "Stored"):
        flash("This item already has an approved claim.")
    else:
        db.execute("UPDATE claim SET status=%s, reviewed_by_admin_id=%s WHERE claim_id=%s",
                   (decision, session["user_id"], claim_id))
        db.commit()
        flash(f"Claim {decision.lower()}.")
    return redirect(url_for("claim_review", claim_id=claim_id))


@app.route("/admin/claim/<int:claim_id>/release", methods=["POST"])
@admin_required
def claim_release(claim_id):
    n = db.execute("UPDATE claim SET released_at=NOW() WHERE claim_id=%s AND status='Approved' AND released_at IS NULL", (claim_id,))
    db.commit()
    flash("Item released to owner." )
    return redirect(url_for("admin"))


@app.route("/admin/found/<int:found_id>/store", methods=["POST"])
@admin_required
def found_store(found_id):
    db.execute("UPDATE found_report SET storage_id=%s, status='Stored' WHERE found_id=%s AND status='Reported'",
               (request.form["storage_id"], found_id))
    db.commit()
    flash("Item marked as stored.")
    return redirect(url_for("admin"))


if __name__ == "__main__":
    app.run(debug=True)
