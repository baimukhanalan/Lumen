#!/bin/bash
#
# awayke — управление функцией "не спать при закрытой крышке, пока идёт
# сессия Claude/Codex". Тонкая обёртка над файлами-флагами и pmset.
#
#   awayke status   — что сейчас: демон, режим сна, идёт ли сессия, батарея
#   awayke on       — принудительно держать бодрым (для работы с телефона)
#   awayke off      — принудительно разрешить сон прямо сейчас
#   awayke auto     — вернуть автоматический режим (по сессиям) [по умолчанию]
#   awayke remote   — режим "работаю с телефона": держать бодрым + wake-on-net (AC)
#   awayke log      — последние строки лога переключений
#   awayke test     — прогнать логику в DRYRUN (без изменений системы)

set -u

FORCE_ON=/tmp/awayke-force-on
FORCE_OFF=/tmp/awayke-force-off
LABEL=com.local.awaykewatch
SCRIPT=/usr/local/bin/awayke-watch.sh
LOG=/var/log/awayke-watch.log

cmd="${1:-status}"

case "$cmd" in
  on)
    rm -f "$FORCE_OFF"; : > "$FORCE_ON"
    echo "✅ Режим: ДЕРЖАТЬ БОДРЫМ принудительно (кроме низкой батареи)."
    echo "   Совет: держи ноут на зарядке, если работаешь с телефона."
    ;;
  off)
    rm -f "$FORCE_ON"; : > "$FORCE_OFF"
    echo "😴 Режим: РАЗРЕШИТЬ СОН принудительно (перебивает активность)."
    ;;
  auto)
    rm -f "$FORCE_ON" "$FORCE_OFF"
    echo "🔄 Режим: АВТО — бодрствует, пока идёт сессия Claude/Codex, иначе спит."
    ;;
  remote)
    if pmset -g batt 2>/dev/null | grep -q "Battery Power"; then
      echo "⚠️  Сейчас ты НА БАТАРЕЕ. Для стабильной работы с телефона поставь ноут"
      echo "    на зарядку — иначе при заряде <20% он всё равно уснёт (это защита)."
    fi
    rm -f "$FORCE_OFF"; : > "$FORCE_ON"
    echo "📱 Remote-режим: держу бодрым принудительно."
    echo "   Включаю wake-on-network на зарядке (спросит пароль sudo)…"
    if sudo pmset -c womp 1; then echo "   ✅ womp=1 (действует на зарядке)"; else echo "   ⚠️ не удалось включить womp"; fi
    echo "   Выход из remote-режима: awayke auto   (womp снять: sudo pmset -c womp 0)"
    ;;
  log)
    if [ -f "$LOG" ]; then tail -n "${2:-30}" "$LOG"; else echo "лог пуст (ещё не было переключений)"; fi
    ;;
  test)
    if [ ! -x "$SCRIPT" ]; then echo "не найден $SCRIPT — сначала установи демон"; exit 1; fi
    echo "Прогон логики без изменений системы:"
    AWAYKE_DRYRUN=1 AWAYKE_LOG=/dev/null AWAYKE_STATE=/tmp/awayke-test.state "$SCRIPT"
    ;;
  status)
    echo "── awayke status ─────────────────────────────"
    # демон установлен? (проверка по plist — без sudo)
    if [ -f "/Library/LaunchDaemons/$LABEL.plist" ]; then
      echo "демон:        установлен ($LABEL)"
    else
      echo "демон:        НЕ установлен"
    fi
    # режим
    if   [ -f "$FORCE_OFF" ]; then echo "режим:        OFF (принудительный сон)"
    elif [ -f "$FORCE_ON"  ]; then echo "режим:        ON (принудительно бодрым)"
    else echo "режим:        AUTO (по сессиям)"; fi
    # текущее состояние сна
    sd="$(pmset -g 2>/dev/null | awk '/SleepDisabled/{print $2; f=1} END{if(!f) print 0}')"
    if [ "$sd" = "1" ]; then echo "сон:          ЗАПРЕЩЁН сейчас (крышку можно закрывать)"
    else echo "сон:          разрешён (обычный режим)"; fi
    # идёт ли сессия (та же проверка, что в демоне)
    UH="${AWAYKE_USER_HOME:-$HOME}"
    active="нет"
    for d in "$UH/.claude/projects" "$UH/.codex/sessions"; do
      [ -d "$d" ] || continue
      if find "$d" -type f -name '*.jsonl' -mmin -10 2>/dev/null | grep -q .; then active="ДА"; break; fi
    done
    echo "сессия (10м): $active"
    # питание
    echo "питание:      $(pmset -g batt 2>/dev/null | sed -n '1p' | sed 's/Now drawing from //')"
    echo "wake-on-net:  $(pmset -g 2>/dev/null | awk '/womp/{print ($2==1?"вкл (на зарядке)":"выкл")}')"
    echo "──────────────────────────────────────────────"
    ;;
  *)
    echo "usage: awayke {status|on|off|auto|remote|log|test}"; exit 1;;
esac
