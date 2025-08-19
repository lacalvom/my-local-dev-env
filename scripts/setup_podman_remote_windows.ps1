
Param(
  [string]$Distro = "Ubuntu-24.04",
  [int]$LocalPort = 2222,
  [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519",
  [string]$ConnName = "wsl",
  [string]$SocketPath = ""   # vacío => autodetecta (/run/user/$uid/podman/podman.sock o ~/.podman-run/podman.sock)
)

$ErrorActionPreference = "Stop"

function Require-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    throw "Ejecuta este script en PowerShell **como Administrador**."
  }
}

function Ensure-OpenSSHClient {
  if (Get-Command ssh -ErrorAction SilentlyContinue -CommandType Application) { return }
  Write-Host "Instalando la característica OpenSSH.Client ..."
  Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 | Out-Null
}

function Ensure-PodmanRemote {
  if (Get-Command podman -ErrorAction SilentlyContinue) { return }
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "Instalando Podman (podman-remote) con winget..."
    winget install -e --id RedHat.Podman --accept-source-agreements --accept-package-agreements
  } else {
    throw "No se encontró 'podman'. Instálalo desde https://podman.io/ o usa winget."
  }
}

function Get-SshKeygenPath {
  $cmd = (Get-Command ssh-keygen -ErrorAction SilentlyContinue)
  if ($cmd) { return $cmd.Source }
  $fallback = Join-Path $env:WINDIR "System32\OpenSSH\ssh-keygen.exe"
  if (Test-Path $fallback) { return $fallback }
  throw "No se encontró ssh-keygen en el PATH ni en $fallback"
}

function New-SSHKeyIfMissing {
  param([string]$Path)

  $pubPath = "$Path.pub"
  $sshKeygen = Get-SshKeygenPath

  if ((Test-Path $Path -PathType Leaf) -and -not (Test-Path $pubPath -PathType Leaf)) {
    Write-Host "Privada encontrada sin pública. Reconstruyendo $pubPath ..."
    $pub = & $sshKeygen -y -f $Path
    if (-not $pub) { throw "No se pudo extraer la clave pública desde $Path" }
    Set-Content -Path $pubPath -Value $pub -NoNewline
    return
  }

  if (Test-Path $pubPath -PathType Leaf) {
    Write-Host "Clave existente: $pubPath"
    return
  }

  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

  Write-Host "Generando clave ED25519 en $Path (sin passphrase)..."
  # Inyectar dos líneas en blanco para aceptar passphrase vacía sin -N ""
  $cmdline = "(echo() & echo()) | `"$sshKeygen`" -t ed25519 -f `"$Path`""
  cmd.exe /c $cmdline | Out-Null

  if (-not (Test-Path $pubPath)) {
    Write-Warning "No se generó la .pub automáticamente; reconstruyendo..."
    $pub = & $sshKeygen -y -f $Path
    if (-not $pub) { throw "No se pudo extraer la clave pública desde $Path" }
    Set-Content -Path $pubPath -Value $pub -NoNewline
  }
  Write-Host "Clave creada: $pubPath"
}

Require-Admin
Ensure-OpenSSHClient
Ensure-PodmanRemote

Write-Host "==> Comprobando que la distro $Distro existe (wsl -l -q) ..."
$distroNames = wsl -l -q | ForEach-Object { $_.Trim() }
if (-not ($distroNames -contains $Distro)) {
  Write-Host "Distros encontradas:"
  $distroNames | ForEach-Object { " - $_" } | Write-Host
  throw "No se encontró la distro '$Distro'. Si tu nombre es distinto, pásalo con -Distro 'MiDistro'."
}

Write-Host "==> Detectando usuario y UID dentro de WSL..."
$wslUser = (wsl -d $Distro -- bash -lc 'id -un').Trim()
if (-not $wslUser) { throw "No se pudo obtener el usuario en $Distro." }
$uid = (wsl -d $Distro -- bash -lc 'id -u').Trim()

# Autodetectar socket si no lo pasó el usuario
if (-not $SocketPath) {
  $userSock = "/run/user/$uid/podman/podman.sock"
  $homeBase = (wsl -d $Distro -- bash -lc 'echo -n $HOME')
  $homeSock = "$homeBase/.podman-run/podman.sock"
  $existsUser = ((wsl -d $Distro -- test -S $userSock; echo $LASTEXITCODE).Trim() -eq "0")
  $existsHome = ((wsl -d $Distro -- test -S $homeSock; echo $LASTEXITCODE).Trim() -eq "0")
  if ($existsUser) { $SocketPath = $userSock }
  elseif ($existsHome) { $SocketPath = $homeSock }
  else { $SocketPath = $homeSock }  # preferimos el de HOME si ninguno existe aún
}
Write-Host "Socket destino dentro de WSL: $SocketPath"

Write-Host "==> Generando clave SSH si no existe..."
New-SSHKeyIfMissing -Path $KeyPath
$pub = Get-Content ($KeyPath + ".pub") -Raw

Write-Host "==> Autorizando la clave pública en WSL..."
$escapedPub = $pub -replace "`r","" -replace "`n",""
wsl -d $Distro -- bash -lc "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$escapedPub' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

Write-Host "==> Asegurando que sshd está activo en WSL..."
wsl -d $Distro -- bash -lc "sudo systemctl enable --now ssh || sudo service ssh start || sudo /usr/sbin/sshd"

Write-Host "==> Obteniendo IP de WSL..."
$wslIp = (wsl -d $Distro -- bash -lc "hostname -I | awk '{print $1}'").Trim()
if (-not $wslIp) { throw "No se pudo obtener la IP de $Distro." }
Write-Host "WSL IP: $wslIp"

Write-Host "==> Configurando portproxy 127.0.0.1:$LocalPort -> $wslIp:22 ..."
try { netsh interface portproxy delete v4tov4 listenport=$LocalPort listenaddress=127.0.0.1 | Out-Null } catch {}
netsh interface portproxy add v4tov4 listenport=$LocalPort listenaddress=127.0.0.1 connectport=22 connectaddress=$wslIp | Out-Null

if (-not (Get-NetFirewallRule -DisplayName "WSL SSH $LocalPort" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName "WSL SSH $LocalPort" -Direction Inbound -LocalPort $LocalPort -Protocol TCP -Action Allow | Out-Null
}

Write-Host "==> Probando SSH hacia WSL a través de localhost:$LocalPort ..."
try { ssh -p $LocalPort -o StrictHostKeyChecking=accept-new $wslUser@localhost "echo ok" } catch { throw "No se pudo conectar por SSH a localhost:$LocalPort" }

Write-Host "==> Registrando conexión remota '$ConnName' en podman..."
try { podman system connection remove $ConnName -f | Out-Null } catch {}
podman system connection add $ConnName "ssh://$wslUser@localhost:$LocalPort$SocketPath" --identity $KeyPath
podman system connection default $ConnName

Write-Host "==> Comprobando podman remoto..."
podman info

Write-Host ""
Write-Host "Listo. En Podman Desktop → Settings → Preferences activa 'Remote connections'."
Write-Host "Luego podrás seleccionar la conexión '$ConnName' en la interfaz."
