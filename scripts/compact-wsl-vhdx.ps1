param(
  [string]$DistroName = "Ubuntu",
  [switch]$WhatIfOnly
)

$ErrorActionPreference = "Stop"

function Write-Info($msg) {
  Write-Host "[INFO] $msg" -ForegroundColor Cyan
}

function Write-WarnMsg($msg) {
  Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function Write-ErrMsg($msg) {
  Write-Host "[ERROR] $msg" -ForegroundColor Red
}

function Require-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($id)
  $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    throw "Este script requiere PowerShell ejecutado como Administrador."
  }
}

function Find-WslVhdx([string]$distro) {
  $packagesRoot = Join-Path $env:LOCALAPPDATA "Packages"
  if (-not (Test-Path $packagesRoot)) {
    throw "No se encontro carpeta Packages en LOCALAPPDATA."
  }

  $allVhdx = Get-ChildItem -Path $packagesRoot -Directory -ErrorAction SilentlyContinue |
    ForEach-Object {
      $vhdx = Join-Path $_.FullName "LocalState\ext4.vhdx"
      if (Test-Path $vhdx) {
        [PSCustomObject]@{
          Package = $_.Name
          VhdxPath = $vhdx
        }
      }
    }

  if (-not $allVhdx) {
    throw "No se encontraron archivos ext4.vhdx de WSL."
  }

  $filtered = $allVhdx | Where-Object { $_.Package -match $distro }
  if ($filtered -and $filtered.Count -ge 1) {
    if ($filtered.Count -gt 1) {
      Write-WarnMsg "Hay multiples coincidencias para '$distro'. Se usara la primera."
      $filtered | ForEach-Object { Write-Host "  - $($_.Package)" }
    }
    return $filtered[0]
  }

  Write-WarnMsg "No hubo coincidencia por nombre de distro '$distro'."
  Write-WarnMsg "Se usara la primera distro detectada."
  return $allVhdx[0]
}

function Get-SizeGB([string]$path) {
  $len = (Get-Item $path).Length
  return [Math]::Round($len / 1GB, 2)
}

function Compact-WithOptimizeVhd([string]$vhdxPath) {
  $cmd = Get-Command Optimize-VHD -ErrorAction SilentlyContinue
  if (-not $cmd) {
    return $false
  }

  Write-Info "Usando Optimize-VHD en modo Full"
  Optimize-VHD -Path $vhdxPath -Mode Full
  return $true
}

function Compact-WithDiskpart([string]$vhdxPath) {
  Write-Info "Usando diskpart como fallback"

  $scriptPath = Join-Path $env:TEMP "compact-wsl-vhdx-diskpart.txt"
  @(
    "select vdisk file=`"$vhdxPath`"",
    "attach vdisk readonly",
    "compact vdisk",
    "detach vdisk",
    "exit"
  ) | Set-Content -Path $scriptPath -Encoding ASCII

  try {
    diskpart /s $scriptPath
  }
  finally {
    Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
  }
}

try {
  Require-Admin

  $target = Find-WslVhdx -distro $DistroName
  $vhdxPath = $target.VhdxPath

  Write-Info "Paquete detectado: $($target.Package)"
  Write-Info "VHDX: $vhdxPath"

  $before = Get-SizeGB -path $vhdxPath
  Write-Info "Tamano antes: $before GB"

  if ($WhatIfOnly) {
    Write-Info "Modo simulacion activo. No se ejecutan cambios."
    exit 0
  }

  Write-Info "Deteniendo WSL..."
  wsl --shutdown
  Start-Sleep -Seconds 2

  $ok = Compact-WithOptimizeVhd -vhdxPath $vhdxPath
  if (-not $ok) {
    Write-WarnMsg "Optimize-VHD no disponible. Se intentara con diskpart."
    Compact-WithDiskpart -vhdxPath $vhdxPath
  }

  $after = Get-SizeGB -path $vhdxPath
  $saved = [Math]::Round($before - $after, 2)

  Write-Info "Tamano despues: $after GB"
  Write-Info "Espacio recuperado aprox: $saved GB"
  Write-Info "Listo. Puedes abrir nuevamente tu distro con: wsl"
}
catch {
  Write-ErrMsg $_.Exception.Message
  exit 1
}
