import sqlite3
import json
import time
import os

DB_PATH = "logs/guardian.db"

class DatabaseManager:
    def __init__(self):
        self._init_db()

    def _init_db(self):
        os.makedirs("logs", exist_ok=True)
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            # Cycles Table: Stores every monitoring tick
            c.execute('''CREATE TABLE IF NOT EXISTS cycles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL,
                image_risk REAL,
                text_risk REAL,
                behavior_risk REAL,
                total_risk REAL,
                extracted_text TEXT,
                ocr_labels TEXT,
                vision_labels TEXT,
                screenshot_path TEXT,
                app_name TEXT
            )''')
            
            # Alerts Table: High risk events
            c.execute('''CREATE TABLE IF NOT EXISTS alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL,
                risk_score REAL,
                alert_type TEXT,
                details TEXT
            )''')

            conn.commit()

    def log_cycle(self, data):
        """
        Logs a full monitoring cycle.
        """
        try:
            with sqlite3.connect(DB_PATH) as conn:
                c = conn.cursor()
                c.execute('''INSERT INTO cycles 
                    (timestamp, image_risk, text_risk, behavior_risk, total_risk, extracted_text, ocr_labels, vision_labels, screenshot_path, app_name)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                    (
                        data.get("timestamp", time.time()),
                        data.get("image_risk", 0.0),
                        data.get("text_risk", 0.0),
                        data.get("behavior_risk", 0.0),
                        data.get("total_risk", 0.0),
                        data.get("extracted_text", "")[:500],
                        json.dumps(data.get("ocr_labels", [])),
                        json.dumps(data.get("vision_labels", [])),
                        data.get("screenshot_path", ""),
                        data.get("app_name", "Unknown")
                    )
                )
                conn.commit()
        except Exception as e:
            print(f"[DB] Error logging cycle: {e}")

    def log_alert(self, risk_score, alert_type, details):
        try:
            with sqlite3.connect(DB_PATH) as conn:
                c = conn.cursor()
                c.execute("INSERT INTO alerts (timestamp, risk_score, alert_type, details) VALUES (?, ?, ?, ?)",
                          (time.time(), risk_score, alert_type, str(details)))
                conn.commit()
        except Exception as e:
            print(f"[DB] Error logging alert: {e}")

    def get_full_history(self, limit=3000):
        try:
            with sqlite3.connect(DB_PATH) as conn:
                conn.row_factory = sqlite3.Row
                c = conn.cursor()
                c.execute("SELECT * FROM cycles ORDER BY id DESC LIMIT ?", (limit,))
                rows = c.fetchall()
                return [dict(row) for row in rows]
        except Exception:
            return []

    def get_latest_cycle(self):
        try:
            with sqlite3.connect(DB_PATH) as conn:
                conn.row_factory = sqlite3.Row
                c = conn.cursor()
                c.execute("SELECT * FROM cycles ORDER BY id DESC LIMIT 1")
                row = c.fetchone()
                if row:
                    return dict(row)
                return None
        except Exception:
            return None

    def get_recent_history(self, limit=20):
        try:
            with sqlite3.connect(DB_PATH) as conn:
                conn.row_factory = sqlite3.Row
                c = conn.cursor()
                c.execute("SELECT * FROM cycles ORDER BY id DESC LIMIT ?", (limit,))
                rows = c.fetchall()
                return [dict(row) for row in rows]
        except Exception:
            return []
