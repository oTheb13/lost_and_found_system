"""Tiny PyMySQL helper. One connection per request; all SQL lives in app.py / db/*.sql."""
import os
import pymysql
from flask import g, session


def get_db():
    if "db" not in g:
        g.db = pymysql.connect(
            host=os.getenv("DB_HOST", "127.0.0.1"),
            port=int(os.getenv("DB_PORT", "3306")),
            user=os.getenv("DB_USER", "root"),
            password=os.getenv("DB_PASS", ""),
            database=os.getenv("DB_NAME", "lfms"),
            charset="utf8mb4",
            cursorclass=pymysql.cursors.DictCursor,
            autocommit=False,
        )
        # The triggers in db/04_triggers.sql read this to record WHO acted in activity_log.
        with g.db.cursor() as cur:
            cur.execute("SET @current_user_id = %s", (session.get("user_id"),))
    return g.db


def close_db(exc=None):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


def query(sql, args=(), one=False):
    with get_db().cursor() as cur:
        cur.execute(sql, args)
        rows = cur.fetchall()
    if one:
        return rows[0] if rows else None
    return rows


def execute(sql, args=()):
    """Run a write. Call commit() when the whole action is done."""
    with get_db().cursor() as cur:
        cur.execute(sql, args)
        return cur.lastrowid


def commit():
    get_db().commit()
