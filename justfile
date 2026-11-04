# Build and sign the macOS app using the installed Homebrew libraries.
build-macos:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ "$(uname -s)" != Darwin ]]; then
        echo 'This recipe requires macOS.' >&2
        exit 1
    fi
    for tool in brew qmake6 make xcrun security codesign plutil; do
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

    identity="${QDIRSTAT_SIGN_IDENTITY:-QDirStat Local Code Signing}"
    keychain="$HOME/Library/Keychains/login.keychain-db"
    fingerprint="$(security find-identity -v -p codesigning "$keychain" |
        awk -F '"' -v name="$identity" '$2 == name { n = split($1, fields, " "); print fields[n] }')"
    if [[ ! "$fingerprint" =~ ^[[:xdigit:]]{40}$ ]]; then
        echo "Missing or ambiguous code-signing identity in the login Keychain: $identity" >&2
        echo 'Run just setup-signing-macos once, or set QDIRSTAT_SIGN_IDENTITY to an existing identity name.' >&2
        exit 1
    fi

    repo_root="$PWD"
    gettext_prefix="$(brew --prefix gettext)"
    mkdir -p build/macos
    cd build/macos
    qmake6 -r "$repo_root/qdirstat.pro" CONFIG+=release CONFIG-=debug \
        "INCLUDEPATH+=$gettext_prefix/include" "LIBS+=-L$gettext_prefix/lib -lintl"
    make -j "$(sysctl -n hw.ncpu)"
    # qmake can retain an older generated plist during incremental builds.
    plutil -replace CFBundleIdentifier -string io.github.mevanlc.qdirstat src/qdirstat.app/Contents/Info.plist
    codesign --force --sign "$fingerprint" --keychain "$keychain" --timestamp=none src/qdirstat.app
    codesign --verify --strict --verbose=2 src/qdirstat.app

# Build and run automated bundle and offscreen startup smoke checks.
test-macos: build-macos
    #!/usr/bin/env bash
    set -euo pipefail

    app="$PWD/build/macos/src/qdirstat.app"
    executable="$app/Contents/MacOS/qdirstat"
    plutil -lint "$app/Contents/Info.plist"
    codesign --verify --strict "$app"
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
    codesign --verify --strict "$staging/QDirStat.app"
    if [[ -e "$destination" || -L "$destination" ]]; then
        mv "$destination" "$backup"
    fi
    mv "$staging/QDirStat.app" "$destination"
    echo "Installed $destination"

# One-time: create a reusable local code-signing identity in the login Keychain.
setup-signing-macos:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077

    if [[ "$(uname -s)" != Darwin ]]; then
        echo 'This recipe requires macOS.' >&2
        exit 1
    fi
    for tool in brew security; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "Missing required tool: $tool (Homebrew OpenSSL is available with: brew install openssl)" >&2
            exit 1
        fi
    done

    identity='QDirStat Local Code Signing'
    keychain="$HOME/Library/Keychains/login.keychain-db"
    identities="$(security find-identity -v -p codesigning "$keychain")"
    if grep -Fq "\"$identity\"" <<< "$identities"; then
        echo "Signing identity already exists: $identity"
        exit 0
    fi

    openssl_prefix="$(brew --prefix openssl 2>/dev/null || true)"
    openssl_bin="$openssl_prefix/bin/openssl"
    if [[ -z "$openssl_prefix" || ! -x "$openssl_bin" ]]; then
        echo 'Missing Homebrew OpenSSL. Install it with: brew install openssl' >&2
        exit 1
    fi

    temporary="$(mktemp -d "${TMPDIR:-/tmp}/qdirstat-signing.XXXXXX")"
    trap 'rm -rf "$temporary"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    # Reuse a partially configured certificate rather than changing the signer.
    if security find-certificate -c "$identity" -p "$keychain" >"$temporary/cert.pem" 2>/dev/null; then
        if ! "$openssl_bin" x509 -in "$temporary/cert.pem" -checkend 0 -noout; then
            echo 'The existing QDirStat certificate has expired; repair its signing identity in Keychain Access.' >&2
            exit 1
        fi
        echo "Reusing the existing certificate: $identity"
    else
        if ! "$openssl_bin" req -x509 -newkey rsa:3072 -nodes -sha256 -days 3650 -subj "/CN=$identity" \
            -addext 'basicConstraints=critical,CA:FALSE' \
            -addext 'keyUsage=critical,digitalSignature' \
            -addext 'extendedKeyUsage=critical,codeSigning' \
            -keyout "$temporary/key.pem" -out "$temporary/cert.pem" 2>"$temporary/openssl.log"; then
            cat "$temporary/openssl.log" >&2
            echo 'Certificate generation failed. Use Homebrew OpenSSL: brew install openssl' >&2
            exit 1
        fi
        password="$("$openssl_bin" rand -hex 32)"
        printf '%s\n' "$password" >"$temporary/password"
        "$openssl_bin" pkcs12 -export -inkey "$temporary/key.pem" -in "$temporary/cert.pem" \
            -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
            -out "$temporary/identity.p12" -passout "file:$temporary/password"
        security import "$temporary/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign
    fi

    echo 'Trusting this certificate for code signing in your user account. macOS may ask for your password.'
    security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$temporary/cert.pem"
    identities="$(security find-identity -v -p codesigning "$keychain")"
    if ! grep -Fq "\"$identity\"" <<< "$identities"; then
        echo 'No usable QDirStat signing identity was found. Restore the matching private key in Keychain Access.' >&2
        exit 1
    fi
    echo "Ready to sign repeated QDirStat builds with: $identity"
