#!/bin/bash
# 把這個資料夾「現在的內容」發佈到 main，main 只保留最近 KEEP 版（預設 2：這次＋上一版），更舊的歷史不再保留。
#
# 用法（Git Bash，在這個資料夾）：
#   ./deploy.sh --dry-run              只檢查與顯示摘要（保留／丟掉哪幾版、這次變了哪些檔案），不 commit、不推送
#   ./deploy.sh "說明這次發佈"          檢查 → 確認 → 重建 main（保留最近 KEEP 版）→ 強制推送 → 清掉本機舊物件
#   ./deploy.sh --keep 3 "說明"         這次改保留 3 版；--keep 1 等於舊做法（只留這一版）
#
# 流程：先照平常把新建置複製進來（Build、StreamingAssets、index.html…），再執行本腳本。
# 不在 Build 裡的檔案（privacy.html、README.md、build-guid.txt…）照現在資料夾裡的樣子一起發佈。
#
# 退回上一版（網站立刻換回上一版內容，main 剩一版）：
#   git reset --hard HEAD~1 && git push --force-with-lease origin main
#
# 注意：
# - 每次發佈都會改寫 GitHub 上的 main（保留的舊版內容、訊息與日期不變，但 commit ID 會變），丟掉的版本無法復原；執行前要輸入 yes 確認。
# - 每多保留一版，repo 就多存那一版改過的檔案（主要是 Build 的 .wasm 與 .data，約 90 MB）；GitHub 建議 repo 不超過 1 GB。
# - 遠端還有 tag 指向舊 commit 時，舊建置仍留在 GitHub，repo 不會變小；本腳本只列出，不刪 tag。
# - GitHub 會在之後自行清掉沒人參照的舊物件，repo 大小不會立刻變小。
set -euo pipefail
cd "$(dirname "$0")"

BRANCH=main
KEEP=2                         # main 保留的版本數（含這次）
LIMIT=$((100 * 1024 * 1024))   # GitHub 單檔上限 100 MB
DRY_RUN=0
MESSAGE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --keep) shift; KEEP="${1:-}" ;;
        *) MESSAGE="$1" ;;
    esac
    shift
done
MESSAGE="${MESSAGE:-deploy $(date +%F)}"

fail() { echo "❌ $1"; exit 1; }
mb() { awk -v b="$1" 'BEGIN { printf "%.1f MB", b / 1048576 }'; }

[[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || fail "--keep 要是 1 以上的整數"

echo "[🔍 發佈前檢查]"
[ -d .git ] || fail "這裡不是 git repo"
git remote get-url origin >/dev/null 2>&1 || fail "沒有 origin"
[ -f index.html ] || fail "缺少 index.html"
[ -d Build ] || fail "缺少 Build 資料夾"
[ -e .git/rebase-merge ] || [ -e .git/rebase-apply ] || [ -e .git/MERGE_HEAD ] && fail "有未完成的 merge／rebase"
[ "$(git symbolic-ref --short -q HEAD || true)" = "$BRANCH" ] || fail "目前不在 $BRANCH 分支"

too_big=$(find . -path ./.git -prune -o -type f -size +$((LIMIT / 1024))k -print)
[ -z "$too_big" ] || fail "超過 100 MB 的檔案，GitHub 會拒收：
$too_big"

has_head=0
git rev-parse --verify -q HEAD >/dev/null && has_head=1

echo "遠端：$(git remote get-url origin)"
echo "檔案：$(find . -path ./.git -prune -o -type f -print | wc -l) 個，共 $(du -sh --exclude=.git . | cut -f1)"
echo "最大的檔案："
find . -path ./.git -prune -o -type f -printf '%s %p\n' | sort -rn | head -3 | awk '{printf "  %.1f MB  %s\n", $1/1048576, $2}'
echo "本機 .git：$(du -sh .git | cut -f1)"

# 這次和目前 main 相比變了哪些檔案（新增或修改的檔案就是這次 repo 要多存的內容）
echo "這次的變更（相對於 $([ $has_head = 1 ] && git rev-parse --short HEAD || echo '空 repo')）："
added_bytes=0
changes=0
while IFS= read -r -d '' entry; do
    state="${entry:0:2}"
    path="${entry:3}"
    changes=$((changes + 1))
    if [ -f "$path" ]; then
        size=$(stat -c %s "$path")
        added_bytes=$((added_bytes + size))
        printf "  %s %9s  %s\n" "$state" "$(mb "$size")" "$path"
    else
        printf "  %s %9s  %s\n" "$state" "刪除" "$path"
    fi
done < <(git status --porcelain -z -uall)
[ "$changes" -gt 0 ] || echo "  （沒有變更）"
echo "  新增或修改的內容共 $(mb "$added_bytes")"

# 保留哪幾版：這次＋目前 main 上最新的 KEEP-1 版；更舊的丟掉
kept=()
dropped=()
if [ $has_head = 1 ]; then
    mapfile -t history < <(git rev-list --first-parent HEAD)
    for i in "${!history[@]}"; do
        if [ "$i" -lt $((KEEP - 1)) ]; then kept+=("${history[$i]}"); else dropped+=("${history[$i]}"); fi
    done
fi
echo "main 保留 $KEEP 版："
echo "  （這次）  $MESSAGE"
for c in "${kept[@]}"; do echo "  $(git log -1 --format='%h  %ad  %s' --date=short "$c")"; done
if [ ${#dropped[@]} -gt 0 ]; then
    echo "丟掉："
    for c in "${dropped[@]}"; do echo "  $(git log -1 --format='%h  %ad  %s' --date=short "$c")"; done
fi
kept_bytes=0
if [ ${#kept[@]} -gt 0 ]; then
    # 保留的舊版各自的檔案，同內容（同 blob）只算一次
    kept_bytes=$(for c in "${kept[@]}"; do git ls-tree -r -l "$c"; done \
        | awk '$2 == "blob" && !seen[$3]++ { s += $4 } END { print s + 0 }')
fi
echo "推送後 main 約 $(mb $((kept_bytes + added_bytes)))（保留的舊版 $(mb "$kept_bytes") ＋ 這次新增或修改 $(mb "$added_bytes")，未計 git 壓縮）"

tags=$(git ls-remote --tags origin 2>/dev/null | grep -v '\^{}' | awk '{print $2}' | sed 's#refs/tags/##' || true)
if [ -n "$tags" ]; then
    echo "⚠️ 遠端還有 tag，會讓舊建置繼續留在 GitHub（本腳本不刪）："
    echo "$tags" | sed 's/^/  /'
fi
others=$(git for-each-ref --format='%(refname:short)' refs/heads | grep -vx "$BRANCH" || true)
[ -z "$others" ] || echo "ℹ️ 本機其他分支會讓本機舊物件留著：$others"

if [ "$DRY_RUN" = 1 ]; then
    echo "（--dry-run：沒有 commit、沒有推送）"
    exit 0
fi

echo
read -r -p "要把 GitHub 上的 $BRANCH 改成只保留上面這 $KEEP 版嗎？丟掉的版本無法復原。輸入 yes 繼續：" answer
[ "$answer" = "yes" ] || fail "已取消，沒有任何變更"

previous=$(git rev-parse -q --verify HEAD || true)

# 由舊到新重建保留的版本：內容、訊息、作者與日期照舊，只是接成一條新的短歷史
parent=()
for ((i = ${#kept[@]} - 1; i >= 0; i--)); do
    c="${kept[$i]}"
    # 訊息走管線（-F -）：Windows 的 git.exe 讀不到 bash 的 <(...)
    commit=$(git log -1 --format=%B "$c" | GIT_AUTHOR_NAME="$(git log -1 --format=%an "$c")" \
        GIT_AUTHOR_EMAIL="$(git log -1 --format=%ae "$c")" GIT_AUTHOR_DATE="$(git log -1 --format=%aI "$c")" \
        GIT_COMMITTER_NAME="$(git log -1 --format=%cn "$c")" GIT_COMMITTER_EMAIL="$(git log -1 --format=%ce "$c")" \
        GIT_COMMITTER_DATE="$(git log -1 --format=%cI "$c")" git commit-tree "$c^{tree}" "${parent[@]}" -F -)
    parent=(-p "$commit")
done
git add -A
commit=$(git commit-tree "$(git write-tree)" "${parent[@]}" -m "$MESSAGE")
git update-ref "refs/heads/$BRANCH" "$commit"

if [ -n "$previous" ]; then
    git push --force-with-lease="$BRANCH:$previous" origin "$BRANCH"
else
    git push origin "$BRANCH"
fi
echo "✅ 已推送：$(git rev-parse --short HEAD)（取代 ${previous:0:7}；main 現在 $(git rev-list --count HEAD) 版）"

echo "[🧹 清理本機舊物件]"
git reflog expire --expire=now --all
git gc --prune=now --quiet
echo "本機 .git：$(du -sh .git | cut -f1)"
echo "GitHub Pages 會自動重新部署；幾分鐘後到網站確認。"
