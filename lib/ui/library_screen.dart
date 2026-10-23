import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_exception.dart';
import '../data/bookmark_store.dart';
import '../data/document_loader.dart';
import '../data/library_store.dart';
import '../data/model_store.dart';
import '../data/pronunciation_store.dart';
import '../data/settings_store.dart';
import '../domain/chapter_detector.dart';
import '../domain/chunk_builder.dart';
import '../domain/language_detector.dart';
import '../domain/library_entry.dart';
import '../domain/text_chunk.dart';
import '../domain/text_normalizer.dart';
import '../ocr/ocr_engine.dart';
import '../platform/native_text.dart';
import '../platform/open_file_bridge.dart';
import '../platform/speech_transcriber.dart';
import '../platform/whisper_transcriber.dart';
import '../playback/tts_audio_handler.dart';
import '../services/llm_cleaner.dart';
import 'player_screen.dart';
import 'recorder_screen.dart';
import 'voices_screen.dart';
import 'pronunciation_screen.dart';

/// Versión mostrada en "Acerca de" (mantener igual que pubspec.yaml).
const String kAppVersion = '1.0.0';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.handler,
    required this.libraryStore,
    required this.settingsStore,
    required this.bookmarkStore,
    required this.pronunciationStore,
    required this.modelStore,
    required this.onModelsChanged,
  });

  final TtsAudioHandler handler;
  final ModelStore modelStore;

  /// Tras instalar/eliminar un modelo (recarga el motor de voz).
  final Future<void> Function() onModelsChanged;
  final LibraryStore libraryStore;
  final SettingsStore settingsStore;
  final BookmarkStore bookmarkStore;
  final PronunciationStore pronunciationStore;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _busy = false;
  String _busyLabel = 'Abriendo…';
  final _native = NativeText();
  TextNormalizer _normalizer = TextNormalizer();
  late final DocumentLoader _loader = DocumentLoader(
    cacheDir: widget.libraryStore.root,
    ocr: _native,
  );

  /// Identifica el trabajo de OCR vigente; un documento nuevo cancela el anterior.
  int _ocrJob = 0;

  @override
  void initState() {
    super.initState();
    final bridge = OpenFileBridge.instance;
    bridge.onOpened = _importExternal;
    bridge.start();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pending = await bridge.takePending();
      if (pending != null) await _importExternal(pending);
    });
  }

  @override
  void dispose() {
    OpenFileBridge.instance.onOpened = null;
    super.dispose();
  }

  /// Archivo llegado desde otra app: importar y abrir directamente.
  bool _importingExternal = false;
  Future<void> _importExternal(OpenedFile file) async {
    if (!mounted || _importingExternal) return;
    _importingExternal = true;
    try {
      // Si había un reproductor abierto, volver a la biblioteca; eso libera
      // la apertura anterior (que espera a que se cierre el reproductor).
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.popUntil((r) => r.isFirst);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!mounted) return;
      setState(() {
        _busy = true;
        _busyLabel = 'Abriendo…';
      });
      final f = File(file.path);
      final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
      if (_audioExt.contains(ext)) {
        _importingExternal = false;
        if (mounted) setState(() => _busy = false);
        await _transcribeAndOpen(file.path, file.name.substring(0, file.name.length - ext.length - 1), deleteSource: true);
        return;
      }
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) throw AppException('No se pudo leer el archivo recibido.');
      final entry = await widget.libraryStore.importFile(originalName: file.name, bytes: bytes);
      await widget.settingsStore.saveLastDocumentId(entry.id);
      try {
        await f.delete(); // copia temporal; el original queda en su app
      } catch (_) {}
      _importingExternal = false;
      await _openEntry(entry, recienImportado: true);
    } catch (error) {
      if (!mounted) return;
      showSafeMessage(context, error);
    } finally {
      _importingExternal = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  late final SpeechTranscriber _speech = CompositeTranscriber([
    NativeSpeechTranscriber(),
    WhisperTranscriber(
      modelDir: widget.modelStore.dirFor(whisperBaseModel).path,
      onProgress: (done, total) {
        if (mounted) setState(() => _busyLabel = 'Transcribiendo… $done/$total');
      },
    ),
  ]);

  /// Graba una clase o conversación, la transcribe en el dispositivo y la abre
  /// como un documento más (se puede escuchar, buscar y resumir).
  Future<void> _record() async {
    final rec = await Navigator.of(context).push<RecordingResult>(
      MaterialPageRoute(builder: (_) => const RecorderScreen()),
    );
    if (rec == null || !mounted) return;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    await _transcribeAndOpen(
      rec.path,
      'Grabación ${two(now.day)}-${two(now.month)} ${two(now.hour)}.${two(now.minute)}',
      deleteSource: true,
    );
  }

  /// Transcribe un audio (grabado aquí o importado) y lo abre como documento.
  /// El audio se guarda junto a la entrada: "Eliminar" borra también el audio.
  Future<void> _transcribeAndOpen(String audioPath, String title, {required bool deleteSource}) async {
    setState(() {
      _busy = true;
      _busyLabel = 'Transcribiendo…';
    });
    try {
      String text;
      String? aviso;
      try {
        text = await _speech.transcribe(audioPath);
        if (text.isEmpty) {
          text = 'La grabación no contiene voz reconocible.';
          aviso = 'No se reconoció voz en la grabación.';
        }
      } on TranscriptionUnavailable catch (e) {
        text = 'Grabación sin transcripción. ${e.message}';
        aviso = '${e.message} El audio se guardó.';
      }
      final entry = await widget.libraryStore.importFile(
        originalName: '$title.txt',
        bytes: utf8.encode(text),
      );
      try {
        final ext = audioPath.contains('.') ? audioPath.substring(audioPath.lastIndexOf('.') + 1) : 'wav';
        await File(audioPath).copy('${widget.libraryStore.root.path}/${entry.id}.$ext');
        if (deleteSource) await File(audioPath).delete();
      } catch (_) {}
      await widget.settingsStore.saveLastDocumentId(entry.id);
      if (aviso != null && mounted) showSafeMessage(context, AppException(aviso));
      if (!mounted) return;
      setState(() => _busy = false);
      await _openEntry(entry, recienImportado: true);
    } catch (error) {
      if (mounted) showSafeMessage(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _audioExt = {'wav', 'm4a', 'mp3', 'aac', 'caf'};

  List<LibraryEntry> get _entries => widget.libraryStore.data.entries;

  LibraryEntry? get _continueEntry {
    for (final e in _entries) {
      if (!e.finished && e.pageCount > 0) return e;
    }
    return null;
  }

  Future<void> _confirmDelete(LibraryEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar de la biblioteca'),
        content: const Text(
          'Se eliminarán la copia local, el texto reconocido, el progreso y los marcadores de este documento. '
          'El archivo original no se modifica.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.bookmarkStore.removeAllFor(entry.id);
    await widget.libraryStore.remove(entry.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PSSTH!'),
        actions: [
          IconButton(
            tooltip: 'Pronunciación',
            icon: const Icon(Icons.record_voice_over_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PronunciationScreen(store: widget.pronunciationStore),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Más',
            onSelected: (v) {
              if (v == 'voces') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VoicesScreen(
                      modelStore: widget.modelStore,
                      onModelsChanged: widget.onModelsChanged,
                      native: _native,
                    ),
                  ),
                );
              }
              if (v == 'ia') {
                _showLlmSettings(context);
              }
              if (v == 'acerca') {
                showAboutDialog(
                  context: context,
                  applicationName: 'PSSTH!',
                  applicationVersion: kAppVersion,
                  applicationLegalese:
                      'Convierte documentos en lectura en voz alta. Todo se procesa en tu dispositivo; '
                      'no se envían datos a ningún servidor.\n\n'
                      'El reconocimiento de texto (OCR) y la voz pueden contener errores; '
                      'consulta siempre el documento original para cualquier uso formal.',
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'voces', child: Text('Voces y modelos')),
              PopupMenuItem(value: 'ia', child: Text('Corrección avanzada (IA local)')),
              PopupMenuItem(value: 'acerca', child: Text('Acerca de Lector y licencias')),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _openFile,
                  icon: const Icon(Icons.folder_open),
                  label: Text(_busy ? _busyLabel : 'Abrir documento'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _record,
                  icon: const Icon(Icons.mic),
                  label: const Text('Grabar clase o conversación'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pickPhoto(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Cámara'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pickPhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Fotos'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_continueEntry != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.play_circle, size: 40),
                  title: const Text('Continuar escuchando'),
                  subtitle: Text(
                    '${_continueEntry!.name} · página ${_continueEntry!.pageIndex + 1}',
                  ),
                  onTap: _busy ? null : () => _openEntry(_continueEntry!),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Documentos recientes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _entries.isEmpty
                ? const Center(child: Text('Todavía no hay documentos.'))
                : ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      final percent = (entry.progress * 100).round();
                      return ListTile(
                        leading: Icon(_iconFor(entry.kind)),
                        title: Text(entry.name),
                        subtitle: Text(
                          entry.finished
                              ? 'Terminado'
                              : entry.pageCount <= 0
                                  ? 'Sin páginas leídas aún'
                                  : 'Última página ${entry.pageIndex + 1} · $percent%',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: entry.favorite ? 'Quitar de favoritos' : 'Favorito',
                              icon: Icon(entry.favorite ? Icons.star : Icons.star_border),
                              onPressed: () async {
                                await widget.libraryStore.toggleFavorite(entry.id);
                                if (mounted) setState(() {});
                              },
                            ),
                            IconButton(
                              tooltip: 'Eliminar de la biblioteca',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: _busy ? null : () => _confirmDelete(entry),
                            ),
                          ],
                        ),
                        onTap: _busy ? null : () => _openEntry(entry),
                      );
                    },
                  ),
          ),
        ],
      ))),
    );
  }

  IconData _iconFor(String kind) => switch (kind) {
        'image' => Icons.image,
        'epub' => Icons.menu_book,
        'txt' => Icons.article,
        _ => Icons.picture_as_pdf,
      };

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() {
      _busy = true;
      _busyLabel = 'Abriendo…';
    });
    try {
      final shot = await ImagePicker().pickImage(source: source, imageQuality: 92);
      if (shot == null) {
        return;
      }
      final bytes = await shot.readAsBytes();
      if (bytes.isEmpty) {
        throw AppException('No se pudo leer la imagen.');
      }
      final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-');
      final entry = await widget.libraryStore.importFile(
        originalName: source == ImageSource.camera ? 'Foto $stamp.jpg' : shot.name,
        bytes: bytes,
      );
      await widget.settingsStore.saveLastDocumentId(entry.id);
      await _openEntry(entry, recienImportado: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showSafeMessage(context, error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openFile() async {
    setState(() {
      _busy = true;
      _busyLabel = 'Abriendo…';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf', 'epub', 'txt', 'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'tif', 'tiff', 'bmp',
          'wav', 'm4a', 'mp3', 'aac', 'caf',
        ],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.single;
      final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
      if (_audioExt.contains(ext)) {
        // Audio (una clase grabada con otra app): se transcribe y se abre como texto.
        final src = file.path;
        if (src == null) throw AppException('No se pudo leer el audio seleccionado.');
        if (mounted) setState(() => _busy = false);
        await _transcribeAndOpen(src, file.name.substring(0, file.name.length - ext.length - 1), deleteSource: false);
        return;
      }
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw AppException('No se pudo leer el archivo seleccionado.');
      }
      final entry = await widget.libraryStore.importFile(
        originalName: file.name,
        bytes: bytes,
      );
      await widget.settingsStore.saveLastDocumentId(entry.id);
      await _openEntry(entry, recienImportado: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showSafeMessage(context, error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  List<TextChunk> _chunksFor(LibraryEntry entry, LoadedDocument doc, TextNormalizer n) =>
      buildChunks(documentId: entry.id, pages: doc.pages, normalizer: n);

  Future<void> _openEntry(LibraryEntry entry, {bool recienImportado = false}) async {
    setState(() {
      _busy = true;
      _busyLabel = 'Abriendo…';
    });
    final job = ++_ocrJob;
    try {
      _normalizer = TextNormalizer(
        dictionary: await widget.pronunciationStore.load(),
      );
      final stored = File(entry.storedPath);
      if (!await stored.exists()) {
        throw AppException('El archivo local ya no existe. Vuelve a abrirlo desde el teléfono.');
      }
      final doc = await _loader.load(entry);
      await widget.libraryStore.updateExtraction(
        id: entry.id,
        pageCount: doc.pageCount,
        totalChunks: 0,
      );
      final updated = widget.libraryStore.byId(entry.id) ?? entry;
      await widget.settingsStore.saveLastDocumentId(updated.id);

      if (LlmCleaner.instance.ready && mounted) {
        setState(() => _busyLabel = 'Corrigiendo con IA local…');
        final fixed = await LlmCleaner.instance.cleanPages(
          doc.pages,
          onProgress: (d, t) {
            if (mounted) setState(() => _busyLabel = 'Corrigiendo con IA local… $d/$t');
          },
        );
        doc.pages
          ..clear()
          ..addAll(fixed);
      }
      var chunks = _chunksFor(updated, doc, _normalizer);
      String? notice;
      final firstOcr = Completer<void>();

      if (doc.pendingOcr.isNotEmpty) {
        final available = await _native.isAvailable();
        if (!available) {
          notice = chunks.isEmpty
              ? noSelectableTextMessage
              : '${doc.pendingOcr.length} página(s) sin texto se omitirán: el OCR no está disponible en este dispositivo.';
        } else {
          if (chunks.isEmpty && mounted) {
            setState(() => _busyLabel = 'Reconociendo texto…');
          }
          unawaited(_runOcr(updated, doc, job, firstOcr));
          if (chunks.isEmpty) {
            await firstOcr.future;
            chunks = _chunksFor(updated, doc, _normalizer);
          }
        }
      }

      await widget.handler.loadDocument(
        entry: updated,
        chunks: chunks,
        noTextMessage: noSelectableTextMessage,
        notice: notice,
      );
      widget.handler.chapters = (doc.chapters ?? detectChapters(doc.pages));
      widget.handler.pages = List.of(doc.pages);
      unawaited(_applyLanguage(chunks));
      if (!mounted) {
        return;
      }
      setState(() {});
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            handler: widget.handler,
            entry: updated,
            bookmarkStore: widget.bookmarkStore,
          ),
        ),
      );
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (recienImportado) {
        // No conservar en la biblioteca un archivo que no se pudo abrir.
        await widget.libraryStore.remove(entry.id);
      }
      if (!mounted) {
        return;
      }
      showSafeMessage(context, error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// OCR en segundo plano: cada página lista se añade a la reproducción.
  Future<void> _runOcr(
    LibraryEntry entry,
    LoadedDocument doc,
    int job,
    Completer<void> first,
  ) async {
    try {
      await for (final r in _loader.runOcr(entry, doc)) {
        if (job != _ocrJob) return; // se abrió otro documento
        doc.pages[r.page] = r.text;
        await widget.handler.replaceChunks(_chunksFor(entry, doc, _normalizer));
        widget.handler.chapters = (doc.chapters ?? detectChapters(doc.pages));
        widget.handler.pages = List.of(doc.pages);
        if (!first.isCompleted) first.complete();
      }
    } on OcrUnavailable {
      // sin OCR: se reproduce solo el texto directo
    } catch (_) {
      // un fallo de OCR no debe detener la reproducción
    } finally {
      if (!first.isCompleted) first.complete();
    }
  }

  Future<void> _applyLanguage(List<TextChunk> chunks) async {
    if (chunks.isEmpty) return;
    final sample = chunks.take(12).map((c) => c.text).join(' ');
    final lang = await _native.detectLanguage(sample) ?? detectLanguageHeuristic(sample);
    await widget.handler.applyDocumentLanguage(lang);
  }
}


Future<void> _showLlmSettings(BuildContext context) async {
  final llm = LlmCleaner.instance;
  await llm.load();
  final urlCtl = TextEditingController(text: llm.url.isEmpty ? 'http://192.168.1.10:11434' : llm.url);
  final modelCtl = TextEditingController(text: llm.model);
  var on = llm.enabled;
  String? status;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Corrección avanzada (IA local)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Usa un modelo Ollama en tu PC (misma red) para corregir errores nuevos. '
              'Si no responde, se lee el texto sin esta capa.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activar'),
              value: on,
              onChanged: (v) => setS(() => on = v),
            ),
            TextField(controller: urlCtl, decoration: const InputDecoration(labelText: 'URL de Ollama')),
            TextField(controller: modelCtl, decoration: const InputDecoration(labelText: 'Modelo')),
            if (status != null) ...[
              const SizedBox(height: 8),
              Text(status!, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await llm.save(url: urlCtl.text, model: modelCtl.text, enabled: on);
              final e = await llm.ping();
              setS(() => status = e == null ? 'Conectado ✓' : 'Sin conexión: $e');
            },
            child: const Text('Probar'),
          ),
          TextButton(
            onPressed: () async {
              await llm.save(url: urlCtl.text, model: modelCtl.text, enabled: on);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}
