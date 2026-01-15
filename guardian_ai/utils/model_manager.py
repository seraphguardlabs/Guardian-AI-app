"""
Model Manager - Centralized model loading and versioning
Handles loading fine-tuned models with fallback to base models
"""

import os
import json
from typing import Optional, Dict, Any


class ModelManager:
    """Manages loading and versioning of AI models"""
    
    def __init__(self, models_dir: str = "models"):
        self.models_dir = models_dir
        self.loaded_models = {}
        
    def get_model_path(self, model_name: str) -> Optional[str]:
        """
        Get path to fine-tuned model if available
        
        Args:
            model_name: Name of model (e.g., 'clip_finetuned', 'bert_finetuned', 'behavior_lstm')
            
        Returns:
            Path to model directory or None if not found
        """
        model_path = os.path.join(self.models_dir, model_name)
        
        if os.path.exists(model_path):
            # Check for metadata file
            metadata_path = os.path.join(model_path, "metadata.json")
            if os.path.exists(metadata_path):
                return model_path
        
        return None
    
    def load_model_metadata(self, model_name: str) -> Optional[Dict[str, Any]]:
        """Load model metadata"""
        model_path = self.get_model_path(model_name)
        
        if model_path:
            metadata_path = os.path.join(model_path, "metadata.json")
            try:
                with open(metadata_path, 'r') as f:
                    return json.load(f)
            except Exception as e:
                print(f"[ModelManager] Error loading metadata for {model_name}: {e}")
        
        return None
    
    def is_model_available(self, model_name: str) -> bool:
        """Check if fine-tuned model is available"""
        return self.get_model_path(model_name) is not None
    
    def get_model_info(self, model_name: str) -> Dict[str, Any]:
        """Get information about a model"""
        metadata = self.load_model_metadata(model_name)
        
        if metadata:
            return {
                "available": True,
                "version": metadata.get("version", "unknown"),
                "trained_date": metadata.get("trained_date", "unknown"),
                "accuracy": metadata.get("accuracy", "unknown"),
                "path": self.get_model_path(model_name)
            }
        else:
            return {
                "available": False,
                "using_base_model": True
            }
    
    def list_available_models(self) -> Dict[str, Dict[str, Any]]:
        """List all available fine-tuned models"""
        model_names = ["clip_finetuned", "bert_finetuned", "behavior_lstm"]
        
        models_info = {}
        for name in model_names:
            models_info[name] = self.get_model_info(name)
        
        return models_info


# Global instance
model_manager = ModelManager()
