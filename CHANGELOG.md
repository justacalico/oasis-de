# Changelog
All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -
## v0.7.0 - 2026-10-30
#### Features
- 新增 KMS 直出运行目标与 CI wlroots 依赖 - (be65cf0) - calico
- 用 wlroots 重写合成器核心 - (e1bf86e) - calico
#### Tests
- 更新协议契约测试扫描新合成器目录 - (a3014e8) - calico
#### Continuous Integration
- wlroots 安装后刷新动态链接器缓存 - (baf01f7) - calico
- 从源码构建 pixman 0.44 - (b6eb37f) - calico
- 从源码构建 wayland 1.23 以满足 wlroots 版本要求 - (27875a6) - calico
- 补齐 wayland 与 xkbcommon 开发包 - (14667b6) - calico
- 移除无效的 meson tests 参数 - (b246933) - calico
- 修正 wlroots 依赖安装与 meson 构建参数 - (bb06709) - calico

- - -

## v0.6.0 - 2026-10-30
#### Other changes
- Merge branch 'fix/ci-regressions' [skip ci] - (4e76fd9) - calico
- Merge branch 'fix/issue-72-panzoom' [skip ci] - (e7af4d9) - calico
#### Features
- app de arquivos para o desktop [skip ci] - (5a43c40) - Devin
- baixar, verificar e instalar atualizações no app [skip ci] - (5bc45b8) - Devin
- cartão de mídia MPRIS no centro de controle [skip ci] - (8886491) - Devin
- novos painéis de configurações e busca na barra lateral - (485ee4b) - HttpAnimations
- componentes oasis_ui (menu, diálogo, campo, checkbox, tooltip) - (89341a1) - HttpAnimations
- painel About com informações do sistema - (fb0e6ea) - HttpAnimations
- animação de geometria em zoom/fullscreen/snap - (777855a) - HttpAnimations
- eventos wl_touch encaminhados para clientes - (4ec2a5e) - HttpAnimations
- seletor de idioma na landing com persistência - (7b8289f) - HttpAnimations
- downloads agrupados por formato e arquitetura - (42bd402) - HttpAnimations
- central de notificações com hora, ícone e urgência - (67f6ae0) - HttpAnimations
- menu de contexto do dock com janelas, ações e sair - (ba96e31) - HttpAnimations
- Semantics e tooltips nos elementos interativos do shell - (e5f6b1b) - HttpAnimations
- banner de notificação interativo com timeout e limite - (6dd54ad) - HttpAnimations
- tela de bloqueio com senha e lock antes de suspender - (64bd67a) - HttpAnimations
- confirmação antes de ações de energia e logout por sessão - (3a1fe3f) - HttpAnimations
- Meta+D alterna mostrar área de trabalho e restaura janelas - (33638bf) - HttpAnimations
- entrada English simples e rótulo English (UK) no seletor - (e1a1455) - HttpAnimations
#### Bug Fixes
- 以 bash 调用 release 和 RPM 构建脚本 - (82b2d8c) - calico
- 修复应用图标在 web 构建下的类型错误 - (53d60ec) - calico
- github-sync 以 bash 运行 watch 脚本 - (d62ef50) - calico
- github-sync 使用完整克隆避免浅克隆推送缺少对象 - (b60b273) - calico
- 修复 CI 流水线并补齐行覆盖率 - (195880b) - calico
- 修复启动器大部分应用图标无法加载的问题 - (fd1b5bd) - HttpAnimations
- 修复激活令牌提前销毁与初始 configure 缺失导致应用无法打开 - (bec387a) - HttpAnimations
- 窗口级联偏移只计当前工作区可见窗口 [skip ci] - (aacbf63) - Devin
- 切换工作区不聚焦最小化窗口 [skip ci] - (7c41737) - Devin
- 移动窗口到工作区时带上瞬态子窗口 [skip ci] - (7067394) - Devin
- Alt+Tab 按最近使用顺序切换窗口 [skip ci] - (6a3b9c6) - Devin
- 修复 CI 打包、集成与覆盖率门禁 - (0b8cdb8) - Devin
- 客户端光标纹理仅在客户端表面上渲染 [skip ci] - (c2b92fe) - Devin
- 启动器结果行传入 iconPath [skip ci] - (bebebf1) - Devin
- 解锁限流改为延迟而非拒绝 - (02106fb) - Devin
- 过滤启动面板时回到第一页 [skip ci] - (aa33483) - Devin
- 焦点丢失时释放客户端按键 [skip ci] - (fc102ce) - Devin
- 修复 MPRIS 总线死锁与打包、集成 CI 检查 - (4278b77) - Devin
- 修复“关于”页系统信息解析与 GPU 显示 [skip ci] - (6e734c4) - Devin
- 修复 CI 失败（MPRIS 总线容错、libdrm 依赖、打包与集成任务） - (2191fe2) - Devin
- desbloqueio falha fechado e limita tentativas [skip ci] - (d9b39a9) - Devin
- relógio da tela de bloqueio atualiza por minuto [skip ci] - (6538f31) - Devin
- tema de ícone do sistema, png-only e fallback de erro - (8bdcc09) - HttpAnimations
- drag/resize/snap respeitam fullscreen, zoom e pré-snap - (2236c7b) - HttpAnimations
- text-input envia leave antes de enter e sync na criação - (ee99fca) - HttpAnimations
- set_source do viewport e crop nas coords de input - (e2bb127) - HttpAnimations
- tokens de ativação com serial, surface e dono validados - (c202a6a) - HttpAnimations
- timer de retry cancelável e ordenação estável de apps - (d98588c) - calico
- enter com teclas, caps locked, pressed limpo, state validado - (bcf214e) - HttpAnimations
- pan-zoom pelos callbacks dedicados do Listener - (b108a95) - calico
- eventos de axis v5 com source, discrete e stop - (ca13a5c) - HttpAnimations
- popup hit-test em subsurfaces e coords normalizadas - (0bbbf4d) - HttpAnimations
- render e fullscreen filtrados pelo workspace ativo - (56224f4) - HttpAnimations
- toplevel anunciado só no primeiro commit com conteúdo - (f4ca33b) - HttpAnimations
- start retenta com backoff e stop exposto - (c88ca62) - HttpAnimations
- diretório ausente vigiado via pai e rearmado - (2a93021) - HttpAnimations
- terminal resolve xdg-terminal-exec e probes Wayland - (b82be8a) - HttpAnimations
- primeiro dir vence, erros por arquivo e symlinks seguidos - (0f8b4f2) - HttpAnimations
- entradas de apps carregam mesmo sem Wayland - (467313d) - HttpAnimations
- foco Wayland enviado só pelo controller - (d52ec43) - HttpAnimations
- cursor limpo no exit e shapes 30/31 como resize - (42e57ef) - HttpAnimations
- evento childrenReordered após reorder de subsurface - (cd79f59) - HttpAnimations
- HID 0x32 mapeia para KEY_102ND - (36645e1) - calico
- página HID checada e teclas de consumidor mapeadas - (da10d60) - HttpAnimations
- botões sincronizados no cancelamento do ponteiro - (db240df) - HttpAnimations
- spawn com child watch, erro, cwd e XDG desktop - (57e24bd) - HttpAnimations
- vínculos de subsurface pendentes resolvem no announce do pai - (1b801fb) - HttpAnimations
- atalhos do shell reservados antes de enviar ao cliente - (1146bee) - HttpAnimations
- contexto EGL perdido reseta caches e dispose apaga textura - (8c7b9fc) - HttpAnimations
- free remove timers, queries e sinais pendentes - (3427f0a) - HttpAnimations
- resend de saída coalescido em idle e só em mudança real - (b101cf9) - HttpAnimations
- feedback dmabuf aborta quando memfd falha - (aadee6f) - HttpAnimations
- oferta anterior destruída por dispositivo - (1a4fa11) - HttpAnimations
- formatos shm não duplicados e keymap só se houver mapa - (7defccb) - HttpAnimations
- modo de decoração rastreado e erro already_constructed - (6508b9d) - HttpAnimations
- erro de role ao destruir e announced limpo - (2cf0509) - HttpAnimations
- serials pendentes em conjunto e w/h validados - (145d8e8) - HttpAnimations
- set_selection exige serial de foco e leitura limitada a 1MB - (12f1cab) - HttpAnimations
- set_cursor valida serial e papel da superfície - (8fb8db2) - HttpAnimations
- commit recursivo cobre toda a subárvore sincronizada - (52a7388) - HttpAnimations
- offset de popup cru no nativo, clamp só no Dart - (5137265) - HttpAnimations
- fullscreen e resizing enviados no configure do toplevel - (0da72db) - HttpAnimations
- evento de tamanho inclui geo x/y e view alinha textura - (a2ed810) - HttpAnimations
- grab de ponteiro rastreia botões até todos liberados - (7491d36) - HttpAnimations
- done/presented após textura e frames destruídos no free - (7860276) - HttpAnimations
- região de input NULL distinta de vazia até o Dart - (de55d90) - HttpAnimations
- checa tipo dos objetos recebidos do cliente com instance_of - (c9da3a7) - HttpAnimations
- mutex na textura dmabuf contra race com populate - (d6187df) - HttpAnimations
- popup_done enviado a popups órfãos ao destruir o pai - (c3aa685) - HttpAnimations
- rejeita subsuperfície de descendente em get_subsurface - (28cea37) - HttpAnimations
- erro de protocolo ao colocar subsuperfície sobre si mesma - (b405faa) - HttpAnimations
- alocações de textura com clamp e try_malloc - (36a3051) - HttpAnimations
- valida formato e stride do buffer shm e ordena access - (69bb42e) - HttpAnimations
- rastreia attach solicitado para unmap com buffer nulo - (eb3f29a) - HttpAnimations
- libera buffer shm após a cópia no commit - (0c45f54) - HttpAnimations
- pipelines sobem test/failures e cobertura como artefatos - (2f41cbb) - HttpAnimations
- sessão exporta activation-env e lança apps em scope - (e929b81) - HttpAnimations
- caminho de crash reentra via cage ou sai com erro - (f903933) - HttpAnimations
- scripts de manutenção atualizam caches de desktop e ícones - (fa840ab) - HttpAnimations
- dependências, arquitetura e gitignore do pacote deb - (66daaf3) - HttpAnimations
- scripts de build usam caminho do próprio diretório - (7eca930) - HttpAnimations
- workflow sem release duplicado e watch checa todos os runs - (8120334) - HttpAnimations
- github-sync só em pushes na main e tags [skip ci] - (6ffaec5) - HttpAnimations
- github-sync só em pushes na main e tags [skip ci] - (a813721) - Devin
- seção de downloads com retry e link sempre visível - (fd89813) - HttpAnimations
- landing desliga listener e remove UpdateService sem uso - (f111359) - HttpAnimations
- busca só a página 1 para o último release - (35b7808) - HttpAnimations
- remove parâmetros mortos e corrige slider degenerado - (82a9cab) - HttpAnimations
- daemon de notificações loga falhas e fecha o bus - (0fa994b) - HttpAnimations
- valida assinatura do Notify antes dos casts - (e87ebbe) - HttpAnimations
- NotificationClosed emitido com motivo ao dispensar - (16f2c6b) - HttpAnimations
- protocolo Notify honra replaces_id, transient e ações - (6ba4e98) - HttpAnimations
- apps empacotados recebem store e backend reais - (29a2cd9) - HttpAnimations
- estado do app de configurações criado uma única vez - (067a609) - HttpAnimations
- alt+tab fecha ao soltar Alt e foco só no commit - (6679f77) - HttpAnimations
- backend CLI exportado condicionalmente para não quebrar web - (a659a28) - HttpAnimations
- launcher com atalho Ctrl+Space, recents e ranking persistido - (a1a79a2) - HttpAnimations
- UI do shell se ajusta a telas pequenas - (080f994) - HttpAnimations
- popups seguem estado do pai, fecham órfãos e respeitam tela - (fccef4e) - HttpAnimations
- leitura do sistema em paralelo e gammastep via stderr - (be30b34) - HttpAnimations
- toggles reconciliam estado após chamada ao backend - (c6b73d0) - HttpAnimations
- toggles persistidos são reaplicados no backend ao iniciar - (7fc121d) - HttpAnimations
- prefs gravam só quando mudam e notas debounce - (2f53bd2) - HttpAnimations
- sliders aplicam no backend só ao soltar o controle - (b45cc67) - HttpAnimations
- fixados do dock persistem após rebuild do shell - (1c29ab4) - HttpAnimations
- dock e banner escondem com janela em tela cheia - (dfd0ec8) - HttpAnimations
- overlays do shell são mutuamente exclusivos - (f5fada2) - HttpAnimations
- dock deduplica janelas por app e mostra apps internos - (7e8cae5) - HttpAnimations
- itens de menu Novo, títulos de janela e Sair funcionam de verdade - (ddc673e) - HttpAnimations
- logo, bateria e relógio na barra de menus agora funcionam - (a6705de) - HttpAnimations
- alphas de texto secundário e terciário sobem para contraste - (6099a7c) - HttpAnimations
- setas não movem seleção quando o campo de busca tem foco - (bfbe844) - HttpAnimations
- atualizações ignoram pré-lançamentos para usuários estáveis - (d1cd146) - HttpAnimations
- UpdateService exige versão, fecha http.Client e separa rótulo do botão - (98a7c22) - HttpAnimations
- bateria lida periodicamente a cada 60s - (7b25471) - HttpAnimations
- cartão de bateria usa leitura real do sistema - (8617bc6) - HttpAnimations
- menus de contexto com separadores e estilo de vidro compartilhado - (b48c52f) - HttpAnimations
- barra de menus com fundo translúcido desfocado - (4122662) - HttpAnimations
- título elidido e zoom só com botão primário - (e9b15a6) - HttpAnimations
- erro de lançamento exibido como notificação localizada - (750b3d7) - HttpAnimations
- promove foco para próxima janela ao fechar ou minimizar - (b95a2af) - HttpAnimations
- persistência de locale mantém country e script - (9cd0ed9) - HttpAnimations
- calculadora avalia operações encadeadas e normaliza display - (fad5631) - HttpAnimations
- guarda contra ciclo em pais transitórios - (ca4ed20) - HttpAnimations
- posição do menu limitada à borda da tela - (d401df7) - HttpAnimations
- títulos, meta SEO e manifest dos index.html web - (65c1343) - HttpAnimations
- textos separados por painel de rede e sem 'demo desktop' - (96caec4) - HttpAnimations
- traduções erradas em ga e zh - (2f092e2) - HttpAnimations
- sombra do OasisGlass renderiza fora do clip - (4e01c0c) - HttpAnimations
- papel de parede valida caminho e decodifica no tamanho da tela - (97a483f) - HttpAnimations
- troca de preset de papel de parede sempre notifica - (ab18c65) - HttpAnimations
- 未命名窗口标题回退走 ARB 本地化 - (5d86cb3) - HttpAnimations
- OLED 主题窗口与侧栏背景改为纯黑 - (55c5f62) - HttpAnimations
- 修复合成器对象生命周期导致的客户端协议错误 - (6749584) - HttpAnimations
#### Documentation
- corrige matriz de protocolos wayland desatualizada - (82aba6e) - HttpAnimations
#### Tests
- 补齐环境相关代码路径的行覆盖率 - (ea050f5) - calico
- integração, build nativo e packaging no CI - (a68a45a) - HttpAnimations
- goldens por locale e superfícies ausentes - (f6acbe9) - HttpAnimations
- contrato do canal Dart/nativo e configureAcked consumido - (02ed13b) - HttpAnimations
#### Refactoring
- configures de toplevel coalescidos em idle - (22f2bc7) - HttpAnimations
- notifyListeners agregado por turno de eventos - (167243e) - HttpAnimations
- constantes compartilhadas e syncApps fora do build - (67191d9) - HttpAnimations
#### Miscellaneous Chores
- corrigir lint no teste de instalação de atualização - (b25d70d) - Devin
- unificar versão 0.5.0 em todos os pubspecs - (aba9410) - HttpAnimations
- remove codegen de tablet-unstable-v2 sem implementação - (05e92b6) - HttpAnimations
- pub get único na raiz do workspace e dev.sh - (bd23c36) - HttpAnimations
- remove empacotamento flatpak - (7ab04d2) - HttpAnimations
- remove ícones e chave ARB morta - (0332b5b) - HttpAnimations

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