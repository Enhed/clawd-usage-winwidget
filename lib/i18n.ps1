# ------------------------------------------------------------ languages ----
# All UI text lives here. T 'key' returns the string for the current language
# (config key `language`), falling back to English, then to $default.
# Strings with {0} placeholders are meant for the -f operator.

$Languages = [ordered]@{ en = 'English'; ru = 'Русский' }

$Strings = @{
  en = @{
    'err.noClaude'   = 'Claude Code (claude) was not found. Install it: irm https://claude.ai/install.ps1 | iex'

    'ui.details'     = 'Details'
    'ui.hide'        = 'Minimize to tray'
    'ui.exit'        = 'Exit'
    'ui.week'        = 'WEEK'
    'ui.fable'       = 'FABLE · WEEK'
    'ui.sessions'    = 'SESSIONS'
    'ui.openStatus'  = 'Open status.claude.com'
    'ui.day'         = 'LAST 24 HOURS · THIS COMPUTER'
    'ui.week7'       = 'LAST 7 DAYS'

    'span.d'         = '{0}d {1}h'
    'span.h'         = '{0}h {1:00}m'
    'span.m'         = '{0}m'

    'loading'        = 'loading...'
    'noData'         = 'no data'
    'error'          = 'error'
    'stale'          = 'stale'
    'reset.in'       = 'resets in {0}'
    'reset.closed'   = 'window closed'
    'period'         = '{0} requests  ·  {1} sessions'

    'tray.noData'    = 'clawd-usage-winwidget: no data'
    'tray.session'   = '{0}% of session'
    'tray.week'      = 'week {0}%'

    'sess.none'      = 'none running'
    'sess.busy'      = '{0} working'
    'sess.wait'      = '{0} waiting'
    'plural.session' = @('session', 'sessions')

    'st.loading'     = 'status: loading...'
    'st.offline'     = 'status: no connection'
    'st.ok'          = 'All Claude systems operational'
    'st.maint'       = 'scheduled maintenance'
    'st.issues'      = 'some issues'
    'comp.degraded_performance' = 'degraded'
    'comp.partial_outage'       = 'partial outage'
    'comp.major_outage'         = 'major outage'
    'comp.under_maintenance'    = 'maintenance'

    'ver.updating'   = 'updating...'
    'ver.available'  = '{0} available  ·  what''s new?'
    'ver.latest'     = 'latest'
    'chg.head'       = 'What''s new: {0} → {1}'
    'chg.loading'    = 'loading the changelog...'
    'chg.more'       = '…and {0} more'
    'chg.empty'      = 'nothing in the CHANGELOG yet'
    'chg.click'      = 'Click to update'

    'acc.out'        = 'not logged in: claude /login'

    'stat.bigCtx'    = '{0}% at >{1} context'
    'stat.alwaysOn'  = '{0}% always-on context >{1}'
    'stat.subagents' = '{0}% subagent-heavy sessions'
    'stat.long'      = '{0}% sessions {1}h+'
    'stat.mcp'       = 'MCP: {0}'
    'stat.skills'    = 'skills: {0}'
    'stat.agents'    = 'subagents: {0}'

    'menu.toggle'    = 'Show / hide window'
    'menu.refresh'   = 'Refresh now'
    'menu.bigger'    = 'Larger'
    'menu.smaller'   = 'Smaller'
    'menu.config'    = 'Open config.json'
    'menu.language'  = 'Language'
    'menu.exit'      = 'Exit'

    'health.6'       = 'full of energy'
    'health.5'       = 'fine'
    'health.4'       = 'a bit tired'
    'health.3'       = 'tired'
    'health.2'       = 'exhausted'
    'health.1'       = 'barely alive'
    'health.0'       = 'out of strength'
    'hearts.left'    = '{0} · {1}% of the session limit left'

    'mood.sleep'     = 'sleeping'
    'mood.doze'      = 'dozing'
    'mood.idle'      = 'wandering'
    'mood.work'      = 'working'
    'mood.wait'      = 'waiting for you'
    'mood.dead'      = 'limit reached'

    'act.jump'       = 'jump'
    'act.look'       = 'looks around'
    'act.celebrate'  = 'celebrate'
    'act.skip'       = 'skip'
    'act.spin'       = 'spin'
    'act.peekaboo'   = 'peekaboo'
    'act.drop'       = 'drops in'
    'act.waddle'     = 'waddle'
    'act.peek'       = 'peek'
    'act.wink'       = 'wink'
    'act.boop'       = 'boop'
    'act.tap'        = 'tap dance'
    'act.sneeze'     = 'sneeze'
    'act.turn'       = 'turn around'
    'act.coin-hop'   = 'coin hop'
    'act.wave'       = 'wave'
    'act.stretch'    = 'stretch'
    'act.yawn'       = 'yawn'
    'act.stumble'    = 'stumble'
    'act.soul'       = 'soul leaves'
    'act.burrow'     = 'burrows in'
    'act.unburrow'   = 'climbs out of the burrow'
    'act.stir'       = 'peeks out of the burrow'

    'mm.head'        = 'Developer mode'
    'mm.auto'        = 'Auto (live data)'
    'mm.state'       = 'State'
    'mm.anim'        = 'Animation'
    'mm.sweat'       = 'Sweating near the limit'
    'mm.hearts'      = 'Hearts'
    'mm.byLimit'     = 'from the limit'
    'mm.drain'       = 'Play losing hearts'
    'mm.sky'         = 'Sky'
    'mm.byClock'     = 'by the clock'
    'mm.wxLive'      = 'live weather'
    'mm.demo'        = 'Show everything in turn'
    'tag.sweat'      = 'sweating near the limit'
    'tag.demo'       = 'demo {0}/{1} · {2}'

    'phase.dawn'     = 'dawn'
    'phase.day'      = 'day'
    'phase.dusk'     = 'dusk'
    'phase.night'    = 'night'

    'wx.clear'       = 'clear'
    'wx.mostlyClear' = 'mostly clear'
    'wx.partly'      = 'partly cloudy'
    'wx.overcast'    = 'overcast'
    'wx.fog'         = 'fog'
    'wx.drizzle'     = 'drizzle'
    'wx.iceDrizzle'  = 'freezing drizzle'
    'wx.rain'        = 'rain'
    'wx.iceRain'     = 'freezing rain'
    'wx.snow'        = 'snow'
    'wx.grains'      = 'snow grains'
    'wx.showers'     = 'rain showers'
    'wx.snowShowers' = 'snow showers'
    'wx.storm'       = 'thunderstorm'
    'wx.code'        = 'code {0}'
    'sky.wind'       = 'wind {0} m/s'
    'sky.noData'     = 'weather: no data'
    'sky.sun'        = 'sunrise {0} · sunset {1}'
  }

  ru = @{
    'err.noClaude'   = 'Не найден Claude Code (claude). Установи: irm https://claude.ai/install.ps1 | iex'

    'ui.details'     = 'Подробности'
    'ui.hide'        = 'Свернуть в трей'
    'ui.exit'        = 'Выход'
    'ui.week'        = 'НЕДЕЛЯ'
    'ui.fable'       = 'FABLE · НЕДЕЛЯ'
    'ui.sessions'    = 'СЕССИИ'
    'ui.openStatus'  = 'Открыть status.claude.com'
    'ui.day'         = 'ЗА 24 ЧАСА · ЭТОТ КОМПЬЮТЕР'
    'ui.week7'       = 'ЗА 7 ДНЕЙ'

    'span.d'         = '{0}д {1}ч'
    'span.h'         = '{0}ч {1:00}м'
    'span.m'         = '{0}м'

    'loading'        = 'загрузка...'
    'noData'         = 'нет данных'
    'error'          = 'ошибка'
    'stale'          = 'устарело'
    'reset.in'       = 'сброс через {0}'
    'reset.closed'   = 'окно закрыто'
    'period'         = '{0} запросов  ·  {1} сессий'

    'tray.noData'    = 'clawd-usage-winwidget: нет данных'
    'tray.session'   = '{0}% сессии'
    'tray.week'      = 'неделя {0}%'

    'sess.none'      = 'не запущено'
    'sess.busy'      = '{0} в работе'
    'sess.wait'      = '{0} ждут'
    'plural.session' = @('сессия', 'сессии', 'сессий')

    'st.loading'     = 'статус: загрузка...'
    'st.offline'     = 'статус: нет связи'
    'st.ok'          = 'Claude работает штатно'
    'st.maint'       = 'плановое обслуживание'
    'st.issues'      = 'есть проблемы'
    'comp.degraded_performance' = 'замедление'
    'comp.partial_outage'       = 'частичный сбой'
    'comp.major_outage'         = 'серьёзный сбой'
    'comp.under_maintenance'    = 'обслуживание'

    'ver.updating'   = 'обновляется...'
    'ver.available'  = 'есть {0}  ·  что нового?'
    'ver.latest'     = 'последняя'
    'chg.head'       = 'Что нового: {0} → {1}'
    'chg.loading'    = 'список изменений загружается...'
    'chg.more'       = '…и ещё {0}'
    'chg.empty'      = 'в CHANGELOG пока пусто'
    'chg.click'      = 'Клик — обновить'

    'acc.out'        = 'не залогинен: claude /login'

    'stat.bigCtx'    = '{0}% на контексте >{1}'
    'stat.alwaysOn'  = '{0}% постоянный контекст >{1}'
    'stat.subagents' = '{0}% сессии с сабагентами'
    'stat.long'      = '{0}% сессии от {1}ч'
    'stat.mcp'       = 'MCP: {0}'
    'stat.skills'    = 'скиллы: {0}'
    'stat.agents'    = 'сабагенты: {0}'

    'menu.toggle'    = 'Показать / скрыть окно'
    'menu.refresh'   = 'Обновить сейчас'
    'menu.bigger'    = 'Крупнее'
    'menu.smaller'   = 'Мельче'
    'menu.config'    = 'Открыть config.json'
    'menu.language'  = 'Язык'
    'menu.exit'      = 'Выход'

    'health.6'       = 'полон сил'
    'health.5'       = 'в норме'
    'health.4'       = 'подустал'
    'health.3'       = 'устал'
    'health.2'       = 'вымотан'
    'health.1'       = 'еле живой'
    'health.0'       = 'без сил'
    'hearts.left'    = '{0} · осталось {1}% лимита сессии'

    'mood.sleep'     = 'спит'
    'mood.doze'      = 'дремлет'
    'mood.idle'      = 'бродит'
    'mood.work'      = 'работает'
    'mood.wait'      = 'ждёт ответа'
    'mood.dead'      = 'лимит исчерпан'

    'act.jump'       = 'прыжок'
    'act.look'       = 'оглядывается'
    'act.celebrate'  = 'праздник'
    'act.skip'       = 'вприпрыжку'
    'act.spin'       = 'вертится'
    'act.peekaboo'   = 'ку-ку'
    'act.drop'       = 'падает сверху'
    'act.waddle'     = 'вперевалку'
    'act.peek'       = 'выглядывает'
    'act.wink'       = 'подмигивает'
    'act.boop'       = 'буп'
    'act.tap'        = 'топчется'
    'act.sneeze'     = 'чихает'
    'act.turn'       = 'поворачивается'
    'act.coin-hop'   = 'монетка'
    'act.wave'       = 'машет'
    'act.stretch'    = 'потягивается'
    'act.yawn'       = 'зевает'
    'act.stumble'    = 'спотыкается'
    'act.soul'       = 'дух выходит'
    'act.burrow'     = 'закапывается'
    'act.unburrow'   = 'вылезает из норы'
    'act.stir'       = 'выглядывает из норы'

    'mm.head'        = 'Режим разработчика'
    'mm.auto'        = 'Авто (по данным)'
    'mm.state'       = 'Состояние'
    'mm.anim'        = 'Анимация'
    'mm.sweat'       = 'Потеет у лимита'
    'mm.hearts'      = 'Сердца'
    'mm.byLimit'     = 'по лимиту'
    'mm.drain'       = 'Проиграть потерю сердец'
    'mm.sky'         = 'Небо'
    'mm.byClock'     = 'по часам'
    'mm.wxLive'      = 'погода по данным'
    'mm.demo'        = 'Показать все по очереди'
    'tag.sweat'      = 'потеет у лимита'
    'tag.demo'       = 'демо {0}/{1} · {2}'

    'phase.dawn'     = 'рассвет'
    'phase.day'      = 'день'
    'phase.dusk'     = 'закат'
    'phase.night'    = 'ночь'

    'wx.clear'       = 'ясно'
    'wx.mostlyClear' = 'малооблачно'
    'wx.partly'      = 'переменная облачность'
    'wx.overcast'    = 'пасмурно'
    'wx.fog'         = 'туман'
    'wx.drizzle'     = 'морось'
    'wx.iceDrizzle'  = 'ледяная морось'
    'wx.rain'        = 'дождь'
    'wx.iceRain'     = 'ледяной дождь'
    'wx.snow'        = 'снег'
    'wx.grains'      = 'снежная крупа'
    'wx.showers'     = 'ливень'
    'wx.snowShowers' = 'снегопад'
    'wx.storm'       = 'гроза'
    'wx.code'        = 'код {0}'
    'sky.wind'       = 'ветер {0} м/с'
    'sky.noData'     = 'погода: нет данных'
    'sky.sun'        = 'восход {0} · закат {1}'
  }
}

function Get-Lang {
    $l = [string]$script:Cfg.language
    if ($Strings.ContainsKey($l)) { return $l }
    return 'en'
}

function T([string]$key, $default = $key) {
    $s = $Strings[(Get-Lang)][$key]
    if ($null -eq $s) { $s = $Strings.en[$key] }
    if ($null -eq $s) { return $default }
    return $s
}

# "1 session" / "5 sessions"; Russian has three plural forms.
function Format-Count([int]$n, [string]$key) {
    $f = T "plural.$key"
    if ($f.Count -eq 2) { return "$n $(if ($n -eq 1) { $f[0] } else { $f[1] })" }
    $d = $n % 10; $h = $n % 100
    if ($d -eq 1 -and $h -ne 11) { return "$n $($f[0])" }
    if ($d -ge 2 -and $d -le 4 -and ($h -lt 12 -or $h -gt 14)) { return "$n $($f[1])" }
    return "$n $($f[2])"
}
