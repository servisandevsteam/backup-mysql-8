# Backup MySQL 8

Servicio Docker que respalda una base MySQL 8, comprime el dump y lo sube a
Amazon S3. Después de cada subida elimina los backups que superaron la
retención configurada.

## Flujo de una ejecución

```text
check-connection -> mysqldump -> zip -> upload-backup -> update-s3-bucket
        |                                                        |
   espera el puerto                                   borra backups antiguos
```

El ciclo se repite cada `TIME_SLEEP` segundos y no termina por sí solo.

## Componentes

| Ruta | Responsabilidad |
| --- | --- |
| `bin/start-backup` | Orquestador del ciclo; dump, compresión, subida y limpieza. |
| `bin/check-connection` | Espera a que `DB_HOSTNAME:DB_PORT` acepte conexiones vía `telnet`. |
| `bin/upload-backup` | Sube el `.zip` con AWS CLI v2. |
| `bin/update-s3-bucket` | Prepara `s3-backup/` y ejecuta la limpieza. |
| `s3-backup/update-s3-bucket` | Script Node que lista y borra objetos antiguos en S3. |
| `database/` | Scripts de inicialización del MySQL de desarrollo (solo primer arranque). |
| `backups/` | Dumps generados por el contenedor (ignorados por git). |

## Requisitos

- Docker con Docker Compose.
- Para validaciones locales: `bash`, `shellcheck`, `shellharden`, `shuck`,
  `python3` y `npm`.

Instalación de las herramientas de análisis:

```bash
sudo apt-get install -y shellcheck
cargo install shellharden   # o descarga el binario desde sus releases
pipx install shuck-cli      # instala el comando `shuck`
```

El DAP `bash-debug-adapter` se instala desde el editor (por ejemplo, la
extensión Bash Debug de VS Code) y usa `bashdb` por debajo.

## Configuración

```bash
cp .env.example .env
```

Completa `.env` antes de levantar el stack:

| Variable | Uso |
| --- | --- |
| `DB_NAME` | Base de datos a respaldar. |
| `DB_USERNAME` / `DB_PASSWORD` | Credenciales de MySQL. |
| `DB_HOSTNAME` | Host de MySQL; en Compose es `mysql-server`. |
| `DB_PORT` | Puerto de MySQL, normalmente `3306`. |
| `TIME_SLEEP` | Segundos entre ciclos de backup. |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Credenciales de AWS. |
| `AWS_DEFAULT_REGION` | Región de S3. |
| `AWS_BUCKET` | Bucket destino. |
| `AWS_PREFIX` | Prefijo opcional dentro del bucket. **Configúralo si usas limpieza.** |
| `EXPIRATE_IN_MONTHS` | Meses de retención; por defecto `2`. |

> `AWS_PREFIX` vacío sube al root del bucket, pero la limpieza lista el prefijo
> `/` y no encuentra esos objetos. Sin prefijo, la retención no borra nada.

## Uso local

```bash
docker compose up -d --build
docker compose exec backup-script start-backup     # ciclo completo (Ctrl-C para salir)
docker compose exec backup-script check-connection # probar solo la conexión
docker compose exec backup-script update-s3-bucket # probar solo la limpieza
```

`docker-compose.yml` reemplaza el `CMD` de la imagen por `sleep infinity`, por
eso el respaldo no arranca solo: hay que ejecutar `start-backup` dentro del
contenedor. El bind mount `./:/app/` hace que los dumps aparezcan en
`backups/` del host.

Para reinicializar la base de desarrollo y volver a ejecutar los scripts de
`database/`:

```bash
docker compose down -v
```

## Formato y retención de backups

- Nombre: `YYYYMMDDHHMMSS.sql.zip` en `/app/backups`.
- Se sube a `s3://$AWS_BUCKET/$AWS_PREFIX/` cuando hay prefijo.
- La limpieza solo considera claves que terminan en `*.sql.zip` y cuya fecha
  inicial se puede interpretar; archivos renombrados no se borran.
- El dump `.sql` local se elimina después de comprimirlo.

## Desarrollo

Herramientas acordadas:

| Función | Herramienta | Uso |
| --- | --- | --- |
| LSP | `shuck` | `shuck server`; configurado en `opencode.json`. |
| DAP | `bash-debug-adapter` (bashdb) | Depuración desde el editor; no se configura en `opencode.json`. |
| Linter / formatter | `shellharden` | `--replace` para aplicar, `--check` para verificar. |
| Verificación de vulnerabilidades shell | `shellcheck` | `--severity=warning`. |
| Verificación de vulnerabilidades JS | `npm audit` | `npm --prefix s3-backup audit --omit=dev`. |
| Dependencias JS | `osv-scanner` | `osv-scanner scan -L s3-backup/package-lock.json`. |
| Análisis estático adicional | `shellyzer` | Solo analiza archivos `*.sh`. |

Comandos de verificación antes de abrir un PR:

```bash
shuck check .
shellharden --check bin/*
shellcheck --severity=warning bin/*
```

Estas validaciones son para el agente y el entorno local. El CI solo ejecuta
Shellyzer y OSV-Scanner. Shellyzer necesita extensión `.sh`, así que el pipeline
copia `bin/*` a un directorio temporal antes de analizarlo.

### Seguridad de dependencias JavaScript

```bash
npm --prefix s3-backup audit --omit=dev
osv-scanner scan -L s3-backup/package-lock.json
```

`npm audit` muestra 3 vulnerabilidades conocidas: `aws-sdk` v2 y su `uuid`
transitivo, más `moment@2.30.1`. **No uses `npm audit fix --force`**: intenta
bajar a `aws-sdk@1.18.0`. La solución es migrar a `@aws-sdk/client-s3` v3 y
actualizar `moment` a `2.31.0`.

`osv-scanner` se ejecuta en CI y usa `s3-backup/osv-scanner.toml` para ignorar
esas 3 excepciones hasta el **2027-01-31**. Pasada esa fecha el pipeline falla
para forzar la migración; no extiendas el plazo sin resolver la deuda.

Reglas de código:

- Cada archivo debe tener 200 líneas o menos (los lockfiles quedan excluidos).
- Los scripts de `bin/` no llevan extensión, usan `#!/bin/bash` y reciben su
  configuración por variables de entorno, no por argumentos.
- Cita siempre las expansiones (`"$VAR"`); una variable sin citar rompe el
  chequeo de `shellharden`.
- Los scripts asumen `/app`; no se ejecutan directamente desde el checkout.
- No agregues dependencias sin justificarlo: la imagen trae Node 22, AWS CLI v2,
  cliente MySQL y `zip`.

## Agentes de OpenCode

| Agente | Cuándo usarlo |
| --- | --- |
| `developer` | Escribir o modificar scripts en `bin/`. |
| `devops-auditor` | Revisar riesgos de seguridad y obtener remediaciones (no edita). |
| `refactor` | Aplicar el cambio mínimo para corregir o simplificar. |

Las definiciones viven en `.opencode/agents/` y las reglas compartidas en
`AGENTS.md`.

## CI/CD

- `.github/workflows/ci.yml` ejecuta ambos workflows en cada pull request.
- `.github/workflows/quality.yml` contiene los pasos reutilizables: Shellyzer y
  límite de 200 líneas.
- `.github/workflows/js-security.yml` ejecuta OSV-Scanner sobre
  `s3-backup/package-lock.json`.
- `.github/workflows/cd.yml` corre en push a `main` y `feature/cd`: primero
  exige Shellyzer y OSV-Scanner, luego construye y publica la imagen en Docker
  Hub y recrea el contenedor remoto `backup-servisan` por SSH.

No existe suite de tests. La verificación funcional es construir la imagen y
correr un ciclo contra el MySQL de Compose.

## Documentar cambios

Cuando cambie el comportamiento del producto (variables de entorno, formato de
archivo, retención, flujo de subida o despliegue), actualiza este README y
`AGENTS.md` en el mismo PR. Las imágenes se publican con tag `latest` y el SHA
del commit, por lo que el README es la referencia vigente para operar cualquier
versión desplegada.
