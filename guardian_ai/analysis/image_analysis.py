from PIL import Image
import torch

try:
    from transformers import CLIPProcessor, CLIPModel
    CLIP_AVAILABLE = True
except ImportError:
    CLIP_AVAILABLE = False

from ..config import THREAT_THRESHOLDS

class ImageAnalyzer:
    """
    Layer 2: Visual Threat Detection
    Uses OpenAI CLIP (Zero-Shot) to detect concepts like nudity or violence.
    """
    
    def __init__(self):
        self._model_loaded = False
        if CLIP_AVAILABLE:
            try:
                print("Loading CLIP (openai/clip-vit-base-patch32)...")
                self.model = CLIPModel.from_pretrained("openai/clip-vit-base-patch32")
                self.processor = CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")
                self._model_loaded = True
                print("CLIP loaded successfully.")
                
                # Zero-Shot Prompts
                # We used to have "screenshot of a safe desktop app", but that confused the model 
                # when explicit content was INSIDE a browser window.
                self.labels = [
                    "safe, normal image", 
                    "explicit nudity, exposed skin, pornography", 
                    "violence, blood, gore"
                ]
            except Exception as e:
                print(f"Failed to load CLIP: {e}")
        else:
            print("Transformers not found. Using simulation mode.")

    def analyze_frame(self, frame_image):
        """
        Analyzes a single frame for visual threats using CLIP.
        """
        if frame_image is None:
            return {"risk_score": 0.0, "labels": []}

        if self._model_loaded and CLIP_AVAILABLE:
            try:
                inputs = self.processor(
                    text=self.labels, 
                    images=frame_image, 
                    return_tensors="pt", 
                    padding=True
                )

                with torch.no_grad():
                    outputs = self.model(**inputs)
                
                # Softmax to get probabilities
                probs = outputs.logits_per_image.softmax(dim=1).squeeze()
                
                # Index 0 is "Safe", Index 1 is "Nudity", Index 2 is "Violence"
                safe_score = float(probs[0])
                nudity_score = float(probs[1])
                violence_score = float(probs[2])
                
                risk_score = 0.0
                detected_labels = []

                print(f"   [Vision] Safe: {safe_score:.2f}, Nudity: {nudity_score:.2f}, Violence: {violence_score:.2f}")

                if nudity_score > 0.5: # 50% confidence
                    risk_score = max(risk_score, nudity_score)
                    detected_labels.append("explicit_content")
                
                if violence_score > 0.5:
                    risk_score = max(risk_score, violence_score)
                    detected_labels.append("violence")

                return {"risk_score": risk_score, "labels": detected_labels}
                
            except Exception as e:
                print(f"Inference failed: {e}")
                return {"risk_score": 0.0, "labels": []}

        # Fallback Simulation
        return {
            "risk_score": 0.1, 
            "labels": []
        }
