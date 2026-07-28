import 'package:background_downloader/background_downloader.dart';
import 'package:collection/collection.dart';
import 'package:kyber_launcher/features/download_manager/services/download_orchestrator.dart';

/// A single entry in the download history, bundling the task record with
/// when it reached its final state and the associated NexusMods mod ID
/// (extracted from task metadata).
class DownloadHistoryEntry {
  const DownloadHistoryEntry({
    required this.record,
    required this.downloadedAt,
    this.modId,
  });

  final TaskRecord record;
  final DateTime downloadedAt;
  final int? modId;

  String get taskId => record.taskId;
  TaskStatus get status => record.status;
}

sealed class DownloadState {
  const DownloadState();
}

class DownloadInitial extends DownloadState {
  const DownloadInitial();
}

class DownloadLoaded extends DownloadState {
  const DownloadLoaded({
    required this.tasks,
    this.history = const [],
    this.progressUpdate,
    this.extractionProgressUpdate,
  });

  /// Progress on extraction phase (incremental updates only).
  final ProgressUpdate? extractionProgressUpdate;
  /// Active and paused downloads (non-final states).
  final List<TaskRecord> tasks;
  /// Completed, cancelled, and errored downloads (final states).
  final List<DownloadHistoryEntry> history;
  final TaskProgressUpdate? progressUpdate;

  TaskRecord? get currentDownload => tasks.firstWhereOrNull(
        (e) => e.status == TaskStatus.running,
      );

  List<TaskRecord> get activeTasks => tasks
      .where(
        (e) => e.status.isNotFinalState && e.status != TaskStatus.paused,
      )
      .toList();

  List<TaskRecord> get pausedTasks => tasks
      .where(
        (e) => e.status == TaskStatus.paused,
      )
      .toList();

  DownloadLoaded copyWith({
    List<TaskRecord>? tasks,
    List<DownloadHistoryEntry>? history,
    TaskProgressUpdate? progressUpdate,
    ProgressUpdate? extractionProgressUpdate,
  }) {
    return DownloadLoaded(
      tasks: tasks ?? this.tasks,
      history: history ?? this.history,
      progressUpdate: progressUpdate ?? this.progressUpdate,
      extractionProgressUpdate:
          extractionProgressUpdate ?? this.extractionProgressUpdate,
    );
  }
}
