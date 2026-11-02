import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// El motor no se pudo usar (no está en este sistema o el modelo no abrió).
class FormulaEngineException implements Exception {
  FormulaEngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

// Posiciones en la tabla OrtApi de ONNX Runtime (onnxruntime_c_api.h). La tabla
// solo crece al final, así que no cambian entre versiones.
const _getErrorMessage = 2;
const _createEnv = 3;
const _createSession = 7;
const _run = 9;
const _createSessionOptions = 10;
const _createTensorWithData = 49;
const _getTensorMutableData = 51;
const _getDimensionsCount = 61;
const _getDimensions = 62;
const _getTensorTypeAndShape = 65;
const _createCpuMemoryInfo = 69;
const _releaseEnv = 92;
const _releaseStatus = 93;
const _releaseMemoryInfo = 94;
const _releaseSession = 95;
const _releaseValue = 96;
const _releaseTensorTypeAndShapeInfo = 99;
const _releaseSessionOptions = 100;

/// La versión de la tabla que se pide: alcanza con esta, y el motor de la app
/// es más nuevo.
const _apiVersion = 22;
const _elementFloat = 1;
const _elementInt64 = 7;
const _arenaAllocator = 1;
const _memTypeDefault = 0;
const _logWarning = 2;

const _startToken = 1;
const _endToken = 2;
const _maxSteps = 100;

typedef _P = Pointer<Void>;
typedef _Pp = Pointer<Pointer<Void>>;

final class _OrtApiBase extends Struct {
  external Pointer<NativeFunction<Pointer<_P> Function(Uint32)>> getApi;
  external Pointer<NativeFunction<Pointer<Utf8> Function()>> getVersionString;
}

/// Corre el modelo que lee fórmulas con el mismo ONNX Runtime que ya traen las
/// voces (sherpa-onnx): no hace falta otra biblioteca nativa. Pensado para un
/// Isolate aparte. Abre el modelo una vez y devuelve, por cada imagen, los números
/// del vocabulario.
List<List<int>> runFormulaModel(String encoderPath, String decoderPath, List<Float32List> images, int size) {
  final DynamicLibrary library;
  try {
    library = DynamicLibrary.open('libonnxruntime.so');
  } on ArgumentError catch (e) {
    throw FormulaEngineException('El motor no está disponible: $e');
  }
  return _Ort(library).read(encoderPath, decoderPath, images, size);
}

/// Aplana una imagen con UVDoc: entra y sale por canales, de 0 a 1.
({Float32List pixels, int width, int height}) runUnwarpModel(String modelPath, Float32List pixels, int w, int h) {
  final DynamicLibrary library;
  try {
    library = DynamicLibrary.open('libonnxruntime.so');
  } on ArgumentError catch (e) {
    throw FormulaEngineException('El motor no está disponible: $e');
  }
  return _Ort(library).unwarp(modelPath, pixels, w, h);
}

class _Ort {
  _Ort(DynamicLibrary library) {
    final getBase = library.lookupFunction<Pointer<_OrtApiBase> Function(), Pointer<_OrtApiBase> Function()>(
      'OrtGetApiBase',
    );
    final getApi = getBase().ref.getApi.asFunction<Pointer<_P> Function(int)>();
    _api = getApi(_apiVersion);
    if (_api == nullptr) throw FormulaEngineException('Versión del motor no compatible');
  }

  late final Pointer<_P> _api;
  final _arena = Arena();

  Pointer<NativeFunction<T>> _fn<T extends Function>(int index) => _api[index].cast<NativeFunction<T>>();

  void _check(_P status) {
    if (status == nullptr) return;
    final getMessage = _fn<Pointer<Utf8> Function(_P)>(_getErrorMessage).asFunction<Pointer<Utf8> Function(_P)>();
    final message = getMessage(status).toDartString();
    _fn<Void Function(_P)>(_releaseStatus).asFunction<void Function(_P)>()(status);
    throw FormulaEngineException(message);
  }

  void _release(int index, _P object) {
    if (object != nullptr) _fn<Void Function(_P)>(index).asFunction<void Function(_P)>()(object);
  }

  _P _env() {
    final out = _arena<_P>();
    _check(
      _fn<_P Function(Int32, Pointer<Utf8>, _Pp)>(_createEnv).asFunction<_P Function(int, Pointer<Utf8>, _Pp)>()(
        _logWarning,
        'pssth'.toNativeUtf8(allocator: _arena),
        out,
      ),
    );
    return out.value;
  }

  _P _session(_P env, _P options, String path) {
    final out = _arena<_P>();
    _check(
      _fn<_P Function(_P, Pointer<Utf8>, _P, _Pp)>(
        _createSession,
      ).asFunction<_P Function(_P, Pointer<Utf8>, _P, _Pp)>()(env, path.toNativeUtf8(allocator: _arena), options, out),
    );
    return out.value;
  }

  _P _tensor(_P memory, _P data, int bytes, List<int> shape, int type) {
    final dims = _arena<Int64>(shape.length);
    for (var i = 0; i < shape.length; i++) {
      dims[i] = shape[i];
    }
    final out = _arena<_P>();
    _check(
      _fn<_P Function(_P, _P, Size, Pointer<Int64>, Size, Int32, _Pp)>(
        _createTensorWithData,
      ).asFunction<_P Function(_P, _P, int, Pointer<Int64>, int, int, _Pp)>()(
        memory,
        data,
        bytes,
        dims,
        shape.length,
        type,
        out,
      ),
    );
    return out.value;
  }

  /// Corre una sesión y devuelve su única salida (hay que liberarla).
  _P _runSession(_P session, List<String> inputNames, List<_P> inputs, String outputName) {
    final names = _arena<Pointer<Utf8>>(inputNames.length);
    final values = _arena<_P>(inputs.length);
    for (var i = 0; i < inputs.length; i++) {
      names[i] = inputNames[i].toNativeUtf8(allocator: _arena);
      values[i] = inputs[i];
    }
    final outputNames = _arena<Pointer<Utf8>>();
    outputNames.value = outputName.toNativeUtf8(allocator: _arena);
    final out = _arena<_P>();
    out.value = nullptr;
    _check(
      _fn<_P Function(_P, _P, Pointer<Pointer<Utf8>>, _Pp, Size, Pointer<Pointer<Utf8>>, Size, _Pp)>(
        _run,
      ).asFunction<_P Function(_P, _P, Pointer<Pointer<Utf8>>, _Pp, int, Pointer<Pointer<Utf8>>, int, _Pp)>()(
        session,
        nullptr,
        names,
        values,
        inputs.length,
        outputNames,
        1,
        out,
      ),
    );
    return out.value;
  }

  Pointer<Float> _floats(_P value) {
    final out = _arena<_P>();
    _check(_fn<_P Function(_P, _Pp)>(_getTensorMutableData).asFunction<_P Function(_P, _Pp)>()(value, out));
    return out.value.cast<Float>();
  }

  List<int> _shape(_P value) {
    final info = _arena<_P>();
    _check(_fn<_P Function(_P, _Pp)>(_getTensorTypeAndShape).asFunction<_P Function(_P, _Pp)>()(value, info));
    try {
      final count = _arena<Size>();
      _check(
        _fn<_P Function(_P, Pointer<Size>)>(_getDimensionsCount).asFunction<_P Function(_P, Pointer<Size>)>()(
          info.value,
          count,
        ),
      );
      final dims = _arena<Int64>(count.value);
      _check(
        _fn<_P Function(_P, Pointer<Int64>, Size)>(_getDimensions).asFunction<_P Function(_P, Pointer<Int64>, int)>()(
          info.value,
          dims,
          count.value,
        ),
      );
      return [for (var i = 0; i < count.value; i++) dims[i]];
    } finally {
      _release(_releaseTensorTypeAndShapeInfo, info.value);
    }
  }

  ({Float32List pixels, int width, int height}) unwarp(String modelPath, Float32List pixels, int w, int h) {
    _P env = nullptr, options = nullptr, memory = nullptr, session = nullptr, input = nullptr, output = nullptr;
    final data = calloc<Float>(pixels.length);
    try {
      env = _env();
      final optionsOut = _arena<_P>();
      _check(_fn<_P Function(_Pp)>(_createSessionOptions).asFunction<_P Function(_Pp)>()(optionsOut));
      options = optionsOut.value;
      final memoryOut = _arena<_P>();
      _check(
        _fn<_P Function(Int32, Int32, _Pp)>(_createCpuMemoryInfo).asFunction<_P Function(int, int, _Pp)>()(
          _arenaAllocator,
          _memTypeDefault,
          memoryOut,
        ),
      );
      memory = memoryOut.value;
      session = _session(env, options, modelPath);
      data.asTypedList(pixels.length).setAll(0, pixels);
      input = _tensor(memory, data.cast(), pixels.lengthInBytes, [1, 3, h, w], _elementFloat);
      output = _runSession(session, const ['image'], [input], 'fetch_name_0');
      final shape = _shape(output);
      final height = shape[2], width = shape[3];
      final copy = Float32List.fromList(_floats(output).asTypedList(3 * width * height));
      return (pixels: copy, width: width, height: height);
    } finally {
      _release(_releaseValue, output);
      _release(_releaseValue, input);
      _release(_releaseSession, session);
      _release(_releaseMemoryInfo, memory);
      _release(_releaseSessionOptions, options);
      _release(_releaseEnv, env);
      calloc.free(data);
      _arena.releaseAll();
    }
  }

  List<List<int>> read(String encoderPath, String decoderPath, List<Float32List> images, int size) {
    _P env = nullptr, options = nullptr, memory = nullptr, encoder = nullptr, decoder = nullptr;
    try {
      env = _env();
      final optionsOut = _arena<_P>();
      _check(_fn<_P Function(_Pp)>(_createSessionOptions).asFunction<_P Function(_Pp)>()(optionsOut));
      options = optionsOut.value;
      final memoryOut = _arena<_P>();
      _check(
        _fn<_P Function(Int32, Int32, _Pp)>(_createCpuMemoryInfo).asFunction<_P Function(int, int, _Pp)>()(
          _arenaAllocator,
          _memTypeDefault,
          memoryOut,
        ),
      );
      memory = memoryOut.value;
      encoder = _session(env, options, encoderPath);
      decoder = _session(env, options, decoderPath);

      return [for (final pixels in images) _readOne(memory, encoder, decoder, pixels, size)];
    } finally {
      _release(_releaseSession, decoder);
      _release(_releaseSession, encoder);
      _release(_releaseMemoryInfo, memory);
      _release(_releaseSessionOptions, options);
      _release(_releaseEnv, env);
      _arena.releaseAll();
    }
  }

  List<int> _readOne(_P memory, _P encoder, _P decoder, Float32List pixels, int size) {
    final data = calloc<Float>(pixels.length);
    final tokens = calloc<Int64>(_maxSteps + 1);
    _P image = nullptr, hidden = nullptr;
    try {
      data.asTypedList(pixels.length).setAll(0, pixels);
      image = _tensor(memory, data.cast(), pixels.lengthInBytes, [1, 3, size, size], _elementFloat);
      hidden = _runSession(encoder, const ['pixel_values'], [image], 'last_hidden_state');
      final ids = <int>[_startToken];
      for (var step = 0; step < _maxSteps; step++) {
        for (var i = 0; i < ids.length; i++) {
          tokens[i] = ids[i];
        }
        final input = _tensor(memory, tokens.cast(), ids.length * 8, [1, ids.length], _elementInt64);
        _P logits = nullptr;
        try {
          logits = _runSession(decoder, const ['input_ids', 'encoder_hidden_states'], [input, hidden], 'logits');
          final vocabulary = _shape(logits)[2];
          final all = _floats(logits);
          final last = (ids.length - 1) * vocabulary;
          var best = 0;
          var bestScore = double.negativeInfinity;
          for (var i = 0; i < vocabulary; i++) {
            final score = all[last + i];
            if (score > bestScore) {
              bestScore = score;
              best = i;
            }
          }
          if (best == _endToken) return ids.sublist(1);
          ids.add(best);
        } finally {
          _release(_releaseValue, logits);
          _release(_releaseValue, input);
        }
      }
      return ids.sublist(1);
    } finally {
      _release(_releaseValue, hidden);
      _release(_releaseValue, image);
      calloc.free(data);
      calloc.free(tokens);
    }
  }
}
