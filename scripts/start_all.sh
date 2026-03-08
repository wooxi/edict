#!/bin/bash
# 三省六部 · 一键启动脚本
# 用法：./start_all.sh
# 功能：一键启动数据刷新循环和看板服务器

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="/tmp/sansheng_liubu"
LOOP_LOG="$LOG_DIR/refresh.log"
SERVER_LOG="$LOG_DIR/server.log"
LOOP_PIDFILE="$LOG_DIR/refresh.pid"
SERVER_PIDFILE="$LOG_DIR/server.pid"
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB

# 创建日志目录
mkdir -p "$LOG_DIR"

# ── 日志轮转 ──
rotate_log() {
    local log="$1"
    if [[ -f "$log" ]] && (( $(stat -c%s "$log" 2>/dev/null || stat -f%z "$log" 2>/dev/null || echo 0) > MAX_LOG_SIZE )); then
        mv "$log" "${log}.1"
        echo "$(date '+%H:%M:%S') 日志已轮转" > "$log"
    fi
}

# ── 清理函数 ──
cleanup() {
    echo "$(date '+%H:%M:%S') 正在停止所有服务..."
    
    if [[ -f "$LOOP_PIDFILE" ]]; then
        LOOP_PID=$(cat "$LOOP_PIDFILE" 2>/dev/null)
        if kill -0 "$LOOP_PID" 2>/dev/null; then
            echo "$(date '+%H:%M:%S') 停止数据刷新循环 (PID=$LOOP_PID)"
            kill "$LOOP_PID" 2>/dev/null || true
        fi
        rm -f "$LOOP_PIDFILE"
    fi
    
    if [[ -f "$SERVER_PIDFILE" ]]; then
        SERVER_PID=$(cat "$SERVER_PIDFILE" 2>/dev/null)
        if kill -0 "$SERVER_PID" 2>/dev/null; then
            echo "$(date '+%H:%M:%S') 停止看板服务器 (PID=$SERVER_PID)"
            kill "$SERVER_PID" 2>/dev/null || true
        fi
        rm -f "$SERVER_PIDFILE"
    fi
    
    echo "$(date '+%H:%M:%S') 所有服务已停止"
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# ── 检查是否已有实例运行 ──
if [[ -f "$LOOP_PIDFILE" ]] && kill -0 $(cat "$LOOP_PIDFILE" 2>/dev/null) 2>/dev/null; then
    echo "❌ 数据刷新循环已在运行 (PID=$(cat "$LOOP_PIDFILE"))"
    exit 1
fi

if [[ -f "$SERVER_PIDFILE" ]] && kill -0 $(cat "$SERVER_PIDFILE" 2>/dev/null) 2>/dev/null; then
    echo "❌ 看板服务器已在运行 (PID=$(cat "$SERVER_PIDFILE"))"
    exit 1
fi

echo "🏛️  三省六部系统启动中..."
echo "   项目目录：$PROJECT_DIR"
echo "   脚本目录：$SCRIPT_DIR"
echo "   日志目录：$LOG_DIR"
echo ""

# ── 启动数据刷新循环 ──
rotate_log "$LOOP_LOG"
echo "$(date '+%H:%M:%S') 启动数据刷新循环..." >> "$LOOP_LOG"
cd "$SCRIPT_DIR"
nohup bash "$SCRIPT_DIR/run_loop.sh" >> "$LOOP_LOG" 2>&1 &
LOOP_PID=$!
echo $LOOP_PID > "$LOOP_PIDFILE"
echo "✅ 数据刷新循环已启动 (PID=$LOOP_PID)"
echo "   日志：$LOOP_LOG"

# ── 启动看板服务器 ──
rotate_log "$SERVER_LOG"
echo "$(date '+%H:%M:%S') 启动看板服务器..." >> "$SERVER_LOG"
cd "$PROJECT_DIR"
nohup python3 "$PROJECT_DIR/dashboard/server.py" --host 0.0.0.0 --port 7891 >> "$SERVER_LOG" 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > "$SERVER_PIDFILE"
echo "✅ 看板服务器已启动 (PID=$SERVER_PID)"
echo "   日志：$SERVER_LOG"
echo "   访问：http://localhost:7891"

echo ""
echo "🎉 所有服务已启动！"
echo ""
echo "快捷操作:"
echo "  查看刷新日志：tail -f $LOOP_LOG"
echo "  查看服务器日志：tail -f $SERVER_LOG"
echo "  停止所有服务：kill $LOOP_PID $SERVER_PID 或按 Ctrl+C"
echo ""
echo "按 Ctrl+C 停止所有服务"

# 等待所有后台进程
wait
