# 协作说明

本仓库是 MipLinux 维护的 Caelestia CLI fork：`caelestia` 安装 / 更新命令与周边子命令。
它不包含 shell 本体，也不包含 dotfiles 配置。

| 仓库 | 内容 |
|---|---|
| [`MipLinux/Caelestia-cli`](https://github.com/MipLinux/Caelestia-cli) | 本仓库：`caelestia` 命令、安装 / 更新、打包 |
| [`MipLinux/Caelestia-shell`](https://github.com/MipLinux/Caelestia-shell) | 顶栏、面板、启动器等 shell 本体（fork） |
| [`MipLinux/Caelestia-dotfiles`](https://github.com/MipLinux/Caelestia-dotfiles) | Hyprland / Wayland 配置与主题（fork） |
| [`caelestia-dots/cli`](https://github.com/caelestia-dots/cli) | CLI 上游 |
| [`MipLinux/MipLinux`](https://github.com/MipLinux/MipLinux) | 发行版构建仓库 |

---

## 先读这个

| 顺序 | 文档 | 内容 |
|---|---|---|
| 1 | [`README.md`](../README.md) | 安装、更新、子命令、用户模板与配置 |
| 2 | [`pyproject.toml`](../pyproject.toml) | Python 包、入口点、依赖与构建后端 |
| 3 | [`default.nix`](../default.nix) / [`flake.nix`](../flake.nix) | Nix 打包、`patchPhase` 与依赖 |
| 4 | [`.github/review/README.md`](review/README.md) | 自动审查流程与所需 secrets / variables |
| 5 | [`.github/pull_request_template.md`](pull_request_template.md) | PR 必须填的三节 |

**不要**把本仓库当成 shell 或 dotfiles 仓库来改。shell 行为问题提到
[`Caelestia-shell`](https://github.com/MipLinux/Caelestia-shell)；配置问题提到
[`Caelestia-dotfiles`](https://github.com/MipLinux/Caelestia-dotfiles)。

---

## 工作方式

### 一条工作 = 一个 issue

功能、重构、需要跨文件协调的改动，先在 [Issues](https://github.com/MipLinux/Caelestia-cli/issues?q=label%3Atask)
开一条带 `task` label 的工作 issue，写清「目标 / 实现 / 验收 / 回报 / 依赖」。
`assignee` 就是受理人；没有对应 issue 的改动，维护者可以要求先补。

小修、纯文档改动可以直接开 PR，但仍要走模板里的「验证方式」。

### 上游同步

`main` 跟踪上游，只保留最小的 MipLinux 文档 / 许可声明；功能 / 行为改动放 `mip` 分支 / tag，
PR 描述里记录上游 base commit。不重写历史；dots / shell / cli 与 Quickshell 的 pin 一起对齐，
不单独升级其中一个。

### 分支

功能 / 行为改动从 `mip` 分支或维护者指定的 `mip-*` tag 切；只有文档改动从 `main` 切。

```bash
# 功能：从 mip 切
git fetch origin
git switch mip
git pull --ff-only
git switch -c feat/<主题>     # 修 Bug 用 fix/<主题>

# 功能：从维护者指定的 mip-* tag 切
git fetch --tags origin
git switch -c feat/<主题> <mip-tag>

# 仅文档 / 纯文案
git switch main
git pull --ff-only
git switch -c docs/<主题>
```

`mip` 不存在时，向维护者要指定的 tag；不要从 `main` 直接开功能分支。
分支不在目标分支上、或拉取不是快进 → 停下来问维护者，**不要**自行 `merge` / `rebase` / `reset --hard`。

### 提交信息

第一行用 `模块: 做了什么`，例如：

```
update: dots 仓库不可达时给出可操作的错误

原先直接抛栈，用户看不出是网络问题还是配置问题。改为捕获 SourceError 并提示重试。
```

- 模块名尽量与子命令 / 目录一致：`install`、`update`、`scheme`、`shell`、`screenshot`、`record`、
  `clipboard`、`emoji`、`wallpaper`、`toggle`、`resizer`、`parser`、`packaging`、`nix`、`docs`、`ci`。
- 一次提交只做一件事；多个改动时，标题写影响最大的那个，其余放正文。

### PR

PR 描述按模板写三件事：

1. **改了什么** —— 涉及的命令 / 文件
2. **为什么** —— 解决什么问题，关联 issue 写 `Closes #N`
3. **验证方式** —— 只写真实跑过的命令与结果；没跑的写「未验证」

`main` 受保护：PR 需要至少 1 个 approving review，且必须包含 code owner（`@LaT-SKY`）的审核。

---

## 提交前自检

先做静态检查（不依赖图形会话）：

```bash
python -m compileall -q src
PYTHONPATH=src python -m caelestia -h
PYTHONPATH=src python -m caelestia scheme list -n
git diff --check
bash -n bin/caelestia bin/test_in_iso_env.sh
```

再按改动范围做实际验证：

- **命令 / 参数**：`./bin/caelestia <子命令> -h`，确认 help 与解析都正常；
- **配色 / 主题**：`./bin/caelestia scheme list`、`scheme get`、`scheme set -n <name>`，确认状态文件与渲染输出；
- **安装 / 更新**：在隔离的测试 HOME 里用 `bin/test_in_iso_env.sh` 跑一次 `caelestia install` / `update`，
  不要在真实配置上直接试；
- **截图 / 录屏 / 剪贴板 / 壁纸**：需要 Wayland 会话，写清「未实测」或给出实际观察结果；
- **shell 控制**：需要 Quickshell 正在运行，写清环境与 `caelestia shell -s` / `-l` 的输出；
- **打包**：`python -m build --wheel`；有 Nix 时 `nix build .#caelestia-cli`。

**不要把「静态检查通过」写成「已验证」**；也不要声称跑过需要图形会话、但实际没跑的命令。

---

## 自动审查

仓库启用了四条 workflow：

| workflow | 触发 | 作用 |
|---|---|---|
| `auto-assign.yml` | issue / PR 创建 | 自动分给维护者 |
| `ai-summary.yml` | issue 创建 / 编辑 | 受理前质检、所有权雷达、查重、引用有效性 |
| `pr-acceptance.yml` | PR 打开 / 标记 ready | 把 issue 的「验收」与 PR 的「验证方式」对账 |
| `pr-review.yml` | 维护者评论 `/mipl-review`（或 `/caelestia-review`） | 严格型代码与红线审查 |

判据在 [`.github/review/`](review/)；所需 secrets / variables 见 [review/README.md](review/README.md)。
自动审查只描述事实，不出「通过 / 不通过」，也不拦合并 —— 合并判断仍由人做。

---

## 报告问题

- **CLI / 安装 / 打包 Bug** → [`bug-report.yml`](ISSUE_TEMPLATE/bug-report.yml)
- **文档与实际不符** → [`documentation.yml`](ISSUE_TEMPLATE/documentation.yml)
- **新功能 / 改进** → [`feature-request.yml`](ISSUE_TEMPLATE/feature-request.yml)
- **需要跨文件协调的工作** → [`task.yml`](ISSUE_TEMPLATE/task.yml)（label `task`）
- **安全漏洞** → [MipLinux SECURITY.md](https://github.com/MipLinux/.github/blob/main/SECURITY.md)，不要在公开 Issue 里披露

---

## 许可

本仓库以 **GPL-3.0-only** 发布（上游 Caelestia 的 LICENSE 为 GPLv3），全文见 [LICENSE](../LICENSE)，
版权与修改声明见 [NOTICE.md](../NOTICE.md)。提交即表示你同意以同一许可证发布你的贡献；
修改上游文件时保留原版权声明并标明改动。
