import 'package:flutter/material.dart';
import '../app/spacing.dart';

import '../app/app_scope.dart';
import '../app/mock_data.dart';
import 'home_shell.dart';

class CategoryManagementPage extends StatelessWidget {
  const CategoryManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Row(
                children: [
                  ToolIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '分类管理',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '预置分类可以继续用，也支持新增、改名和长按删除。删除后，已关联素材会自动回到未分类。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SectionLabel('操作'),
              UtilityPanel(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '当前共 ${state.categories.length} 个分类，未分类素材 ${state.attachmentCountForCategory(uncategorizedCategory)} 个。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Semantics(
                      button: true,
                      label: '新增分类',
                      child: CapsuleButton(
                        label: '新增分类',
                        icon: Icons.add_rounded,
                        emphasized: true,
                        onPressed: () => _openCategoryEditor(
                          context,
                          title: '新增分类',
                          onSubmit: (value) {
                            final success = state.addCategory(value);
                            _showResult(
                              context,
                              success ? '分类已添加' : '分类名为空或已存在',
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionLabel('分类列表'),
              UtilityPanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    ...state.categories.map(
                      (category) => Column(
                        children: [
                          _CategoryTile(category: category),
                          const PanelDivider(),
                        ],
                      ),
                    ),
                    _ReadonlyCategoryTile(
                      title: uncategorizedCategoryLabel,
                      subtitle:
                          '${state.attachmentCountForCategory(uncategorizedCategory)} 个素材等待归类',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _openCategoryEditor(
    BuildContext context, {
    required String title,
    String initialValue = '',
    required ValueChanged<String> onSubmit,
  }) async {
    final controller = TextEditingController(text: initialValue);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                '分类名会同时用于素材筛选和素材标记。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '分类名',
                  hintText: '例如：服装、品牌、机位',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  onSubmit(controller.text);
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CapsuleButton(
                      label: '取消',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CapsuleButton(
                      label: '保存',
                      icon: Icons.check_rounded,
                      emphasized: true,
                      onPressed: () {
                        onSubmit(controller.text);
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static void _showResult(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final count = state.attachmentCountForCategory(category);
    return Semantics(
      button: true,
      label: '分类 $category，点按编辑，长按删除',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => CategoryManagementPage._openCategoryEditor(
          context,
          title: '修改分类',
          initialValue: category,
          onSubmit: (value) {
            final success = state.renameCategory(category, value);
            CategoryManagementPage._showResult(
              context,
              success ? '分类已更新' : '分类名为空、未变化或已存在',
            );
          },
        ),
        onLongPress: () async {
          final confirmed = await confirmAction(
            context,
            title: '删除分类？',
            message: '删除后，关联到「$category」的素材会自动变成未分类。',
            confirmLabel: '删除',
            destructive: true,
          );
          if (!confirmed) return;
          state.deleteCategory(category);
          if (!context.mounted) return;
          CategoryManagementPage._showResult(context, '分类已删除');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$count 个素材',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '$count',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              const Icon(Icons.edit_outlined, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadonlyCategoryTile extends StatelessWidget {
  const _ReadonlyCategoryTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Icon(
            Icons.label_outline_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
