# AntiCount 智能记账

一款基于 Flutter 开发的个人智能记账应用，支持 AI 图像/文字识别记账、多厂商模型配置、账单分组查看等功能。

## 功能特性

### 记账管理
- 手动记账：支持收入/支出分类管理
- 账单查看：按日/周/月/年分组展示，月收支汇总
- 分类管理：自定义收支分类
- 重复检测：自动识别重复账单并提示确认

### AI 智能记账
- 多照片识别：支持一次拍摄多张票据同时识别
- 多厂商支持：DeepSeek、Kimi、通义千问、智谱、OpenAI、Google、Anthropic
- 双模式识别：文字识别 + 图像识别（多模态）
- 自动保存：识别后可自动保存（带确认弹窗）
- API Key 验证：保存前自动验证 API Key 有效性

### 用户系统
- 注册/登录/重置密码
- 头像上传（相机/相册）
- 昵称编辑
- 退出登录（可选保留数据）
- 账户注销

### 设置
- 主题色：蓝色主题
- 货币单位切换
- 账户安全（修改密码/注销账户）
- AI 自动保存开关
- 中文本地化

## 技术栈

| 技术 | 说明 |
|------|------|
| Flutter | 跨平台 UI 框架 |
| Dart | 编程语言 |
| Provider | 状态管理 |
| sqflite | 本地 SQLite 数据库 |
| shared_preferences | 轻量级本地存储 |
| http | AI API 网络请求 |
| image_picker | 图片选择（相机/相册） |
| url_launcher | 打开外部链接（厂商开放平台） |
| crypto | 密码加密 |

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── config/
│   └── env.dart                 # 环境配置
├── constants/
│   └── app_info.dart            # 应用信息（版本号等）
├── models/
│   ├── transaction.dart         # 交易模型
│   └── user.dart                # 用户模型
├── providers/
│   ├── ai_provider.dart         # AI 配置状态管理
│   ├── auth_provider.dart       # 认证状态管理
│   ├── settings_provider.dart   # 设置状态管理
│   └── transaction_provider.dart # 交易状态管理
├── screens/
│   ├── accounting/              # 手动记账
│   ├── ai/                      # AI 记账 + 配置
│   ├── auth/                    # 登录/注册/重置密码
│   ├── bills/                   # 账单查看
│   ├── home/                    # 主页
│   ├── profile/                 # 个人中心
│   └── settings/                # 设置
├── services/
│   ├── ai_service.dart          # AI 服务（7 厂商 + 双 API 格式）
│   ├── auth_service.dart        # 认证服务
│   ├── database_service.dart    # 数据库服务
│   ├── settings_service.dart    # 设置服务
│   └── transaction_service.dart # 交易服务
└── widgets/
    ├── animated_dialog.dart     # 动画对话框
    ├── app_button.dart          # 通用按钮
    └── app_text_field.dart      # 通用输入框
```

## 开发环境

- Flutter SDK: ^3.9.2
- Dart SDK: ^3.9.2
- 最低 Android 版本: API 21+

## 构建与运行

### 环境准备

```bash
flutter doctor
flutter pub get
```

### 开发运行

```bash
# 查看可用设备
flutter devices

# 运行到 Android 模拟器/真机
flutter run

# 运行到指定设备
flutter run -d <device_id>
```

### 构建 APK

```bash
# Release APK
flutter build apk --release

# 输出路径：build/app/outputs/flutter-apk/app-release.apk
```

### 代码分析

```bash
flutter analyze
```

## 应用图标

图标设计参考 Anticraft 品牌风格：
- 紫色圆角矩形背景 (#6C5CE7)
- 白色 N 字母
- 青色对角斜线 (#00CEC9)

## 版本历史

- v1.1.14 - AI记账界面精简 + 厂商开放平台跳转 + 配置菜单优化
- v1.1.13 - 年月切换动画移除 + 月份切换同步更新周 + AI识别底部留白
- v1.1.12 - 图标改为圆角矩形
- v1.1.11 - 直接使用网站图标设计
- v1.1.10 - 参考网站风格设计记账主题图标
- v1.1.9 - 艺术字 A + 存钱罐投币口图标
- v1.1.8 - 白色主题 + 存钱罐图标
- v1.1.7 - 创建应用图标
- v1.1.6 - 删除周收支模块
- v1.1.5 - 重复账单检测 + 自动保存确认
- v1.1.4 - _dependents.isEmpty bug 修复
- v1.1.3 - 周切换动画 + 卷帘门下拉 + 版本号抽象
- v1.1.2 - 账单页重构（月份切换 + 周切换 + 每日列表）
- v1.1.0 - 中文化 + 5 个新 AI 厂商 + 多照片 + 账单分组
- v1.0.1 - temperature 400 错误修复 + AI 配置分组
- v1.0.0 - 初始版本

## 开发规范

- 版本号格式：x.y.z
  - x：大版本号（需确认）
  - y：次版本号（新增功能时增加）
  - z：修订版本号（修复 bug 或完善功能时增加）
- 代码需写中文注释
- 工作日志记录在 `log/` 目录

## License

© 2026 Anticraft. All rights reserved.
