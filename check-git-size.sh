#!/bin/bash
echo "[🔍 檢查 Git Repo 大小]"
du -sh .git
echo "=========="
git count-objects -vH
read -p "按 Enter 關閉..."