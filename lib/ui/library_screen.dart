import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_exception.dart';
import '../core/motion.dart';
import '../core/perf_log.dart';
import '../core/crash_log.dart';
import '../data/batch_import.dart';
import '../data/bookmark_store.dart';
import '../data/corrected_pages_store.dart';
import '../data/document_loader.dart';
import '../data/highlight_store.dart';
import '../data/library_store.dart';
import '../data/model_queue.dart';
import '../data/model_store.dart';
import '../data/pronunciation_store.dart';
import '../data/settings_store.dart';
import '../data/url_import.dart';
import '../data/youtube_transcript.dart' show youtubeVideoId;
import '../domain/chapter_detector.dart';
import '../domain/chunk_builder.dart';
import '../domain/date_label.dart';
import '../domain/language_detector.dart';
import '../domain/library_entry.dart';
import '../domain/link_finder.dart';
import '../domain/scanned_pdf.dart';
import '../domain/text_chunk.dart';
import '../domain/text_normalizer.dart';
import '../ocr/ocr_engine.dart';
import '../platform/document_scanner.dart';
import '../platform/native_text.dart';
import '../platform/open_file_bridge.dart';
import '../platform/speech_transcriber.dart';
import '../platform/whisper_transcriber.dart';
import 'math_screen.dart';
import 'scan_review_screen.dart';
import 'swarm_transition.dart';
import '../playback/tts_audio_handler.dart';
import '../services/llm_cleaner.dart';
import 'first_run_guide.dart';
import 'player_screen.dart';
import 'recorder_screen.dart';
import 'voices_screen.dart';
import 'pronunciation_screen.dart';
import 'premium.dart';
import 'processing_sign.dart';
import '../theme/app_theme.dart';

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
  late final DocumentLoader _loader = DocumentLoader(cacheDir: widget.libraryStore.root, ocr: _native);

  /// Identifica el trabajo de OCR vigente; un documento nuevo cancela el anterior.
  int _ocrJob = 0;

  /// Documento de [_ocrJob]: si se borra, sus trabajos se cancelan.
  String? _jobDocId;

  @override
  void initState() {
    super.initState();
    final bridge = OpenFileBridge.instance;
    bridge.onOpened = _importExternal;
    bridge.start();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pending = await bridge.takePending();
      // Quien recién instala (biblioteca vacía) ve antes una guía de 3 pasos.
      final isNewUser = pending == null && widget.libraryStore.data.entries.isEmpty;
      if (mounted) await FirstRunGuide.showOnce(context, isNewUser: isNewUser);
      if (pending != null) await _importExternal(pending);
      await _askModelsOnce();
    });
  }

  static const _whatItDoes = {
    'kokoro': 'Voz natural: la voz que suena como una persona al leer.',
    'whisper': 'Transcripción: pasa a texto lo que grabas, sin Internet.',
  };

  /// Una sola vez: ¿bajar en segundo plano la voz natural y los demás modelos?
  Future<void> _askModelsOnce() async {
    final queue = ModelQueue.instance;
    if (queue.consent != null || queue.missing.isEmpty || !mounted) return;
    final mb = (queue.missingBytes / (1024 * 1024)).round();
    final yes = await showSwarmDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Completar la app'),
        content: Text(
          'Hay complementos que no vienen dentro de la app:\n\n'
          '${queue.missing.map((m) => '• ${_whatItDoes[m.id] ?? m.title}\n').join()}'
          '\n¿Los descargo ahora ($mb MB)? Puedes seguir usando la app mientras tanto.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ahora no')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Descargar')),
        ],
      ),
    );
    await queue.setConsent(yes ?? false);
  }

  void _openVoices() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          VoicesScreen(modelStore: widget.modelStore, onModelsChanged: widget.onModelsChanged, native: _native),
    ),
  );

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
        await _transcribeAndOpen(
          file.path,
          file.name.substring(0, file.name.length - ext.length - 1),
          deleteSource: true,
        );
        return;
      }
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) throw AppException('No se pudo leer el archivo recibido.');
      final entry = await widget.libraryStore.importFile(originalName: file.name, bytes: bytes);
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
    if (!await _speech.isAvailable()) {
      ModelQueue.instance.prioritize(whisperBaseModel);
      if (!mounted) return;
      // Sin transcripción la grabación queda solo como audio: se avisa antes.
      final choice = await showSwarmDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Falta la transcripción'),
          content: Text(
            widget.modelStore.isInstalling(whisperBaseModel)
                ? 'La transcripción sin conexión se está bajando en segundo plano. Si grabas antes de '
                      'que termine, la grabación se guarda solo como audio.'
                : 'Para convertir la grabación en texto hay que descargar una vez el modelo de '
                      'transcripción sin conexión (${whisperBaseModel.sizeLabel}) en Voces y modelos. '
                      'Sin él, la grabación se guarda solo como audio.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'grabar'), child: const Text('Grabar igual')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'descargar'), child: const Text('Descargar')),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'descargar') {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                VoicesScreen(modelStore: widget.modelStore, onModelsChanged: widget.onModelsChanged, native: _native),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    final rec = await Navigator.of(
      context,
    ).push<RecordingResult>(MaterialPageRoute(builder: (_) => const RecorderScreen()));
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
      final (entry, aviso) = await _transcribeToLibrary(audioPath, title, deleteSource: deleteSource);
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

  /// Transcribe el audio y lo guarda en la biblioteca (sin abrirlo). Devuelve
  /// la entrada y, si la hay, una advertencia para el usuario.
  Future<(LibraryEntry, String?)> _transcribeToLibrary(
    String audioPath,
    String title, {
    required bool deleteSource,
  }) async {
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
    final entry = await widget.libraryStore.importFile(originalName: '$title.txt', bytes: utf8.encode(text));
    try {
      final ext = audioPath.contains('.') ? audioPath.substring(audioPath.lastIndexOf('.') + 1) : 'wav';
      await File(audioPath).copy('${widget.libraryStore.root.path}/${entry.id}.$ext');
      if (deleteSource) await File(audioPath).delete();
    } catch (_) {}
    return (entry, aviso);
  }

  static const _audioExt = audioExtensions;

  /// Pestaña de la lista: documentos normales o los creados con el escáner.
  bool _showScans = false;

  List<LibraryEntry> get _entries => [
    for (final e in widget.libraryStore.data.entries)
      if (e.scanned == _showScans) e,
  ];

  int get _scanCount => widget.libraryStore.data.entries.where((e) => e.scanned).length;

  LibraryEntry? get _continueEntry {
    for (final e in widget.libraryStore.data.entries) {
      if (!e.finished && e.pageCount > 0) return e;
    }
    return null;
  }

  /// «Enviar informe de errores»: los errores anotados en el aparato, por la
  /// hoja Compartir (correo, WhatsApp…). Solo sale si la persona lo envía.
  Future<void> _shareCrashLog() async {
    final log = await CrashLog.instance?.read() ?? '';
    if (!mounted) return;
    if (log.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: SwarmText('No hay errores registrados.')));
      return;
    }
    try {
      final file = File('${(await getTemporaryDirectory()).path}/PSSTH-errores.txt');
      await file.writeAsString(
        'PSSTH! $kAppVersion · ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n\n$log',
        flush: true,
      );
      await const MethodChannel('lector/share').invokeMethod<bool>('shareFile', {
        'path': file.path,
        'text': 'Informe de errores de PSSTH!',
      });
    } catch (error) {
      if (mounted) showSafeMessage(context, error);
    }
  }

  Future<void> _confirmDelete(LibraryEntry entry) async {
    final ok = await showSwarmDialog<bool>(
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
    // El OCR y la corrección en segundo plano de este documento volvían a
    // guardar sus archivos (y a pedirle páginas a la IA) después de borrarlo.
    if (_jobDocId == entry.id) _ocrJob++;
    await widget.bookmarkStore.removeAllFor(entry.id);
    await HighlightStore.instance?.removeAllFor(entry.id);
    await widget.libraryStore.remove(entry.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cont = _continueEntry;
    final entries = _entries;
    return Stack(
      children: [
        PremiumPage(
          showBack: false,
          title: _showScans ? 'Escaneados' : 'Biblioteca',
          actions: [
            PageAction.widget(
              ListenableBuilder(
                listenable: ModelQueue.instance,
                // Mientras se preparan voces y modelos, su señal; si no, la
                // entrada a Voces.
                builder: (_, _) => ModelQueue.instance.busy
                    ? ProcessingSign(active: true, tooltip: 'Preparando voces y modelos', onTap: _openVoices)
                    : IconButton(
                        tooltip: 'Voces y modelos',
                        icon: const Icon(CupertinoIcons.waveform),
                        onPressed: _openVoices,
                      ),
              ),
            ),
            PageAction(icon: CupertinoIcons.link, tooltip: 'Pegar enlace', onTap: _busy ? null : _openUrl),
            PageAction(icon: CupertinoIcons.plus, tooltip: 'Abrir documento', onTap: _busy ? null : _openFile, primary: true),
          ],
          hero: _hero(cont),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Recientes'),
                      selected: !_showScans,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _showScans = false),
                    ),
                    ChoiceChip(
                      label: Text('Escaneados ($_scanCount)'),
                      selected: _showScans,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _showScans = true),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? _EmptyLibrary(
                        scans: _showScans,
                        onStart: _busy ? null : (_showScans ? _scanToPdf : _openFile),
                      )
                    : ListView(padding: const EdgeInsets.only(bottom: 16), children: _entryRows(entries)),
              ),
            ],
          ),
          tabs: [
            const TabItem(icon: CupertinoIcons.house_fill, label: 'Biblioteca', onTap: null, selected: true),
            TabItem(
              icon: CupertinoIcons.number,
              label: 'Matemáticas',
              onTap: _busy
                  ? null
                  : () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => MathScreen(handler: widget.handler))),
            ),
            TabItem(icon: CupertinoIcons.waveform, label: 'Voces', onTap: _openVoices),
            TabItem(icon: CupertinoIcons.gear, label: 'Ajustes', onTap: _showSettings),
          ],
        ),
        // Mientras carga un documento: un panel flotante en el centro.
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Premium.radiusSheet)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_busyLabel, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(minHeight: 3),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Lo de arriba, sobre el negro: lo que se está escuchando con su avance en
  /// grande (como el saldo) y las formas de traer un documento en píldoras.
  Widget _hero(LibraryEntry? cont) {
    final t = Theme.of(context).textTheme;
    final percent = cont == null ? 0 : (cont.progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cont == null ? 'Escucha cualquier documento' : 'Continuar escuchando',
          style: t.bodyMedium?.copyWith(color: Premium.heroMuted),
        ),
        const SizedBox(height: 4),
        if (cont != null) ...[
          Text('$percent%', style: t.displaySmall?.copyWith(color: Premium.heroText)),
          const SizedBox(height: 4),
          Text(
            '${cont.name} · página ${cont.pageIndex + 1}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodyMedium?.copyWith(color: const Color(0xFFBDBDBD)),
          ),
        ] else
          Text('PSSTH!', style: t.displaySmall?.copyWith(color: Premium.heroText)),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final pill in [
                if (cont != null)
                  HeroPill(icon: CupertinoIcons.play_fill, label: 'Seguir', onTap: _busy ? null : () => _openEntry(cont)),
                HeroPill(
                  icon: CupertinoIcons.doc_text_viewfinder,
                  label: 'Escanear',
                  tooltip: 'Escanear a PDF',
                  onTap: _busy ? null : _scanToPdf,
                ),
                HeroPill(icon: CupertinoIcons.mic, label: 'Grabar', tooltip: 'Grabar clase o conversación', onTap: _busy ? null : _record),
                HeroPill(
                  icon: CupertinoIcons.camera,
                  label: 'Cámara',
                  tooltip: 'Sacar una foto para leerla',
                  onTap: _busy ? null : () => _pickPhoto(ImageSource.camera),
                ),
                HeroPill(
                  icon: CupertinoIcons.photo_on_rectangle,
                  label: 'Fotos',
                  tooltip: 'Leer una foto de la galería',
                  onTap: _busy ? null : () => _pickPhoto(ImageSource.gallery),
                ),
              ])
                Padding(padding: const EdgeInsets.only(right: 8), child: pill),
            ],
          ),
        ),
      ],
    );
  }

  /// Los documentos agrupados por el día en que se abrieron («Hoy», «Ayer»…).
  List<Widget> _entryRows(List<LibraryEntry> entries) {
    final now = DateTime.now();
    final rows = <Widget>[];
    String? last;
    for (final entry in entries) {
      final label = dayLabel(DateTime.tryParse(entry.lastOpenedIso ?? ''), now);
      if (label != last) {
        rows.add(SectionCaption(label));
        last = label;
      }
      rows.add(_entryRow(entry));
    }
    return rows;
  }

  Widget _entryRow(LibraryEntry entry) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final percent = (entry.progress * 100).round();
    final fresh = entry.pageCount <= 0;
    return ListTile(
      leading: IconAvatar(_iconFor(entry.kind)),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.finished
            ? 'Terminado'
            : fresh
            ? 'Sin escuchar todavía'
            : 'Página ${entry.pageIndex + 1}${entry.favorite ? ' · favorito' : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            fresh ? 'Nuevo' : '$percent%',
            style: t.titleSmall?.copyWith(color: fresh ? Premium.positive : s.onSurface),
          ),
          IconButton(
            tooltip: 'Opciones de ${entry.name}',
            icon: Icon(CupertinoIcons.ellipsis, color: s.onSurfaceVariant),
            onPressed: _busy ? null : () => _entryOptions(entry),
          ),
        ],
      ),
      onTap: _busy ? null : () => _openEntry(entry),
    );
  }

  /// Favorito y eliminar, en una hoja (en la lista solo se ve el avance).
  Future<void> _entryOptions(LibraryEntry entry) async {
    final choice = await showSwarmSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: IconAvatar(_iconFor(entry.kind)),
              title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            ListTile(
              leading: Icon(entry.favorite ? CupertinoIcons.star_fill : CupertinoIcons.star),
              title: Text(entry.favorite ? 'Quitar de favoritos' : 'Marcar como favorito'),
              onTap: () => Navigator.pop(ctx, 'favorito'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.trash),
              title: const Text('Eliminar de la biblioteca'),
              onTap: () => Navigator.pop(ctx, 'eliminar'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'favorito') {
      await widget.libraryStore.toggleFavorite(entry.id);
      if (mounted) setState(() {});
    }
    if (choice == 'eliminar') await _confirmDelete(entry);
  }

  /// Ajustes: todo lo que antes estaba en el menú de arriba.
  Future<void> _showSettings() async {
    final v = await showSwarmSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, icon, label) in const [
              ('voces', CupertinoIcons.waveform, 'Voces y modelos'),
              ('pronunciacion', CupertinoIcons.ear, 'Pronunciación'),
              ('ia', CupertinoIcons.sparkles, 'Corrección avanzada (IA local)'),
              ('comodidad', CupertinoIcons.paintbrush, 'Aspecto y letra'),
              ('errores', CupertinoIcons.ant, 'Enviar informe de errores'),
              ('acerca', CupertinoIcons.info_circle, 'Acerca de PSSTH! y licencias'),
            ])
              ListTile(leading: Icon(icon), title: Text(label), onTap: () => Navigator.pop(ctx, value)),
          ],
        ),
      ),
    );
    if (!mounted || v == null) return;
    switch (v) {
      case 'voces':
        _openVoices();
      case 'pronunciacion':
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => PronunciationScreen(store: widget.pronunciationStore)));
      case 'ia':
        _showLlmSettings(context);
      case 'comodidad':
        showComfortSheet(context);
      case 'errores':
        await _shareCrashLog();
      case 'acerca':
        showAboutDialog(
          context: context,
          applicationName: 'PSSTH!',
          applicationVersion: kAppVersion,
          applicationLegalese:
              'Convierte documentos en lectura en voz alta. Todo se procesa en tu dispositivo. '
              'Solo se usa Internet si descargas los modelos opcionales (desde GitHub y Hugging Face), y la red local '
              'solo si activas la corrección con Ollama.\n\n'
              'El reconocimiento de texto (OCR) y la voz pueden contener errores; '
              'consulta siempre el documento original para cualquier uso formal.\n\n'
              'Modelos opcionales: voz natural Kokoro-82M (Apache 2.0; entrenada con datos CC BY: '
              'Koniwa y SIWIS) y transcripción Whisper (MIT), ejecutados con sherpa-onnx (Apache 2.0); '
              'Letras Inter y Atkinson Hyperlegible (OFL). '
              'Esta versión incluye espeak-ng (GPL-3.0) dentro de sherpa-onnx. '
              'El resto de licencias está en «Ver licencias».',
        );
    }
  }

  IconData _iconFor(String kind) => switch (kind) {
    'image' => CupertinoIcons.photo,
    'epub' => CupertinoIcons.book,
    'txt' => CupertinoIcons.doc_text,
    'html' => CupertinoIcons.globe,
    _ => CupertinoIcons.doc_richtext,
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

  /// Primero un QR; si no hay, una dirección escrita en la foto (OCR).
  /// Ese OCR queda en caché: si no hay enlace, la foto se lee sin repetirlo.
  Future<Uri?> _findLinkInPhoto(LibraryEntry entry) async {
    final path = entry.storedPath;
    for (final code in await _native.barcodes(path)) {
      final uri = findLinkInText(code);
      if (uri != null) return uri;
    }
    try {
      // Sin corrección de idioma: la corrección "arregla" las direcciones
      // como si fueran palabras (youtube.corn, espacios tras el punto).
      // Con letra mínima pequeña: en una foto del monitor la barra de
      // direcciones mide mucho menos que el 1/32 de alto que Vision exige.
      final text = await _native.recognize(path, languageCorrection: false, minimumTextHeight: 0.004);
      if (text.trim().isNotEmpty) await _loader.rememberOcr(entry.id, 0, text);
      return findLinkInText(text);
    } on OcrUnavailable {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> _askOpenLink(Uri link) async {
    final video = youtubeVideoId(link) != null;
    final open = await showSwarmDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(video ? 'Video de YouTube en la foto' : 'Enlace en la foto'),
        content: Text(
          '${link.host}${link.path}${link.hasQuery ? '?${link.query}' : ''}\n\n'
          '${video ? 'Puedo escuchar la transcripción del video.' : 'Puedo abrir la página y leerla.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Leer la foto')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(video ? 'Escuchar video' : 'Abrir enlace'),
          ),
        ],
      ),
    );
    return open ?? false;
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
          'pdf',
          'epub',
          'txt',
          'html',
          'htm',
          'jpg',
          'jpeg',
          'png',
          'heic',
          'heif',
          'webp',
          'tif',
          'tiff',
          'bmp',
          'wav',
          'm4a',
          'mp3',
          'aac',
          'caf',
        ],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      if (result.files.length > 1) {
        await _importBatch(result.files);
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
      final path = file.path;
      final bytes = file.bytes ?? (path == null ? null : await File(path).readAsBytes());
      if (bytes == null || bytes.isEmpty) {
        throw AppException('No se pudo leer el archivo seleccionado.');
      }
      final entry = await widget.libraryStore.importFile(originalName: file.name, bytes: bytes);
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

  /// Enlace pegado por el usuario: una página web se lee como texto; un PDF o
  /// EPUB se importa como archivo; un audio se transcribe.
  /// Escanea varias páginas, reconoce su texto y arma un PDF buscable que se
  /// entrega solo por la hoja Compartir del sistema (nada se sube solo).
  Future<void> _scanToPdf() async {
    final List<String> paths;
    try {
      paths = await DocumentScanner().scan();
    } catch (error) {
      if (mounted) showSafeMessage(context, error);
      return;
    }
    if (paths.isEmpty || !mounted) return;
    final now = DateTime.now();
    try {
      // Elegir cómo limpiar las páginas (B&N, Mejorar…) viendo cómo quedan.
      final clean = await Navigator.of(
        context,
      ).push<List<CleanPage>>(MaterialPageRoute(builder: (_) => ScanReviewScreen(paths: paths)));
      if (clean == null || clean.isEmpty || !mounted) return;
      final pages = <ScannedPage>[];
      for (var i = 0; i < clean.length; i++) {
        setState(() {
          _busy = true;
          _busyLabel = 'Reconociendo texto… página ${i + 1} de ${clean.length}';
        });
        var lines = const <ScannedLine>[];
        try {
          // El texto se lee en la foto original (más detalle); la posición es
          // la misma en la página limpia porque se mide en fracciones.
          lines = (await _native.recognizeLines(paths[i])).lines;
        } catch (_) {
          // Sin texto reconocido, la página va igual (solo la imagen).
        }
        pages.add((jpeg: clean[i].jpeg, width: clean[i].width, height: clean[i].height, lines: lines));
      }
      if (!mounted) return;
      setState(() => _busy = false);
      final name = await _askScanName(defaultScanName(now));
      if (name == null || !mounted) return;
      setState(() {
        _busy = true;
        _busyLabel = 'Armando el PDF…';
      });
      final fileName = safePdfFileName(name, now);
      final bytes = await buildScannedPdf(pages, title: fileName.substring(0, fileName.length - 4));
      final dir = Directory('${(await getTemporaryDirectory()).path}/escaneos');
      await dir.create(recursive: true);
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      // Queda también en PSSTH!, en «Escaneados»: se puede abrir, escuchar y
      // volver a compartir.
      await widget.libraryStore.importFile(originalName: fileName, bytes: bytes, scanned: true);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _showScans = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: SwarmText('«$fileName» quedó en Escaneados.')));
      await const MethodChannel('lector/share').invokeMethod<bool>('shareFile', {'path': file.path});
    } catch (error) {
      if (mounted) showSafeMessage(context, error);
    } finally {
      for (final path in paths) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Nombre del PDF antes de compartirlo (sugerido con fecha y hora).
  Future<String?> _askScanName(String suggested) async {
    final controller = TextEditingController(text: suggested)
      ..selection = TextSelection(baseOffset: 0, extentOffset: suggested.length);
    final name = await showSwarmDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre del PDF'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(suffixText: '.pdf'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Compartir')),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    return name;
  }

  Future<void> _openUrl() async {
    // Sin leer el portapapeles por código: en iOS eso pide permiso cada vez.
    // El usuario pega en el campo (mantener pulsado → Pegar).
    final controller = TextEditingController();
    final raw = await showSwarmDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pegar enlace'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'https://…', helperText: 'Artículo, noticia, PDF o audio'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Abrir')),
        ],
      ),
    );
    // El diálogo sigue usando el campo mientras se cierra: liberarlo después.
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (raw == null || !mounted) return;
    final uri = parseUserUrl(raw);
    if (uri == null) {
      showSafeMessage(context, AppException('Eso no parece un enlace. Copia la dirección completa de la página.'));
      return;
    }
    await _importUri(uri);
  }

  /// Descarga [uri] y lo abre: página como texto, video de YouTube por su
  /// transcripción, PDF/EPUB como archivo y audio transcrito.
  Future<void> _importUri(Uri uri) async {
    setState(() {
      _busy = true;
      _busyLabel = 'Descargando…';
    });
    try {
      final content = await downloadUrl(
        uri,
        tempDir: Directory.systemTemp,
        onProgress: (got, total) {
          if (!mounted) return;
          final mb = (got / (1024 * 1024)).toStringAsFixed(1);
          setState(
            () => _busyLabel = total == null ? 'Descargando… $mb MB' : 'Descargando… ${(got * 100 / total).round()}%',
          );
        },
      );
      if (!mounted) return;
      if (content is UrlAudio) {
        setState(() => _busy = false);
        await _transcribeAndOpen(content.path, content.title, deleteSource: true);
        return;
      }
      final entry = switch (content) {
        UrlText(:final title, :final text) => await widget.libraryStore.importFile(
          originalName: '${title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.txt',
          bytes: utf8.encode('$title\n\n$text\n\nFuente: $uri\n'),
        ),
        UrlDocument(:final fileName, :final bytes) => await widget.libraryStore.importFile(
          originalName: fileName,
          bytes: bytes,
        ),
        UrlAudio() => throw StateError('audio ya tratado'),
      };
      await _openEntry(entry, recienImportado: true);
    } catch (error) {
      if (mounted) showSafeMessage(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Varios archivos a la vez: se guardan en la biblioteca sin abrirlos y al
  /// final se muestra un resumen.
  Future<void> _importBatch(List<PlatformFile> picked) async {
    final result = await importBatch(
      files: [for (final f in picked) BatchFile(name: f.name, path: f.path)],
      store: widget.libraryStore,
      importAudio: (path, title) async => (await _transcribeToLibrary(path, title, deleteSource: false)).$1,
      onProgress: (i, total, f) {
        if (mounted) setState(() => _busyLabel = '${f.isAudio ? 'Transcribiendo' : 'Importando'} $i/$total…');
      },
    );
    if (!mounted) return;
    setState(() {});
    showSafeMessage(context, AppException(result.summary));
  }

  List<TextChunk> _chunksFor(LibraryEntry entry, LoadedDocument doc, TextNormalizer n) =>
      buildChunks(documentId: entry.id, pages: doc.pages, normalizer: n);

  Future<void> _openEntry(LibraryEntry entry, {bool recienImportado = false}) async {
    // Imagen recién llegada (cámara, Fotos, Archivos o compartida desde otra
    // app) con un QR o una dirección escrita: se ofrece abrir el enlace.
    if (recienImportado && entry.kind == 'image') {
      setState(() {
        _busy = true;
        _busyLabel = 'Buscando enlaces…';
      });
      final link = await _findLinkInPhoto(entry);
      if (!mounted) return;
      if (link != null && await _askOpenLink(link)) {
        if (mounted) await _importUri(link);
        return;
      }
      if (!mounted) return;
    }
    setState(() {
      _busy = true;
      _busyLabel = 'Abriendo…';
    });
    final job = ++_ocrJob;
    _jobDocId = entry.id;
    final sw = Stopwatch()..start();
    try {
      _normalizer = TextNormalizer(dictionary: await widget.pronunciationStore.load());
      final stored = File(entry.storedPath);
      if (!await stored.exists()) {
        throw AppException('El archivo local ya no existe. Vuelve a abrirlo desde el teléfono.');
      }
      final doc = await _loader.load(entry);
      perfLog('tiempo: cargar ${doc.pageCount} pág. ${sw.elapsedMilliseconds} ms');
      await widget.libraryStore.updateExtraction(id: entry.id, pageCount: doc.pageCount, totalChunks: 0);
      final updated = widget.libraryStore.byId(entry.id) ?? entry;

      // IA local: lo ya corregido en otra apertura se usa al momento; el resto
      // se corrige en segundo plano mientras se escucha (ver _runLlm).
      final llm = LlmCleaner.instance;
      final corrected = llm.ready ? await _corrected.load(updated.id, model: llm.model) : const <int, String>{};
      for (final e in corrected.entries) {
        if (e.key < doc.pages.length) doc.pages[e.key] = e.value;
      }
      // En segundo plano: con documentos largos no traba la pantalla.
      var chunks = await buildChunksInBackground(documentId: updated.id, pages: doc.pages, normalizer: _normalizer);
      perfLog('tiempo: ${chunks.length} fragmentos ${sw.elapsedMilliseconds} ms');
      String? notice;
      final firstOcr = Completer<void>();
      var noTextMessage = noSelectableTextMessage;

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
          final ocr = _runOcr(updated, doc, job, firstOcr);
          unawaited(ocr);
          if (chunks.isEmpty) {
            await firstOcr.future;
            chunks = _chunksFor(updated, doc, _normalizer);
          }
          // Las demás páginas siguen reconociéndose: no decir que no hay texto.
          noTextMessage = ocrInProgressMessage;
          unawaited(
            ocr.then((_) {
              if (job == _ocrJob) widget.handler.showMessage(ocrNoTextMessage);
            }),
          );
        }
      }

      await widget.handler.loadDocument(entry: updated, chunks: chunks, noTextMessage: noTextMessage, notice: notice);
      widget.handler.chapters = (doc.chapters ?? detectChapters(doc.pages));
      widget.handler.pages = List.of(doc.pages);
      unawaited(_applyLanguage(chunks, manual: updated.language));
      // PDF largo abierto por primera vez: se empezó a leer con las primeras
      // páginas; al terminar de extraerse el resto, se suma sin perder el lugar.
      final more = doc.morePages;
      if (more != null) {
        unawaited(
          more
              .then((all) async {
                if (job != _ocrJob || !mounted) return;
                // Las primeras páginas se quedan como están (pueden venir ya
                // corregidas o reconocidas); se suman las que faltaban. Así las
                // correcciones y el OCR siguientes trabajan sobre el texto completo.
                doc.pages.addAll(all.skip(doc.pages.length));
                final full = await buildChunksInBackground(
                  documentId: updated.id,
                  pages: doc.pages,
                  normalizer: _normalizer,
                );
                await widget.libraryStore.updateExtraction(id: updated.id, pageCount: doc.pages.length, totalChunks: 0);
                await _publish(doc, job, chunks: full);
              })
              .catchError((Object _) {}),
        );
      }
      if (llm.ready) unawaited(_runLlm(updated, doc, job, corrected));
      if (!mounted) {
        return;
      }
      setState(() {});
      await Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: SwarmTransitionsBuilder.solidBackground),
          builder: (_) => PlayerScreen(handler: widget.handler, entry: updated, bookmarkStore: widget.bookmarkStore),
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
  Future<void> _runOcr(LibraryEntry entry, LoadedDocument doc, int job, Completer<void> first) async {
    try {
      await for (final r in _loader.runOcr(entry, doc)) {
        if (job != _ocrJob) return; // se abrió otro documento
        doc.pages[r.page] = r.text;
        await _publish(doc, job, chunks: _chunksFor(entry, doc, _normalizer));
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

  /// Pasa al reproductor el texto de [doc] (fragmentos, capítulos y páginas
  /// juntos), solo si sigue abierto ese documento: un trabajo atrasado del
  /// anterior (OCR, IA, páginas que faltaban) pisaba al recién abierto.
  Future<void> _publish(LoadedDocument doc, int job, {required List<TextChunk> chunks}) async {
    if (job != _ocrJob) return;
    await widget.handler.replaceChunks(chunks);
    if (job != _ocrJob) return;
    widget.handler.chapters = doc.chapters ?? detectChapters(doc.pages);
    widget.handler.pages = List.of(doc.pages);
  }

  late final CorrectedPagesStore _corrected = CorrectedPagesStore(widget.libraryStore.root);

  /// Corrige con la IA local mientras se escucha, empezando por la página
  /// actual. Cada página corregida reemplaza a la original (sin perder la
  /// posición) y se guarda para la próxima vez. Si falla, se sigue con el
  /// texto original.
  Future<void> _runLlm(LibraryEntry entry, LoadedDocument doc, int job, Map<int, String> done) async {
    final llm = LlmCleaner.instance;
    final saved = Map<int, String>.of(done);
    try {
      await for (final (page, text) in llm.cleanInBackground(
        List.of(doc.pages),
        startPage: entry.pageIndex,
        skip: saved.keys.toSet(),
      )) {
        if (job != _ocrJob) return; // se abrió otro documento
        saved[page] = text;
        await _corrected.save(entry.id, model: llm.model, pages: saved);
        if (doc.pages[page] == text) continue;
        if (job != _ocrJob) return; // se abrió otro mientras se guardaba
        doc.pages[page] = text;
        await _publish(doc, job, chunks: _chunksFor(entry, doc, _normalizer));
      }
    } on Exception {
      // la corrección es opcional: si falla, se sigue leyendo el original
    }
  }

  Future<void> _applyLanguage(List<TextChunk> chunks, {String? manual}) async {
    if (chunks.isEmpty) return;
    final sample = chunks.take(12).map((c) => c.text).join(' ');
    final lang = await _native.detectLanguage(sample) ?? detectLanguageHeuristic(sample);
    await widget.handler.applyDocumentLanguage(lang, manual: manual);
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
  await showSwarmDialog<void>(
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
            TextField(
              controller: urlCtl,
              decoration: const InputDecoration(labelText: 'URL de Ollama'),
            ),
            TextField(
              controller: modelCtl,
              decoration: const InputDecoration(labelText: 'Modelo'),
            ),
            if (status != null) ...[const SizedBox(height: 8), Text(status!, style: const TextStyle(fontSize: 12))],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await llm.save(url: urlCtl.text, model: modelCtl.text, enabled: on);
              final e = await llm.ping();
              setS(
                () => status = e == null
                    ? 'Conectado ✓'
                    : 'Sin conexión: revisa que la computadora esté encendida, en la misma red Wi-Fi y con Ollama abierto.',
              );
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

/// Biblioteca sin documentos: qué se puede abrir y un botón para empezar.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.scans, required this.onStart});
  final bool scans;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(scans ? 'Todavía no escaneaste documentos.' : 'Todavía no hay documentos.', style: t.titleMedium),
            const SizedBox(height: 8),
            Text(
              scans
                  ? 'Escanea hojas con la cámara: quedan como PDF con su texto, listas para escuchar.'
                  : 'Abre un PDF, un EPUB o una imagen, pega un enlace o saca una foto: PSSTH! lo lee en voz '
                        'alta, sin Internet.',
              textAlign: TextAlign.center,
              style: t.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onStart,
              icon: Icon(scans ? CupertinoIcons.doc_text_viewfinder : CupertinoIcons.folder),
              label: Text(scans ? 'Escanear a PDF' : 'Abrir documento'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fondo (negro o blanco), dispersión de letras y letra muy legible.
Future<void> showComfortSheet(BuildContext context) => showSwarmSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => SafeArea(
    child: ListenableBuilder(
      listenable: Listenable.merge([
        Comfort.paper,
        Comfort.scatter,
        Comfort.legible,
        Comfort.textSize,
        Comfort.lineHeight,
        Comfort.keepControls,
        Comfort.skipCitations,
      ]),
      builder: (ctx, _) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Fondo', style: Theme.of(ctx).textTheme.titleLarge),
              RadioGroup<Paper>(
                groupValue: Comfort.paper.value,
                onChanged: (p) {
                  if (p != null) Comfort.setPaper(p);
                },
                child: Column(
                  children: [
                    for (final p in Paper.values)
                      RadioListTile<Paper>(
                        value: p,
                        contentPadding: EdgeInsets.zero,
                        title: Text(p.label),
                        subtitle: Text(p.detail),
                      ),
                  ],
                ),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: Comfort.scatter.value,
                onChanged: Comfort.setScatter,
                title: const Text('Dispersión de letras'),
                subtitle: Text(
                  Comfort.scatter.value && MediaQuery.of(ctx).disableAnimations
                      ? 'El sistema pide reducir el movimiento: la app queda quieta.'
                      : 'Las pantallas se forman desde un enjambre de letras y el fondo se mueve. '
                            'Apagada, la pantalla es lisa y todo aparece de una vez.',
                ),
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: Comfort.legible.value,
                onChanged: Comfort.setLegible,
                title: const Text('Letra muy legible'),
                subtitle: const Text('Para el texto que se lee: letras más abiertas y fáciles de distinguir.'),
              ),
              const Divider(),
              const SizedBox(height: 8),
              Text('Lectura', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Tamaño de la letra: ${Comfort.textSize.value.round()}'),
              Slider(
                value: Comfort.textSize.value,
                min: Comfort.minTextSize,
                max: Comfort.maxTextSize,
                divisions: (Comfort.maxTextSize - Comfort.minTextSize).round(),
                label: '${Comfort.textSize.value.round()}',
                onChanged: Comfort.setTextSize,
              ),
              // Muestra cómo queda el texto que se lee.
              Text(
                'Así se verá el texto que se lee en voz alta.',
                style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                  fontSize: Comfort.textSize.value,
                  height: Comfort.lineHeight.value.height,
                ),
              ),
              const SizedBox(height: 12),
              const Text('Espacio entre renglones'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final l in LineSpacing.values)
                    ChoiceChip(
                      label: Text(l.label),
                      selected: Comfort.lineHeight.value == l,
                      onSelected: (_) => Comfort.setLineHeight(l),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: Comfort.keepControls.value,
                onChanged: Comfort.setKeepControls,
                title: const Text('Mantener controles visibles'),
                subtitle: const Text('Mientras lee, los botones no se esconden solos.'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: Comfort.skipCitations.value,
                onChanged: Comfort.setSkipCitations,
                title: const Text('Saltar citas y notas'),
                subtitle: const Text('No lee en voz alta las referencias como [12] o (Pérez, 2019).'),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
