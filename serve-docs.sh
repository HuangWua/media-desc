#!/bin/bash
# 启动 docs/ 本地服务，浏览测试报告和可视化
cd "$(dirname "$0")/docs"
echo "📋 测试报告: http://localhost:8765/TEST_REPORT.md"
echo "🖼 全量API可视化: http://localhost:8765/test-visual-all.html"
echo "📜 长图切片对比: http://localhost:8765/test-visual-long.html"
echo ""
python3 -m http.server 8765
