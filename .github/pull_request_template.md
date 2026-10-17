<!--
main 受保护：PR 需要至少 1 个 approving review，且必须包含 code owner（@LaT-SKY）的审核。
本文件里的 HTML 注释不会显示在渲染后的正文中，但下面的标题请保留。
填不出来的项请写「未验证」或「N/A」，不要留空。
-->

## 改了什么

<!-- 一两句话，列出涉及的子命令 / 文件。 -->

## 为什么

<!-- 解决什么问题、依据哪条 issue 或已有结论。关联 issue 请在最下方写 Closes #编号。 -->

## 验证方式

<!-- 只写真实跑过的命令与结果。纯文档改动可整段写 N/A。 -->

| 项 | 结果 |
|---|---|
| 静态检查 | 例如 `python -m compileall -q src`、`PYTHONPATH=src python -m caelestia -h`、`git diff --check` |
| 子命令 / 行为 | 例如 `./bin/caelestia scheme list -n`；需要桌面会话的写「未实测」 |
| 打包 | 例如 `python -m build --wheel`、`nix build .#caelestia-cli` |
| 安装 / 更新 | 例如在测试 HOME 用 `bin/test_in_iso_env.sh` 跑一次 `caelestia install` / `update` |

## 检查项

- [ ] 本次 PR 只做一件事（例如没有把「搬文件」和「改文件」混在一起）
- [ ] 改动范围与关联 issue 的「实现」一致
- [ ] 新增 / 删除运行时依赖时已同步 `pyproject.toml` 与 `default.nix`
- [ ] 新增子命令 / 参数时已更新 `parser.py`、help 文本、README 与 fish 补全
- [ ] 没有提交生成文件（`dist/`、`result`、`flake.lock`、`src/caelestia/data/emojis.txt`、`__pycache__/`）或任何密钥
- [ ] 没有破坏 `install` / `update` 的备份、确认与状态文件语义
- [ ] 改了行为或结论时，相关文档已同步

<!-- 关联 Issue 写 Closes #编号，合并后会自动关闭。 -->
