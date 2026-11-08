import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/bookmark.dart';
import '../domain/highlight.dart';
import '../domain/sync_state.dart';
import 'bookmark_store.dart';
import 'highlight_store.dart';
import 'library_store.dart';
import 'listening_store.dart';
import 'pronunciation_store.dart';

/// Un documento que está en otro aparato (y en el Drive) pero no en este.
class CloudDoc {
  const CloudDoc({required this.hash, required this.name, required this.kind, this.openedIso});
  final String hash;
  final String name;
  final String kind;
  final String? openedIso;
}

/// Dónde se comparte el estado entre aparatos (en la app, un archivo oculto
/// en el Google Drive de la persona). null si todavía no hay nada.
abstract class SyncRemote {
  Future<String?> read();
  Future<void> write(String json);
}

/// Sincroniza el avance, los marcadores, los subrayados, la pronunciación y
/// la escucha de este aparato con los demás. Los documentos no viajan: cada
/// aparato aplica lo de los documentos que tiene (reconocidos por su huella)
/// y lo demás queda guardado para cuando los tenga.
///
/// Borrar un documento no lo borra en los otros aparatos: solo se quita de
/// este (borrar archivos ajenos es demasiado fácil de lamentar).
class SyncService {
  SyncService({
    required this.file,
    required this.library,
    required this.bookmarks,
    required this.highlights,
    required this.pronunciation,
    required this.listening,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Lo último sincronizado en este aparato: el estado, qué claves había
  /// aquí y el nombre de este aparato.
  final File file;
  final LibraryStore library;
  final BookmarkStore bookmarks;
  final HighlightStore highlights;
  final PronunciationStore pronunciation;
  final ListeningStore listening;
  final int Function() _clock;

  /// Devuelve lo que quedó en la nube (para ver qué documentos hay en otros
  /// aparatos y no en este).
  Future<SyncState> syncWith(SyncRemote remote) async {
    await library.ensureHashes();
    final saved = await _readSaved();
    final local = await _localRecords();
    final mine = observeLocal(
      last: saved.state,
      lastLocalKeys: saved.localKeys,
      local: local,
      changedAt: _readTimes(),
      device: saved.device,
      deviceListening: await listening.days(),
      now: _clock(),
    );
    final merged = mergeStates(mine, _parse(await remote.read()));
    // Primero a la nube: si algo falla después, lo de este aparato ya está a salvo.
    await remote.write(jsonEncode(merged.toJson()));
    // Se editó algo mientras se hablaba con la nube: aplicar pisaría ese cambio.
    // Queda para la próxima sincronización, que lo verá y lo juntará.
    if (jsonEncode(await _localRecords()) != jsonEncode(local)) return merged;
    await _apply(merged);
    final after = await _localRecords();
    await _writeSaved(device: saved.device, state: merged, localKeys: after.keys.toSet());
    listening.setOtherDevices(combinedListening(SyncState(listening: {...merged.listening}..remove(saved.device))));
    return merged;
  }

  /// Otra cuenta de Google: lo guardado de la anterior no debe pasar a esta.
  Future<void> forgetAccount() async {
    if (await file.exists()) await file.delete();
  }

  /// Documentos que están en otros aparatos y no en este (por su huella).
  List<CloudDoc> cloudOnly(SyncState state) {
    final here = {for (final e in library.data.entries) ?e.contentHash};
    final out = <CloudDoc>[];
    for (final r in state.records.entries) {
      final data = r.value.data;
      if (!r.key.startsWith('doc:') || data is! Map) continue;
      final hash = r.key.substring(4);
      if (here.contains(hash)) continue;
      out.add(
        CloudDoc(
          hash: hash,
          name: data['name'] as String? ?? 'Documento',
          kind: data['kind'] as String? ?? 'pdf',
          openedIso: data['opened'] as String?,
        ),
      );
    }
    return out..sort((a, b) => (b.openedIso ?? '').compareTo(a.openedIso ?? ''));
  }

  /// El avance de un documento vale desde la última vez que se leyó; uno que
  /// nunca se empezó pierde contra cualquiera (un aparato nuevo no borra
  /// lo leído en otro).
  Map<String, int> _readTimes() => {
    for (final e in library.data.entries)
      if (e.contentHash != null)
        'doc:${e.contentHash}': e.pageIndex == 0 && e.chunkIndex == 0 && !e.finished
            ? 0
            : DateTime.tryParse(e.lastOpenedIso ?? '')?.millisecondsSinceEpoch ?? 0,
  };

  static SyncState _parse(String? text) {
    if (text == null) return const SyncState();
    try {
      final j = jsonDecode(text);
      return j is Map<String, dynamic> ? SyncState.fromJson(j) : const SyncState();
    } on FormatException {
      return const SyncState();
    }
  }

  /// Todo lo de este aparato, con claves que valen en cualquier aparato: el
  /// documento va por su huella, no por su número local.
  Future<Map<String, Object?>> _localRecords() async {
    final hashOf = {
      for (final e in library.data.entries)
        if (e.contentHash != null) e.id: e.contentHash!,
    };
    return {
      for (final e in library.data.entries)
        if (e.contentHash != null)
          'doc:${e.contentHash}': {
            'name': e.name,
            'kind': e.kind,
            'page': e.pageIndex,
            'chunk': e.chunkIndex,
            'finished': e.finished,
            'favorite': e.favorite,
            'opened': e.lastOpenedIso,
          },
      for (final b in await bookmarks.all())
        if (hashOf[b.documentId] case final doc?)
          'bm:${b.id}': {
            'doc': doc,
            'page': b.pageIndex,
            'chunk': b.chunkIndex,
            'label': b.label,
            'created': b.createdIso,
          },
      for (final h in await highlights.all())
        if (hashOf[h.documentId] case final doc?)
          'hl:${h.id}': {
            'doc': doc,
            'page': h.pageIndex,
            'chunk': h.chunkIndex,
            'text': h.text,
            'note': h.note,
            'created': h.createdIso,
          },
      for (final p in (await pronunciation.load()).entries) 'pr:${p.key}': p.value,
    };
  }

  /// Deja este aparato como quedó la mezcla (solo lo de sus documentos).
  Future<void> _apply(SyncState merged) async {
    final idOf = {
      for (final e in library.data.entries)
        if (e.contentHash != null) e.contentHash!: e.id,
    };
    final marks = <Bookmark>[], lines = <Highlight>[], words = <String, String>{};
    for (final r in merged.records.entries) {
      final data = r.value.data;
      if (data == null) continue;
      final (kind, key) = _split(r.key);
      if (kind == 'pr' && data is String) {
        words[key] = data;
        continue;
      }
      if (data is! Map) continue;
      final docId = kind == 'doc' ? idOf[key] : idOf[data['doc']];
      if (docId == null) continue; // ese documento no está en este aparato
      int number(String k) => (data[k] as num?)?.toInt() ?? 0;
      String text(String k) => data[k] as String? ?? '';
      switch (kind) {
        case 'doc':
          final e = library.byId(docId)!;
          if (e.pageIndex != number('page') ||
              e.chunkIndex != number('chunk') ||
              e.finished != (data['finished'] == true) ||
              e.favorite != (data['favorite'] == true) ||
              e.lastOpenedIso != data['opened']) {
            await library.applySynced(
              docId,
              pageIndex: number('page'),
              chunkIndex: number('chunk'),
              finished: data['finished'] == true,
              favorite: data['favorite'] == true,
              lastOpenedIso: data['opened'] as String?,
            );
          }
        case 'bm':
          marks.add(
            Bookmark(
              id: key,
              documentId: docId,
              pageIndex: number('page'),
              chunkIndex: number('chunk'),
              label: text('label'),
              createdIso: text('created'),
            ),
          );
        case 'hl':
          lines.add(
            Highlight(
              id: key,
              documentId: docId,
              pageIndex: number('page'),
              chunkIndex: number('chunk'),
              text: text('text'),
              note: text('note'),
              createdIso: text('created'),
            ),
          );
      }
    }
    // Los de documentos sin huella no viajan: se quedan como están.
    final hashed = idOf.values.toSet();
    await bookmarks.replaceAll([...(await bookmarks.all()).where((b) => !hashed.contains(b.documentId)), ...marks]);
    await highlights.replaceAll([...(await highlights.all()).where((h) => !hashed.contains(h.documentId)), ...lines]);
    await pronunciation.replaceAll(words);
  }

  static (String, String) _split(String key) {
    final i = key.indexOf(':');
    return i < 0 ? ('', key) : (key.substring(0, i), key.substring(i + 1));
  }

  Future<({String device, SyncState state, Set<String> localKeys})> _readSaved() async {
    try {
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString());
        if (j is Map<String, dynamic> && j['device'] is String) {
          return (
            device: j['device'] as String,
            state: j['state'] is Map<String, dynamic>
                ? SyncState.fromJson(j['state'] as Map<String, dynamic>)
                : const SyncState(),
            localKeys: {...((j['local'] as List?) ?? const []).map((k) => '$k')},
          );
        }
      }
    } on FormatException {
      // Dañado: se empieza de nuevo (lo de la nube y lo de aquí se juntan).
    }
    final rnd = Random.secure();
    final device = List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
    return (device: device, state: const SyncState(), localKeys: <String>{});
  }

  Future<void> _writeSaved({required String device, required SyncState state, required Set<String> localKeys}) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'device': device, 'state': state.toJson(), 'local': localKeys.toList()}),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}
