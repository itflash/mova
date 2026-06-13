# Mova 图片生成入库设计与开发清单

## 1. 背景与目标

`Mova` 的主定位仍然是视频创作工具，现有 [create_page.dart](/Users/jbrains/projects/apps/mova/lib/pages/create_page.dart) 已经完整围绕视频任务构建，包括：

- 视频模式选择
- 视频参数设置
- 视频任务提交
- 视频任务轮询
- 视频结果下载

因此，图片生成能力不建议直接并入现有视频创作页，而应作为“素材生产与入库能力”放入素材库域。

本次设计目标：

- 在素材库中新增 `AI 生图` 入口
- 新增独立的 `图片创作页`
- 接入 AgentEarth 的 `GPT Image 2` 生图能力
- 将第三方返回的图片链接自动下载到本地，再自动上传到七牛或缤纷云
- 自动写入素材库，供视频创作页继续引用
- 在任务页中新增图片任务视图，并尽量复用现有视频任务的信息结构和交互体验

## 2. 设计原则

### 2.1 产品原则

- `创作页` 继续专注视频，不混入图片任务模式
- `素材库` 负责素材导入、管理和 AI 生成入库
- `任务页` 统一承接视频任务和图片任务，但通过 tab 区分

### 2.2 交互原则

- 图片创作页尽量沿用视频创作页的视觉结构和信息密度
- 图片任务尽量保留视频任务已有的信息项
- 只有确实不兼容的视频字段才移除
- 图片特有的“外链转存”和“多图结果项状态”单独增强

### 2.3 技术原则

- 图片任务必须按“异步任务”处理，不能当作同步接口
- 结果图必须转存到自有云存储后再写入素材库
- 多图结果必须支持单图粒度状态管理和异常重试
- 优先复用现有上传、素材库写入和任务展示能力

## 3. AgentEarth 工具策略

### 3.1 主工具

主工具固定优先使用：

- `xl_falai_post_openai_gpt_image_2`

当前已确认的核心入参：

- `prompt` 必填
- `image_size` 可选
- `num_images` 可选，支持 `1-4`
- `output_format` 可选，支持 `jpeg/png/webp`
- `quality` 可选，支持 `low/medium/high`
- `sync_mode` 可选，默认应为 `false`

### 3.2 fallback 工具

备用工具：

- `xl_dumplingai_generate_ai_image`

### 3.3 fallback 策略

不建议第一版直接把 fallback 工具名暴露给普通用户作为创作页参数。

建议做成设置页中的高级策略项：

- `仅使用 GPT Image 2（推荐）`
- `主工具失败时自动尝试备用服务`

第一版最小实现建议：

- 在设置中新增布尔项：`imageAutoFallbackEnabled`
- 默认值：`false`

执行策略：

1. recommend 时优先匹配 `xl_falai_post_openai_gpt_image_2`
2. 主工具不可用或执行失败时，如果 `imageAutoFallbackEnabled == true`，尝试 `xl_dumplingai_generate_ai_image`
3. 任务详情必须记录实际使用的 `toolName`
4. 如果发生 fallback，状态详情中明确写出：
   - `主工具失败，已切换备用服务继续生成`

## 4. 页面与导航设计

## 4.1 素材库页入口

修改 [library_page.dart](/Users/jbrains/projects/apps/mova/lib/pages/library_page.dart) 的“上传与统计”区。

现有按钮：

- `打开相册`

新增按钮：

- `AI 生图`

推荐布局：

- `打开相册`
- `AI 生图`

两个按钮并列展示，风格一致。

点击 `AI 生图` 后跳转独立页面：

- `image_create_page.dart`

## 4.2 图片创作页

页面标题建议：

- `图片创作`

副标题建议：

- `生成图片并自动入库到素材库。`

页面结构尽量复用视频创作页：

1. `模式`
2. `描述`
3. `参数`
4. `请求预览`
5. `提交区`
6. `提示`
7. `提交失败`

右上角必须展示：

- `积分 badge`
- `生成并入库` 按钮

### 4.2.1 模式区

第一版只做：

- `文生图`

此区保留是为了未来扩展图生图、局部重绘、风格延展等图片模式。

### 4.2.2 描述区

字段：

- `Prompt`

提示文案建议：

- `描述主体、风格、镜头、构图、光线、材质和氛围。`

第一版不需要支持素材 `@` 引用。

### 4.2.3 参数区

建议包含：

- `比例`
- `质量`
- `张数`
- `输出格式`
- `分类`
- `入库角色`

#### 比例

前端可选值：

- `1:1`
- `4:3`
- `16:9`
- `9:16`

映射到主工具 `image_size`：

- `1:1 -> square_hd`
- `4:3 -> landscape_4_3`
- `16:9 -> landscape_16_9`
- `9:16 -> portrait_16_9`

备注：

- 如果后续需要竖版 `4:3`，再补 `portrait_4_3`

#### 质量

- `low`
- `medium`
- `high`

#### 张数

- UI 可显示 `1-4`
- 如果担心首版复杂度，可临时只开放 `1`
- 但底层数据结构必须按多图设计

#### 输出格式

- `png`
- `jpeg`
- `webp`

#### 分类

- 复用当前素材分类体系
- 默认可为空或默认第一项

#### 入库角色

建议支持：

- `参考图`
- `首帧图`
- `尾帧图`

默认：

- `参考图`

### 4.2.4 不应出现在图片创作页的字段

以下为视频专属字段，应在图片页隐藏：

- `时长`
- `帧数`
- `Seed`（当前主工具 schema 未提供）
- `生成音频`
- `returnLastFrame`
- `首帧/尾帧视频控制逻辑`
- `参考视频`
- `参考音频`
- 视频素材 `@` 引用入口

### 4.2.5 积分展示

图片创作页必须像视频创作页一样展示积分。

建议复用现有 `ToolResolution` + `CreditBadge` 的交互模式：

- `获取积分中`
- `积分未获取`
- `10 credits`

积分来源：

- AgentEarth recommend 返回的 `credit`

### 4.2.6 请求预览

图片创作页保留请求预览，展示：

- `tool_name`
- `tool_url`
- `params`

方便开发调试和高级用户确认请求。

### 4.2.7 提交按钮

文案：

- `生成并入库`

点击后行为：

- 创建图片任务
- 自动跳转任务页 `图片` tab

## 4.3 任务页

修改 [tasks_page.dart](/Users/jbrains/projects/apps/mova/lib/pages/tasks_page.dart)。

### 4.3.1 顶部 tab

新增 tab：

- `视频`
- `图片`

默认选中：

- 保持视频优先

### 4.3.2 视频任务

- 保持现有行为不变

### 4.3.3 图片任务卡片

图片任务卡应尽量复用视频任务卡结构，保留：

- 状态标签
- Prompt 摘要
- 创建时间
- 更新时间
- 异常标识
- 状态详情
- 失败原因
- 轮询日志入口
- 详情入口

图片任务新增展示：

- `生成张数`
- `已入库 x/y`
- 缩略图结果网格
- `重试失败项`
- `查看素材`

### 4.3.4 图片任务详情

详情页尽量保留视频任务已有内容：

- 任务 ID
- 状态
- 轮询状态
- 创建时间
- 更新时间
- 状态详情
- 失败信息
- 异常标识
- Prompt
- 请求入参
- 任务响应
- 轮询日志

图片任务额外补充：

- 工具名
- 预计积分
- 结果项列表
- 每张图的三方 URL
- 每张图的云存储 URL
- 对应素材库 attachmentId

## 5. 状态机设计

## 5.1 图片任务粒度

图片任务不能设计成“一任务一图片”，必须是：

- 一个图片任务
- 多个图片结果项

原因：

- `num_images` 支持 `1-4`
- 转存过程中每张图可能成功或失败情况不同

## 5.2 任务级状态

建议沿用现有视频任务的枚举：

- `submitted`
- `inProgress`
- `success`
- `failure`

但通过 `statusDetail` 表达更细信息。

推荐状态详情示例：

- `已提交，等待上游生成`
- `正在查询上游状态...`
- `已生成 2/4 张，正在转存`
- `已入库 3/4 张，1 张上传失败`
- `全部图片已入库`

## 5.3 图片结果项状态

新增图片结果项状态：

- `queued`
- `generating`
- `readyToTransfer`
- `downloading`
- `downloadFailed`
- `uploading`
- `uploadFailed`
- `imported`

### 状态含义

- `queued`：任务刚创建，尚未得到最终图片结果
- `generating`：上游仍在生成
- `readyToTransfer`：已获得第三方 URL，待下载
- `downloading`：正在从第三方 URL 下载到临时文件
- `downloadFailed`：下载失败
- `uploading`：正在上传到七牛/缤纷云
- `uploadFailed`：上传失败
- `imported`：已上传成功并写入素材库

## 5.4 失败与异常

结果项失败必须细分为：

- 生成失败
- 下载失败
- 上传失败

任务级异常建议继续保留：

- `hasAnomaly`
- `anomalyMessage`

## 6. 操作设计

## 6.1 图片任务级操作

建议支持：

- `复制到图片创作`
- `重新生成`
- `重试失败项`
- `查看详情`
- `删除任务`

### 复制到图片创作

语义：

- 复制当前任务的创作参数到图片创作页
- 不自动再次提交

复制内容：

- Prompt
- 比例
- 质量
- 张数
- 输出格式
- 分类
- 入库角色

### 重新生成

语义：

- 使用原参数新建一条新的图片任务
- 不覆盖原任务

### 重试失败项

语义：

- 仅重试失败的下载/上传/入库项
- 不重新调用模型

## 6.2 图片结果项操作

建议支持：

- `预览`
- `复制结果 URL`
- `重试下载`
- `重试上传`
- `查看素材`

说明：

- `重试下载` 适用于已有三方 URL 但下载失败
- `重试上传` 适用于图片已下载成功但上传云存储失败
- `查看素材` 在已入库时跳到素材库对应素材

## 7. 数据模型设计

建议尽量复用现有 [models.dart](/Users/jbrains/projects/apps/mova/lib/app/models.dart) 中的命名风格。

## 7.1 新增枚举

建议新增：

```dart
enum TaskKind { video, image }

enum TaskTab { video, image }

enum ImageCreateMode { textToImage }

enum ImageResultStatus {
  queued,
  generating,
  readyToTransfer,
  downloading,
  downloadFailed,
  uploading,
  uploadFailed,
  imported,
}
```

## 7.2 图片创作元数据

建议新增：

```dart
class ImageMetadataState {
  const ImageMetadataState({
    required this.aspectRatio,
    required this.quality,
    required this.numImages,
    required this.outputFormat,
    required this.category,
    required this.role,
  });

  final String aspectRatio;
  final String quality;
  final int numImages;
  final String outputFormat;
  final String category;
  final AttachmentRole role;
}
```

## 7.3 图片结果项

建议新增：

```dart
class ImageTaskResultItem {
  const ImageTaskResultItem({
    required this.id,
    required this.status,
    this.remoteUrl,
    this.localTempPath,
    this.storageUrl,
    this.attachmentId,
    this.lastError,
    this.updatedAt,
    this.downloadRetryCount = 0,
    this.uploadRetryCount = 0,
  });
}
```

建议字段包含：

- `id`
- `status`
- `remoteUrl`
- `localTempPath`
- `storageUrl`
- `attachmentId`
- `lastError`
- `updatedAt`
- `downloadRetryCount`
- `uploadRetryCount`

## 7.4 图片任务

有两种实现路线。

### 路线 A：扩展现有 TaskRecord

在现有 `TaskRecord` 中增加：

- `TaskKind kind`
- `List<ImageTaskResultItem> imageResults`
- `ImageMetadataState? imageMetadata`

优点：

- 任务页更容易复用
- 序列化、列表展示、详情展示更集中

缺点：

- `TaskRecord` 会变重

### 路线 B：单独 ImageTaskRecord

新增 `ImageTaskRecord`，与 `TaskRecord` 并行维护。

优点：

- 语义清晰

缺点：

- 任务页、存储、状态管理需要双份逻辑

推荐：

- 第一版采用 `路线 A`

## 8. AppState 设计

在 [app_state.dart](/Users/jbrains/projects/apps/mova/lib/app/app_state.dart) 中新增图片域状态。

## 8.1 图片创作状态

建议新增：

- `String imagePrompt`
- `ImageMetadataState imageMetadata`
- `ImageCreateMode activeImageMode`
- `ToolResolution imageToolResolution`
- `bool isSubmittingImageTask`
- `String? imageSubmitErrorMessage`
- `TaskTab activeTaskTab`

说明：

- 不建议复用视频的 `prompt` 和 `metadata`
- 视频和图片创作页状态应分离，避免互相污染

## 8.2 图片任务动作

建议新增：

- `Future<void> resolveImageTool()`
- `ImageRequestPreview get imageRequestPreview`
- `Future<bool> submitImageTask()`
- `Future<bool> refreshImageTask(String taskId)`
- `Future<bool> retryImageTask(String taskId)`
- `void copyImageTaskToCreate(String taskId)`
- `Future<bool> retryFailedImageTransfers(String taskId)`
- `Future<bool> retryImageResultDownload(String taskId, String resultId)`
- `Future<bool> retryImageResultUpload(String taskId, String resultId)`

## 8.3 转存动作

建议新增：

- `Future<File> downloadRemoteImageToTemp(String url, String fileName)`
- `Future<StorageUploadResult> uploadGeneratedImageFile(PickedNativeFile file)`
- `Future<String> importGeneratedImageToLibrary(...)`

最后一个方法建议返回：

- 新增的 `attachmentId`

## 8.4 图片任务流转

`submitImageTask()` 建议流程：

1. 校验设置与参数
2. resolve 图片工具
3. 调用图片服务 execute
4. 创建图片任务记录
5. 切换到任务页图片 tab
6. 启动自动轮询

`refreshImageTask()` 建议流程：

1. 轮询上游状态
2. 如果未完成，更新任务状态
3. 如果已完成，解析图片 URL 列表
4. 为每个结果项创建或更新状态
5. 对未转存结果项逐个触发下载上传流程
6. 聚合结果项状态回写任务状态

## 9. 服务设计

## 9.1 新增图片服务

建议新增：

- [lib/services/image_generation_service.dart](/Users/jbrains/projects/apps/mova/lib/services/image_generation_service.dart)

职责：

- recommend 图片工具
- 解析推荐工具
- 构造 execute 请求
- 构造请求预览
- execute 提交任务
- poll 轮询任务
- 解析最终图片结果 URL 列表

## 9.2 参数构造

主工具参数构造建议：

```json
{
  "prompt": "...",
  "image_size": "landscape_4_3",
  "num_images": 1,
  "output_format": "png",
  "quality": "high",
  "sync_mode": false
}
```

比例到 `image_size` 映射：

- `1:1 -> square_hd`
- `4:3 -> landscape_4_3`
- `16:9 -> landscape_16_9`
- `9:16 -> portrait_16_9`

## 9.3 多图解析

服务层必须统一输出 `List<String>` 图片 URL。

无论上游返回：

- 单图对象
- 多图数组
- 嵌套结果结构

都应在服务层统一成结果项列表，避免 UI 层解析上游结构。

## 10. 云存储与素材库写入

## 10.1 现有可复用能力

当前项目已经有：

- 七牛上传服务 [qiniu_upload_service.dart](/Users/jbrains/projects/apps/mova/lib/services/qiniu_upload_service.dart)
- 缤纷云上传服务 [bitiful_s4_upload_service.dart](/Users/jbrains/projects/apps/mova/lib/services/bitiful_s4_upload_service.dart)
- 素材库 Attachment 模型和管理逻辑 [app_state.dart](/Users/jbrains/projects/apps/mova/lib/app/app_state.dart)

## 10.2 需要补的能力

上传服务当前使用 `PickedNativeFile` 作为输入。

图片生成结果从三方 URL 下载下来后，会变成：

- 本地临时文件

因此需要补一个把临时文件转换成上传入参的能力。

建议：

- 在 `native_file_picker.dart` 附近增加工厂方法
- 从本地 `File` + `mimeType` + `fileName` 构造 `PickedNativeFile`

## 10.3 素材入库策略

图片转存成功后，自动写入 `library`，与手动上传素材保持一致。

建议抽取一个通用方法，替代目前只在 `pickAndUploadFiles()` 中使用的成功分支。

建议新增通用入库方法：

- `insertUploadedAttachment(StorageUploadResult result, {String? labelOverride, AttachmentRole? roleOverride, String? categoryOverride})`

这样可同时服务：

- 本地导入素材
- AI 生成图片入库

## 10.4 默认命名规则

建议默认素材名：

- `AI图片-20260613-001`

或

- `AI图片-YYYYMMDD-HHmmss-序号`

建议在用户未手动命名时按此规则生成。

## 11. 重试设计

## 11.1 为什么必须有重试

图片任务不是一次纯模型调用，而是三段式链路：

1. 上游生成
2. 三方链接下载
3. 自有云存储上传

任一段都可能失败，因此必须支持重试。

## 11.2 重试类型

建议支持：

- `重新生成`
- `重试失败项`
- `重试下载`
- `重试上传`

### 重新生成

- 新建任务
- 可能重复扣模型 credits

### 重试失败项

- 只重跑失败的下载/上传项
- 不重新调用生图模型

### 重试下载

- 针对单个结果项

### 重试上传

- 针对单个结果项

## 11.3 状态提示

结果项失败信息建议清晰展示：

- `下载失败：403`
- `下载失败：连接超时`
- `上传失败：七牛配置缺失`
- `上传失败：Bitiful 鉴权失败`

## 12. 设置页变更

修改 [settings_page.dart](/Users/jbrains/projects/apps/mova/lib/pages/settings_page.dart)。

建议新增高级设置项：

- `主工具失败时自动尝试备用生图服务`

说明文案建议：

- `关闭后会严格使用 GPT Image 2；开启后失败时会尝试兼容服务，结果风格和参数支持可能不同。`

对应 `SettingsState` 新字段：

- `bool imageAutoFallbackEnabled`

默认值：

- `false`

## 13. 文件级开发清单

## 13.1 建议新增文件

- [lib/pages/image_create_page.dart](/Users/jbrains/projects/apps/mova/lib/pages/image_create_page.dart)
- [lib/services/image_generation_service.dart](/Users/jbrains/projects/apps/mova/lib/services/image_generation_service.dart)
- 可选：[lib/widgets/image_task_card.dart](/Users/jbrains/projects/apps/mova/lib/widgets/image_task_card.dart)
- 可选：[lib/widgets/image_result_grid.dart](/Users/jbrains/projects/apps/mova/lib/widgets/image_result_grid.dart)

## 13.2 需要修改的文件

- [lib/pages/library_page.dart](/Users/jbrains/projects/apps/mova/lib/pages/library_page.dart)
- [lib/pages/tasks_page.dart](/Users/jbrains/projects/apps/mova/lib/pages/tasks_page.dart)
- [lib/pages/settings_page.dart](/Users/jbrains/projects/apps/mova/lib/pages/settings_page.dart)
- [lib/app/models.dart](/Users/jbrains/projects/apps/mova/lib/app/models.dart)
- [lib/app/mock_data.dart](/Users/jbrains/projects/apps/mova/lib/app/mock_data.dart)
- [lib/app/app_state.dart](/Users/jbrains/projects/apps/mova/lib/app/app_state.dart)
- [lib/main.dart](/Users/jbrains/projects/apps/mova/lib/main.dart) 或相关路由入口
- [lib/services/native_file_picker.dart](/Users/jbrains/projects/apps/mova/lib/services/native_file_picker.dart)

## 14. 实施顺序建议

推荐按以下顺序落地：

1. 扩展 `models.dart`
2. 扩展 `mock_data.dart` 和 `SettingsState`
3. 新增 `image_generation_service.dart`
4. 在 `AppState` 中补图片任务状态与动作
5. 抽取“通用素材入库方法”
6. 新增 `图片创作页`
7. 在素材库页增加 `AI 生图` 入口
8. 在任务页增加 `视频/图片` tab
9. 增加图片任务卡、详情、结果项与重试操作
10. 补测试

## 15. 测试与验收清单

## 15.1 基础验收

- 素材库页可进入图片创作页
- 图片创作页可展示积分 badge
- 图片创作页可展示请求预览
- 图片创作页可提交任务
- 提交后任务页自动切到 `图片` tab

## 15.2 任务验收

- 图片任务可正常轮询
- 图片任务可显示状态详情
- 图片任务可显示请求入参与任务响应
- 图片任务可显示轮询日志
- 图片任务可复制到图片创作页
- 图片任务可重新生成

## 15.3 转存验收

- 上游返回单张图片时能自动转存入库
- 上游返回多张图片时能逐张转存入库
- 下载失败时有清晰状态
- 上传失败时有清晰状态
- 可重试失败项
- 已入库图片可在素材库中看到

## 15.4 回归验收

- 视频创作页现有能力不受影响
- 视频任务页现有能力不受影响
- 手动素材上传不受影响
- 七牛上传流程不回归
- 缤纷云上传流程不回归

## 16. 第一版范围建议

建议第一版必须做：

- 素材库增加 `AI 生图` 入口
- 新增图片创作页
- 接 `GPT Image 2`
- 自动下载第三方结果图
- 自动上传到七牛/缤纷云
- 自动入素材库
- 任务页新增 `视频/图片` tab
- 图片任务支持 `复制到图片创作`
- 图片任务支持 `重新生成`
- 图片任务支持 `重试失败项`

建议第一版暂不做：

- 图生图
- 局部重绘
- 多参考图控制
- 图片结果再反向自动带入视频创作页
- 图片任务拖拽排序
- 多工具手动切换面板

## 17. 推荐给下一次对话的启动指令

下次可以直接用下面这段作为实现目标：

`按 docs/image-generation-design.md 开始实现第一版：素材库加 AI 生图入口，新增图片创作页，接 AgentEarth GPT Image 2，自动下载外链并上传七牛/缤纷云入库，任务页加视频/图片 tab，图片任务支持复制到图片创作、重新生成、失败重试，并在设置页增加图片自动 fallback 开关。`
