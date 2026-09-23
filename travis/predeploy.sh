#!/usr/bin/env bash

# Packages Realm of Kings builds into deploy.
#
# Windows produces:
#
#   1. realm-of-kings-windows.zip
#      Small automatic Realm engine update.
#
#   2. realm-of-kings-complete-windows.zip
#      Complete first-time Realm of Kings client.
#
# The complete client is assembled from the official Project Ignis
# Distribution, then the stock EDOPro executable is replaced with
# the Realm of Kings executable produced by this build.

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
        $OBJCOPY --only-keep-debug \
            bin/$ARCH/$BUILD_CONFIG/$1 \
            bin/$ARCH/$BUILD_CONFIG/$1.debug

        $STRIP --strip-debug --strip-unneeded \
            bin/$ARCH/$BUILD_CONFIG/$1

        $OBJCOPY \
            --add-gnu-debuglink=bin/$ARCH/$BUILD_CONFIG/$1.debug \
            bin/$ARCH/$BUILD_CONFIG/$1

        tar -Jcvf deploy/$1.debug.tgx \
            -C bin/$ARCH/$BUILD_CONFIG \
            $1.debug

        if [[ -n "${CV2PDB:-""}" ]]; then
            PDBNAME=`echo "$1" | cut -d'.' -f1`.pdb
            $CV2PDB -p$PDBNAME bin/$ARCH/$BUILD_CONFIG/$1
        fi
    fi
}

function bundle_if_exists {
    if [[ -f bin/$ARCH/$BUILD_CONFIG/$1.app ]]; then
        mkdir -p deploy/$1.app/Contents/MacOS
        cp bin/$ARCH/$BUILD_CONFIG/$1.app \
            deploy/$1.app/Contents/MacOS/EDOPro

        mkdir -p deploy/$1.app/Contents/Resources
        cp gframe/ygopro.icns \
            deploy/$1.app/Contents/Resources/edopro.icns

        cp gframe/Info.plist \
            deploy/$1.app/Contents/Info.plist

        if [[ -f bin/$ARCH/$BUILD_CONFIG/discord-launcher ]]; then
            mkdir -p \
                deploy/$1.app/Contents/MacOS/discord-launcher.app/Contents/MacOS

            cp bin/$ARCH/$BUILD_CONFIG/discord-launcher \
                deploy/$1.app/Contents/MacOS/discord-launcher.app/Contents/MacOS

            defaults write \
                "$PWD/deploy/$1.app/Contents/MacOS/discord-launcher.app/Contents/Info.plist" \
                "CFBundleIdentifier" \
                "io.github.edo9300.$1.discord"
        fi
    fi
}

function bundle_if_exists_ios {
    if [[ -f bin/$ARCH/$BUILD_CONFIG/$1.app ]]; then
        mkdir -p deploy/$1.app

        cp bin/$ARCH/$BUILD_CONFIG/$1.app \
            deploy/$1.app/$1

        ldid -S deploy/$1.app/$1

        cp -r ios-assets/* deploy/$1.app/

        cp gframe/ios-Info.plist \
            deploy/$1.app/Info.plist

        mkdir -p deploy/Payload

        cp -r deploy/$1.app \
            deploy/Payload/EDOPro.app

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
    # REALM OF KINGS CUSTOM ENGINE
    # ============================================================
    #
    # The source build target remains ygoprodll.exe.
    #
    # Realm distributes it as EDOPro.exe.
    #
    # DO NOT UPX-compress the Realm executable.
    # ============================================================

    copy_if_exists ygoprodll.exe
    copy_compressed_if_exists ygoprodll.pdb

    if [[ -f deploy/ygoprodll.exe ]]; then

        cp deploy/ygoprodll.exe deploy/EDOPro.exe

        # ========================================================
        # 1. NORMAL REALM ENGINE UPDATE
        # ========================================================
        #
        # This remains intentionally small.
        #
        # Existing Realm players receive only the custom engine
        # through the Realm automatic updater.
        # ========================================================

        cd deploy

        rm -f realm-of-kings-windows.zip
        rm -f realm-of-kings-windows.zip.md5
        rm -f update.json

        7z a -tzip \
            realm-of-kings-windows.zip \
            EDOPro.exe

        # --------------------------------------------------------
        # Generate MD5 required by ClientUpdater
        # --------------------------------------------------------

        certutil \
            -hashfile realm-of-kings-windows.zip MD5 \
            | grep -E '^[0-9A-Fa-f ]{32,}$' \
            | tr -d ' \r\n' \
            | tr 'A-F' 'a-f' \
            > realm-of-kings-windows.zip.md5

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

        echo
        echo "============================================================"
        echo "REALM ENGINE UPDATE PACKAGE CREATED"
        echo "============================================================"
        echo

        # ========================================================
        # 2. COMPLETE REALM OF KINGS WINDOWS CLIENT
        # ========================================================
        #
        # This is the package NEW PLAYERS download.
        #
        # The process is:
        #
        #   Project Ignis Distribution
        #             +
        #   Project Ignis Windows runtime/core/WindBot
        #             +
        #   Realm EDOPro.exe
        #             +
        #   Realm user_configs.json
        #             =
        #   Complete Realm of Kings client
        #
        # Players do NOT need an existing EDOPro installation.
        # ========================================================

        COMPLETE_DIR="$PWD/deploy/realm-of-kings-complete"
        COMPLETE_ZIP="$PWD/deploy/realm-of-kings-complete-windows.zip"

        rm -rf "$COMPLETE_DIR"
        rm -f "$COMPLETE_ZIP"

        echo
        echo "============================================================"
        echo "REALM COMPLETE CLIENT: Starting assembly"
        echo "============================================================"
        echo

        COMPLETE_OK=true

        # --------------------------------------------------------
        # STEP A
        #
        # Clone the official Project Ignis Distribution.
        #
        # --recurse-submodules is important because Distribution
        # contains resource repositories as submodules.
        # --------------------------------------------------------

        if git clone \
            --depth 1 \
            --recurse-submodules \
            --shallow-submodules \
            https://github.com/ProjectIgnis/Distribution.git \
            "$COMPLETE_DIR"; then

            echo
            echo "REALM COMPLETE CLIENT: Distribution downloaded"
            echo

        else

            echo
            echo "REALM COMPLETE CLIENT WARNING:"
            echo "Could not download Project Ignis Distribution."
            echo

            COMPLETE_OK=false
        fi

        # --------------------------------------------------------
        # STEP B
        #
        # Obtain the current official Project Ignis Windows runtime
        # from the latest edopro-assets release.
        #
        # Distribution's legacy update.sh still points at the old
        # kevinlul/edopro-bin repository, so Realm deliberately does
        # NOT call that script here.
        #
        # Instead we:
        #   1. Ask GitHub for the latest edopro-assets release.
        #   2. Find its IgnisUpdate-*-windows.zip asset.
        #   3. Download/extract it in a temporary directory.
        #   4. Locate EDOPro.exe so wrapper-folder layouts are safe.
        #   5. Merge that runtime into the Distribution staging tree.
        #
        # STEP C immediately replaces the stock EDOPro.exe with the
        # Realm executable produced by THIS SAME build.
        # --------------------------------------------------------

        if [[ "$COMPLETE_OK" == true ]]; then

            RUNTIME_TMP="$PWD/deploy/realm-ignis-runtime"
            RUNTIME_ZIP="$PWD/deploy/realm-ignis-runtime.zip"
            RELEASE_JSON="$PWD/deploy/realm-ignis-release.json"

            rm -rf "$RUNTIME_TMP"
            rm -f "$RUNTIME_ZIP"
            rm -f "$RELEASE_JSON"
            mkdir -p "$RUNTIME_TMP"

            if curl \
                --retry 5 \
                --connect-timeout 30 \
                --fail \
                --location \
                --silent \
                --show-error \
                -H "Accept: application/vnd.github+json" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "https://api.github.com/repos/ProjectIgnis/edopro-assets/releases/latest" \
                --output "$RELEASE_JSON"; then

                IGNIS_UPDATE_URL="$(grep -oE 'https://[^" ]+/IgnisUpdate-[^" ]+-windows\.zip' "$RELEASE_JSON" | head -n 1 || true)"

                if [[ -n "$IGNIS_UPDATE_URL" ]]; then

                    echo
                    echo "REALM COMPLETE CLIENT: Found official Ignis Windows runtime"
                    echo "  $IGNIS_UPDATE_URL"
                    echo

                    if curl \
                        --retry 5 \
                        --connect-timeout 30 \
                        --fail \
                        --location \
                        --silent \
                        --show-error \
                        "$IGNIS_UPDATE_URL" \
                        --output "$RUNTIME_ZIP"; then

                        if 7z x -y "$RUNTIME_ZIP" -o"$RUNTIME_TMP"; then

                            STOCK_EXE="$(find "$RUNTIME_TMP" -type f -iname 'EDOPro.exe' -print -quit)"

                            if [[ -n "$STOCK_EXE" ]]; then

                                RUNTIME_ROOT="$(dirname "$STOCK_EXE")"

                                cp -a "$RUNTIME_ROOT"/. "$COMPLETE_DIR"/

                                echo
                                echo "REALM COMPLETE CLIENT: Ignis Windows runtime installed"
                                echo

                            else

                                echo
                                echo "REALM COMPLETE CLIENT WARNING:"
                                echo "Official Ignis Windows update did not contain EDOPro.exe."
                                echo

                                COMPLETE_OK=false
                            fi

                        else

                            echo
                            echo "REALM COMPLETE CLIENT WARNING:"
                            echo "Could not extract the official Ignis Windows update."
                            echo

                            COMPLETE_OK=false
                        fi

                    else

                        echo
                        echo "REALM COMPLETE CLIENT WARNING:"
                        echo "Could not download the official Ignis Windows update."
                        echo

                        COMPLETE_OK=false
                    fi

                else

                    echo
                    echo "REALM COMPLETE CLIENT WARNING:"
                    echo "Latest edopro-assets release has no IgnisUpdate-*-windows.zip asset."
                    echo

                    COMPLETE_OK=false
                fi

            else

                echo
                echo "REALM COMPLETE CLIENT WARNING:"
                echo "Could not read the latest Project Ignis asset release."
                echo

                COMPLETE_OK=false
            fi

            rm -rf "$RUNTIME_TMP"
            rm -f "$RUNTIME_ZIP"
            rm -f "$RELEASE_JSON"
        fi

        # --------------------------------------------------------
        # STEP C
        #
        # Replace the normal EDOPro engine with the Realm engine
        # produced by THIS SAME GitHub Actions build.
        # --------------------------------------------------------

        if [[ "$COMPLETE_OK" == true ]]; then

            if [[ -f "$PWD/deploy/EDOPro.exe" ]]; then

                cp -f \
                    "$PWD/deploy/EDOPro.exe" \
                    "$COMPLETE_DIR/EDOPro.exe"

                echo
                echo "REALM COMPLETE CLIENT: Realm engine installed"
                echo

            else

                echo
                echo "REALM COMPLETE CLIENT WARNING:"
                echo "deploy/EDOPro.exe was not found."
                echo

                COMPLETE_OK=false
            fi
        fi

        # --------------------------------------------------------
        # STEP D
        #
        # Install Realm's user configuration.
        #
        # This gives new players the Realm repository/server
        # configuration without requiring them to edit JSON.
        # --------------------------------------------------------

        if [[ "$COMPLETE_OK" == true ]]; then

            mkdir -p "$COMPLETE_DIR/config"

            if curl \
                --retry 5 \
                --connect-timeout 30 \
                --fail \
                --location \
                --silent \
                --show-error \
                "https://raw.githubusercontent.com/Hacato/Realm-Of-Kings/main/user_configs.json" \
                --output "$COMPLETE_DIR/config/user_configs.json"; then

                echo
                echo "REALM COMPLETE CLIENT: Realm configuration installed"
                echo

            else

                echo
                echo "REALM COMPLETE CLIENT WARNING:"
                echo "Could not download Realm user_configs.json."
                echo

                COMPLETE_OK=false
            fi
        fi

        # --------------------------------------------------------
        # STEP E
        #
        # Remove Git metadata.
        #
        # Players need the game resources, not the Git history or
        # repository internals used to assemble the package.
        # --------------------------------------------------------

        if [[ "$COMPLETE_OK" == true ]]; then

            find "$COMPLETE_DIR" \
                -name ".git" \
                -type d \
                -prune \
                -exec rm -rf {} + || true

            find "$COMPLETE_DIR" \
                -name ".git" \
                -type f \
                -delete || true

            rm -f "$COMPLETE_DIR/.gitmodules"
            rm -f "$COMPLETE_DIR/.gitattributes"
            rm -f "$COMPLETE_DIR/.gitignore"

            echo
            echo "REALM COMPLETE CLIENT: Git metadata removed"
            echo
        fi

        # --------------------------------------------------------
        # STEP F
        #
        # Package the COMPLETE client.
        #
        # We enter the staging directory first so the ZIP contains
        # the actual game files at its root rather than another
        # unnecessary wrapper directory.
        # --------------------------------------------------------

        if [[ "$COMPLETE_OK" == true ]]; then

            (
                cd "$COMPLETE_DIR"

                7z a \
                    -tzip \
                    "$COMPLETE_ZIP" \
                    ./*
            )

            echo
            echo "============================================================"
            echo "REALM COMPLETE CLIENT CREATED SUCCESSFULLY"
            echo
            echo "File:"
            echo "  deploy/realm-of-kings-complete-windows.zip"
            echo
            echo "A new player can extract this ZIP and launch EDOPro.exe."
            echo "============================================================"
            echo

        else

            echo
            echo "============================================================"
            echo "REALM COMPLETE CLIENT WAS NOT CREATED"
            echo
            echo "The normal Realm engine update was still created."
            echo "Check the warnings above for the failed bootstrap step."
            echo "============================================================"
            echo

            rm -f "$COMPLETE_ZIP"
        fi

        # --------------------------------------------------------
        # Remove temporary complete-client staging directory.
        # --------------------------------------------------------

        rm -rf "$COMPLETE_DIR"

    else

        echo
        echo "REALM ERROR: deploy/ygoprodll.exe was not produced."
        echo "Realm Windows packages cannot be created."
        echo
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
