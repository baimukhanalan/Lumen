#!/bin/bash
#
# awayke-watch — держит Mac бодрым при ЗАКРЫТОЙ крышке, только пока
# ИДЁТ сессия Claude Code или Codex, и спокойно отпускает в сон, когда
# сессий нет. Управляет `pmset -a disablesleep`.
#
# Запускается root-демоном (LaunchDaemon) раз в POLL секунд.
#
# "Сессия идёт" = свежая запись (за GRACE_MIN минут) в лог-файлах
# сессий Claude/Codex. Это надёжнее, чем ловить процессы: приложения
# держат процессы, пока просто открыты, а лог сессии пишется только
# когда реально идёт работа/переписка (в т.ч. с телефона по remote).
#
# Защиты:
#   * BATTERY_FLOOR — на батарее ниже этого % сон разрешается всегда;
#   * MAX_HOURS     — жёсткий предел непрерывного бодрствования;
#   * при отсутствии активности состояние сбрасывается (self-heal),
#     ребут тоже сбрасывает disablesleep в 0.
#
# Ручное управление (файлы-флаги, их дёргает CLI `awayke`):
#   FORCE_ON_FILE  — держать бодрым принудительно (кроме порога батареи);
#   FORCE_OFF_FILE — разрешить сон принудительно (перебивает всё).

set -u

# ============================ НАСТРОЙКИ ==============================
# Домашняя папка пользователя (демон работает от root, ~ = /var/root!).
USER_HOME="${AWAYKE_USER_HOME:-/Users/alanbaimukhan}"

# Сколько минут держать бодрым после последней активности сессии.
GRACE_MIN="${AWAYKE_GRACE_MIN:-10}"

# На батарее ниже этого % — разрешаем сон, несмотря на активность.
BATTERY_FLOOR="${AWAYKE_BATTERY_FLOOR:-20}"

# Жёсткий предел непрерывного бодрствования (часов). 0 = без предела.
MAX_HOURS="${AWAYKE_MAX_HOURS:-8}"

# Где искать свежие логи сессий (ищем *.jsonl по mtime).
WATCH_DIRS=(
    "$USER_HOME/.claude/projects"
    "$USER_HOME/.codex/sessions"
)

# Файлы-флаги ручного управления (world-writable /tmp, без sudo).
FORCE_ON_FILE="${AWAYKE_FORCE_ON:-/tmp/awayke-force-on}"
FORCE_OFF_FILE="${AWAYKE_FORCE_OFF:-/tmp/awayke-force-off}"

# Служебные пути.
LOG="${AWAYKE_LOG:-/var/log/awayke-watch.log}"
STATE="${AWAYKE_STATE:-/var/run/awayke-watch.state}"

# DRYRUN=1 — ничего не переключать, только печатать решение (для тестов).
DRYRUN="${AWAYKE_DRYRUN:-0}"
# ====================================================================

now() { date +%s; }

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG" 2>/dev/null || true
    [ "$DRYRUN" = "1" ] && printf 'LOG: %s\n' "$1"
}

# --- определить, идёт ли сессия ---
is_active() {
    [ -f "$FORCE_OFF_FILE" ] && return 1      # ручной "спать" перебивает всё
    [ -f "$FORCE_ON_FILE" ]  && return 0      # ручной "не спать"
    local d
    for d in "${WATCH_DIRS[@]}"; do
        [ -d "$d" ] || continue
        if find "$d" -type f -name '*.jsonl' -mmin -"$GRACE_MIN" 2>/dev/null | grep -q .; then
            return 0
        fi
    done
    return 1
}

forced_on() { [ -f "$FORCE_ON_FILE" ] && [ ! -f "$FORCE_OFF_FILE" ]; }

# --- питание ---
on_battery() {
    if [ -n "${AWAYKE_FAKE_ON_BATTERY:-}" ]; then
        [ "$AWAYKE_FAKE_ON_BATTERY" = "1" ]; return
    fi
    pmset -g batt 2>/dev/null | grep -q "Battery Power"
}
battery_pct() {
    if [ -n "${AWAYKE_FAKE_PCT:-}" ]; then echo "$AWAYKE_FAKE_PCT"; return; fi
    pmset -g batt 2>/dev/null | grep -Eo '[0-9]+%' | tr -d '%' | head -1
}

# --- текущее состояние сна ---
sleep_disabled() {
    pmset -g 2>/dev/null | awk '/SleepDisabled/ {print $2; f=1} END{if(!f) print 0}'
}

# --- состояние между запусками ---
load_state() { on_since=0; capped=0; [ -f "$STATE" ] && . "$STATE" 2>/dev/null; }
save_state() { printf 'on_since=%s\ncapped=%s\n' "$on_since" "$capped" > "$STATE" 2>/dev/null || true; }

# ============================== ЛОГИКА ===============================
load_state
T="$(now)"

if is_active; then
    if [ "$capped" = "1" ]; then
        want=0                                # достигли лимита — ждём простоя
    else
        want=1
        [ "$on_since" = "0" ] && on_since="$T"
        if [ "$MAX_HOURS" != "0" ]; then
            max_secs=$(( MAX_HOURS * 3600 ))
            if [ $(( T - on_since )) -ge "$max_secs" ]; then
                want=0; capped=1
                log "Достигнут предел ${MAX_HOURS}ч непрерывно → отпускаю в сон до простоя"
            fi
        fi
    fi
else
    want=0; on_since=0; capped=0              # простой — полный сброс (self-heal)
fi

# порог батареи (safety) — перебивает даже force-on
reason=""
if [ "$want" = "1" ] && on_battery; then
    pct="$(battery_pct)"
    if [ -n "$pct" ] && [ "$pct" -le "$BATTERY_FLOOR" ]; then
        want=0
        reason="батарея ${pct}% <= ${BATTERY_FLOOR}%"
    fi
fi

save_state

have="$(sleep_disabled)"

if [ "$DRYRUN" = "1" ]; then
    echo "DRYRUN: want=$want have=$have on_since=$on_since capped=$capped ${reason:+($reason)}"
    exit 0
fi

if [ "$want" != "$have" ]; then
    pmset -a disablesleep "$want"
    if [ "$want" = "1" ]; then
        log "Сессия активна → disablesleep 1 (крышку можно закрывать)"
    else
        log "Сон разрешён → disablesleep 0${reason:+ ($reason)}"
    fi
fi

exit 0
