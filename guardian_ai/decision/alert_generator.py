import random

class AlertGenerator:
    """
    Layer 3: Alert Generator (SLM)
    Generates sanitized, context-aware summaries using a Small Language Model.
    """
    
    def __init__(self):
        print("Initializing AlertGenerator (SLM Stub)...")
        self.templates = [
            "Potentially inappropriate content detected in {source}.",
            "High-risk visual content blocked in {source}.",
            "Conversation flagged for safety review in {source}."
        ]

    def generate_alert(self, risk_score, labels, source):
        """
        Creates a human-readable alert.
        """
        if risk_score < 0.5:
            return None
            
        # Real SLM would generate this dynamically based on labels
        # Here we pick a template based on severity
        
        if risk_score > 0.8:
            base_msg = "CRITICAL ALERT: High-risk content detected."
        else:
            base_msg = "Safety Alert: Suspicious activity."
            
        detail = ""
        if labels:
            detail = f" Detected: {', '.join(labels)}."
            
        return f"{base_msg}{detail} Source: {source}."
