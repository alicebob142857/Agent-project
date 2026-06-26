#!/bin/bash

PORT="${1:-8010}"

echo "当前共享目录：$(pwd)"
echo "本地端口：$PORT"

python3 -m http.server "$PORT" --bind 127.0.0.1 &
HTTP_PID=$!

sleep 1

cloudflared tunnel --protocol http2 --edge-ip-version 4 --url "http://127.0.0.1:$PORT" &
TUNNEL_PID=$!

echo ""
echo "等待 cloudflared 输出 trycloudflare.com 地址。"
echo "看到 https://xxxx.trycloudflare.com 后，在虚拟机中用："
echo ""
echo "wget -O /data/vm_pull_changes.sh https://xxxx.trycloudflare.com/vm_pull_changes.sh"
echo "bash /data/vm_pull_changes.sh https://xxxx.trycloudflare.com"
echo ""
echo "下载完后按 Ctrl+C 关闭。"

trap "kill $HTTP_PID $TUNNEL_PID 2>/dev/null; exit" INT TERM EXIT

wait
