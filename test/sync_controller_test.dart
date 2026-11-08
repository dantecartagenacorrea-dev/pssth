import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lector_pdf/data/library_store.dart';
import 'package:lector_pdf/data/sync_service.dart';
import 'package:lector_pdf/domain/library_entry.dart';
import 'package:lector_pdf/domain/sync_state.dart';
import 'package:lector_pdf/platform/drive_sync.dart';
import 'package:lector_pdf/services/sync_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Remote implements SyncRemote {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String json) async {}
}

class _Drive implements DriveSync {
  bool permission = true;
  final downloaded = <String>[];

  @override
  bool get configured => true;
  @override
  Future<GoogleSignInAccount?> signInSilently() async => null;
  @override
  Future<SyncRemote?> stateFile({bool interactive = false}) async => permission ? _Remote() : null;
  @override
  Future<Set<String>> uploadedDocs() async => {};
  @override
  Future<List<int>?> downloadDoc(String hash) async {
    downloaded.add(hash);
    return [1, 2, 3];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service implements SyncService {
  _Service(this.docs);
  List<CloudDoc> docs;

  @override
  Future<SyncState> syncWith(SyncRemote remote) async => const SyncState();
  @override
  List<CloudDoc> cloudOnly(SyncState state) => docs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Library implements LibraryStore {
  final imported = <String>[];

  @override
  LibraryData get data => LibraryData();
  @override
  Future<LibraryEntry> importFile({required String originalName, required List<int> bytes, bool scanned = false}) async {
    imported.add(originalName);
    return LibraryEntry(id: originalName, name: originalName, storedPath: originalName, pageCount: 1, totalChunks: 1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CloudDoc _doc(String hash) => CloudDoc(hash: hash, name: '$hash.pdf', kind: 'pdf');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('baja sola los documentos de otros aparatos, menos los que se borraron aquí', () async {
    final drive = _Drive();
    final library = _Library();
    final sync = SyncController(service: _Service([_doc('a'), _doc('b')]), library: library, drive: drive);
    sync.status.value = const SyncStatus(email: 'x@gmail.com');

    await sync.keepOff('b');
    await sync.syncNow();

    expect(drive.downloaded, ['a']);
    expect(library.imported, ['a.pdf']);
    expect(sync.status.value.error, isNull);
  });

  test('pregunta una sola vez si quiere conectar su Drive', () async {
    final sync = SyncController(service: _Service([]), library: _Library(), drive: _Drive());
    await sync.start(); // no había entrado antes

    expect(await sync.shouldOffer(), isTrue);
    await sync.markOffered();
    expect(await sync.shouldOffer(), isFalse);
  });

  test('si Google quita el permiso, pide autorizar de nuevo en vez de fallar callado', () async {
    final drive = _Drive()..permission = false;
    final sync = SyncController(service: _Service([]), library: _Library(), drive: drive);
    sync.status.value = const SyncStatus(email: 'x@gmail.com');

    await sync.syncNow();

    expect(sync.needsAuthorization.value, isTrue);
  });

  test('quien había autorizado y no entra solo al abrir, recibe el pedido de autorizar', () async {
    SharedPreferences.setMockInitialValues({'sync_on': true});
    final sync = SyncController(service: _Service([]), library: _Library(), drive: _Drive());

    await sync.start();

    expect(sync.needsAuthorization.value, isTrue);
  });
}
