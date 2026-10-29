import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/ui/swarm.dart';

void main() {
  testWidgets('recoge cada letra con su color y peso, los íconos con su fuente, sin texto invisible', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: key,
        appBar: AppBar(title: const Text('Hola')),
        body: Column(children: [
          const Text('ab', style: TextStyle(color: Colors.red, fontSize: 20)),
          const Text.rich(TextSpan(
            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w700),
            children: [TextSpan(text: 'C'), TextSpan(text: 'd', style: TextStyle(fontWeight: FontWeight.w400))],
          )),
          const Icon(Icons.add),
          const Text('zz', style: TextStyle(color: Colors.transparent)),
        ]),
      ),
    ));
    final all = collectGlyphs(key.currentContext!);
    final icons = all.where((g) => g.family != null).toList();
    expect(icons.single.ch, String.fromCharCode(Icons.add.codePoint));
    expect(icons.single.family, 'MaterialIcons');
    final glyphs = all.where((g) => g.family == null).toList();
    expect(glyphs.map((g) => g.ch).toList()..sort(), ['C', 'H', 'a', 'a', 'b', 'd', 'l', 'o']);
    final a = glyphs.firstWhere((g) => g.ch == 'a');
    expect(a.color, Colors.red);
    expect(a.size, 20);
    expect(glyphs.firstWhere((g) => g.ch == 'C').bold, isTrue);
    expect(glyphs.firstWhere((g) => g.ch == 'd').bold, isFalse);
  });
}
