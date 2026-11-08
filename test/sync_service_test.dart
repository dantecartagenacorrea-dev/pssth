import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/bookmark_store.dart';
import 'package:lector_pdf/data/highlight_store.dart';
import 'package:lector_pdf/data/library_store.dart';
import 'package:lector_pdf/data/listening_store.dart';
import 'package:lector_pdf/data/pronunciation_store.dart';
import 'package:lector_pdf/data/sync_service.dart';

/// El archivo compartido (en la app, el Drive de la persona).
class FakeRemote implements SyncRemote {
  String? text;
  @override
  Future<String?> read() async => text;
  @override
  Future<void> write(String json) async => text = json;
}

/// Un aparato con sus almacenes en una carpeta propia.
class Device {
  Device._(this.dir, this.library, this.bookmarks, this.highlights, this.pronunciation, this.listening, this.sync);

  final Directory dir;
  final LibraryStore library;
  final BookmarkStore bookmarks;
  final HighlightStore highlights;
  final PronunciationStore pronunciation;
  final ListeningStore listening;
  final SyncService sync;

  static int _clock = 1000;

  static Future<Device> create() async {
    final dir = Directory.systemTemp.createTempSync('aparato');
    final library = LibraryStore();
    await library.initAt(Directory('${dir.path}/library'));
    final bookmarks = BookmarkStore(File('${dir.path}/bookmarks.json'));
    final highlights = HighlightStore(File('${dir.path}/highlights.json'));
    final pronunciation = PronunciationStore(File('${dir.path}/pronunciation.json'));
    final listening = ListeningStore(File('${dir.path}/listening.json'));
    final sync = SyncService(
      file: File('${dir.path}/sync.json'),
      library: library,
      bookmarks: bookmarks,
      highlights: highlights,
      pronunciation: pronunciation,
      listening: listening,
      // Cada sincronización ocurre "después" de la anterior.
      clock: () => _clock += 10,
    );
    return Device._(dir, library, bookmarks, highlights, pronunciation, listening, sync);
  }
}

/// Nube lenta: mientras se lee, la persona sigue editando.
class _EditWhileReading implements SyncRemote {
  _EditWhileReading(this.inner, this.edit);
  final SyncRemote inner;
  final Future<void> Function() edit;
  @override
  Future<String?> read() async {
    await edit();
    return inner.read();
  }

  @override
  Future<void> write(String json) => inner.write(json);
}

void main() {
  late Device tablet, phone;
  late FakeRemote drive;
  final pdf = List<int>.generate(4000, (i) => i % 251);

  setUp(() async {
    tablet = await Device.create();
    phone = await Device.create();
    drive = FakeRemote();
  });
  tearDown(() {
    tablet.dir.deleteSync(recursive: true);
    phone.dir.deleteSync(recursive: true);
  });

  test('el avance, los marcadores y las notas pasan de un aparato al otro', () async {
    final onTablet = await tablet.library.importFile(originalName: 'libro.pdf', bytes: pdf);
    final onPhone = await phone.library.importFile(originalName: 'libro.pdf', bytes: pdf);
    expect(onTablet.id, isNot(onPhone.id)); // cada aparato le da su número

    await tablet.library.updatePosition(id: onTablet.id, pageIndex: 41, chunkIndex: 3);
    await tablet.bookmarks.add(documentId: onTablet.id, pageIndex: 41, chunkIndex: 3, label: 'Clausius');
    await tablet.highlights.add(
      documentId: onTablet.id,
      pageIndex: 41,
      chunkIndex: 3,
      text: 'La entropía',
      note: 'clave',
    );
    await tablet.pronunciation.set('SQL', 'ese cu ele');

    await tablet.sync.syncWith(drive);
    await phone.sync.syncWith(drive);

    final e = phone.library.byId(onPhone.id)!;
    expect(e.pageIndex, 41);
    expect(e.chunkIndex, 3);
    expect((await phone.bookmarks.forDocument(onPhone.id)).single.label, 'Clausius');
    expect((await phone.highlights.forDocument(onPhone.id)).single.note, 'clave');
    expect((await phone.pronunciation.load())['SQL'], 'ese cu ele');
  });

  test('un aparato nuevo no borra lo leído en otro; si lee después, gana él', () async {
    final onTablet = await tablet.library.importFile(originalName: 'libro.pdf', bytes: pdf);
    await tablet.library.updatePosition(id: onTablet.id, pageIndex: 80, chunkIndex: 2);
    await tablet.sync.syncWith(drive);
    // El teléfono lo importa más tarde (lo "abre" después) pero no lo leyó.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final onPhone = await phone.library.importFile(originalName: 'libro.pdf', bytes: pdf);
    await phone.sync.syncWith(drive);
    expect(phone.library.byId(onPhone.id)!.pageIndex, 80);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await phone.library.updatePosition(id: onPhone.id, pageIndex: 95, chunkIndex: 0);
    await phone.sync.syncWith(drive);
    await tablet.sync.syncWith(drive);
    expect(tablet.library.byId(onTablet.id)!.pageIndex, 95);
  });

  test('lo borrado en un aparato se borra en el otro', () async {
    final onTablet = await tablet.library.importFile(originalName: 'libro.pdf', bytes: pdf);
    final onPhone = await phone.library.importFile(originalName: 'libro.pdf', bytes: pdf);
    final b = await tablet.bookmarks.add(documentId: onTablet.id, pageIndex: 2, chunkIndex: 0, label: 'x');
    await tablet.sync.syncWith(drive);
    await phone.sync.syncWith(drive);
    expect(await phone.bookmarks.forDocument(onPhone.id), hasLength(1));

    await phone.bookmarks.remove((await phone.bookmarks.forDocument(onPhone.id)).single.id);
    await phone.sync.syncWith(drive);
    await tablet.sync.syncWith(drive);
    expect(await tablet.bookmarks.forDocument(onTablet.id), isEmpty, reason: 'marcador ${b.id}');
  });

  test('quitar un documento de un aparato no borra sus marcadores ni notas en el otro', () async {
    final onTablet = await tablet.library.importFile(originalName: 'libro.pdf', bytes: pdf);
    final onPhone = await phone.library.importFile(originalName: 'libro.pdf', bytes: pdf);
    await tablet.bookmarks.add(documentId: onTablet.id, pageIndex: 2, chunkIndex: 0, label: 'x');
    await tablet.highlights.add(documentId: onTablet.id, pageIndex: 2, chunkIndex: 0, text: 't', note: 'n');
    await tablet.sync.syncWith(drive);
    await phone.sync.syncWith(drive);

    await tablet.bookmarks.removeAllFor(onTablet.id);
    await tablet.highlights.removeAllFor(onTablet.id);
    await tablet.library.remove(onTablet.id);
    await tablet.sync.syncWith(drive);
    await phone.sync.syncWith(drive);

    expect(await phone.bookmarks.forDocument(onPhone.id), hasLength(1));
    expect(await phone.highlights.forDocument(onPhone.id), hasLength(1));
    expect(phone.library.byId(onPhone.id), isNotNull);
  });

  test('un marcador creado mientras se sincroniza no se pierde', () async {
    final onTablet = await tablet.library.importFile(originalName: 'libro.pdf', bytes: pdf);
    final slow = _EditWhileReading(drive, () async {
      await tablet.bookmarks.add(documentId: onTablet.id, pageIndex: 9, chunkIndex: 0, label: 'en el medio');
    });

    await tablet.sync.syncWith(slow);
    expect((await tablet.bookmarks.forDocument(onTablet.id)).single.label, 'en el medio');

    await tablet.sync.syncWith(drive);
    await phone.library.importFile(originalName: 'libro.pdf', bytes: pdf);
    await phone.sync.syncWith(drive);
    final id = phone.library.data.entries.single.id;
    expect((await phone.bookmarks.forDocument(id)).single.label, 'en el medio');
  });

  test('al olvidar la cuenta, lo de la anterior no pasa a la nueva', () async {
    await tablet.library.importFile(originalName: 'libro.pdf', bytes: pdf);
    await tablet.pronunciation.set('SQL', 'ese cu ele');
    await tablet.sync.syncWith(drive);
    await tablet.pronunciation.remove('SQL');
    final other = FakeRemote();

    await tablet.sync.forgetAccount();
    await tablet.sync.syncWith(other);

    expect(other.text, isNot(contains('SQL')));
  });

  test('lo que solo está en un aparato queda en la nube para cuando el otro lo tenga', () async {
    final onTablet = await tablet.library.importFile(originalName: 'solo.pdf', bytes: pdf);
    await tablet.bookmarks.add(documentId: onTablet.id, pageIndex: 5, chunkIndex: 1, label: 'y');
    await tablet.sync.syncWith(drive);
    await phone.sync.syncWith(drive); // el teléfono aún no tiene el PDF
    await tablet.sync.syncWith(drive); // y eso no borra nada en la tablet
    expect(await tablet.bookmarks.forDocument(onTablet.id), hasLength(1));

    final onPhone = await phone.library.importFile(originalName: 'solo.pdf', bytes: pdf);
    await phone.sync.syncWith(drive);
    expect((await phone.bookmarks.forDocument(onPhone.id)).single.pageIndex, 5);
  });

  test('las estadísticas suman lo escuchado en los dos aparatos, sin repetir', () async {
    final today = DateTime.now();
    await tablet.listening.add(seconds: 600, words: 900, at: today);
    await phone.listening.add(seconds: 300, words: 400, at: today);
    await tablet.sync.syncWith(drive);
    await phone.sync.syncWith(drive);
    await tablet.sync.syncWith(drive);
    await tablet.sync.syncWith(drive); // sincronizar de más no suma de más

    expect((await tablet.listening.summary(now: today)).today.seconds, 900);
    expect((await phone.listening.summary(now: today)).today.seconds, 900);
    expect((await tablet.listening.days()).values.single.seconds, 600, reason: 'su archivo guarda solo lo suyo');
  });

  test('un archivo de la nube dañado no borra nada', () async {
    final onTablet = await tablet.library.importFile(originalName: 'libro.pdf', bytes: pdf);
    await tablet.bookmarks.add(documentId: onTablet.id, pageIndex: 1, chunkIndex: 0, label: 'z');
    drive.text = '{roto';
    await tablet.sync.syncWith(drive);
    expect(await tablet.bookmarks.forDocument(onTablet.id), hasLength(1));
    expect(drive.text, contains('"bm:'));
  });
}
