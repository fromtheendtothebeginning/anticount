import 'package:flutter/foundation.dart';

import '../services/ai_service.dart';

/// AI 配置与识别状态
///
/// 管理多个 AI Profile，支持增删改查和激活切换。
class AiProvider extends ChangeNotifier {
  AiProvider(this._service);

  final AiService _service;

  List<AiProfile> _profiles = const [];
  String? _activeProfileId;
  bool _initialized = false;

  List<AiProfile> get profiles => _profiles;
  bool get initialized => _initialized;

  /// 当前激活的配置
  AiProfile? get activeProfile {
    if (_activeProfileId == null) return null;
    return _profiles.firstWhere(
      (p) => p.id == _activeProfileId,
      orElse: () => _profiles.first,
    );
  }

  /// 是否有可用配置
  bool get hasAvailableProfile =>
      activeProfile != null && activeProfile!.hasTextModel;

  /// 当前激活配置是否支持多模态（有配置多模态模型且厂商支持）
  bool get supportsMultimodal =>
      activeProfile != null &&
      activeProfile!.hasMultimodalModel &&
      activeProfile!.multimodalConfig!.vendor.supportsMultimodal;

  /// 启动时加载配置
  Future<void> bootstrap() async {
    _profiles = await _service.getProfiles();
    _activeProfileId = await _service.getActiveProfileId();
    _initialized = true;
    notifyListeners();
  }

  /// 添加配置
  Future<void> addProfile(AiProfile profile) async {
    await _service.addProfile(profile);
    _profiles = await _service.getProfiles();
    // 如果是第一个配置，自动激活
    if (_profiles.length == 1) {
      _activeProfileId = profile.id;
      await _service.setActiveProfileId(profile.id);
    }
    notifyListeners();
  }

  /// 更新配置
  Future<void> updateProfile(AiProfile profile) async {
    await _service.updateProfile(profile);
    _profiles = await _service.getProfiles();
    notifyListeners();
  }

  /// 删除配置
  Future<void> removeProfile(String id) async {
    await _service.removeProfile(id);
    _profiles = await _service.getProfiles();
    _activeProfileId = await _service.getActiveProfileId();
    notifyListeners();
  }

  /// 切换激活配置
  Future<void> setActiveProfile(String id) async {
    await _service.setActiveProfileId(id);
    _activeProfileId = id;
    notifyListeners();
  }

  /// 文本识别（使用激活配置）
  Future<AiRecognitionResult> recognizeFromText({
    required String text,
    required List<String> expenseCategories,
    required List<String> incomeCategories,
  }) async {
    final profile = activeProfile;
    if (profile == null) throw const AiException('未选择 AI 配置');
    return _service.recognizeFromText(
      profile: profile,
      text: text,
      expenseCategories: expenseCategories,
      incomeCategories: incomeCategories,
    );
  }

  /// 图片识别（使用激活配置）
  Future<AiRecognitionResult> recognizeFromImage({
    required String base64Image,
    String? textHint,
    required List<String> expenseCategories,
    required List<String> incomeCategories,
  }) async {
    final profile = activeProfile;
    if (profile == null) throw const AiException('未选择 AI 配置');
    return _service.recognizeFromImage(
      profile: profile,
      base64Image: base64Image,
      textHint: textHint,
      expenseCategories: expenseCategories,
      incomeCategories: incomeCategories,
    );
  }
}
