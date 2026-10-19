# 项目开发规则

所有成员与 AI 开工先读 docs/design/2026-10-18-项目共识与目标.md，再读 docs/文档导航.md、相关模块设计和当前任务卡。正式目标是 Steam 跨网络组队游玩；ENet/LAN 仅作开发验证，不得替代 Steam 双机异地验收。项目根即 Godot 资源根，不新建第二个 game/project.godot。
运行文件/目录使用英文 snake_case；中文文档放 docs，分类目录使用英文，文件名带 YYYY-MM-DD，维护任务状态及验证记录。
UI 只提出意图；共享状态由房主确认。纯背包规则不引用地图或 HUD。物理节点不是纯表现层。
按功能目录改动；app/main.gd、project.godot、网络协议和地图由当次集成人协调，不多人同目录切分支。
保留原有 addons/godot_ai，除非任务明确要求不调整插件。
代码与文本场景入 Git；美术、二进制、缓存和工具个人设置不上传，不用 LFS 绕过。保留脚本 .uid。
分别报告静态、headless、可见界面、同机多进程、双机异地验证；未运行不得写通过。
有本地 Git 时可以按完成的小功能提交。远端交付需在用户任务授权范围内；成员都可合 main，不设角色审核门槛，先同步 rebase 并验证，禁止强推 main。

## 每次合并 main 前必须同步（2026-10-19）

- 每次将功能分支合并到 main 前，必须先成功执行 `git fetch origin`，取得当次最新的 `origin/main`；不能仅检查已有的远端跟踪记录，也不能用旧的本地 main 代替。即使用户只要求本地合并、不推送远程，也必须执行此步骤。
- 保存本任务的本地提交后，在功能分支执行 `git rebase origin/main`；不在 main 上 rebase，不重写队友共用分支。存在无关未提交修改时保留原状，必要时在独立工作目录集成，不全量 stash 或丢弃成果。
- 逐项处理冲突并检查最终差异；根据远程新增内容和冲突处理补做相关验证。同步、rebase 或必要验证失败时不得继续合并，须报告具体阻塞，不能把旧测试结果当作新组合已通过。
- 验证完成后再快进合并到本地 main，保留本地主线已有提交；发生分叉时先在功能集成分支妥善纳入，不强制重置 main。交接记录 fetch 取得的远端基线、rebase 后提交及验证结果。
- 远程推送仍需用户授权。推送若因队友更新 main 被拒绝，重新 fetch → 在功能分支 rebase → 补验 → 普通推送，禁止强推 main。

## Skill 使用约定

AI 先读项目共识、相关设计和任务，再按实际工作选择 skill，并读取对应的 `SKILL.md`，不能只凭技能名宣称已遵循流程。用户显式点名的 skill 优先使用；一般局部任务不必串行调用全部技能。

| 工作类型 | Skill |
| --- | --- |
| 需求拆分、分工边界与最小接口约定 | `game-task-design` |
| 跨模块架构、状态归属与依赖调整 | `godot-architecture-design` |
| 工程初始化、目录整理和资源迁移 | `godot-project-setup` |
| 功能实现、Bug 修复与已有模块调整 | `godot-module-dev` |
| 对指定提交或差异做只读审核 | `godot-code-review` |
| 提交、同步主线、合并及远端交付 | `github-pr-handoff` |


- 成员可在请求中显式写 `$godot-module-dev`、`$godot-code-review` 等，并附当前任务、文件范围、设计链接和验收要求。审核默认只读，不因调用审核技能就修复、提交或合并。
- Skill 安装在成员各自的 AI 工具环境中，不是 Godot 插件，也不随游戏运行。按当前环境提供的技能清单定位 `SKILL.md`，不要把某位成员的 `C:/Users/...` 绝对路径写作团队必需路径；拉取本仓库不代表技能已安装。
- 本机缺少指定技能时先说明缺项，不虚构已执行。能够继续的工作按项目规则推进；必须依赖该技能才能完成的步骤明确列为未完成。
- 用户明确要求和当前项目约定优先于技能默认建议。技能不能扩大任务授权：默认本地提交，远程推送仍需用户授权；本项目根即资源根，素材继续外置，保留现有插件与无关修改。
- 分工和交接上下文见 [团队分工与协作约定](docs/design/2026-10-18-团队分工与协作约定.md)。

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
