package io.fynn.pytorch_mobile;

import android.content.Context;
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

import androidx.annotation.NonNull;

import org.pytorch.IValue;
import org.pytorch.LiteModuleLoader;
import org.pytorch.Module;
import org.pytorch.Tensor;
import org.pytorch.torchvision.TensorImageUtils;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class PyTorchMobilePlugin implements FlutterPlugin, MethodCallHandler {
    private MethodChannel channel;
    private Context context;
    private Map<String, Module> loadedModules = new HashMap<>();

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "pytorch_mobile");
        channel.setMethodCallHandler(this);
        context = flutterPluginBinding.getApplicationContext();
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        // Release all loaded modules
        for (Module module : loadedModules.values()) {
            module.destroy();
        }
        loadedModules.clear();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "loadModel":
                handleLoadModel(call, result);
                break;
            case "predict":
                handlePredict(call, result);
                break;
            case "predictInt":
                handlePredictInt(call, result);
                break;
            case "predictImage":
                handlePredictImage(call, result);
                break;
            default:
                result.notImplemented();
        }
    }

    private void handleLoadModel(MethodCall call, Result result) {
        try {
            String assetPath = call.argument("assetPath");
            if (assetPath == null) {
                result.error("INVALID_ARGUMENT", "assetPath is required", null);
                return;
            }

            // Copy asset to cache and load
            String modelPath = assetFilePath(assetPath);
            if (modelPath != null) {
                Module module = LiteModuleLoader.load(modelPath);
                loadedModules.put(modelPath, module);
                result.success(modelPath);
            } else {
                result.error("LOAD_ERROR", "Failed to copy model from assets", null);
            }
        } catch (Exception e) {
            result.error("LOAD_ERROR", "Failed to load model: " + e.getMessage(), null);
        }
    }

    private void handlePredict(MethodCall call, Result result) {
        try {
            String modelPath = call.argument("modelPath");
            double[] input = toDoubleArray(call.argument("input"));
            List<Integer> shapeList = call.argument("shape");
            
            if (modelPath == null || input == null || shapeList == null) {
                result.error("INVALID_ARGUMENT", "modelPath, input, and shape are required", null);
                return;
            }

            Module module = loadedModules.get(modelPath);
            if (module == null) {
                result.error("MODEL_NOT_LOADED", "Model not loaded: " + modelPath, null);
                return;
            }

            // Convert to float array and create tensor
            float[] floatInput = new float[input.length];
            for (int i = 0; i < input.length; i++) {
                floatInput[i] = (float) input[i];
            }
            
            long[] shape = new long[shapeList.size()];
            for (int i = 0; i < shapeList.size(); i++) {
                shape[i] = shapeList.get(i);
            }

            Tensor inputTensor = Tensor.fromBlob(floatInput, shape);
            Tensor outputTensor = module.forward(IValue.from(inputTensor)).toTensor();
            
            float[] outputData = outputTensor.getDataAsFloatArray();
            List<Double> outputList = new ArrayList<>();
            for (float f : outputData) {
                outputList.add((double) f);
            }

            result.success(outputList);
        } catch (Exception e) {
            result.error("PREDICT_ERROR", "Prediction failed: " + e.getMessage(), null);
        }
    }

    private void handlePredictInt(MethodCall call, Result result) {
        try {
            String modelPath = call.argument("modelPath");
            long[] input = toLongArray(call.argument("input"));
            List<Integer> shapeList = call.argument("shape");
            
            if (modelPath == null || input == null || shapeList == null) {
                result.error("INVALID_ARGUMENT", "modelPath, input, and shape are required", null);
                return;
            }

            Module module = loadedModules.get(modelPath);
            if (module == null) {
                result.error("MODEL_NOT_LOADED", "Model not loaded: " + modelPath, null);
                return;
            }

            long[] shape = new long[shapeList.size()];
            for (int i = 0; i < shapeList.size(); i++) {
                shape[i] = shapeList.get(i);
            }

            Tensor inputTensor = Tensor.fromBlob(input, shape);
            Tensor outputTensor = module.forward(IValue.from(inputTensor)).toTensor();
            
            float[] outputData = outputTensor.getDataAsFloatArray();
            List<Double> outputList = new ArrayList<>();
            for (float f : outputData) {
                outputList.add((double) f);
            }

            result.success(outputList);
        } catch (Exception e) {
            result.error("PREDICT_ERROR", "Prediction failed: " + e.getMessage(), null);
        }
    }

    private void handlePredictImage(MethodCall call, Result result) {
        try {
            String modelPath = call.argument("modelPath");
            byte[] imageData = call.argument("imageData");
            Integer width = call.argument("width");
            Integer height = call.argument("height");
            String meanStr = call.argument("mean");
            String stdStr = call.argument("std");
            
            if (modelPath == null || imageData == null) {
                result.error("INVALID_ARGUMENT", "modelPath and imageData are required", null);
                return;
            }

            Module module = loadedModules.get(modelPath);
            if (module == null) {
                result.error("MODEL_NOT_LOADED", "Model not loaded: " + modelPath, null);
                return;
            }

            // Decode image
            Bitmap bitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.length);
            if (bitmap == null) {
                result.error("IMAGE_ERROR", "Failed to decode image", null);
                return;
            }

            // Resize if needed
            if (width != null && height != null) {
                bitmap = Bitmap.createScaledBitmap(bitmap, width, height, true);
            }

            // Parse mean and std
            float[] mean = parseMeanStd(meanStr, new float[]{0.485f, 0.456f, 0.406f});
            float[] std = parseMeanStd(stdStr, new float[]{0.229f, 0.224f, 0.225f});

            // Convert to tensor
            Tensor inputTensor = TensorImageUtils.bitmapToFloat32Tensor(
                bitmap, mean, std
            );

            // Run inference
            Tensor outputTensor = module.forward(IValue.from(inputTensor)).toTensor();
            
            float[] outputData = outputTensor.getDataAsFloatArray();
            List<Double> outputList = new ArrayList<>();
            for (float f : outputData) {
                outputList.add((double) f);
            }

            result.success(outputList);
        } catch (Exception e) {
            result.error("PREDICT_ERROR", "Image prediction failed: " + e.getMessage(), null);
        }
    }

    private float[] parseMeanStd(String str, float[] defaultVal) {
        if (str == null || str.isEmpty()) {
            return defaultVal;
        }
        try {
            String[] parts = str.split(",");
            float[] result = new float[parts.length];
            for (int i = 0; i < parts.length; i++) {
                result[i] = Float.parseFloat(parts[i].trim());
            }
            return result;
        } catch (Exception e) {
            return defaultVal;
        }
    }

    private double[] toDoubleArray(Object obj) {
        if (obj == null) return null;
        if (obj instanceof byte[]) {
            byte[] bytes = (byte[]) obj;
            double[] result = new double[bytes.length / 8];
            java.nio.ByteBuffer.wrap(bytes).asDoubleBuffer().get(result);
            return result;
        }
        if (obj instanceof List) {
            List<?> list = (List<?>) obj;
            double[] result = new double[list.size()];
            for (int i = 0; i < list.size(); i++) {
                result[i] = ((Number) list.get(i)).doubleValue();
            }
            return result;
        }
        return null;
    }

    private long[] toLongArray(Object obj) {
        if (obj == null) return null;
        if (obj instanceof byte[]) {
            byte[] bytes = (byte[]) obj;
            long[] result = new long[bytes.length / 8];
            java.nio.ByteBuffer.wrap(bytes).asLongBuffer().get(result);
            return result;
        }
        if (obj instanceof List) {
            List<?> list = (List<?>) obj;
            long[] result = new long[list.size()];
            for (int i = 0; i < list.size(); i++) {
                result[i] = ((Number) list.get(i)).longValue();
            }
            return result;
        }
        return null;
    }

    private String assetFilePath(String assetName) {
        try {
            // Handle Flutter asset paths
            String flutterAssetPath = "flutter_assets/" + assetName;
            
            File file = new File(context.getCacheDir(), assetName.replace("/", "_"));
            if (file.exists() && file.length() > 0) {
                return file.getAbsolutePath();
            }

            AssetManager assetManager = context.getAssets();
            InputStream inputStream;
            
            try {
                inputStream = assetManager.open(flutterAssetPath);
            } catch (IOException e) {
                // Try without flutter_assets prefix
                inputStream = assetManager.open(assetName);
            }

            OutputStream outputStream = new FileOutputStream(file);
            byte[] buffer = new byte[4 * 1024];
            int read;
            while ((read = inputStream.read(buffer)) != -1) {
                outputStream.write(buffer, 0, read);
            }
            outputStream.flush();
            outputStream.close();
            inputStream.close();

            return file.getAbsolutePath();
        } catch (Exception e) {
            return null;
        }
    }
}
