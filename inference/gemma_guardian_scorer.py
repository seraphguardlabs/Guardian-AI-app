import argparse
import json
import os
import re
from pathlib import Path
from typing import Any

from PIL import Image
from transformers import AutoModelForImageTextToText, AutoProcessor

DEFAULT_MODEL_ID = "google/gemma-4-E2B-it"


def load_model_and_processor(model_id: str):
    hf_token = os.getenv("HF_TOKEN")

    # Uses the exact Transformers APIs requested by the user.
    processor = AutoProcessor.from_pretrained(model_id, token=hf_token)
    model = AutoModelForImageTextToText.from_pretrained(model_id, token=hf_token)
    return processor, model


def build_guardian_prompt() -> str:
    return (
        "You are a child-safety classifier. Analyze the screenshot and return ONLY JSON with keys: "
        "sexual_content, violence, predatory_text, overall_risk, explanation. "
        "Each score must be a float from 0.0 to 1.0. "
        "overall_risk should summarize all factors. "
        "Keep explanation under 25 words."
    )


def _extract_json(raw_text: str) -> dict[str, Any]:
    text = raw_text.strip()
    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, flags=re.DOTALL)
    if fenced:
        text = fenced.group(1).strip()

    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        obj_match = re.search(r"\{.*\}", text, flags=re.DOTALL)
        if not obj_match:
            raise
        data = json.loads(obj_match.group(0))

    return {
        "sexual_content": float(data.get("sexual_content", 0.0)),
        "violence": float(data.get("violence", 0.0)),
        "predatory_text": float(data.get("predatory_text", 0.0)),
        "overall_risk": float(data.get("overall_risk", 0.0)),
        "explanation": str(data.get("explanation", "")),
    }


def score_image(image_path: Path, model_id: str) -> dict[str, Any]:
    processor, model = load_model_and_processor(model_id)
    image = Image.open(image_path).convert("RGB")

    prompt = build_guardian_prompt()
    inputs = processor(text=prompt, images=image, return_tensors="pt")
    outputs = model.generate(**inputs, max_new_tokens=256)
    decoded = processor.batch_decode(outputs, skip_special_tokens=True)[0]

    parsed = _extract_json(decoded)
    parsed["model_id"] = model_id
    parsed["image_path"] = str(image_path)
    return parsed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Score screenshot safety risk with Gemma-4-E2B-it via Transformers",
    )
    parser.add_argument("--image", required=True, help="Path to screenshot image")
    parser.add_argument("--model-id", default=DEFAULT_MODEL_ID, help="HF model ID")
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Print indented JSON",
    )
    args = parser.parse_args()

    image_path = Path(args.image).expanduser().resolve()
    if not image_path.exists():
        raise FileNotFoundError(f"Image not found: {image_path}")

    result = score_image(image_path=image_path, model_id=args.model_id)
    if args.pretty:
        print(json.dumps(result, indent=2))
    else:
        print(json.dumps(result))


if __name__ == "__main__":
    main()
