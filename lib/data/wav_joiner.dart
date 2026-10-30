import 'dart:io';
import 'dart:typed_data';

import '../core/app_exception.dart';

/// Une varios WAV (PCM) en uno solo sin tenerlos todos en memoria: escribe la
/// cabecera al principio y corrige los tamaños al cerrar. Todos deben tener el
/// mismo formato (la misma voz).
class WavJoiner {
  WavJoiner(this.path);
  final String path;

  RandomAccessFile? _out;
  int? _rate, _channels, _bits;
  int _dataBytes = 0;

  int get dataBytes => _dataBytes;

  /// Agrega el audio de un WAV completo ([wav] con su cabecera).
  Future<void> add(Uint8List wav) async {
    final f = readWavFormat(wav);
    if (_out == null) {
      _rate = f.sampleRate;
      _channels = f.channels;
      _bits = f.bits;
      _out = await File(path).open(mode: FileMode.write);
      await _out!.writeFrom(_header(0));
    } else if (f.sampleRate != _rate || f.channels != _channels || f.bits != _bits) {
      throw AppException('La voz cambió mientras se preparaba el audio. Inténtalo de nuevo.');
    }
    await _out!.writeFrom(wav, f.dataStart, f.dataStart + f.dataLength);
    _dataBytes += f.dataLength;
  }

  /// Cierra el archivo con los tamaños correctos. Devuelve false si no se
  /// agregó nada.
  Future<bool> close() async {
    final out = _out;
    if (out == null) return false;
    await out.setPosition(0);
    await out.writeFrom(_header(_dataBytes));
    await out.close();
    _out = null;
    return true;
  }

  Uint8List _header(int dataBytes) {
    final b = ByteData(44);
    void tag(int at, String s) {
      for (var i = 0; i < 4; i++) {
        b.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    final blockAlign = _channels! * _bits! ~/ 8;
    tag(0, 'RIFF');
    b.setUint32(4, 36 + dataBytes, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, _channels!, Endian.little);
    b.setUint32(24, _rate!, Endian.little);
    b.setUint32(28, _rate! * blockAlign, Endian.little);
    b.setUint16(32, blockAlign, Endian.little);
    b.setUint16(34, _bits!, Endian.little);
    tag(36, 'data');
    b.setUint32(40, dataBytes, Endian.little);
    return b.buffer.asUint8List();
  }
}

typedef WavFormat = ({int sampleRate, int channels, int bits, int dataStart, int dataLength});

/// Formato y ubicación de los datos de un WAV PCM (los fragmentos pueden venir
/// en cualquier orden).
WavFormat readWavFormat(Uint8List wav) {
  String tag(int at) => String.fromCharCodes(wav.sublist(at, at + 4));
  if (wav.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('No es un WAV');
  }
  final b = ByteData.sublistView(wav);
  int? rate, channels, bits;
  var at = 12;
  while (at + 8 <= wav.length) {
    final id = tag(at);
    final size = b.getUint32(at + 4, Endian.little);
    final body = at + 8;
    if (id == 'fmt ') {
      if (b.getUint16(body, Endian.little) != 1) throw const FormatException('El WAV no es PCM');
      channels = b.getUint16(body + 2, Endian.little);
      rate = b.getUint32(body + 4, Endian.little);
      bits = b.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (rate == null) throw const FormatException('WAV sin formato');
      final length = size > wav.length - body ? wav.length - body : size;
      return (sampleRate: rate, channels: channels!, bits: bits!, dataStart: body, dataLength: length);
    }
    at = body + size + (size & 1);
  }
  throw const FormatException('WAV sin datos');
}
