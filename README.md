# wenmar

`wenmar` is the command-line client for [Wenmar](https://app.wenmarpro.com), the shop
management system for repair shops. This repository holds **releases only**: prebuilt
binaries, their checksums, and the install scripts. The source code is private.

## Install

Linux and macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/wenmar-pro/wenmar/main/install.sh | sh
```

Windows (PowerShell, Windows 10 1803 or later):

```powershell
irm https://raw.githubusercontent.com/wenmar-pro/wenmar/main/install.ps1 | iex
```

With [mise](https://mise.jdx.dev):

```sh
mise use -g github:wenmar-pro/wenmar
```

Then sign in on this computer:

```sh
wenmar setup
```

Both install scripts download from this repository's
[releases](https://github.com/wenmar-pro/wenmar/releases) and refuse to install
unless the file matches the release's `SHA256SUMS`. Read them first if you like:
[install.sh](install.sh), [install.ps1](install.ps1).

Options (environment variables):

| Variable | Meaning | Default |
|---|---|---|
| `WENMAR_VERSION` | Install this version, e.g. `0.2.0` | the latest release |
| `WENMAR_INSTALL_DIR` | Where to put `wenmar` | `~/.local/bin`, or `%LOCALAPPDATA%\Programs\wenmar` on Windows |

## Update

```sh
wenmar upgrade            # install the newest release
wenmar upgrade --check    # only report whether one exists
wenmar upgrade --version 0.2.0   # install an exact version (also rolls back)
```

`wenmar upgrade` checks the SHA-256 before it replaces anything. If you installed with
mise, run `mise upgrade github:wenmar-pro/wenmar` instead.

`wenmar upgrade` asks GitHub's API for the latest release. Without a token GitHub
allows 60 requests an hour per network; if a shared office connection uses them up,
wait, or set `GITHUB_TOKEN` to any GitHub token.

## Platforms

Every release has one archive per platform plus `SHA256SUMS`:

| Platform | File |
|---|---|
| Linux x86_64 (glibc 2.17+) | `wenmar-x86_64-unknown-linux-gnu.tar.gz` |
| Linux arm64 (glibc 2.17+) | `wenmar-aarch64-unknown-linux-gnu.tar.gz` |
| macOS Apple silicon | `wenmar-aarch64-apple-darwin.tar.gz` |
| Windows x86_64 | `wenmar-x86_64-pc-windows-gnu.tar.gz` |

Each archive holds a single `wenmar` (or `wenmar.exe`) at its root. To verify by hand:

```sh
sha256sum -c SHA256SUMS --ignore-missing
```

## Help

Run `wenmar help`, or contact Wenmar support. Issues in this repository are not
monitored.
