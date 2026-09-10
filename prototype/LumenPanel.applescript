-- Awayke — панель управления "не спать при закрытой крышке, пока идёт
-- сессия Claude/Codex". Установка и переключение режимов без терминала.
-- Привилегии спрашивает сама macOS (do shell script ... with administrator privileges).

property cliPath : "/usr/local/bin/awayke"
property watchPath : "/usr/local/bin/awayke-watch.sh"
property plistPath : "/Library/LaunchDaemons/com.local.awaykewatch.plist"
property srcDir : (POSIX path of (path to home folder)) & "awayke-watch/"

on isInstalled()
	try
		do shell script "test -x " & quoted form of cliPath
		return true
	on error
		return false
	end try
end isInstalled

on statusText()
	try
		return do shell script quoted form of cliPath & " status"
	on error errMsg
		return "Статус недоступен: " & errMsg
	end try
end statusText

on installAll()
	set s to srcDir
	set sh to "set -e; " & ¬
		"mkdir -p /usr/local/bin; " & ¬
		"cp " & quoted form of (s & "awayke-watch.sh") & " " & watchPath & "; " & ¬
		"cp " & quoted form of (s & "awayke") & " " & cliPath & "; " & ¬
		"chown root:wheel " & watchPath & " " & cliPath & "; " & ¬
		"chmod 755 " & watchPath & " " & cliPath & "; " & ¬
		"cp " & quoted form of (s & "com.local.awaykewatch.plist") & " " & plistPath & "; " & ¬
		"chown root:wheel " & plistPath & "; " & ¬
		"chmod 644 " & plistPath & "; " & ¬
		"launchctl bootout system/com.local.awaykewatch 2>/dev/null || true; " & ¬
		"launchctl bootstrap system " & plistPath
	do shell script sh with administrator privileges
end installAll

on runCli(arg)
	try
		do shell script quoted form of cliPath & " " & arg
	end try
end runCli

on run
	-- 1) установка при необходимости
	if not isInstalled() then
		set src to srcDir
		try
			do shell script "test -f " & quoted form of (src & "awayke")
		on error
			display dialog "Не найдены файлы в папке awayke-watch (" & src & "). Сначала их должен подготовить Claude Code." buttons {"Ок"} default button "Ок" with title "Awayke"
			return
		end try
		set ans to button returned of (display dialog "Awayke ещё не установлен." & return & return & "Установить и запустить сейчас? macOS попросит пароль администратора (я его не вижу)." buttons {"Отмена", "Установить"} default button "Установить" with title "Awayke")
		if ans is not "Установить" then return
		try
			installAll()
		on error errMsg number errNum
			if errNum is -128 then return -- отмена в окне пароля
			display dialog "Не удалось установить:" & return & errMsg & return & return & "Если окно пароля не принимает пароль — это твой пароль ВХОДА в Mac, и аккаунт должен быть администратором." buttons {"Ок"} default button "Ок" with title "Awayke"
			return
		end try
		display dialog "✅ Установлено и запущено. Дальше просто открывай Awayke и выбирай режим." buttons {"Продолжить"} default button "Продолжить" with title "Awayke"
	end if

	-- 2) панель управления
	repeat
		set statusStr to statusText()
		set opts to {"🔄 Авто (спать, когда сессий нет)", "☕️ Держать бодрым (для телефона)", "😴 Разрешить сон сейчас", "📱 Remote-режим (+ wake-on-net на зарядке)", "🔁 Обновить статус", "✖️ Закрыть"}
		set sel to (choose from list opts with title "Awayke — управление" with prompt statusStr default items {"🔁 Обновить статус"})
		if sel is false then exit repeat
		set choice to item 1 of sel
		if choice starts with "🔄" then
			runCli("auto")
			exit repeat
		else if choice starts with "☕️" then
			runCli("on")
			exit repeat
		else if choice starts with "😴" then
			runCli("off")
			exit repeat
		else if choice starts with "📱" then
			runCli("on")
			try
				do shell script "/usr/bin/pmset -c womp 1" with administrator privileges
			end try
			display dialog "📱 Remote-режим включён: держу ноут бодрым + wake-on-network на зарядке." & return & return & "Важно: с телефона через интернет разбудить УСНУВШИЙ ноут нельзя — поэтому держи его на зарядке, пока работаешь удалённо. Вернулся — выбери «Авто»." buttons {"Понятно"} default button "Понятно" with title "Awayke"
			exit repeat
		else if choice starts with "🔁" then
			-- перечитать статус на следующем витке (окно откроется снова)
		else
			exit repeat
		end if
	end repeat
end run
