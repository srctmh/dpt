#!/data/data/com.termux/files/usr/bin/bash
set -u

TOOL_VERSION="3.0.0"
REPO_RAW="https://raw.githubusercontent.com/srctmh/dpt/main"
ENGINE_API="https://api.github.com/repos/luoyesiqiu/dpt-shell/releases/latest"
BASE="${HOME}/.srctmh-dpt"
TMP="${BASE}/tmp_install"
CONFIG="${BASE}/config"
RUNTIME="${BASE}/runtime"
MIN_SPACE_KB=204800

if [ -t 1 ]; then
  BOLD=$'\033[1m'; RESET=$'\033[0m'
  GREEN=$'\033[32m'; RED=$'\033[31m'
  CYAN=$'\033[36m'; YELLOW=$'\033[33m'
  MAGENTA=$'\033[35m'; DIM=$'\033[2m'
else
  BOLD=""; RESET=""; GREEN=""; RED=""; CYAN=""; YELLOW=""; MAGENTA=""; DIM=""
fi

BW=36
box_top(){ printf "%s╔══════════════════════════════════════╗%s\n" "$CYAN" "$RESET"; }
box_bot(){ printf "%s╚══════════════════════════════════════╝%s\n" "$CYAN" "$RESET"; }
box_mid(){ printf "%s╠══════════════════════════════════════╣%s\n" "$CYAN" "$RESET"; }
box_line(){
  local raw="$1" vis len pad sp i=0
  vis=$(printf '%s' "$raw" | sed -E 's/\x1b\[[0-9;]*m//g')
  len=${#vis}
  if [ "$len" -gt "$BW" ]; then
    vis="${vis:0:$((BW-1))}…"
    raw="$vis"
    len=${#vis}
  fi
  pad=$((BW-len)); sp=""
  while [ "$i" -lt "$pad" ]; do sp="$sp "; i=$((i+1)); done
  printf "%s║%s %s%s %s║%s\n" "$CYAN" "$RESET" "$raw" "$sp" "$CYAN" "$RESET"
}
ok(){   printf "  %s[✓]%s %s\n" "$GREEN" "$RESET" "$1"; }
info(){ printf "  %s[i]%s %s\n" "$CYAN" "$RESET" "$1"; }
warn(){ printf "  %s[!]%s %s\n" "$YELLOW" "$RESET" "$1"; }
die(){
  echo
  box_top
  box_line "${RED}${BOLD}INSTALL FAILED${RESET}"
  box_mid
  box_line "$1"
  box_bot
  echo
  printf "  Help: %s@srcmax%s on Telegram\n\n" "$BOLD" "$RESET"
  rm -rf "$TMP" 2>/dev/null || true
  exit 1
}
cleanup(){ rm -rf "$TMP" 2>/dev/null || true; }
trap 'echo; box_top; box_line "${YELLOW}Setup interrupted${RESET}"; box_bot; cleanup; exit 130' INT TERM

banner(){
  clear 2>/dev/null || true
  box_top
  box_line "${BOLD}${CYAN}SRC TMH DPT INSTALLER${RESET}"
  box_line "Fully Automatic Setup"
  box_line "Version ${TOOL_VERSION}"
  box_bot
  echo
}

need_cmd(){ command -v "$1" >/dev/null 2>&1; }

ensure_pkg(){
  local bin="$1" pkg="${2:-$1}"
  if need_cmd "$bin"; then
    return 0
  fi
  info "Installing ${pkg}..."
  if pkg install -y "$pkg" >/dev/null 2>&1; then
    need_cmd "$bin" && return 0
  fi
  return 1
}

banner

if ! need_cmd pkg; then
  die "Termux required. Open Termux app and run again."
fi
ok "Termux environment"

net_ok=0
for url in "https://api.github.com" "https://github.com" "https://1.1.1.1"; do
  if curl -fsS --connect-timeout 8 --max-time 12 -o /dev/null "$url" 2>/dev/null; then
    net_ok=1
    break
  fi
done
if [ "$net_ok" -eq 0 ]; then
  if need_cmd pkg; then
    pkg update -y >/dev/null 2>&1 || true
    pkg install -y curl >/dev/null 2>&1 || true
  fi
  for url in "https://api.github.com" "https://github.com"; do
    if curl -fsS --connect-timeout 8 --max-time 12 -o /dev/null "$url" 2>/dev/null; then
      net_ok=1
      break
    fi
  done
fi
[ "$net_ok" -eq 1 ] || die "No internet connection."
ok "Internet connection"

STORAGE_ROOT=""
for p in "/storage/emulated/0" "/sdcard" "${HOME}/storage/shared"; do
  if [ -d "$p" ] && [ -w "$p" ]; then STORAGE_ROOT="$p"; break; fi
done
if [ -z "$STORAGE_ROOT" ]; then
  warn "Requesting storage access..."
  if need_cmd termux-setup-storage; then
    termux-setup-storage 2>/dev/null || true
    sleep 2
  fi
  for p in "/storage/emulated/0" "/sdcard" "${HOME}/storage/shared"; do
    if [ -d "$p" ] && [ -w "$p" ]; then STORAGE_ROOT="$p"; break; fi
  done
fi
if [ -z "$STORAGE_ROOT" ]; then
  warn "Storage not writable yet — using default path"
  STORAGE_ROOT="/storage/emulated/0"
else
  ok "Storage ready"
fi

avail=$(df "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "${avail:-}" ] && [ "$avail" -lt "$MIN_SPACE_KB" ] 2>/dev/null; then
  die "Need at least 200MB free space."
fi
ok "Disk space OK"

echo
info "Installing dependencies (automatic)..."
pkg update -y >/dev/null 2>&1 || true

ensure_pkg curl curl || die "Could not install curl"
ensure_pkg wget wget || warn "wget optional — skipped"
ensure_pkg unzip unzip || die "Could not install unzip"
ensure_pkg python3 python || ensure_pkg python python || warn "python optional for some features"

if ! need_cmd termux-clipboard-set; then
  info "Installing termux-api (clipboard support)..."
  pkg install -y termux-api >/dev/null 2>&1 || warn "termux-api optional"
fi

if ! need_cmd java; then
  info "Installing Java (this may take a minute)..."
  if ! pkg install -y openjdk-21 >/dev/null 2>&1; then
    if ! pkg install -y openjdk-17 >/dev/null 2>&1; then
      pkg install -y openjdk-11 >/dev/null 2>&1 || true
    fi
  fi
fi
need_cmd java || die "Java install failed. Run: pkg install openjdk-21"
if ! java -version >/dev/null 2>&1; then
  die "Java installed but not working."
fi
ok "Java ready"
ok "All dependencies ready"

echo
info "Fetching protection engine..."
mkdir -p "$TMP"
RELEASE="${TMP}/release.json"
if ! curl -fL --retry 5 --retry-delay 2 --connect-timeout 20 \
  -H "Accept: application/vnd.github+json" \
  "$ENGINE_API" -o "$RELEASE" 2>/dev/null; then
  die "Cannot reach GitHub for engine release."
fi

ASSET_URL=$(grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+\.zip"' "$RELEASE" 2>/dev/null \
  | sed -E 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -n1)
TAG=$(grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' "$RELEASE" 2>/dev/null \
  | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -n1)
[ -n "$ASSET_URL" ] || die "Engine package not found in release."
ok "Engine package: ${TAG:-unknown}"

ZIP="${TMP}/engine.zip"
info "Downloading engine..."
if ! curl -fL --retry 5 --retry-delay 3 --connect-timeout 20 --max-time 1800 \
  -o "$ZIP" "$ASSET_URL" 2>/dev/null; then
  die "Engine download failed."
fi
[ -s "$ZIP" ] || die "Downloaded engine is empty."
unzip -t "$ZIP" >/dev/null 2>&1 || die "Engine archive corrupted."
ok "Engine verified"

rm -rf "$RUNTIME"
mkdir -p "$RUNTIME"
unzip -q "$ZIP" -d "$RUNTIME" || die "Could not extract engine."
JAR=$(find "$RUNTIME" -type f -name "dpt.jar" 2>/dev/null | head -n1)
[ -n "$JAR" ] || die "dpt.jar missing inside engine package."
ENGINE_DIR=$(dirname "$JAR")
ok "Engine installed"

mkdir -p "$BASE"
cat > "$CONFIG" <<EOF
DPT_JAR=$JAR
DPT_RUNTIME=$ENGINE_DIR
DPT_ENGINE_VERSION=${TAG:-unknown}
TOOL_VERSION=$TOOL_VERSION
INSTALL_DIR=$BASE
STORAGE_ROOT=$STORAGE_ROOT
EOF
ok "Configuration saved"

TOOL_SRC="${TMP}/dpt"
got=0
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
if [ -f "${SCRIPT_DIR}/dpt" ]; then
  cp "${SCRIPT_DIR}/dpt" "$TOOL_SRC"
  got=1
fi
if [ "$got" -eq 0 ]; then
  if curl -fL --retry 4 --connect-timeout 15 "${REPO_RAW}/dpt" -o "$TOOL_SRC" 2>/dev/null && [ -s "$TOOL_SRC" ]; then
    got=1
  fi
fi
[ "$got" -eq 1 ] || die "Could not locate main tool (dpt)."

if head -n 5 "$TOOL_SRC" | grep -q "python3 - "; then
  if grep -q "subprocess.call" "$TOOL_SRC" 2>/dev/null; then
    die "Repo dpt looks like a broken protected build. Upload clean dpt."
  fi
fi

chmod 755 "$TOOL_SRC"
mkdir -p "${PREFIX}/bin"
cp "$TOOL_SRC" "${PREFIX}/bin/dpt"
chmod 755 "${PREFIX}/bin/dpt"
ok "Launcher installed (command: dpt)"

if [ ! -x "${PREFIX}/bin/dpt" ]; then die "Self-test: dpt not executable"; fi
if [ ! -f "$JAR" ]; then die "Self-test: engine jar missing"; fi
ok "Self-test passed"

cleanup
echo
box_top
box_line "${GREEN}${BOLD}INSTALLATION COMPLETE${RESET}"
box_mid
box_line "Version  : ${TOOL_VERSION}"
box_line "Engine   : ${TAG:-unknown}"
box_line "Command  : dpt"
box_bot
echo
printf "  Type %s%sdpt%s to launch.\n\n" "$BOLD" "$CYAN" "$RESET"
printf "  Developed by %s@SRCTMH%s\n" "$BOLD" "$RESET"
printf "  Telegram: %s@srcmax%s\n\n" "$BOLD" "$RESET"
