part of 'live_cue_page.dart';

ProjectSetlistSectionType _liveCueSectionTypeFromItem(
  Map<String, dynamic>? data,
) {
  return ProjectSetlistSectionType.fromUnknown(
    data?['sectionType']?.toString(),
  );
}

Widget _buildLiveCueSectionBadge(
  BuildContext context,
  ProjectSetlistSectionType sectionType,
) {
  final colorScheme = Theme.of(context).colorScheme;
  return Chip(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
    backgroundColor: colorScheme.surface.withValues(alpha: 0.92),
    label: Text(sectionType.displayLabel()),
  );
}

Widget _buildLiveCueOperatorPage(
  _LiveCuePageState state,
  BuildContext context,
) {
  final ref = state.ref;
  final widget = state.widget;
  final syncCoordinator = state._syncCoordinator;
  final focusNode = state._focusNode;
  final beginCueWaitingWatchdog = state._beginCueWaitingWatchdog;
  final clearCueWaitingWatchdog = state._clearCueWaitingWatchdog;
  final isCueWaitingTimedOut = state._isCueWaitingTimedOut;
  final cueAutoRetryAttempted = state._cueAutoRetryAttempted;
  final scheduleCueAutoRetry = state._scheduleCueAutoRetry;
  final retryCueSync = state._retryCueSync;
  final resetCueRetryState = state._resetCueRetryState;
  final seedFromSetlistIfNeeded = state._seedFromSetlistIfNeeded;
  final moveByStep = state._moveByStep;
  final applySetlistAsCurrent = state._applySetlistAsCurrent;
  final reorderSetlistItem = state._reorderSetlistItem;
  final deleteSetlistItem = state._deleteSetlistItem;
  final setCurrentKey = state._setCurrentKey;
  final requestPageRebuild = state._requestPageRebuild;
  final loadAvailableKeysCached = state._loadAvailableKeysCached;
  final setlistMutationInFlight = state._setlistMutationInFlight;
  final firestore = ref.watch(firestoreProvider);
  final setlistRef = _setlistRefFor(firestore, widget.teamId, widget.projectId);
  final liveCueRef = _liveCueRefFor(firestore, widget.teamId, widget.projectId);
  final setlistQuery = setlistRef.orderBy('order');
  final syncStreams = syncCoordinator.attach(
    setlistQuery: setlistQuery,
    liveCueRef: liveCueRef,
  );
  final setlistStream = syncStreams.setlist;
  final cueStream = syncStreams.cue;

  return Focus(
    focusNode: focusNode,
    autofocus: true,
    onKeyEvent: (node, event) {
      if (!widget.canEdit) return KeyEventResult.ignored;
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (state._latestSetlist.isEmpty) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.keyA) {
        moveByStep(firestore, state._latestSetlist, state._latestCueData, -1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.keyD) {
        moveByStep(firestore, state._latestSetlist, state._latestCueData, 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: AppContentFrame(
      maxWidth: 1260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionCard(
            icon: Icons.equalizer_rounded,
            title: 'LiveCue',
            subtitle: widget.canEdit
                ? '운영 모드에서 곡을 전환하고, 악보보기에서 전체화면 악보를 확인합니다.'
                : '운영 모드 상태와 악보보기를 실시간으로 확인합니다.',
            trailing: FilledButton.tonalIcon(
              onPressed: () => context.go(
                '/teams/${widget.teamId}/projects/${widget.projectId}/live',
              ),
              icon: const Icon(Icons.fullscreen),
              label: const Text('악보보기'),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const Chip(
                  avatar: Icon(Icons.swipe, size: 16),
                  label: Text('운영 모드'),
                ),
                const Chip(
                  avatar: Icon(Icons.fullscreen, size: 16),
                  label: Text('악보보기'),
                ),
                const Chip(
                  avatar: Icon(Icons.auto_awesome, size: 16),
                  label: Text('콘티 입력 자동 반영'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: setlistStream,
              builder: (context, setlistSnapshot) {
                if (setlistSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const AppLoadingState(message: '콘티를 불러오는 중...');
                }
                if (setlistSnapshot.hasError) {
                  return AppStateCard(
                    icon: Icons.error_outline,
                    isError: true,
                    title: '콘티 로드 실패',
                    message: '${setlistSnapshot.error}',
                    actionLabel: '다시 시도',
                    onAction: requestPageRebuild,
                  );
                }
                final items = setlistSnapshot.data?.docs ?? [];
                state._latestSetlist = items;

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: cueStream,
                  builder: (context, cueSnapshot) {
                    if (cueSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      beginCueWaitingWatchdog();
                      if (isCueWaitingTimedOut) {
                        if (!cueAutoRetryAttempted) {
                          scheduleCueAutoRetry();
                          return const AppLoadingState(
                            message: 'LiveCue 자동 재연결 시도 중...',
                          );
                        }
                        return AppStateCard(
                          icon: Icons.sync_problem_outlined,
                          isError: true,
                          title: 'LiveCue 상태 동기화 지연',
                          message:
                              '상태 문서를 읽지 못하고 있습니다. 권한/네트워크를 확인한 뒤 다시 시도해 주세요.',
                          actionLabel: '다시 시도',
                          onAction: retryCueSync,
                        );
                      }
                      return const AppLoadingState(
                        message: 'LiveCue 상태 동기화 중...',
                      );
                    }
                    clearCueWaitingWatchdog();
                    if (cueSnapshot.hasError) {
                      if (!cueAutoRetryAttempted) {
                        scheduleCueAutoRetry();
                        return const AppLoadingState(
                          message: 'LiveCue 상태 복구 시도 중...',
                        );
                      }
                      return AppStateCard(
                        icon: Icons.sync_problem_outlined,
                        isError: true,
                        title: 'LiveCue 상태 로드 실패',
                        message: '${cueSnapshot.error}',
                        actionLabel: '다시 시도',
                        onAction: retryCueSync,
                      );
                    }

                    resetCueRetryState();
                    final cueData = cueSnapshot.data?.data() ?? {};
                    state._latestCueData = cueData;
                    if (items.isNotEmpty &&
                        !_hasCueValue(cueData, 'current') &&
                        !state._autoSeeding) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!state.mounted) return;
                        seedFromSetlistIfNeeded(firestore, items, cueData);
                      });
                    }

                    final syncState = LiveCueResolvedState.resolve(
                      items: items,
                      cueData: cueData,
                      cueLabelFromItem: _cueLabelFromItem,
                      titleFromItem: _titleFromItem,
                      keyFromItem: _keyFromItem,
                      normalizeKeyText: normalizeKeyText,
                    );
                    final currentIndex = syncState.currentIndex;
                    final currentSongId = syncState.currentSongId;
                    final currentTitle = syncState.currentTitle;
                    final currentKey = syncState.currentKey;
                    final currentLabel = syncState.currentLabel;
                    final currentMetadataSummary = _buildMetadataSummary(
                      _extractMetadataFromItem(
                        syncState.matchedCurrentSetlistData,
                      ),
                    );
                    final nextTitle = syncState.nextTitle;
                    final nextKey = syncState.nextKey;
                    final nextLabel = syncState.nextLabel;
                    final nextMetadataSummary = _buildMetadataSummary(
                      _extractMetadataFromItem(
                        syncState.nextIndex >= 0 &&
                                syncState.nextIndex < items.length
                            ? items[syncState.nextIndex].data()
                            : null,
                      ),
                    );

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragEnd: (details) {
                        if (!widget.canEdit) return;
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity > 220) {
                          moveByStep(firestore, items, cueData, -1);
                        } else if (velocity < -220) {
                          moveByStep(firestore, items, cueData, 1);
                        }
                      },
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 1120;

                          final livePanel = AppSectionCard(
                            icon: Icons.equalizer_rounded,
                            title: '실시간 진행 라인',
                            subtitle: '운영 모드: 현재/다음 곡 전환',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.34),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _lineText(
                                          label: currentLabel,
                                          title: currentTitle,
                                          keyText: currentKey,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      if (currentMetadataSummary
                                          .hasMetadata) ...[
                                        const SizedBox(height: 8),
                                        _buildLiveCueOperatorMetadataBlock(
                                          context,
                                          currentMetadataSummary,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.46),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _lineText(
                                          label: nextLabel,
                                          title: nextTitle,
                                          keyText: nextKey,
                                        ),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyLarge,
                                      ),
                                      if (nextMetadataSummary.hasMetadata) ...[
                                        const SizedBox(height: 6),
                                        _buildLiveCueOperatorMetadataBlock(
                                          context,
                                          nextMetadataSummary,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: widget.canEdit
                                          ? () => moveByStep(
                                              firestore,
                                              items,
                                              cueData,
                                              -1,
                                            )
                                          : null,
                                      icon: const Icon(Icons.chevron_left),
                                      label: const Text('이전'),
                                    ),
                                    FilledButton.tonalIcon(
                                      onPressed: widget.canEdit
                                          ? () => moveByStep(
                                              firestore,
                                              items,
                                              cueData,
                                              1,
                                            )
                                          : null,
                                      icon: const Icon(Icons.chevron_right),
                                      label: const Text('다음'),
                                    ),
                                    const Chip(
                                      avatar: Icon(Icons.swipe, size: 16),
                                      label: Text('스와이프/화살표 전환'),
                                    ),
                                    const CircleOfFifthsHelpButton(
                                      label: '5도권 참고',
                                      compact: true,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );

                          final keysPanel =
                              (currentSongId != null &&
                                  currentSongId.isNotEmpty)
                              ? FutureBuilder<List<String>>(
                                  future: loadAvailableKeysCached(
                                    firestore,
                                    currentSongId,
                                  ),
                                  builder: (context, keySnapshot) {
                                    final keys =
                                        keySnapshot.data ?? const <String>[];
                                    if (keys.length <= 1) {
                                      return const SizedBox.shrink();
                                    }
                                    final selectedKey =
                                        cueData['currentKeyText']?.toString() ??
                                        '';
                                    return AppSectionCard(
                                      icon: Icons.piano_rounded,
                                      title: '현재 곡 키 선택',
                                      subtitle: '키 전환 시 악보 매칭 우선순위가 바뀝니다.',
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: keys
                                            .map(
                                              (key) => ChoiceChip(
                                                label: Text(key),
                                                selected:
                                                    normalizeKeyText(
                                                      selectedKey,
                                                    ) ==
                                                    normalizeKeyText(key),
                                                onSelected: widget.canEdit
                                                    ? (_) => setCurrentKey(
                                                        firestore,
                                                        key,
                                                      )
                                                    : null,
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    );
                                  },
                                )
                              : const SizedBox.shrink();

                          final setlistPanel = AppSectionCard(
                            icon: Icons.format_list_numbered_rounded,
                            title: '등록 콘티',
                            subtitle: 'LiveCue 반영 기준 목록',
                            child: items.isEmpty
                                ? AppStateCard(
                                    icon: Icons
                                        .playlist_add_check_circle_outlined,
                                    title: '콘티가 비어 있습니다',
                                    message: widget.canEdit
                                        ? '예배 전 탭에서 콘티를 입력하면 자동으로 LiveCue에 반영됩니다.'
                                        : '팀장이 콘티를 입력하면 여기에서 곡 전환 상태를 볼 수 있습니다.',
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: items.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final data = items[index].data();
                                      final colorScheme = Theme.of(
                                        context,
                                      ).colorScheme;
                                      final label = _displayOrderLabelFromItem(
                                        data,
                                        index + 1,
                                      );
                                      final title = _titleForDisplayFromItem(
                                        data,
                                      );
                                      final key = _keyFromItem(data);
                                      final line = _lineText(
                                        label: label,
                                        title: title,
                                        keyText: key,
                                      );
                                      final isCurrent = index == currentIndex;
                                      final sectionType =
                                          _liveCueSectionTypeFromItem(data);
                                      return AppActionListTile(
                                        backgroundColor: isCurrent
                                            ? colorScheme.primaryContainer
                                                  .withValues(alpha: 0.58)
                                            : colorScheme
                                                  .surfaceContainerHighest
                                                  .withValues(alpha: 0.46),
                                        title: Text(
                                          line,
                                          style: isCurrent
                                              ? const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                )
                                              : null,
                                        ),
                                        subtitle: Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            _buildLiveCueSectionBadge(
                                              context,
                                              sectionType,
                                            ),
                                            if (isCurrent)
                                              Text(
                                                widget.canEdit
                                                    ? '현재 Cue에 반영 중'
                                                    : '현재 Cue',
                                              ),
                                          ],
                                        ),
                                        actions: [
                                          if (!isCurrent && widget.canEdit)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.playlist_play,
                                              ),
                                              tooltip: '현재 Cue로 이동',
                                              onPressed: () =>
                                                  applySetlistAsCurrent(
                                                    firestore,
                                                    items,
                                                    index,
                                                  ),
                                            ),
                                          if (widget.canEdit && index > 0)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.arrow_upward,
                                              ),
                                              tooltip: '위로 이동',
                                              onPressed: setlistMutationInFlight
                                                  ? null
                                                  : () => reorderSetlistItem(
                                                      firestore,
                                                      items,
                                                      oldIndex: index,
                                                      newIndex: index - 1,
                                                    ),
                                            ),
                                          if (widget.canEdit &&
                                              index < items.length - 1)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.arrow_downward,
                                              ),
                                              tooltip: '아래로 이동',
                                              onPressed: setlistMutationInFlight
                                                  ? null
                                                  : () => reorderSetlistItem(
                                                      firestore,
                                                      items,
                                                      oldIndex: index,
                                                      newIndex: index + 1,
                                                    ),
                                            ),
                                          if (widget.canEdit)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline,
                                              ),
                                              tooltip: '삭제',
                                              onPressed: setlistMutationInFlight
                                                  ? null
                                                  : () => deleteSetlistItem(
                                                      context,
                                                      firestore,
                                                      items[index],
                                                    ),
                                            ),
                                        ],
                                        onTap: widget.canEdit
                                            ? () => applySetlistAsCurrent(
                                                firestore,
                                                items,
                                                index,
                                              )
                                            : null,
                                      );
                                    },
                                  ),
                          );

                          if (isWide) {
                            return SingleChildScrollView(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 7,
                                    child: Column(
                                      children: [
                                        livePanel,
                                        const SizedBox(height: 10),
                                        keysPanel,
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(flex: 5, child: setlistPanel),
                                ],
                              ),
                            );
                          }

                          return ListView(
                            children: [
                              livePanel,
                              const SizedBox(height: 10),
                              keysPanel,
                              const SizedBox(height: 10),
                              setlistPanel,
                            ],
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
