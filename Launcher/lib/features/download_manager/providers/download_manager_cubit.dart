import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/features/download_manager/models/download_request.dart';
import 'package:kyber_launcher/features/download_manager/models/download_state.dart';
import 'package:kyber_launcher/features/download_manager/repositories/download_repository.dart';
import 'package:kyber_launcher/features/download_manager/services/download_orchestrator.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';

class DownloadCubit extends Cubit<DownloadState> {
  DownloadCubit({
    DownloadOrchestrator? orchestrator,
    DownloadRepository? repository,
  }) : _orchestrator = orchestrator,
       _repository = repository ?? const DownloadRepository(),
       super(const DownloadInitial()) {
    _initialize();
  }

  final DownloadOrchestrator? _orchestrator;
  final DownloadRepository _repository;
  final Logger _logger = Logger('download_cubit');
  StreamSubscription<TaskProgressUpdate>? _progressSubscription;
  StreamSubscription<TaskStatusUpdate>? _statusSubscription;
  StreamSubscription<ProgressUpdate>? _extractionProgressSubscription;

  final _callbackTasks = <String, TaskRecord>{};
  final _downloadedAt = <String, DateTime>{};

  Future<void> _initialize() async {
    await sl.isReady<DownloadOrchestrator>();
    final orchestrator = _orchestrator ?? sl.get<DownloadOrchestrator>();

    _progressSubscription = orchestrator.progressUpdates.listen(
      _onProgressUpdate,
    );
    _statusSubscription = orchestrator.statusUpdates.listen(
      _onStatusUpdate,
    );
    _extractionProgressSubscription = orchestrator.extractionProgressUpdates
        .listen(_onExtractionProgressUpdate);

    await _loadTasks();
  }

  void _onStatusUpdate(TaskStatusUpdate update) {
    if (update.task is CallbackTask) {
      if (update.status.isFinalState) {
        _callbackTasks.remove(update.task.taskId);
      } else {
        _callbackTasks[update.task.taskId] = TaskRecord(
          update.task,
          update.status,
          0,
          -1,
        );
      }
    }

    // Record when a download reaches its final state for history sorting.
    if (update.status.isFinalState) {
      _downloadedAt[update.task.taskId] = DateTime.now();
    }

    // Fire-and-forget is intentional to keep the stream callback
    // non-blocking, but we add error handling so failures don't go
    // unnoticed.
    _loadTasks().catchError((e, s) {
      // Errors are logged by _loadTasks itself; this catchError
      // prevents unhandled async exceptions.
    });
  }

  Future<void> _loadTasks() async {
    try {
      final allTasks = await _repository.getAllTasks();

      // Split into active (non-final) and history (final) tasks.
      final active = allTasks
          .where((t) => t.status.isNotFinalState)
          .toList();
      final history = allTasks
          .where((t) => !t.status.isNotFinalState)
          .toList();

      // Merge callback tasks into active list.
      active.addAll(_callbackTasks.values);

      active.sort((a, b) {
        if (a.status == TaskStatus.running) {
          return -1;
        } else if (b.status == TaskStatus.running) {
          return 1;
        }
        return b.task.priority.compareTo(a.task.priority);
      });

      // Build history entries: sort by downloadedAt descending.
      // Prefer timestamps from nexus_mod_manifest.json (written at
      // download-complete time), falling back to _downloadedAt (set when
      // status callback fires this session), then DateTime.now().
      final manifestTimestamps = await _readManifestTimestamps();

      final historyEntries = history.map((t) {
        final modId = _extractModId(t.task.metaData);
        final downloadedAt = _downloadedAt[t.taskId] ??
            (modId != null ? manifestTimestamps[modId] : null) ??
            DateTime.now();
        return DownloadHistoryEntry(
          record: t,
          downloadedAt: downloadedAt,
          modId: modId,
        );
      }).toList()
        ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));

      if (state is DownloadLoaded) {
        final currentState = state as DownloadLoaded;
        emit(
          currentState.copyWith(
            tasks: active,
            history: historyEntries,
          ),
        );
      } else {
        emit(
          DownloadLoaded(
            tasks: active,
            history: historyEntries,
          ),
        );
      }
    } catch (e, s) {
      // Don't let a database error prevent future state updates.
      // The next status/progress callback will retry.
      _logger.warning('Error loading download tasks', e, s);
    }
  }

  void _onProgressUpdate(TaskProgressUpdate update) {
    if (update.task is CallbackTask) {
      _callbackTasks[update.task.taskId] = TaskRecord(
        update.task,
        TaskStatus.running,
        update.progress,
        update.expectedFileSize,
      );
    }

    if (state is DownloadLoaded) {
      final currentState = state as DownloadLoaded;
      emit(currentState.copyWith(progressUpdate: update));
    } else {
      // State is still DownloadInitial (e.g., a progress update arrived
      // before any status update). Trigger a task list refresh so the
      // download appears in the UI.
      _loadTasks();
    }
  }

  void _onExtractionProgressUpdate(ProgressUpdate update) {
    if (state is! DownloadLoaded) return;
    final current = state as DownloadLoaded;
    emit(current.copyWith(extractionProgressUpdate: update));
  }

  Future<void> enqueueDownload(DownloadRequest request) async {
    await sl.isReady<DownloadOrchestrator>();
    final orchestrator = _orchestrator ?? sl.get<DownloadOrchestrator>();
    await orchestrator.enqueueDownload(request);
  }

  Future<void> pauseDownload(String taskId) async {
    await sl.isReady<DownloadOrchestrator>();
    final orchestrator = _orchestrator ?? sl.get<DownloadOrchestrator>();
    await orchestrator.pauseDownload(taskId);
  }

  Future<void> resumeDownload(String taskId) async {
    await sl.isReady<DownloadOrchestrator>();
    final orchestrator = _orchestrator ?? sl.get<DownloadOrchestrator>();
    await orchestrator.resumeDownload(taskId);
  }

  Future<void> cancelDownload(String taskId) async {
    await sl.isReady<DownloadOrchestrator>();
    final orchestrator = _orchestrator ?? sl.get<DownloadOrchestrator>();
    await orchestrator.cancelDownload(taskId);
  }

  /// Removes all completed, cancelled, and errored items from in-memory
  /// history. Does not touch the underlying database records.
  void clearHistory() {
    if (state is DownloadLoaded) {
      final current = state as DownloadLoaded;
      emit(current.copyWith(history: []));
    }
  }

  /// Removes a single history item from the in-memory list.
  void removeHistoryItem(String taskId) {
    if (state is DownloadLoaded) {
      final current = state as DownloadLoaded;
      emit(
        current.copyWith(
          history: current.history
              .where((e) => e.taskId != taskId)
              .toList(),
        ),
      );
    }
  }

  /// Extracts the NexusMods mod ID from task metadata, if present.
  static int? _extractModId(String metaDataString) {
    if (metaDataString.isEmpty) return null;
    try {
      final decoded = jsonDecode(metaDataString);
      if (decoded is Map<String, dynamic>) {
        final modId = decoded['modId'];
        if (modId != null) return (modId as num).toInt();
      }
    } catch (_) {}
    return null;
  }

  /// Reads `nexus_mod_manifest.json` and returns a map of modId ->
  /// DateTime parsed from the `lastDownloaded` field.
  static Future<Map<int, DateTime>> _readManifestTimestamps() async {
    try {
      final mods = await ModService.readManifestSection('mods');
      if (mods.isEmpty) return {};
      final result = <int, DateTime>{};
      for (final entry in mods.entries) {
        final modId = int.tryParse(entry.key);
        if (modId == null) continue;
        final meta = entry.value as Map<String, dynamic>?;
        final lastDownloaded = meta?['lastDownloaded'] as String?;
        if (lastDownloaded != null) {
          result[modId] = DateTime.tryParse(lastDownloaded) ?? DateTime.now();
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> close() {
    _progressSubscription?.cancel();
    _statusSubscription?.cancel();
    _extractionProgressSubscription?.cancel();
    return super.close();
  }
}
