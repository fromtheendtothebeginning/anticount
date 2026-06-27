import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// AI 请求统一超时时间
const Duration _kRequestTimeout = Duration(seconds: 20);

/// AI 模型类型
enum AiModelType {
  /// 自然语言模型（仅文本）
  text,
  /// 多模态模型（文本 + 图片）
  multimodal,
}

/// AI 模型描述
class AiModel {
  const AiModel({
    required this.id,
    required this.type,
    this.description,
  });

  /// 模型 ID（用于 API 请求）
  final String id;
  /// 模型类型
  final AiModelType type;
  /// 模型描述（可选，用于 UI 显示）
  final String? description;

  /// 是否为多模态模型
  bool get isMultimodal => type == AiModelType.multimodal;
}

/// AI 模型厂商
enum AiVendor {
  kimi,
  deepseek;

  String get label {
    switch (this) {
      case AiVendor.kimi:
        return 'Kimi (Moonshot AI)';
      case AiVendor.deepseek:
        return 'DeepSeek';
    }
  }

  /// API 基础地址
  String get baseUrl {
    switch (this) {
      case AiVendor.kimi:
        return 'https://api.moonshot.cn/v1';
      case AiVendor.deepseek:
        return 'https://api.deepseek.com';
    }
  }

  /// 该厂商可用的模型列表（含类型信息）
  /// 参考：
  /// - Kimi: https://platform.moonshot.cn/docs/introduction
  /// - DeepSeek: https://api-docs.deepseek.com/api/create-chat-completion
  List<AiModel> get availableModels {
    switch (this) {
      case AiVendor.kimi:
        return const [
          AiModel(id: 'kimi-k2.5', type: AiModelType.multimodal, description: '多模态'),
          AiModel(id: 'kimi-k2-thinking', type: AiModelType.text, description: '思考'),
          AiModel(id: 'moonshot-v1-8k', type: AiModelType.text, description: '8k 上下文'),
          AiModel(id: 'moonshot-v1-32k', type: AiModelType.text, description: '32k 上下文'),
          AiModel(id: 'moonshot-v1-128k', type: AiModelType.text, description: '128k 上下文'),
        ];
      case AiVendor.deepseek:
        return const [
          AiModel(id: 'deepseek-v4-pro', type: AiModelType.text, description: '思考'),
          AiModel(id: 'deepseek-v4-flash', type: AiModelType.text, description: '快捷'),
        ];
    }
  }

  /// 该厂商的所有多模态模型 ID（用于图片识别选择）
  List<String> get multimodalModelIds =>
      availableModels.where((m) => m.isMultimodal).map((m) => m.id).toList();

  /// 该厂商的所有模型 ID（用于文字识别选择，多模态模型也可用于文字）
  List<String> get allModelIds =>
      availableModels.map((m) => m.id).toList();

  /// 该厂商是否支持多模态（图片输入）
  /// DeepSeek 仅支持自然语言处理
  bool get supportsMultimodal => multimodalModelIds.isNotEmpty;

  /// 根据 ID 查找模型
  AiModel? findModel(String id) {
    for (final m in availableModels) {
      if (m.id == id) return m;
    }
    return null;
  }
}

/// 单个模型配置（厂商 + API Key + 模型 ID）
///
/// 文本识别和多模态识别各自独立配置，可使用不同厂商。
/// 例如：文本用 DeepSeek，多模态用 Kimi。
class AiModelConfig {
  const AiModelConfig({
    required this.vendor,
    required this.apiKey,
    required this.modelId,
  });

  final AiVendor vendor;
  final String apiKey;
  final String modelId;

  bool get isValid => apiKey.isNotEmpty && modelId.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'vendor': vendor.name,
        'apiKey': apiKey,
        'modelId': modelId,
      };

  factory AiModelConfig.fromMap(Map<String, dynamic> map) => AiModelConfig(
        vendor: AiVendor.values.firstWhere(
          (e) => e.name == map['vendor'],
          orElse: () => AiVendor.kimi,
        ),
        apiKey: map['apiKey'] as String? ?? '',
        modelId: map['modelId'] as String? ?? '',
      );

  AiModelConfig copyWith({
    AiVendor? vendor,
    String? apiKey,
    String? modelId,
  }) =>
      AiModelConfig(
        vendor: vendor ?? this.vendor,
        apiKey: apiKey ?? this.apiKey,
        modelId: modelId ?? this.modelId,
      );
}

/// AI 配置（Profile）
///
/// 将文本识别配置和多模态识别配置打包为一个完整配置。
/// 用户可创建多个配置并在不同配置间切换。
/// 文本和多模态可分别使用不同厂商的模型。
class AiProfile {
  const AiProfile({
    required this.id,
    required this.name,
    this.textConfig,
    this.multimodalConfig,
  });

  /// 唯一标识
  final String id;
  /// 配置名称（如"我的配置"）
  final String name;
  /// 文本识别配置（厂商 + API Key + 模型）
  final AiModelConfig? textConfig;
  /// 多模态识别配置（厂商 + API Key + 模型），可选
  final AiModelConfig? multimodalConfig;

  /// 是否有可用的文本模型
  bool get hasTextModel =>
      textConfig != null && textConfig!.modelId.isNotEmpty;

  /// 是否有可用的多模态模型
  bool get hasMultimodalModel =>
      multimodalConfig != null && multimodalConfig!.modelId.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'textConfig': textConfig?.toMap(),
        'multimodalConfig': multimodalConfig?.toMap(),
      };

  factory AiProfile.fromMap(Map<String, dynamic> map) => AiProfile(
        id: map['id'] as String,
        name: map['name'] as String,
        textConfig: map['textConfig'] != null
            ? AiModelConfig.fromMap(map['textConfig'] as Map<String, dynamic>)
            : null,
        multimodalConfig: map['multimodalConfig'] != null
            ? AiModelConfig.fromMap(
                map['multimodalConfig'] as Map<String, dynamic>)
            : null,
      );

  AiProfile copyWith({
    String? name,
    AiModelConfig? textConfig,
    AiModelConfig? multimodalConfig,
  }) =>
      AiProfile(
        id: id,
        name: name ?? this.name,
        textConfig: textConfig ?? this.textConfig,
        multimodalConfig: multimodalConfig ?? this.multimodalConfig,
      );
}

/// AI 识别结果
class AiRecognitionResult {
  const AiRecognitionResult({
    required this.amount,
    required this.type,
    required this.category,
    this.note,
  });

  final double amount;
  final String type; // 'income' / 'expense'
  final String category;
  final String? note;
}

/// AI 服务
///
/// 管理多个 AI 配置（Profile），调用大模型 API 进行记账识别。
class AiService {
  static const _kProfiles = 'ai_profiles';
  static const _kActiveProfileId = 'ai_active_profile_id';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// 获取所有配置
  Future<List<AiProfile>> getProfiles() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_kProfiles);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => AiProfile.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveProfiles(List<AiProfile> profiles) async {
    final prefs = await _getPrefs();
    final raw = jsonEncode(profiles.map((p) => p.toMap()).toList());
    await prefs.setString(_kProfiles, raw);
  }

  /// 添加配置
  Future<void> addProfile(AiProfile profile) async {
    // getProfiles 可能返回 const []（不可修改），需创建可修改副本
    final profiles = List<AiProfile>.from(await getProfiles());
    profiles.add(profile);
    await _saveProfiles(profiles);
  }

  /// 更新配置
  Future<void> updateProfile(AiProfile profile) async {
    final profiles = List<AiProfile>.from(await getProfiles());
    final idx = profiles.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      profiles[idx] = profile;
      await _saveProfiles(profiles);
    }
  }

  /// 删除配置
  Future<void> removeProfile(String id) async {
    final profiles = List<AiProfile>.from(await getProfiles());
    profiles.removeWhere((p) => p.id == id);
    await _saveProfiles(profiles);
    // 如果删除的是当前激活的，清除激活状态
    final activeId = await getActiveProfileId();
    if (activeId == id) {
      await setActiveProfileId(profiles.isEmpty ? null : profiles.first.id);
    }
  }

  /// 获取当前激活的配置 ID
  Future<String?> getActiveProfileId() async {
    final prefs = await _getPrefs();
    return prefs.getString(_kActiveProfileId);
  }

  Future<void> setActiveProfileId(String? id) async {
    final prefs = await _getPrefs();
    if (id == null) {
      await prefs.remove(_kActiveProfileId);
    } else {
      await prefs.setString(_kActiveProfileId, id);
    }
  }

  /// 获取当前激活的配置
  Future<AiProfile?> getActiveProfile() async {
    final id = await getActiveProfileId();
    if (id == null) return null;
    final profiles = await getProfiles();
    return profiles.firstWhere((p) => p.id == id, orElse: () => profiles.first);
  }

  /// 验证 API Key 是否有效
  ///
  /// 发送一个最小化的测试请求，根据响应判断 API Key 是否正确。
  /// 验证失败时抛出 [AiException]，包含具体错误信息和解决建议。
  Future<void> verifyApiKey({
    required AiVendor vendor,
    required String apiKey,
    required String modelId,
  }) async {
    // 去除前后空格（用户粘贴时可能带入空白字符）
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isEmpty) {
      throw const AiException('API Key 不能为空\n\n解决方法：请输入有效的 API Key');
    }

    // 基本格式校验：常见厂商 Key 前缀
    if (vendor == AiVendor.deepseek && !trimmedKey.startsWith('sk-')) {
      throw const AiException(
          'API Key 格式可能不正确（DeepSeek 的 Key 通常以 sk- 开头）\n\n'
          '解决方法：请前往 https://platform.deepseek.com 创建 API Key');
    }
    if (vendor == AiVendor.kimi && !trimmedKey.startsWith('sk-')) {
      throw const AiException(
          'API Key 格式可能不正确（Kimi 的 Key 通常以 sk- 开头）\n\n'
          '解决方法：请前往 https://platform.moonshot.cn 创建 API Key');
    }

    final url = '${vendor.baseUrl}/chat/completions';
    final body = <String, dynamic>{
      'model': modelId,
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
      'max_tokens': 5,
    };
    // DeepSeek 支持 JSON Output，但验证请求无需启用
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $trimmedKey',
        },
        body: jsonEncode(body),
      ).timeout(_kRequestTimeout);
    } on TimeoutException {
      throw AiException(
          'API 验证请求超时（20 秒）\n\n'
          '可能原因：\n'
          '· 网络连接不稳定或无法访问 API 服务器\n'
          '· 模拟器/设备未联网或 DNS 解析慢\n\n'
          '解决方法：\n'
          '· 检查网络连接\n'
          '· 确认设备能访问 ${vendor.baseUrl}');
    } catch (e) {
      throw AiException(
          '网络请求失败：$e\n\n'
          '解决方法：\n'
          '· 检查网络连接\n'
          '· 确认 API 地址 ${vendor.baseUrl} 可访问');
    }

    if (response.statusCode == 401) {
      throw const AiException(
          'API Key 无效或未授权（401）\n\n'
          '解决方法：\n'
          '· 检查 API Key 是否正确复制（无多余空格/换行）\n'
          '· 确认 API Key 未过期或被禁用\n'
          '· 重新生成 API Key');
    }
    if (response.statusCode == 403) {
      throw const AiException(
          'API Key 无访问权限（403）\n\n'
          '解决方法：\n'
          '· 确认账号已实名认证\n'
          '· 确认 API Key 有访问该模型的权限\n'
          '· 确认账户余额充足');
    }
    if (response.statusCode == 404) {
      throw AiException(
          '模型不存在或路径错误（404）\n\n'
          '解决方法：\n'
          '· 检查模型 ID「$modelId」是否正确\n'
          '· 确认厂商 ${vendor.label} 支持该模型');
    }
    if (response.statusCode == 429) {
      throw const AiException(
          '请求频率过高或余额不足（429）\n\n'
          '解决方法：\n'
          '· 稍后重试\n'
          '· 检查账户余额是否充足\n'
          '· 确认未触发 RPM 限制');
    }
    if (response.statusCode != 200) {
      // 提取错误消息
      String detail = response.body;
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final err = data['error'];
        if (err is Map && err['message'] != null) {
          detail = err['message'].toString();
        }
      } catch (_) {
        // 保持原始 body
      }
      throw AiException(
          'API 验证失败（${response.statusCode}）：$detail\n\n'
          '解决方法：\n'
          '· 查看上方错误详情\n'
          '· 如无法解决，请复制完整错误联系开发者');
    }
    // 200 表示 API Key 有效
  }

  /// 调用 AI 识别记账信息（纯文本）
  /// 使用 profile 的 textConfig
  /// 解析失败时自动重试，最多 3 次
  Future<AiRecognitionResult> recognizeFromText({
    required AiProfile profile,
    required String text,
    required List<String> expenseCategories,
    required List<String> incomeCategories,
  }) async {
    final config = profile.textConfig;
    if (config == null || config.apiKey.isEmpty) {
      throw const AiException('未配置文本识别');
    }
    if (config.modelId.isEmpty) {
      throw const AiException('未配置文本识别模型');
    }

    final prompt = _buildPrompt(expenseCategories, incomeCategories);
    final url = '${config.vendor.baseUrl}/chat/completions';

    // DeepSeek 支持 response_format JSON Output
    final useJsonMode = config.vendor == AiVendor.deepseek;

    // 最多重试 3 次
    for (var attempt = 1; attempt <= 3; attempt++) {
      final body = <String, dynamic>{
        'model': config.modelId,
        'messages': [
          {'role': 'system', 'content': prompt},
          {'role': 'user', 'content': text},
        ],
        'temperature': 0.1,
      };
      if (useJsonMode) {
        body['response_format'] = {'type': 'json_object'};
      }

      final http.Response response;
      try {
        response = await http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode(body),
        ).timeout(_kRequestTimeout);
      } on TimeoutException {
        // 超时直接抛出，不重试
        throw const AiException('API 请求超时（20s），请检查网络或代理设置');
      } catch (e) {
        // 网络错误直接抛出，不重试
        throw AiException('网络请求失败：$e');
      }

      if (response.statusCode != 200) {
        throw AiException(
            'API 请求失败（${response.statusCode}）：${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content =
          (data['choices'] as List).first['message']['content'] as String;
      try {
        return _parseResult(
          content,
          validCategories: [...expenseCategories, ...incomeCategories],
        );
      } catch (e) {
        // 解析失败，如果是最后一次尝试，抛出异常
        if (attempt == 3) {
          throw AiException('AI 返回结果无法解析（已重试 3 次）：$content');
        }
        // 否则继续重试
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    // 逻辑上不会到达
    throw const AiException('AI 识别失败');
  }

  /// 调用 AI 识别记账信息（图片 + 文本）
  /// 使用 profile 的 multimodalConfig
  /// 解析失败时自动重试，最多 3 次
  Future<AiRecognitionResult> recognizeFromImage({
    required AiProfile profile,
    required String base64Image,
    String? textHint,
    required List<String> expenseCategories,
    required List<String> incomeCategories,
  }) async {
    final config = profile.multimodalConfig;
    if (config == null || config.apiKey.isEmpty) {
      throw const AiException('未配置多模态识别');
    }
    if (config.modelId.isEmpty) {
      throw const AiException('未配置多模态识别模型');
    }
    if (!config.vendor.supportsMultimodal) {
      throw const AiException('多模态识别厂商不支持图片输入');
    }

    final prompt = _buildPrompt(expenseCategories, incomeCategories);
    final url = '${config.vendor.baseUrl}/chat/completions';

    // 最多重试 3 次
    for (var attempt = 1; attempt <= 3; attempt++) {
      final http.Response response;
      try {
        response = await http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode({
            'model': config.modelId,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': prompt},
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
                  },
                  if (textHint != null && textHint.isNotEmpty)
                    {'type': 'text', 'text': textHint},
                ],
              },
            ],
            'temperature': 0.1,
          }),
        ).timeout(_kRequestTimeout);
      } on TimeoutException {
        // 超时直接抛出，不重试
        throw const AiException('API 请求超时（20s），请检查网络或代理设置');
      } catch (e) {
        // 网络错误直接抛出，不重试
        throw AiException('网络请求失败：$e');
      }

      if (response.statusCode != 200) {
        throw AiException(
            'API 请求失败（${response.statusCode}）：${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content =
          (data['choices'] as List).first['message']['content'] as String;
      try {
        return _parseResult(
          content,
          validCategories: [...expenseCategories, ...incomeCategories],
        );
      } catch (e) {
        // 解析失败，如果是最后一次尝试，抛出异常
        if (attempt == 3) {
          throw AiException('AI 返回结果无法解析（已重试 3 次）：$content');
        }
        // 否则继续重试
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    // 逻辑上不会到达
    throw const AiException('AI 识别失败');
  }

  String _buildPrompt(
    List<String> expenseCategories,
    List<String> incomeCategories,
  ) {
    return '''你是一个记账助手。请根据用户输入识别记账信息，并以 JSON 格式返回结果。

返回格式（严格 JSON，禁止任何额外文字、解释或 markdown 代码块）：
{
  "amount": 35.5,
  "type": "expense",
  "category": "餐饮",
  "note": "午餐"
}

字段约定（必须严格遵守，否则视为解析失败）：
1. "amount" 必须是正数（number 类型，不能是字符串），如 35.5
2. "type" 必须是字符串 "income" 或 "expense" 之一，不能是其他值
3. "category" 必须从下方分类列表中选择，不能编造新分类
4. "note" 是字符串，可选；如无备注返回空字符串 ""

支出可选分类：${expenseCategories.join('、')}
收入可选分类：${incomeCategories.join('、')}

规则：
1. 根据 type 选择对应分类：type=income 时从收入分类选，type=expense 时从支出分类选
2. 如无法确定分类，使用"其他"（如分类列表中存在）
3. amount 必须为正数；如输入为"收入 100"则 type=income，amount=100
4. 仅返回 JSON 对象，不要包裹在 markdown 代码块中''';
  }

  AiRecognitionResult _parseResult(
    String content, {
    required List<String> validCategories,
  }) {
    var jsonStr = content.trim();
    if (jsonStr.contains('```')) {
      final match = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(jsonStr);
      if (match != null) {
        jsonStr = match.group(1)!.trim();
      }
    }

    final map = jsonDecode(jsonStr) as Map<String, dynamic>;

    // amount 必须是正数
    final rawAmount = map['amount'];
    if (rawAmount == null) {
      throw AiException('缺少 amount 字段: $content');
    }
    final amount = (rawAmount as num).toDouble();
    if (amount <= 0) {
      throw AiException('amount 必须为正数: $content');
    }

    // type 必须是 income 或 expense
    final type = (map['type'] as String?)?.toLowerCase();
    if (type != 'income' && type != 'expense') {
      throw AiException('type 字段无效: $content');
    }

    // category 必须在分类列表中
    final category = (map['category'] as String?) ?? '';
    if (category.isEmpty || !validCategories.contains(category)) {
      throw AiException('category 不在分类列表中: $content');
    }

    final note = map['note'] as String?;
    return AiRecognitionResult(
      amount: amount,
      type: type == 'income' ? 'income' : 'expense',
      category: category,
      note: note,
    );
  }
}

/// AI 异常
class AiException implements Exception {
  const AiException(this.message);
  final String message;

  @override
  String toString() => message;
}
