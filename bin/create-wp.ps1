param(
  [string]$Project,
  [string]$Domain
)

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

# ===== Rutas base (asumiendo que este script vive en /bin) =====
$root = Resolve-Path "$PSScriptRoot\.."
$templatesSiteDir   = Join-Path $root "templates\wp-site"
$templatesRuleFile  = Join-Path $root "infra\traefik\rule.template.yml"
$traefikDynamicDir  = Join-Path $root "infra\traefik\dynamic"

# ===== Entradas =====
if (-not $Project) {
  $Project = Read-Host "Nombre del proyecto (slug sin espacios, ej. talentum)"
}
# normaliza slug
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

$siteDir = Join-Path $root "sites\$slug"
$envFile = Join-Path $siteDir ".env"

# ===== Comprobaciones previas =====
if (-not (Test-Path $templatesSiteDir)) {
  Write-Error "No existe la carpeta de plantilla: $templatesSiteDir"
  exit 1
}
if (-not (Test-Path $templatesRuleFile)) {
  Write-Error "No existe la plantilla de regla Traefik: $templatesRuleFile"
  exit 1
}

# ===== Crea carpeta del sitio y copia plantilla =====
New-Item -ItemType Directory -Force $siteDir | Out-Null
Copy-Item (Join-Path $templatesSiteDir "docker-compose.yml") (Join-Path $siteDir "docker-compose.yml") -Force
Copy-Item (Join-Path $templatesSiteDir "php") $siteDir -Recurse -Force

# ===== Genera .env con valores del sitio =====
$envContent = @"
PROJECT=$slug
DOMAIN=$Domain
MYSQL_ROOT_PASSWORD=$RootPW
MYSQL_USER=$DbUser
MYSQL_PASSWORD=$UserPW
MYSQL_DATABASE=$DbName
"@
$envContent | Set-Content $envFile -Encoding ascii

# ===== Asegura red 'web' (externa) =====
$null = docker network inspect web 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Creando red 'web'..."
  docker network create web | Out-Null
}

# ===== Genera regla Traefik desde template =====
$rule = Get-Content $templatesRuleFile -Raw
$rule = $rule -replace 'PROJECT', $slug -replace 'DOMAIN', $Domain
$rulePath = Join-Path $traefikDynamicDir "$slug.yml"
$rule | Set-Content $rulePath -Encoding ascii

# ===== Añade líneas a hosts (si hay permisos) =====
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$linesToAdd = @("127.0.0.1  $Domain","127.0.0.1  pma.$Domain")

if (Test-Admin) {
  $existing = (Get-Content $hostsPath -ErrorAction SilentlyContinue) -join "`n"
  foreach ($l in $linesToAdd) {
    if ($existing -notmatch [regex]::Escape($l)) {
      Add-Content -Path $hostsPath -Value $l
      Write-Host "Añadida a hosts: $l"
    } else {
      Write-Host "Ya existe en hosts: $l"
    }
  }
} else {
  Write-Warning "No tengo permisos para editar hosts. Añade estas líneas manualmente:"
  $linesToAdd | ForEach-Object { Write-Host "  $_" }
}

ipconfig /flushdns | Out-Null

# ===== Levanta el stack =====
Push-Location $siteDir
docker compose --env-file .env up -d
Pop-Location

# ===== Reinicia Traefik para recargar reglas =====
Write-Host "Reiniciando Traefik para aplicar nueva regla..."
docker restart traefik | Out-Null

# ===== Resumen =====
Write-Host "----------------------------------------------------"
Write-Host "Sitio creado: $slug"
Write-Host "Dominio WP:   http://$Domain   (o https si lo configuras)"
Write-Host "phpMyAdmin:   http://pma.$Domain"
Write-Host ""
Write-Host "Carpeta WP para VS Code:"
Write-Host "  $siteDir\wp"
Write-Host ""
Write-Host "Credenciales MySQL generadas:"
Write-Host "  ROOT: $RootPW"
Write-Host "  DB:   $DbName"
Write-Host "  USER: $DbUser"
Write-Host "  PASS: $UserPW"
Write-Host "Regla Traefik: $rulePath"
Write-Host "Compose dir:   $siteDir"
Write-Host "----------------------------------------------------"