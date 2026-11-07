#!/bin/bash
# 把這個資料夾「現在的內容」發佈成 main 上唯一的一個 commit，舊的建置歷史不再保留。
#
# 用法（Git Bash，在這個資料夾）：
#   ./deploy.sh --dry-run          只檢查與顯示摘要，不 commit、不推送
#   ./deploy.sh "說明這次發佈"      檢查 → 確認 → 單一 commit → 強制推送 main → 清掉本機舊物件
#
# 流程：先照平常把新建置複製進來（Build、StreamingAssets、index.html…），再執行本腳本。
# 不在 Build 裡的檔案（privacy.html、README.md、build-guid.txt…）照現在資料夾裡的樣子一起發佈。
#
# 注意：
# - 強制推送會改寫 GitHub 上的 main，無法復原；執行前要輸入 yes 確認。
# - 遠端還有 tag 指向舊 commit 時，舊建置仍留在 GitHub，repo 不會變小；本腳本只列出，不刪 tag。
# - GitHub 會在之後自行清掉沒人參照的舊物件，repo 大小不會立刻變小。
set -euo pipefail
cd "$(dirname "$0")"

BRANCH=main
LIMIT=$((100 * 1024 * 1024))   # GitHub 單檔上限 100 MB
DRY_RUN=0
MESSAGE=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        *) MESSAGE="$arg" ;;
    esac
done
MESSAGE="${MESSAGE:-deploy $(date +%F)}"

fail() { echo "❌ $1"; exit 1; }

echo "[🔍 發佈前檢查]"
[ -d .git ] || fail "這裡不是 git repo"
git remote get-url origin >/dev/null 2>&1 || fail "沒有 origin"
[ -f index.html ] || fail "缺少 index.html"
[ -d Build ] || fail "缺少 Build 資料夾"
[ -e .git/rebase-merge ] || [ -e .git/rebase-apply ] || [ -e .git/MERGE_HEAD ] && fail "有未完成的 merge／rebase"

too_big=$(find . -path ./.git -prune -o -type f -size +$((LIMIT / 1024))k -print)
[ -z "$too_big" ] || fail "超過 100 MB 的檔案，GitHub 會拒收：
$too_big"

echo "遠端：$(git remote get-url origin)"
echo "分支：$BRANCH（目前 $(git rev-list --count HEAD 2>/dev/null || echo 0) 個 commit）"
echo "檔案：$(find . -path ./.git -prune -o -type f -print | wc -l) 個，共 $(du -sh --exclude=.git . | cut -f1)"
echo "最大的檔案："
find . -path ./.git -prune -o -type f -printf '%s %p\n' | sort -rn | head -3 | awk '{printf "  %.1f MB  %s\n", $1/1048576, $2}'
echo "本機 .git：$(du -sh .git | cut -f1)"

tags=$(git ls-remote --tags origin 2>/dev/null | grep -v '\^{}' | awk '{print $2}' | sed 's#refs/tags/##' || true)
if [ -n "$tags" ]; then
    echo "⚠️ 遠端還有 tag，會讓舊建置繼續留在 GitHub（本腳本不刪）："
    echo "$tags" | sed 's/^/  /'
fi
others=$(git for-each-ref --format='%(refname:short)' refs/heads | grep -vx "$BRANCH" || true)
[ -z "$others" ] || echo "ℹ️ 本機其他分支會讓本機舊物件留著：$others"
echo "訊息：$MESSAGE"

if [ "$DRY_RUN" = 1 ]; then
    echo "（--dry-run：沒有 commit、沒有推送）"
    exit 0
fi

echo
read -r -p "要把 GitHub 上的 $BRANCH 改成只有這一個 commit 嗎？舊歷史無法復原。輸入 yes 繼續：" answer
[ "$answer" = "yes" ] || fail "已取消，沒有任何變更"

previous=$(git rev-parse --short HEAD 2>/dev/null || echo none)
git checkout --quiet --orphan deploy-tmp
git add -A
git commit --quiet -m "$MESSAGE"
git branch -D "$BRANCH" >/dev/null 2>&1 || true
git branch -m "$BRANCH"
git push --force origin "$BRANCH"
echo "✅ 已推送：$(git rev-parse --short HEAD)（取代 $previous）"

echo "[🧹 清理本機舊物件]"
git reflog expire --expire=now --all
git gc --prune=now --quiet
echo "本機 .git：$(du -sh .git | cut -f1)"
echo "GitHub Pages 會自動重新部署；幾分鐘後到網站確認。"
