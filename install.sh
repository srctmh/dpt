#!/data/data/com.termux/files/usr/bin/bash
# MAX Protection Installer
set -u

TOOL_VERSION="4.0.0"
BASE="${HOME}/.maxguard"
TMP="${BASE}/tmp_install"
CONFIG="${BASE}/config"
MIN_SPACE_KB=102400

if [ -t 1 ]; then
  BOLD=$'\033[1m'; RESET=$'\033[0m'
  GREEN=$'\033[32m'; RED=$'\033[31m'
  CYAN=$'\033[36m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'
else
  BOLD=""; RESET=""; GREEN=""; RED=""; CYAN=""; YELLOW=""; DIM=""
fi

BW=46
box_top(){ printf "%s╔══════════════════════════════════════════════╗%s\n" "$CYAN" "$RESET"; }
box_bot(){ printf "%s╚══════════════════════════════════════════════╝%s\n" "$CYAN" "$RESET"; }
box_mid(){ printf "%s╠══════════════════════════════════════════════╣%s\n" "$CYAN" "$RESET"; }
box_line(){
  local raw="$1" vis len pad sp i=0
  vis=$(printf '%s' "$raw" | sed -E 's/\x1b\[[0-9;]*m//g')
  len=${#vis}
  if [ "$len" -gt "$BW" ]; then vis="${vis:0:$((BW-1))}…"; raw="$vis"; len=${#vis}; fi
  pad=$((BW-len)); sp=""
  while [ "$i" -lt "$pad" ]; do sp="$sp "; i=$((i+1)); done
  printf "%s║%s %s%s %s║%s\n" "$CYAN" "$RESET" "$raw" "$sp" "$CYAN" "$RESET"
}
ok(){ printf "  %s[✓]%s %s\n" "$GREEN" "$RESET" "$1"; }
info(){ printf "  %s[i]%s %s\n" "$CYAN" "$RESET" "$1"; }
die(){
  echo; box_top; box_line "${RED}${BOLD}INSTALL FAILED${RESET}"; box_mid; box_line "$1"; box_bot
  echo; printf "  Help: %s@srcmax%s\n\n" "$BOLD" "$RESET"
  rm -rf "$TMP" 2>/dev/null; exit 1
}
need_cmd(){ command -v "$1" >/dev/null 2>&1; }
ensure_pkg(){
  local bin="$1" pkg="${2:-$1}"
  need_cmd "$bin" && return 0
  info "Installing ${pkg}..."
  pkg install -y "$pkg" >/dev/null 2>&1 || return 1
  need_cmd "$bin"
}

clear 2>/dev/null || true
box_top
box_line "${BOLD}${CYAN}MAX PROTECTION INSTALLER${RESET}"
box_line "Version ${TOOL_VERSION}"
box_bot
echo

need_cmd pkg || die "Termux required."
ok "Termux"

if ! need_cmd curl; then pkg update -y >/dev/null 2>&1; pkg install -y curl >/dev/null 2>&1; fi

STORAGE_ROOT=""
for p in "/storage/emulated/0" "/sdcard" "${HOME}/storage/shared"; do
  [ -d "$p" ] && [ -w "$p" ] && { STORAGE_ROOT="$p"; break; }
done
if [ -z "$STORAGE_ROOT" ]; then
  need_cmd termux-setup-storage && termux-setup-storage 2>/dev/null || true
  sleep 2
  for p in "/storage/emulated/0" "/sdcard" "${HOME}/storage/shared"; do
    [ -d "$p" ] && [ -w "$p" ] && { STORAGE_ROOT="$p"; break; }
  done
fi
[ -z "$STORAGE_ROOT" ] && STORAGE_ROOT="/storage/emulated/0"
ok "Storage ready"

echo
info "Installing dependencies..."
pkg update -y >/dev/null 2>&1 || true
ensure_pkg curl curl || die "curl failed"
ensure_pkg unzip unzip || die "unzip failed"
ensure_pkg zip zip || die "zip failed"
need_cmd python3 || pkg install -y python >/dev/null 2>&1 || true
need_cmd termux-clipboard-set || pkg install -y termux-api >/dev/null 2>&1 || true
ensure_pkg apktool apktool || true
need_cmd aapt || pkg install -y aapt >/dev/null 2>&1 || true
need_cmd apksigner || pkg install -y apksigner >/dev/null 2>&1 || true
need_cmd zipalign || true

if ! need_cmd java; then
  info "Installing Java..."
  pkg install -y openjdk-21 >/dev/null 2>&1 || pkg install -y openjdk-17 >/dev/null 2>&1 || pkg install -y openjdk-11 >/dev/null 2>&1 || true
fi
need_cmd java || die "Java required: pkg install openjdk-21"
ok "Dependencies ready"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)

# Engine must be in package
[ -f "${SCRIPT_DIR}/core/max.jar" ] || die "Engine missing (core/max.jar)"
[ -d "${SCRIPT_DIR}/core/shell-files" ] || die "Engine runtime missing"

mkdir -p "$BASE"
# Copy engine + libs + apkshield into home
rm -rf "${BASE}/core"
cp -a "${SCRIPT_DIR}/core" "${BASE}/core"
ok "Engine installed (inbuilt)"

if [ -d "${SCRIPT_DIR}/libs" ]; then
  rm -rf "${BASE}/libs"
  cp -a "${SCRIPT_DIR}/libs" "${BASE}/libs"
  ok "Libraries ready"
fi
if [ -f "${SCRIPT_DIR}/apkshield.py" ]; then
  cp "${SCRIPT_DIR}/apkshield.py" "${BASE}/apkshield.py"
  chmod 755 "${BASE}/apkshield.py"
  ok "Resource Protect ready"
fi

cat > "$CONFIG" <<EOF
TOOL_VERSION=$TOOL_VERSION
INSTALL_DIR=$BASE
STORAGE_ROOT=$STORAGE_ROOT
CORE_JAR=${BASE}/core/max.jar
CORE_DIR=${BASE}/core
LIBS_DIR=${BASE}/libs
APKSHIELD=${BASE}/apkshield.py
CREDITS_URL=https://example.com/gatecredit
EOF
ok "Config saved"

[ -f "${SCRIPT_DIR}/maxdpt" ] || die "maxdpt tool missing"
chmod 755 "${SCRIPT_DIR}/maxdpt"
mkdir -p "${PREFIX}/bin"
cp "${SCRIPT_DIR}/maxdpt" "${PREFIX}/bin/maxdpt"
chmod 755 "${PREFIX}/bin/maxdpt"
ok "Command: maxdpt"

echo
box_top
box_line "${GREEN}${BOLD}INSTALLATION COMPLETE${RESET}"
box_mid
box_line "Command : maxdpt"
box_line "Version : ${TOOL_VERSION}"
box_bot
echo
printf "  Type %smaxdpt%s to launch.\n\n" "$BOLD" "$CYAN" "$RESET"
printf "  Developed by %s@SRCTMH%s\n\n" "$BOLD" "$RESET"
