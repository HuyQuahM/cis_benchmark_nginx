#!/bin/bash
# ============================================================
# CIS Benchmark NGINX - 5.1 Access Control
# 5.1.1 (Giới hạn IP) + 5.1.2 (Giới hạn HTTP Method)
# ============================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SITE_CONF="/etc/nginx/sites-available/default"
BACKUP="${SITE_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
NEED_DEPLOY=0

echo "======================================"
echo " CIS 5.1 - Kiểm tra Access Control"
echo "======================================"

# ── CHECK: File site config có tồn tại không ──────────────────────────────
echo ""
echo "[CHECK] Kiểm tra file config tồn tại..."
if [ ! -f "$SITE_CONF" ]; then
    echo -e "  ${RED}[ERROR] Không tìm thấy file: $SITE_CONF${NC}"
    echo "          Vui lòng kiểm tra lại đường dẫn hoặc tạo file config trước."
    exit 1
fi
echo -e "  ${GREEN}[OK] File tồn tại: $SITE_CONF${NC}"

# ── CHECK 5.1.1: Giới hạn IP ──────────────────────────────────────────────
echo ""
echo "[CHECK] 5.1.1 - Giới hạn địa chỉ IP truy cập..."

if grep -q "allow 127.0.0.1" "$SITE_CONF" && grep -q "deny all" "$SITE_CONF"; then
    echo -e "  ${GREEN}[PASS] Rule allow/deny IP đã được cấu hình.${NC}"
    STATUS_511="PASS"
else
    echo -e "  ${RED}[FAIL] Chưa có rule giới hạn IP.${NC}"
    STATUS_511="FAIL"
    NEED_DEPLOY=1
fi

# ── CHECK 5.1.2: Giới hạn HTTP Method ─────────────────────────────────────
echo ""
echo "[CHECK] 5.1.2 - Giới hạn phương thức HTTP..."

if grep -q "limit_except GET HEAD POST" "$SITE_CONF"; then
    echo -e "  ${GREEN}[PASS] limit_except đã được cấu hình.${NC}"
    STATUS_512="PASS"
else
    echo -e "  ${RED}[FAIL] Chưa giới hạn HTTP method.${NC}"
    STATUS_512="FAIL"
    NEED_DEPLOY=1
fi

# ── Tóm tắt kết quả check ─────────────────────────────────────────────────
echo ""
echo "======================================"
echo " Kết quả kiểm tra"
echo "======================================"
echo "  5.1.1 Giới hạn IP            :  $STATUS_511"
echo "  5.1.2 Giới hạn HTTP Method   :  $STATUS_512"
echo "======================================"

# ── Nếu tất cả PASS thì không cần làm gì ──────────────────────────────────
if [ "$NEED_DEPLOY" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}[OK] Hệ thống đã đạt chuẩn CIS 5.1. Không cần triển khai thêm.${NC}"
    exit 0
fi

# ── Có ít nhất 1 FAIL → tiến hành DEPLOY ──────────────────────────────────
echo ""
echo -e "${YELLOW}[INFO] Phát hiện cấu hình chưa đạt. Bắt đầu triển khai...${NC}"
echo ""

# Bước 1: Backup
echo "[BƯỚC 1] Backup config..."
sudo cp "$SITE_CONF" "$BACKUP"
echo -e "         ${GREEN}Đã backup: $BACKUP${NC}"

# Bước 2: Kiểm tra config hiện tại hợp lệ không
echo "[BƯỚC 2] Kiểm tra nginx config..."
if ! sudo nginx -t; then
    echo -e "${RED}[ERROR] Config hiện tại đã bị lỗi. Dừng lại."
    exit 1
fi

# Bước 3: Deploy 5.1.1 nếu FAIL
if [ "$STATUS_511" = "FAIL" ]; then
    echo "[BƯỚC 3] Triển khai 5.1.1 - Giới hạn IP..."
    if sudo grep -q "^[[:space:]]*listen \[::\]:80" "$SITE_CONF"; then
        sudo sed -i '/^[[:space:]]*listen \[::\]:80/a\ \n\tallow 127.0.0.1\/32;\n\tdeny all;' "$SITE_CONF"
    else
        sudo sed -i '/^[[:space:]]*listen 80/a\ \n\tallow 127.0.0.1\/32;\n\tdeny all;' "$SITE_CONF"
    fi
    echo -e "${GREEN}[OK] Đã thêm rule giới hạn IP.${NC}"
else
    echo "[BƯỚC 3] Bỏ qua 5.1.1 (đã PASS)."
fi

# Bước 4: Deploy 5.1.2 nếu FAIL
if [ "$STATUS_512" = "FAIL" ]; then
    echo "[BƯỚC 4] Triển khai 5.1.2 - Giới hạn HTTP Method..."
    sudo sed -i '/^[[:space:]]*location \/ {/a\ \n\t\tlimit_except GET HEAD POST {\n\t\t\tdeny all;\n\t\t}' "$SITE_CONF"
    echo -e "${GREEN}[OK] Đã thêm rule giới hạn HTTP method.${NC}"
else
    echo "[BƯỚC 4] Bỏ qua 5.1.2 (đã PASS)."
fi

# Bước 5: Kiểm tra lại config sau khi sửa
echo "[BƯỚC 5] Kiểm tra nginx config sau khi sửa..."
if ! sudo nginx -t 2>&1; then
    echo -e "${RED}[ERROR] Config sau khi sửa bị lỗi! Đang phục hồi backup...${NC}"
    sudo cp "$BACKUP" "$SITE_CONF"
    echo -e "         ${YELLOW}Đã phục hồi: $BACKUP${NC}"
    exit 1
fi

# Bước 6: Reload nginx
echo "[BƯỚC 6] Reload Nginx..."
sudo systemctl reload nginx
echo -e "${GREEN}[OK] Nginx đã reload thành công.${NC}"

# Bước 7: Kiểm tra lại sau deploy
echo ""
echo "======================================"
echo " Xác nhận sau khi triển khai"
echo "======================================"

FINAL_OK=1

if grep -q "allow 127.0.0.1" "$SITE_CONF" && grep -q "deny all" "$SITE_CONF"; then
    echo -e "  ${GREEN}[PASS] 5.1.1 - Giới hạn IP${NC}"
else
    echo -e "  ${RED}[FAIL] 5.1.1 - Vẫn chưa chính xác, Thêm thủ công vào server:${NC}"
    echo "      allow 127.0.0.1/32;"
    echo "      deny all;"
    FINAL_OK=0
fi

if grep -q "limit_except GET HEAD POST" "$SITE_CONF"; then
    echo -e "  ${GREEN}[PASS] 5.1.2 - Giới hạn HTTP Method${NC}"
else
    echo -e "  ${RED}[FAIL] 5.1.2 - Vẫn chưa chính xác, Thêm thủ công vào location / {}:${NC}"
    echo "      limit_except GET HEAD POST {"
    echo "          deny all;"
    echo "      }"
    FINAL_OK=0
fi

echo "======================================"

if [ "$FINAL_OK" -eq 1 ]; then
    echo -e "${GREEN}[DONE] Triển khai hoàn tất. Hệ thống đạt chuẩn CIS 5.1.${NC}"
else
    echo -e "${YELLOW}[WARN] Một số mục vẫn chưa đạt. Vui lòng kiểm tra thủ công.${NC}"
fi
