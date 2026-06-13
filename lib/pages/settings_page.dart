import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

import '../app/app_scope.dart';
import '../app/models.dart';
import 'home_shell.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool showAgentEarthKey = false;
  bool showQiniuAccessKey = false;
  bool showQiniuSecretKey = false;
  bool showBitifulAccessKey = false;
  bool showBitifulSecretKey = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return AppPageScaffold(
      eyebrow: 'Config',
      title: '设置',
      subtitle: '把账号、存储和默认偏好收在一处，保持日常配置足够直接。',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
        children: [
          SectionLabel('接口配置'),
          UtilityPanel(
            child: Column(
              children: [
                _ValueEditorRow(
                  title: 'AgentEarth 接口地址',
                  value: state.settings.agentEarthBaseUrl,
                  onChanged: (value) => state.updateSettings(
                    (current) => current.copyWith(agentEarthBaseUrl: value),
                  ),
                ),
                const PanelDivider(),
                _SecureRow(
                  title: 'AgentEarth API Key',
                  value: state.settings.agentEarthApiKey,
                  reveal: showAgentEarthKey,
                  onRevealChanged: () =>
                      setState(() => showAgentEarthKey = !showAgentEarthKey),
                  onChanged: (value) => state.updateSettings(
                    (current) => current.copyWith(agentEarthApiKey: value),
                  ),
                  action: ToolIconButton(
                    tooltip: '测试 AgentEarth 配置',
                    icon: state.isTestingAgentEarth
                        ? Icons.more_horiz_rounded
                        : Icons.bolt_rounded,
                    onPressed: state.isTestingAgentEarth
                        ? null
                        : () => _runAndToast(
                            context,
                            state.testAgentEarthConfig(),
                          ),
                  ),
                ),
                const PanelDivider(),
                const PanelDivider(),
                _StorageProviderRow(
                  value: state.currentStorageProvider,
                  onChanged: (value) => state.updateSettings(
                    (current) => current.copyWith(storageProvider: value),
                  ),
                ),
                const SizedBox(height: 14),
                _ProviderConfigHeader(provider: state.currentStorageProvider),
                const SizedBox(height: 12),
                _ProviderConfigPanel(
                  child: state.currentStorageProvider == StorageProvider.qiniu
                      ? Column(
                          children: [
                            _SecureRow(
                              title: '七牛 AccessKey',
                              value: state.settings.qiniuAccessKey,
                              reveal: showQiniuAccessKey,
                              onRevealChanged: () => setState(
                                () => showQiniuAccessKey = !showQiniuAccessKey,
                              ),
                              onChanged: (value) => state.updateSettings(
                                (current) =>
                                    current.copyWith(qiniuAccessKey: value),
                              ),
                            ),
                            const PanelDivider(),
                            _SecureRow(
                              title: '七牛 SecretKey',
                              value: state.settings.qiniuSecretKey,
                              reveal: showQiniuSecretKey,
                              onRevealChanged: () => setState(
                                () => showQiniuSecretKey = !showQiniuSecretKey,
                              ),
                              onChanged: (value) => state.updateSettings(
                                (current) =>
                                    current.copyWith(qiniuSecretKey: value),
                              ),
                            ),
                            const PanelDivider(),
                            _BucketEditorRow(
                              title: 'Bucket',
                              value: state.settings.qiniuBucket,
                              options: state.bucketOptions,
                              placeholder: '请选择或填写',
                              onChanged: (value) => state.updateSettings(
                                (current) =>
                                    current.copyWith(qiniuBucket: value),
                              ),
                              action: ToolIconButton(
                                tooltip: '拉取七牛 Bucket 列表',
                                icon: state.isFetchingBuckets
                                    ? Icons.more_horiz_rounded
                                    : Icons.refresh_rounded,
                                onPressed: state.isFetchingBuckets
                                    ? null
                                    : () => _runAndToast(
                                        context,
                                        state.fetchBucketList(),
                                      ),
                              ),
                            ),
                            const PanelDivider(),
                            _BucketEditorRow(
                              title: '域名',
                              value: state.settings.qiniuDomain,
                              options: state.domainOptions,
                              placeholder: 'http:// 或 https://',
                              onChanged: (value) => state.updateSettings(
                                (current) =>
                                    current.copyWith(qiniuDomain: value),
                              ),
                              action: ToolIconButton(
                                tooltip: '测试七牛配置',
                                icon: state.isTestingQiniu
                                    ? Icons.more_horiz_rounded
                                    : Icons.cloud_done_outlined,
                                onPressed: state.isTestingQiniu
                                    ? null
                                    : () => _runAndToast(
                                        context,
                                        state.testQiniuConfig(),
                                      ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SecureRow(
                              title: '缤纷云 AccessKey',
                              value: state.settings.bitifulAccessKey,
                              reveal: showBitifulAccessKey,
                              onRevealChanged: () => setState(
                                () => showBitifulAccessKey =
                                    !showBitifulAccessKey,
                              ),
                              onChanged: (value) => state.updateSettings(
                                (current) =>
                                    current.copyWith(bitifulAccessKey: value),
                              ),
                            ),
                            const PanelDivider(),
                            _SecureRow(
                              title: '缤纷云 SecretKey',
                              value: state.settings.bitifulSecretKey,
                              reveal: showBitifulSecretKey,
                              onRevealChanged: () => setState(
                                () => showBitifulSecretKey =
                                    !showBitifulSecretKey,
                              ),
                              onChanged: (value) => state.updateSettings(
                                (current) =>
                                    current.copyWith(bitifulSecretKey: value),
                              ),
                            ),
                            const PanelDivider(),
                            _ValueEditorRow(
                              title: 'Bucket',
                              value: state.settings.bitifulBucket,
                              onChanged: (value) => state.updateSettings(
                                (current) =>
                                    current.copyWith(bitifulBucket: value),
                              ),
                            ),
                            const PanelDivider(),
                            _ValueEditorRow(
                              title: 'Endpoint',
                              value: state.settings.bitifulEndpoint,
                              placeholder: 'https://s3.bitiful.net',
                              onChanged: (value) => state.updateSettings(
                                (current) =>
                                    current.copyWith(bitifulEndpoint: value),
                              ),
                            ),
                            const PanelDivider(),
                            _ValueEditorRow(
                              title: 'Region',
                              value: state.settings.bitifulRegion,
                              placeholder: 'cn-east-1',
                              onChanged: (value) => state.updateSettings(
                                (current) =>
                                    current.copyWith(bitifulRegion: value),
                              ),
                            ),
                            const PanelDivider(),
                            _ValueEditorRow(
                              title: '自定义访问域名',
                              value: state.settings.bitifulPublicDomain,
                              placeholder: '可留空，有 CDN 或自定义域名时再填',
                              onChanged: (value) => state.updateSettings(
                                (current) => current.copyWith(
                                  bitifulPublicDomain: value,
                                ),
                              ),
                              action: ToolIconButton(
                                tooltip: '测试缤纷云配置',
                                icon: state.isTestingBitiful
                                    ? Icons.more_horiz_rounded
                                    : Icons.cloud_done_outlined,
                                onPressed: state.isTestingBitiful
                                    ? null
                                    : () => _runAndToast(
                                        context,
                                        state.testBitifulConfig(),
                                      ),
                              ),
                            ),
                          ],
                        ),
                ),
                if (state.currentStorageProvider == StorageProvider.bitifulS4)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(2, 14, 2, 14),
                    child: _SettingsHintCard(
                      message:
                          'Bitiful S4 通常使用默认 Endpoint 和 cn-east-1。自定义访问域名只有在你配置了 CDN 或绑定了自有域名时才需要填写。',
                    ),
                  ),
                const PanelDivider(),
                UtilityTile(
                  title: '配置状态',
                  subtitle: state.configStatusMessage,
                  trailing: Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionLabel('数据备份'),
          UtilityPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UtilityTile(
                  title: '导出本地数据',
                  subtitle: '导出设置、素材、任务和最近使用记录。',
                  trailing: ToolIconButton(
                    tooltip: '导出备份',
                    icon: Icons.ios_share_rounded,
                    onPressed: () => _exportBackup(context),
                  ),
                ),
                const PanelDivider(),
                UtilityTile(
                  title: '导入备份',
                  subtitle: '从 JSON 备份恢复当前应用数据。',
                  trailing: ToolIconButton(
                    tooltip: '导入备份',
                    icon: Icons.file_open_rounded,
                    onPressed: () => _importBackup(context),
                  ),
                ),
                const PanelDivider(),
                UtilityTile(title: '存储说明', subtitle: '敏感配置会在 Android 端加密后再落库。'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionLabel('偏好'),
          UtilityPanel(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动轮询'),
                  subtitle: Text(
                    '视频创作页里的分辨率、比例和时长会自动记住上次选择，这里只保留全局行为开关。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  value: state.settings.autoPoll,
                  onChanged: (value) => state.updateSettings(
                    (current) => current.copyWith(autoPoll: value),
                  ),
                ),
                const PanelDivider(),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动下载'),
                  value: state.settings.autoDownload,
                  onChanged: (value) => state.updateSettings(
                    (current) => current.copyWith(autoDownload: value),
                  ),
                ),
                const PanelDivider(),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('主工具失败时自动尝试备用生图服务'),
                  subtitle: Text(
                    '关闭后会严格使用 GPT Image 2；开启后失败时会尝试兼容服务，结果风格和参数支持可能不同。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  value: state.settings.imageAutoFallbackEnabled,
                  onChanged: (value) => state.updateSettings(
                    (current) =>
                        current.copyWith(imageAutoFallbackEnabled: value),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runAndToast(BuildContext context, Future<bool> future) async {
    await future;
    if (!context.mounted) return;
    final state = AppScope.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(state.configStatusMessage)));
  }

  Future<void> _exportBackup(BuildContext context) async {
    final state = AppScope.of(context);
    final uri = await state.exportBackup();
    if (!context.mounted) return;
    final message = uri == null ? '已取消导出' : '备份已导出';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importBackup(BuildContext context) async {
    final state = AppScope.of(context);
    final imported = await state.importBackup();
    if (!context.mounted) return;
    final message = imported ? '备份已导入' : state.configStatusMessage;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ValueEditorRow extends StatelessWidget {
  const _ValueEditorRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.action,
  });

  final String title;
  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _SettingsInputRow(
      title: title,
      builder: (context, compact) => Row(
        children: [
          Expanded(
            child: TextField(
              controller: TextEditingController(text: value)
                ..selection = TextSelection.collapsed(offset: value.length),
              onChanged: onChanged,
              textAlign: compact ? TextAlign.left : TextAlign.right,
              decoration: InputDecoration(
                hintText: placeholder,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

class _StorageProviderRow extends StatelessWidget {
  const _StorageProviderRow({required this.value, required this.onChanged});

  final StorageProvider value;
  final ValueChanged<StorageProvider> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return _SettingsInputRow(
      title: '存储提供商',
      builder: (context, compact) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: _ProviderSegment(
                label: '七牛云',
                icon: CupertinoIcons.cloud,
                hint: '对象存储',
                selected: value == StorageProvider.qiniu,
                position: _ProviderSegmentPosition.left,
                onTap: () => onChanged(StorageProvider.qiniu),
              ),
            ),
            Expanded(
              child: _ProviderSegment(
                label: '缤纷云 S4',
                icon: CupertinoIcons.layers_alt,
                hint: 'Bitiful 对象存储',
                selected: value == StorageProvider.bitifulS4,
                position: _ProviderSegmentPosition.right,
                onTap: () => onChanged(StorageProvider.bitifulS4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderConfigHeader extends StatelessWidget {
  const _ProviderConfigHeader({required this.provider});

  final StorageProvider provider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isQiniu = provider == StorageProvider.qiniu;
    final icon = isQiniu ? CupertinoIcons.cloud : CupertinoIcons.layers_alt;
    final title = isQiniu ? '七牛云配置' : '缤纷云（Bitiful）S4 配置';
    final subtitle = isQiniu
        ? '适合需要 Bucket 与域名联动管理的素材存储。'
        : '适合统一管理图片、视频和音频，并支持私有空间签名访问。';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isQiniu
                  ? const Color(0xFFE9F2FF)
                  : const Color(0xFFFFF2E8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isQiniu
                  ? const Color(0xFF1570EF)
                  : const Color(0xFFB54708),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderConfigPanel extends StatelessWidget {
  const _ProviderConfigPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: child,
    );
  }
}

enum _ProviderSegmentPosition { left, right }

class _ProviderSegment extends StatelessWidget {
  const _ProviderSegment({
    required this.label,
    required this.icon,
    required this.hint,
    required this.selected,
    required this.position,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String hint;
  final bool selected;
  final _ProviderSegmentPosition position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderRadius = BorderRadius.horizontal(
      left: position == _ProviderSegmentPosition.left
          ? const Radius.circular(16)
          : Radius.zero,
      right: position == _ProviderSegmentPosition.right
          ? const Radius.circular(16)
          : Radius.zero,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary,
                  colorScheme.primary.withValues(alpha: 0.84),
                ],
              )
            : null,
        color: selected ? null : Colors.transparent,
        borderRadius: borderRadius,
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 15,
                      color: selected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: selected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: selected
                        ? colorScheme.onPrimary.withValues(alpha: 0.82)
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BucketEditorRow extends StatelessWidget {
  const _BucketEditorRow({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder,
    this.action,
  });

  final String title;
  final String value;
  final List<String> options;
  final String? placeholder;
  final ValueChanged<String> onChanged;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _SettingsInputRow(
      title: title,
      builder: (context, compact) => Row(
        children: [
          Expanded(
            child: TextField(
              controller: TextEditingController(text: value)
                ..selection = TextSelection.collapsed(offset: value.length),
              onChanged: onChanged,
              textAlign: compact ? TextAlign.left : TextAlign.right,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: placeholder,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          if (options.isNotEmpty) ...[
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: '选择已拉取项',
              onSelected: onChanged,
              itemBuilder: (context) {
                return options
                    .map<PopupMenuEntry<String>>(
                      (item) => PopupMenuItem<String>(
                        value: item,
                        child: Text(
                          item,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList();
              },
              icon: const Icon(Icons.arrow_drop_down_rounded),
            ),
          ],
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

class _SecureRow extends StatelessWidget {
  const _SecureRow({
    required this.title,
    required this.value,
    required this.reveal,
    required this.onRevealChanged,
    required this.onChanged,
    this.action,
  });

  final String title;
  final String value;
  final bool reveal;
  final VoidCallback onRevealChanged;
  final ValueChanged<String> onChanged;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _SettingsInputRow(
      title: title,
      builder: (context, compact) => Row(
        children: [
          Expanded(
            child: TextField(
              controller: TextEditingController(text: value)
                ..selection = TextSelection.collapsed(offset: value.length),
              onChanged: onChanged,
              obscureText: !reveal,
              textAlign: compact ? TextAlign.left : TextAlign.right,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onRevealChanged,
            icon: Icon(
              reveal
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
            ),
          ),
          if (action != null) ...[const SizedBox(width: 4), action!],
        ],
      ),
    );
  }
}

class _SettingsHintCard extends StatelessWidget {
  const _SettingsHintCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.tips_and_updates_outlined,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.45,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsInputRow extends StatelessWidget {
  const _SettingsInputRow({required this.title, required this.builder});

  final String title;
  final Widget Function(BuildContext context, bool compact) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final titleWidget = Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        );
        final input = builder(context, compact);

        if (compact) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleWidget, const SizedBox(height: 12), input],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 4, child: titleWidget),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: input),
            ],
          ),
        );
      },
    );
  }
}
