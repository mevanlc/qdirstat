# Build the macOS app using the installed Homebrew libraries.
build-macos:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ "$(uname -s)" != Darwin ]]; then
        echo 'This recipe requires macOS.' >&2
        exit 1
    fi
    for tool in brew qmake6 make xcrun; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "Missing required tool: $tool" >&2
            echo 'Install Homebrew and Xcode Command Line Tools, then run:' >&2
            echo '  brew install just qtbase qt5compat qtsvg gettext' >&2
            exit 1
        fi
    done
    if ! xcrun --find clang++ >/dev/null 2>&1; then
        echo 'A C++ compiler is required. Install Xcode Command Line Tools with: xcode-select --install' >&2
        exit 1
    fi
    for formula in qtbase qt5compat qtsvg gettext; do
        prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
        if [[ -z "$prefix" || ! -d "$prefix" ]]; then
            echo "Missing Homebrew dependency. Install it with: brew install $formula" >&2
            exit 1
        fi
    done

    repo_root="$PWD"
    gettext_prefix="$(brew --prefix gettext)"
    mkdir -p build/macos
    cd build/macos
    qmake6 -r "$repo_root/qdirstat.pro" CONFIG+=release CONFIG-=debug \
        "INCLUDEPATH+=$gettext_prefix/include" "LIBS+=-L$gettext_prefix/lib -lintl"
    make -j "$(sysctl -n hw.ncpu)"

# Build and run automated bundle and offscreen startup smoke checks.
test-macos: build-macos
    #!/usr/bin/env bash
    set -euo pipefail

    app="$PWD/build/macos/src/qdirstat.app"
    executable="$app/Contents/MacOS/qdirstat"
    plutil -lint "$app/Contents/Info.plist"
    if [[ ! -x "$executable" ]]; then
        echo "Missing app executable: $executable" >&2
        exit 1
    fi
    qt_plugins="$(qmake6 -query QT_INSTALL_PLUGINS)"
    if [[ ! -f "$qt_plugins/platforms/libqoffscreen.dylib" ]]; then
        echo 'Missing Qt offscreen plugin. Restore it with: brew reinstall qtbase' >&2
        exit 1
    fi

    output="$(mktemp "${TMPDIR:-/tmp}/qdirstat-macos-help.XXXXXX")"
    trap 'rm -f "$output"' EXIT
    help_status=0
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORM_PLUGIN_PATH="$qt_plugins/platforms" \
        /usr/bin/perl -e 'alarm 30; exec @ARGV or die "exec failed: $!\n"' \
        "$executable" --help >"$output" 2>&1 || help_status=$?
    # QDirStat currently treats --help as a usage error and exits with status 1.
    if [[ "$help_status" -ne 1 ]] || ! grep -Fq 'Usage:' "$output"; then
        cat "$output" >&2
        echo "Startup smoke check failed (exit status $help_status; expected 1 and usage output)." >&2
        exit 1
    fi
    echo 'macOS bundle and startup smoke checks passed.'

# Build, check, and replace /Applications/QDirStat.app.
install-macos: test-macos
    #!/usr/bin/env bash
    set -euo pipefail

    destination=/Applications/QDirStat.app
    if [[ ! -w /Applications ]]; then
        echo 'Cannot write to /Applications. Run this recipe from an account with write access.' >&2
        exit 1
    fi
    staging="$(mktemp -d /Applications/.QDirStat-install.XXXXXX)"
    backup="$staging/previous.app"
    cleanup() {
        status=$?
        if [[ "$status" -ne 0 && ( -e "$backup" || -L "$backup" ) ]]; then
            if [[ -e "$destination" || -L "$destination" ]] || ! mv "$backup" "$destination"; then
                echo "Install failed; the previous app is preserved at: $backup" >&2
                return 1
            fi
        fi
        rm -rf "$staging"
        return "$status"
    }
    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    ditto "$PWD/build/macos/src/qdirstat.app" "$staging/QDirStat.app"
    if [[ -e "$destination" || -L "$destination" ]]; then
        mv "$destination" "$backup"
    fi
    mv "$staging/QDirStat.app" "$destination"
    echo "Installed $destination"
