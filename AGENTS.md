# AGENTS.md

Servicio Docker de backup MySQL 8: `mysqldump` → zip → upload a S3 → limpieza de
backups antiguos. No hay suite de tests ni linter integrado en la imagen.

## Configuración y comandos

- `cp .env.example .env` y completar valores; `.env.example` es la base.
  `AWS_PREFIX` debe tener valor si vas a usar limpieza.
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
- `bin/start-backup` hardcodea `/app/backups`, calcula la próxima hora de
  `BACKUP_SCHEDULE` en la zona `BACKUP_TIMEZONE` (opcional), duerme hasta ella y
  ejecuta: check DB → dump `<YYYYMMDDHHMMSS>.sql` → zip → borrar `.sql` →
  upload → limpieza S3. Si el horario no tiene horas válidas termina con error.
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
| Vulnerabilidades shell | `shellcheck` | `shellcheck --severity=warning bin/*` |
| Vulnerabilidades JS | `npm audit` | `npm --prefix s3-backup audit --omit=dev` |
| Dependencias JS | `osv-scanner` | `osv-scanner scan -L s3-backup/package-lock.json` |
| Análisis estático | `shellyzer` | solo archivos `*.sh` |

Estas herramientas son para el agente y el entorno local. El CI solo ejecuta
Shellyzer y OSV-Scanner.

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
- `s3-backup/osv-scanner.toml` ignora 3 vulnerabilidades conocidas hasta
  2027-01-31. No extiendas la fecha: la salida correcta es migrar `aws-sdk` v2 a
  `@aws-sdk/client-s3` y actualizar `moment` a `2.31.0` (o reemplazarlo).
- No uses `npm audit fix --force` en `s3-backup`: propone bajar a `aws-sdk@1.18.0`.

## Agentes

- `developer`: escribe y mantiene los scripts. Úsalo para cambios en `bin/`.
- `devops-auditor`: audita seguridad y propone remediaciones; no edita.
- `refactor`: aplica el cambio mínimo, sin cambiar contratos.

Definiciones en `.opencode/agents/`. Delega auditoría al `devops-auditor` antes
de mergear cambios que toquen credenciales, borrado o CI.

## Versionado y despliegue

- Cada despliegue es un tag `vX.Y.Z` con componentes de 0 a 99. Se incrementa
  el patch; al pasar de 99 se reinicia y se acarrea (`v0.0.99` -> `v0.1.0`,
  `v0.99.99` -> `v1.0.0`). `v99.99.99` está agotado: pide una decisión.
- `VERSION` guarda la versión vigente sin `v` y debe coincidir con el último
  tag. Sin tags previos, el primer despliegue es `v0.0.1`.
- Calcula la siguiente versión con
  `.opencode/skills/versioning/scripts/next-version.sh`.
- El procedimiento completo vive en `.opencode/skills/versioning/SKILL.md`
  (skill `versioning`). No hagas push directo a `main`: crea un branch
  `release/vX.Y.Z`, actualiza `VERSION`, abre un PR con `gh` y crea el tag
  solo después del merge. El push del tag dispara `cd.yml`.

## CI/CD

- `.github/workflows/quality.yml`: ejecuta Shellyzer y el límite de 200 líneas.
- `.github/workflows/js-security.yml`: ejecuta OSV-Scanner sobre
  `s3-backup/package-lock.json`.
- `.github/workflows/ci.yml`: ejecuta ambos workflows en pull requests.
- `.github/workflows/cd.yml`: solo en push de tags `v*`; exige Shellyzer y
  OSV-Scanner, publica la imagen en Docker Hub con el tag de git y `latest`, y
  recrea `backup-servisan` por SSH usando los secretos de GitHub. No despliega
  desde `main`: hay que crear y subir el tag.
