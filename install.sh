#!/bin/sh
# Install the wenmar client on Linux or macOS:
#   curl -fsSL https://raw.githubusercontent.com/wenmar-pro/wenmar/main/install.sh | sh
# Env:
#   WENMAR_VERSION       version to install, e.g. 0.2.0 (default: the latest release)
#   WENMAR_INSTALL_DIR   where to put `wenmar` (default: $HOME/.local/bin)
#   WENMAR_DOWNLOAD_URL  release downloads (default: GitHub releases of wenmar-pro/wenmar)
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
say "next: wenmar setup"
