# Claude-StatusBar

<img width="2464" height="700" alt="image" src="https://github.com/user-attachments/assets/cb9dd9bf-b5b8-46e5-8662-306e8a56667b" />

Status Bar para [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) escrito en bash. Muestra modelo, contexto, tokens, rate limits y duración de sesión en una sola línea, con animaciones suaves a 1 Hz.

Compatible con **Windows** (Git Bash), **macOS** y **Linux**.

## Características

- Indicador `live` pulsante (breathing verde, 4 frames).
- Carpeta de trabajo abreviada.
- Modelo + nivel de effort actual (`Opus 4.7 (xhigh)`, `Sonnet 4.6 (high)`, etc.).
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

- **bash** 3.2+ — macOS incluye 3.2 nativo; en Windows usa [Git Bash](https://git-scm.com/downloads).
- **Python 3.6+** (`python3` o `python`) — para parsear el JSON de entrada; ya viene instalado en macOS 3.x+, la mayoría de distribuciones Linux y la descarga estándar de Windows.
- `awk`, `date`, `basename`, `tr`, `grep` — presentes en cualquier macOS, Linux o Git Bash para Windows.
- Terminal con soporte de color truecolor (24-bit). Probado en iTerm2, Terminal.app, Alacritty, Kitty, WezTerm, Windows Terminal.

## Instalación rápida

```bash
git clone https://github.com/afsh4ck/Claude-Status-Bar.git
cd Claude-Status-Bar
bash install.sh
```

El script `install.sh`:

1. Copia `custom_bar.sh` a `~/.claude/`.
2. Detecta el sistema operativo y construye la ruta absoluta correcta (Windows necesita `C:/Users/…`, macOS/Linux usan la ruta Unix directa).
3. Actualiza `~/.claude/settings.json` añadiendo el bloque `statusLine` sin tocar el resto de tu configuración.

Reinicia Claude Code una vez finalizado.

## Instalación manual

1. Copia el script y dale permisos de ejecución:

   ```bash
   cp custom_bar.sh ~/.claude/custom_bar.sh
   chmod +x ~/.claude/custom_bar.sh
   ```

2. Añade el bloque `statusLine` a `~/.claude/settings.json`:

   **macOS / Linux**
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "/Users/TU_USUARIO/.claude/custom_bar.sh"
     }
   }
   ```

   **Windows (Git Bash)**
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash 'C:/Users/TU_USUARIO/.claude/custom_bar.sh'"
     }
   }
   ```

   > Claude Code no expande `~` en este campo; usa la ruta absoluta completa.

3. Reinicia Claude Code (`exit` y vuelve a abrir).

## Configuración

No hay flags ni variables de entorno: el script lee todo del JSON que pasa Claude Code por stdin. Para cambiar el aspecto edita directamente `~/.claude/custom_bar.sh`:

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
