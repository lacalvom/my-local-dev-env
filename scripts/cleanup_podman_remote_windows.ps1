Param(
  [string]$ConnName = "wsl",
  [int]$LocalPort  = 2222,
  [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519",
  [switch]$RemoveFirewallRule,
  [switch]$RemoveKey
)

$ErrorActionPreference = "Stop"

function Require-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    throw "Ejecuta este script en PowerShell **como Administrador**."
  }
}

Require-Admin

try { podman system connection remove $ConnName -f | Out-Null } catch {}
try { netsh interface portproxy delete v4tov4 listenport=$LocalPort listenaddress=127.0.0.1 | Out-Null } catch {}

if ($RemoveFirewallRule) {
  $ruleName = "WSL SSH $LocalPort"
  try { Get-NetFirewallRule -DisplayName $ruleName -ErrorAction Stop | Remove-NetFirewallRule -Confirm:$false | Out-Null } catch {}
}

if ($RemoveKey) {
  try { Remove-Item -Force -ErrorAction Stop $KeyPath, ($KeyPath + ".pub") } catch {}
}
Write-Host "Limpieza Windows OK"
