import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Recuadro donde se encuadra el ejercicio, en fracciones de la vista de la
/// cámara: ancho y bajo, como un renglón de cuaderno.
const _frame = Rect.fromLTWH(0.06, 0.32, 0.88, 0.26);

/// Cámara dentro de la app, como en las apps de matemáticas: se encuadra solo
/// el ejercicio en el recuadro y la foto se recorta a él (así no se lee el
/// resto de la hoja). Devuelve la ruta de la foto recortada, o null.
class MathCameraScreen extends StatefulWidget {
  const MathCameraScreen({super.key});

  @override
  State<MathCameraScreen> createState() => _MathCameraScreenState();
}

class _MathCameraScreenState extends State<MathCameraScreen> {
  CameraController? _camera;
  String? _error;
  bool _shooting = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'Este equipo no tiene cámara.');
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final cam = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await cam.initialize();
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() => _camera = cam);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'CameraAccessDenied'
            ? 'Sin permiso de cámara. Actívalo en Ajustes.'
            : 'No se pudo abrir la cámara. Ciérrala en otras apps e inténtalo de nuevo.');
      }
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final cam = _camera;
    if (cam == null || _shooting) return;
    setState(() => _shooting = true);
    try {
      final shot = await cam.takePicture();
      final dir = await getTemporaryDirectory();
      final out = '${dir.path}/ejercicio_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Isolate.run(() => _cropToFrame(shot.path, out));
      try {
        await File(shot.path).delete();
      } on FileSystemException {
        // la foto original es temporal: si no se borra, no pasa nada
      }
      if (mounted) Navigator.pop(context, out);
    } on CameraException {
      if (mounted) setState(() => _error = 'No se pudo tomar la foto. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _shooting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Foto del ejercicio')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: switch ((cam, _error)) {
                  (_, final String error) => Padding(padding: const EdgeInsets.all(24), child: Text(error, textAlign: TextAlign.center)),
                  (final CameraController c?, _) => CameraPreview(c, child: const _FrameOverlay()),
                  _ => const CircularProgressIndicator(),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: IconButton.filled(
                tooltip: 'Tomar la foto',
                iconSize: 40,
                padding: const EdgeInsets.all(18),
                onPressed: cam == null || _shooting ? null : _shoot,
                icon: _shooting
                    ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3))
                    : const Icon(CupertinoIcons.camera_fill),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El recuadro con esquinas y el resto oscurecido, encima de la cámara.
class _FrameOverlay extends StatelessWidget {
  const _FrameOverlay();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final r = Rect.fromLTWH(
            _frame.left * box.maxWidth,
            _frame.top * box.maxHeight,
            _frame.width * box.maxWidth,
            _frame.height * box.maxHeight,
          );
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _FramePainter(r))),
            Positioned(
              left: 0,
              right: 0,
              top: r.top - 40,
              child: const Text(
                'Encuadra solo el ejercicio',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ]);
        },
      );
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.frame);
  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(10)));
    canvas.drawPath(shade, Paint()..color = Colors.black54);
    final corner = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 26.0;
    for (final (p, dx, dy) in [
      (frame.topLeft, 1.0, 1.0),
      (frame.topRight, -1.0, 1.0),
      (frame.bottomLeft, 1.0, -1.0),
      (frame.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(p, p + Offset(l * dx, 0), corner);
      canvas.drawLine(p, p + Offset(0, l * dy), corner);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.frame != frame;
}

/// Recorta la foto a lo que quedó dentro del recuadro (con un poco de margen)
/// y la guarda en [out].
void _cropToFrame(String path, String out) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) throw const FileSystemException('La foto no se pudo leer.');
  final photo = img.bakeOrientation(decoded);
  final margin = 0.03;
  final left = ((_frame.left - margin).clamp(0.0, 1.0) * photo.width).round();
  final top = ((_frame.top - margin).clamp(0.0, 1.0) * photo.height).round();
  final right = ((_frame.right + margin).clamp(0.0, 1.0) * photo.width).round();
  final bottom = ((_frame.bottom + margin).clamp(0.0, 1.0) * photo.height).round();
  final cropped = img.copyCrop(photo, x: left, y: top, width: right - left, height: bottom - top);
  File(out).writeAsBytesSync(img.encodeJpg(cropped, quality: 95));
}
