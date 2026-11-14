# UP Mindanao Lost & Found Management System (LFMS)
DS 187 Final Project. MySQL/MariaDB database + a bare-bones Flask app.

```
lfms/
├─ db/            SQL scripts (schema, views, matching, triggers, seed) + build scripts
├─ app/           Flask app (routes, templates, smoke test)
├─ README.md
└─ .gitignore
```

## Quick start (Windows + XAMPP), about 10 minutes

**You need:** [XAMPP](https://www.apachefriends.org) and [Python 3.10+](https://www.python.org/downloads/) (tick "Add Python to PATH" when installing).

1. **Clone the repo** and open the folder in VS Code (`File > Open Folder`):
   ```
   git clone <repo-url>
   ```
2. **Start MySQL**: open the XAMPP Control Panel, click **Start** next to **MySQL** (it turns green). You don't need Apache.
3. **Build the database**: double-click `db\build.bat`. You should see `Running 01_schema.sql` ... `05_seed.sql`, then `Done`.
   - *If the script fails:* open the XAMPP Control Panel, click **Shell**, type `mysql -u root < ` (with a space), drag `db\lfms_all.sql` into the window, press Enter. No output means success.
4. **Run the app**: double-click `app\run_app.bat`. (First run takes a minute to install packages.)
   - *Or manually, from inside the `app` folder:*
     ```
     python -m venv venv
     venv\Scripts\activate
     pip install -r requirements.txt
     python app.py
     ```
     PowerShell blocks `activate`? Run `Set-ExecutionPolicy -Scope Process Bypass` first.
5. Open **http://127.0.0.1:5000** and click **Log in**.

### Test users (dev login: pick one from the list)
| User | Role | Use it to |
|---|---|---|
| Ana Admin | admin | review claims, release items, mark stored, dashboard |
| Juan Dela Cruz | student | owns the lost umbrella (has a suggested match) |
| Maria Santos | student | owns a lost phone |
| Pedro Reyes | faculty | found the umbrella |

### Mac / Linux
```
brew install mysql python && brew services start mysql      # Linux: apt install mysql-server python3-venv
bash db/build.sh
cd app && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt && python app.py
```

## Troubleshooting
| Problem | Fix |
|---|---|
| `No module named 'pymysql'` | You skipped `pip install -r requirements.txt`, or used a different Python. Use `run_app.bat`. |
| `Can't connect to MySQL server` | XAMPP MySQL isn't started (must be green), or port 3306 is taken. |
| `Access denied for user 'root'` | Your root has a password. Set env vars: `DB_PASS=yourpassword` (see below). |
| `Unknown database 'lfms'` | Step 3 wasn't done. Run `db\build.bat`. |
| `requirements.txt` not found | Your terminal isn't in the `app` folder. Run `dir`: you should see `app.py`. |
| MySQL Workbench says `Unknown system variable 'explain_json_format_version'` | New Workbench vs XAMPP's MariaDB mismatch. Not your fault. Use phpMyAdmin (XAMPP > MySQL **Admin**), DBeaver, or the XAMPP **Shell** instead. |
| Photos disappear | Uploads are saved in `app/static/uploads/` (git-ignored, local only). |

### DB connection settings
Defaults match XAMPP. Override with environment variables if yours differ:
`DB_HOST=127.0.0.1  DB_PORT=3306  DB_USER=root  DB_PASS=  DB_NAME=lfms`
PowerShell: `$env:DB_PASS="secret"; python app.py`

## Database files (`db/`, run in order)
| File | What |
|---|---|
| `01_schema.sql` | Tables, PK/FK, constraints, indexes. **Drops and recreates `lfms`** (dev only). |
| `02_views.sql` | Public views (hide private details) + admin dashboard/analytics views |
| `03_matching.sql` | `sp_suggest_matches_for_lost/found` (weighted score, threshold 40) |
| `04_triggers.sql` | Activity log, notifications, status changes, auto-matching |
| `05_seed.sql` | Sample data (replace placeholder locations with the official list) |
| `lfms_all.sql` | All five above joined, as a one-shot fallback. **Don't edit it.** Regenerate after changing a 0x file: `cat db/0*.sql > db/lfms_all.sql` (Git Bash/Mac/Linux) |

## Team workflow
- **Everyone runs their own local DB.** Never edit a shared live DB. The `.sql` files in Git are the source of truth.
- To change the DB: edit the `.sql` file, rebuild locally, test, then open a PR.
- **Branch per task**, never push straight to `main`:
  ```
  git checkout -b feat/short-name
  git add .
  git commit -m "area: what you changed"
  git push -u origin feat/short-name
  ```
  Then open a Pull Request on GitHub. One teammate reviews before merging.
- Before every PR: run `db\build.bat`, then `python smoke_test.py` (inside `app/`). If either fails, don't merge. (The smoke test writes rows, so rebuild the DB afterwards to get clean sample data.)
- Pull often: `git checkout main && git pull`.
- To avoid merge conflicts, tell the group chat before editing a file someone else is working in.
- The app records who acted in the audit log by setting `@current_user_id` per connection (`app/db.py`). Keep that when adding routes.

## First push (repo owner only)
1. On github.com create an **empty** repo (no README), then add teammates under **Settings > Collaborators**.
2. In a terminal inside this folder:
   ```
   git init
   git add .
   git commit -m "init: LFMS database and Flask app"
   git branch -M main
   git remote add origin <repo-url>
   git push -u origin main
   ```

## Where to help (suggested split)
- **Auth**: real login and registration (`werkzeug.security` + `password_hash`), replace the pick-a-user dev login in `app/app.py`.
- **UI**: styling and nicer templates in `app/templates/`.
- **Admin extras**: manage users/reports/claims; auto-reject other pending claims when one is approved.
- **Database**: add `released_by_admin_id` to `claim`, a public `item_name` for found items, more indexes and EXPLAIN checks.
- **Docs and demo**: final report, slides, ERD updates.

## Known gaps
- Dev-stub login, no CSRF protection or rate limiting.
- Found items have no public title, so keyword search on them only matches category/location. Searching the private description would leak hidden details.
- The schema stores `reviewed_by_admin_id` but not *who released* the item.

## Differences from the ERD (decide as a team)
- `MATCH` is a reserved word, so the table is `item_match`.
- `USER` is reserved in some databases, so it's `app_user`.
- `ACTIVITY_LOG.timestamp` is `logged_at`.
- `FOUND_REPORT` has no `item_name` (see Known gaps).
