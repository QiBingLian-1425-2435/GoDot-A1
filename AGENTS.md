# 项目开发规则

所有成员与 AI 开工先读 docs/design/2026-10-18-项目共识与目标.md，再读 docs/文档导航.md、相关模块设计和当前任务卡。正式目标是 Steam 跨网络组队游玩；ENet/LAN 仅作开发验证，不得替代 Steam 双机异地验收。项目根即 Godot 资源根，不新建第二个 game/project.godot。
运行文件/目录使用英文 snake_case；中文文档放 docs，分类目录使用英文，文件名带 YYYY-MM-DD，维护任务状态及验证记录。
UI 只提出意图；共享状态由房主确认。纯背包规则不引用地图或 HUD。物理节点不是纯表现层。
按功能目录改动；app/main.gd、project.godot、网络协议和地图由当次集成人协调，不多人同目录切分支。
保留原有 addons/godot_ai，除非任务明确要求不调整插件。
代码与文本场景入 Git；美术、二进制、缓存和工具个人设置不上传，不用 LFS 绕过。保留脚本 .uid。
分别报告静态、headless、可见界面、同机多进程、双机异地验证；未运行不得写通过。
有本地 Git 时可以按完成的小功能提交。远端交付需在用户任务授权范围内；成员都可合 main，不设角色审核门槛，先同步 rebase 并验证，禁止强推 main。

## 常用运行与验证入口

- 使用 Godot 4.5.2 标准版，打开根目录 `project.godot`，按 F5 运行主场景；F6 仅运行当前场景，不替代主场景联机验证。
- 首次拉取或缺少 Steam 扩展时，在项目根执行 `python tools/setup_steam.py`，按固定依赖清单还原 `addons/godotsteam/`。脚本只用 Python 3 标准库，无需 uv、虚拟环境或 pip；版本完整且一致时无需重复安装。
- Steam 联机前先启动并登录 Steam；当前使用测试 App ID 480，队员须使用相同构建。普通 F5 无需先经过 Python 启动，Python 用于依赖还原、测试和打包。
- 以下命令均在项目根执行。测试与打包脚本的默认 Godot 路径属于当前机器，其他成员使用 `--godot "实际的 Godot 可执行文件路径"` 覆盖。

| 用途 | 命令 |
| --- | --- |
| 快速规则与 headless 组合验证 | `python tools/run_base_tests.py --suite fast` |
| 可见场景与界面验证 | `python tools/run_base_tests.py --suite ui` |
| 同机多进程网络验证 | `python tools/run_base_tests.py --suite network` |
| 全部自动测试及真实 Steam 单账号房主检查 | `python tools/run_base_tests.py --suite all --steam-live` |
| 生成 Windows Steam 测试包 | `python tools/build_steam.py` |

真实 Steam 检查需要客户端登录，会创建测试房间；不能证明双账号双机异地成功。测试日志在 `artifacts/base_tests/`，打包输出在 `build/`，均不提交 Git。详细步骤及当前结果见 [文档导航](docs/文档导航.md)、[基地迁移验证](docs/verification/2026-10-19-地下基地迁移验证.md)与 [Steam 验证与分发](docs/verification/2026-10-18-Steam联机验证与分发.md)。

## 外置依赖与提交范围

- `assets/` 为外置素材，`addons/` 为外置插件；遵循现有忽略规则，不强行加入 Git。GodotSteam 用上述脚本还原，原有 `godot_ai` 保留；素材还原见 [外置素材说明](docs/assets/2026-10-18-外置素材与还原.md)。
- 当前基地主要使用程序生成表现和 Git 内文本资源；修改或新增运行依赖时同步维护 `docs/dependencies/2026-10-19-bunker_sources.json`，避免导出包漏文件。
- `.references_code/` 是可清理的参考与备份目录，正式运行、测试、打包不得依赖其中的文件。`artifacts/dependencies/` 是下载缓存，不是成员必须复制的工程目录。
- 默认仅提交本任务本地版本；合并 main、远程推送按用户当次授权范围执行。暂存明确文件，保留已有无关修改，导出包及素材通过仓库外渠道分发。
