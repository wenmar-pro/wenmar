#!/bin/sh
# Install the wenmar client on Linux or macOS:
#   curl -fsSL https://raw.githubusercontent.com/wenmar-pro/wenmar/main/install.sh | sh
# Env:
#   WENMAR_VERSION       version to install, e.g. 0.2.0 (default: the latest release)
#   WENMAR_INSTALL_DIR   where to put `wenmar` (default: $HOME/.local/bin)
#   WENMAR_DOWNLOAD_URL  release downloads (default: GitHub releases of wenmar-pro/wenmar)
#   WENMAR_STATION       the shop's access code: also sign this computer in to that station
#   WENMAR_VIEW          foxpro or modern: the view of `wenmar tui` (with WENMAR_STATION)
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

# The station. stdin is /dev/null because under `curl | sh` it is this script.
NEXT="wenmar setup, then wenmar tui"
if [ -n "${WENMAR_STATION:-}" ]; then
  set -- setup --yes --access-code "$WENMAR_STATION"
  if [ -n "${WENMAR_VIEW:-}" ]; then set -- "$@" --view "$WENMAR_VIEW"; fi
  if "$BIN_DIR/wenmar" "$@" </dev/null >/dev/null; then
    say "this computer is set up for station $WENMAR_STATION"
    NEXT="wenmar tui"
  else
    say "could not set up the station; run: wenmar setup"
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

write_desktop_entry() { # write_desktop_entry FILE [ICON]
  {
    printf '[Desktop Entry]\nType=Application\nName=Wenmar\n'
    printf 'Comment=Wenmar terminal client\n'
    printf 'Exec="%s" tui\n' "$BIN_DIR/wenmar"
    if [ -n "${2:-}" ]; then printf 'Icon=%s\n' "$2"; fi
    printf 'Terminal=true\nCategories=Office;\n'
  } > "$1"
  chmod 755 "$1"
}

# write_icon FILE: the program writes its own icon; true when the file is there.
write_icon() {
  mkdir -p "$(dirname "$1")"
  "$BIN_DIR/wenmar" icon "$1" </dev/null >/dev/null 2>&1 || true
  [ -s "$1" ]
}

# A "Wenmar" shortcut that opens the terminal client. A desktop folder that
# does not exist is never created.
make_shortcut() {
  [ -z "${WENMAR_NO_SHORTCUT:-}" ] || return 0
  DESKTOP="$(desktop_dir)"
  case "$(uname -s)" in
    Darwin)
      [ -d "$DESKTOP" ] || return 0
      # An app folder, so the Finder shows the icon. Its program opens
      # Terminal on a command file kept inside the app.
      APP="$DESKTOP/Wenmar.app"
      rm -rf "$APP" "$DESKTOP/Wenmar.command"
      mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
      printf '#!/bin/sh\nexec "%s" tui\n' "$BIN_DIR/wenmar" > "$APP/Contents/Resources/Wenmar.command"
      printf '#!/bin/sh\nexec /usr/bin/open -a Terminal "%s"\n' "$APP/Contents/Resources/Wenmar.command" > "$APP/Contents/MacOS/Wenmar"
      chmod 755 "$APP/Contents/Resources/Wenmar.command" "$APP/Contents/MacOS/Wenmar"
      write_icon "$APP/Contents/Resources/wenmar.icns" || true
      cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Wenmar</string>
  <key>CFBundleIdentifier</key><string>com.wenmarpro.wenmar-terminal</string>
  <key>CFBundleExecutable</key><string>Wenmar</string>
  <key>CFBundleIconFile</key><string>wenmar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
EOF
      say "added Wenmar to the desktop"
      ;;
    Linux)
      APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
      mkdir -p "$APPS"
      ICON="${XDG_DATA_HOME:-$HOME/.local/share}/wenmar/wenmar.png"
      write_icon "$ICON" || ICON=""
      write_desktop_entry "$APPS/wenmar.desktop" "$ICON"
      [ -d "$DESKTOP" ] || return 0
      write_desktop_entry "$DESKTOP/wenmar.desktop" "$ICON"
      # GNOME starts a desktop file only when it is marked trusted.
      if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v gio >/dev/null 2>&1; then
        gio set "$DESKTOP/wenmar.desktop" metadata::trusted true 2>/dev/null || true
      fi
      say "added Wenmar to the desktop"
      ;;
  esac
}
make_shortcut || say "could not add the desktop shortcut"

say "next: $NEXT"
