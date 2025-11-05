#!/bin/bash
# 设置脚本权限

echo "设置脚本权限..."

chmod +x docker-deploy.sh
chmod +x start-wireguard.sh
chmod +x start-web.sh
chmod +x cleanup-wireguard.sh
chmod +x docker/entrypoint-web.sh

echo "✅ 所有脚本权限已设置"
echo ""
echo "可用脚本:"
echo "  ./docker-deploy.sh       - 完整直接部署"
echo "  ./start-wireguard.sh     - 仅启动 WireGuard"
echo "  ./start-web.sh           - 启动 Web 管理界面"
echo "  ./cleanup-wireguard.sh   - 清理环境"