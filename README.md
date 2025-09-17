# 🚀 Gestión de instalaciones WordPress con Docker + Traefik

## 🔧 Preparar Traefik

```powershell
# Crear red compartida (si no existe)
docker network create web

# Arrancar Traefik
cd C:\Users\pablo\wp\infra\traefik
docker compose up -d

# Ver dashboard
# http://localhost:8080/dashboard/

# Recargar reglas (cuando añades un sitio)
docker restart traefik
```

---

## 🆕 Crear un nuevo sitio

```powershell
# Desde C:\Users\pablo\wp
.\bin\create-wp.ps1 -Project escuela             # dominio por defecto: escuela.test
.\bin\create-wp.ps1 -Project blog -Domain blog.test
```

---

## ▶️ Arranque / parada / actualización

```powershell
# Arrancar o recrear con cambios del compose
docker compose up -d

# Parar y borrar contenedores (mantiene datos)
docker compose down

# Actualizar a últimas imágenes + recrear
docker compose pull
docker compose up -d
```

---

## 🔍 Diagnóstico y gestión

```powershell
# Ver contenedores
docker ps

# Logs del sitio
docker compose logs -f
docker logs escuela-wp -f
docker logs escuela-db --tail=100

# Ver variables cargadas por compose (valida .env)
docker compose --env-file .env config

# Comprobar envs dentro de WP
docker exec -it escuela-wp env | findstr WORDPRESS_DB

# Entrar al contenedor WP / DB
docker exec -it escuela-wp bash
docker exec -it escuela-db mysql -u root -p
```

---

## 🧹 Borrar un sitio (con carpeta)

```powershell
cd C:\Users\pablo\wp\sites\escuela
docker compose down -v                         # borra contenedores y volúmenes (BD)
Remove-Item -Recurse -Force .                 # borra carpeta del sitio

# borra regla Traefik y reinicia
Remove-Item C:\Users\pablo\wp\infra\traefik\dynamic\escuela.yml
docker restart traefik

# limpia hosts
notepad C:\Windows\System32\drivers\etc\hosts
# elimina líneas escuela.test / pma.escuela.test
ipconfig /flushdns
```

---

## 🧹 Borrar un sitio (sin carpeta)

```powershell
docker rm -f escuela-wp escuela-pma escuela-db
docker volume ls | findstr escuela
docker volume rm escuela_wp_data escuela_db_data
Remove-Item C:\Users\pablo\wp\infra\traefik\dynamic\escuela.yml
docker restart traefik
```

---

## 🖥️ Editar WordPress con VS Code

1. Instala la extensión **Dev Containers** en VS Code.  
2. Lanza el proyecto con `.\bin\create-wp.ps1`.  
3. En VS Code abre la paleta de comandos (**Ctrl+Shift+P**) →  
   `Dev Containers: Attach to Running Container...`.  
4. Selecciona `<project>-wp` (ejemplo: `escuela-wp`).  
5. Abre la carpeta `/var/www/html`.  

👉 Ya puedes trabajar directamente **dentro del contenedor**, sin bind mounts en tu Windows.

---

## 📦 Exportar plugins o temas

### Exportar plugin en `.tar.gz`
Ejemplo con `hld-int`:
```powershell
docker exec escuela-wp tar -czf /tmp/hld-int.tar.gz -C /var/www/html/wp-content/plugins hld-int
docker cp escuela-wp:/tmp/hld-int.tar.gz C:\Users\pablo\Desktop\hld-int.tar.gz
docker exec escuela-wp rm /tmp/hld-int.tar.gz
```

### Exportar tema en `.tar.gz`
Ejemplo con `mi-tema`:
```powershell
docker exec escuela-wp tar -czf /tmp/mi-tema.tar.gz -C /var/www/html/wp-content/themes mi-tema
docker cp escuela-wp:/tmp/mi-tema.tar.gz C:\Users\pablo\Desktop\mi-tema.tar.gz
docker exec escuela-wp rm /tmp/mi-tema.tar.gz
```

---

## 📥 Importar plugins o temas

### Importar plugin
Ejemplo con `mi-plugin.tar.gz` desde el escritorio:
```powershell
docker cp C:\Users\pablo\Desktop\mi-plugin.tar.gz escuela-wp:/tmp/
docker exec escuela-wp tar -xzf /tmp/mi-plugin.tar.gz -C /var/www/html/wp-content/plugins
docker exec escuela-wp rm /tmp/mi-plugin.tar.gz
```

### Importar tema
Ejemplo con `mi-tema.tar.gz`:
```powershell
docker cp C:\Users\pablo\Desktop\mi-tema.tar.gz escuela-wp:/tmp/
docker exec escuela-wp tar -xzf /tmp/mi-tema.tar.gz -C /var/www/html/wp-content/themes
docker exec escuela-wp rm /tmp/mi-tema.tar.gz
```

---

✅ De esta forma puedes trabajar directamente dentro del contenedor con VS Code, y usar `.tar.gz` para mover plugins o temas entre tu WordPress local y tu máquina.
