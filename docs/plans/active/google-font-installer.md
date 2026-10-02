# Implementation Plan: Google Fonts TUI Installer

**Target Slug:** `google-font-installer`  
**Status:** In Progress (Plan Locked)  
**Primary Deliverable:** `scripts/fonts/googlefont-installer.sh`

---

## 1. Approach & Architecture

Xây dựng script độc lập `scripts/fonts/googlefont-installer.sh` theo mô hình TUI tương tự `nerdfont-installer.sh`, sử dụng Charm `gum` cho tương tác người dùng, tích hợp các cơ chế bảo vệ lỗi khi tải font từ Google Fonts.

### Các điểm mấu chốt:
1. **Curated & Custom Selection:**
   - Danh sách chọn nhanh: `Inter`, `Roboto Mono`, `Fira Code`, `JetBrains Mono`, `Space Grotesk`, `Plus Jakarta Sans`, `Inconsolata`, `Source Code Pro`, `Montserrat`, `Open Sans`.
   - Tùy chọn `✏️ Custom font name...` kích hoạt `gum input` để nhập bất kỳ font nào trên Google Fonts.
2. **Download & Archive Validation:**
   - URL download: `https://fonts.google.com/download?family=<Encoded_Name>`
   - Validation bắt buộc: `unzip -tq` để phát hiện payload HTML lỗi (do Google trả về HTTP 200 ngay cả khi tên font không tồn tại).
3. **Granular Multi-select (Font lẻ):**
   - Đọc danh sách file `.ttf`/`.otf` qua `unzip -Z1`.
   - Dùng `gum choose --no-limit` cho phép user chỉ cài đặt những file font (Regular, Bold, Italic...) cần thiết.
4. **Integration:**
   - Thêm vào menu `bin/fsetup.sh`.
   - Cập nhật tài liệu `README.md`, `AGENTS.md`, `CLAUDE.md`.

---

## 2. Implementation Phases & Waves

### Phase 1: Core Script (`scripts/fonts/googlefont-installer.sh`)
- **Wave 1.1 (Pre-flight & Input Handling):**
  - Kiểm tra và cài đặt tự động `gum` (theo chuẩn Charm APT repo).
  - Kiểm tra các công cụ hệ thống bắt buộc: `curl`, `unzip`, `fc-cache`.
  - Hiển thị banner và menu chọn font (Curated list + Custom input).
  - Chuẩn hóa tên font (xử lý khoảng trắng thành `%20` khi gọi URL, tạo thư mục con sạch).
- **Wave 1.2 (Download, Verification & Granular Install):**
  - Tải file zip về `/tmp/googlefont_zip/<font>.zip` bằng `curl` bọc trong `gum spin`.
  - Kiểm tra tính toàn vẹn của archive (`unzip -tq`). Nếu không phải zip hợp lệ, thông báo lỗi đỏ và thoát an toàn.
  - Trích xuất danh sách file font (`.ttf`, `.otf`), lọc bỏ metadata rác (như `OFL.txt`, `README.txt`).
  - Dùng `gum choose --no-limit` cho người dùng chọn file lẻ.
  - Giải nén các file đã chọn vào `$HOME/.local/share/fonts/GoogleFonts/<FontName>/`.
  - Chạy `fc-cache -fv` bọc trong `gum spin`.
  - Cấp quyền thực thi `chmod +x scripts/fonts/googlefont-installer.sh`.

### Phase 2: Integration & Documentation
- **Wave 2.1 (Orchestrator Integration):**
  - Cập nhật `bin/fsetup.sh`: bổ sung option `"🔤 Install Google Fonts"` vào menu chính và xử lý trong case switch tương tự Nerd Fonts.
- **Wave 2.2 (Repo Docs):**
  - Cập nhật `README.md`: bổ sung mục hướng dẫn sử dụng `googlefont-installer.sh` kèm lệnh `curl | bash`.
  - Cập nhật `AGENTS.md` và `CLAUDE.md`: ghi nhận script mới trong bảng cấu trúc thư mục `scripts/fonts/`.

### Phase 3: Verification & Quality Gate
- **Wave 3.1 (Static Analysis):**
  - Kiểm tra cú pháp: `bash -n scripts/fonts/googlefont-installer.sh` và `bash -n bin/fsetup.sh`.
  - Linter ShellCheck: `shellcheck -x scripts/fonts/googlefont-installer.sh` và `shellcheck -x bin/fsetup.sh`.
- **Wave 3.2 (Functional Smoke Test):**
  - Kiểm tra luồng tải thử nghiệm font thực tế (chẳng hạn `Space Grotesk` hoặc `Inter`).
  - Xác nhận tính năng bắt lỗi khi nhập font không tồn tại.
  - Xác nhận file font xuất hiện trong `~/.local/share/fonts/GoogleFonts/` và cache font nhận diện thành công.

---

## 3. Acceptance Criteria

1. [ ] `scripts/fonts/googlefont-installer.sh` chạy độc lập thành công, hiển thị TUI trực quan bằng `gum`.
2. [ ] Hỗ trợ cả 2 chế độ: chọn từ danh sách có sẵn và tự gõ tên font.
3. [ ] Xử lý đúng lỗi khi gõ sai tên font (không crash, báo lỗi rõ ràng, dọn dẹp file rác).
4. [ ] Cho phép chọn file font lẻ (`.ttf`/`.otf`) từ zip trước khi cài đặt.
5. [ ] Font sau khi cài được nhận diện trong hệ thống qua `fc-list`.
6. [ ] `bin/fsetup.sh` có entrypoint gọi script Google Fonts.
7. [ ] Vượt qua `bash -n` và `shellcheck` không có warning/error.
