#!/bin/bash
# Claude-StatusBar — statusline de 2 líneas para Claude Code.
#
#   Línea 1 (sesión):  carpeta · modelo · contexto · tokens · duración
#   Línea 2 (cuenta):  plan · límite 5h · límite semanal
#
# Entrada: JSON por stdin (statusLine.type=command) + ~/.claude.json para el plan.
# Salida: dos líneas con escapes ANSI.
#
# Todos los porcentajes mostrados son LIBRE (lo que queda), no lo consumido.
#
# Dependencias: bash, awk, coreutils (date, basename, tr), python3 (stdlib).

input=$(cat)

# ── Frames de animación (1 Hz, derivados de date +%s — sin polling) ─────────
anim_s=$(date +%s)
anim_frame=$(( anim_s % 13 ))       # 0..12: recorre los 10 bloques + 2 de pausa
pulse_frame=$(( anim_s % 4 ))       # 0..3: breathing del dot "live"

# ── Parseo: stdin (sesión) + ~/.claude.json (plan) en un solo proceso ───────
_py=$(cat <<'PYEOF'
import json, os, sys

def get_int(d, *keys, default='0'):
    for k in keys:
        if not isinstance(d, dict):
            return default
        v = d.get(k)
        if v is None:
            return default
        d = v
    try:
        return str(int(d))
    except (ValueError, TypeError):
        return default

def maybe(d, *keys):
    """'' si la ruta no existe o es null; si no, el valor como str."""
    for k in keys:
        if not isinstance(d, dict) or k not in d:
            return ''
        d = d[k]
        if d is None:
            return ''
    return str(d)

try:
    d = json.load(sys.stdin)
except Exception:
    d = {}

# Plan: ~/.claude.json → oauthAccount. organizationType da la familia
# (claude_pro/claude_max/claude_team/claude_enterprise) y
# organizationRateLimitTier el escalón de Max (default_claude_max_5x/_20x).
plan, plan_family = '', ''
try:
    with open(os.path.expanduser('~/.claude.json'), encoding='utf-8') as f:
        acc = json.load(f).get('oauthAccount') or {}
    org_type = acc.get('organizationType') or ''
    tier     = acc.get('organizationRateLimitTier') or ''
    plan_family = {
        'claude_pro':        'pro',
        'claude_max':        'max',
        'claude_team':       'team',
        'claude_enterprise': 'enterprise',
    }.get(org_type, '')
    plan = {
        'pro': 'Pro', 'max': 'Max', 'team': 'Team', 'enterprise': 'Enterprise',
    }.get(plan_family, '')
    if plan_family == 'max':
        plan += {'default_claude_max_5x': ' 5x',
                 'default_claude_max_20x': ' 20x'}.get(tier, '')
except Exception:
    pass

rows = [
    ('model_id',       maybe(d, 'model', 'id')),
    ('model_display',  maybe(d, 'model', 'display_name')),
    ('effort',         maybe(d, 'effort', 'level')),
    ('cwd',            maybe(d, 'workspace', 'current_dir') or maybe(d, 'cwd')),
    ('plan',           plan),
    ('plan_family',    plan_family),
    ('ctx_rem_raw',    maybe(d, 'context_window', 'remaining_percentage')),
    ('ctx_used_raw',   maybe(d, 'context_window', 'used_percentage')),
    ('ctx_size',       get_int(d, 'context_window', 'context_window_size', default='200000')),
    ('tok_in',         get_int(d, 'context_window', 'total_input_tokens',  default='0')),
    ('tok_out',        get_int(d, 'context_window', 'total_output_tokens', default='0')),
    ('dur_ms',         get_int(d, 'cost', 'total_duration_ms',             default='0')),
    ('rl_5h_used_raw', maybe(d, 'rate_limits', 'five_hour', 'used_percentage')),
    ('rl_5h_reset',    get_int(d, 'rate_limits', 'five_hour', 'resets_at',  default='0')),
    ('rl_7d_used_raw', maybe(d, 'rate_limits', 'seven_day', 'used_percentage')),
    ('rl_7d_reset',    get_int(d, 'rate_limits', 'seven_day', 'resets_at',  default='0')),
]

for name, val in rows:
    print(name + "='" + str(val).replace("'", "'\\''") + "'")
PYEOF
)
_python=$(command -v python3 2>/dev/null || command -v python 2>/dev/null)
eval "$(echo "$input" | "$_python" -c "$_py")"

# ── Nombre del modelo ──────────────────────────────────────────────────────
# claude-opus-5 → Opus 5 · claude-fable-5-1 → Fable 5.1 · claude-haiku-4-5 → Haiku 4.5
if [ -n "$model_display" ]; then
    model="$model_display"
elif [[ "$model_id" =~ claude-([a-z]+)-([0-9]+)(-([0-9]+))? ]]; then
    fam="${BASH_REMATCH[1]}"
    model="$(tr '[:lower:]' '[:upper:]' <<< ${fam:0:1})${fam:1} ${BASH_REMATCH[2]}"
    [ -n "${BASH_REMATCH[4]}" ] && model="${model}.${BASH_REMATCH[4]}"
else
    model="Claude"
fi

# ── Contexto libre ─────────────────────────────────────────────────────────
if [ -n "$ctx_rem_raw" ]; then
    ctx_rem=$(LC_NUMERIC=C awk -v r="$ctx_rem_raw" 'BEGIN{printf "%.0f", r}')
elif [ -n "$ctx_used_raw" ]; then
    ctx_rem=$(LC_NUMERIC=C awk -v u="$ctx_used_raw" 'BEGIN{printf "%.0f", 100-u}')
else
    ctx_rem=""
fi

# ── Rate limits: usado → libre ─────────────────────────────────────────────
pct_free() {
    [ -z "$1" ] && return
    awk -v u="$1" 'BEGIN{r=100-u; if(r<0) r=0; if(r>100) r=100; printf "%d", r}'
}
rl_5h_rem=$(pct_free "$rl_5h_used_raw")
rl_7d_rem=$(pct_free "$rl_7d_used_raw")

# ── Carpeta ────────────────────────────────────────────────────────────────
folder=$(basename "${cwd:-$PWD}")
[ -z "$folder" ] && folder="~"

# ── Formatos ───────────────────────────────────────────────────────────────
fmt_n() {
    local n=$1
    if   [ "$n" -lt 1000 ];    then echo "$n"
    elif [ "$n" -lt 1000000 ]; then LC_NUMERIC=C awk "BEGIN{printf \"%.0fk\", $n/1000}"
    else                            LC_NUMERIC=C awk "BEGIN{v=$n/1000000; printf (v==int(v) ? \"%.0fM\" : \"%.1fM\"), v}"
    fi
}

secs=$(( dur_ms / 1000 ))
if   [ "$secs" -lt 60 ];   then dur_str="${secs}s"
elif [ "$secs" -lt 3600 ]; then dur_str="$((secs/60))m"
else                            dur_str="$((secs/3600))h $((secs%3600/60))m"
fi

# Tiempo hasta el reset: "45m" / "2h 10m" / "6d 3h".
fmt_reset() {
    local diff=$(( $1 - $(date +%s) ))
    local d=$(( diff / 86400 ))
    local h=$(( (diff % 86400) / 3600 ))
    local m=$(( (diff % 3600) / 60 ))
    if   [ "$1" -le 0 ];                   then echo "sin ventana abierta"
    elif [ "$diff" -le 0 ];                then echo "ya disponible"
    elif [ "$d" -gt 0 ] && [ "$h" -gt 0 ]; then echo "${d}d ${h}h"
    elif [ "$d" -gt 0 ];                   then echo "${d}d"
    elif [ "$h" -gt 0 ] && [ "$m" -gt 0 ]; then echo "${h}h ${m}m"
    elif [ "$h" -gt 0 ];                   then echo "${h}h"
    elif [ "$m" -gt 0 ];                   then echo "${m}m"
    else                                        echo "<1m"
    fi
}

# ── Colores ────────────────────────────────────────────────────────────────
RST="\033[0m"
DIM="\033[2;37m"
WHT="\033[0;37m"
SEP="${DIM} │ ${RST}"

# Color según % LIBRE: poco = rojo, medio = amarillo, mucho = verde.
color_free() {
    if   [ "$1" -lt 15 ]; then echo "\033[1;31m"
    elif [ "$1" -lt 40 ]; then echo "\033[1;33m"
    else                       echo "\033[1;32m"
    fi
}

# ── Barra de contexto: se llena según se consume ───────────────────────────
# Los bloques muestran lo USADO; el color y el porcentaje, lo que queda libre.
width=10
if [ -n "$ctx_rem" ]; then
    ctx_used=$(( 100 - ctx_rem ))
    filled=$(( (ctx_used * width + 50) / 100 ))
    [ "$filled" -gt "$width" ] && filled=$width
    [ "$filled" -lt 1 ] && [ "$ctx_used" -gt 0 ] && filled=1
    fill_color=$(color_free "$ctx_rem")
else
    filled=0
    fill_color="$DIM"
fi
bar=""
for ((i=0; i<width; i++)); do
    if [ "$i" -lt "$filled" ]; then
        if [ "$i" -eq "$anim_frame" ]; then
            bar+="\033[1m${fill_color}█${RST}"      # shimmer
        else
            bar+="${fill_color}█${RST}"
        fi
    elif [ "$i" -eq "$anim_frame" ]; then
        bar+="\033[38;2;110;110;110m░${RST}"
    else
        bar+="\033[38;2;60;60;60m░${RST}"
    fi
done

# ── Dot "live" pulsante ────────────────────────────────────────────────────
case "$pulse_frame" in
    0) live="\033[38;2;40;170;80m●${RST}" ;;
    2) live="\033[1m\033[38;2;140;255;180m●${RST}" ;;
    *) live="\033[38;2;80;215;120m●${RST}" ;;
esac

# ── Línea 1: sesión ────────────────────────────────────────────────────────
l1="${live} 📁 \033[1;36m${folder}${RST}"
l1+="${SEP}\033[1;35m${model}${RST}"
[ -n "$effort" ] && l1+=" ${WHT}(effort: ${effort})${RST}"
if [ -n "$ctx_rem" ]; then
    l1+="${SEP}🧠 Contexto ${bar} $(color_free "$ctx_rem")${ctx_rem}%${RST} ${DIM}libre${RST}"
    l1+="${SEP}🔢 $(color_free "$ctx_rem")$(fmt_n $((tok_in + tok_out)))${RST}${DIM} de $(fmt_n "$ctx_size") tokens${RST}"
else
    l1+="${SEP}🧠 Contexto ${bar} ${DIM}sin datos aún${RST}"
fi
l1+="${SEP}🕒 ${WHT}Sesión:${RST} ${DIM}${dur_str}${RST}"

# ── Línea 2: cuenta y límites ──────────────────────────────────────────────
case "$plan_family" in
    max)  plan_color="\033[1;35m" ;;
    pro)  plan_color="\033[1;34m" ;;
    "")   plan_color="$DIM" ;;
    *)    plan_color="\033[1;36m" ;;
esac
if [ -n "$plan" ]; then
    l2="🚀 ${DIM}Plan${RST} ${plan_color}${plan}${RST}"
else
    l2="🚀 ${DIM}Sin suscripción (API key)${RST}"
fi

if [ -n "$rl_5h_rem" ]; then
    l2+="${SEP}5️⃣  ${WHT}Límite 5h:${RST} $(color_free "$rl_5h_rem")${rl_5h_rem}%${RST} ${DIM}libre · reset en $(fmt_reset "$rl_5h_reset")${RST}"
fi
if [ -n "$rl_7d_rem" ]; then
    l2+="${SEP}7️⃣  ${WHT}Límite semanal:${RST} $(color_free "$rl_7d_rem")${rl_7d_rem}%${RST} ${DIM}libre · reset en $(fmt_reset "$rl_7d_reset")${RST}"
fi
if [ -z "$rl_5h_rem$rl_7d_rem" ]; then
    l2+="${SEP}${DIM}Límites no disponibles en esta cuenta${RST}"
fi

# ── Sentinel (opcional) ────────────────────────────────────────────────────
# Solo aparece si están los archivos del skill mcp-sentinel.
SENTINEL_SCRIPT="$HOME/.claude/skills/mcp-sentinel/hooks/sentinel_preflight.py"
if [ -e "$SENTINEL_SCRIPT" ]; then
    if [ -x "$SENTINEL_SCRIPT" ] && grep -q "sentinel_preflight" "$HOME/.claude/settings.json" 2>/dev/null; then
        l2+="${SEP}🛡 \033[1;32mSentinel ON${RST}"
    else
        l2+="${SEP}🛡 \033[1;31mSentinel OFF${RST}"
    fi
fi

echo -e "$l1\n$l2"
