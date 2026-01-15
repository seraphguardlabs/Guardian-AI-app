# Guardian-AI Configuration

# Threat Guidelines
THREAT_THRESHOLDS = {
    "nudity": 0.85,
    "violence": 0.80,
    "grooming": 0.75,
    "hate_speech": 0.80,
    "self_harm": 0.90
}

# System settings
SAMPLING_RATE_FPS = 1
MAX_TEXT_CACHE_SIZE = 1000

# Model Paths (placeholders)
MODEL_PATHS = {
    "image_model": "models/mobilenet_v3.tflite",
    "text_model": "models/distilbert_quantized.onnx"
}
