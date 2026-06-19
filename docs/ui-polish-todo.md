# UI Polish 待办清单

分支：`codex/ui-polish`（已提交推送，commit `9182a36`）

## Bug 修复（优先）

### 1. 图片 prompt 限制前后矛盾
- `lib/app/app_state.dart:1508` 检查 `imagePrompt.length > 2000`，但下一行错误提示写的是"Prompt 不能超过 5000 字符"
- `lib/pages/image_create_page.dart:120` 计数器显示 `/2000`
- 三处对不上。需先确认 gpt image 2 实际限制，再统一改一致

### 2. 悬浮提交按钮可能遮挡 prompt 右下角
- `lib/pages/create_page.dart` 与 `lib/pages/image_create_page.dart` 中，键盘弹出时 `FloatingSubmitBar` 定位 `right: 20, bottom: viewInsets.bottom + 12`
- 与 prompt 输入框右下角字符计数器（`right: 12, bottom: 8`）可能重叠，挡住该区域文字选择
- 需给 prompt 输入区域底部加 padding，或键盘弹出时按钮换位

## 重构

### 3. 抽取共享 TaskCardShell
- `lib/pages/tasks_page.dart` 中 `_VideoTaskCard`（约 1177 行）和 `_ImageTaskCard`（约 1319 行）外壳结构大量重复
- 共同结构：`Column > SectionLabel + UtilityPanel > Column`，头部行（prompt + metaRow + pills + StatusPill），ID 行（id + actionBar），条件块（日志/lastError/引用素材）
- 三处不同点作为可变插槽传入：
  - 标题标签来源（`_modeLabel` vs `_imageModeLabel`）
  - 异常 pill（单个 vs 失败数+异常 Wrap）
  - 结果区（视频下载进度+ResultPanel vs 图片横向预览列表）

## UI 改造（苹果原生质感）

### 4. 底部 tab 栏改为苹果风
- 当前 `lib/pages/home_shell.dart` 的 `_BottomDock`（约 689 行）用的是 Material 3 `NavigationBar`，外面包了圆角卡片 + 边框 + elevation
- 要改成苹果原生质感：贴近底部的毛玻璃/半透明背景，不要圆角卡片包裹，分隔线更细，选中态用填充药丸或柔和高亮，图标和文字间距更紧凑
- 参考 iOS TabBar 的视觉：全宽贴底、薄背景模糊、选中色用主题色、无卡片阴影

## 清理

### 5. 删除未使用的 dropdown_button2 依赖
- `pubspec.yaml` 有 `dropdown_button2: ^3.1.0`，全项目无任何 import，应删掉

## 已完成（本次提交）

- 设计系统基础：`AppSpacing`/`AppRadius` token（`lib/app/spacing.dart`）
- 主题升级：Indigo 主色 `#5856F6`，按钮/输入框/卡片主题，FlexColorScheme
- 自定义 `AppDropdownField`（PopupMenuButton，菜单宽度匹配触发器）
- prompt 字符计数：视频 5000 / 图片 2000，右下角显示
- 任务提交时自动切换 tab + 重置归档视图（`app_state.dart:1440/1586`）
- 存储提供商左对齐 + 全宽 SegmentedButton
- "更多筛选"行：标签与箭头合并为单一可点击单元（左侧），清空按钮右侧
- 各页面设计语言统一（剪辑页、设置页、创建页、图片创建页、素材库页等）

## 备注

- 不再截图，用户自行在设备上验证
- Flutter SDK 路径：`/Users/jbrains/dev/flutter-sdk/bin/flutter`（不在 PATH）
- 不要提交 `.claude/` 目录
- iOS 模拟器不支持 `ffmpeg_kit_flutter_new`（arm64），等有线再真机调试
- 最新 release APK 在 `build/app/outputs/flutter-apk/`，版本 `1.0.2+2003`
