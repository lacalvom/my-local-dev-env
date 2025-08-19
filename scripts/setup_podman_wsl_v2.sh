#!/usr/bin/env bash
set -euo pipefail

echo "==> Preparando Podman en WSL (rootless, compatible sin systemd)"

# --- Variables
USERNAME="${USER}"
UIDNUM="$(id -u)"
HOME_SOCK_DIR="${HOME}/.podman-run"
HOME_SOCK_PATH="${HOME_SOCK_DIR}/podman.sock"
USER_SOCKET="/run/user/${UIDNUM}/podman/podman.sock"

# --- Paquetes
echo "==> Instalando paquetes requeridos (podman, sshd, overlay helpers)..."
sudo apt-get update -y
sudo apt-get install -y podman buildah skopeo uidmap slirp4netns fuse-overlayfs iptables openssh-server curl

# --- subuid/subgid
if ! grep -q "^${USERNAME}:" /etc/subuid 2>/dev/null; then
  echo "==> Configurando subuids/subgids para ${USERNAME} (rootless)"
  sudo usermod --add-subuids 100000-165536 --add-subgids 100000-165536 "${USERNAME}"
  echo "   (Si ves problemas con rootless, cierra y vuelve a entrar a la sesión)"
fi

# --- Engine en WSL: cgroupfs + file + crun
echo "==> Escribiendo ~/.config/containers/containers.conf (cgroupfs, file, crun)"
mkdir -p "${HOME}/.config/containers"
cat > "${HOME}/.config/containers/containers.conf" <<'EOF'
[engine]
cgroup_manager = "cgroupfs"
events_logger  = "file"
runtime        = "crun"
EOF

# --- SSH
echo "==> Asegurando SSH en WSL..."
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  sudo systemctl enable --now ssh || true
else
  if command -v service >/dev/null 2>&1; then
    sudo service ssh start || true
  fi
  if ! pgrep -x sshd >/dev/null 2>&1; then
    echo "   -> Iniciando /usr/sbin/sshd en background (sin systemd)"
    sudo /usr/sbin/sshd || true
  fi
fi

# --- Socket activo (systemd de usuario vs fallback)
have_systemd_user=0
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
  if systemctl --user show-environment >/dev/null 2>&1; then
    have_systemd_user=1
  fi
fi

if [ "${have_systemd_user}" -eq 1 ]; then
  echo "==> Detectado systemd de usuario: habilitando 'podman.socket' rootless"
  systemctl --user daemon-reload || true
  systemctl --user enable --now podman.socket
  ACTIVE_SOCK="${USER_SOCKET}"
else
  echo "==> Sin systemd de usuario: levantando 'podman system service' en ${HOME_SOCK_PATH}"
  mkdir -p "${HOME_SOCK_DIR}"
  if ! pgrep -f "podman system service .*unix://${HOME_SOCK_PATH}" >/dev/null 2>&1; then
    nohup podman system service --time=0 "unix://${HOME_SOCK_PATH}" >"${HOME}/.local/share/podman-service.log" 2>&1 &
    sleep 1
  fi
  ACTIVE_SOCK="${HOME_SOCK_PATH}"
fi

# --- Pruebas (no fallar si es la primera vez)
echo "==> Prueba rápida: 'podman images' y 'podman run --rm quay.io/podman/hello'"
podman images || true
podman run --rm quay.io/podman/hello || true

# --- Datos para Windows
WSL_IP="$(hostname -I | awk '{print $1}')"
echo
echo "==> Datos para Windows:"
echo "   Usuario         : ${USERNAME}"
echo "   UID             : ${UIDNUM}"
echo "   Socket activo   : ${ACTIVE_SOCK}"
echo "   IP WSL (actual) : ${WSL_IP}"
echo
echo "Para registrar la conexión en Windows:"
echo "  podman system connection add wsl \"ssh://${USERNAME}@localhost:2222${ACTIVE_SOCK}\" --identity %USERPROFILE%\\.ssh\\id_ed25519"
echo "  podman system connection default wsl"
echo
echo "Sugerencia: auto-arranque sin systemd, añade a ~/.bashrc:"
cat <<'EOS'
p="$HOME/.podman-run/podman.sock"
pgrep -f "podman system service .* $p" >/dev/null || nohup podman system service --time=0 unix://$p >~/.local/share/podman-service.log 2>&1 &
EOS

echo "==> Todo listo."
