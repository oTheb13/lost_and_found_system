"""End-to-end check of the whole flow. WARNING: writes rows. Rebuild the DB first
(run db/lfms_all.sql), run this once, rebuild again afterwards if you want clean data.
Usage:  python smoke_test.py"""
import io
import re
from app import app


def login(c, uid):
    c.post("/login", data={"user_id": uid})


def check(label, cond):
    print(("PASS  " if cond else "FAIL  ") + label)
    if not cond:
        raise SystemExit(1)


with app.test_client() as anon:
    r = anon.get("/")
    check("browse page loads", r.status_code == 200 and b"Black umbrella" in r.data)
    check("public listing hides private details", b"Initials" not in r.data and b"red lanyard" not in r.data)
    check("filter by kind=found", b"Black umbrella" not in anon.get("/?kind=found").data)
    check("filter by category", b"Umbrellas" in anon.get("/?category=Umbrellas").data and b"Smartphone" not in anon.get("/?category=Umbrellas").data)
    check("keyword search", b"Phone" in anon.get("/?q=phone").data)
    check("date range excludes old items", b"No" in anon.get("/?date_from=2030-01-01").data or b"0 result" in anon.get("/?date_from=2030-01-01").data)
    check("claim page needs login", b"Log in" in anon.get("/found/1").data)
    check("my page redirects when logged out", anon.get("/my").status_code == 302)
    check("admin blocked when logged out", anon.get("/admin").status_code == 302)

with app.test_client() as maria:                       # user 3: student with a lost phone
    login(maria, 3)
    check("student blocked from admin", maria.get("/admin").status_code == 403)
    r = maria.post("/found/new", data={"category_id": 1, "location_id": 3, "date_found": "2026-11-12T10:30",
                   "description": "Blue Samsung phone, anime sticker", "color": "Blue", "brand": "Samsung",
                   "storage_id": "", "question1": "What sticker is on the case?"})
    check("found report form saves", r.status_code == 302)
    r = maria.post("/found/1/claim", data={"proof": "", "answer_1": "", "answer_2": ""}, follow_redirects=True)
    check("empty proof/answers rejected", b"all verification answers are required" in r.data)

with app.test_client() as juan:                        # user 2: owner of the lost umbrella
    login(juan, 2)
    r = juan.post("/lost/new", data={"item_name": "Water bottle", "category_id": 10, "location_id": 1,
                  "date_lost": "2026-11-12T08:00", "description": "Steel", "distinguishing_features": "Dent on lid",
                  "color": "Green", "brand": ""}, follow_redirects=True)
    check("lost report saved", r.status_code == 200 and b"Water bottle" in r.data)
    r = juan.get("/my")
    check("my page shows suggested match for umbrella", b"Black umbrella" in r.data and b"100.0" in r.data)
    r = juan.get("/found/1")
    check("found detail shows verification questions, hides description", b"What initials" in r.data and b"Foldable" not in r.data)
    r = juan.post("/found/1/claim", data={"proof": "My initials are on it", "lost_id": 1,
                  "answer_1": "JD", "answer_2": "Fulton"}, follow_redirects=True)
    check("claim submitted", b"Claim submitted" in r.data)
    r = juan.post("/found/1/claim", data={"proof": "again", "answer_1": "x", "answer_2": "y"}, follow_redirects=True)
    check("duplicate pending claim blocked", b"already have a pending" in r.data)

with app.test_client() as pedro:                       # user 4 found the umbrella, can't claim own find
    login(pedro, 4)
    r = pedro.post("/found/1/claim", data={"proof": "mine?", "answer_1": "a", "answer_2": "b"}, follow_redirects=True)
    check("finder can't claim own item", b"claim an item you reported" in r.data)

with app.test_client() as admin:
    login(admin, 1)
    r = admin.get("/admin")
    check("admin dashboard loads with pending claim", r.status_code == 200 and b"Review" in r.data)
    r = admin.get("/admin/claim/1")
    check("review page shows private details + answers", b"Foldable umbrella" in r.data and b"Fulton" in r.data and b"Initials JD" in r.data)
    r = admin.post("/admin/claim/1/decide", data={"decision": "Approved"}, follow_redirects=True)
    check("claim approved", b"Claim approved" in r.data)
    r = admin.post("/admin/claim/1/release", follow_redirects=True)
    check("item released", b"released" in r.data)
    r = admin.get("/admin")
    check("dashboard shows 1 returned + audit trail", b"Item released to owner" in r.data and b"Claimed -&gt; Returned" in r.data)
    r = admin.post("/admin/found/%d/store" % 3, data={"storage_id": 1}, follow_redirects=True)
    check("admin can mark found item stored", r.status_code == 200)

with app.test_client() as juan:
    login(juan, 2)
    r = juan.get("/my")
    check("owner sees claim approved + lost report Resolved", b"Resolved" in r.data and b"Approved" in r.data)
    check("owner got notifications", b"was approved" in r.data)
print("\nALL CHECKS PASSED")
