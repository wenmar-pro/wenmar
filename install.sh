#!/bin/sh
# Install the wenmar client on Linux or macOS:
#   curl -fsSL https://raw.githubusercontent.com/wenmar-pro/wenmar/main/install.sh | sh
# Env:
#   WENMAR_VERSION       version to install, e.g. 0.2.0 (default: the latest release)
#   WENMAR_INSTALL_DIR   where to put `wenmar` (default: $HOME/.local/bin)
#   WENMAR_DOWNLOAD_URL  release downloads (default: GitHub releases of wenmar-pro/wenmar)
#   WENMAR_PAIR          a pairing code from the shop's owner: also pair this computer with the shop
#   WENMAR_VIEW          foxpro or modern: the view of `wenmar tui` (with WENMAR_PAIR)
#   WENMAR_NO_SHORTCUT   set to make no desktop shortcut
#   WENMAR_DESKTOP_DIR   where the shortcut goes (default: the desktop folder)
# The download is checked against the release's SHA256SUMS before install.
# Source of truth: dist/github-releases-repo/ in the private wenmar repository.
set -eu

DOWNLOAD_URL="${WENMAR_DOWNLOAD_URL:-https://github.com/wenmar-pro/wenmar/releases}"
DOWNLOAD_URL="${DOWNLOAD_URL%/}"
INSTALL_DIR="${WENMAR_INSTALL_DIR:-$HOME/.local/bin}"

say() { printf 'wenmar-install: %s\n' "$*" >&2; }
die() { say "error: $*"; exit 1; }

fetch() { # fetch URL DEST
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    die "curl or wget is required"
  fi
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d ' ' -f 1
  else
    die "sha256sum or shasum is required"
  fi
}

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64 | Linux/amd64) TARGET=x86_64-unknown-linux-gnu ;;
  Linux/aarch64 | Linux/arm64) TARGET=aarch64-unknown-linux-gnu ;;
  Darwin/arm64 | Darwin/aarch64) TARGET=aarch64-apple-darwin ;;
  Darwin/x86_64) TARGET=x86_64-apple-darwin ;;
  *) die "there is no wenmar build for $(uname -s)/$(uname -m)" ;;
esac

ASSET="wenmar-$TARGET.tar.gz"
if [ -n "${WENMAR_VERSION:-}" ]; then
  VERSION="${WENMAR_VERSION#v}"
  BASE="$DOWNLOAD_URL/download/v$VERSION"
  LABEL="wenmar $VERSION"
else
  BASE="$DOWNLOAD_URL/latest/download"
  LABEL="the latest wenmar"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

say "downloading $ASSET ($LABEL)"
fetch "$BASE/SHA256SUMS" "$TMP/SHA256SUMS" || die "could not download SHA256SUMS from $BASE"
fetch "$BASE/$ASSET" "$TMP/$ASSET" || die "could not download $ASSET from $BASE"

EXPECTED="$(awk -v a="$ASSET" '$2 == a || $2 == "*" a { print tolower($1); exit }' "$TMP/SHA256SUMS")"
[ -n "$EXPECTED" ] || die "SHA256SUMS has no line for $ASSET"
ACTUAL="$(sha256 "$TMP/$ASSET")"
[ "$EXPECTED" = "$ACTUAL" ] || die "checksum mismatch for $ASSET (expected $EXPECTED, got $ACTUAL); nothing was installed"

tar -xzf "$TMP/$ASSET" -C "$TMP" wenmar || die "$ASSET does not contain wenmar"
mkdir -p "$INSTALL_DIR"
cp "$TMP/wenmar" "$INSTALL_DIR/.wenmar.new"
chmod 755 "$INSTALL_DIR/.wenmar.new"
mv -f "$INSTALL_DIR/.wenmar.new" "$INSTALL_DIR/wenmar"

say "installed $LABEL to $INSTALL_DIR/wenmar"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) say "add $INSTALL_DIR to your PATH" ;;
esac

BIN_DIR="$(cd "$INSTALL_DIR" && pwd)"

# Pairing. stdin is /dev/null because under `curl | sh` it is this script.
NEXT="wenmar setup, then wenmar tui"
if [ -n "${WENMAR_PAIR:-}" ]; then
  set -- setup --yes --pairing-code "$WENMAR_PAIR"
  if [ -n "${WENMAR_VIEW:-}" ]; then set -- "$@" --view "$WENMAR_VIEW"; fi
  # What setup prints is for a person who ran it by hand (its own next steps):
  # it is shown only when setup fails.
  if SETUP_OUT="$("$BIN_DIR/wenmar" "$@" </dev/null 2>&1)"; then
    say "this computer is paired with the shop"
    NEXT="wenmar tui"
  else
    [ -z "$SETUP_OUT" ] || printf '%s\n' "$SETUP_OUT" >&2
    say "could not pair this computer; run: wenmar setup"
  fi
fi

desktop_dir() {
  if [ -n "${WENMAR_DESKTOP_DIR:-}" ]; then
    printf '%s\n' "$WENMAR_DESKTOP_DIR"
    return 0
  fi
  if command -v xdg-user-dir >/dev/null 2>&1; then
    d="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    # With no desktop folder configured xdg-user-dir prints $HOME itself.
    if [ -n "$d" ] && [ "$d" != "$HOME" ] && [ "$d" != "$HOME/" ]; then
      printf '%s\n' "$d"
      return 0
    fi
  fi
  printf '%s\n' "$HOME/Desktop"
}

# The text size of the window the shortcut opens.
FONT_SIZE=24

# write_linux_launcher FILE: opens `wenmar tui` in a terminal that takes a text
# size on its command line, else in any terminal at its own size.
write_linux_launcher() {
  mkdir -p "$(dirname "$1")"
  {
    printf '#!/bin/sh\nW="%s"\nS=%s\n' "$BIN_DIR/wenmar" "$FONT_SIZE"
    cat <<'LAUNCH'
has() { command -v "$1" >/dev/null 2>&1; }
if has ghostty; then exec ghostty --font-size="$S" -e "$W" tui; fi
if has kitty; then exec kitty -o font_size="$S" "$W" tui; fi
if has alacritty; then exec alacritty -o font.size="$S" -e "$W" tui; fi
if has foot; then exec foot -f "monospace:size=$S" "$W" tui; fi
if has wezterm; then exec wezterm --config font_size="$S" start -- "$W" tui; fi
if has xdg-terminal-exec; then exec xdg-terminal-exec "$W" tui; fi
if has x-terminal-emulator; then exec x-terminal-emulator -e "$W" tui; fi
if has gnome-terminal; then exec gnome-terminal -- "$W" tui; fi
if has konsole; then exec konsole -e "$W" tui; fi
if has xterm; then exec xterm -fa Monospace -fs "$S" -e "$W" tui; fi
echo "no terminal program found; run: $W tui" >&2
exit 1
LAUNCH
  } > "$1"
  chmod 755 "$1"
}

# write_mac_launcher FILE: opens Terminal on the app's command file at a large
# text size when the Mac lets it control Terminal (it asks once), else as usual.
write_mac_launcher() {
  {
    printf '#!/bin/sh\nS=%s\n' "$FONT_SIZE"
    cat <<'LAUNCH'
CMD="$(cd "$(dirname "$0")/../Resources" && pwd)/Wenmar.command"
/usr/bin/osascript - "$CMD" "$S" >/dev/null 2>&1 <<'OSA' && exit 0
on run argv
  set wasRunning to application "Terminal" is running
  tell application "Terminal"
    if wasRunning then
      set t to do script quoted form of (item 1 of argv)
    else
      -- Started just now: use the window it opened, not a second one.
      try
        set t to do script quoted form of (item 1 of argv) in window 1
      on error
        set t to do script quoted form of (item 1 of argv)
      end try
    end if
    try
      set font size of t to ((item 2 of argv) as integer)
    end try
    activate
  end tell
end run
OSA
exec /usr/bin/open -a Terminal "$CMD"
LAUNCH
  } > "$1"
  chmod 755 "$1"
}

write_desktop_entry() { # write_desktop_entry FILE LAUNCHER [ICON]
  {
    printf '[Desktop Entry]\nType=Application\nName=Wenmar Pro\n'
    printf 'Comment=Wenmar Pro terminal client\n'
    printf 'Exec="%s"\n' "$2"
    if [ -n "${3:-}" ]; then printf 'Icon=%s\n' "$3"; fi
    printf 'Terminal=false\nCategories=Office;\n'
  } > "$1"
  chmod 755 "$1"
}

# write_icon FILE: the program writes its own icon; true when the file is there.
write_icon() {
  mkdir -p "$(dirname "$1")"
  "$BIN_DIR/wenmar" icon "$1" </dev/null >/dev/null 2>&1 || true
  [ -s "$1" ]
}

# A "Wenmar Pro" shortcut that opens the terminal client. A desktop folder that
# does not exist is never created.
make_shortcut() {
  [ -z "${WENMAR_NO_SHORTCUT:-}" ] || return 0
  DESKTOP="$(desktop_dir)"
  case "$(uname -s)" in
    Darwin)
      [ -d "$DESKTOP" ] || return 0
      # An app folder, so the Finder shows the icon. Its program opens
      # Terminal on a command file kept inside the app.
      APP="$DESKTOP/Wenmar Pro.app"
      # Wenmar.app and Wenmar.command: earlier installs, named before "Wenmar Pro".
      rm -rf "$APP" "$DESKTOP/Wenmar.app" "$DESKTOP/Wenmar.command"
      mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
      printf '#!/bin/sh\nexec "%s" tui\n' "$BIN_DIR/wenmar" > "$APP/Contents/Resources/Wenmar.command"
      chmod 755 "$APP/Contents/Resources/Wenmar.command"
      write_mac_launcher "$APP/Contents/MacOS/Wenmar"
      write_icon "$APP/Contents/Resources/wenmar.icns" || true
      cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Wenmar Pro</string>
  <key>CFBundleDisplayName</key><string>Wenmar Pro</string>
  <key>CFBundleIdentifier</key><string>com.wenmarpro.wenmar-terminal</string>
  <key>CFBundleExecutable</key><string>Wenmar</string>
  <key>CFBundleIconFile</key><string>wenmar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
EOF
      say "added Wenmar Pro to the desktop"
      ;;
    Linux)
      DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
      APPS="$DATA/applications"
      mkdir -p "$APPS"
      ICON="$DATA/wenmar/wenmar.png"
      write_icon "$ICON" || ICON=""
      LAUNCHER="$DATA/wenmar/open-tui"
      write_linux_launcher "$LAUNCHER"
      write_desktop_entry "$APPS/wenmar.desktop" "$LAUNCHER" "$ICON"
      [ -d "$DESKTOP" ] || return 0
      write_desktop_entry "$DESKTOP/wenmar.desktop" "$LAUNCHER" "$ICON"
      # GNOME starts a desktop file only when it is marked trusted.
      if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v gio >/dev/null 2>&1; then
        gio set "$DESKTOP/wenmar.desktop" metadata::trusted true 2>/dev/null || true
      fi
      say "added Wenmar Pro to the desktop"
      ;;
  esac
}
make_shortcut || say "could not add the desktop shortcut"

say "next: $NEXT"
