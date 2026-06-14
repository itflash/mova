import 'models.dart';
import '../services/api_client.dart';

const appTabs = [
  (tab: AppTab.create, label: '创作'),
  (tab: AppTab.library, label: '素材库'),
  (tab: AppTab.composition, label: '剪辑'),
  (tab: AppTab.tasks, label: '任务'),
  (tab: AppTab.settings, label: '设置'),
];

const modes = [
  ModeOption(id: ModeId.text, title: '文本生视频', hint: '只输入文字，快速出片'),
  ModeOption(id: ModeId.firstFrame, title: '首帧图生视频', hint: '一张首帧图加动作描述'),
  ModeOption(id: ModeId.firstLast, title: '首尾帧视频', hint: '控制开头和结尾画面'),
  ModeOption(id: ModeId.reference, title: '参考素材生成', hint: '支持参考图、视频、音频'),
];

const defaultCategories = ['角色', '分镜', '运镜', '场景', '氛围', '道具', '音乐', '音效'];
const uncategorizedCategory = '';
const uncategorizedCategoryLabel = '未分类';

String displayCategoryLabel(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? uncategorizedCategoryLabel : trimmed;
}

const fieldHelp = {
  'frames': '默认留空，只有想精确控制总帧数时再填写。',
  'seed': '默认随机，只有想复现相近结果时再填写。',
  'cameraFixed': '开启后镜头更稳，适合少运镜场景。',
  'watermark': '开启后结果带平台水印。',
  'generateAudio': '带参考音频时必须保持开启。',
  'returnLastFrame': '需要复用尾帧时开启。',
};

const modeCredits = {
  ModeId.text: 500,
  ModeId.firstFrame: 500,
  ModeId.firstLast: 500,
  ModeId.reference: 500,
};

const metadataDefaults = MetadataState(
  model: 'doubao-seedance-2-0-260128',
  duration: '15',
  frames: '',
  resolution: '720p',
  ratio: '16:9',
  seed: '',
  cameraFixed: false,
  watermark: true,
  generateAudio: true,
  returnLastFrame: false,
);

const settingsDefaults = SettingsState(
  storageProvider: StorageProvider.qiniu,
  agentEarthBaseUrl: agentEarthDefaultBaseUrl,
  agentEarthApiKey: '',
  qiniuAccessKey: '',
  qiniuSecretKey: '',
  qiniuBucket: '',
  qiniuDomain: '',
  bitifulAccessKey: '',
  bitifulSecretKey: '',
  bitifulBucket: '',
  bitifulEndpoint: 'https://s3.bitiful.net',
  bitifulRegion: 'cn-east-1',
  bitifulPublicDomain: '',
  autoPoll: true,
  autoDownload: true,
  imageAutoFallbackEnabled: false,
);

final initialLibrary = <Attachment>[];

final initialTasks = <TaskRecord>[];

const initialPrompt = '';

const imageMetadataDefaults = ImageMetadataState(
  aspectRatio: '1:1',
  quality: 'medium',
  numImages: 1,
  outputFormat: 'png',
  category: '',
  role: AttachmentRole.referenceImage,
);

const aspectRatioToImageSize = {
  '1:1': 'square_hd',
  '4:3': 'landscape_4_3',
  '16:9': 'landscape_16_9',
  '9:16': 'portrait_16_9',
};
