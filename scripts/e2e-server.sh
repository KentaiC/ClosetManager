#!/usr/bin/env bash
# 为端到端测试启动一个隔离的 closet-server：
# 新建数据目录，导入 Tests/Fixtures 中的样例备份，然后在指定端口提供 Web/dist。
#
# 环境变量：
#   CLOSET_E2E_PORT    监听端口，默认 18766
#   CLOSET_E2E_DATA    数据目录，默认 Web/e2e/.data
#   CLOSET_SERVER_BIN  运行 closet-server 的命令前缀，默认 "swift run --package-path <仓库> closet-server"
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${CLOSET_E2E_PORT:-18766}"
DATA="${CLOSET_E2E_DATA:-$REPO/Web/e2e/.data}"
SERVER="${CLOSET_SERVER_BIN:-swift run --package-path $REPO closet-server}"

rm -rf "$DATA"
$SERVER import "$REPO/Tests/Fixtures/wardrobe-v1-sample.wardrobe" --data-dir "$DATA" --mode overwrite --apply
exec $SERVER serve --data-dir "$DATA" --port "$PORT" --web-root "$REPO/Web/dist"
