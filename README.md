# 🚀 Entorno WordPress con Docker + Vite + Composer + WP-CLI

## 📑 Índice
- [1. Crear nuevo proyecto](#1-crear-nuevo-proyecto)
- [2. Levantar / detener el stack](#2-levantar--detener-el-stack)
- [3. Verificar estado](#3-verificar-estado)
- [4. Acceder a los servicios](#4-acceder-a-los-servicios)
- [5. WP-CLI](#5-wp-cli)
- [6. Composer](#6-composer)
- [7. Node.js / Vite](#7-nodejs--vite)
- [8. phpMyAdmin](#8-phpmyadmin)
- [9. Red y Traefik](#9-red-y-traefik)
- [10. Gestión de plugins](#10-gestión-de-plugins)
- [11. Logs](#11-logs)
- [12. Solución de problemas comunes](#12-solución-de-problemas-comunes)

---

## 1. Crear nuevo proyecto

Ejecutar script desde la carpeta raíz:

```powershell
.\bin\create-wp.ps1 -Project nombreproyecto
```

Ejemplo:
```powershell
.\bin\create-wp.ps1 -Project talentum
```

Esto genera:
- Carpeta `sites\nombreproyecto`
- `.env` con credenciales aleatorias
- Regla dinámica Traefik
- Entradas en `hosts` (`nombreproyecto.test`, `pma.nombreproyecto.test`)
- Stack levantado con `docker compose up -d`

---

## 2. Levantar / detener el stack

Desde la carpeta del proyecto:

```powershell
docker compose up -d       # Levantar en segundo plano
docker compose down        # Parar y eliminar contenedores
docker compose build       # Reconstruir imágenes
docker compose restart     # Reiniciar contenedores
```

---

## 3. Verificar estado

```powershell
docker compose ps
```

Debe mostrar `running` en:
- `wordpress`
- `db`
- `pma` (phpMyAdmin, opcional)

---

## 4. Acceder a los servicios

- WordPress: `http://<project>.test`
- phpMyAdmin: `http://pma.<project>.test`

---

## 5. WP-CLI

Ejecutar comandos dentro del contenedor:

```powershell
docker compose exec -u www-data wordpress wp core version
docker compose exec -u www-data wordpress wp plugin list
docker compose exec -u www-data wordpress wp theme list
```

Instalar WordPress (ejemplo):
```powershell
docker compose exec -u www-data wordpress wp core install `
  --url="http://nombreproyecto.test" `
  --title="Nombre Proyecto" `
  --admin_user=admin `
  --admin_password=admin123 `
  --admin_email=admin@nombreproyecto.test
```

---

## 6. Composer

Ejemplo en un plugin:

```powershell
docker compose exec -u www-data wordpress bash
cd /var/www/html/wp-content/plugins/mi-plugin
composer install
```

---

## 7. Node.js / Vite

Comprobar versiones:

```powershell
docker compose exec -u www-data wordpress node -v
docker compose exec -u www-data wordpress npm -v
```

Dentro de un tema:

```powershell
docker compose exec -u www-data wordpress bash
cd /var/www/html/wp-content/themes/mi-tema
npm install
npm run dev    # inicia Vite en modo desarrollo
npm run build  # genera build para producción
```

El puerto `5173` ya está expuesto → acceder en `http://localhost:5173`.

---

## 8. phpMyAdmin

Abrir navegador en:

```
http://pma.<project>.test
```

Credenciales:
- **Servidor**: `${PROJECT}-db`
- **Usuario**: `${MYSQL_USER}`
- **Contraseña**: `${MYSQL_PASSWORD}`

---

## 9. Red y Traefik

Comprobar que los contenedores están en la red `web`:

```powershell
docker network inspect web
```

Traefik se reinicia automáticamente al crear un nuevo proyecto, cargando la regla dinámica en `infra/traefik/dynamic/<project>.yml`.

---

## 10. Gestión de plugins

Los plugins de la carpeta `templates/wp-site/plugins` se copian automáticamente al volumen de WordPress en cada nuevo proyecto.

Puedes comprobarlo:

```powershell
docker compose exec -u www-data wordpress ls -l /var/www/html/wp-content/plugins
```

---

## 11. Logs

```powershell
docker compose logs wordpress
docker compose logs db
docker compose logs pma
```

Para seguir logs en tiempo real:

```powershell
docker compose logs -f wordpress
```

---

## 12. Solución de problemas comunes

- **`memory_limit` warning**  
  Editar `php/conf.d/uploads.ini` → usar `M` en vez de `MB`:  
  ```ini
  memory_limit = 1024M
  ```

- **WP-CLI da error de root**  
  Ya solucionado en Dockerfile con `--allow-root` o `ENV WP_CLI_ALLOW_ROOT=1`.

- **`hosts` bloqueado**  
  El script reintenta varias veces. Si aún falla, añadir manualmente:
  ```
  127.0.0.1  <project>.test
  127.0.0.1  pma.<project>.test
  ```
