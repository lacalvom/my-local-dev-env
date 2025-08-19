# Dev Containers con **Podman en WSL** (Windows 11 + Ubuntu 24.04)

> **¿Por qué este entorno?**  
> Mi día a día es **Linux/Ubuntu**, pero por política de empresa trabajo en **Windows 11**. Quería:
> 1) **Un solo backend de contenedores** visible **desde Windows y desde WSL** (mismas imágenes/volúmenes/containers).
> 2) **Sin VMs extra** (ni `podman-machine` ni Docker Desktop Engine) para evitar capas, consumo y discrepancias.
> 3) **Volúmenes con nombre** rápidos y estables (evitar `/mnt/c/...`), con datos en ext4 dentro de WSL.
> 4) **Licenciamiento claro** y herramientas abiertas: preferencia por **Podman**.
> 5) Poder usar **CLI** (Windows y WSL), **Podman Desktop** y, si hace falta, comandos **`docker`** contra el mismo backend.
>
> El resultado: **Podman corre dentro de WSL (Ubuntu-24.04)** como motor único; **Windows** se conecta por **SSH** al socket de Podman.  
> Así, todo comparte **el mismo estado** (imágenes/containers/volúmenes) y se evita el sobrecoste/aislamiento de una VM adicional.  
> Además, si no hay `systemd` en WSL, el setup arranca la API de Podman en tu `$HOME` como fallback (sin sacrificar funcionalidades clave).

---

## 📦 Contenido del repo

```
scripts/
  setup_podman_wsl_v2.sh                  # Configura Podman en WSL (con o sin systemd)
  setup_podman_remote_windows_final.ps1   # Configura Windows para hablar con Podman en WSL por SSH
  cleanup_podman_wsl.sh                   # Limpieza/rollback en WSL
  cleanup_podman_remote_windows.ps1       # Limpieza/rollback en Windows
```

> **Nota**: ejecuta los scripts desde las rutas donde los descargues/clones.

---

## ✅ Prerrequisitos

- **Windows 11** con **WSL 2** habilitado.
- **Distro WSL**: **Ubuntu 24.04 LTS** instalada.
- **Podman Desktop** en Windows (opcional pero recomendado).
- **Visual Studio Code** en Windows (opcional pero muy recomendado).

### Guías oficiales
- Microsoft: *Instalar WSL en Windows 11* → https://learn.microsoft.com/windows/wsl/install
- Ubuntu: *Instalar Ubuntu en WSL2* → https://documentation.ubuntu.com/wsl/latest/howto/install-ubuntu-wsl2/
- Podman Desktop (Windows) → https://podman-desktop.io/docs/installation/windows-install
- Visual Studio Code (Windows) → https://code.visualstudio.com/Download
- VS Code + WSL → https://code.visualstudio.com/docs/remote/wsl
- VS Code Dev Containers → https://code.visualstudio.com/docs/devcontainers/containers

---

## 🚀 Puesta en marcha (2 pasos)

### 1) Dentro de **WSL (Ubuntu-24.04)**
```bash
# 1. Dale permisos de ejecución
chmod +x scripts/setup_podman_wsl_v2.sh

# 2. Lánzalo
bash scripts/setup_podman_wsl_v2.sh
```
¿Qué hace?
- Instala `podman` y utilidades.
- Configura el engine para WSL: `cgroupfs`, `events=file`, `runtime=crun`.
- **Con systemd de usuario**: activa `podman.socket` → `/run/user/1000/podman/podman.sock`.
- **Sin systemd**: levanta `podman system service` en **`~/.podman-run/podman.sock`** (persistente con `nohup`).

### 2) En **Windows** (PowerShell **Administrador**)
```powershell
# Ejecuta el script que crea la clave SSH (si falta), autoriza en WSL,
# crea el portproxy 127.0.0.1:2222 -> WSL:22 y registra la conexión "wsl"
powershell -ExecutionPolicy Bypass -File .\scripts\setup_podman_remote_windows_final.ps1
```
¿Qué hace?
- Asegura **OpenSSH Client** y `podman-remote` en Windows.
- Autoriza la clave en `~/.ssh/authorized_keys` (WSL).
- Registra `podman system connection` → **wsl** (por SSH) y la deja por defecto.
- Valida con `podman info`.

### (Opcional) Podman Desktop
- **Settings → Extension: Podman → Remote**: *Enabled* (pulsa **Reload**).
- Reinicia la app y, en la barra superior de **Containers/Images**, elige el engine **wsl**.

---

## 🧰 VS Code en este entorno (recomendado)

**Instala VS Code en Windows** y añade estas extensiones:
- **Remote - WSL** (ID: `ms-vscode-remote.remote-wsl`)
- **Dev Containers** (ID: `ms-vscode-remote.remote-containers`)

**Flujo recomendado:**
1) Abre **VS Code** en Windows → **Remote Explorer** → **WSL** → **Open Folder in WSL** y selecciona tu carpeta en `/home/<usuario>/...` (no en `/mnt/c/...` por rendimiento).  
2) Si tu proyecto tiene `.devcontainer/` o `.devcontainer.json`, usa **Command Palette** → `Dev Containers: Reopen in Container`.  
3) Para que Dev Containers funcione con Podman en WSL, usa una de estas opciones:
   - **Opción A (sencilla, recomendada)**: instala `podman-docker` en WSL. Así `docker` **apunta a Podman** y VS Code lo usa sin cambios.
     ```bash
     sudo apt update && sudo apt install -y podman-docker
     docker version   # el "Server" mostrará Podman
     ```
   - **Opción B**: expón la API Docker-compat de Podman en `127.0.0.1:2375` (ver sección “Usar comando docker”) y asegúrate de que el CLI `docker` que use VS Code apunta a esa API (`DOCKER_HOST`).

> Consejos: trabaja siempre en la **ruta de WSL** (`/home/...`). Evita `/mnt/c` para que el I/O sea rápido. Si usas `podman-compose`, ejecútalo **dentro de WSL**.

---

## 🗂️ Volúmenes con nombre (recomendado en WSL)

**CLI**
```bash
# Crear
podman volume create miapp-data

# Usar (equivalentes)
podman run -v miapp-data:/var/lib/postgresql/data postgres:16
podman run --mount type=volume,source=miapp-data,target=/var/lib/postgresql/data postgres:16

# Inspeccionar
podman volume inspect miapp-data

# Exportar/Importar
podman volume export miapp-data > miapp-data.tar
podman volume import miapp-data miapp-data.tar
```

**Podman Desktop**
- **Volumes → Create volume** → nombre (ej. `miapp-data`).
- Al crear un contenedor: **Storage → Mount → Type: Volume → Source: `miapp-data` → Target: `/ruta/en/contenedor`**.

> Evita montar rutas de Windows (`/mnt/c/...`) por rendimiento y permisos; usa **volúmenes con nombre**.

---

## 🐳 Usar comando `docker` con Podman por debajo

Tienes dos opciones. **Ambas usan el mismo backend Podman en WSL**:

### Opción A — Alias simple (WSL)
```bash
sudo apt update && sudo apt install -y podman-docker
# Ahora: docker ps == podman ps
```
Para Compose en WSL:
```bash
sudo apt install -y pipx python3-venv
pipx install podman-compose
# podman-compose up
```

### Opción B — Docker CLI real (Windows/WSL) → API de Podman
**Exponer API Docker-compat de Podman en WSL (solo loopback):**
```bash
# Sin systemd:
nohup podman system service --time=0 tcp:127.0.0.1:2375   >~/.local/share/podman-docker-api.log 2>&1 &
```
**En Windows, apuntar el Docker CLI a esa API:**
```powershell
setx DOCKER_HOST "tcp://127.0.0.1:2375"
# nueva sesión:
$env:DOCKER_HOST = "tcp://127.0.0.1:2375"

docker version
docker ps
```
> Seguridad: **no** expongas `0.0.0.0:2375`. Mantén `127.0.0.1`.

---

## 🧹 Limpieza / Rollback

**WSL**
```bash
chmod +x scripts/cleanup_podman_wsl.sh
bash scripts/cleanup_podman_wsl.sh            # básico
bash scripts/cleanup_podman_wsl.sh --purge-config --disable-linger  # agresivo
```

**Windows (PowerShell, Admin)**
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\cleanup_podman_remote_windows.ps1
# Flags opcionales:
#   -RemoveFirewallRule   (borra regla de firewall "WSL SSH <puerto>")
#   -RemoveKey            (borra tu clave SSH local)
```

> Ninguno de estos scripts borra imágenes/containers. Para reset total:
```bash
podman system reset -f
```

---

## 🔧 Troubleshooting rápido

- **¿No hay systemd en WSL?** Usa el socket de HOME (`~/.podman-run/podman.sock`) que ya levanta el setup.
- **Comprobaciones clave (WSL):**
  ```bash
  podman info --format 'cgroup={{.Host.CgroupManager}}, events={{.Host.EventLogger}}, runtime={{.Host.OCIRuntime.Name}}'
  ss -lx | grep podman.sock
  ```
  Deberías ver `cgroup=cgroupfs`, `events=file`, `runtime=crun`.
- **Windows no conecta?**
  - Re-lanza el setup de Windows.
  - Comprueba el portproxy: `netsh interface portproxy show v4tov4`
  - Prueba `ssh -p 2222 <tu-usuario>@localhost "echo ok"`

---

## 📚 Referencias útiles

- WSL en Windows 11 (Microsoft Learn): https://learn.microsoft.com/windows/wsl/install
- Ubuntu en WSL2 (Ubuntu docs): https://documentation.ubuntu.com/wsl/latest/howto/install-ubuntu-wsl2/
- Podman Desktop para Windows: https://podman-desktop.io/docs/installation/windows-install
- Visual Studio Code (Windows): https://code.visualstudio.com/Download
- VS Code + WSL: https://code.visualstudio.com/docs/remote/wsl
- VS Code Dev Containers: https://code.visualstudio.com/docs/devcontainers/containers
- API Docker-compatible de Podman: https://docs.podman.io/en/latest/markdown/podman-system-service.1.html
- Podman docs (general): https://docs.podman.io/

---

## ⚖️ Licencia

MIT
