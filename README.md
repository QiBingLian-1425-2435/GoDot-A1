# A1 · 地下基地合作原型

更新：2026-10-19。以队长新 Demo `.references_code/123(1)/123` 为功能与体验基准，迁入当前功能目录。工程根是唯一 Godot 资源根，主场景 `app/main.tscn`，Godot **4.5.2 标准版 / Windows x64**。

## 开始开发与运行

直接打开根目录 project.godot，等待导入后 **F5**。本轮基地、鸭角色、动画、物品图标与音效均由程序或文本资源生成，单机无需旧旅店/Game1 的外置素材。原有 addons/godot_ai 保留。

首次测试 Steam 时先打开并登录 Steam，再执行一次 `python tools/setup_steam.py` 恢复固定 GodotSteam 4.23.1，或向队友取得完整 addons/godotsteam 文件夹并放在相同位置；之后重新打开 Godot，即可一直 F5。脚本只用 Python 标准库，不需要 uv、虚拟环境或 pip。没有扩展也可体验单人/IP 基地。

开始画面点击后“继续游戏”进入单人基地；Steam 联机创建好友房间后直接进入基地，Esc 菜单中邀请或复制房间号；队友从菜单 Steam 联机加入。含房主 **最多 5 人**，各自不同 Steam 账号、同版本包。ENet/IP 直连保留作开发验证，不作为异地 Steam 已通过。

## 已迁入功能

- 基地卧室/医疗、工作台、仓库、商人、地图桌、出口提示与靶场。
- 24 格背包、48 格仓库、装备、堆叠/拆分/拖拽/Ctrl 快存取、消耗、丢弃拾取、负重减速。
- WASD 移动、Shift 冲刺、C 蹲行、鼠标瞄准、左键射击、右键瞄准、R 装填、1/2 换枪、4/5 医疗饮水。
- E 设施互动/拾取，Tab/I 背包，Esc 菜单，滚轮缩放，F5 手动保存，F11 全屏。弹匣按武器分别保存；靶场有遮挡和命中反馈，基地没有玩家互伤。
- 可编辑骨骼鸭角色与 14 种动画、NPC 待机、程序音效；独立动作预览场景 `features/player/animation/animation_preview.tscn` 可 F6。
- 单人/房主每 30 秒及回菜单/退出保存到独立 `user://a1_bunker_profile_v1.json`；客机物资仅本次会话保留。不读取原版游戏或旧 Demo 存档。

当前是基地与核心操作原型，**未实现野外地图、任务战役、旧旅店怪物/救援/附身或原版鸭科夫完整内容**。旧旅店代码已退出入口并存于 Git 历史/本机参考备份；之前未提交的人物动画修改保持原样，不被新入口加载。

## 模块与验证

[目录和接口](docs/design/2026-10-18-项目结构说明.md) · [迁移计划与差异](docs/plans/2026-10-19-地下基地Demo迁移.md) · [本轮验证](docs/verification/2026-10-19-地下基地迁移验证.md) · [文档导航](docs/文档导航.md)

```powershell
python tools/run_base_tests.py --suite all
python tools/run_base_tests.py --suite fast --steam-live
python tools/build_steam.py --godot '<Godot 4.5.2 console.exe绝对路径>'
```

测试和打包工具可传 --godot；默认路径只是本机安装位置。单独网络回归也可执行 tools/run_network_tests.ps1。源码测试位于 tests/base，旧 tests 根目录的旅店测试已退役。

打包工具依据 docs/dependencies/2026-10-19-bunker_sources.json 只收集当前入口依赖，不复制旧素材、参考工程或未提交的旧人物脚本。输出 build/bunker_a1_steam_<build_id>.zip；所有成员须使用同一构建，旧旅店包/参考 Demo 包不兼容。DLL、素材、缓存和 ZIP 不入 Git，不用 LFS。Steam App ID 480 仅开发测试，双账号异地与五人 Steam 仍需实际验收。
