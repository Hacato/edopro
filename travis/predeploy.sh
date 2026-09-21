#!/usr/bin/env bash

# Packages just the binaries into deploy

set -euxo pipefail

BUILD_CONFIG=${BUILD_CONFIG:-release}
TARGET_OS=${TARGET_OS:-$TRAVIS_OS_NAME}
PLATFORM=${1:-$TARGET_OS}
ARCH=${ARCH:-""}
OBJCOPY="objcopy"
STRIP="strip"

function copy_if_exists {
    if [[ -f bin/$ARCH/$BUILD_CONFIG/$1 ]]; then
        cp bin/$ARCH/$BUILD_CONFIG/$1 deploy
    fi
}

function copy_compressed_if_exists {
    if [[ -f bin/$ARCH/$BUILD_CONFIG/$1 ]]; then
        tar -Jcvf deploy/$1.tgx -C bin/$ARCH/$BUILD_CONFIG $1
    fi
}

function compress_if_exist {
    if [[ -f bin/$ARCH/$BUILD_CONFIG/$1 ]]; then
        if [[ -n "${CV2PDB:-""}" ]]; then
            # upx doesn't like binaries touched by cv2pdb
            ./upx deploy/$1 -o deploy/compressed-$1 --force
        else
            ./upx deploy/$1 -o deploy/compressed-$1
        fi
    fi
}

function strip_if_exists {
    if [[ -f bin/$ARCH/$BUILD_CONFIG/$1 ]]; then
        $OBJCOPY --only-keep-debug bin/$ARCH/$BUILD_CONFIG/$1 bin/$ARCH/$BUILD_CONFIG/$1.debug
        $STRIP --strip-debug --strip-unneeded bin/$ARCH/$BUILD_CONFIG/$1
        $OBJCOPY --add-gnu-debuglink=bin/$ARCH/$BUILD_CONFIG/$1.debug bin/$ARCH/$BUILD_CONFIG/$1
        tar -Jcvf deploy/$1.debug.tgx -C bin/$ARCH/$BUILD_CONFIG $1.debug
        if [[ -n "${CV2PDB:-""}" ]]; then
            PDBNAME=`echo "$1" | cut -d'.' -f1`.pdb
            $CV2PDB -p$PDBNAME bin/$ARCH/$BUILD_CONFIG/$1
        fi
    fi
}

function bundle_if_exists {
    if [[ -f bin/$ARCH/$BUILD_CONFIG/$1.app ]]; then
        mkdir -p deploy/$1.app/Contents/MacOS
        cp bin/$ARCH/$BUILD_CONFIG/$1.app deploy/$1.app/Contents/MacOS/EDOPro

        mkdir -p deploy/$1.app/Contents/Resources
        cp gframe/ygopro.icns deploy/$1.app/Contents/Resources/edopro.icns
        cp gframe/Info.plist deploy/$1.app/Contents/Info.plist

        if [[ -f bin/$ARCH/$BUILD_CONFIG/discord-launcher ]]; then
            mkdir -p deploy/$1.app/Contents/MacOS/discord-launcher.app/Contents/MacOS
            cp bin/$ARCH/$BUILD_CONFIG/discord-launcher deploy/$1.app/Contents/MacOS/discord-launcher.app/Contents/MacOS
            defaults write "$PWD/deploy/$1.app/Contents/MacOS/discord-launcher.app/Contents/Info.plist" "CFBundleIdentifier" "io.github.edo9300.$1.discord"
        fi
    fi
}

function bundle_if_exists_ios {
    if [[ -f bin/$ARCH/$BUILD_CONFIG/$1.app ]]; then
        mkdir -p deploy/$1.app
        cp bin/$ARCH/$BUILD_CONFIG/$1.app deploy/$1.app/$1
        ldid -S deploy/$1.app/$1
        cp -r ios-assets/* deploy/$1.app/
        cp gframe/ios-Info.plist deploy/$1.app/Info.plist
        mkdir -p deploy/Payload
        cp -r deploy/$1.app deploy/Payload/EDOPro.app
        rcodesign sign deploy/Payload/EDOPro.app
        cd deploy
        zip -0 -y -r EDOPro.ipa Payload
        rm -rf Payload
        cd ..
    fi
}

mkdir -p deploy

if [[ "$PLATFORM" == "windows" ]]; then
    if [[ "$ARCH" == "x86" ]] || [[ "$ARCH" == "win32" ]]; then
        ARCH="."
    fi

    if [[ -n "${MINGW_LITE_VARIANT:-""}" ]]; then
        strip_if_exists ygopro.exe
    fi
    copy_if_exists ygopro.exe
    compress_if_exist ygopro.exe
    copy_compressed_if_exists ygopro.pdb

    if [[ -n "${MINGW_LITE_VARIANT:-""}" ]]; then
        strip_if_exists ygoprodll.exe
    fi

    # ============================================================
    # Realm of Kings custom client
    # ============================================================
    #
    # The build target remains ygoprodll.exe.
    #
    # For Realm distribution, however, we package that executable
    # as EDOPro.exe so it replaces the executable players already
    # launch from their existing EDOPro installation.
    #
    # Keep the original unpacked binary. Do NOT UPX-compress it.
    #
    copy_if_exists ygoprodll.exe
    copy_compressed_if_exists ygoprodll.pdb

    if [[ -f deploy/ygoprodll.exe ]]; then

        # Create the Realm-distribution copy.
        cp deploy/ygoprodll.exe deploy/EDOPro.exe

        # ========================================================
        # 1. NORMAL REALM ENGINE UPDATE
        # ========================================================
        #
        # The automatic updater receives EDOPro.exe.
        #
        # This lets the Realm engine replace the normal executable
        # that the player already launches.
        #
        cd deploy

        7z a -tzip realm-of-kings-windows.zip EDOPro.exe

        # Generate the MD5 required by EDOPro's ClientUpdater.
        certutil -hashfile realm-of-kings-windows.zip MD5 \
            | grep -E '^[0-9A-Fa-f ]{32,}$' \
            | tr -d ' \r\n' \
            | tr 'A-F' 'a-f' \
            > realm-of-kings-windows.zip.md5

        # Generate updater metadata from this exact build.
        UPDATE_MD5="$(cat realm-of-kings-windows.zip.md5)"

        cat > update.json <<EOF
[
  {
    "name": "realm-of-kings-windows.zip",
    "url": "https://raw.githubusercontent.com/Hacato/Realm-Of-Kings-Client/travis-windows/realm-of-kings-windows.zip",
    "md5": "${UPDATE_MD5}"
  }
]
EOF

        cd ..

        # ========================================================
        # 2. REALM OF KINGS STARTER PACKAGE
        # ========================================================
        #
        # One-time bootstrap package.
        #
        # It contains:
        #
        #   EDOPro.exe
        #   config/user_configs.json
        #
        # When merged into an existing EDOPro installation, the
        # existing EDOPro.exe is replaced by the Realm engine.
        #
        STARTER_DIR="deploy/realm-of-kings-starter"

        rm -rf "$STARTER_DIR"
        mkdir -p "$STARTER_DIR/config"

        # Use the same Realm-distribution executable.
        cp deploy/EDOPro.exe "$STARTER_DIR/EDOPro.exe"

        # Pull the current Realm configuration from the Realm repo.
        #
        # A failure here does NOT break the normal engine package.
        if curl \
            --fail \
            --location \
            --silent \
            --show-error \
            "https://raw.githubusercontent.com/Hacato/Realm-Of-Kings/main/user_configs.json" \
            --output "$STARTER_DIR/config/user_configs.json"; then

            echo "REALM STARTER: user_configs.json downloaded successfully"

            cd "$STARTER_DIR"

            7z a -tzip \
                ../realm-of-kings-starter-windows.zip \
                EDOPro.exe \
                config/user_configs.json

            cd ../..

            echo "REALM STARTER: realm-of-kings-starter-windows.zip created"

        else
            echo "REALM STARTER WARNING: Could not download user_configs.json"
            echo "REALM STARTER WARNING: Normal Realm engine deployment will continue"

            rm -rf "$STARTER_DIR"
        fi

        # Remove temporary starter staging directory.
        rm -rf "$STARTER_DIR"
    fi
fi

if [[ "$PLATFORM" == "linux" ]]; then
    if [[ "$ARCH" == "arm64" ]]; then
        OBJCOPY="aarch64-linux-gnu-objcopy"
        STRIP="aarch64-linux-gnu-strip"
    fi
    strip_if_exists ygopro
    copy_if_exists ygopro
    compress_if_exist ygopro
    strip_if_exists ygoprodll
    copy_if_exists ygoprodll
    compress_if_exist ygoprodll
fi

if [[ "$PLATFORM" == "macosx" ]]; then
    bundle_if_exists ygopro
    bundle_if_exists ygoprodll
fi

if [[ "$PLATFORM" == "ios" ]]; then
    bundle_if_exists_ios ygopro
    bundle_if_exists_ios ygoprodll
fi
