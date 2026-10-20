#!/usr/bin/env bash
# PR 代码审查上下文生成器 —— 提取 git diff、计算机械信号、组装模型输入。
#
# 用法：
#   ./.github/review/scripts/pr-review-context.sh --pr <N> [--out <DIR>]    # 联网取 GitHub PR 数据与 diff
#   ./.github/review/scripts/pr-review-context.sh --dry-run [--out <DIR>]  # 离线比对本地分支与 main 的 diff（用于自检）
#
# 产物（写入 --out，默认 /tmp/caelestia-pr-review）：
#   meta.tsv       PR 基础元数据（pr号、head、base、标题等）
#   context.md     组装好、喂给模型的完整上下文（含带行号的 diff 与机械告警）
#
# 不需要 root。退出码：0 = 正常；1 = 参数错误或执行失败。

set -euo pipefail
export LC_ALL=C

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SELF_DIR/../../.." && pwd)

MODE=""
PR=""
OUT_DIR=${CAELESTIA_PR_REVIEW_OUT:-/tmp/caelestia-pr-review}

# Print the script's usage header to stdout.
usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)
      [ $# -ge 2 ] || { echo "错误：--pr 需要一个编号" >&2; exit 1; }
      MODE="pr"
      PR=$2
      case "$PR" in ''|*[!0-9]*) echo "错误：--pr 必须是纯数字" >&2; exit 1 ;; esac
      shift 2
      ;;
    --dry-run)
      MODE="dryrun"
      shift
      ;;
    --out)
      [ $# -ge 2 ] || { echo "错误：--out 需要一个目录" >&2; exit 1; }
      OUT_DIR=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "错误：不认识参数 $1（见 --help）" >&2
      exit 1
      ;;
  esac
done

[ -n "$MODE" ] || { usage; exit 1; }

mkdir -p "$OUT_DIR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Write an annotated unified diff from the file at $1 to stdout.
# Added and context lines use new-file line numbers; deletions stay unnumbered.
# Return awk's exit status, including failures to read the input file.
annotate_diff() {
  local diff_file=$1
  awk '
    /^diff --git / {
      in_hunk = 0;
      next;
    }
    /^\+\+\+ b\// {
      file = substr($0, 7);
      print "\n========================================================";
      print "文件: " file;
      print "========================================================";
      next;
    }
    /^@@ / {
      # 匹配 @@ -old,len +new,len @@
      split($3, arr, ",");
      new_line = substr(arr[1], 2) + 0;
      in_hunk = 1;
      print $0;
      next;
    }
    in_hunk {
      if ($0 ~ /^\\/) {
        # 处理类似 \ No newline at end of file，不打行号也不自增
        print $0;
      } else if ($0 ~ /^\+/) {
        printf "[L%d] %s\n", new_line, $0;
        new_line++;
      } else if ($0 ~ /^-/) {
        print $0;
      } else {
        printf "[L%d] %s\n", new_line, $0;
        new_line++;
      }
    }
  ' "$diff_file"
}

# Scan added lines in the unified diff at $1 for command and quoting warnings.
# Write matching lines with diff-file line numbers to stdout, or a no-match message.
# Grep errors are treated as no matches, so the message does not guarantee clean input.
detect_mechanical_signals() {
  local diff_file=$1
  local signals=()

  # 1. 文件头：生成的 / CI 维护的文件不应由 PR 手改
  local generated
  generated=$(grep -En '^[+]{3} b/(dist/|result(/|$)|flake\.lock|src/caelestia/data/emojis\.txt|.*__pycache__/|.*\.pyc$)' "$diff_file" || true)
  if [ -n "$generated" ]; then
    signals+=("发现改动生成文件或 CI 维护文件（flake.lock / emojis.txt / dist / 缓存不应手改）：\n$generated")
  fi

  # 2. 新增行里的 sudo / pkexec：CLI 只在已文档化的包管理 / 主题路径用提权，
  #    新增提权要说明原因并保留真实错误码。
  local raw_sudo
  raw_sudo=$(grep -En '^[+][[:space:]]*(sudo|pkexec)[[:space:]]+' "$diff_file" || true)
  if [ -n "$raw_sudo" ]; then
    signals+=("发现新增提权调用（确认属于既有包管理 / 主题路径，不要新增隐式提权）：\n$raw_sudo")
  fi

  # 3. 写死家目录 / 机器相关路径
  local hardcoded_home
  hardcoded_home=$(grep -En '^[+].*(/home/[A-Za-z0-9._-]+|/Users/[A-Za-z0-9._-]+)' "$diff_file" || true)
  if [ -n "$hardcoded_home" ]; then
    signals+=("发现写死的家目录 / 机器路径（应使用 \$HOME / \$XDG_CONFIG_HOME 或仓库相对路径）：\n$hardcoded_home")
  fi

  # 4. 文件操作命令中路径变量未加双引号
  local unquoted_vars
  unquoted_vars=$(grep -En '^[+][[:space:]]*(rm|cp|mv|cd|cat|install|mkdir|tee)[[:space:]]+[^"'"'"'#]*\$(HOME|XDG_CONFIG_HOME|XDG_DATA_HOME|XDG_STATE_HOME|XDG_CACHE_HOME|XDG_RUNTIME_DIR|CAELESTIA_DOTS|DOTS|REPO)([[:space:]/]|$)' "$diff_file" \
    | grep -vE '^[0-9]+:[+][[:space:]]*[-*#]' || true)
  if [ -n "$unquoted_vars" ]; then
    signals+=("发现文件操作命令中路径变量未加双引号保护：\n$unquoted_vars")
  fi

  # 5. 明显的密钥 / token
  local secrets
  secrets=$(grep -En '^[+].*(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{16,}|BEGIN [A-Z ]*PRIVATE KEY)' "$diff_file" || true)
  if [ -n "$secrets" ]; then
    signals+=("发现疑似密钥 / 私钥（必须移除并轮换）：\n$secrets")
  fi

  # 6. curl | sh 一类不可审计的安装方式
  local curl_pipe
  curl_pipe=$(grep -En '^[+].*(curl|wget)[^|]*\|[[:space:]]*(ba)?sh' "$diff_file" \
    | grep -vE '^[0-9]+:[+][[:space:]]*[-*#]' || true)
  if [ -n "$curl_pipe" ]; then
    signals+=("发现 curl/wget 管道到 shell（不可审计，应改为显式下载并校验）：\n$curl_pipe")
  fi

  # 7. Python 里的 shell 字符串执行：新增处要确认输入来源可信
  local py_shell
  py_shell=$(grep -En '^[+].*(subprocess\.[A-Za-z_]+\([^)]*shell[[:space:]]*=[[:space:]]*True|os\.system\(|os\.popen\(|\beval\(|\bexec\()' "$diff_file" \
    | grep -vE '^[0-9]+:[+][[:space:]]*[-*#]' || true)
  if [ -n "$py_shell" ]; then
    signals+=("发现新增 shell 字符串执行 / eval / exec（确认输入不是用户可控的命令串）：\n$py_shell")
  fi

  # 8. 依赖声明与 Nix 打包的一致性：改了 pyproject 却没碰 default.nix 时提醒人工核对
  if grep -qE '^[+]{3} b/pyproject\.toml' "$diff_file" && ! grep -qE '^[+]{3} b/default\.nix' "$diff_file"; then
    signals+=("pyproject.toml 有改动但 default.nix 没改：确认新增 / 删除的依赖已同步到 Nix 的 build-system / dependencies。")
  fi

  if [ ${#signals[@]} -eq 0 ]; then
    echo "未检测到明显的显式机械违规特征。"
  else
    local s
    for s in "${signals[@]}"; do
      echo -e "- ⚠️ $s"
    done
  fi
}

# 从 issue / PR 正文里切出 `### <名>` / `## <名>` 段，直到下一个同级或更高级标题。
section_of() { # $1=文件 $2=段名
  awk -v want="$2" '
    /^#+[[:space:]]/ {
      n = 0; tmp = $0
      while (substr(tmp, n + 1, 1) == "#") n++
      line = $0; sub(/^#+[[:space:]]*/, "", line); sub(/[[:space:]]*$/, "", line)
      if (f && n <= lvl) f = 0
      if (!f && line == want) { f = 1; lvl = n; next }
    }
    f { print }
  ' "$1"
}

echo "── 运行模式：$MODE"

if [ "$MODE" = "pr" ]; then
  echo "正在获取 PR #$PR 数据..."
  gh pr view "$PR" --json number,title,headRefOid,baseRefName,body \
    -q '[.number, .title, .headRefOid, .baseRefName] | @tsv' \
    | awk -F'\t' '{printf "number\t%s\ntitle\t%s\nhead\t%s\nbase\t%s\n", $1, $2, $3, $4}' \
    >"$OUT_DIR/meta.tsv"

  gh pr view "$PR" --json body -q .body >"$TMP/pr-body.md"
  gh pr diff "$PR" >"$TMP/raw.diff"

  # 关联 issue 的「实现」段：严格型审查用它判断「改动是否越出 issue 范围」。
  # 取不到就留空，不阻塞审查；rubric 里也允许模型在缺上下文时不下越界结论。
  : >"$TMP/issue-scope.md"
  grep -Eio 'close[sd]?[[:space:]]+#[0-9]+|fixe[sd]?[[:space:]]+#[0-9]+|resolves?[[:space:]]+#[0-9]+' "$TMP/pr-body.md" \
    | grep -Eo '[0-9]+' | sort -un >"$TMP/issue-numbers.txt" || true
  while IFS= read -r iss; do
    [ -n "$iss" ] || continue
    ititle=$(gh issue view "$iss" --json title -q .title 2>/dev/null || true)
    ibody=$(gh issue view "$iss" --json body -q .body 2>/dev/null || true)
    [ -n "$ititle$ibody" ] || continue
    printf '### Issue #%s %s\n\n' "$iss" "$ititle" >>"$TMP/issue-scope.md"
    printf '%s\n' "$ibody" >"$TMP/issue.md"
    section_of "$TMP/issue.md" 实现 >>"$TMP/issue-scope.md" || true
    printf '\n' >>"$TMP/issue-scope.md"
  done <"$TMP/issue-numbers.txt"
else
  # dry-run 模式：比对当前分支与 main
  BASE_REF=$(git -C "$PROJECT_ROOT" merge-base HEAD origin/main 2>/dev/null || git -C "$PROJECT_ROOT" merge-base HEAD main 2>/dev/null || echo "HEAD~1")
  HEAD_OID=$(git -C "$PROJECT_ROOT" rev-parse HEAD)
  BRANCH_NAME=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)

  printf "number\tdry-run\ntitle\t本地分支自检 (%s)\nhead\t%s\nbase\t%s\n" \
    "$BRANCH_NAME" "$HEAD_OID" "$BASE_REF" >"$OUT_DIR/meta.tsv"

  echo "本地测试 PR 描述（Dry-run 模式）" >"$TMP/pr-body.md"
  : >"$TMP/issue-scope.md"
  git -C "$PROJECT_ROOT" diff "$BASE_REF" >"$TMP/raw.diff"
fi

# 过滤不需要审查的文件类型（构建产物、缓存、IDE 目录）
awk '
  /^diff --git / {
    skip = ($0 ~ /^diff --git a\/(dist\/|result(\/| )|\.idea\/|([^/]+\/)*__pycache__\/)/)
  }
  !skip { print }
' "$TMP/raw.diff" >"$TMP/filtered.diff"

# 生成带行号的 diff
annotate_diff "$TMP/filtered.diff" >"$TMP/annotated.diff"

# 提取机械信号
SIGNALS=$(detect_mechanical_signals "$TMP/raw.diff")

# 组装 context.md
{
  echo "# PR 代码审查上下文"
  echo
  echo "## PR 基本信息"
  echo "- **PR**: $(awk -F'\t' '$1=="number"{print $2}' "$OUT_DIR/meta.tsv")"
  echo "- **标题**: $(awk -F'\t' '$1=="title"{print $2}' "$OUT_DIR/meta.tsv")"
  echo "- **Head SHA**: $(awk -F'\t' '$1=="head"{print $2}' "$OUT_DIR/meta.tsv")"
  echo "- **Base Ref**: $(awk -F'\t' '$1=="base"{print $2}' "$OUT_DIR/meta.tsv")"
  echo
  echo "## PR 正文"
  cat "$TMP/pr-body.md"
  echo
  if [ -s "$TMP/issue-scope.md" ]; then
    echo "## 关联 issue 的「实现」范围（用于判断越界）"
    cat "$TMP/issue-scope.md"
    echo
  fi
  echo "## 机械信号初筛"
  echo "$SIGNALS"
  echo
  echo "## 代码变更 Diff（含 [L行号] 标记）"
  cat "$TMP/annotated.diff"
} >"$OUT_DIR/context.md"

echo "✅ 上下文生成完成：$OUT_DIR/context.md"
