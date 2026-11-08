import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lector_pdf/data/library_store.dart';
import 'package:lector_pdf/data/sync_service.dart';
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

String _hash(String content) => sha256.convert(utf8.encode(content)).toString();

class _Drive implements DriveSync {
  bool permission = true;
  final files = <String, String>{};
  final downloaded = <String>[];

  @override
  bool get configured => true;
  @override
  Future<GoogleSignInAccount?> signInSilently() async => null;
  @override
  Future<GoogleSignInAccount> signIn() async => throw Exception('canceled');
  @override
  Future<SyncRemote?> stateFile({bool interactive = false}) async => permission ? _Remote() : null;
  @override
  Future<Set<String>> uploadedDocs() async => {};
  @override
  Future<void> uploadDoc(String hash, File file) async {}
  @override
  Future<bool> downloadDoc(String hash, File target) async {
    final content = files[hash];
    if (content == null) return false;
    downloaded.add(hash);
    await target.writeAsString(content);
    return true;
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

CloudDoc _doc(String content) => CloudDoc(hash: _hash(content), name: '$content.pdf', kind: 'pdf');

void main() {
  late Directory tmp;
  late LibraryStore library;
  late _Drive drive;
  var network = [ConnectivityResult.wifi];

  SyncController make(List<CloudDoc> docs) =>
      SyncController(service: _Service(docs), library: library, drive: drive, network: () async => network);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    network = [ConnectivityResult.wifi];
    tmp = Directory.systemTemp.createTempSync('sync');
    library = LibraryStore();
    await library.initAt(tmp);
    drive = _Drive();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('con Wi-Fi baja al disco los documentos de otros aparatos, menos los borrados aquí', () async {
    drive.files.addAll({_hash('a'): 'a', _hash('b'): 'b'});
    final sync = make([_doc('a'), _doc('b')]);
    sync.status.value = const SyncStatus(email: 'x@gmail.com');

    await sync.keepOff(_hash('b'));
    await sync.syncNow();

    expect(drive.downloaded, [_hash('a')]);
    final entry = library.data.entries.single;
    expect(entry.name, 'a.pdf');
    expect(entry.contentHash, _hash('a'));
    expect(File(entry.storedPath).readAsStringSync(), 'a');
    expect(tmp.listSync().where((f) => f.path.contains('.llegando-')), isEmpty);
    expect(sync.status.value.error, isNull);
  });

  test('con datos móviles no baja documentos', () async {
    network = [ConnectivityResult.mobile];
    drive.files[_hash('a')] = 'a';
    final sync = make([_doc('a')]);
    sync.status.value = const SyncStatus(email: 'x@gmail.com');

    await sync.syncNow();

    expect(drive.downloaded, isEmpty);
  });

  test('un documento que llega dañado no entra a la biblioteca', () async {
    drive.files[_hash('a')] = 'otra cosa';
    final sync = make([_doc('a')]);
    sync.status.value = const SyncStatus(email: 'x@gmail.com');

    await sync.syncNow();

    expect(library.data.entries, isEmpty);
    expect(tmp.listSync().where((f) => f.path.contains('.llegando-')), isEmpty);
  });

  test('pregunta una sola vez si quiere conectar su Drive', () async {
    final sync = make([]);
    await sync.start(); // no había entrado antes

    expect(await sync.shouldOffer(), isTrue);
    await sync.markOffered();
    expect(await sync.shouldOffer(), isFalse);
  });

  test('si Google quita el permiso pide autorizar, y se apaga cuando vuelve a funcionar', () async {
    drive.permission = false;
    final sync = make([]);
    sync.status.value = const SyncStatus(email: 'x@gmail.com');

    await sync.syncNow();
    expect(sync.needsAuthorization.value, isTrue);

    drive.permission = true;
    await sync.syncNow();
    expect(sync.needsAuthorization.value, isFalse);
  });

  test('sin internet no pide autorizar', () async {
    network = [ConnectivityResult.none];
    drive.permission = false;
    SharedPreferences.setMockInitialValues({'sync_on': true});
    final sync = make([]);

    await sync.start();
    expect(sync.needsAuthorization.value, isFalse);

    sync.status.value = const SyncStatus(email: 'x@gmail.com');
    await sync.syncNow();
    expect(sync.needsAuthorization.value, isFalse);
  });

  test('quien había autorizado y no entra solo al abrir, recibe el pedido de autorizar', () async {
    SharedPreferences.setMockInitialValues({'sync_on': true});
    final sync = make([]);

    await sync.start();

    expect(sync.needsAuthorization.value, isTrue);
  });

  test('cancelar la autorización estando conectada no la desconecta', () async {
    final sync = make([]);
    sync.status.value = const SyncStatus(email: 'x@gmail.com');

    await sync.signIn();

    expect(sync.status.value.email, 'x@gmail.com');
    expect(sync.status.value.error, isNotNull);
  });
}
