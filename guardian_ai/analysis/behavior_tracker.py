import collections
import time
import os
import torch
import torch.nn as nn
from typing import Optional, List, Tuple
from datetime import datetime


class BehaviorLSTM(nn.Module):
    """Bidirectional LSTM for behavioral anomaly detection"""
    
    def __init__(self, input_size: int = 4, hidden_size: int = 64, num_layers: int = 2):
        super(BehaviorLSTM, self).__init__()
        
        self.hidden_size = hidden_size
        self.num_layers = num_layers
        
        self.lstm = nn.LSTM(
            input_size=input_size,
            hidden_size=hidden_size,
            num_layers=num_layers,
            batch_first=True,
            bidirectional=True,
            dropout=0.3
        )
        
        self.attention = nn.Linear(hidden_size * 2, 1)
        
        self.fc = nn.Sequential(
            nn.Linear(hidden_size * 2, 32),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(32, 1),
            nn.Sigmoid()
        )
    
    def forward(self, x):
        lstm_out, _ = self.lstm(x)
        attention_weights = torch.softmax(self.attention(lstm_out), dim=1)
        context = torch.sum(attention_weights * lstm_out, dim=1)
        output = self.fc(context)
        return output.squeeze()


class BehaviorTracker:
    """
    Layer 2: Behavior Tracking
    Uses LSTM-based deep learning to detect usage anomalies.
    """
    
    def __init__(self):
        print("Initializing BehaviorTracker (LSTM-based)...")
        self.history = collections.deque(maxlen=100)
        self.model: Optional[BehaviorLSTM] = None
        self.model_loaded = False
        
        # Try to load fine-tuned LSTM model
        self._load_model()

    def _load_model(self):
        """Load trained LSTM model if available"""
        model_path = "models/behavior_lstm/model.pth"
        
        if os.path.exists(model_path):
            try:
                self.model = BehaviorLSTM(input_size=4, hidden_size=64, num_layers=2)
                self.model.load_state_dict(torch.load(model_path, map_location='cpu'))
                self.model.eval()
                self.model_loaded = True
                print("[BehaviorTracker] ✓ Loaded fine-tuned LSTM model")
            except Exception as e:
                print(f"[BehaviorTracker] Failed to load LSTM model: {e}")
                print("[BehaviorTracker] Using fallback heuristic-based detection")
        else:
            print("[BehaviorTracker] No trained model found, using heuristic-based detection")

    def add_event(self, event_type, timestamp):
        """
        Logs a usage event.
        """
        self.history.append((timestamp, event_type))

    def analyze_pattern(self) -> float:
        """
        Checks for high-risk patterns using LSTM or heuristics.
        
        Returns:
            float: Anomaly score (0.0 to 1.0)
        """
        if len(self.history) < 10:
            return 0.0
        
        # If LSTM model is loaded, use it
        if self.model_loaded and self.model is not None:
            return self._analyze_with_lstm()
        else:
            return self._analyze_with_heuristics()
    
    def _analyze_with_lstm(self) -> float:
        """Use trained LSTM model for anomaly detection"""
        try:
            # Prepare sequence (last 50 events)
            sequence_length = min(50, len(self.history))
            sequence = list(self.history)[-sequence_length:]
            
            # Extract features: [hour, risk_score, duration, app_hash]
            features = []
            for i, (timestamp, event_type) in enumerate(sequence):
                # Get current hour
                current_time = datetime.fromtimestamp(timestamp)
                hour = current_time.hour / 24.0  # Normalize
                
                # Placeholder risk and duration (would come from actual data)
                risk_score = 0.1  # Default low risk
                duration = 120.0 / 600.0  # Normalize
                app_hash = hash(event_type) % 100 / 100.0
                
                features.append([hour, risk_score, duration, app_hash])
            
            # Pad if necessary
            while len(features) < 50:
                features.append([0.0, 0.0, 0.0, 0.0])
            
            # Convert to tensor
            input_tensor = torch.tensor([features], dtype=torch.float32)
            
            # Run inference
            with torch.no_grad():
                anomaly_score = self.model(input_tensor).item()
            
            return float(anomaly_score)
        
        except Exception as e:
            print(f"[BehaviorTracker] LSTM inference error: {e}")
            return self._analyze_with_heuristics()
    
    def _analyze_with_heuristics(self) -> float:
        """Fallback heuristic-based anomaly detection"""
        # Check for late night activity (1 AM - 5 AM)
        late_night_count = 0
        
        for timestamp, _ in self.history:
            current_time = datetime.fromtimestamp(timestamp)
            hour = current_time.hour
            
            if 1 <= hour <= 5:
                late_night_count += 1
        
        # Calculate risk based on late night usage
        late_night_ratio = late_night_count / len(self.history)
        
        if late_night_ratio > 0.3:  # More than 30% late night
            return 0.7
        elif late_night_ratio > 0.1:
            return 0.4
        else:
            return 0.1


    def generate_report(self, output_dir="logs"):
        """
        Writes a daily usage report.
        """
        os.makedirs(output_dir, exist_ok=True)
        report_path = os.path.join(output_dir, "daily_report.md")
        
        with open(report_path, "w") as f:
            f.write(f"# Guardian-AI Daily Report\n")
            f.write(f"**Date**: {time.ctime()}\n\n")
            f.write("## Activity Log\n")
            for timestamp, event in list(self.history)[-20:]: # Last 20 events
                f.write(f"- {time.ctime(timestamp)}: {event}\n")
                
        print(f"[Behavior] Report generated: {report_path}")

    def generate_analytics(self, history_rows):
        """
        Analyzes cycle history to generate screen time and risk patterns.
        """
        stats = {
            "total_cycles": len(history_rows),
            "app_usage": {},
            "risk_patterns": {"Safe": 0, "Low": 0, "Medium": 0, "High": 0, "Critical": 0},
            "top_risks": []
        }
        
        for row in history_rows:
            # 1. App Usage
            app = row.get("app_name", "Unknown")
            # Cleaning title (e.g. "YouTube - Chrome" -> "Chrome")
            # For now, just use full title or simplified
            stats["app_usage"][app] = stats["app_usage"].get(app, 0) + 2 # Approx 2 sec per cycle
            
            # 2. Risk Patterns
            risk = row.get("total_risk", 0.0)
            if risk > 0.8: cat = "Critical"
            elif risk > 0.6: cat = "High"
            elif risk > 0.3: cat = "Medium"
            elif risk > 0.1: cat = "Low"
            else: cat = "Safe"
            stats["risk_patterns"][cat] += 1
            
        # 3. Sort App Usage (Top 5)
        sorted_apps = sorted(stats["app_usage"].items(), key=lambda x: x[1], reverse=True)[:5]
        stats["top_apps"] = [{"name": k, "seconds": v} for k, v in sorted_apps]
        
        return stats
