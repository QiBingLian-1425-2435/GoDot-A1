# 雾灯旅店 · 合作搜集撤离

更新：2026-10-18。队长初稿已迁入当前按功能分工的骨架；工程根仍为 Godot 资源根，入口 `app/main.tscn`。固定斜俯视、单层 3D 旅店、2D 纸片角色。

## 快速开始

1. 源码开发：先恢复外置素材并执行 `python tools/setup_steam.py`，再用 Godot **4.5.2 标准版**打开根目录 `project.godot`，等待导入，按 F5。收到完整 Windows 测试包的成员直接解压运行 `start_steam.cmd`，无需安装 Godot。
2. 点击“点亮提灯 · 单人出发”，AI 队友薇拉会跟随、搜集、救援和撤离。
3. WASD / 方向键按屏幕方向移动；E 拾取、搜尸，长按 E 救援；行囊中的 ↓ 丢弃；Tab 切换行囊/队伍；F1 / Esc 打开关闭手册；M 静音。
4. 背包 12 kg，一局 6 分钟；进入右前方绿灯圈停留 4 秒撤离。个人撤离后等待队友，结算后“再探一局”。

包含怪物巡逻/追逐、倒地救援、死亡遗留行囊、受限观战、自愿附身共享视角、地图、音效和重开。参数继承初稿，仍可调整。

Steam 开发联机（App ID 480）：各自登录 Steam 并互加好友，使用同一测试包。房主创建好友房间，成员接受邀请或填房间号加入，2–5 人由房主开始；开局后锁加入。房主撤离后必须保持程序运行，退出会关闭房间，无房主迁移或重连。ENet 局域网仅作开发选项，切换后填 IP（同机 127.0.0.1，UDP 24567）。

## 正式目标与当前验证

先读[项目共识与目标](docs/design/2026-10-18-项目共识与目标.md)。**Steam SDK、好友大厅和原生 SteamMultiplayerPeer 已接入，并生成独立 Windows 测试包；双账号双机异地尚未验收。**

Steam 打包、实际分层结果和成员异地步骤见[Steam 验证与分发](docs/verification/2026-10-18-Steam联机验证与分发.md)。构建命令为 `python tools/build_steam.py --godot <4.5.2_console.exe>`，ZIP 位于本地忽略目录 build。

迁移验证及限制见[迁移验证记录](docs/verification/2026-10-18-初稿迁移验证.md)，初稿旧测试报告不作为本次通过证据。双机异地和五名真人试玩需要另行验收。

## 分工入口

- `app/`：组合主场景、输入意图、网络会话。
- `features/`：match、inventory、player、enemies、rescue、extraction、companions、possession、navigation、audio。
- `worlds/lantern_inn/`：旅店几何、真实碰撞、镜头和快照表现。
- `ui/`：HUD 和控件，只发意图。
- `tests/`：规则、AI、主场景物理、可见界面和真实多进程测试。

[结构与接口](docs/design/2026-10-18-原型范围与模块边界.md) · [项目结构](docs/design/2026-10-18-项目结构说明.md) · [迁移对照与交接](docs/plans/2026-10-18-队长初稿迁移与复刻.md) · [任务看板](docs/tasks/2026-10-18-任务跟进.md) · [文档导航](docs/文档导航.md)

## 素材与代码交接

本机已还原初稿三张角色图和七个音频。美术、音频、导入缓存、导出包仍不入 Git；清单、SHA256 和还原方法见[外置素材](docs/assets/2026-10-18-外置素材与还原.md)。复制代码到其他电脑后须同时取得外置素材，并保留原有 `addons/godot_ai` 插件。

参考工程与迁移前骨架备份留在 `.references_code/`，通过 `.gdignore` 排除，运行不读取该目录。2026-10-18 已初始化本地 Git（main），代码与文本场景保留，素材和导出物排除；远端为 [MnivL/GoDot-A1](https://github.com/MnivL/GoDot-A1)，main 为团队取代码的入口。首次上传通过 GitHub 连接器导入源码快照，原本地历史保留于 archive/pre-upload-main 和 chore/github-initial-upload；素材仍由共享包还原。提交前运行 `python tools/check_git_files.py`，检查暂存文件不含忽略文件或大于等于 10 MiB 的文件。本机已接入 pre-commit 检查；Git hooks 不随 clone 自动安装，成员可参照[Git 检查记录](docs/verification/2026-10-18-Git初始化与忽略检查.md)配置。
