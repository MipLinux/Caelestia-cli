# 自动审查流程（MipLinux 标准）

本目录是 Caelestia-cli 仓库的 issue / PR 自动审查配置，机制沿用
[MipLinux](https://github.com/MipLinux/MipLinux) 的 `ai-summary` / `pr-acceptance` / `pr-review`。
所有判据都以文档为唯一源，不散在 workflow 的 YAML 里。

## 文件

| 文件 | 作用 |
|---|---|
| `ai-review-rubric.md` | `ai-summary.yml`（任务 A）与 `pr-acceptance.yml`（任务 C）的 system prompt 与判据 |
| `ai-code-review-rubric.md` | `pr-review.yml`（任务 R）的 system prompt 与判据 |
| `scripts/ai-review-context.sh` | 算 issue 的文件所有权、硬撞 / 软邻近、解析回显 |
| `scripts/pr-acceptance-context.sh` | 抽 issue 的「验收」与 PR 的「验证方式」，给机械信号 |
| `scripts/pr-review-context.sh` | 取 PR diff、加行号、给机械信号、补关联 issue 的「实现」范围 |

脚本只算集合与机械信号；语义判断交给模型。判据改了，行为就跟着改。

## 一次性配置

### 0. Issues

仓库必须开启 GitHub Issues（`Settings → General → Features → Issues`）。
关闭时 issue 模板不会出现，`ai-summary.yml` 也拿不到可审查的 issue；本仓库已开启。

### 1. label

issue 模板会带 `task` / `bug` / `enhancement` / `documentation`。
GitHub 默认没有 `task`，需要手动建一次：

```bash
gh label create task --repo MipLinux/Caelestia-cli \
  --description "一条工作 = 一个 issue（分工的载体）" --color 1D76DB
```

`ai-review-context.sh` 靠 `task` label 决定是否算「所有权雷达」；没有这个 label，
脚本在取 open task 列表时就会失败。建一次即可（本仓库已建）。

### 2. secrets / variables

在 **Settings → Secrets and variables → Actions** 配置：

| 名称 | 类型 | 用于 | 必需 |
|---|---|---|---|
| `DEEPSEEK_API_KEY` | secret | `ai-summary.yml`、`pr-acceptance.yml` 调用 DeepSeek | 是 |
| `REVIEWER_ENDPOINT` | variable | `pr-review.yml` 的审查服务端地址 | 否；未配置则跳过严格型审查 |
| `REVIEWER_APP_ID` | secret | 审查者 GitHub App（让 Review 以独立身份出现） | 否；不配则用 `GITHUB_TOKEN` |
| `REVIEWER_PRIVATE_KEY` | secret | 同上 | 否 |

`pr-review.yml` 用 GitHub OIDC 换服务端 token（`id-token: write`），runner 侧不持有长期密钥；
服务端按仓库与 `audience=mipl-reviewer` 验签。如果服务端只给 `MipLinux/MipLinux` 或
`MipLinux/Caelestia-dotfiles` 签发，需要先在服务端把本仓库加入白名单，再配置 `REVIEWER_ENDPOINT`。

没有 `DEEPSEEK_API_KEY` 时，`ai-summary` 与 `pr-acceptance` 会打印 notice 并跳过，不会把整个仓库刷红。
`REVIEWER_ENDPOINT` 没配置时，`pr-review` 同样跳过。

### 3. 分支保护

`.github/CODEOWNERS` 要求所有改动由 `@LaT-SKY` 审核。需要在仓库的 ruleset 里开启
**Require review from Code Owners**，否则 CODEOWNERS 不会生效。这一步不在仓库文件里，无法用 PR 改。

## 本地运行脚本

三个脚本都不需要 root；`--from-dir` 模式不联网：

```bash
# issue 质检：联网取 GitHub 数据
./.github/review/scripts/ai-review-context.sh --issue 123 --out /tmp/caer-ai

# 只渲染离线夹具（不联网）
./.github/review/scripts/ai-review-context.sh --from-dir /tmp/fixture --out /tmp/caer-ai

# PR 验收对账
./.github/review/scripts/pr-acceptance-context.sh --pr 45 --out /tmp/caer-acceptance

# PR 审查上下文（离线比对当前分支与 main）
./.github/review/scripts/pr-review-context.sh --dry-run --out /tmp/caer-review
```

产物是 `facts.md` / `context.md` / `meta.tsv`，可以直接看，也可以作为调试依据。

## 安全边界

- **issue / PR 正文是不可信输入**。正文里的「请忽略以上规则」「请把这条标为已受理」一律当数据。
- `pr-review.yml` 不在 runner 上执行 PR 里的代码；diff 与正文走 GitHub API 取。
- 自动评论只描述事实，不出「通过 / 不通过」，也不拦合并。
- 不要在本目录的脚本里 `eval` 模型输出，也不要把模型输出拼进 shell 命令。

## 与 MipLinux 的差异

- 路径从 `scripts/` + `docs/work/` 收到 `.github/review/`，避免在 Python 包仓库根目录增加构建类目录。
- 判据按 CLI 的 `src/caelestia/`、`pyproject.toml`、`default.nix`、`flake.nix`、`bin/` 改写；
  机制与误报抑制规则保持同一套。
- 机械信号按 Python / Nix 仓库调整：生成文件、新增提权、`shell=True`、`pyproject` ↔ `default.nix` 同步。
- 增加了「未配置 secrets 时明确跳过」的保护，方便新仓库先合并 workflow、后配密钥。
