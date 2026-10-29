# Changelog
All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -
## v0.5.0 - 2026-10-29
#### Features
- freedesktop 通知守护进程与通知中心 - (7a3995c) - HttpAnimations
- 会话操作电源菜单(锁定 注销 睡眠 重启 关机) - (e521694) - HttpAnimations
- 菜单栏电量指示读取真实电池状态 - (73c88d1) - HttpAnimations
- 控制中心接入真实系统服务并读取初始状态 - (6a3978d) - HttpAnimations
- 全局快捷键与 Alt-Tab 窗口切换器 - (3dbc4a7) - HttpAnimations
- 新增文本输入、光标形状、空闲抑制、呈现时间、激活与主选择协议 - (eda2d0d) - HttpAnimations
- 系统后端与统一设置状态 - (6920d1b) - calico
- 桌面无障碍语义与 Alt-Tab 窗口切换 - (cdb7465) - calico
- 壁纸与标题栏右键菜单 - (1c7076c) - calico
- 会话监督器在 shell 崩溃时重启 - (ede6ec4) - calico
- Debian 与 Flatpak 打包 - (ba98083) - calico
- Notes 持久化与计算器应用 - (418732d) - calico
- 内置壁纸预设与选择器 - (6d6632c) - calico
- 工作区切换与窗口迁移 - (04334e4) - calico
- 菜单项接活窗口状态并移除死项 - (4926c5a) - calico
- dock 图标固定、取消固定与拖拽排序 - (e76d496) - calico
- 窗口拖拽限制在屏幕内并支持边缘贴靠 - (12f7f60) - calico
- 真正的全屏窗口覆盖 shell 界面 - (7271b8f) - calico
- 持久化主题、语言与控制中心状态 - (93bcb34) - calico
- 启动器搜索结果按前缀、关键词和最近使用排序 - (f53a992) - calico
- 应用目录变更时重新加载 - (11a4d08) - calico
#### Bug Fixes
- 支持客户端自定义指针光标纹理 - (bae8de3) - HttpAnimations
- 指针输入按层级命中并转发给子表面 - (349f0c7) - HttpAnimations
- shm 提交按脏矩形局部拷贝 - (5b28657) - HttpAnimations
- 输出上报真实分辨率与缩放并支持视口和分数缩放协议 - (e73cbdd) - HttpAnimations
- 完整实现 wl_surface 挂起状态并应用输入区域 - (b6b812d) - HttpAnimations
- 点击子弹窗不再误关父级弹窗并实现 grab - (789010c) - HttpAnimations
- 跟踪瞬态窗口父子关系并转发窗口菜单请求 - (44820da) - HttpAnimations
- 剪贴板改为异步读写并按实际 mime 提供 - (c9b5ea5) - HttpAnimations
- dmabuf 缓冲区按引用计数管理生命周期 - (e643798) - HttpAnimations
- 关闭窗口改为宽限后逐级升级 SIGTERM/SIGKILL - (c4e0b96) - HttpAnimations
- 焦点切换时向旧窗口发送非激活配置 - (e5a6e60) - HttpAnimations
- 启动应用时清除 DISPLAY 与 XAUTHORITY - (8a8abaf) - HttpAnimations
- 会话脚本经 cage 合成器启动 shell - (8b5c227) - HttpAnimations
- 会话模式下原生窗口全屏启动 - (20d6620) - HttpAnimations
- 二次启动聚焦已有窗口而非新建窗口 - (2f416bf) - HttpAnimations
- 启动中窗口超时清理并按 appId 匹配 surface - (1844ad3) - calico
- 启动器评分修正名称加权 - (3e62c4d) - calico
- 图标查找解析 index.theme 并移到后台 isolate - (6944590) - calico
- desktop 条目解析补齐 TryExec、动作、本地化名称等规范 - (be70dec) - calico
- dock 显示真实图标并修复最小化重复与放大抖动 - (8f187c6) - calico
- 菜单下拉位置改用真实布局测量 - (4a04827) - calico
- LaunchPad 左右方向键不再抢占搜索框光标 - (9d1dd45) - calico
- 控制中心去掉占位点并补齐分组卡片 - (7eb2a90) - calico
- 取消未聚焦窗口整体变暗 - (bd7ae07) - calico
- 菜单栏时钟按本地化格式显示并在整分钟刷新 - (986c65c) - calico
- pubspec 版本与 cog 标签同步 - (34f8e07) - calico
#### Documentation
- 补齐原生构建依赖与架构、贡献文档 - (f99ec31) - calico
#### Tests
- 覆盖 NoopSystemBackend 构造函数 - (1f024ff) - calico
- 覆盖率门禁输出缺失行 - (fd40855) - calico
- 图标主题查找覆盖 - (22f89fb) - calico
- 拆分 coverage_fill 测试并补充暗色黄金图 - (7319307) - calico
- 更新 LaunchPad 翻页键盘行为断言 - (68e78fc) - calico
#### Refactoring
- 合成器拆分与串行跟踪 - (ac0a147) - calico
- 每种语言只保留一个 ARB 文件 - (730684c) - calico
#### Miscellaneous Chores
- 触发主分支流水线验证 - (1857a25) - HttpAnimations
- 删除无关的 altstore.json 并添加 .gitattributes - (23323d0) - calico

- - -

## v0.4.3 - 2026-10-29
#### Bug Fixes
- 修复 Wayland 应用窗口输入事件错位与指针状态泄漏 - (f98f3da) - calico

- - -

## v0.4.2 - 2026-10-29
#### Bug Fixes
- 发布前清理残留本地标签 - (d4ff84b) - HttpAnimations
- 发布流程识别轻量标签 - (cfa0a79) - HttpAnimations
- 自动发布直接推送标签并同步发布资产 - (dd40f19) - HttpAnimations

- - -

## v0.4.1 - 2026-10-29
#### Bug Fixes
- 修复 GitLab 发布链接参数被拒绝 - (906c9e4) - HttpAnimations
#### Continuous Integration
- cog 打带 v 前缀的版本标签 - (f4779ff) - HttpAnimations

- - -

## 0.4.0 - 2026-10-29
#### Features
- 新增自定义壁纸服务与设置面板 - (53d28b9) - HttpAnimations
- 新增 RPM 打包与登录会话文件 - (3c6b127) - HttpAnimations
- 支持窗口边缘拖拽缩放 - (98329d0) - HttpAnimations
- 新增启动台应用网格 - (7b72ed6) - HttpAnimations
- 支持 dmabuf 硬件加速缓冲区 - (e7bda6b) - calico
#### Bug Fixes
- 兼容旧版 wayland-protocols 的 dmabuf 参数接口 - (e9f374b) - HttpAnimations
- 修复应用窗口无法交互并持续缩小的问题 - (5ab0295) - calico
- 遵循客户端尺寸限制并贴合缓冲区 - (2b0d194) - HttpAnimations
- 缩放 Wayland 缓冲区以填满窗口 - (72da8f1) - HttpAnimations
#### Continuous Integration
- RPM 构建跳过构建依赖检查 - (1a99b93) - HttpAnimations
- 补齐 Linux 构建缺失的系统依赖 - (380a750) - HttpAnimations
- 构建流程产出 x86_64 与 aarch64 RPM - (3953601) - HttpAnimations

- - -

## 0.3.0 - 2026-10-29
#### Features
- 支持 Wayland 应用窗口嵌入 - (8977f75) - calico

- - -

## 0.2.0 - 2026-10-29
#### Features
- 窗口最小化添加精灵动画 - (ea08d12) - Calico
#### Continuous Integration
- 页面部署覆盖唯一域路径 - (45d0398) - Calico
- 发布脚本支持已存在的 release - (e858ee2) - Calico
- 修复 workflow 语法 - (0cb49a1) - Calico
- 修复产物路径、发布权限与构建监听 - (9a92710) - Calico
- tag 流水线只推送标签不推主分支 - (dcbee36) - Calico
- tag 构建触发与 GitHub 发布创建 - (5f222fb) - Calico
- 单独推送标签 - (a29244d) - Calico

- - -

## 0.1.0 - 2026-10-28
#### Features
- 初始提交 Oasis 桌面环境 - (e2e06fe) - Calico
#### Bug Fixes
- 补齐 landing 展示图片资源 - (b3ed02c) - Calico
#### Tests
- 修复冗余 const 导致的分析告警 - (93fdbc5) - Calico
- 修复壁纸构造器覆盖率的确定性 - (340bd22) - Calico
- 固定窗口双击时间保证覆盖率稳定 - (d96759c) - Calico
- 允许 golden 测试跨环境的像素容差 - (d3a64a6) - Calico
#### Continuous Integration
- 直接运行 cog bump 并推送标签 - (9a528c0) - Calico
- 修正 cog 二进制解压路径 - (a0635ec) - Calico
- 发布 job 改用 GitLab API - (89b8372) - Calico
- 安装 Linux 桌面构建依赖并手动安装 arm64 Flutter - (bb4374f) - Calico
- 用 sh 运行同步脚本 - (6953d2a) - Calico
- 保存覆盖率产物便于排查 - (60a1a5f) - Calico
- 修正 github 推送的引用规范 - (41d9e21) - Calico
- 同步 job 换用 alpine 基础镜像 - (d309e43) - Calico
- 修正覆盖率检查读取 lcov 记录 - (3abb5e7) - Calico
- 修复发布 job 的镜像与依赖 - (e2a51d0) - Calico
- 修复同步脚本与发布 job 的依赖 - (51ac810) - Calico
#### Miscellaneous Chores
- 修正 cog 配置 - (e27db77) - Calico

- - -

Changelog generated by [cocogitto](https://github.com/cocogitto/cocogitto).