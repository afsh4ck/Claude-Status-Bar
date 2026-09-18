# CLAUDE.md

Guía para Claude Code al trabajar en este repositorio.

## Qué es

`Claude-StatusBar` es una statusline de dos líneas para Claude Code, escrita en bash.
Claude Code ejecuta el script en cada render (~1 Hz), le pasa un JSON por stdin y pinta
su stdout debajo del prompt.

```
● 📁 mi-proyecto │ Opus 5 (effort: high) │ 🧠 Contexto ██░░░░░░░░ 78% libre │ 🔢 220k de 1M tokens │ 🕒 Sesión: 12m
🚀 Plan Max 5x │ 5️⃣  Límite 5h: 88% libre · reset en 1h 12m │ 7️⃣  Límite semanal: 91% libre · reset en 6d 10h
```

- **Línea 1 (sesión)**: dot `live` pulsante, 📁 carpeta, modelo + effort, 🧠 barra de
  contexto, 🔢 tokens, 🕒 duración.
- **Línea 2 (cuenta)**: 🚀 plan de suscripción, 5️⃣ límite de 5 horas, 7️⃣ límite semanal,
  🛡 estado opcional del skill `mcp-sentinel`.

Todos los porcentajes son **libre** (lo que queda), nunca lo consumido. La barra de
contexto es la excepción visual: se llena con lo consumido, pero su color y el número
que la acompaña siguen siendo lo libre.

## Archivos

| Archivo | Qué es |
|---|---|
| `custom_bar.sh` | Todo el script. Fuente de verdad. |
| `install.sh` | Copia el script a `~/.claude/` y escribe el bloque `statusLine` en `~/.claude/settings.json`. |
| `README.md` | Documentación de usuario. |
| `assets/*.png` | Capturas del README. |

No hay build, ni tests, ni dependencias instalables.

## Flujo de trabajo

El script vive en dos sitios: **este repo** (fuente) y `~/.claude/custom_bar.sh` (la copia
que ejecuta Claude Code). Editar el repo no cambia nada hasta reinstalar.

```bash
# 1. Editar custom_bar.sh
# 2. Comprobar sintaxis
bash -n custom_bar.sh

# 3. Probar con un JSON de entrada
echo '{"model":{"display_name":"Opus 5"},"effort":{"level":"high"},
       "workspace":{"current_dir":"/tmp/demo"},
       "context_window":{"remaining_percentage":42,"context_window_size":1000000,
                         "total_input_tokens":580000,"total_output_tokens":900},
       "cost":{"total_duration_ms":754000},
       "rate_limits":{"five_hour":{"used_percentage":30,"resets_at":9999999999},
                      "seven_day":{"used_percentage":12,"resets_at":9999999999}}}' | ./custom_bar.sh

# 4. Instalar (y reiniciar Claude Code no hace falta: se relee en cada render)
bash install.sh
```

Para ver los códigos ANSI en crudo, quítalos con
`./custom_bar.sh < entrada.json | sed $'s/\033\\[[0-9;]*m//g'`.

Para capturar el JSON real que envía Claude Code, añade temporalmente tras `input=$(cat)`:

```bash
printf "%s" "$input" > /tmp/statusline_input.json
```

y bórralo después.

## Instalación (usuario final)

```bash
git clone https://github.com/afsh4ck/Claude-Status-Bar.git
cd Claude-Status-Bar
bash install.sh
```

`install.sh` copia `custom_bar.sh` a `~/.claude/`, resuelve la ruta absoluta (en Git Bash
para Windows convierte `/c/Users/...` a `C:/Users/...` con `cygpath -m`) y añade a
`~/.claude/settings.json`:

```json
{ "statusLine": { "type": "command", "command": "/ruta/absoluta/.claude/custom_bar.sh" } }
```

Claude Code no expande `~` en ese campo. Desinstalar: borrar el script y quitar el bloque
`statusLine` (o ponerlo a `null`).

## De dónde salen los datos

**Del JSON de stdin** (lo que Claude Code entrega en cada render):

| Ruta | Uso |
|---|---|
| `model.display_name`, `model.id` | Nombre del modelo |
| `effort.level` | `(effort: high)` |
| `workspace.current_dir` (o `cwd`) | Carpeta |
| `context_window.remaining_percentage` / `used_percentage` | Barra y % de contexto |
| `context_window.context_window_size` | Tamaño del contexto |
| `context_window.total_input_tokens` + `total_output_tokens` | Contador de tokens |
| `cost.total_duration_ms` | Duración de sesión |
| `rate_limits.five_hour.{used_percentage,resets_at}` | Límite 5h |
| `rate_limits.seven_day.{used_percentage,resets_at}` | Límite semanal |

**De `~/.claude.json` → `oauthAccount`** (el JSON de stdin no trae la suscripción):

| Campo | Valor | Se muestra |
|---|---|---|
| `organizationType` | `claude_pro` | `Pro` |
| `organizationType` + `organizationRateLimitTier` | `claude_max` + `default_claude_max_5x` | `Max 5x` |
| `organizationType` + `organizationRateLimitTier` | `claude_max` + `default_claude_max_20x` | `Max 20x` |
| `organizationType` | `claude_team` | `Team` |
| `organizationType` | `claude_enterprise` | `Enterprise` |

Sin ese bloque (API key, Bedrock, Vertex) se muestra `Sin suscripción (API key)`.

### Lo que NO está disponible

El objeto `rate_limits` que llega al statusline contiene **solo** `five_hour`, `seven_day`
y, en modo gateway, `spend_limit`. Claude Code mantiene internamente ventanas por modelo
(`seven_day_opus`, `seven_day_overage_included`, `model_scoped[]`) pero no las expone aquí;
solo se obtienen llamando a `GET /api/oauth/usage` con el token OAuth del Keychain.

**No añadas esa llamada.** El script es deliberadamente offline: cero red, cero
credenciales, cero latencia. Para el desglose por modelo existe el comando `/usage`.

## Estructura de `custom_bar.sh`

Secciones en orden, marcadas con cabeceras `# ── ... ──`:

1. **Frames de animación** — `anim_frame` (shimmer, `date +%s % 13`) y `pulse_frame`
   (breathing del dot, `% 4`). Sin estado ni polling: el frame se deriva del reloj.
2. **Parseo** — un único bloque Python embebido (heredoc `PYEOF`) lee stdin y
   `~/.claude.json`, e imprime asignaciones `nombre='valor'` que bash evalúa con `eval`.
   Un solo proceso Python por render.
3. **Nombre del modelo** — usa `display_name`; si falta, deriva de `model.id`
   (`claude-fable-5-1` → `Fable 5.1`).
4. **Contexto, rate limits, carpeta, formatos** — `pct_free`, `fmt_n` (`220k`, `1M`),
   `fmt_reset` (`45m`, `1h 12m`, `6d 10h`).
5. **Colores** — `RST`, `DIM` (gris tenue), `WHT` (blanco de etiquetas), `SEP` (` │ `),
   y `color_free`: rojo <15% libre, amarillo <40%, verde el resto.
6. **Barra de contexto** — `width=10` bloques; se llenan con lo consumido, coloreados por
   lo libre, con un bloque brillante recorriéndola.
7. **Líneas 1 y 2** — se componen en `l1` y `l2`, y salen con `echo -e "$l1\n$l2"`.

## Reglas al modificar

- **Rendimiento primero.** El script corre ~1 vez por segundo. Nada de red, sleeps,
  llamadas a `claude`, ni procesos extra. Si necesitas un dato nuevo del sistema, sácalo
  dentro del bloque Python que ya existe.
- **Sin credenciales.** No leer el Keychain ni tokens.
- **Portabilidad**: bash 3.2 (el de macOS), Python 3.6 solo stdlib, `awk`/`date`/`basename`/
  `tr`/`grep`. Nada de `jq`, `bash 4+`, `mapfile`, `${var,,}` ni GNU-ismos de `date`.
- **Degradar siempre.** Cualquier campo puede faltar: el script debe imprimir dos líneas
  igualmente. Casos ya cubiertos: sin contexto todavía, sin rate limits, sin suscripción.
- Toda salida pasa por `echo -e`, así que los escapes se escriben `\033[...m` en cadenas
  normales de bash.
- Tras editar, `bash install.sh` para que el cambio llegue a `~/.claude/custom_bar.sh`.

## Regenerar las capturas del README

Las capturas de `assets/` se generan convirtiendo la salida ANSI del script a HTML y
capturándolo con Chrome headless; no son fotos de terminal. Si cambia el formato hay que
rehacerlas todas: `preview.png` (cabecera, tres estados apilados), `preview-normal.png`,
`preview-lleno.png` y `preview-sin-plan.png` (sección "Vista previa"). Usa datos de
ejemplo coherentes: el plan Max trabaja con contexto de 1M.

## Convenciones del repositorio

- Comentarios y textos de la statusline en español; mensajes de commit en inglés.
- Sin emojis en el código fuera de los que pinta la statusline.
