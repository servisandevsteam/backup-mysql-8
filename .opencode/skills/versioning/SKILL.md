---
name: Versionado de despliegues
description: Calcula la siguiente versión X.Y.Z con componentes de 0 a 99 y acarreo, y prepara cada despliegue mediante branch y pull request sin tocar main directamente.
---

# Versionado de despliegues

Usa este skill cuando haya que preparar, revisar o publicar un despliegue de
este repositorio.

## Regla de versión

- Cada despliegue usa una versión `vX.Y.Z`; `X`, `Y` y `Z` van de `0` a `99`.
- Se incrementa `Z`. Al pasar de `99`, vuelve a `0` y se incrementa `Y`; si `Y`
  también pasa de `99`, vuelve a `0` y se incrementa `X`.
- Ejemplos: `v0.0.1` -> `v0.0.2`; `v0.0.99` -> `v0.1.0`; `v0.99.99` ->
  `v1.0.0`.
- `v99.99.99` no tiene sucesor dentro de la regla. Detente y pide una decisión
  antes de inventar una versión.
- La versión vigente vive en `VERSION` (sin el prefijo `v`). El tag de git y
  `VERSION` deben coincidir. Sin tags previos, la primera versión es `v0.0.1`.
- No reutilices ni muevas un tag existente. No uses sufijos como `-rc`, `+meta`
  o fechas: el CD solo se dispara con tags `v*` y publica el tag tal cual.

## Flujo obligatorio

1. Sincroniza sin tocar `main` de forma local con cambios pendientes:

   ```bash
   git status --short
   git fetch origin --tags --prune
   git switch main
   git pull --ff-only
   ```

   Si `git status` muestra cambios sin commitear, no los mezcles con el
   despliegue: pregunta si se descartan, se guardan o pertenecen a la release.

2. Calcula la siguiente versión y comprueba que no exista:

   ```bash
   next=$(.opencode/skills/versioning/scripts/next-version.sh)
   git rev-parse --verify --quiet "refs/tags/$next" && exit 1
   git ls-remote --exit-code --tags origin "refs/tags/$next"
   ```

   El segundo comando debe fallar; si el tag ya existe en local o en remoto,
   detente y reporta la inconsistencia.

3. Crea un branch de release. Nunca hagas commit ni push directo a `main`:

   ```bash
   git switch -c "release/$next"
   printf '%s\n' "${next#v}" > VERSION
   ```

4. Incluye en el mismo branch los cambios que se van a desplegar y actualiza
   `README.md`/`AGENTS.md` si cambió el comportamiento. Si el despliegue no
   necesita cambios de código, el bump de `VERSION` es el cambio mínimo.

5. Verifica antes de commitear:

   ```bash
   shuck check .
   shellharden --check bin/*
   shellcheck --severity=warning bin/*
   ```

   Si tocaste `s3-backup/`, agrega
   `npm --prefix s3-backup audit --omit=dev`.

6. Commitea, publica el branch y abre el PR:

   ```bash
   git add VERSION README.md AGENTS.md
   git commit -m "chore(release): $next"
   git push -u origin "release/$next"
   gh pr create --base main --head "release/$next" \
     --title "chore(release): $next" \
     --body "Prepara el despliegue $next. Incluye el bump de VERSION y los cambios de la release."
   ```

   Ajusta `git add` a los archivos reales. No hagas merge del PR salvo que el
   usuario lo pida explícitamente.

7. Solo después de que el PR esté mergeado en `main`, crea el tag que dispara
   el CD:

   ```bash
   git switch main
   git pull --ff-only
   test "$(tr -d '[:space:]' < VERSION)" = "${next#v}"
   git tag -a "$next" -m "release $next"
   git push origin "$next"
   ```

   Si el merge fue squash o hubo cambios, vuelve a verificar `VERSION` antes
   del tag. El push del tag es el único paso que despliega.

## Comprobaciones y errores frecuentes

- `VERSION` y el último tag no coinciden: no continúes; corrige la release con
  un PR y deja que el tag se cree después del merge.
- El tag ya existe: elige la siguiente versión solo si el tag anterior no se
  desplegó; si ya se desplegó, avanza una versión más y documenta el salto.
- `99.99.99`: la regla está agotada; pide cambiar el esquema de versionado.
- No uses `git push --force` ni `git tag -f` sobre tags publicados.
- El CD exige Shellyzer y OSV-Scanner; revisa el estado del PR/tag antes de
  asumir que el despliegue terminó.
