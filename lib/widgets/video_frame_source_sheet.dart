import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/models.dart';
import '../pages/home_shell.dart';

Future<VideoFrameSource?> showVideoSourceSheet({
  required BuildContext context,
  required AppState state,
  required String title,
  required String subtitle,
}) {
  return showModalBottomSheet<VideoFrameSource>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => _VideoSourceSheet(
      state: state,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class _VideoSourceSheet extends StatelessWidget {
  const _VideoSourceSheet({
    required this.state,
    required this.title,
    required this.subtitle,
  });

  final AppState state;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final videoAttachments = state.uploadedLibrary
        .where((item) => item.kind == AttachmentKind.video)
        .take(8)
        .toList();
    final recentSources = state.visibleRecentVideoSources;
    final recentTasks = state.tasks
        .where(
          (task) =>
              task.kind == TaskKind.video &&
              (task.localResourceUri?.trim().isNotEmpty == true ||
                  task.videoUrl?.trim().isNotEmpty == true),
        )
        .take(8)
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            UtilityPanel(
              child: UtilityTile(
                title: '本地视频',
                subtitle: '从设备里选一段视频，直接进入截帧页面。',
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final picked = await state.pickLocalVideoSource();
                  if (!context.mounted || picked == null) return;
                  Navigator.of(context).pop(
                    VideoFrameSource(
                      type: VideoFrameSourceType.localFile,
                      label: picked.name,
                      sourceUri: picked.path?.trim().isNotEmpty == true
                          ? picked.path!
                          : picked.uri,
                      fileName: picked.name,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Text('最近使用视频', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            if (recentSources.isEmpty)
              _EmptySourceHint(
                title: '还没有最近使用的视频',
                message: '选过一次本地视频、云端视频或任务结果后，这里会保留最近可继续截帧的视频来源。',
              )
            else
              ...recentSources.map(
                (source) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: UtilityPanel(
                    child: UtilityTile(
                      title: source.label,
                      subtitle: _recentSourceSubtitle(source),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(context).pop(source.toVideoFrameSource());
                      },
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Text('云端素材库视频', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            if (videoAttachments.isEmpty)
              _EmptySourceHint(
                title: '暂无可用视频素材',
                message: '这里只有已上传的视频素材。上传截帧图片不会出现在这里；你也可以直接从“最近使用视频”继续截。',
                actionLabel: '去素材库',
                onTap: () {
                  Navigator.of(context).pop();
                  state.setCurrentTab(AppTab.library);
                },
              )
            else
              ...videoAttachments.map(
                (attachment) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: UtilityPanel(
                    child: UtilityTile(
                      title: attachment.label,
                      subtitle: attachment.localStatus == AttachmentLocalStatus.ready
                          ? '本地可直接截帧'
                          : '需要先下载到本地',
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        var ready =
                            attachment.localStatus == AttachmentLocalStatus.ready;
                        if (!ready) {
                          final confirmed = await confirmAction(
                            context,
                            title: '需要先下载视频',
                            message:
                                '该视频当前只有云端版本，截帧前需要先下载到本地。是否现在下载？',
                            confirmLabel: '下载并继续',
                          );
                          if (!confirmed || !context.mounted) return;
                          ready = await state.ensureAttachmentVideoLocal(
                            attachment.id,
                          );
                        }
                        if (!context.mounted || !ready) return;
                        final refreshed = state.attachmentById(attachment.id);
                        final localUri = refreshed?.localResourceUri?.trim() ?? '';
                        if (localUri.isEmpty) return;
                        Navigator.of(context).pop(
                          VideoFrameSource(
                            type: VideoFrameSourceType.attachment,
                            label: refreshed?.label ?? attachment.label,
                            sourceUri: localUri,
                            attachmentId: attachment.id,
                            fileName:
                                refreshed?.localFileName ?? attachment.fileName,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Text('最近任务结果', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            if (recentTasks.isEmpty)
              _EmptySourceHint(
                title: '暂无可用任务结果',
                message: '生成完成后，这里会自动出现最近可截帧的视频结果。',
              )
            else
              ...recentTasks.map(
                (task) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: UtilityPanel(
                    child: UtilityTile(
                      title: task.localFileName ?? task.videoUrl ?? '任务结果视频',
                      subtitle: task.localResourceUri?.trim().isNotEmpty == true
                          ? '本地可直接截帧'
                          : '需要先下载到本地',
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        var ready =
                            task.localResourceUri?.trim().isNotEmpty == true;
                        if (!ready) {
                          final confirmed = await confirmAction(
                            context,
                            title: '需要先下载视频',
                            message:
                                '该结果视频尚未落地到本地，截帧前需要先下载。是否现在下载？',
                            confirmLabel: '下载并继续',
                          );
                          if (!confirmed || !context.mounted) return;
                          ready = await state.ensureTaskVideoLocal(task.id);
                        }
                        if (!context.mounted || !ready) return;
                        final refreshed = state.tasks.firstWhere(
                          (item) => item.id == task.id,
                        );
                        final localUri = refreshed.localResourceUri?.trim() ?? '';
                        if (localUri.isEmpty) return;
                        Navigator.of(context).pop(
                          VideoFrameSource(
                            type: VideoFrameSourceType.task,
                            label:
                                refreshed.localFileName ??
                                refreshed.videoUrl ??
                                '任务结果视频',
                            sourceUri: localUri,
                            taskId: task.id,
                            fileName: refreshed.localFileName,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _recentSourceSubtitle(RecentVideoSource source) {
  switch (source.type) {
    case VideoFrameSourceType.localFile:
      return '来自系统相册/本地视频';
    case VideoFrameSourceType.attachment:
      return '来自云端素材库视频';
    case VideoFrameSourceType.task:
      return '来自最近任务结果视频';
  }
}

class _EmptySourceHint extends StatelessWidget {
  const _EmptySourceHint({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onTap,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return UtilityPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.video_library_outlined,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (actionLabel != null && onTap != null) ...[
            const SizedBox(width: 10),
            CapsuleButton(
              label: actionLabel!,
              icon: Icons.chevron_right_rounded,
              emphasized: false,
              onPressed: onTap,
            ),
          ],
        ],
      ),
    );
  }
}
