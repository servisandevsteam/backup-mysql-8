# AGENTS.md

Servicio Docker de backup MySQL 8: `mysqldump` → zip → upload a S3 → limpieza de
backups antiguos. No hay suite de tests ni linter integrado en la imagen.

## Configuración y comandos

- `cp .env.example .env` y completar valores; `.env.example` es la base. Agrega
  `AWS_PREFIX` a mano si vas a usar limpieza.
- `docker compose up -d --build` — levanta `backup-script` (con `sleep infinity`)
  y un `mysql-server:8.4` local para pruebas.
- `docker compose exec backup-script start-backup` — corre el ciclo completo en
  primer plano (bucle infinito; Ctrl-C para salir).
- `docker compose exec backup-script update-s3-bucket` — solo limpieza S3.
- `docker compose exec backup-script check-connection` — espera el puerto MySQL.
- `docker build -t <tag> .` — imagen de producción; el `CMD` es `start-backup`
  y `/app/bin` está en `PATH`.

## Arquitectura

- `bin/*` son scripts bash sin extensión, en `PATH`, sin argumentos: toda la
  configuración entra por variables de entorno. Si agregas uno, déjalo
  ejecutable y llámalo por nombre.
- `bin/start-backup` hardcodea `/app/backups` y ejecuta: check DB → dump
  `<YYYYMMDDHHMMSS>.sql` → zip → borrar `.sql` → upload → limpieza S3 →
  `sleep "$TIME_SLEEP"`.
- `bin/upload-backup` se invoca como `pathfile=$PATH_SAVE upload-backup`.
- `bin/update-s3-bucket` hace `cd /app/s3-backup` y `npm install` si falta
  `node_modules`; `s3-backup/update-s3-bucket` es el script Node (aws-sdk v2 +
  moment) que borra claves más antiguas que `EXPIRATE_IN_MONTHS` (default 2).
- Los scripts asumen `/app`, así que no se ejecutan desde el checkout. El bind
  mount `./:/app/` deja los dumps en `backups/` del host (ignorado por git).

## Reglas de código

- Máximo 200 líneas por archivo. El pipeline falla si algún archivo versionado
  (excepto lockfiles) se pasa del límite.
- Cita siempre las expansiones (`"$VAR"`). Para condicionales usa
  `[ "$VAR" = "" ]` / `[ "$VAR" != "" ]`, que es lo que espera shellharden.
- No cambies la interfaz por variables de entorno ni el nombre
  `YYYYMMDDHHMMSS.sql.zip` sin actualizar a todos los llamadores y la limpieza.
- No agregues dependencias sin justificarlo. La imagen trae Node 22, AWS CLI v2,
  cliente MySQL, `zip` y `unzip`.
- No edites `.env` ni imprimas secretos.

## Herramientas de calidad

| Función | Herramienta | Comando |
| --- | --- | --- |
| LSP | `shuck` | `shuck server` (configurado en `opencode.json`) |
| DAP | `bash-debug-adapter` | debug del editor con bashdb; requiere el layout `/app` |
| Linter/formatter | `shellharden` | `shellharden --replace <file>` / `--check` |
| Vulnerabilidades | `shellcheck` | `shellcheck --severity=warning bin/*` |
| Análisis estático | `shellyzer` | solo archivos `*.sh` |

Estas herramientas son para el agente y el entorno local; el CI no las ejecuta.

Verificación obligatoria antes de terminar:

```bash
shuck check .
shellharden --check bin/*
shellcheck --severity=warning bin/*
```

Shellyzer solo escanea `.sh`; hay que copiar los scripts sin extensión:

```bash
mkdir -p /tmp/shellyzer-src
for f in bin/*; do cp "$f" "/tmp/shellyzer-src/$(basename "$f").sh"; done
curl -fsSL -o /tmp/shellyzer.py \
  https://raw.githubusercontent.com/automatesecurity/shellyzer/2c93cec49d26358f1a5e7363d6e9b5b7bd6ba2b3/shellyzer.py
python3 /tmp/shellyzer.py /tmp/shellyzer-src
```

Nota: el LSP y el formatter de OpenCode seleccionan por extensión, y `bin/*` no
tiene extensión. Para esos archivos la fuente de verdad es la CLI
(`shuck check`, `shellharden`). `opencode.json` solo cubre `*.sh`/`*.bash`.

## Gotchas

- `AWS_PREFIX` vacío sube al root del bucket, pero la limpieza lista el prefijo
  `/` y no encuentra nada. Sin prefijo, la retención no borra.
- La limpieza solo reconoce claves que terminan en `*.sql.zip` y empiezan con
  fecha; archivos renombrados quedan fuera.
- `database/` solo se ejecuta al inicializar el volumen `dbbackup` por primera
  vez. Para reinicializar: `docker compose down -v`.
- Compose reemplaza el `CMD` por `sleep infinity`; el respaldo no arranca solo.
- `check-connection` depende de que la salida de `telnet` contenga `Connected` y
  bloquea `start-backup` si la base no responde.
- `s3-backup/package-lock.json` fija `aws-sdk` v2 y `moment`; no lo regeneres sin
  probar la limpieza.

## Agentes

- `developer`: escribe y mantiene los scripts. Úsalo para cambios en `bin/`.
- `devops-auditor`: audita seguridad y propone remediaciones; no edita.
- `refactor`: aplica el cambio mínimo, sin cambiar contratos.

Definiciones en `.opencode/agents/`. Delega auditoría al `devops-auditor` antes
de mergear cambios que toquen credenciales, borrado o CI.

## CI/CD

- `.github/workflows/quality.yml`: ejecuta Shellyzer y el límite de 200 líneas.
- `.github/workflows/ci.yml`: ejecuta el workflow anterior en pull requests.
- `.github/workflows/cd.yml`: solo en push a `main` y `feature/cd`; exige
  Shellyzer, publica la imagen en Docker Hub y recrea `backup-servisan` por SSH
  usando los secretos de GitHub.
