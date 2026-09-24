#!/usr/bin/env bash

# Packages Realm of Kings builds into deploy.
#
# Windows produces:
#name: Build EDOPro
on: [push, pull_request]
env:
  COVERS_URL: ${{ secrets.COVERS_URL }}
  DEPENDENCIES_BASE_URL: https://github.com/edo9300/edopro-vcpkg-cache/releases/latest/download
  DEPLOY_DIR: deploy
  DEPLOY_REPO: ${{ secrets.DEPLOY_REPO }}
  DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
  DISCORD_APP_ID: ${{ secrets.DISCORD_APP_ID }}
  FIELDS_URL: ${{ secrets.FIELDS_URL }}
  PICS_URL: ${{ secrets.PICS_URL }}
  UPDATE_URL: ${{ secrets.UPDATE_URL }}
jobs:
  Windows:
    runs-on: windows-2022
    env:
      DEPLOY_BRANCH: travis-windows
      TRAVIS_OS_NAME: windows
      DXSDK_DIR: /c/d3d9sdk/
      VCPKG_ROOT: /c/vcpkg2
      BUILD_CONFIG: release
      ARCH: x86
    steps:
    - name: Set custom env vars
      shell: bash
      run: |
        echo "VCPKG_CACHE_ZIP_URL=$DEPENDENCIES_BASE_URL/installed_x86-windows-static.zip" >> $GITHUB_ENV
    - name: Add msbuild to PATH
      uses: microsoft/setup-msbuild@v3
    - uses: actions/checkout@v1
      with:
        ref: ${{ github.head_ref }}
        repository: ${{github.event.pull_request.head.repo.full_name}}
        fetch-depth: 1
        submodules: recursive
    - name: Install winxp components
      run: |
        Set-Location "C:\Program Files (x86)\Microsoft Visual Studio\Installer\"
        $InstallPath = "C:\Program Files\Microsoft Visual Studio\2022\Enterprise"
        $componentsToAdd= @(
          "Microsoft.VisualStudio.Component.VC.v141.x86.x64",
          "Microsoft.VisualStudio.Component.WinXP"
        )
        [string]$workloadArgs = $componentsToAdd | ForEach-Object {" --add " +  $_}
        $Arguments = ('/c', "vs_installer.exe", 'modify', '--installPath', "`"$InstallPath`"",$workloadArgs, '--quiet', '--norestart', '--nocache')
        # should be run twice
        $process = Start-Process -FilePath cmd.exe -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    - name: Install premake
      shell: bash
      run: ./travis/install-premake5.sh
    - name: Install dependencies
      shell: bash
      run: ./travis/dependencies.sh
    - name: Build
      shell: bash
      run: ./travis/build.sh
    - name: Build Realm of Kings launcher
      shell: cmd
      run: |
        call "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars32.bat"
        cl /nologo /std:c++17 /EHsc /O2 /DUNICODE /D_UNICODE travis\realm_launcher.cpp /Fe:"Realm of Kings.exe" /link /SUBSYSTEM:WINDOWS
        if not exist "Realm of Kings.exe" exit /b 1
    - name: Predeploy
      shell: bash
      run: ./travis/predeploy.sh
    - name: Deploy
      if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/master' }}
      shell: bash
      run: ./travis/deploy.sh
    - name: Upload Windows build
      if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/master' }}
      uses: actions/upload-artifact@v6
      with:
        name: windows
        path: deploy/
    - name: Log Failure
      uses: sarisia/actions-status-discord@v1
      if: failure()
      with:
        nodetail: true
        description: |
            [[${{ github.event.repository.name }}] ${{ github.job }} failed on ${{ github.ref }}](https://github.com/${{github.repository}}/actions/runs/${{github.run_id}})
        title: |

        color: 0xff0000
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        avatar_url: https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png
        username: Github

  Windows-mingw:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - deploy_name: windows-mingw
            package_name: installed_x86-windows-mingw-static.zip
            mingw_variant: -msvcrt
            vcpkg_triplet: -mingw-static
            extra_cflags: ""
          - deploy_name: windows-mingw-nt4
            package_name: installed_x86-windows-mingw-nt4-static.zip
            mingw_variant: _486-msvcrt_win98
            vcpkg_triplet: -i486-mingw-static
            extra_cflags: "-march=i486"
    env:
      DEPLOY_BRANCH: ${{ format('travis-{0}', matrix.deploy_name) }}
      TRAVIS_OS_NAME: linux
      TARGET_OS: windows
      DXSDK_DIR: /tmp/d3d9sdk/
      VCPKG_ROOT: /tmp/vcpkg2
      BUILD_CONFIG: release
      ARCH: win32
      MINGW_LITE_VARIANT: ${{ matrix.mingw_variant }}
      VCPKG_TRIPLET: ${{ matrix.vcpkg_triplet }}
      EXTRA_CFLAGS: ${{ matrix.extra_cflags }}
      CC: /usr/local/bin/i686-w64-mingw32-gcc
      CXX: /usr/local/bin/i686-w64-mingw32-g++
      AR: /usr/local/bin/i686-w64-mingw32-gcc-ar
    steps:
    - name: Set custom env vars
      shell: bash
      run: |
        echo "VCPKG_CACHE_ZIP_URL=$DEPENDENCIES_BASE_URL/${{ matrix.package_name }}" >> $GITHUB_ENV
    - uses: actions/checkout@v1
      with:
        ref: ${{ github.head_ref }}
        repository: ${{github.event.pull_request.head.repo.full_name}}
        fetch-depth: 1
        submodules: recursive
    - name: Install mingw lite toolchain
      shell: bash
      run: ./travis/install_mingw_lite.sh
    - name: Install premake
      shell: bash
      run: ./travis/install-premake5.sh
    - name: Install dependencies
      shell: bash
      run: ./travis/dependencies.sh
    - name: Build
      shell: bash
      run: ./travis/build.sh
    - name: Predeploy
      shell: bash
      run: |
        export CV2PDB="docker run --rm --volume $PWD:/work ghcr.io/projectignis/cv2pdb_builder:master"
        ./travis/predeploy.sh
    - name: Deploy
      if: ${{ false }}
      shell: bash
      run: ./travis/deploy.sh
    - uses: actions/upload-artifact@v6
      if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/master' }}
      with:
        name: ${{ matrix.deploy_name }}
        path: deploy/
    - name: Log Failure
      uses: sarisia/actions-status-discord@v1
      if: failure()
      with:
        nodetail: true
        description: |
            [[${{ github.event.repository.name }}] ${{ github.job }} failed on ${{ github.ref }}](https://github.com/${{github.repository}}/actions/runs/${{github.run_id}})
        title: |

        color: 0xff0000
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        avatar_url: https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png
        username: Github

  Linux-gcc-7-5-0:
    runs-on: ubuntu-latest
    container: ubuntu:18.04
    env:
      DEPLOY_BRANCH: travis-linux
      TRAVIS_OS_NAME: linux
      BUILD_CONFIG: release
      ARCH: x64
      PREMAKE_VERSION: 5.0.0-beta1
      ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION: true
      ACTIONS_RUNNER_FORCE_ACTIONS_NODE_VERSION: node16
    steps:
    - name: Set custom env vars
      shell: bash
      run: |
        echo "VCPKG_ROOT=$PWD/vcpkg" >> $GITHUB_ENV
        echo "VCPKG_CACHE_7Z_URL=$DEPENDENCIES_BASE_URL/installed_x64-linux.7z" >> $GITHUB_ENV
    - name: Get apt packages
      shell: bash
      run: |
        apt update
        apt install sudo
        sudo apt remove libsqlite3-dev
        sudo apt install -y g++ build-essential curl p7zip-full p7zip-rar zip git
    - uses: actions/checkout@v1
      with:
        ref: ${{ github.head_ref }}
        repository: ${{github.event.pull_request.head.repo.full_name}}
        fetch-depth: 1
        submodules: recursive
    - name: Install premake
      shell: bash
      run: ./travis/install-premake5.sh
    - name: Install dependencies
      shell: bash
      run: ./travis/dependencies.sh
    - name: Build
      shell: bash
      run: ./travis/build.sh
    - name: Predeploy
      shell: bash
      run: ./travis/predeploy.sh
    - name: Deploy
      if: ${{ false }}
      shell: bash
      run: ./travis/deploy.sh
    - name: Log Failure
      uses: sarisia/actions-status-discord@v1.12.0
      if: failure()
      with:
        nodetail: true
        description: |
            [[${{ github.event.repository.name }}] ${{ github.job }} failed on ${{ github.ref }}](https://github.com/${{github.repository}}/actions/runs/${{github.run_id}})
        title: |

        color: 0xff0000
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        avatar_url: https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png
        username: Github

  Linux-gcc-10-3-0:
    runs-on: ubuntu-22.04
    env:
      DEPLOY_BRANCH: travis-linux-gcc-10
      TRAVIS_OS_NAME: linux
      BUILD_CONFIG: release
      ARCH: x64
    steps:
    - name: Set custom env vars
      shell: bash
      run: |
        echo "VCPKG_ROOT=$PWD/vcpkg" >> $GITHUB_ENV
        echo "VCPKG_CACHE_7Z_URL=$DEPENDENCIES_BASE_URL/installed_x64-linux.7z" >> $GITHUB_ENV
    - name: Get apt packages
      shell: bash
      run: |
        sudo apt remove libsqlite3-dev
    - uses: actions/checkout@v1
      with:
        ref: ${{ github.head_ref }}
        repository: ${{github.event.pull_request.head.repo.full_name}}
        fetch-depth: 1
        submodules: recursive
    - name: Install premake
      shell: bash
      run: ./travis/install-premake5.sh
    - name: Install dependencies
      shell: bash
      run: ./travis/dependencies.sh
    - name: Build
      env:
        CC: gcc-10
        CXX: g++-10
      shell: bash
      run: ./travis/build.sh
    - name: Predeploy
      shell: bash
      run: ./travis/predeploy.sh
    - name: Deploy
      if: ${{ false }}
      shell: bash
      run: ./travis/deploy.sh
    - name: Log Failure
      uses: sarisia/actions-status-discord@v1
      if: failure()
      with:
        nodetail: true
        description: |
            [[${{ github.event.repository.name }}] ${{ github.job }} failed on ${{ github.ref }}](https://github.com/${{github.repository}}/actions/runs/${{github.run_id}})
        title: |

        color: 0xff0000
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        avatar_url: https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png
        username: Github

  Linux-gcc-11:
    runs-on: ubuntu-22.04
    env:
      DEPLOY_BRANCH: travis-linux-gcc-11
      TRAVIS_OS_NAME: linux
      BUILD_CONFIG: release
      ARCH: x64
    steps:
    - name: Set custom env vars
      shell: bash
      run: |
        echo "VCPKG_ROOT=$PWD/vcpkg" >> $GITHUB_ENV
        echo "VCPKG_CACHE_7Z_URL=$DEPENDENCIES_BASE_URL/installed_x64-linux.7z" >> $GITHUB_ENV
    - name: Get apt packages
      shell: bash
      run: |
        sudo apt remove libsqlite3-dev
    - uses: actions/checkout@v1
      with:
        ref: ${{ github.head_ref }}
        repository: ${{github.event.pull_request.head.repo.full_name}}
        fetch-depth: 1
        submodules: recursive
    - name: Install premake
      shell: bash
      run: ./travis/install-premake5.sh
    - name: Install dependencies
      shell: bash
      run: ./travis/dependencies.sh
    - name: Build
      env:
        CC: gcc-11
        CXX: g++-11
      shell: bash
      run: ./travis/build.sh
    - name: Predeploy
      shell: bash
      run: ./travis/predeploy.sh
    - name: Deploy
      if: ${{ false }}
      shell: bash
      run: ./travis/deploy.sh
    - name: Log Failure
      uses: sarisia/actions-status-discord@v1
      if: failure()
      with:
        nodetail: true
        description: |
            [[${{ github.event.repository.name }}] ${{ github.job }} failed on ${{ github.ref }}](https://github.com/${{github.repository}}/actions/runs/${{github.run_id}})
        title: |

        color: 0xff0000
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        avatar_url: https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png
        username: Github

  Linux-gcc-14:
    runs-on: ubuntu-24.04
    env:
      DEPLOY_BRANCH: travis-linux-gcc-14
      TRAVIS_OS_NAME: linux
      BUILD_CONFIG: release
      ARCH: x64
    steps:
    - name: Set custom env vars
      shell: bash
      run: |
        echo "VCPKG_ROOT=$PWD/vcpkg" >> $GITHUB_ENV
        echo "VCPKG_CACHE_7Z_URL=$DEPENDENCIES_BASE_URL/installed_x64-linux.7z" >> $GITHUB_ENV
    - name: Get apt packages
      shell: bash
      run: |
        sudo apt remove libsqlite3-dev
    - uses: actions/checkout@v1
      with:
        ref: ${{ github.head_ref }}
        repository: ${{github.event.pull_request.head.repo.full_name}}
        fetch-depth: 1
        submodules: recursive
    - name: Install premake
      shell: bash
      run: ./travis/install-premake5.sh
    - name: Install dependencies
      shell: bash
      run: ./travis/dependencies.sh
    - name: Build
      env:
        CC: gcc-14
        CXX: g++-14
      shell: bash
      run: ./travis/build.sh
    - name: Predeploy
      shell: bash
      run: ./travis/predeploy.sh
    - name: Deploy
      if: ${{ false }}
      shell: bash
      run: ./travis/deploy.sh
    - name: Log Failure
      uses: sarisia/actions-status-discord@v1
      if: failure()
      with:
        nodetail: true
        description: |
            [[${{ github.event.repository.name }}] ${{ github.job }} failed on ${{ github.ref }}](https://github.com/${{github.repository}}/actions/runs/${{github.run_id}})
        title: |

        color: 0xff0000
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        avatar_url: https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png
        username: Github

  Linux-aarch64-gcc-7-5-0:
    runs-on: ubuntu-latest
    container: ubuntu:18.04
    env:
      DEPLOY_BRANCH: travis-linux-aarch64
      TRAVIS_OS_NAME: linux
      BUILD_CONFIG: release
      ARCH: arm64
      PREMAKE_VERSION: 5.0.0-beta1
      ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION: true
      ACTIONS_RUNNER_FORCE_ACTIONS_NODE_VERSION: node16
    steps:
    - name: Set custom env vars
      shell: bash
      run: |
        echo "VCPKG_ROOT=$PWD/vcpkg" >> $GITHUB_ENV
        echo "VCPKG_CACHE_7Z_URL=$DEPENDENCIES_BASE_URL/installed_aarch64-linux.7z" >> $GITHUB_ENV
    - name: Get apt packages
      shell: bash
      run: |
        apt update
        apt install sudo
        sudo apt remove libsqlite3-dev
        sudo apt install -y g++ build-essential curl p7zip-full p7zip-rar zip git gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu
    - uses: actions/checkout@v1
      with:
        ref: ${{ github.head_ref }}
        repository: ${{github.event.pull_request.head.repo.full_name}}
        fetch-depth: 1
        submodules: recursive
    - name: Install premake
      shell: bash
      run: ./travis/install-premake5.sh
    - name: Install dependencies
      shell: bash
      run: |
        ./travis/dependencies.sh
    - name: Build
      env:
        CC: /usr/bin/aarch64-linux-gnu-gcc
        CXX: /usr/bin/aarch64-linux-gnu-g++
      shell: bash
      run: ./travis/build.sh
    - name: Predeploy
      shell: bash
      run: ./travis/predeploy.sh
    - name: Deploy
      if: ${{ false }}
      shell: bash
      run: ./travis/deploy.sh
    - name: Log Failure
      uses: sarisia/actions-status-discord@v1
      if: failure()
      with:
        nodetail: true
        description: |
            [[${{ github.event.repository.name }}] ${{ github.job }} failed on ${{ github.ref }}](https://github.com/${{github.repository}}/actions/runs/${{github.run_id}})
        title: |

        color: 0xff0000
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        avatar_url: https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png
        username: Github

  Mac-os-cctools:
    strategy:
      fail-fast: false
      matrix:
        arch: ["x86_64", "aarch64"]
        stdc: ["", "-stdc++"]
        include:
          - arch: 'x86_64'
            package_prefix: 'x64'
            triplet_prefix: 'x64'
          - arch: 'aarch64'
            package_prefix: 'aarch64'
            triplet_prefix: 'arm64'
            deploy_prefix: '-aarch64'
          - stdc: '-stdc++'
            compiler_suffix: '-gstdc++'
            vcpkg_triplet: '-osx-stdc'
    runs-on: ubuntu-latest
    env:
      DEPLOY_BRANCH: ${{ format('osx{0}{1}-cctools', matrix.deploy_prefix, matrix.stdc) }}
      TRAVIS_OS_NAME: linux
      VCPKG_ROOT: ./vcpkg2
      BUILD_CONFIG: release
      TARGET_OS: macosx
      ARCH: ${{ matrix.triplet_prefix }}
      CC: ${{ format('/opt/cctools/bin/{0}-apple-darwin21.4-clang', matrix.arch) }}
      CXX: ${{ format('/opt/cctools/bin/{0}-apple-darwin21.4-clang++{1}', matrix.arch, matrix.compiler_suffix) }}
      AR: ${{ format('/opt/cctools/bin/{0}-apple-darwin21.4-ar', matrix.arch) }}
      LDFLAGS: /opt/cctools/clang/lib/clang/22/lib/darwin/libclang_rt.osx.a
      CFLAGS: -Wno-deprecated
      CXXFLAGS: -Wno-deprecated
      VCPKG_TRIPLET: ${{ matrix.vcpkg_triplet }}
      ARCHIVE_NAME: ${{ format('installed_{0}-osx{1}-cctools.7z', matrix.package_prefix, matrix.stdc) }}
      OSXCROSS_NO_INCLUDE_PATH_WARNINGS: 1
    steps:
    - name: Set custom env vars
      shell: bash
      run: |
        echo "VCPKG_CACHE_7Z_URL=$DEPENDENCIES_BASE_URL/$ARCHIVE_NAME" >> $GITHUB_ENV
    - uses: actions/checkout@v1
      with:
        ref: ${{ github.head_ref }}
        repository: ${{github.event.pull_request.head.repo.full_name}}
        fetch-depth: 1
        submodules: recursive
    - name: Download cctools
      run: |
        cd /opt
        wget https://github.com/edo9300/cctools-build/releases/download/osxcross/cctools.tar.xz
        tar xf cctools.tar.xz
        echo "PATH=/opt/cctools/bin:/opt/cctools/clang/bin:$PATH" >> $GITHUB_ENV
    - name: Install premake
      shell: bash
      run: ./travis/install-premake5.sh
    - name: Install dependencies
      shell: bash
      run: ./travis/dependencies.sh
    - name: Build
      shell: bash
      run: ./travis/build.sh
    - name: Predeploy
      shell: bash
      run: ./travis/predeploy.sh
    - name: Deploy
      if: ${{ false }}
      shell: bash
      run: ./travis/deploy.sh
    - uses: actions/upload-artifact@v6
      if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/master' }}
      with:
        name: ${{ format('osx{0}{1}-cctools', matrix.deploy_prefix, matrix.stdc) }}
        path: ${{ format('bin/{0}/release/ygoprodll.app', matrix.triplet_prefix) }}
    - name: Log Failure
      uses: sarisia/actions-status-discord@v1
      if: failure()
      with:
        nodetail: true
        description: |
            [[${{ github.event.repository.name }}] ${{ github.job }} failed on ${{ github.ref }}](https://github.com/${{github.repository}}/actions/runs/${{github.run_id}})
        title: |

        color: 0xff0000
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        avatar_url: https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png
        username: Github

  Mac-os-universal-cctools:
    runs-on: ubuntu-slim
    strategy:
      matrix:
        stdc: ["", "-stdc++"]
    env:
      DEPLOY_BRANCH: ${{ format('travis-osx-universal{0}-cctools', matrix.stdc) }}
      TRAVIS_OS_NAME: linux
      TARGET_OS: macosx
    if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/master' }}
    needs: [ Mac-os-cctools ]
    steps:
    - uses: actions/checkout@v1
      with:
        ref: ${{ github.head_ref }}
        repository: ${{github.event.pull_request.head.repo.full_name}}
        fetch-depth: 1
    - name: Download lipo binary
      run: |
        wget https://github.com/edo9300/cctools-build/releases/download/preview/lipo
        chmod +x lipo
    - name: Download osx artifacts
      uses: actions/download-artifact@v7
    - name: Merge binaries
      shell: bash
      run: |
        ./lipo -create -output ygoprodll ./osx-aarch64${{matrix.stdc}}-cctools/ygoprodll.app ./osx${{matrix.stdc}}-cctools/ygoprodll.app
    - name: Move merged binary
      shell: bash
      run: |
        mkdir -p bin/release && cp ygoprodll bin/release/ygoprodll.app && chmod +x bin/release/ygoprodll.app
    - name: Predeploy
      shell: bash
      run: ./travis/predeploy.sh
    - name: Deploy
      if: ${{ false }}
      shell: bash
      run: ./travis/deploy.sh
    - name: Delete artifacts
      uses: geekyeggo/delete-artifact@v6
      with:
        name: |
            ${{ format('osx-aarch64{0}-cctools', matrix.stdc) }}
            ${{ format('osx{0}-cctools', matrix.stdc) }}
    - name: Log Failure
      uses: sarisia/actions-status-discord@v1
      if: failure()
      with:
        nodetail: true
        description: |
            [[${{ github.event.repository.name }}] ${{ github.job }} failed on ${{ github.ref }}](https://github.com/${{github.repository}}/actions/runs/${{github.run_id}})
        title: |

        color: 0xff0000
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        avatar_url: https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png
        username: Github

  Ios-cctools:
    strategy:
      fail-fast: false
      matrix:
        include:
          - deploy_name: ios-cctools
            package_name: installed_aarch64-ios-cctools.7z
            clang: arm64-iphoneos
            compiler_arch: arm
            triplet: arm64-ios
            premake_arch: arm64
            libclang_rt: libclang_rt.ios.a
          - deploy_name: ios-armv7-cctools
            package_name: installed_armv7-ios-cctools.7z
            clang: armv7-iphoneos
            compiler_arch: arm
            triplet: arm-ios
            premake_arch: armv7
            libclang_rt: libclang_rt.ios.a
          - deploy_name: iossim-x64-cctools
            package_name: installed_x64-iossim-cctools.7z
            clang: x86_64-iphonesimulator
            compiler_arch: x86_64
            triplet: x64-iossim
            premake_arch: x64-iossim
            libclang_rt: libclang_rt.iossim.a
    runs-on: ubuntu-latest
    env:
      DEPLOY_BRANCH: ${{ format('travis-{0}', matrix.deploy_name) }}
      TRAVIS_OS_NAME: linux
      VCPKG_ROOT: ./vcpkg2
      BUILD_CONFIG: release
      TARGET_OS: ios
      ARCH: ${{ matrix.premake_arch }}
      VCPKG_DEFAULT_TRIPLET: ${{ matrix.triplet }}
      CC: ${{ format('/opt/cctools/bin/{0}-clang', matrix.clang) }}
      CXX: ${{ format('/opt/cctools/bin/{0}-clang++', matrix.clang) }}
      AR: /opt/cctools/clang/bin/llvm-ar
      RANLIB: ${{ format('/opt/cctools/bin/{0}-apple-darwin11-ranlib', matrix.compiler_arch) }}
      LDFLAGS: ${{ format('/opt/cctools/darwin/{0}', matrix.libclang_rt) }}
    steps:
    - name: Set custom env vars
      shell: bash
      run: |
        echo "VCPKG_CACHE_7Z_URL=$DEPENDENCIES_BASE_URL/${{ matrix.package_name }}" >> $GITHUB_ENV
    - uses: actions/checkout@v1
      with:
        ref: ${{ github.head_ref }}
        repository: ${{github.event.pull_request.head.repo.full_name}}
        fetch-depth: 1
        submodules: recursive
    - name: Download cctools
      run: |
        cd /opt
        wget https://github.com/edo9300/cctools-build/releases/download/osxcross/cctools-ios.tar.xz
        tar xf cctools-ios.tar.xz
        echo "PATH=/opt/cctools/clang/bin:/opt/cctools/bin:$PATH" >> $GITHUB_ENV
    - name: Install premake
      shell: bash
      run: ./travis/install-premake5.sh
    - name: Install dependencies
      shell: bash
      run: ./travis/dependencies.sh
    - name: Build
      shell: bash
      run: ./travis/build.sh
    - name: Predeploy
      shell: bash
      run: ./travis/predeploy.sh
    - name: Deploy
      if: ${{ false }}
      shell: bash
      run: ./travis/deploy.sh
    - uses: actions/upload-artifact@v6
      if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/master' }}
      with:
        name: ${{ matrix.deploy_name }}
        path: ${{ format('bin/{0}/release/ygoprodll.app', matrix.premake_arch) }}
    - name: Log Failure
      uses: sarisia/actions-status-discord@v1
      if: failure()
      with:
        nodetail: true
        description: |
            [[${{ github.event.repository.name }}] ${{ github.job }} failed on ${{ github.ref }}](https://github.com/${{github.repository}}/actions/runs/${{github.run_id}})
        title: |

        color: 0xff0000
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        avatar_url: https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png
        username: Github

  Ios-universal-cctools:
    runs-on: ubuntu-slim
    env:
      DEPLOY_BRANCH: travis-ios-universal-cctools
      TRAVIS_OS_NAME: linux
      TARGET_OS: ios
    if: ${{ github.event_name == 'push' && github.ref == 'refs/heads/master' }}
    needs: [ Ios-cctools ]
    steps:
    - uses: actions/checkout@v1
      with:
        ref: ${{ github.head_ref }}
        repository: ${{github.event.pull_request.head.repo.full_name}}
        fetch-depth: 1
    - name: Download osx artifacts
      uses: actions/download-artifact@v7
    - name: Download ldid binary
      run: |
        cd /tmp
        wget https://github.com/sbingner/ldid/releases/download/v2.1.4/linux-ldid.tgz
        tar xf linux-ldid.tgz
        sudo cp ldid /usr/bin/
    - name: Download rcodesign binary
      run: |
        cd /tmp
        wget https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F0.29.0/apple-codesign-0.29.0-x86_64-unknown-linux-musl.tar.gz
        tar xf apple-codesign-0.29.0-x86_64-unknown-linux-musl.tar.gz
        sudo cp apple-codesign-0.29.0-x86_64-unknown-linux-musl/rcodesign /usr/bin/
    - name: Download lipo binary
      run: |
        wget https://github.com/edo9300/cctools-build/releases/download/preview/lipo
        chmod +x lipo
        ./lipo -create -output ygoprodll ./ios-cctools/ygoprodll.app ./ios-armv7-cctools/ygoprodll.app
        mkdir -p bin/release && cp ygoprodll bin/release/ygoprodll.app && chmod +x bin/release/ygoprodll.app
    - name: Predeploy
      shell: bash
      run: ./travis/predeploy.sh
    - name: Deploy
      if: ${{ false }}
      shell: bash
      run: ./travis/deploy.sh
    - name: Delete artifacts
      uses: geekyeggo/delete-artifact@v6
      with:
        name: |
            ios-cctools
            ios-armv7-cctools
    - name: Log Failure
      uses: sarisia/actions-status-discord@v1
      if: failure()
      with:
        nodetail: true
        description: |
            [[${{ github.event.repository.name }}] ${{ github.job }} failed on ${{ github.ref }}](https://github.com/${{github.repository}}/actions/runs/${{github.run_id}})
        title: |

        color: 0xff0000
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        avatar_url: https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png
        username: Github

  Notify-success:
    runs-on: ubuntu-slim
    needs: [ Windows, Linux-gcc-7-5-0, Mac-os-universal-cctools, Windows-mingw ]
    steps:
    - name: Log Success
      uses: sarisia/actions-status-discord@v1
      with:
        nodetail: true
        description: |
            [[${{ github.event.repository.name }}] Build EDOPro success on ${{ github.ref }}](https://github.com/${{github.repository}}/actions/runs/${{github.run_id}})
        title: |

        color: 0x0f9826
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        avatar_url: https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png
        username: Github
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
