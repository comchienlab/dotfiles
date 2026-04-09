#!/usr/bin/env bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════
#  GoClaw — Local Build & Deploy Script
#  Chạy trên máy LOCAL (không phải VPS)
#  Build Go binary + Web UI, copy lên VPS qua rsync/scp
#  Usage: bash goclaw-deploy.sh [--host user@ip] [--dir /path/to/goclaw]
# ══════════════════════════════════════════════════════════════════

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1m'; N='\033[0m'

ok()  { echo -e "${G}[✔]${N} $*"; }
inf() { echo -e "${B}[→]${N} $*"; }
wrn() { echo -e "${Y}[!]${N} $*"; }
die() { echo -e "${R}[✘]${N} $*" >&2; exit 1; }
sec() { echo -e "\n${C}${W}━━━  $*  ━━━${N}"; }
hr()  { echo -e "${C}──────────────────────────────────────────${N}"; }

# ── Config file ────────────────────────────────────────────────────
CONF_FILE="${HOME}/.goclaw.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Defaults ───────────────────────────────────────────────────────
VPS_USER="root"
VPS_HOST=""
VPS_SSH_KEY=""
VPS_DEST_BIN="/usr/local/bin/goclaw"
VPS_DEST_STATIC="/opt/goclaw/public"
GOCLAW_REPO_DIR=""
GOCLAW_REPO_URL=""    # nếu có → tự clone/pull trước khi build
GOCLAW_BRANCH=""      # branch/tag để checkout (dùng với --repo hoặc --dir có .git)
_TEMP_CLONE=""        # path temp clone → cleanup khi script kết thúc
TARGET_ARCH="amd64"   # amd64 | arm64

# ── Load saved config ──────────────────────────────────────────────
load_config() {
  if [[ -f "$CONF_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
    ok "Đọc config từ ${CONF_FILE}"
  fi
}

save_config() {
  cat > "$CONF_FILE" << EOF
# GoClaw deploy config — $(date '+%Y-%m-%d')
VPS_USER="${VPS_USER}"
VPS_HOST="${VPS_HOST}"
VPS_SSH_KEY="${VPS_SSH_KEY}"
VPS_DEST_BIN="${VPS_DEST_BIN}"
VPS_DEST_STATIC="${VPS_DEST_STATIC}"
GOCLAW_REPO_DIR="${GOCLAW_REPO_DIR}"
GOCLAW_REPO_URL="${GOCLAW_REPO_URL}"
GOCLAW_BRANCH="${GOCLAW_BRANCH}"
TARGET_ARCH="${TARGET_ARCH}"
EOF
  chmod 600 "$CONF_FILE"
  ok "Config lưu vào ${CONF_FILE}"
}

# ── SSH helper ─────────────────────────────────────────────────────
ssh_cmd() {
  local ssh_args=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
  [[ -n "$VPS_SSH_KEY" ]] && ssh_args+=(-i "$VPS_SSH_KEY")
  ssh "${ssh_args[@]}" "${VPS_USER}@${VPS_HOST}" "$@"
}

rsync_cmd() {
  local rsync_args=(-az --progress)
  [[ -n "$VPS_SSH_KEY" ]] && rsync_args+=(-e "ssh -i ${VPS_SSH_KEY} -o StrictHostKeyChecking=accept-new")
  rsync "${rsync_args[@]}" "$@"
}

# ── Parse CLI args ─────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)    VPS_HOST="$2"; shift 2 ;;
      --user)    VPS_USER="$2"; shift 2 ;;
      --key)     VPS_SSH_KEY="$2"; shift 2 ;;
      --dir)     GOCLAW_REPO_DIR="$2"; shift 2 ;;
      --repo)    GOCLAW_REPO_URL="$2"; shift 2 ;;
      --branch)  GOCLAW_BRANCH="$2"; shift 2 ;;
      --arch)    TARGET_ARCH="$2"; shift 2 ;;
      *) wrn "Unknown arg: $1"; shift ;;
    esac
  done
}

# ── Collect inputs interactively ───────────────────────────────────
collect_inputs() {
  hr
  echo -e "  ${W}GoClaw Deploy — Cấu hình${N}"
  hr

  # VPS host
  if [[ -z "$VPS_HOST" ]]; then
    echo -e "\n${W}VPS Host (IP hoặc hostname):${N}"
    read -rp "  → Host: " VPS_HOST
    [[ -z "$VPS_HOST" ]] && die "VPS host không được để trống"
  fi

  # VPS user
  echo -e "\n${W}VPS User [${VPS_USER}]:${N}"
  read -rp "  → User (Enter = ${VPS_USER}): " _u
  VPS_USER="${_u:-$VPS_USER}"

  # SSH key (optional)
  echo -e "\n${W}SSH Key path (Enter để bỏ qua — dùng SSH agent):${N}"
  echo -e "  ${B}Ví dụ: ~/.ssh/id_rsa${N}"
  read -rp "  → Key: " _k
  if [[ -n "$_k" ]]; then
    _k="${_k/#\~/$HOME}"
    [[ -f "$_k" ]] || die "SSH key không tồn tại: ${_k}"
    VPS_SSH_KEY="$_k"
  fi

  # GoClaw source — local dir hoặc git URL
  if [[ -z "$GOCLAW_REPO_DIR" ]] && [[ -z "$GOCLAW_REPO_URL" ]]; then
    echo -e "\n${W}GoClaw source:${N}"
    echo -e "  ${B}[1] Đường dẫn local (~/projects/goclaw)${N}"
    echo -e "  ${B}[2] Git URL (tự clone — không cần source local)${N}"
    read -rp "  → Chọn [1/2]: " _src_choice
    if [[ "${_src_choice:-1}" == "2" ]]; then
      echo -e "\n${W}Git repository URL:${N}"
      echo -e "  ${B}Ví dụ: https://github.com/org/goclaw${N}"
      read -rp "  → URL: " GOCLAW_REPO_URL
      [[ -z "$GOCLAW_REPO_URL" ]] && die "Git URL không được để trống"
      echo -e "\n${W}Branch/tag (Enter = default branch):${N}"
      read -rp "  → Branch: " GOCLAW_BRANCH
    else
      echo -e "\n${W}Đường dẫn GoClaw source trên máy local:${N}"
      echo -e "  ${B}Ví dụ: ~/projects/goclaw${N}"
      read -rp "  → Repo dir: " GOCLAW_REPO_DIR
      GOCLAW_REPO_DIR="${GOCLAW_REPO_DIR/#\~/$HOME}"
      [[ -d "$GOCLAW_REPO_DIR" ]] || die "Directory không tồn tại: ${GOCLAW_REPO_DIR}"
    fi
  elif [[ -n "$GOCLAW_REPO_DIR" ]] && [[ -z "$GOCLAW_REPO_URL" ]] && [[ -z "$GOCLAW_BRANCH" ]]; then
    # Có local dir nhưng chưa hỏi branch → hỏi branch nếu là git repo
    if [[ -d "${GOCLAW_REPO_DIR}/.git" ]]; then
      _cur_branch=$(git -C "$GOCLAW_REPO_DIR" symbolic-ref --short HEAD 2>/dev/null || echo "")
      echo -e "\n${W}Branch/tag để checkout [${_cur_branch:-current}]:${N}"
      echo -e "  ${B}Enter = giữ nguyên branch hiện tại${N}"
      read -rp "  → Branch: " GOCLAW_BRANCH
    fi
  fi

  # Target arch
  echo -e "\n${W}VPS architecture [amd64/arm64] [${TARGET_ARCH}]:${N}"
  read -rp "  → Arch (Enter = ${TARGET_ARCH}): " _a
  TARGET_ARCH="${_a:-$TARGET_ARCH}"

  save_config
}

# ── Prepare source (clone hoặc pull) ──────────────────────────────
prepare_source() {
  if [[ -n "$GOCLAW_REPO_URL" ]]; then
    if [[ -n "$GOCLAW_REPO_DIR" ]] && [[ -d "${GOCLAW_REPO_DIR}/.git" ]]; then
      # Dir đã có → chỉ pull
      inf "git pull từ ${GOCLAW_REPO_URL}..."
      git -C "$GOCLAW_REPO_DIR" fetch origin
      local _branch="${GOCLAW_BRANCH:-$(git -C "$GOCLAW_REPO_DIR" symbolic-ref --short HEAD 2>/dev/null)}"
      if [[ -n "$_branch" ]]; then
        git -C "$GOCLAW_REPO_DIR" checkout "$_branch"
        git -C "$GOCLAW_REPO_DIR" pull origin "$_branch"
      else
        git -C "$GOCLAW_REPO_DIR" pull
      fi
    else
      # Clone vào temp dir
      _TEMP_CLONE="$(mktemp -d /tmp/goclaw-src-XXXXX)"
      # Cleanup temp dir khi script kết thúc
      # shellcheck disable=SC2064
      trap "rm -rf '${_TEMP_CLONE}'" EXIT
      local _branch_args=()
      [[ -n "$GOCLAW_BRANCH" ]] && _branch_args=(--branch "$GOCLAW_BRANCH")
      inf "git clone ${GOCLAW_REPO_URL}${GOCLAW_BRANCH:+ (${GOCLAW_BRANCH})}..."
      git clone --depth 1 "${_branch_args[@]}" "$GOCLAW_REPO_URL" "$_TEMP_CLONE" \
        || die "Clone thất bại: ${GOCLAW_REPO_URL}"
      GOCLAW_REPO_DIR="$_TEMP_CLONE"
    fi
    ok "Source sẵn sàng: ${GOCLAW_REPO_DIR}"
  elif [[ -n "$GOCLAW_BRANCH" ]] && [[ -d "${GOCLAW_REPO_DIR}/.git" ]]; then
    # Có local dir + branch chỉ định → checkout + pull
    inf "git checkout ${GOCLAW_BRANCH}..."
    git -C "$GOCLAW_REPO_DIR" fetch origin
    git -C "$GOCLAW_REPO_DIR" checkout "$GOCLAW_BRANCH" \
      || die "Không checkout được branch: ${GOCLAW_BRANCH}"
    git -C "$GOCLAW_REPO_DIR" pull origin "$GOCLAW_BRANCH" 2>/dev/null || true
    ok "Branch: ${GOCLAW_BRANCH}"
  fi
}

# ── Detect frontend build info ─────────────────────────────────────
detect_frontend() {
  FRONTEND_DIR=""
  BUILD_CMD=""
  BUILD_OUT=""
  PKG_MANAGER=""

  # Look for frontend sub-directories
  local candidates=("web" "frontend" "ui" "app" "dashboard" ".")
  for dir in "${candidates[@]}"; do
    local check_dir="${GOCLAW_REPO_DIR}/${dir}"
    [[ "$dir" == "." ]] && check_dir="$GOCLAW_REPO_DIR"
    if [[ -f "${check_dir}/package.json" ]]; then
      FRONTEND_DIR="$check_dir"
      break
    fi
  done

  [[ -z "$FRONTEND_DIR" ]] && return 0  # No frontend found

  # Detect package manager
  if [[ -f "${FRONTEND_DIR}/bun.lockb" ]] || command -v bun &>/dev/null; then
    PKG_MANAGER="bun"
  elif [[ -f "${FRONTEND_DIR}/pnpm-lock.yaml" ]]; then
    PKG_MANAGER="pnpm"
  elif [[ -f "${FRONTEND_DIR}/yarn.lock" ]]; then
    PKG_MANAGER="yarn"
  else
    PKG_MANAGER="npm"
  fi

  # Detect build script from package.json
  if command -v jq &>/dev/null; then
    local _scripts
    _scripts=$(jq -r '.scripts | keys[]' "${FRONTEND_DIR}/package.json" 2>/dev/null || echo "")
    echo "$_scripts" | grep -q "^build$" && BUILD_CMD="${PKG_MANAGER} run build"
  fi
  [[ -z "$BUILD_CMD" ]] && BUILD_CMD="${PKG_MANAGER} run build"

  # Detect build output dir
  local out_candidates=("dist" "build" "out" ".next/standalone")
  for od in "${out_candidates[@]}"; do
    # also check vite.config / next.config for custom outDir
    if [[ -f "${FRONTEND_DIR}/${od}" ]] || [[ -d "${FRONTEND_DIR}/${od}" ]]; then
      BUILD_OUT="${FRONTEND_DIR}/${od}"
      break
    fi
  done
  # Default to dist if nothing exists yet
  [[ -z "$BUILD_OUT" ]] && BUILD_OUT="${FRONTEND_DIR}/dist"
}

# ── Detect Go entrypoint ───────────────────────────────────────────
detect_go_entrypoint() {
  GO_ENTRY=""
  local candidates=("./cmd/goclaw" "./cmd/server" "./cmd/main" ".")
  for ep in "${candidates[@]}"; do
    if [[ -d "${GOCLAW_REPO_DIR}/${ep#./}" ]] || [[ "$ep" == "." ]]; then
      GO_ENTRY="$ep"
      break
    fi
  done
  [[ -z "$GO_ENTRY" ]] && GO_ENTRY="."
}

# ══════════════════════════════════════════════════════════════════
#  Main
# ══════════════════════════════════════════════════════════════════

clear
echo -e "${C}${W}"
echo "  GoClaw — Local Build & Deploy"
echo -e "${N}"
hr

load_config
parse_args "$@"
collect_inputs

# ── Test SSH ────────────────────────────────────────────────────────
sec "Kiểm tra SSH"
inf "Kết nối đến ${VPS_USER}@${VPS_HOST}..."
ssh_cmd "echo ok" &>/dev/null || die "SSH không kết nối được đến ${VPS_HOST}"
ok "SSH OK"

# ── Check prerequisites ────────────────────────────────────────────
sec "Kiểm tra prerequisites"

command -v go &>/dev/null || die "Go chưa cài trên máy local. Cài tại: https://go.dev/dl/"
ok "Go $(go version | awk '{print $3}')"

GO_VERSION_LOCAL=$(go version | awk '{print $3}' | sed 's/go//')
IFS='.' read -r _maj _min _ <<< "$GO_VERSION_LOCAL"
[[ $_maj -lt 1 || ( $_maj -eq 1 && $_min -lt 22 ) ]] \
  && die "Go 1.22+ required, hiện có ${GO_VERSION_LOCAL}"

command -v rsync &>/dev/null || die "rsync chưa cài. Cài: brew install rsync / apt install rsync"
ok "rsync OK"

command -v git &>/dev/null || die "git chưa cài"
ok "git OK"

# ── Prepare source (clone/pull nếu cần) ────────────────────────────
prepare_source

# ── Detect build targets ───────────────────────────────────────────
detect_frontend
detect_go_entrypoint

echo -e "  Repo dir    : ${GOCLAW_REPO_DIR}"
echo -e "  Go entry    : ${GO_ENTRY}"
if [[ -n "$FRONTEND_DIR" ]]; then
  echo -e "  Frontend    : ${FRONTEND_DIR}"
  echo -e "  Pkg manager : ${PKG_MANAGER}"
  echo -e "  Build cmd   : ${BUILD_CMD}"
  echo -e "  Build out   : ${BUILD_OUT}"
else
  echo -e "  Frontend    : ${Y}không tìm thấy${N} (chỉ deploy binary)"
fi
echo -e "  Target arch : linux/${TARGET_ARCH}"
echo -e "  VPS         : ${VPS_USER}@${VPS_HOST}"
hr
read -rp "  Bắt đầu deploy? [Y/n] " _go
[[ "${_go:-Y}" =~ ^[Nn]$ ]] && { echo "Đã huỷ."; exit 0; }

START_TIME=$SECONDS

# ══════════════════════════════════════════════════════════════════
#  Step 1 — Build Go binary
# ══════════════════════════════════════════════════════════════════
sec "Step 1 — Build Go binary (linux/${TARGET_ARCH})"

cd "$GOCLAW_REPO_DIR"

BIN_OUTPUT="/tmp/goclaw_linux_${TARGET_ARCH}"

inf "Building..."
GOOS=linux GOARCH="$TARGET_ARCH" CGO_ENABLED=0 \
  go build -ldflags="-s -w" -o "$BIN_OUTPUT" "$GO_ENTRY" \
  || die "Build Go binary thất bại"

BIN_SIZE=$(du -sh "$BIN_OUTPUT" | cut -f1)
ok "Binary → ${BIN_OUTPUT} (${BIN_SIZE})"

# ══════════════════════════════════════════════════════════════════
#  Step 2 — Build Web UI (if frontend found)
# ══════════════════════════════════════════════════════════════════
if [[ -n "$FRONTEND_DIR" ]]; then
  sec "Step 2 — Build Web UI"

  cd "$FRONTEND_DIR"

  # Check package manager available
  command -v "$PKG_MANAGER" &>/dev/null || {
    wrn "${PKG_MANAGER} không tìm thấy, thử npm..."
    PKG_MANAGER="npm"
    BUILD_CMD="npm run build"
    command -v npm &>/dev/null || die "npm không cài — không build được Web UI"
  }

  inf "Install dependencies..."
  $PKG_MANAGER install --silent 2>/dev/null || $PKG_MANAGER install

  inf "Build Web UI (${BUILD_CMD})..."
  $BUILD_CMD || die "Build Web UI thất bại"

  [[ -d "$BUILD_OUT" ]] || die "Build output không tìm thấy tại: ${BUILD_OUT}"
  UI_FILES=$(find "$BUILD_OUT" -type f | wc -l)
  ok "Web UI built → ${BUILD_OUT} (${UI_FILES} files)"

  cd "$GOCLAW_REPO_DIR"
fi

# ══════════════════════════════════════════════════════════════════
#  Step 3 — Copy binary to VPS
# ══════════════════════════════════════════════════════════════════
sec "Step 3 — Deploy binary"

# Backup existing binary on VPS
inf "Backup binary cũ trên VPS..."
ssh_cmd "
  if [[ -f ${VPS_DEST_BIN} ]]; then
    cp -f ${VPS_DEST_BIN} ${VPS_DEST_BIN}.bak
    echo 'Backup OK'
  fi
" || wrn "Không backup được binary cũ"

inf "Dừng service trên VPS..."
ssh_cmd "systemctl stop goclaw 2>/dev/null || true"

inf "Copy binary → VPS:${VPS_DEST_BIN}..."
rsync_cmd "$BIN_OUTPUT" "${VPS_USER}@${VPS_HOST}:${VPS_DEST_BIN}"
ssh_cmd "chmod +x ${VPS_DEST_BIN}"
ok "Binary deployed"

rm -f "$BIN_OUTPUT"

# ══════════════════════════════════════════════════════════════════
#  Step 4 — Copy Web UI (if built)
# ══════════════════════════════════════════════════════════════════
if [[ -n "$FRONTEND_DIR" ]] && [[ -d "$BUILD_OUT" ]]; then
  sec "Step 4 — Deploy Web UI"

  inf "Đảm bảo thư mục tồn tại trên VPS: ${VPS_DEST_STATIC}"
  ssh_cmd "mkdir -p ${VPS_DEST_STATIC}"

  inf "Rsync static files → VPS:${VPS_DEST_STATIC}/..."
  rsync_cmd --delete "${BUILD_OUT}/" "${VPS_USER}@${VPS_HOST}:${VPS_DEST_STATIC}/"
  ok "Web UI deployed (${UI_FILES} files)"
fi

# ══════════════════════════════════════════════════════════════════
#  Step 5 — Restart & verify
# ══════════════════════════════════════════════════════════════════
sec "Step 5 — Restart & verify"

inf "Khởi động lại service..."
ssh_cmd "systemctl restart goclaw"

# Wait for service (with auto-rollback on failure)
inf "Chờ service khởi động..."
SERVICE_OK=false
for i in $(seq 1 10); do
  if ssh_cmd "systemctl is-active --quiet goclaw" 2>/dev/null; then
    SERVICE_OK=true
    break
  fi
  sleep 2
done

if [[ "$SERVICE_OK" == "false" ]]; then
  wrn "Service fail sau 20s — đang rollback về binary cũ..."
  ssh_cmd "
    if [[ -x ${VPS_DEST_BIN}.bak ]]; then
      cp -f ${VPS_DEST_BIN}.bak ${VPS_DEST_BIN}
      chmod +x ${VPS_DEST_BIN}
      systemctl restart goclaw
      echo 'Rollback OK'
    elif [[ -f ${VPS_DEST_BIN}.bak ]]; then
      echo 'Backup tồn tại nhưng không executable — bỏ qua rollback'
    else
      echo 'Không có backup để rollback'
    fi
  " 2>/dev/null || true
  ssh_cmd "journalctl -u goclaw -n 30 --no-hostname" 2>/dev/null || true
  die "Deploy thất bại (đã rollback). Kiểm tra logs: journalctl -u goclaw -f"
fi
ok "Service goclaw đang chạy"

# HTTP health check (đọc PORT từ /etc/goclaw.env trên VPS)
inf "Kiểm tra HTTP health check..."
HEALTH_OK=false
for i in $(seq 1 5); do
  if ssh_cmd "
    _port=\$(grep -E '^PORT=' /etc/goclaw.env 2>/dev/null | cut -d= -f2 | tr -d '\"' || echo 3000)
    curl -fsSL --max-time 3 \"http://127.0.0.1:\${_port:-3000}/\" -o /dev/null 2>/dev/null
  " 2>/dev/null; then
    HEALTH_OK=true
    break
  fi
  sleep 2
done
[[ "$HEALTH_OK" == "true" ]] && ok "HTTP health check OK" \
  || wrn "HTTP health check timeout — app có thể cần thêm thời gian khởi động"

# ── Done ───────────────────────────────────────────────────────────
ELAPSED=$(( SECONDS - START_TIME ))
ELAPSED_FMT=$(printf '%dm%02ds' $((ELAPSED/60)) $((ELAPSED%60)))

echo ""
hr
echo -e "${G}${W}   ✅  Deploy hoàn tất! (${ELAPSED_FMT})${N}"
hr
echo ""
echo -e "  ${W}VPS${N}     : ${VPS_USER}@${VPS_HOST}"
echo -e "  ${W}Binary${N}  : ${VPS_DEST_BIN}"
[[ -n "$FRONTEND_DIR" ]] && \
echo -e "  ${W}Web UI${N}  : ${VPS_DEST_STATIC}"
echo ""
echo -e "  ${W}Commands hữu ích:${N}"
echo -e "  Logs   : ${B}ssh ${VPS_USER}@${VPS_HOST} journalctl -u goclaw -f${N}"
echo -e "  Status : ${B}ssh ${VPS_USER}@${VPS_HOST} systemctl status goclaw${N}"
echo ""
