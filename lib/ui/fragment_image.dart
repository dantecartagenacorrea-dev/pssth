import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Una imagen (la hoja escaneada) que se arma desde la dispersión: está
/// partida en fragmentos que vuelan girando desde lejos hasta su lugar, como
/// las letras del enjambre. Al cambiar la imagen (otro filtro) los fragmentos
/// se sueltan un poco y se vuelven a juntar. Ya armada se dibuja entera.
class FragmentImage extends StatefulWidget {
  const FragmentImage({super.key, required this.jpeg});
  final Uint8List jpeg;

  @override
  State<FragmentImage> createState() => _FragmentImageState();
}

class _FragmentImageState extends State<FragmentImage> with SingleTickerProviderStateMixin {
  static const _cols = 22;
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  ui.Image? _image;
  List<_Shard> _shards = const [];
  double _spread = 1;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load(widget.jpeg, spread: 1);
  }

  @override
  void didUpdateWidget(FragmentImage old) {
    super.didUpdateWidget(old);
    if (!identical(old.jpeg, widget.jpeg)) _load(widget.jpeg, spread: 0.3);
  }

  Future<void> _load(Uint8List bytes, {required double spread}) async {
    final my = ++_gen;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted || my != _gen) {
      frame.image.dispose();
      return;
    }
    final img = frame.image;
    final rows = math.max(1, (_cols * img.height / img.width).round());
    final rnd = math.Random(my);
    setState(() {
      _image?.dispose();
      _image = img;
      _spread = spread;
      _shards = [
        for (var r = 0; r < rows; r++)
          for (var c = 0; c < _cols; c++) _Shard(c, r, _cols, rows, rnd),
      ];
    });
    _anim.forward(from: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, box) {
        final fit = math.min(box.maxWidth / img.width, box.maxHeight / img.height);
        final size = Size(img.width * fit, img.height * fit);
        return Center(
          child: CustomPaint(
            size: size,
            painter: _ShardPainter(img, _shards, _anim, _spread, fit),
          ),
        );
      },
    );
  }
}

class _Shard {
  _Shard(this.col, this.row, int cols, int rows, math.Random r)
      : delay = r.nextDouble() * 0.45,
        angle = (r.nextDouble() - 0.5) * math.pi * 2,
        dx = (r.nextDouble() - 0.5) * 2.2,
        dy = (r.nextDouble() - 0.5) * 2.2 + 0.35, // suben un poco desde abajo
        ux = col / cols,
        uy = row / rows,
        uw = 1 / cols,
        uh = 1 / rows;

  final int col, row;
  final double delay, angle, dx, dy;
  final double ux, uy, uw, uh; // trozo de la imagen, en fracciones
}

class _ShardPainter extends CustomPainter {
  _ShardPainter(this.image, this.shards, this.anim, this.spread, this.fit) : super(repaint: anim);

  final ui.Image image;
  final List<_Shard> shards;
  final Animation<double> anim;
  final double spread;
  final double fit;

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    final dst = Offset.zero & size;
    if (t >= 1) {
      canvas.drawImageRect(image, Offset.zero & Size(image.width.toDouble(), image.height.toDouble()), dst,
          Paint()..filterQuality = FilterQuality.medium);
      return;
    }
    final w = image.width.toDouble(), h = image.height.toDouble();
    final transforms = <ui.RSTransform>[], rects = <Rect>[], colors = <Color>[];
    for (final s in shards) {
      final p = Curves.easeOutCubic.transform(((t - s.delay) / 0.55).clamp(0.0, 1.0));
      final away = (1 - p) * spread;
      final src = Rect.fromLTWH(s.ux * w, s.uy * h, s.uw * w, s.uh * h);
      final home = Offset((s.ux + s.uw / 2) * size.width, (s.uy + s.uh / 2) * size.height);
      transforms.add(ui.RSTransform.fromComponents(
        rotation: s.angle * away,
        scale: fit * (1 - 0.6 * away),
        anchorX: src.width / 2,
        anchorY: src.height / 2,
        translateX: home.dx + s.dx * size.width * away,
        translateY: home.dy + s.dy * size.height * away,
      ));
      rects.add(src);
      colors.add(Colors.white.withValues(alpha: (0.15 + 0.85 * p).clamp(0.0, 1.0)));
    }
    canvas.drawAtlas(image, transforms, rects, colors, BlendMode.modulate, null, Paint()..filterQuality = FilterQuality.low);
  }

  @override
  bool shouldRepaint(_ShardPainter old) => old.image != image || old.spread != spread || old.fit != fit;
}
