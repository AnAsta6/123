#!/bin/sh
# Copyright 2000-2021 JetBrains s.r.o. and contributors. Use of this source code is governed by the Apache 2.0 license that can be found in the LICENSE file.

### See plugins/remote-dev-server/bin/launcher.sh for actual launcher code
set -e -u -f

IDE_BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
IDE_HOME="$(dirname "$IDE_BIN_DIR")"
REMOTE_DEV_SERVER_DIR="$IDE_HOME/plugins/remote-dev-server/bin"

check_is_not_gcompat_dynamic_linker() {
    if /lib64/ld-linux-x86-64.so.2 2>&1 | grep -q "gcompat ELF interpreter stub"; then
      return 1
    elif /lib/ld-linux-aarch64.so.1 2>&1 | grep -q "gcompat ELF interpreter stub"; then
      return 1
    fi

    return 0
}

check_glibc_in_getconf() {
    glibc_version=$(getconf GNU_LIBC_VERSION 2>/dev/null)
    if [ -n "$glibc_version" ]; then
        return 0
    fi

    return 1
}

check_ldd_version_is_not_musl() {
  if ldd --version 2>&1 | grep -q musl; then
    return 1
  fi

  return 0
}

IS_DARWIN=0
case "$(uname)" in
  Darwin* )
    IS_DARWIN=1
    ;;
esac

# new launcher doesn't work with musl yet
IS_GLIBC=0
if [ $IS_DARWIN -eq 0 ]; then
  if check_is_not_gcompat_dynamic_linker && check_glibc_in_getconf && check_ldd_version_is_not_musl; then
    IS_GLIBC=1
  fi
fi

IS_NATIVE_LAUNCHER=0
if [ $IS_DARWIN -eq 1 ] || [ $IS_GLIBC -eq 1 ]; then
  IS_NATIVE_LAUNCHER=1
fi

export REMOTE_DEV_SERVER_IS_NATIVE_LAUNCHER="$IS_NATIVE_LAUNCHER"

REMOTE_DEV_SERVER_LAUNCHER_PATH="$REMOTE_DEV_SERVER_DIR/launcher.sh"
if [ $IS_NATIVE_LAUNCHER -eq 1 ]; then
  REMOTE_DEV_SERVER_LAUNCHER_PATH="$IDE_BIN_DIR/remote-dev-server"
fi

if [ ! -f "$REMOTE_DEV_SERVER_LAUNCHER_PATH" ]; then
  echo "ERROR! Remote development launcher is not found."
  echo "Please make sure you use a correct distribution with enabled Remote Development and related libraries included: '/plugins/remove-development'"
  exit 1
fi

export IDEA_RESTART_VIA_EXIT_CODE=88

REMOTE_DEV_LAUNCHER_NAME_FOR_USAGE_WITH_EXIT_CODE_CHECK="${REMOTE_DEV_LAUNCHER_NAME_FOR_USAGE:-$(basename "$0")}"
export REMOTE_DEV_LAUNCHER_NAME_FOR_USAGE="$REMOTE_DEV_LAUNCHER_NAME_FOR_USAGE_WITH_EXIT_CODE_CHECK"

# do not add `exec` to this script - this breaks restarts as `exec` effectively terminates execution of this script
while true; do
  set +e
  if [ $IS_NATIVE_LAUNCHER -eq 1 ]; then
    "$REMOTE_DEV_SERVER_LAUNCHER_PATH" "$@"
  else
    "$REMOTE_DEV_SERVER_LAUNCHER_PATH" "pycharm.sh" "PY" "PYCHARM" "pycharm" "-Xmx2048m" "$@"
  fi
  host_exit_code=$?
  set -e
  # restart on special exit code, otherwise forward the exit code to caller
  if [ $host_exit_code -ne $IDEA_RESTART_VIA_EXIT_CODE ]; then
    exit $host_exit_code
  fi
done
