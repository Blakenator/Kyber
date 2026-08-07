// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/gen/Proto/kyber_common.pb.dart';
import 'package:kyber/gen/Proto/kyber_interface.pb.dart' as ki;
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_status_cubit.dart';
import 'package:kyber_launcher/features/kyber/services/map_helper.dart';
import 'package:kyber_launcher/features/map_rotation/models/map_rotation_entry.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/features/server_browser/dialogs/load_map_dialog.dart';
import 'package:kyber_launcher/features/server_host/providers/host_collection_cubit.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:logging/logging.dart';

/// Shows the running server's map rotation and allows the host to edit it
/// (reorder, add, remove) and jump to any map. The server is the source of
/// truth: the list is read from [KyberStatusHosting.serverState] and edits
/// are pushed back to the module via the local `Server.SetMapRotation` RPC.
class IngameRotation extends StatefulWidget {
  const IngameRotation({super.key});

  @override
  State<IngameRotation> createState() => _IngameRotationState();
}

class _IngameRotationState extends State<IngameRotation> {
  static final _logger = Logger('ingame_rotation');

  /// Working copy of the rotation. Synced from the server when there are no
  /// pending local edits; otherwise holds the in-progress edit.
  List<LevelSetup> _rotation = [];
  bool _dirty = false;

  bool _sameRotation(List<LevelSetup> a, List<LevelSetup> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].map != b[i].map || a[i].mode != b[i].mode) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<KyberStatusCubit, KyberStatusState>(
      listener: (context, state) {
        if (state is! KyberStatusHosting) {
          if (_rotation.isNotEmpty || _dirty) {
            setState(() {
              _rotation = [];
              _dirty = false;
            });
          }
          return;
        }

        // Server is SOT; re-sync from it while no edits are pending.
        if (!_dirty) {
          final serverRotation = List<LevelSetup>.from(
            state.serverState.mapRotation,
          );
          if (!_sameRotation(serverRotation, _rotation)) {
            setState(() => _rotation = serverRotation);
          }
        }
      },
      child: BlocBuilder<KyberStatusCubit, KyberStatusState>(
        builder: (context, state) {
          if (state is! KyberStatusHosting) {
            return const Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No server running',
                  style: TextStyle(
                    fontFamily: FontFamily.battlefrontUI,
                    fontSize: 16,
                    color: kInactiveColor,
                  ),
                ),
              ),
            );
          }
          return _buildContent(context, state);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, KyberStatusHosting status) {
    final playingMap = status.serverState.levelSetup.map;
    final playingMode = status.serverState.levelSetup.mode;
    // Prefer the server-reported index (authoritative); fall back to matching
    // the currently playing map against the rotation when it's out of range.
    var currentIndex = status.serverState.mapRotationIndex;
    if (currentIndex < 0 || currentIndex >= _rotation.length) {
      currentIndex = _rotation.indexWhere(
        (entry) => entry.map == playingMap && entry.mode == playingMode,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              KyberButton(
                text: 'SKIP MAP',
                icon: const Icon(mt.Icons.skip_next),
                onPressed: () => context
                    .read<ModerationCubit>()
                    .sendCommand('/Kyber.restart'),
              ),
              const SizedBox(width: 10),
              KyberButton(
                text: 'ADD MAP',
                icon: const Icon(mt.Icons.add),
                onPressed: _addMap,
              ),
              const Spacer(),
              Text(
                '${_rotation.length} maps',
                style: const TextStyle(
                  fontFamily: FontFamily.battlefrontUI,
                  fontSize: 12,
                  color: kInactiveColor,
                ),
              ),
            ],
          ),
        ),
        const CardSection(),
        Expanded(
          child: _rotation.isEmpty
              ? const Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No maps in rotation',
                      style: TextStyle(
                        fontFamily: FontFamily.battlefrontUI,
                        fontSize: 16,
                        color: kInactiveColor,
                      ),
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.all(10),
                  itemCount: _rotation.length,
                  onReorderItem: _onReorder,
                  itemBuilder: (context, index) {
                    final entry = _rotation[index];
                    return _RotationTile(
                      key: ValueKey('$index-${entry.map}-${entry.mode}'),
                      index: index,
                      entry: entry,
                      isCurrent: index == currentIndex,
                      onRemove: () => _removeAt(index),
                      onJump: () => _jumpTo(entry),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _rotation.removeAt(oldIndex);
      _rotation.insert(newIndex, item);
      _dirty = true;
    });
    unawaited(_save());
  }

  void _removeAt(int index) {
    setState(() {
      _rotation.removeAt(index);
      _dirty = true;
    });
    unawaited(_save());
  }

  Future<void> _addMap() async {
    final result = await showKyberDialog<MapRotationEntry>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<HostCollectionCubit>(),
        child: const LoadMapDialog(),
      ),
    );
    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _rotation.add(LevelSetup(map: result.map, mode: result.mode));
      _dirty = true;
    });
    unawaited(_save());
  }

  void _jumpTo(LevelSetup entry) {
    context
        .read<ModerationCubit>()
        .sendCommand('/Kyber.LoadLevel ${entry.map} ${entry.mode}');
  }

  Future<void> _save() async {
    if (!sl.isRegistered<MaximaGameInstance>()) {
      NotificationService.error(
        message: 'Game instance is not available to update the map rotation',
      );
      if (mounted) {
        setState(() => _dirty = false);
      }
      return;
    }

    // The `current` field is the index of the currently playing map within the
    // new rotation. If the playing map was removed, point at the last entry so
    // the server wraps back to the top on the next auto-rotation.
    var current = 0;
    final status = context.read<KyberStatusCubit>().state;
    if (status is KyberStatusHosting) {
      final playingMap = status.serverState.levelSetup.map;
      final playingMode = status.serverState.levelSetup.mode;
      final idx = _rotation.indexWhere(
        (entry) => entry.map == playingMap && entry.mode == playingMode,
      );
      if (idx != -1) {
        current = idx;
      } else if (_rotation.isNotEmpty) {
        current = _rotation.length - 1;
      }
    }

    try {
      await sl
          .get<MaximaGameInstance>()
          .clientService
          .serverClient
          .setMapRotation(
            ki.SetMapRotationRequest(rotation: _rotation, current: current),
          );
    } on Exception catch (e, stack) {
      _logger.severe('Failed to update map rotation', e, stack);
      NotificationService.error(message: 'Failed to update map rotation');
    } finally {
      if (mounted) {
        // The server echoes the rotation back via GetInfo; re-sync on the
        // next poll.
        setState(() => _dirty = false);
      }
    }
  }
}

class _RotationTile extends StatelessWidget {
  const _RotationTile({
    required this.index,
    required this.entry,
    required this.isCurrent,
    required this.onRemove,
    required this.onJump,
    super.key,
  });

  final int index;
  final LevelSetup entry;
  final bool isCurrent;
  final VoidCallback onRemove;
  final VoidCallback onJump;

  @override
  Widget build(BuildContext context) {
    final mode = MapHelper.getMode(entry.mode);
    final mapName = mode != null
        ? MapHelper.getMapName(mode, entry.map)
        : entry.map;
    final modeName = mode?.name ?? entry.mode;
    final image = MapHelper.getImageForMap(entry.map);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: KyberCard(
        borderColor: isCurrent ? kActiveColor : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  fontFamily: FontFamily.battlefrontUI,
                  fontSize: 16,
                  color: kInactiveColor,
                ),
              ),
            ),
            if (image != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 56,
                  height: 32,
                  child: image.image(fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      mapName,
                      style: const TextStyle(
                        fontFamily: FontFamily.battlefrontUI,
                        fontSize: 15,
                        color: kWhiteColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      modeName,
                      style: const TextStyle(
                        fontFamily: FontFamily.battlefrontUI,
                        fontSize: 12,
                        color: kInactiveColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
            if (isCurrent) ...[
              Text(
                'NOW PLAYING',
                style: TextStyle(
                  fontFamily: FontFamily.battlefrontUI,
                  fontSize: 11,
                  color: kActiveColor,
                ),
              ),
              const SizedBox(width: 8),
            ],
            KyberTooltip(
              message: 'Jump to map',
              child: KyberIconButton(
                iconData: mt.Icons.double_arrow,
                size: 16,
                onPressed: onJump,
              ),
            ),
            const SizedBox(width: 6),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Transform.rotate(
                  // 90 degrees
                  angle: 1.57,
                  child: const Icon(
                    mt.Icons.drag_indicator,
                    size: 20,
                    color: kInactiveColor,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(mt.Icons.close, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}
