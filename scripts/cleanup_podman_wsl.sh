#!/usr/bin/env bash
set -euo pipefail
USERNAME="${USER}"
UIDNUM="$(id -u)"
HOME_SOCK_PATH="${HOME}/.podman-run/podman.sock"

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  systemctl --user disable --now podman.socket || true
  sudo systemctl disable --now podman.socket || true
fi

pids=$(pgrep -f "podman system service .*unix://$HOME_SOCK_PATH" || true)
if [[ -n "$pids" ]]; then kill $pids || true; fi
rm -f "$HOME_SOCK_PATH" || true
echo "Limpieza WSL OK"
