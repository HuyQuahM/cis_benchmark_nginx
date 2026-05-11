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
# Lý do: Đảm bảo config ban đầu hợp lệ, tránh nhầm lẫn lỗi cũ/mới
# ============================================================
echo "[BƯỚC 2] Kiểm tra config nginx hiện tại..."

if sudo nginx -t 2>/dev/null; then
    echo -e "${GREEN}[OK] Config nginx hiện tại hợp lệ.${NC}"
else
    echo -e "${RED}[CẢNH BÁO] Config nginx hiện tại đã có lỗi TRƯỚC khi chỉnh sửa.${NC}"
    echo "           Vẫn tiếp tục triển khai, nhưng hãy kiểm tra lại thủ công."
fi
echo ""

# ============================================================
# BƯỚC 3: Áp dụng 5.1.1 - Giới hạn IP truy cập
# Chỉ cho phép localhost (127.0.0.1), chặn tất cả IP khác
#
# CÁCH LÀM: Dùng Python để parse và sửa file config an toàn.
# KHÔNG dùng sed thay thế thô vì dễ gây lỗi nếu format file thay đổi.
# Script kiểm tra xem rule đã tồn tại chưa, nếu rồi thì bỏ qua.
# ============================================================
echo "[BƯỚC 3] Áp dụng 5.1.1 - Giới hạn IP (chỉ localhost)..."

# Kiểm tra nếu rule đã có rồi
if sudo grep -q "allow 127.0.0.1/32" "$SITE_CONF"; then
    echo -e "${YELLOW}[BỎ QUA] Rule 'allow 127.0.0.1/32' đã tồn tại trong config.${NC}"
else
    # Thêm allow/deny vào block server{} - sau dòng listen cuối cùng
    sudo python3 - <<'PYEOF'
import re

conf_path = "/etc/nginx/sites-available/default"

with open(conf_path, "r") as f:
    content = f.read()

# Thêm allow/deny sau dòng listen cuối trong server block đầu tiên
# Tìm pattern: listen [::]:80 default_server; hoặc listen 80 default_server;
# Thêm vào sau lần xuất hiện cuối của "listen" trong server block đầu

RULES = "\n\t# CIS 5.1.1 - Chi cho phep localhost\n\tallow 127.0.0.1/32;\n\tdeny all;"

# Tìm vị trí sau dòng listen [::]:80
pattern = r'(listen \[::\]:80[^;]*;)'
match = re.search(pattern, content)

if match:
    insert_pos = match.end()
    # Kiểm tra chưa có rule
    if "allow 127.0.0.1" not in content:
        content = content[:insert_pos] + RULES + content[insert_pos:]
        with open(conf_path, "w") as f:
            f.write(content)
        print("Da them rule allow/deny vao server block.")
    else:
        print("Rule da ton tai, bo qua.")
else:
    # Fallback: tìm "listen 80 default_server;"
    pattern2 = r'(listen 80[^;]*;)'
    match2 = re.search(pattern2, content)
    if match2:
        insert_pos = match2.end()
        if "allow 127.0.0.1" not in content:
            content = content[:insert_pos] + RULES + content[insert_pos:]
            with open(conf_path, "w") as f:
                f.write(content)
            print("Da them rule allow/deny (fallback) vao server block.")
        else:
            print("Rule da ton tai, bo qua.")
    else:
        print("CANH BAO: Khong tim thay dong listen de chen rule. Kiem tra thu cong.")
PYEOF

    if sudo grep -q "allow 127.0.0.1/32" "$SITE_CONF"; then
        echo -e "${GREEN}[OK] Đã thêm rule giới hạn IP.${NC}"
    else
        echo -e "${RED}[LỖI] Không thể thêm rule tự động. Vui lòng thêm thủ công:${NC}"
        echo "      allow 127.0.0.1/32;"
        echo "      deny all;"
        echo "      (Đặt trong block server{}, sau các dòng listen)"
    fi
fi
echo ""

# ============================================================
# BƯỚC 4: Áp dụng 5.1.2 - Giới hạn HTTP Method
# Chỉ cho phép GET, HEAD, POST. Chặn DELETE, PUT, OPTIONS, TRACE...
#
# Cần đặt trong block location / {}
# ============================================================
echo "[BƯỚC 4] Áp dụng 5.1.2 - Giới hạn HTTP Method..."

if sudo grep -q "limit_except GET HEAD POST" "$SITE_CONF"; then
    echo -e "${YELLOW}[BỎ QUA] Rule 'limit_except' đã tồn tại trong config.${NC}"
else
    sudo python3 - <<'PYEOF'
import re

conf_path = "/etc/nginx/sites-available/default"

with open(conf_path, "r") as f:
    content = f.read()

LIMIT_EXCEPT_RULE = """
\t\t# CIS 5.1.2 - Chi cho phep GET HEAD POST
\t\tlimit_except GET HEAD POST {
\t\t\tdeny all;
\t\t}"""

# Tìm location / { và thêm rule vào bên trong
# Tìm "location / {" rồi chèn sau dấu {
pattern = r'(location\s+/\s*\{)'
match = re.search(pattern, content)

if match:
    insert_pos = match.end()
    if "limit_except" not in content:
        content = content[:insert_pos] + LIMIT_EXCEPT_RULE + content[insert_pos:]
        with open(conf_path, "w") as f:
            f.write(content)
        print("Da them rule limit_except vao location / block.")
    else:
        print("Rule limit_except da ton tai, bo qua.")
else:
    print("CANH BAO: Khong tim thay block 'location /' de chen rule.")
    print("Them thu cong vao location / {}:")
    print("    limit_except GET HEAD POST { deny all; }")
PYEOF

    if sudo grep -q "limit_except GET HEAD POST" "$SITE_CONF"; then
        echo -e "${GREEN}[OK] Đã thêm rule giới hạn HTTP method.${NC}"
    else
        echo -e "${RED}[LỖI] Không thể thêm rule tự động. Thêm thủ công vào location / {}:${NC}"
        echo "      limit_except GET HEAD POST {"
        echo "          deny all;"
        echo "      }"
    fi
fi
echo ""

# ============================================================
# BƯỚC 5: Test config sau khi sửa
# Lý do: nginx -t kiểm tra syntax trước khi reload, tránh nginx bị crash
# ============================================================
echo "[BƯỚC 5] Kiểm tra config sau khi sửa..."

if sudo nginx -t 2>&1; then
    echo -e "${GREEN}[OK] Config hợp lệ. Tiến hành reload nginx.${NC}"
    echo ""

    # ============================================================
    # BƯỚC 6: Reload nginx
    # Dùng reload (không phải restart) để tránh downtime
    # ============================================================
    echo "[BƯỚC 6] Reload nginx..."
    if sudo systemctl reload nginx; then
        echo -e "${GREEN}[OK] Nginx đã reload thành công.${NC}"
    else
        echo -e "${RED}[LỖI] Reload nginx thất bại. Kiểm tra: sudo systemctl status nginx${NC}"
        exit 1
    fi
else
    echo -e "${RED}[LỖI] Config có lỗi sau khi sửa! Đang khôi phục backup...${NC}"
    sudo cp "${SITE_CONF}.bak.${TIMESTAMP}" "$SITE_CONF"
    echo -e "${YELLOW}[ĐÃ KHÔI PHỤC] File config đã được restore về bản backup.${NC}"
    echo "Hãy kiểm tra lại file config thủ công: $SITE_CONF"
    exit 1
fi

echo ""
echo "============================================"
echo -e "${GREEN} HOÀN THÀNH: Phần 5.1 đã được triển khai!${NC}"
echo "============================================"
echo ""
echo "Kiểm tra lại bằng lệnh:"
echo "  bash 5.1_check.sh"
echo ""
echo "Nếu cần rollback:"
echo "  sudo cp ${SITE_CONF}.bak.${TIMESTAMP} $SITE_CONF"
echo "  sudo systemctl reload nginx"
