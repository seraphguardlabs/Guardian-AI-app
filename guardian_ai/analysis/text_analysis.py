import re
try:
    from transformers import pipeline
    TRANSFORMERS_AVAILABLE = True
except ImportError:
    TRANSFORMERS_AVAILABLE = False

from ..config import THREAT_THRESHOLDS

class TextAnalyzer:
    """
    Layer 2: Text Analysis
    Uses NLP models (DistilBERT/MiniLM) to scan for toxic content.
    """

    
    def __init__(self):
        self._model_ready = False
        if TRANSFORMERS_AVAILABLE:
            try:
                print("Loading DistilBERT Pipeline...")
                # Using a tiny sentiment model as a proxy for 'toxicity' in this demo
                self.classifier = pipeline("text-classification", model="distilbert-base-uncased-finetuned-sst-2-english")
                self._model_ready = True
                print("Text Pipeline loaded.")
            except Exception as e:
                 print(f"Failed to load Transformers: {e}")
        else:
             print("Transformers not found. Using simulation.")

    def analyze_text(self, text):
        """
        Scans text for grooming, hate speech, or self-harm keywords.
        
        Args:
            text (str): Content to analyze.
            
        Returns:
            dict: Risk assessment.
        """
        if not text:
             return {"risk_score": 0.0, "labels": []}
             
        risk_score = 0.0
        labels = []
        lower_text = text.lower()
        
        # 1. Keyword Check (Regex for whole words)
        # Prevents "audience" or "diet" triggering "die"
        if re.search(r'\b(kill|suicide)\b', lower_text):
            risk_score = 0.95
            labels.append("self_harm")
        elif re.search(r'\b(secret)\b', lower_text) and re.search(r'\b(meet)\b', lower_text):
            risk_score = 0.85
            labels.append("grooming")
        elif re.search(r'\b(die)\b', lower_text):
             # "die" is common in gaming/news, so use lower score unless combined
             if "hate" in lower_text or "you" in lower_text:
                 risk_score = 0.90
                 labels.append("self_harm")
            
        # 2. Model Check (Deep)
        if self._model_ready and TRANSFORMERS_AVAILABLE:
            try:
                res = self.classifier(text)[0]
                # If negative sentiment with high confidence, increase risk
                if res['label'] == 'NEGATIVE' and res['score'] > 0.9:
                    # Only add if we haven't already flagged it
                    if risk_score < 0.6:
                         risk_score = 0.6
                    labels.append("negative_sentiment")
            except Exception:
                pass
                
        return {
            "risk_score": risk_score,
            "labels": labels
        }
