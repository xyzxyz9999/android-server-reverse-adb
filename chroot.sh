#!/usr/bin/env bash
set -euo pipefail

# Utilities to interact with the chroot

CHROOT_DISTRO_NAME=void
CHROOT_ENTER_CMD="chroot-distro login $CHROOT_DISTRO_NAME"

usage() {
  cat <<HELP
Usage: $(basename "${BASH_SOURCE[0]}") [COMMAND] [ARGS...]

Commands:
  run [CMD...] Run a command inside the Void chroot
                    With args: run whoami
                    With heredoc:
                      run <<'CMDS'
                      whoami
                      ls /etc
                      CMDS

  login Interactive shell into the Void chroot

  push SRC [DEST] Copy file/dir from host into chroot
                    Default dest: /tmp/<filename>
                      push myfile.txt
                      push myfile.txt /etc/myfile.conf

  pull SRC [DEST] Copy file/dir from chroot to host
                    Default dest: current directory
                      pull /etc/resolv.conf .

  os-info Print user, OS, and kernel info

  help, --help Show this message
HELP
}

### Executing commands
# Run both one-liners and multi-line
run() {
  if [ $# -gt 0 ]; then
    echo "$*" | adb shell -T "$CHROOT_ENTER_CMD"
  else
    adb shell -T "$CHROOT_ENTER_CMD"
  fi
}

# e.g.
# ```
# run <<'CMDS'
# whoami
# ls /etc
# CMDS
# # or with local variable expansion:
# run <<CMDS
# echo "hello from $HOSTNAME"
# whoami
# CMDS
# ```

### File operations
push() {
  [[ $# -lt 1 ]] && { echo "Usage: push SRC [DEST]" >&2; return 1; }
  local src="$1"
  local dest="${2:-/tmp/$(basename "$1")}"
  adb push "$src" "/data/local/chroot-distro/installed-rootfs/${CHROOT_DISTRO_NAME}${dest}"
}

pull() {
  [[ $# -lt 1 ]] && { echo "Usage: pull SRC [DEST]" >&2; return 1; }
  local src="$1"
  local dest="${2:-.}"
  adb pull "/data/local/chroot-distro/installed-rootfs/${CHROOT_DISTRO_NAME}${src}" "$dest"
}


### Logging in: the `-tt` option is required to get an interactive shell
login() { adb shell -tt "$CHROOT_ENTER_CMD"; }


os_info() {
  run <<'CMDS'
  echo User: $(whoami)
  echo OS: $(cat /etc/os-release  | grep -P '^NAME' | cut -d'=' -f 2 | tr -d '"')
  echo "Kernel: $(uname -r)"
CMDS
}


[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
  case "${1:-}" in
    run) shift; run "$@" ;;
    login) login ;;
    push) shift; push "$@" ;;
    pull) shift; pull "$@" ;;
    os-info) os_info ;;
    help|--help|-h) usage ;;
    "") usage ;;
    *) echo "Unknown command: $1" >&2; usage; exit 1 ;;
  esac
}
