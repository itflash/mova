import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../app/app_scope.dart';
import '../app/app_state.dart';
import '../app/models.dart';
import 'home_shell.dart';
import 'image_create_page.dart';
import '../widgets/attachment_media.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  static const MethodChannel _mediaChannel = MethodChannel('mova/media');

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final filteredTasks = state.tasks.where((task) {
      if (state.activeTaskTab == TaskTab.video) {
        return task.kind == TaskKind.video;
      }
      return task.kind == TaskKind.image;
    }).toList();

    return AppPageScaffold(
      eyebrow: 'Queue',
      title: '任务',
      subtitle: '进度、结果、日志和异常状态。',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: SegmentedButton<TaskTab>(
              segments: const [
                ButtonSegment<TaskTab>(
                  value: TaskTab.video,
                  label: Text('视频'),
                  icon: Icon(Icons.movie_outlined, size: 18),
                ),
                ButtonSegment<TaskTab>(
                  value: TaskTab.image,
                  label: Text('图片'),
                  icon: Icon(Icons.image_outlined, size: 18),
                ),
              ],
              selected: {state.activeTaskTab},
              onSelectionChanged: (selected) {
                state.setActiveTaskTab(selected.first);
              },
              emptySelectionAllowed: false,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filteredTasks.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                    children: [_TaskEmptyState(activeTab: state.activeTaskTab)],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                    itemCount: filteredTasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final task = filteredTasks[index];
                      if (task.kind == TaskKind.image) {
                        return _ImageTaskCard(task: task);
                      }
                      return _VideoTaskCard(task: task);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadResult(
    BuildContext context,
    AppState state,
    TaskRecord task,
  ) async {
    final downloaded = await state.downloadTaskResult(task.id);
    if (!context.mounted) return;
    _showToast(context, downloaded ? '结果已下载到系统相册/媒体库' : '下载暂不可用');
  }

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyTaskId(BuildContext context, String taskId) async {
    await copyToClipboard(context, text: taskId, message: '已复制任务号');
  }

  Future<void> _copyText(
    BuildContext context,
    String value,
    String label,
  ) async {
    await copyToClipboard(context, text: value, message: '已复制$label');
  }

  Future<void> _openMedia(BuildContext context, TaskRecord task) async {
    final uri = task.localResourceUri ?? task.videoUrl;
    if (uri == null || uri.trim().isEmpty) {
      _showToast(context, '当前没有可打开的媒体');
      return;
    }
    final mimeType =
        (task.localFileName ?? task.videoUrl ?? '').toLowerCase().contains(
              '.jpg',
            ) ||
            (task.localFileName ?? task.videoUrl ?? '').toLowerCase().contains(
              '.png',
            ) ||
            (task.localFileName ?? task.videoUrl ?? '').toLowerCase().contains(
              '.jpeg',
            )
        ? 'image/*'
        : 'video/*';
    try {
      await _mediaChannel.invokeMethod<bool>('openMedia', {
        'uri': uri,
        'mimeType': mimeType,
      });
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      _showToast(context, error.message ?? '打开媒体失败');
    }
  }

  Future<void> _confirmRetry(
    BuildContext context,
    AppState state,
    TaskRecord task,
  ) async {
    final confirmed = await confirmAction(
      context,
      title: '重新提交任务？',
      message: '会使用当前任务参数重新提交一次。',
      confirmLabel: '重新提交',
      destructive: true,
    );
    if (!confirmed) return;
    final retried = await state.retryTask(task.id);
    if (!context.mounted) return;
    _showToast(context, retried ? '已重新提交任务' : '重新提交失败');
  }

  Future<void> _confirmDeleteTask(
    BuildContext context,
    AppState state,
    TaskRecord task,
  ) async {
    final confirmed = await confirmAction(
      context,
      title: '删除任务？',
      message: '任务「${task.id}」会从列表中移除。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed) return;
    state.deleteTask(task.id);
    if (!context.mounted) return;
    _showToast(context, '已删除任务');
  }

  Future<void> _openTaskDetail(BuildContext context, TaskRecord task) async {
    final isImage = task.kind == TaskKind.image;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text('任务详情', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            _DetailBlock(label: '任务 ID', value: task.id, copyValue: task.id),
            _DetailBlock(
              label: '模式',
              value: isImage
                  ? _imageModeLabel(task.imageMode)
                  : _modeLabel(task.mode),
            ),
            _DetailBlock(label: '状态', value: _statusLabel(task.status)),
            _DetailBlock(label: '轮询', value: _pollingLabel(task.pollingStatus)),
            if (!isImage)
              _DetailBlock(
                label: '下载',
                value: _downloadLabel(task.downloadStatus),
              ),
            _DetailBlock(label: '创建时间', value: _formatDateTime(task.createdAt)),
            _DetailBlock(label: '更新时间', value: _formatDateTime(task.updatedAt)),
            _DetailBlock(label: '状态详情', value: task.statusDetail ?? '等待更新'),
            _DetailBlock(label: '失败信息', value: task.lastError ?? '当前无失败信息'),
            _DetailBlock(
              label: '异常标识',
              value: task.anomalyMessage ?? (task.hasAnomaly ? '存在异常' : '无'),
            ),
            if (isImage) ...[
              _DetailBlock(label: '工具名', value: task.toolName ?? '未知'),
              _DetailBlock(label: '预计积分', value: '${task.estimatedCredit}'),
              if (task.imageMetadata != null) ...[
                _DetailBlock(
                  label: '比例',
                  value: task.imageMetadata!.aspectRatio,
                ),
                _DetailBlock(label: '质量', value: task.imageMetadata!.quality),
                _DetailBlock(
                  label: '张数',
                  value: '${task.imageMetadata!.numImages}',
                ),
                _DetailBlock(
                  label: '输出格式',
                  value: task.imageMetadata!.outputFormat,
                ),
              ],
              _DetailBlock(label: '生成张数', value: '${task.imageResults.length}'),
              _DetailBlock(
                label: '已入库',
                value:
                    '${task.imageResults.where((r) => r.status == ImageResultStatus.imported).length}/${task.imageResults.length}',
              ),
              if (task.imageResults.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('结果项', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                ...task.imageResults.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ImageResultTile(item: item),
                  ),
                ),
              ],
            ],
            if (!isImage) ...[
              _DetailBlock(
                label: '结果文件',
                value: task.localFileName ?? (task.videoUrl ?? '暂无'),
                copyValue: task.localFileName ?? task.videoUrl,
              ),
              if (task.videoUrl != null)
                _DetailBlock(
                  label: '结果 URL',
                  value: task.videoUrl!,
                  copyValue: task.videoUrl,
                ),
            ],
            _DetailBlock(
              label: 'Prompt',
              value: task.prompt,
              copyValue: task.prompt,
            ),
            if (task.attachments.isNotEmpty)
              _DetailBlock(
                label: '本次素材',
                value: task.attachments
                    .map((item) => '${item.label} · ${item.category}')
                    .join('\n'),
              ),
            _JsonBlock(label: '请求入参', value: task.requestPreview),
            _JsonBlock(label: '任务响应', value: task.responsePreview),
          ],
        );
      },
    );
  }

  Color _toneForTask(BuildContext context, TaskStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case TaskStatus.submitted:
        return scheme.tertiary;
      case TaskStatus.inProgress:
        return scheme.primary;
      case TaskStatus.success:
        return Colors.green.shade700;
      case TaskStatus.failure:
        return scheme.error;
    }
  }

  bool _isActive(TaskRecord task) {
    return task.status == TaskStatus.submitted ||
        task.status == TaskStatus.inProgress;
  }

  static String _modeLabel(ModeId mode) {
    switch (mode) {
      case ModeId.text:
        return '文本生视频';
      case ModeId.firstFrame:
        return '首帧图生视频';
      case ModeId.firstLast:
        return '首尾帧视频';
      case ModeId.reference:
        return '参考素材生成';
    }
  }

  static String _imageModeLabel(ImageCreateMode? mode) {
    switch (mode ?? ImageCreateMode.textToImage) {
      case ImageCreateMode.textToImage:
        return '文生图';
      case ImageCreateMode.imageToImage:
        return '图生图';
    }
  }

  static String _statusLabel(TaskStatus status) {
    switch (status) {
      case TaskStatus.submitted:
        return '已提交';
      case TaskStatus.inProgress:
        return '生成中';
      case TaskStatus.success:
        return '已完成';
      case TaskStatus.failure:
        return '失败';
    }
  }

  static String _pollingLabel(PollingStatus status) {
    switch (status) {
      case PollingStatus.idle:
        return '空闲';
      case PollingStatus.polling:
        return '轮询中';
      case PollingStatus.paused:
        return '已暂停';
      case PollingStatus.error:
        return '异常';
    }
  }

  static String _downloadLabel(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.idle:
        return '未下载';
      case DownloadStatus.downloading:
        return '下载中';
      case DownloadStatus.success:
        return '已下载';
      case DownloadStatus.error:
        return '下载失败';
    }
  }

  static String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  static IconData _iconForAttachment(AttachmentKind kind) {
    switch (kind) {
      case AttachmentKind.image:
        return Icons.image_outlined;
      case AttachmentKind.video:
        return Icons.movie_outlined;
      case AttachmentKind.audio:
        return Icons.graphic_eq_outlined;
    }
  }
}

class _TaskEmptyState extends StatelessWidget {
  const _TaskEmptyState({required this.activeTab});

  final TaskTab activeTab;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final isImage = activeTab == TaskTab.image;
    return UtilityPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isImage ? '还没有图片任务' : '还没有视频任务',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            isImage ? '去图片创作提交第一张图，结果和入库进度会回到这里。' : '去创作页提交第一个视频任务，进度和结果会回到这里。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              CapsuleButton(
                label: isImage ? '去图片创作' : '去视频创作',
                icon: isImage
                    ? Icons.auto_awesome_outlined
                    : Icons.movie_creation_outlined,
                emphasized: true,
                onPressed: () {
                  state.setCurrentTab(AppTab.create);
                  if (isImage) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ImageCreatePage(),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label, this.tone});

  final IconData icon;
  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final effectiveTone =
        tone ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: effectiveTone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: effectiveTone),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: effectiveTone),
          ),
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.task});

  final TaskRecord task;

  @override
  Widget build(BuildContext context) {
    final helper = const TasksPage();
    final mediaUrl = task.localResourceUri ?? task.videoUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('结果', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 10),
        if (mediaUrl != null && mediaUrl.trim().isNotEmpty) ...[
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => helper._openMedia(context, task),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: double.infinity,
                height: 180,
                child: _TaskVideoPreview(
                  url: mediaUrl,
                  label: task.localFileName ?? '视频结果',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                task.localFileName ?? task.videoUrl ?? '暂无结果文件',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (task.videoUrl != null)
              ToolIconButton(
                tooltip: '复制 URL',
                icon: Icons.content_copy_rounded,
                onPressed: () =>
                    helper._copyText(context, task.videoUrl!, '结果 URL'),
              ),
          ],
        ),
        if (task.videoUrl != null) ...[
          const SizedBox(height: 8),
          Text(
            task.videoUrl!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.label,
    required this.value,
    this.copyValue,
  });

  final String label;
  final String value;
  final String? copyValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              if (copyValue != null && copyValue!.trim().isNotEmpty)
                ToolIconButton(
                  tooltip: '复制',
                  icon: Icons.content_copy_rounded,
                  onPressed: () => copyToClipboard(
                    context,
                    text: copyValue!,
                    message: '已复制$label',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _JsonBlock extends StatefulWidget {
  const _JsonBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  State<_JsonBlock> createState() => _JsonBlockState();
}

class _JsonBlockState extends State<_JsonBlock> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              ToolIconButton(
                tooltip: _expanded ? '折叠' : '展开',
                icon: _expanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
              const SizedBox(width: 6),
              ToolIconButton(
                tooltip: '复制',
                icon: Icons.content_copy_rounded,
                onPressed: () => copyToClipboard(
                  context,
                  text: widget.value,
                  message: '已复制${widget.label}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                widget.value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PollLogPanel extends StatelessWidget {
  const _PollLogPanel({required this.logs});

  final List<TaskPollLog> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          '暂无轮询日志，下一次自动或手动刷新后会记录。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('最近轮询日志', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          ...logs.map((log) => _PollLogTile(log: log)),
        ],
      ),
    );
  }
}

class _PollLogTile extends StatelessWidget {
  const _PollLogTile({required this.log});

  final TaskPollLog log;

  @override
  Widget build(BuildContext context) {
    final tone = log.success
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      dense: true,
      leading: Icon(
        log.success ? Icons.check_circle_outline_rounded : Icons.error_outline,
        color: tone,
        size: 18,
      ),
      title: Text(
        log.summary,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      subtitle: Text(
        TasksPage._formatDateTime(log.createdAt),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        _JsonBlock(label: '请求', value: log.requestPreview),
        const SizedBox(height: 10),
        _JsonBlock(label: '响应', value: log.responsePreview),
      ],
    );
  }
}

class _TaskActionBar extends StatelessWidget {
  const _TaskActionBar({required this.task});

  final TaskRecord task;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final helper = const TasksPage();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.status != TaskStatus.success) ...[
          _PrimaryTaskButton(task: task),
          const SizedBox(width: 8),
        ],
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) async {
              switch (value) {
                case 'detail':
                  await helper._openTaskDetail(context, task);
                  return;
                case 'refresh':
                  final refreshed = await state.refreshTask(task.id);
                  if (!context.mounted) return;
                  if (!refreshed) {
                    helper._showToast(context, '刷新失败，请查看失败原因');
                  }
                  return;
                case 'toggle':
                  state.toggleTaskPolling(task.id);
                  return;
                case 'copy':
                  state.copyTaskToCreate(task.id);
                  return;
                case 'retry':
                  await helper._confirmRetry(context, state, task);
                  return;
                case 'download':
                  await helper._downloadResult(context, state, task);
                  return;
                case 'copy_id':
                  await helper._copyTaskId(context, task.id);
                  return;
                case 'copy_url':
                  if (task.videoUrl != null) {
                    await helper._copyText(context, task.videoUrl!, '结果 URL');
                  }
                  return;
                case 'delete':
                  await helper._confirmDeleteTask(context, state, task);
                  return;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'detail', child: Text('查看详情')),
              const PopupMenuItem(value: 'refresh', child: Text('手动刷新')),
              if (task.status == TaskStatus.submitted ||
                  task.status == TaskStatus.inProgress)
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(
                    task.pollingStatus == PollingStatus.polling
                        ? '暂停轮询'
                        : '继续轮询',
                  ),
                ),
              if (task.status == TaskStatus.failure)
                const PopupMenuItem(value: 'retry', child: Text('重新提交')),
              if (task.status == TaskStatus.success)
                const PopupMenuItem(value: 'download', child: Text('下载结果')),
              if (task.videoUrl != null)
                const PopupMenuItem(value: 'copy_url', child: Text('复制结果 URL')),
              const PopupMenuItem(value: 'copy', child: Text('复制到创作')),
              const PopupMenuItem(value: 'copy_id', child: Text('复制任务号')),
              const PopupMenuItem(value: 'delete', child: Text('删除任务')),
            ],
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.more_horiz_rounded, size: 19),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryTaskButton extends StatelessWidget {
  const _PrimaryTaskButton({required this.task});

  final TaskRecord task;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final helper = const TasksPage();

    switch (task.status) {
      case TaskStatus.submitted:
      case TaskStatus.inProgress:
        return ToolIconButton(
          tooltip: '手动刷新',
          icon: Icons.refresh_rounded,
          onPressed: () => state.refreshTask(task.id),
        );
      case TaskStatus.success:
        return const SizedBox.shrink();
      case TaskStatus.failure:
        return ToolIconButton(
          tooltip: '重新提交',
          icon: Icons.refresh_rounded,
          emphasized: true,
          onPressed: () {
            helper._confirmRetry(context, state, task);
          },
        );
    }
  }
}

class _VideoTaskCard extends StatelessWidget {
  const _VideoTaskCard({required this.task});

  final TaskRecord task;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tone = TasksPage()._toneForTask(context, task.status);
    final active = TasksPage()._isActive(task);
    final logsExpanded = state.expandedPollLogTaskIds.contains(task.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(TasksPage._modeLabel(task.mode)),
        UtilityPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.prompt,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MetaPill(
                              icon: Icons.schedule_rounded,
                              label:
                                  '创建 ${TasksPage._formatDateTime(task.createdAt)}',
                            ),
                            _MetaPill(
                              icon: Icons.update_rounded,
                              label:
                                  '更新 ${TasksPage._formatDateTime(task.updatedAt)}',
                            ),
                            if (task.hasAnomaly)
                              _MetaPill(
                                icon: Icons.warning_amber_rounded,
                                label: '异常',
                                tone: Theme.of(context).colorScheme.error,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  StatusPill(
                    label: TasksPage._statusLabel(task.status),
                    tone: tone,
                    busy: active,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.id,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  _TaskActionBar(task: task),
                ],
              ),
              const SizedBox(height: 10),
              UtilityTile(
                title: '状态详情',
                subtitle: task.statusDetail ?? '等待更新',
                trailing: ToolIconButton(
                  tooltip: logsExpanded ? '收起轮询日志' : '查看轮询日志',
                  icon: logsExpanded
                      ? Icons.article_rounded
                      : Icons.article_outlined,
                  onPressed: () => state.toggleTaskPollLogs(task.id),
                ),
              ),
              if (task.hasAnomaly) ...[
                const PanelDivider(),
                UtilityTile(
                  title: '异常标识',
                  subtitle: task.anomalyMessage ?? '上游结果异常，可手动刷新',
                  trailing: Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error,
                    size: 18,
                  ),
                ),
              ],
              if (task.downloadStatus == DownloadStatus.downloading) ...[
                const PanelDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '下载中 ${task.downloadProgress}%',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: task.downloadProgress <= 0
                            ? null
                            : task.downloadProgress / 100,
                      ),
                    ],
                  ),
                ),
              ],
              if (task.videoUrl != null || task.localResourceUri != null) ...[
                const PanelDivider(),
                const SizedBox(height: 12),
                _ResultPanel(task: task),
              ],
              if (logsExpanded) ...[
                const PanelDivider(),
                _PollLogPanel(logs: task.pollLogs),
              ],
              if (task.lastError != null) ...[
                const PanelDivider(),
                UtilityTile(
                  title: '失败原因',
                  subtitle: task.lastError!,
                  trailing: Icon(
                    Icons.error_outline_rounded,
                    color: tone,
                    size: 18,
                  ),
                ),
              ],
              if (task.attachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: task.attachments
                      .map(
                        (attachment) => InputChip(
                          label: Text(attachment.label),
                          avatar: Icon(
                            TasksPage._iconForAttachment(attachment.kind),
                            size: 16,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ImageTaskCard extends StatelessWidget {
  const _ImageTaskCard({required this.task});

  final TaskRecord task;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tone = TasksPage()._toneForTask(context, task.status);
    final active = TasksPage()._isActive(task);
    final logsExpanded = state.expandedPollLogTaskIds.contains(task.id);
    final previewItems = task.imageResults
        .map((item) => _TaskImagePreviewData.fromResult(state, item))
        .whereType<_TaskImagePreviewData>()
        .toList();
    final imported = task.imageResults
        .where((r) => r.status == ImageResultStatus.imported)
        .length;
    final failed = task.imageResults
        .where(
          (r) =>
              r.status == ImageResultStatus.downloadFailed ||
              r.status == ImageResultStatus.uploadFailed,
        )
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(TasksPage._imageModeLabel(task.imageMode)),
        UtilityPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.prompt,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MetaPill(
                              icon: Icons.schedule_rounded,
                              label:
                                  '创建 ${TasksPage._formatDateTime(task.createdAt)}',
                            ),
                            _MetaPill(
                              icon: Icons.update_rounded,
                              label:
                                  '更新 ${TasksPage._formatDateTime(task.updatedAt)}',
                            ),
                            _MetaPill(
                              icon: Icons.image_outlined,
                              label: '${task.imageResults.length} 张',
                            ),
                            _MetaPill(
                              icon: Icons.check_circle_outline_rounded,
                              label:
                                  '已入库 $imported/${task.imageResults.length}',
                            ),
                            if (failed > 0)
                              _MetaPill(
                                icon: Icons.error_outline_rounded,
                                label: '$failed 失败',
                                tone: Theme.of(context).colorScheme.error,
                              ),
                            if (task.hasAnomaly)
                              _MetaPill(
                                icon: Icons.warning_amber_rounded,
                                label: '异常',
                                tone: Theme.of(context).colorScheme.error,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  StatusPill(
                    label: TasksPage._statusLabel(task.status),
                    tone: tone,
                    busy: active,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.id,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  _ImageTaskActionBar(task: task),
                ],
              ),
              const SizedBox(height: 10),
              UtilityTile(
                title: '状态详情',
                subtitle: task.statusDetail ?? '等待更新',
                trailing: ToolIconButton(
                  tooltip: logsExpanded ? '收起轮询日志' : '查看轮询日志',
                  icon: logsExpanded
                      ? Icons.article_rounded
                      : Icons.article_outlined,
                  onPressed: () => state.toggleTaskPollLogs(task.id),
                ),
              ),
              if (task.hasAnomaly) ...[
                const PanelDivider(),
                UtilityTile(
                  title: '异常标识',
                  subtitle: task.anomalyMessage ?? '上游结果异常，可手动刷新',
                  trailing: Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error,
                    size: 18,
                  ),
                ),
              ],
              if (task.imageResults.isNotEmpty) ...[
                const PanelDivider(),
                const SizedBox(height: 12),
                if (previewItems.isNotEmpty) ...[
                  Text('结果预览', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 112,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: previewItems.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) => _TaskImagePreviewCard(
                        taskId: task.id,
                        item: previewItems[index],
                        allItems: previewItems,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ...task.imageResults.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ImageResultTile(item: item),
                  ),
                ),
              ],
              if (logsExpanded) ...[
                const PanelDivider(),
                _PollLogPanel(logs: task.pollLogs),
              ],
              if (task.lastError != null) ...[
                const PanelDivider(),
                UtilityTile(
                  title: '失败原因',
                  subtitle: task.lastError!,
                  trailing: Icon(
                    Icons.error_outline_rounded,
                    color: tone,
                    size: 18,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskVideoPreview extends StatefulWidget {
  const _TaskVideoPreview({required this.url, required this.label});

  final String url;
  final String label;

  @override
  State<_TaskVideoPreview> createState() => _TaskVideoPreviewState();
}

class _TaskVideoPreviewState extends State<_TaskVideoPreview> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize()
          .then((_) {
            if (!mounted) return;
            setState(() {
              _ready = true;
            });
          })
          .catchError((_) {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.play_circle_outline_rounded,
            size: 42,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x22000000), Color(0x8A000000)],
            ),
          ),
        ),
        const Center(
          child: Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.white,
            size: 44,
          ),
        ),
      ],
    );
  }
}

class _ImageResultTile extends StatelessWidget {
  const _ImageResultTile({required this.item});

  final ImageTaskResultItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (item.status) {
      ImageResultStatus.queued => ('等待生成', scheme.onSurfaceVariant),
      ImageResultStatus.generating => ('生成中', scheme.tertiary),
      ImageResultStatus.readyToTransfer => ('待转存', scheme.tertiary),
      ImageResultStatus.downloading => ('下载中', scheme.primary),
      ImageResultStatus.downloadFailed => ('下载失败', scheme.error),
      ImageResultStatus.uploading => ('上传中', scheme.primary),
      ImageResultStatus.uploadFailed => ('上传失败', scheme.error),
      ImageResultStatus.imported => ('已入库', Colors.green.shade700),
    };

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        if (item.lastError != null)
          Flexible(
            child: Text(
              item.lastError!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.red),
            ),
          ),
      ],
    );
  }
}

class _TaskImagePreviewData {
  const _TaskImagePreviewData({
    required this.id,
    required this.url,
    required this.label,
    required this.source,
    this.attachment,
  });

  final String id;
  final String url;
  final String label;
  final String source;
  final Attachment? attachment;

  static _TaskImagePreviewData? fromResult(
    AppState state,
    ImageTaskResultItem item,
  ) {
    final attachment = state.attachmentById(item.attachmentId);
    final source = attachment != null ? '已入库' : '远程结果';
    final url = attachment?.url ?? item.storageUrl ?? item.remoteUrl;
    if (url == null || url.trim().isEmpty) return null;
    return _TaskImagePreviewData(
      id: item.id,
      url: url,
      label: attachment?.label ?? '结果图',
      source: source,
      attachment: attachment,
    );
  }
}

class _TaskImagePreviewCard extends StatelessWidget {
  const _TaskImagePreviewCard({
    required this.taskId,
    required this.item,
    required this.allItems,
  });

  final String taskId;
  final _TaskImagePreviewData item;
  final List<_TaskImagePreviewData> allItems;

  @override
  Widget build(BuildContext context) {
    final previewAttachments = allItems
        .map(
          (entry) =>
              entry.attachment ??
              Attachment(
                id: 'task-preview-$taskId-${entry.id}',
                label: entry.label,
                role: AttachmentRole.referenceImage,
                kind: AttachmentKind.image,
                fileName: entry.label,
                category: entry.source,
                createdAt: DateTime.now(),
                status: AttachmentStatus.uploaded,
                url: entry.url,
              ),
        )
        .toList();
    final previewAttachment =
        item.attachment ??
        Attachment(
          id: 'task-preview-$taskId-${item.id}',
          label: item.label,
          role: AttachmentRole.referenceImage,
          kind: AttachmentKind.image,
          fileName: item.label,
          category: item.source,
          createdAt: DateTime.now(),
          status: AttachmentStatus.uploaded,
          url: item.url,
        );

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => showAttachmentPreviewSheet(
        context,
        previewAttachment,
        attachments: previewAttachments,
      ),
      child: SizedBox(
        width: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AttachmentThumb(
                attachment: previewAttachment,
                width: 112,
                height: 84,
                radius: 18,
                overlayLabel: item.label,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageTaskActionBar extends StatelessWidget {
  const _ImageTaskActionBar({required this.task});

  final TaskRecord task;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final helper = const TasksPage();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.status != TaskStatus.success) ...[
          _PrimaryTaskButton(task: task),
          const SizedBox(width: 8),
        ],
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) async {
              switch (value) {
                case 'detail':
                  await helper._openTaskDetail(context, task);
                case 'refresh':
                  final refreshed = await state.refreshImageTask(task.id);
                  if (!context.mounted) return;
                  if (!refreshed) {
                    helper._showToast(context, '刷新失败，请查看失败原因');
                  }
                case 'copy':
                  state.copyImageTaskToCreate(task.id);
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ImageCreatePage()),
                  );
                case 'retry':
                  await helper._confirmRetry(context, state, task);
                case 'retryFailedTransfers':
                  await state.retryFailedImageTransfers(task.id);
                  if (!context.mounted) return;
                  helper._showToast(context, '已开始重试失败项');
                case 'copy_id':
                  await helper._copyTaskId(context, task.id);
                case 'delete':
                  await helper._confirmDeleteTask(context, state, task);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'detail', child: Text('查看详情')),
              const PopupMenuItem(value: 'refresh', child: Text('手动刷新')),
              const PopupMenuItem(value: 'copy', child: Text('复制到图片创作')),
              if (task.status == TaskStatus.failure)
                const PopupMenuItem(value: 'retry', child: Text('重新生成')),
              if (task.imageResults.any(
                (r) =>
                    r.status == ImageResultStatus.downloadFailed ||
                    r.status == ImageResultStatus.uploadFailed,
              ))
                const PopupMenuItem(
                  value: 'retryFailedTransfers',
                  child: Text('重试失败项'),
                ),
              const PopupMenuItem(value: 'copy_id', child: Text('复制任务号')),
              const PopupMenuItem(value: 'delete', child: Text('删除任务')),
            ],
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.more_horiz_rounded, size: 19),
            ),
          ),
        ),
      ],
    );
  }
}
