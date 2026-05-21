# Claude-StatusBar

Statusline para [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) escrito en bash puro. Muestra modelo, contexto, tokens, rate limits y duración de sesión en una sola línea, con animaciones suaves a 1 Hz.

## Características

- Indicador `live` pulsante (breathing verde, 4 frames).
- Carpeta de trabajo abreviada.
- Modelo + nivel de effort actual (`opus 4.7 (xhigh)`, `sonnet 4.6 (high)`, etc.).
- Barra de contexto multicolor verde → amarillo → rojo (10 bloques, degradado continuo) con efecto shimmer que recorre los bloques llenos.
- Porcentaje libre de contexto con color por umbral.
- Contador de tokens `usados / tamaño del contexto` con formato compacto (`1.2k`, `3.4M`).
- Duración acumulada de la sesión.
- Rate limits 5h y 7d (solo en cuentas Claude Pro/Max). En cuentas API/prepaid muestra `N/A (API)` porque ese campo no existe.
- Segmento opcional `SNTL:ON/OFF` para el skill [mcp-sentinel](https://github.com/anthropics/claude-code) — solo aparece si los archivos del sentinel están instalados.

## Vista previa

```
● 📁 mi-proyecto │ 🤖 Opus 4.7 (xhigh) │ ██████░░░░ 42% libre │ 🔢 24.5k / 1.0M │ ⏱ 12m │ 📊 5h: 87% libre (reset en 3h 12m) · Semana: 64% libre (reset en 4d 2h)
```

## Requisitos

- `bash` 4+ (en macOS usa Homebrew si necesitas una versión moderna; el script funciona en el bash 3.2 nativo, pero la concatenación de animaciones queda mejor con 4+).
- `jq` — `brew install jq` / `apt install jq`.
- `awk`, `date`, `basename`, `tr`, `grep` (presentes en cualquier macOS o Linux).
- Terminal con soporte de color truecolor (24-bit). Probado en iTerm2, Terminal.app, Alacritty, Kitty, WezTerm.

## Instalación

1. Clona o descarga este repositorio.

   ```bash
   git clone https://github.com/<tu-usuario>/Claude-StatusBar.git
   cd Claude-StatusBar
   ```

2. Copia el script a tu directorio de Claude Code y dale permisos de ejecución.

   ```bash
   cp custom_bar.sh ~/.claude/custom_bar.sh
   chmod +x ~/.claude/custom_bar.sh
   ```

3. Registra el statusline en `~/.claude/settings.json`. Si el archivo no existe, créalo con este contenido:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "/Users/TU_USUARIO/.claude/custom_bar.sh"
     }
   }
   ```

   Si ya tienes `settings.json`, añade únicamente el bloque `statusLine` respetando el resto. Sustituye `TU_USUARIO` por tu nombre de usuario real (Claude Code no expande `~` en este campo, hay que poner la ruta absoluta).

4. Reinicia Claude Code (`exit` y vuelve a abrir). La nueva barra aparecerá debajo del prompt.

## Configuración

No hay flags ni variables de entorno: el script lee todo del JSON que pasa Claude Code por stdin. Para cambiar el aspecto edita directamente `custom_bar.sh`:

- **Anchura de la barra**: variable `width=10` en la sección "Barra multicolor". Subir a 15 o 20 da más resolución visual.
- **Umbrales de color**: función `color_remaining`. Por defecto rojo <15%, amarillo <40%, verde el resto.
- **Iconos / separadores**: la línea final `echo -e ...` controla el orden y los emojis (📁 🤖 🔢 ⏱ 📊 🛡).
- **Animaciones**: las variables `anim_frame` y `pulse_frame` calculan el frame en cada render usando `date +%s % N`. Si quieres congelar las animaciones, fija ambos a un valor fijo.

## Rate limits 5h / Semana

Los segmentos `5h` y `Semana` solo se rellenan cuando Claude Code incluye el objeto `rate_limits.five_hour` y `rate_limits.seven_day` en el stdin del statusline. Esto sucede únicamente en cuentas con suscripción **Claude Pro** o **Claude Max**.

En cuentas **API/prepaid** (incluyendo Claude Teams con facturación prepago) Claude Code no envía esos campos, así que la barra muestra `N/A (API)` en gris tenue. No es un error: es lo correcto, esas ventanas de rate limit son una característica exclusiva de las suscripciones.

## Cómo lo verifica Claude Code

Claude Code llama al `command` configurado en `statusLine` cada ~1 segundo mientras la sesión está activa, le envía un JSON por stdin y muestra la primera línea de stdout como statusline. El script no tiene estado entre renders: cada llamada parsea de nuevo el JSON. Esto permite refrescar las animaciones sin polling adicional.

Para inspeccionar el JSON que llega al script puedes añadir temporalmente al principio:

```bash
echo "$input" > /tmp/statusline_input.json
```

Y luego revisar `/tmp/statusline_input.json` después de unos segundos.

## Desinstalación

```bash
rm ~/.claude/custom_bar.sh
```

Y elimina el bloque `statusLine` de `~/.claude/settings.json` (o pon `"statusLine": null` para volver al statusline por defecto de Claude Code).

## Licencia

MIT.
