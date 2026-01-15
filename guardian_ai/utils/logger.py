import os
import time
import json
from PIL import Image

class EvidenceLogger:
    """
    Handles secure logging of sensitive evidence (Screenshots, Text).
    """
    
    def __init__(self, log_dir="logs"):
        self.log_dir = log_dir
        self.img_dir = os.path.join(log_dir, "evidence", "images")
        self.text_dir = os.path.join(log_dir, "evidence", "text")
        
        # Ensure directories exist
        os.makedirs(self.img_dir, exist_ok=True)
        os.makedirs(self.text_dir, exist_ok=True)
        
        self.text_log_file = os.path.join(self.text_dir, "incident_log.json")

    def save_screenshot(self, image, risk_score, source="screen"):
        """
        Saves a screenshot if it's high risk.
        """
        if image is None:
            return None
            
        timestamp = int(time.time())
        filename = f"{timestamp}_{source}_risk{int(risk_score*100)}.jpg"
        filepath = os.path.join(self.img_dir, filename)
        
        try:
            image.save(filepath, "JPEG")
            print(f"[Evidence] Saved screenshot: {filepath}")
            return filepath
        except Exception as e:
            print(f"[Evidence] Failed to save screenshot: {e}")
            return None

    def log_text_incident(self, text, risk_score, labels):
        """
        Logs harmful text to a JSON file.
        """
        if not text:
            return

        incident = {
            "timestamp": time.time(),
            "date": time.ctime(),
            "risk_score": risk_score,
            "labels": labels,
            "content_snippet": text[:100] + "..." if len(text) > 100 else text
        }
        
        try:
            # Read existing log
            data = []
            if os.path.exists(self.text_log_file):
                with open(self.text_log_file, 'r') as f:
                    try:
                        data = json.load(f)
                    except json.JSONDecodeError:
                        data = []
            
            data.append(incident)
            
            # Write back
            with open(self.text_log_file, 'w') as f:
                json.dump(data, f, indent=2)
                
            print(f"[Evidence] Logged text incident.")
        except Exception as e:
            print(f"[Evidence] Failed to log text: {e}")
