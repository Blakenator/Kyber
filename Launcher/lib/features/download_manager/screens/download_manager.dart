import 'package:background_downloader/background_downloader.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as mt;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/features/download_manager/models/download_state.dart';
import 'package:kyber_launcher/features/download_manager/models/download_type.dart';
import 'package:kyber_launcher/features/download_manager/providers/download_manager_cubit.dart';
import 'package:kyber_launcher/features/nexusmods/services/nexusmods_service.dart';
import 'package:kyber_launcher/features/settings/dialogs/chromium_download_dialog.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/buttons/custom_icon_button.dart';
import 'package:kyber_launcher/shared/ui/cards/kyber_container.dart';
import 'package:kyber_launcher/shared/ui/utils/background_blur.dart';
import 'package:kyber_launcher/shared/ui/utils/button_builder.dart';
import 'package:kyber_launcher/shared/ui/elements/kyber_tab_bar.dart';
import 'package:url_launcher/url_launcher_string.dart';

class DownloadManager extends StatefulWidget {
  const DownloadManager({super.key});

  @override
  State<DownloadManager> createState() => _DownloadManagerState();
}

class _DownloadManagerState extends State<DownloadManager> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .all(10),
      child: Row(
        mainAxisAlignment: .center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 550,
              maxHeight: 900,
              maxWidth: 900,
            ),
            child: ClipRRect(
              borderRadius: .circular(kDefaultOuterBorderRadius),
              child: BackgroundBlur(
                child: Container(
                  alignment: .center,
                  decoration: BoxDecoration(
                    borderRadius: .circular(
                      kDefaultOuterBorderRadius,
                    ),
                    border: kDefaultAllBorder,
                  ),
                  child: ClipRRect(
                    borderRadius: .circular(
                      kDefaultOuterBorderRadius - 2,
                    ),
                    child: BlocBuilder<DownloadCubit, DownloadState>(
                      builder: (context, state) {
                        final tasks =
                            state is DownloadLoaded ? state.tasks : <TaskRecord>[];
                        final history =
                            state is DownloadLoaded ? state.history : <DownloadHistoryEntry>[];
                        final progressUpdate =
                            state is DownloadLoaded ? state.progressUpdate : null;
                        final currentDownload =
                            state is DownloadLoaded ? state.currentDownload : null;

                        final activeTasks = tasks
                            .where(
                              (e) =>
                                  e.status.isNotFinalState &&
                                  e.status != .paused,
                            )
                            .toList();

                        final pausedTasks = tasks
                            .where((e) => e.status == .paused)
                            .toList();

                        return Column(
                          crossAxisAlignment: .stretch,
                          children: [
                            const _DownloadManagerHeader(),
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  height: 40,
                                  width: 240,
                                  child: KyberTabBar(
                                    tabs: const [
                                      Text('ACTIVE'),
                                      Text('HISTORY'),
                                    ],
                                    selectedIndex: _selectedTab,
                                    onChanged: (i) =>
                                        setState(() => _selectedTab = i),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const CardSection(),
                            Expanded(
                              child: _selectedTab == 0
                                  ? _buildActiveTab(
                                      activeTasks,
                                      pausedTasks,
                                      progressUpdate,
                                    )
                                  : _buildHistoryTab(history),
                            ),
                            if (currentDownload != null)
                              _CurrentDownloadFooter(
                                currentDownload: currentDownload,
                                progressUpdate: progressUpdate,
                                tasks: tasks,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTab(
    List<TaskRecord> activeTasks,
    List<TaskRecord> pausedTasks,
    TaskProgressUpdate? progressUpdate,
  ) {
    if (activeTasks.isEmpty && pausedTasks.isEmpty) {
      return const Center(
        child: Text(
          'No active downloads',
          style: TextStyle(
            fontFamily: FontFamily.battlefrontUI,
            fontSize: 16,
            color: kGrayColor,
          ),
        ),
      );
    }
    return ListView(
      children: [
        if (activeTasks.isNotEmpty)
          _ActiveDownloadsList(
            tasks: activeTasks,
            progressUpdate: progressUpdate,
          ),
        if (pausedTasks.isNotEmpty)
          _PausedDownloadsSection(tasks: pausedTasks),
      ],
    );
  }

  Widget _buildHistoryTab(List<DownloadHistoryEntry> history) {
    if (history.isEmpty) {
      return const Center(
        child: Text(
          'No download history',
          style: TextStyle(
            fontFamily: FontFamily.battlefrontUI,
            fontSize: 16,
            color: kGrayColor,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${history.length} item${history.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontFamily: FontFamily.battlefrontUI,
                    fontSize: 14,
                    color: kGrayColor,
                  ),
                ),
              ),
              KyberIconButton(
                iconData: FluentIcons.delete,
                size: 16,
                onPressed: () =>
                    context.read<DownloadCubit>().clearHistory(),
              ),
            ],
          ),
        ),
        const CardSection(),
        Expanded(
          child: ListView(
            children: [
              for (var i = 0; i < history.length; i++) ...[
                if (i > 0) const CardSection(),
                _DownloadTaskItem(
                  task: history[i].record,
                  isHistory: true,
                  downloadedAt: history[i].downloadedAt,
                  modId: history[i].modId,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DownloadManagerHeader extends StatelessWidget {
  const _DownloadManagerHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  'DOWNLOAD MANAGER',
                  style: TextStyle(
                    fontFamily: FontFamily.aurebesh,
                    fontSize: 14,
                    color: kWhiteColor1,
                    height: 1,
                  ),
                ),
                Text(
                  'DOWNLOAD MANAGER',
                  style: TextStyle(
                    fontFamily: FontFamily.battlefrontUI,
                    fontSize: 24,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          KyberIconButton(
            iconData: FluentIcons.cancel,
            onPressed: router.pop,
          ),
        ],
      ),
    );
  }
}

class _ActiveDownloadsList extends StatelessWidget {
  const _ActiveDownloadsList({
    required this.tasks,
    required this.progressUpdate,
  });

  final List<TaskRecord> tasks;
  final TaskProgressUpdate? progressUpdate;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < tasks.length; i++) ...[
          if (i > 0) const CardSection(),
          _DownloadTaskItem(
            task: tasks[i],
            progressUpdate:
                tasks[i].status == TaskStatus.running ? progressUpdate : null,
          ),
        ],
      ],
    );
  }
}

class _PausedDownloadsSection extends StatelessWidget {
  const _PausedDownloadsSection({required this.tasks});

  final List<TaskRecord> tasks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: .symmetric(horizontal: 15, vertical: 10),
          child: Text(
            'PAUSED DOWNLOADS',
            style: TextStyle(
              fontFamily: FontFamily.battlefrontUI,
              fontSize: 20,
              color: kWhiteColor,
            ),
            textAlign: .left,
          ),
        ),
        const CardSection(),
        for (var i = 0; i < tasks.length; i++) ...[
          if (i > 0) const CardSection(),
          _DownloadTaskItem(task: tasks[i], isPaused: true),
        ],
      ],
    );
  }
}

class _DownloadTaskItem extends StatelessWidget {
  const _DownloadTaskItem({
    required this.task,
    this.progressUpdate,
    this.isPaused = false,
    this.isHistory = false,
    this.downloadedAt,
    this.modId,
  });

  final TaskRecord task;
  final TaskProgressUpdate? progressUpdate;
  final bool isPaused;
  final bool isHistory;
  final DateTime? downloadedAt;
  final int? modId;

  @override
  Widget build(BuildContext context) {
    final canRemove = isHistory || task.status.isFinalState;
    return SizedBox(
      height: 45,
      child: ButtonBuilder(
        builder: (context, hovered) {
          return Row(
            children: [
              _buildLeadingIcon(),
              const VCardSection(),
              Expanded(child: _buildTaskInfo()),
              if (isHistory) ...[
                const VCardSection(),
                _buildHistoryMeta(context),
              ],
              if (!isHistory && task.status.isNotFinalState) ...[
                const VCardSection(),
                _buildCancelButton(),
              ],
              if (canRemove) ...[
                const VCardSection(),
                _buildRemoveButton(context),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildHistoryMeta(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Row(
          children: [
          if (task.expectedFileSize != null &&
              task.expectedFileSize! > 0) ...[
            Text(
              formatBytes(task.expectedFileSize!, 1),
              style: const TextStyle(
                fontFamily: FontFamily.battlefrontUI,
                fontSize: 14,
                color: kGrayColor,
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (downloadedAt != null) ...[
            Flexible(
              child: Text(
                _formatDownloadedAt(downloadedAt!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: FontFamily.battlefrontUI,
                  fontSize: 14,
                  color: kGrayColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (modId != null)
            SizedBox(
              width: 24,
              height: 24,
              child: CustomIconButton(
                iconData: mt.Icons.open_in_new,
                size: 18,
                onPressed: () {
                  router.go('/mods/mod_browser/$modId');
                },
              ),
            ),
        ],
      ),
    ),
    );
  }

  String _formatDownloadedAt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  Widget _buildRemoveButton(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 45,
      child: CustomIconButton(
        iconData: FluentIcons.chrome_close,
        onPressed: () {
          final cubit = context.read<DownloadCubit>();
          if (isHistory) {
            cubit.removeHistoryItem(task.taskId);
          } else {
            FileDownloader().cancelTaskWithId(task.taskId);
          }
        },
      ),
    );
  }

  Widget _buildLeadingIcon() {
    if (isHistory) {
      final iconData = switch (task.status) {
        TaskStatus.complete => FluentIcons.completed,
        TaskStatus.canceled => FluentIcons.cancel,
        TaskStatus.failed => FluentIcons.error,
        _ => FluentIcons.status_error_full,
      };
      final color = switch (task.status) {
        TaskStatus.complete => kActiveColor,
        TaskStatus.canceled => kGrayColor,
        TaskStatus.failed => Colors.red,
        _ => kWhiteColor,
      };
      return SizedBox(
        width: 50,
        height: 45,
        child: Icon(iconData, color: color, size: 22),
      );
    }

    if (isPaused || task.status == .paused) {
      return SizedBox(
        width: 50,
        height: 45,
        child: CustomIconButton(
          iconData: FluentIcons.play,
          padding: const EdgeInsets.all(13),
          onPressed: () async {
            await FileDownloader().resume(task.task as DownloadTask);
          },
        ),
      );
    }

    if (task.status == .running) {
      return SizedBox(
        width: 50,
        height: 45,
        child: Icon(
          FluentIcons.download,
          color: kActiveColor,
          size: 25,
        ),
      );
    }

    return const SizedBox(
      width: 50,
      height: 45,
      child: Icon(
        mt.Icons.timelapse,
        color: kWhiteColor,
        size: 25,
      ),
    );
  }

  Widget _buildTaskInfo() {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(left: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  task.task.displayName,
                  style: const TextStyle(
                    fontFamily: FontFamily.battlefrontUI,
                    fontSize: 18,
                    height: 1,
                    color: kWhiteColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (task.status == TaskStatus.running && progressUpdate != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kActiveColor, Colors.transparent],
                  stops: [
                    progressUpdate?.progress ?? 1 / 100,
                    progressUpdate?.progress ?? 1 / 100,
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: 50,
      height: 45,
      child: CustomIconButton(
        iconData: FluentIcons.cancel,
        onPressed: () async {
          await FileDownloader().cancelTaskWithId(task.taskId);
        },
      ),
    );
  }
}

class _CurrentDownloadFooter extends StatelessWidget {
  const _CurrentDownloadFooter({
    required this.currentDownload,
    required this.progressUpdate,
    required this.tasks,
  });

  final TaskRecord? currentDownload;
  final TaskProgressUpdate? progressUpdate;
  final List<TaskRecord> tasks;

  bool get _shouldShowPremiumBanner {
    if (currentDownload == null) return false;

    final isNexusDownload = currentDownload!.task.url.contains('nexusmods') ||
        currentDownload!.task.url.contains('nexus-cdn');
    if (!isNexusDownload) return false;

    final isPremium =
        sl.get<NexusModsService>().nexusUser?.isPremium ?? true;

    return isNexusDownload && !isPremium;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_shouldShowPremiumBanner) const _NexusPremiumBanner(),
        const CardSection(),
        _buildProgressSection(),
      ],
    );
  }

  Widget _buildProgressSection() {
    return Container(
      alignment: Alignment.center,
      height: 85,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            _PauseResumeButton(
              currentDownload: currentDownload,
              tasks: tasks,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _DownloadProgressIndicator(
                currentDownload: currentDownload,
                progressUpdate: progressUpdate,
                tasks: tasks,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NexusPremiumBanner extends StatelessWidget {
  const _NexusPremiumBanner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(15),
        child: RichText(
          text: TextSpan(
            children: [
              const TextSpan(
                text: 'UN-CAP DOWNLOAD SPEEDS WITH ',
                style: TextStyle(
                  color: kGrayColor,
                  fontFamily: FontFamily.battlefrontUI,
                  fontSize: 16,
                ),
              ),
              TextSpan(
                text: 'NEXUS MODS PREMIUM',
                style: TextStyle(
                  color: kActiveColor,
                  fontFamily: FontFamily.battlefrontUI,
                  fontSize: 16,
                ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () => launchUrlString(
                        'https://users.nexusmods.com/account/billing/premium',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PauseResumeButton extends StatelessWidget {
  const _PauseResumeButton({
    required this.currentDownload,
    required this.tasks,
  });

  final TaskRecord? currentDownload;
  final List<TaskRecord> tasks;

  Future<void> _onPressed() async {
    if (currentDownload != null) {
      await FileDownloader().pause(currentDownload!.task as DownloadTask);
    } else {
      final pausedTask = tasks.firstWhere(
        (e) => e.status == TaskStatus.paused,
      );
      await FileDownloader().resume(pausedTask.task as DownloadTask);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 55,
      child: ClipRRect(
        borderRadius: .circular(100),
        child: ButtonBuilder(
          onClick: _onPressed,
          builder: (context, hovered) {
            return Stack(
              children: [
                Positioned.fill(
                  child: Assets.icons.kblPauseCircle.svg(),
                ),
                Positioned.fill(
                  child: Container(
                    margin: const .all(10),
                    decoration: BoxDecoration(
                      borderRadius: .circular(100),
                      border: .all(
                        color: hovered ? kActiveColor : kWhiteColor,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        currentDownload != null
                            ? mt.Icons.pause
                            : mt.Icons.play_arrow,
                        size: 18,
                        color: hovered ? kActiveColor : kWhiteColor,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DownloadProgressIndicator extends StatelessWidget {
  const _DownloadProgressIndicator({
    required this.currentDownload,
    required this.progressUpdate,
    required this.tasks,
  });

  final TaskRecord? currentDownload;
  final TaskProgressUpdate? progressUpdate;
  final List<TaskRecord> tasks;

  @override
  Widget build(BuildContext context) {
    final download = currentDownload ??
        tasks.firstWhere(
          (e) => e.status == TaskStatus.paused || e.status == TaskStatus.enqueued,
        );
    final size = progressUpdate?.expectedFileSize ?? download.expectedFileSize;
    final progress = progressUpdate?.progress ?? (download.progress) * 100;
    final downloadType = DownloadTypeHelper.getDownloadType(download.task.url);

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildSourceIcon(downloadType),
        _buildProgressBar(progress),
        _buildProgressText(size, progress),
        Positioned.fill(
          child: Assets.icons.kblDownloadProgress.svg(),
        ),
      ],
    );
  }

  Widget _buildSourceIcon(DownloadType downloadType) {
    return Positioned(
      top: 15,
      left: 5,
      child: SizedBox(
        height: 20,
        width: 20,
        child: switch (downloadType) {
          .kyber => Assets.logos.kyberLight.svg(),
          .nexus => Assets.logos.nexusMods.svg(),
          .online => const Icon(
              FluentIcons.globe,
              color: kWhiteColor,
            ),
        },
      ),
    );
  }

  Widget _buildProgressBar(double progress) {
    return Positioned(
      top: 15,
      left: 33,
      right: 229,
      bottom: 20,
      child: AnimatedFractionallySizedBox(
        widthFactor: progress >= 0.0 ? progress : 0.01,
        alignment: Alignment.centerLeft,
        duration: const Duration(milliseconds: 200),
        child: Container(color: kActiveColor),
      ),
    );
  }

  Widget _buildProgressText(int size, double progress) {
    final downloadedBytes = formatBytes((size * progress).toInt(), 1);
    final totalBytes = formatBytes(size, 1);
    final speed = formatBytes(
      (progressUpdate?.networkSpeed.toInt() ?? 0) * 1000000,
      1,
    );
    final percentage = (progress * 100).toInt();

    return Positioned(
      top: 15,
      left: 563,
      right: 5,
      bottom: 19,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            downloadedBytes,
            style: TextStyle(
              fontFamily: FontFamily.battlefrontUI,
              fontSize: 15,
              color: kActiveColor,
            ),
          ),
          Text(
            ' / $totalBytes ($speed/s) $percentage%',
            style: const TextStyle(
              fontFamily: FontFamily.battlefrontUI,
              fontSize: 15,
              color: kWhiteColor,
            ),
          ),
        ],
      ),
    );
  }
}
