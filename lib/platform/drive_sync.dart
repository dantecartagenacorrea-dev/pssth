import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../data/sync_service.dart';

/// Id del cliente web de Google Cloud, proyecto pssth-514022 (no es secreto:
/// identifica la app). Se puede cambiar al compilar con
/// --dart-define=GOOGLE_WEB_CLIENT_ID=...
const kGoogleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue:
      '858392211519-8u0l3n0lfhgnc5spcrn9uk2ljetbtdqd.apps.googleusercontent.com',
);

/// La cuenta de Google de la persona y su carpeta oculta de Drive
/// (appDataFolder): solo esta app la ve, no aparece entre sus archivos.
class DriveSync {
  DriveSync._();
  static final instance = DriveSync._();

  static const _scopes = [drive.DriveApi.driveAppdataScope];
  static const _stateName = 'pssth_sync.json';

  bool get configured => kGoogleWebClientId.isNotEmpty;

  GoogleSignInAccount? _account;
  GoogleSignInAccount? get account => _account;

  Future<void>? _init;
  Future<void> _ready() => _init ??= GoogleSignIn.instance.initialize(serverClientId: kGoogleWebClientId);

  /// Entra sin preguntar si ya había entrado antes; null si no.
  Future<GoogleSignInAccount?> signInSilently() async {
    if (!configured) return null;
    await _ready();
    final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
    return _account = attempt == null ? null : await attempt;
  }

  /// Entra con la cuenta que elija la persona y pide permiso para la carpeta
  /// de la app. Solo desde un botón (Android lo exige).
  Future<GoogleSignInAccount> signIn() async {
    await _ready();
    final account = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
    await account.authorizationClient.authorizeScopes(_scopes);
    return _account = account;
  }

  Future<void> signOut() async {
    await _ready();
    await GoogleSignIn.instance.signOut();
    _account = null;
  }

  /// Drive con el permiso ya dado; null si hay que volver a pedirlo con un
  /// botón ([interactive]).
  Future<drive.DriveApi?> _api({bool interactive = false}) async {
    final account = _account;
    if (account == null) return null;
    final auth =
        await account.authorizationClient.authorizationForScopes(_scopes) ??
        (interactive ? await account.authorizationClient.authorizeScopes(_scopes) : null);
    return auth == null ? null : drive.DriveApi(auth.authClient(scopes: _scopes));
  }

  /// El archivo de sincronización de esta persona.
  Future<SyncRemote?> stateFile({bool interactive = false}) async {
    final api = await _api(interactive: interactive);
    return api == null ? null : _DriveFile(api, _stateName, 'application/json');
  }

  /// Huellas de los documentos que ya están en su Drive.
  Future<Set<String>> uploadedDocs() async {
    final api = await _api();
    if (api == null) return {};
    final out = <String>{};
    String? page;
    do {
      final list = await api.files.list(
        spaces: 'appDataFolder',
        q: "name contains 'doc-'",
        pageSize: 1000,
        pageToken: page,
        $fields: 'nextPageToken, files(name)',
      );
      for (final f in list.files ?? const <drive.File>[]) {
        final name = f.name ?? '';
        if (name.startsWith('doc-')) out.add(name.substring(4).split('.').first);
      }
      page = list.nextPageToken;
    } while (page != null);
    return out;
  }

  static String _docName(String hash, String ext) => 'doc-$hash.$ext';

  Future<void> uploadDoc(String hash, File file) async {
    final api = await _api();
    if (api == null) return;
    final ext = file.path.split('.').last;
    await api.files.create(
      drive.File(name: _docName(hash, ext), parents: ['appDataFolder']),
      uploadMedia: drive.Media(file.openRead(), await file.length()),
    );
  }

  /// Baja el documento de [hash]; null si no está en su Drive.
  Future<List<int>?> downloadDoc(String hash) async {
    final api = await _api();
    if (api == null) return null;
    final list = await api.files.list(spaces: 'appDataFolder', q: "name contains 'doc-$hash'", $fields: 'files(id)');
    final id = list.files?.firstOrNull?.id;
    if (id == null) return null;
    final media = await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }
}

/// Un archivo con nombre fijo en la carpeta oculta de la app.
class _DriveFile implements SyncRemote {
  _DriveFile(this._api, this._name, this._type);
  final drive.DriveApi _api;
  final String _name;
  final String _type;

  Future<String?> _id() async {
    final list = await _api.files.list(spaces: 'appDataFolder', q: "name = '$_name'", $fields: 'files(id)');
    return list.files?.firstOrNull?.id;
  }

  @override
  Future<String?> read() async {
    final id = await _id();
    if (id == null) return null;
    final media = await _api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    return utf8.decodeStream(media.stream);
  }

  @override
  Future<void> write(String json) async {
    final bytes = utf8.encode(json);
    final media = drive.Media(Stream.value(bytes), bytes.length, contentType: _type);
    final id = await _id();
    if (id == null) {
      await _api.files.create(
        drive.File(name: _name, parents: ['appDataFolder']),
        uploadMedia: media,
      );
    } else {
      await _api.files.update(drive.File(), id, uploadMedia: media);
    }
  }
}
