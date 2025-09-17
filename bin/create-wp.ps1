param(
  [string]$Project,
  [string]$Domain,
  [int]$VitePort
)

# ===== Hard fail ante cualquier error =====
$ErrorActionPreference = 'Stop'

# ===== Helpers =====
function New-RandomString([int]$Length = 24) {
  $alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  $bytes = New-Object byte[] ($Length)
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  ($bytes | ForEach-Object { $alphabet[ $_ % $alphabet.Length ] }) -join ''
}

function Test-Admin {
  return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "No se encontró el comando requerido: $name. Asegúrate de tenerlo instalado/en PATH."
  }
}

function Wait-ContainerRunning {
  param(
    [string]$ServiceName,
    [string]$ComposeDir,
    [int]$TimeoutSec = 90
  )
  Write-Host "Esperando a que el servicio '$ServiceName' esté RUNNING (timeout ${TimeoutSec}s)..."
  $sw = [Diagnostics.Stopwatch]::StartNew()
  do {
    Push-Location $ComposeDir
    try {
      $json = docker compose ps --format json
      $list = if ($json) { $json | ConvertFrom-Json } else { @() }
      $state = ($list | Where-Object { $_.Service -eq $ServiceName }).State
    } finally {
      Pop-Location
    }
    if ($state -eq 'running') { return $true }
    Start-Sleep -Seconds 2
  } while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec)
  return $false
}

# ===== Prechecks =====
Assert-Command "docker"
Assert-Command "docker-compose" # alias a compose v2 suele ser "docker compose", pero validamos ambos
try { docker version | Out-Null } catch { throw "Docker no responde. ¿Docker Desktop está arrancado?" }

# ===== Rutas base =====
$root = Resolve-Path "$PSScriptRoot\.."
$templatesSiteDir   = Join-Path $root "templates\wp-site"
$templatesRuleFile  = Join-Path $root "infra\traefik\rule.template.yml"
$traefikDynamicDir  = Join-Path $root "infra\traefik\dynamic"

if (-not $Project) {
  $Project = Read-Host "Nombre del proyecto (slug sin espacios, ej. talentum)"
}
$slug = ($Project.ToLower() -replace '[^a-z0-9\-]','-') -replace '-+','-'

if (-not $Domain) {
  $default = "$slug.test"
  $Domain = Read-Host "Dominio (ENTER = $default)"
  if ([string]::IsNullOrWhiteSpace($Domain)) { $Domain = $default }
}

# ===== Derivados y credenciales =====
$DbUser  = "wp_{0}_user" -f ($slug -replace '-', '')
$DbName  = "wp_{0}_db"  -f ($slug -replace '-', '')
$RootPW  = New-RandomString 26
$UserPW  = New-RandomString 26

$siteDir   = Join-Path $root "sites\$slug"
$envFile   = Join-Path $siteDir ".env"
$composeYml= Join-Path $siteDir "docker-compose.yml"

# Rutas de plantilla
$tplDockerDir    = Join-Path $templatesSiteDir "docker"
$tplPhpDir       = Join-Path $templatesSiteDir "php"
$tplPlugins      = Join-Path $templatesSiteDir "plugins"
$tplDevcontainer = Join-Path $templatesSiteDir ".devcontainer"

# ===== Comprobaciones previas =====
if (-not (Test-Path $templatesSiteDir))   { throw "No existe la carpeta de plantilla: $templatesSiteDir" }
if (-not (Test-Path $templatesRuleFile))  { throw "No existe la plantilla de regla Traefik: $templatesRuleFile" }
if (-not (Test-Path $tplDockerDir))       { throw "No existe 'templates\wp-site\docker' (se necesita para el Dockerfile de WP)." }
if (-not (Test-Path $tplPhpDir))          { throw "No existe 'templates\wp-site\php'." }
# plugins es opcional, no forzamos error si no existe

# ===== Crea carpeta del sitio y copia plantilla =====
New-Item -ItemType Directory -Force $siteDir | Out-Null
Copy-Item (Join-Path $templatesSiteDir "docker-compose.yml") $composeYml -Force
Copy-Item $tplPhpDir $siteDir -Recurse -Force
Copy-Item $tplDockerDir $siteDir -Recurse -Force
if (Test-Path $tplDevcontainer) {
  Copy-Item $tplDevcontainer $siteDir -Recurse -Force
}

# ===== Helpers para encontrar un puerto libre =====
function Test-PortFree {
  param([int]$Port)
  try {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
    $listener.Start()
    $listener.Stop()
    return $true
  } catch {
    return $false
  }
}

function Get-FreePort {
  param([int]$StartFrom = 5173, [int]$MaxTries = 200)
  for ($p = $StartFrom; $p -lt ($StartFrom + $MaxTries); $p++) {
    if (Test-PortFree -Port $p) { return $p }
  }
  throw "No hay puertos libres en el rango $StartFrom-$($StartFrom+$MaxTries-1)."
}

# ===== Puerto Vite publicado en host =====
if (-not $VitePort -or $VitePort -le 0) {
  $VitePort = Get-FreePort -StartFrom 5173
}

# ===== Genera .env con valores del sitio =====
@"
PROJECT=$slug
DOMAIN=$Domain
MYSQL_ROOT_PASSWORD=$RootPW
MYSQL_USER=$DbUser
MYSQL_PASSWORD=$UserPW
MYSQL_DATABASE=$DbName
VITE_PUBLISHED_PORT=$VitePort
"@ | Set-Content $envFile -Encoding ascii

# ===== Asegura red 'web' (externa) =====
$null = docker network inspect web 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Creando red 'web'..."
  docker network create web | Out-Null
}

# ===== Genera regla Traefik desde template =====
$rule = Get-Content $templatesRuleFile -Raw
$rule = $rule -replace 'PROJECT', $slug -replace 'DOMAIN', $Domain
if (-not (Test-Path $traefikDynamicDir)) { New-Item -ItemType Directory -Force $traefikDynamicDir | Out-Null }
$rulePath = Join-Path $traefikDynamicDir "$slug.yml"
$rule | Set-Content $rulePath -Encoding ascii

# ===== Añade líneas a hosts (no-fatal, con reintentos) =====
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$linesToAdd = @("127.0.0.1  $Domain","127.0.0.1  pma.$Domain","127.0.0.1  vite.$Domain")

function Add-HostsLine {
  param(
    [string]$Path,
    [string]$Line,
    [int]$MaxRetries = 10,
    [int]$DelayMs = 500
  )
  # Evita duplicados (comparación literal)
  $current = (Get-Content -Path $Path -ErrorAction SilentlyContinue) -join "`n"
  if ($current -and $current -match [regex]::Escape($Line)) {
    Write-Host "Ya existe en hosts: $Line"
    return $true
  }

  for ($i=1; $i -le $MaxRetries; $i++) {
    try {
      # Fuerza CRLF y ASCII para evitar rarezas de codificación
      [System.IO.File]::AppendAllText($Path, "`r`n$Line", [System.Text.Encoding]::ASCII)
      Write-Host "Añadida a hosts: $Line"
      return $true
    } catch [System.IO.IOException] {
      Start-Sleep -Milliseconds $DelayMs
    } catch {
      Write-Warning "Fallo inesperado añadiendo '$Line' a hosts: $($_.Exception.Message)"
      return $false
    }
  }
  Write-Warning "No se pudo escribir en hosts tras $MaxRetries reintentos: $Line"
  return $false
}

if (Test-Admin) {
  $okAll = $true
  foreach ($l in $linesToAdd) {
    $ok = Add-HostsLine -Path $hostsPath -Line $l
    if (-not $ok) { $okAll = $false }
  }
  try { ipconfig /flushdns | Out-Null } catch { Write-Warning "No se pudo ejecutar flushdns: $($_.Exception.Message)" }
  if (-not $okAll) {
    Write-Warning "Sigue habiendo líneas pendientes de añadir en hosts. Puedes hacerlo manualmente:"
    $linesToAdd | ForEach-Object { Write-Host "  $_" }
  }
} else {
  Write-Warning "No tengo permisos para editar hosts. Añade estas líneas manualmente:"
  $linesToAdd | ForEach-Object { Write-Host "  $_" }
}

# ===== Levanta el stack (build incluido) =====
Push-Location $siteDir
try {
  Write-Host "Construyendo imagen de WordPress con tooling..."
  docker compose --env-file .env build --no-cache wordpress

  Write-Host "Levantando contenedores..."
  docker compose --env-file .env up -d
}
catch {
  Pop-Location
  throw "Fallo al construir o levantar el stack: $($_.Exception.Message)"
}
Pop-Location

# ===== Espera a que wordpress esté 'running' =====
if (-not (Wait-ContainerRunning -ServiceName "wordpress" -ComposeDir $siteDir -TimeoutSec 120)) {
  throw "El servicio 'wordpress' no está RUNNING tras el timeout."
}

# ===== Copia de plugins al volumen (si existen en la plantilla) =====
if (Test-Path $tplPlugins) {
  try {
    Write-Host "Copiando plugins al volumen de WP..."
    # Nota: el /.\ incluye contenido (no la carpeta raíz)
    Push-Location $siteDir
    docker compose --env-file .env cp "$tplPlugins/." "wordpress:/var/www/html/wp-content/plugins"
    Pop-Location
    Write-Host "Plugins copiados correctamente."
  }
  catch {
    Write-Warning "No se pudieron copiar los plugins al contenedor: $($_.Exception.Message)"
  }
} else {
  Write-Host "No hay carpeta 'plugins' en la plantilla; se omite copia."
}

# ===== Ajusta permisos en wp-content =====
Push-Location $siteDir
docker compose --env-file .env exec -T -u root wordpress bash -lc `
  "set -e; \
   chown -R www-data:www-data /var/www/html/wp-content; \
   find /var/www/html/wp-content -type d -exec chmod 775 {} \;; \
   find /var/www/html/wp-content -type f -exec chmod 664 {} \;"
Pop-Location

# ===== Reinicia Traefik para recargar reglas (si existe) =====
try {
  $traefikExists = docker ps --format "{{.Names}}" | Select-String -SimpleMatch "traefik"
  if ($traefikExists) {
    Write-Host "Reiniciando Traefik para aplicar la nueva regla..."
    docker restart traefik | Out-Null
  } else {
    Write-Warning "Traefik no está corriendo; inicia Traefik para que tome la nueva regla: $rulePath"
  }
}
catch {
  Write-Warning "No se pudo reiniciar Traefik: $($_.Exception.Message)"
}

# ===== Resumen =====
Write-Host "----------------------------------------------------"
Write-Host "Sitio creado: $slug"
Write-Host "Dominio WP:   http://$Domain   (o https si lo configuras)"
Write-Host "phpMyAdmin:   http://pma.$Domain"
Write-Host ""
Write-Host "Carpeta del proyecto:"
Write-Host "  $siteDir"
Write-Host ""
Write-Host "Credenciales MySQL:"
Write-Host "  ROOT: $RootPW"
Write-Host "  DB:   $DbName"
Write-Host "  USER: $DbUser"
Write-Host "  PASS: $UserPW"
Write-Host "Regla Traefik: $rulePath"
Write-Host "Compose dir:   $siteDir"
Write-Host "----------------------------------------------------"
