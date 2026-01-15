from flask import Flask, render_template, jsonify, send_from_directory
import os
import sqlite3
from ..utils.database import DatabaseManager
from ..analysis.behavior_tracker import BehaviorTracker

app = Flask(__name__)
db = DatabaseManager()
behavior_tracker = BehaviorTracker()

# Ensure we can serve evidence images
EVIDENCE_DIR = os.path.abspath("logs/evidence/images")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/live')
def get_live_data():
    """
    Returns the most recent cycle data.
    """
    data = db.get_latest_cycle()
    if data:
        # Normalize paths for frontend
        if data.get("screenshot_path"):
             data["screenshot_url"] = "/assets/" + os.path.basename(data["screenshot_path"])
        else:
             data["screenshot_url"] = ""
    return jsonify(data if data else {})

@app.route('/api/history')
def get_history():
    """
    Returns the last 20 cycles for charts.
    """
    history = db.get_recent_history(20)
    
    # Process rows to add URLs
    output = []
    for row in history:
        r = dict(row) # Convert to mutable dict
        if r.get("screenshot_path"):
             r["screenshot_url"] = "/assets/" + os.path.basename(r["screenshot_path"])
        else:
             r["screenshot_url"] = ""
        output.append(r)

    return jsonify(output) # No reverse needed if DB returns DESC

@app.route('/api/summary')
def get_summary():
    """
    Returns behavioral analytics.
    """
    rows = db.get_full_history(limit=5000) # Fetch lots of data
    stats = behavior_tracker.generate_analytics(rows)
    return jsonify(stats)

@app.route('/assets/<path:filename>')
def serve_evidence(filename):
    """
    Serves images from the evidence directory.
    """
    return send_from_directory(EVIDENCE_DIR, filename)

def run_dashboard(port=5000):
    print(f"[{'Dashboard'}] Starting Web Interface on http://localhost:{port}")
    # Disable reloader/debug for production-like thread usage
    app.run(host='0.0.0.0', port=port, debug=False, use_reloader=False)
