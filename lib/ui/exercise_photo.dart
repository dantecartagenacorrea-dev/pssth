import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'math_camera_screen.dart';

/// La foto de un ejercicio: [full] es la foto entera cuando [path] es el
/// recorte del recuadro de la cámara.
typedef ExercisePhoto = ({String path, String? full});

/// Pide la foto. La cámara es la propia, con recuadro (como en las apps de
/// matemáticas); de la galería se elige una foto entera. null si se cancela.
Future<ExercisePhoto?> takeExercisePhoto(BuildContext context, ImageSource source) async {
  if (source == ImageSource.camera) {
    final shot = await Navigator.of(
      context,
    ).push<({String cropped, String full})>(MaterialPageRoute(builder: (_) => const MathCameraScreen()));
    return shot == null ? null : (path: shot.cropped, full: shot.full);
  }
  final picked = await ImagePicker().pickImage(source: source, imageQuality: 95);
  return picked == null ? null : (path: picked.path, full: null);
}

/// Borra las copias que dejó la cámara (las de la galería no son nuestras).
Future<void> deleteExercisePhoto(ExercisePhoto photo) async {
  final full = photo.full;
  if (full == null) return;
  for (final temp in [photo.path, full]) {
    try {
      await File(temp).delete();
    } on FileSystemException {
      // son temporales: si no se borran, no pasa nada
    }
  }
}
