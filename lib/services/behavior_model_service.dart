import 'package:pytorch_mobile/pytorch_mobile.dart';
import 'package:pytorch_mobile/model.dart';
import 'package:pytorch_mobile/enums/dtype.dart';

class BehaviorModelService {
  Model? _model;
  bool _isLoaded = false;

  Future<void> loadModel() async {
    if (_isLoaded) return;
    try {
      _model = await PyTorchMobile.loadModel('assets/models/behavior_lstm_mobile.ptl');
      _isLoaded = true;
      print('✅ LSTM loaded');
    } catch (e) {
      print('❌ Error loading LSTM: $e');
    }
  }

  Future<double> predictAnomaly(List<List<double>> sequence) async {
    if (!_isLoaded) await loadModel();
    if (_model == null) throw Exception('Model not loaded');
    if (sequence.length != 50) throw Exception('Need 50 events');
    
    // Flatten the 2D sequence to 1D list for PyTorch model
    final flattened = sequence.expand((row) => row).toList();
    
    final result = await _model!.getPrediction(flattened, [1, 50, 4], DType.float32);
    // Assuming the output is a single float wrapped in a list/tensor structure
    // Adjust based on actual model output format if needed
    if (result is List && result.isNotEmpty) {
       return result[0] as double;
    }
    return 0.0;
  }
}
