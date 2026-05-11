#!/bin/bash
# ============================================================
# CIS Benchmark NGINX - Phần 5.1: Kiểm soát truy cập
# Script: Triển khai tự động (Deploy)
# Áp dụng: 5.1.1 (Giới hạn IP) + 5.1.2 (Giới hạn HTTP Method)
# ============================================================

set -e  # Dừng ngay nếu có lỗi

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

NGINX_CONF="/etc/nginx/nginx.conf"
SITE_CONF="/etc/nginx/sites-available/default"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================"
echo " CIS NGINX Benchmark - Phần 5.1 Deploy"
echo " Thời gian: $(date)"
echo "============================================"
echo ""

# ============================================================
# BƯỚC 1: Backup file config trước khi sửa
# Lý do: Nếu script làm hỏng config, khôi phục bằng file .bak
# ============================================================
echo "[BƯỚC 1] Backup file config..."

if [ ! -f "$NGINX_CONF" ]; then
    echo -e "${RED}[LỖI] Không tìm thấy file: $NGINX_CONF${NC}"
    exit 1
fi

if [ ! -f "$SITE_CONF" ]; then
    echo -e "${RED}[LỖI] Không tìm thấy file: $SITE_CONF${NC}"
    exit 1
fi

sudo cp "$NGINX_CONF" "${NGINX_CONF}.bak.${TIMESTAMP}"
sudo cp "$SITE_CONF" "${SITE_CONF}.bak.${TIMESTAMP}"

echo -e "${GREEN}[OK] Đã backup:${NC}"
echo "     ${NGINX_CONF}.bak.${TIMESTAMP}"
echo "     ${SITE_CONF}.bak.${TIMESTAMP}"
echo ""

# ============================================================
# BƯỚC 2: Kiểm tra config nginx hiện tại trước khi sửa
# Lý do: Đảm bảo config ban đầu hợp lệ, tránh thêm lỗi
# ============================================================
echo "[BƯỚC 2] Kiểm tra config nginx hiện tại..."

if sudo nginx -t; then
    echo -e "${GREEN}[OK] Config nginx hiện tại hợp lệ.${NC}"
else
    echo -e "${RED}[LỖI] Config nginx hiện tại đang lỗi. Dừng script để tránh lỗi chồng lỗi.${NC}"
    exit 1
fi
echo ""

# ============================================================
# BƯỚC 3: Áp dụng 5.1.1 - Giới hạn IP (chỉ localhost)
#
# Cách làm với sed:
# - Tìm dòng "listen [::]:80 default_server;" (dòng listen cuối)
# - Dùng "a\" để append thêm các dòng NGAY SAU dòng match
# - Fallback sang "listen 80" nếu không có IPv6
# ============================================================
echo "[BƯỚC 3] Áp dụng 5.1.1 - Giới hạn IP truy cập..."
 
if sudo grep -q "allow 127.0.0.1/32" "$SITE_CONF"; then
    echo -e "${YELLOW}[BỎ QUA] Rule 'allow 127.0.0.1/32' đã tồn tại.${NC}"
else
    if sudo grep -q "^[[:space:]]*listen \[::\]:80" "$SITE_CONF"; then
        sudo sed -i '/^[[:space:]]*listen \[::\]:80/a \\n\t# CIS 5.1.1 - Chi cho phep localhost\n\tallow 127.0.0.1\/32;\n\tdeny all;' "$SITE_CONF"
    else
        sudo sed -i '/^[[:space:]]*listen 80/a \\n\t# CIS 5.1.1 - Chi cho phep localhost\n\tallow 127.0.0.1\/32;\n\tdeny all;' "$SITE_CONF"
    fi
 
    if sudo grep -q "allow 127.0.0.1/32" "$SITE_CONF"; then
        echo -e "${GREEN}[OK] Đã thêm rule giới hạn IP.${NC}"
    else
        echo -e "${RED}[LỖI] Không thể thêm rule. Thêm thủ công vào server:${NC}"
        echo "      allow 127.0.0.1/32;"
        echo "      deny all;"
    fi
fi
echo ""
 
# ============================================================
# BƯỚC 4: Áp dụng 5.1.2 - Giới hạn HTTP Method
#
# Cách làm với sed:
# - Tìm dòng "location / {" trong file
# - Dùng "a\" để chèn block limit_except NGAY SAU dòng đó
# ============================================================
echo "[BƯỚC 4] Áp dụng 5.1.2 - Giới hạn HTTP Method..."
 
if sudo grep -q "limit_except GET HEAD POST" "$SITE_CONF"; then
    echo -e "${YELLOW}[BỎ QUA] Rule 'limit_except' đã tồn tại.${NC}"
else
    sudo sed -i '/^[[:space:]]*location \/ {[[:space:]]*$/a \\t\t# CIS 5.1.2 - Chi cho phep GET HEAD POST\n\t\tlimit_except GET HEAD POST {\n\t\t\tdeny all;\n\t\t}' "$SITE_CONF"
 
    if sudo grep -q "limit_except GET HEAD POST" "$SITE_CONF"; then
        echo -e "${GREEN}[OK] Đã thêm rule giới hạn HTTP method.${NC}"
    else
        echo -e "${RED}[LỖI] Không thể thêm rule. Thêm thủ công vào location / {}:${NC}"
        echo "      limit_except GET HEAD POST {"
        echo "          deny all;"
        echo "      }"
    fi
fi
echo ""
 
# ============================================================
# BƯỚC 5: Test config sau khi sửa
# Nếu lỗi → tự restore backup
# ============================================================
echo "[BƯỚC 5] Kiểm tra config sau khi sửa..."
 
if sudo nginx -t 2>&1; then
    echo -e "${GREEN}[OK] Config hợp lệ. Tiến hành reload nginx.${NC}"
    echo ""
 
    echo "[BƯỚC 6] Reload nginx..."
    if sudo systemctl reload nginx; then
        echo -e "${GREEN}[OK] Nginx đã reload thành công.${NC}"
    else
        echo -e "${RED}[LỖI] Reload thất bại. Kiểm tra: sudo systemctl status nginx${NC}"
        exit 1
    fi
else
    echo -e "${RED}[LỖI] Config có lỗi sau khi sửa! Đang khôi phục backup...${NC}"
    sudo cp "${SITE_CONF}.bak.${TIMESTAMP}" "$SITE_CONF"
    echo -e "${YELLOW}[ĐÃ KHÔI PHỤC] File config đã restore về bản backup.${NC}"
    exit 1
fi
 
echo ""
echo "============================================"
echo -e "${GREEN} HOÀN THÀNH: Phần 5.1 đã được triển khai!${NC}"
echo "============================================"
echo "Nếu cần rollback:"
echo "  sudo cp ${SITE_CONF}.bak.${TIMESTAMP} $SITE_CONF"
echo "  sudo systemctl reload nginx"