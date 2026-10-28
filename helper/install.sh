#!/bin/bash
# Install or remove Memdive's root helper. Run as root, e.g.:
#   pkexec bash ~/.config/omarchy/plugins/io.github.arbabmujtaba.memdive/helper/install.sh
#   pkexec bash .../helper/install.sh --uninstall
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

readonly HELPER_DEST=/usr/local/libexec/memdive-helper
readonly POLICY_DEST=/usr/share/polkit-1/actions/io.github.arbabmujtaba.memdive.policy

[[ $EUID -eq 0 ]] || { echo "install.sh: run as root (pkexec bash $0)" >&2; exit 1; }

src=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

case ${1:-} in
  --uninstall)
    rm -f "$HELPER_DEST" "$POLICY_DEST"
    echo "removed $HELPER_DEST and $POLICY_DEST"
    ;;
  "")
    [[ -f $src/memdive-helper && -f $src/io.github.arbabmujtaba.memdive.policy ]] \
      || { echo "install.sh: helper files missing next to $0" >&2; exit 1; }
    install -Dm755 -o root -g root "$src/memdive-helper" "$HELPER_DEST"
    install -Dm644 -o root -g root "$src/io.github.arbabmujtaba.memdive.policy" "$POLICY_DEST"
    echo "installed $HELPER_DEST and $POLICY_DEST"
    ;;
  *)
    echo "usage: install.sh [--uninstall]" >&2
    exit 64
    ;;
esac
