param(
  [string]$Project,
  [string]$Domain,
  [switch]$WhatIf
)

# ===== Helpers =====
function Test-Admin {
  ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-Slug([string]$s) {
  ($s.ToLower() -replace '[^a-z0-9\-]','-') -replace '-+','-'
}

function Remove-HostsEntries([string]$domain) {
  $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
  if (-not (Test-Path $hostsPath)) { return }

  $patterns = @(
    "^\s*127\.0\.0\.1\s+$([regex]::Escape($domain))\s*$",
    "^\s*127\.0\.0\.1\s+pma\.$([regex]::Escape($domain))\s*$"
  )

  $content = Get-Content $hostsPath -ErrorAction SilentlyContinue
  if ($null -eq $content) { return }

  $new = $content | Where-Object {
    $line = $_
    -not ($patterns | ForEach-Object { $line -match $_ } | Where-Object { $_ })
  }

  if ($WhatIf) {
    Write-Host "[WhatIf] Quitar del hosts:"
    $content | Where-Object {
      $line = $_
      ($patterns | ForEach-Object { $line -match $_ } | Where-Object { $_ })
    } | ForEach-Object { Write-Host "  $_" }
  } else {
    if ($new.Count -ne $content.Count) {
      $new | Set-Content -Path $hostsPath -Encoding ascii
      Write-Host "Entradas eliminadas de hosts para $domain y pma.$domain"
      # Flush DNS
      ipconfig /flushdns | Out-Null
      Write-Host "Cache DNS limpiada."
    } else {
      Write-Host "No había entradas de hosts para $domain / pma.$domain"
    }
  }
}

# ===== Rutas base (asumiendo que este script vive en /bin como el de creación) =====
$root = Resolve-Path "$PSScriptRoot\.."
$sitesRoot          = Join-Path $root "sites"
$traefikDynamicDir  = Join-Path $root "infra\traefik\dynamic"

# ===== Entradas =====
if (-not $Project) {
  $Project = Read-Host "Nombre del proyecto a borrar (slug sin espacios, ej. escuela)"
}
$slug = Format-Slug $Project
$siteDir = Join-Path $sitesRoot $slug
$composeFile = Join-Path $siteDir "docker-compose.yml"
$envFile     = Join-Path $siteDir ".env"

if (-not (Test-Path $siteDir)) {
  Write-Error "No existe la carpeta del sitio: $siteDir"
  exit 1
}

# Intenta obtener DOMAIN del .env si no vino por parámetro
if (-not $Domain) {
  if (Test-Path $envFile) {
    $envLines = Get-Content $envFile -ErrorAction SilentlyContinue
    $Domain = ($envLines | Where-Object { $_ -match '^\s*DOMAIN\s*=' } | ForEach-Object { ($_ -split '=',2)[1].Trim() }) | Select-Object -First 1
  }
  if (-not $Domain) {
    # fallback a slug.test si no lo encuentra
    $Domain = "$slug.test"
  }
}

Write-Host "==============================================="
Write-Host "  BORRANDO SITIO WP"
Write-Host "  Slug:    $slug"
Write-Host "  Dominio: $Domain"
Write-Host "  Carpeta: $siteDir"
Write-Host "==============================================="

# ===== 1) Apagar y borrar contenedores + volúmenes =====
if (Test-Path $composeFile) {
  Write-Host "Parando y borrando stack Docker (down -v)..."
  $cmd = { docker compose --env-file ".env" down -v }
  if ($WhatIf) {
    Write-Host "[WhatIf] docker compose --env-file .env down -v (en $siteDir)"
  } else {
    Push-Location $siteDir
    try { & $cmd } finally { Pop-Location }
  }
} else {
  Write-Host "No existe docker-compose.yml; salto down -v."
}

# ===== 2) Borrar carpeta del sitio =====
# Importante: no estar dentro para que no esté "en uso"
if ((Get-Location).Path -like "$siteDir*") {
  Set-Location $sitesRoot
}

if (Test-Path $siteDir) {
  if ($WhatIf) {
    Write-Host "[WhatIf] Remove-Item -Recurse -Force $siteDir"
  } else {
    try {
      Remove-Item -Recurse -Force $siteDir
      Write-Host "Carpeta del sitio eliminada: $siteDir"
    } catch {
      Write-Warning "No se pudo eliminar $siteDir : $($_.Exception.Message)"
      Write-Warning "Cierra procesos que puedan estar usando la ruta y reintenta."
    }
  }
}

# ===== 3) Borrar regla de Traefik =====
$rulePath = Join-Path $traefikDynamicDir "$slug.yml"
if (Test-Path $rulePath) {
  if ($WhatIf) {
    Write-Host "[WhatIf] Remove-Item $rulePath"
  } else {
    Remove-Item $rulePath -Force
    Write-Host "Regla Traefik eliminada: $rulePath"
  }
} else {
  Write-Host "No se encontró regla Traefik para $slug ($rulePath)"
}

# ===== 4) Reiniciar Traefik =====
if ($WhatIf) {
  Write-Host "[WhatIf] docker restart traefik"
} else {
  $null = docker ps --format "{{.Names}}" | Select-String -Pattern "^traefik$"
  if ($LASTEXITCODE -eq 0) {
    docker restart traefik | Out-Null
    Write-Host "Traefik reiniciado."
  } else {
    Write-Host "No se encontró contenedor 'traefik'; salto reinicio."
  }
}

# ===== 5) Limpiar hosts =====
if (Test-Admin) {
  Remove-HostsEntries -domain $Domain
} else {
  Write-Warning "Sin permisos de administrador: no puedo editar hosts."
  Write-Host "Elimina manualmente estas líneas (si existen) en:"
  Write-Host "  $env:SystemRoot\System32\drivers\etc\hosts"
  Write-Host "  127.0.0.1  $Domain"
  Write-Host "  127.0.0.1  pma.$Domain"
  Write-Host "Luego ejecuta: ipconfig /flushdns"
}

Write-Host "==============================================="
Write-Host "Sitio '$slug' eliminado (o simulado si -WhatIf)."
Write-Host "==============================================="
