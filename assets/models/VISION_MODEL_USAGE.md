
# Lightweight Vision Model Usage

## Model Info
- **Backbone**: MobileNetV2 (optimized for mobile)
- **Size**: ~14 MB (PTL) or ~13 MB (ONNX)
- **Input**: 224x224 RGB image
- **Output**: 3 classes [Safe, Explicit, Violence]

## Flutter Integration (PyTorch Mobile)

```dart
import 'package:pytorch_mobile/pytorch_mobile.dart';
import 'package:image/image.dart' as img;

class VisionModelService {
  Model? _model;
  
  Future<void> loadModel() async {
    _model = await PyTorchMobile.loadModel('assets/models/vision_mobile.ptl');
  }
  
  Future<Map<String, double>> analyzeImage(img.Image image) async {
    // Resize to 224x224
    final resized = img.copyResize(image, width: 224, height: 224);
    
    // Convert to normalized tensor [0-1]
    final pixels = <double>[];
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
        pixels.add(pixel.r / 255.0);
        pixels.add(pixel.g / 255.0);
        pixels.add(pixel.b / 255.0);
      }
    }
    
    // Run inference
    final output = await _model!.getPrediction(pixels, [1, 3, 224, 224], DType.float32);
    
    // Apply softmax
    final logits = output.sublist(0, 3);
    final probs = _softmax(logits);
    
    return {
      'safe': probs[0],
      'explicit': probs[1],
      'violence': probs[2]
    };
  }
  
  List<double> _softmax(List<double> logits) {
    final exp = logits.map((x) => Math.exp(x)).toList();
    final sum = exp.reduce((a, b) => a + b);
    return exp.map((x) => x / sum).toList();
  }
}
```

## Note
This model uses MobileNetV2 pre-trained on ImageNet. For production use:
1. Fine-tune on your specific dataset (explicit content, violence)
2. Or use as feature extractor with custom training
3. Current version provides general image classification capability
