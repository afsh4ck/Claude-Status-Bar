#!/bin/bash
# Claude-StatusBar — statusline para Claude Code con animaciones, barra de
# contexto, contador de tokens, rate limits (Pro/Max) y duración de sesión.
#
# Entrada: JSON por stdin proporcionado por Claude Code (statusLine.type=command).
# Salida: una línea con escapes ANSI para el statusline del terminal.
#
# Dependencias: bash, jq, awk, coreutils (date, basename, tr, grep).

input=$(cat)

# ── Frame de animación (1 Hz, basado en date +%s — sin polling) ────────────
anim_s=$(date +%s)
anim_frame=$(( anim_s % 13 ))       # 0..12: recorre los 10 bloques + 2 de pausa
pulse_frame=$(( anim_s % 4 ))       # 0..3: breathing del dot "live"

# ── Campos básicos ─────────────────────────────────────────────────────────
model_id=$(echo "$input" | jq -r '.model.id // ""')
model_display=$(echo "$input" | jq -r '.model.display_name // ""')
# claude-sonnet-4-7 → Sonnet 4.7 · claude-opus-4-7 → Opus 4.7 · claude-haiku-4-5 → Haiku 4.5
if [[ "$model_id" =~ claude-(opus|sonnet|haiku)-([0-9]+)-([0-9]+) ]]; then
    fam="${BASH_REMATCH[1]}"
    model="$(tr '[:lower:]' '[:upper:]' <<< ${fam:0:1})${fam:1} ${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
elif [ -n "$model_display" ]; then
    model="$model_display"
else
    model="Claude"
fi
# Effort: en v2.1+ el campo oficial es .effort.level; algunas builds antiguas
# usaban .output_config.effort. Probamos ambos y dejamos "?" si no llega.
effort=$(echo "$input" | jq -r '.effort.level // .output_config.effort // empty')
[ -z "$effort" ] && effort="?"
cwd=$(echo "$input"    | jq -r '.workspace.current_dir // .cwd // ""')

# Contexto: distinguimos "campo ausente" (aún sin primera respuesta de API)
# de "0% real". Si no hay datos, ctx_has_data=0 y mostramos un placeholder.
ctx_used_raw=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_rem_raw=$(echo "$input"  | jq -r '.context_window.remaining_percentage // empty')
ctx_size=$(echo "$input"     | jq -r '.context_window.context_window_size // 200000')
if [ -n "$ctx_used_raw" ]; then
    ctx_pct=$(LC_NUMERIC=C awk -v u="$ctx_used_raw" 'BEGIN{printf "%.0f", u}')
    ctx_has_data=1
else
    ctx_pct=0
    ctx_has_data=0
fi
if [ -n "$ctx_rem_raw" ]; then
    ctx_rem=$(LC_NUMERIC=C awk -v r="$ctx_rem_raw" 'BEGIN{printf "%.0f", r}')
elif [ "$ctx_has_data" = "1" ]; then
    ctx_rem=$(( 100 - ctx_pct ))
else
    ctx_rem=""
fi
tok_in=$(echo "$input"  | jq -r '.context_window.total_input_tokens  // 0')
tok_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
dur_ms=$(echo "$input"  | jq -r '.cost.total_duration_ms // 0')

# Rate limits: el campo solo existe en suscripciones Pro/Max y aparece tras la
# primera respuesta de API. En cuentas prepaid/API el objeto rate_limits no
# llega nunca y mostraremos el placeholder "N/A (API)".
rl_5h_used_raw=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_5h_reset=$(echo "$input"    | jq -r '.rate_limits.five_hour.resets_at // 0')
rl_7d_used_raw=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_7d_reset=$(echo "$input"    | jq -r '.rate_limits.seven_day.resets_at // 0')

if [ -n "$rl_5h_used_raw" ]; then
    rl_5h_rem=$(awk -v u="$rl_5h_used_raw" 'BEGIN{r=100-u; if(r<0) r=0; if(r>100) r=100; printf "%d", r}')
else
    rl_5h_rem=""
fi
if [ -n "$rl_7d_used_raw" ]; then
    rl_7d_rem=$(awk -v u="$rl_7d_used_raw" 'BEGIN{r=100-u; if(r<0) r=0; if(r>100) r=100; printf "%d", r}')
else
    rl_7d_rem=""
fi

# ── Carpeta abreviada ──────────────────────────────────────────────────────
folder="${cwd/#$HOME/~}"
folder=$(basename "$folder")
[ -z "$folder" ] && folder="~"

# ── Formato de tokens (1.2k / 3.4M) ────────────────────────────────────────
fmt_n() {
    local n=$1
    if   [ "$n" -lt 1000 ];     then echo "$n"
    elif [ "$n" -lt 1000000 ];  then LC_NUMERIC=C awk "BEGIN{printf \"%.1fk\", $n/1000}"
    else                              LC_NUMERIC=C awk "BEGIN{printf \"%.1fM\", $n/1000000}"
    fi
}
tokens_total=$((tok_in + tok_out))
tok_fmt=$(fmt_n "$tokens_total")
ctx_max_fmt=$(fmt_n "$ctx_size")

# ── Duración de sesión ─────────────────────────────────────────────────────
secs=$((dur_ms / 1000))
if   [ "$secs" -lt 60 ];   then dur_str="${secs}s"
elif [ "$secs" -lt 3600 ]; then dur_str="$((secs/60))m"
else                            dur_str="$((secs/3600))h$((secs%3600/60))m"
fi

# ── Tiempo hasta reset (formato "2h" / "3d 5h") ────────────────────────────
# "—" = sin ventana abierta (API no envía resets_at aún)
# "ya" = reset vencido
fmt_reset() {
    local target=$1
    local now=$(date +%s)
    if [ "$target" -le 0 ]; then echo "—"; return; fi
    local diff=$((target - now))
    if [ "$diff" -le 0 ]; then echo "ya"; return; fi
    local d=$(( diff / 86400 ))
    local h=$(( (diff % 86400) / 3600 ))
    local m=$(( (diff % 3600) / 60 ))
    if   [ "$d" -gt 0 ] && [ "$h" -gt 0 ]; then echo "${d}d ${h}h"
    elif [ "$d" -gt 0 ];                   then echo "${d}d"
    elif [ "$h" -gt 0 ] && [ "$m" -gt 0 ]; then echo "${h}h ${m}m"
    elif [ "$h" -gt 0 ];                   then echo "${h}h"
    elif [ "$m" -gt 0 ];                   then echo "${m}m"
    else                                        echo "<1m"
    fi
}

# ── Barra multicolor verde→amarillo→rojo (10 bloques, degradado continuo) ──
width=10
filled=$(( (ctx_pct * width + 50) / 100 ))
[ "$filled" -gt "$width" ] && filled=$width
bar=""
for ((i=0; i<width; i++)); do
    pos=$(( (2*i + 1) * 5 ))           # centro del bloque en %: 5, 15, 25… 95
    if [ "$pos" -le 50 ]; then
        r=$(( pos * 255 / 50 )); g=255
    else
        r=255; g=$(( (100 - pos) * 255 / 50 ))
    fi
    if [ "$i" -lt "$filled" ]; then
        # Shimmer: el bloque en la posición de la animación gana brillo
        if [ "$i" -eq "$anim_frame" ]; then
            br=$(( (r + 255) / 2 ))
            bg=$(( (g + 255) / 2 ))
            bar+="\033[1m\033[38;2;${br};${bg};200m█\033[22m"
        else
            bar+="\033[38;2;${r};${g};0m█"
        fi
    else
        # Traza tenue del shimmer al pasar por bloques vacíos
        if [ "$i" -eq "$anim_frame" ]; then
            bar+="\033[38;2;110;110;110m█"
        else
            bar+="\033[38;2;60;60;60m█"
        fi
    fi
done
bar+="\033[0m"

# ── Dot "live" pulsante (breathing verde, 4 frames) ────────────────────────
case "$pulse_frame" in
    0) live_dot="\033[38;2;40;170;80m●\033[0m" ;;
    1) live_dot="\033[38;2;80;215;120m●\033[0m" ;;
    2) live_dot="\033[1m\033[38;2;140;255;180m●\033[22m\033[0m" ;;
    3) live_dot="\033[38;2;80;215;120m●\033[0m" ;;
esac

# ── Color por % restante (bajo=rojo, medio=amarillo, alto=verde) ───────────
color_remaining() {
    local p=$1
    if   [ "$p" -lt 15 ]; then echo "\033[1;31m"
    elif [ "$p" -lt 40 ]; then echo "\033[1;33m"
    else                        echo "\033[1;32m"
    fi
}
RST="\033[0m"
DIM="\033[2;37m"

if [ -n "$rl_5h_rem" ]; then
    rl_5h_seg="$(color_remaining "$rl_5h_rem")${rl_5h_rem}%${RST} libre (reset en $(fmt_reset "$rl_5h_reset"))"
else
    rl_5h_seg="${DIM}N/A (API)${RST}"
fi
if [ -n "$rl_7d_rem" ]; then
    rl_7d_seg="$(color_remaining "$rl_7d_rem")${rl_7d_rem}%${RST} libre (reset en $(fmt_reset "$rl_7d_reset"))"
else
    rl_7d_seg="${DIM}N/A (API)${RST}"
fi

# ── Sentinel (opcional) ────────────────────────────────────────────────────
# Solo se muestra si se detectan los archivos del skill mcp-sentinel. Si no
# están instalados, se omite el segmento entero.
SENTINEL_SCRIPT="$HOME/.claude/skills/mcp-sentinel/hooks/sentinel_preflight.py"
SETTINGS_FILE="$HOME/.claude/settings.json"
sntl_seg=""
if [ -e "$SENTINEL_SCRIPT" ]; then
    if [ -x "$SENTINEL_SCRIPT" ] && grep -q "sentinel_preflight" "$SETTINGS_FILE" 2>/dev/null; then
        sntl_seg=" │ 🛡 \033[1;32mSNTL:ON\033[0m"
    else
        sntl_seg=" │ 🛡 \033[1;31mSNTL:OFF\033[0m"
    fi
fi

# ── Salida ─────────────────────────────────────────────────────────────────
# Segmento de contexto: bar (visualiza % USADO) + porcentaje LIBRE en texto.
# Cuando aún no hay datos (antes de la primera respuesta de API), avisamos.
if [ "$ctx_has_data" = "1" ]; then
    ctx_color=$(color_remaining "$ctx_rem")
    ctx_seg="$bar ${ctx_color}${ctx_rem}%${RST} libre"
    tok_seg="${tok_fmt} / ${ctx_max_fmt}"
else
    ctx_seg="$bar ${DIM}sin datos${RST}"
    tok_seg="${DIM}sin datos${RST}"
fi

echo -e "$live_dot 📁 $folder │ 🤖 $model ($effort) │ $ctx_seg │ 🔢 ${tok_seg} │ ⏱ ${dur_str} │ 📊 5h: ${rl_5h_seg} · Semana: ${rl_7d_seg}${sntl_seg}"
