# ------------------------------------------------------------------- sky ----
# Backdrop behind the mascot. Sky color follows the real sunrise and sunset,
# the sun and moon (in its real phase) travel an arc, stars twinkle at night.
# Weather from Open-Meteo (no key): clouds, drizzle, rain, showers, snow, fog,
# thunderstorm. Coordinates come from the config, or else once per run by IP.

$Inv = [System.Globalization.CultureInfo]::InvariantCulture

# WMO weather codes. rain/snow - how many drops or flakes at medium intensity;
# three codes in a group - light, moderate and heavy.
$WeatherKinds = @(
    @{ codes = @(0);          id = 'clear';       cover = 0.0 }
    @{ codes = @(1);          id = 'mostlyClear'; cover = 0.2 }
    @{ codes = @(2);          id = 'partly';      cover = 0.5 }
    @{ codes = @(3);          id = 'overcast';    cover = 0.85 }
    @{ codes = @(45, 48);     id = 'fog';         cover = 0.7;  fog = $true }
    @{ codes = @(51, 53, 55); id = 'drizzle';     cover = 0.8;  rain = 6 }
    @{ codes = @(56, 57);     id = 'iceDrizzle';  cover = 0.8;  rain = 6 }
    @{ codes = @(61, 63, 65); id = 'rain';        cover = 0.9;  rain = 12 }
    @{ codes = @(66, 67);     id = 'iceRain';     cover = 0.9;  rain = 12 }
    @{ codes = @(71, 73, 75); id = 'snow';        cover = 0.85; snow = 10 }
    @{ codes = @(77);         id = 'grains';      cover = 0.85; snow = 8 }
    @{ codes = @(80, 81, 82); id = 'showers';     cover = 0.85; rain = 16 }
    @{ codes = @(85, 86);     id = 'snowShowers'; cover = 0.9;  snow = 14 }
    @{ codes = @(95, 96, 99); id = 'storm';       cover = 1.0;  rain = 16; storm = $true }
)

function Get-WeatherKind([int]$code) {
    foreach ($k in $WeatherKinds) {
        $i = [array]::IndexOf($k.codes, $code)
        if ($i -lt 0) { continue }
        $mul = $(if ($k.codes.Count -eq 3) { @(0.6, 1.0, 1.35)[$i] } else { 1.0 })
        return @{
            name = T "wx.$($k.id)"; cover = $k.cover; fog = [bool]$k.fog; storm = [bool]$k.storm
            rain = [int][math]::Round([int]$k.rain * $mul); snow = [int][math]::Round([int]$k.snow * $mul)
        }
    }
    return @{ name = (T 'wx.code') -f $code; cover = 0.5; fog = $false; storm = $false; rain = 0; snow = 0 }
}

# ----- where and what weather -----

$script:Geo     = $null   # @{ lat; lon; city } from IP
$script:GeoTask = $null
$script:GeoTry  = [datetime]::MinValue
$script:Wx      = $null   # @{ code; temp; wind; sunrise; sunset; at }
$script:WxTask  = $null
$script:WxTry   = [datetime]::MinValue
$script:WxAlt   = $false  # Open-Meteo did not answer - use met.no

function New-WebClient {
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $wc.Headers['User-Agent'] = 'clawd-usage-winwidget'
    return $wc
}

function Get-WeatherPlace {
    $c = $script:Cfg
    if ("$($c.weatherLat)" -ne '' -and "$($c.weatherLon)" -ne '') {
        try { return @{ lat = [double]$c.weatherLat; lon = [double]$c.weatherLon; city = $null } } catch {}
    }
    return $script:Geo
}

function Start-WeatherProbe {
    if ($script:WxTask -and -not $script:WxTask.IsCompleted) { return }
    if ($script:GeoTask -and -not $script:GeoTask.IsCompleted) { return }
    $place = Get-WeatherPlace
    if (-not $place) {
        # No coordinates - first find the location by IP, ask for weather next tick.
        if (([datetime]::Now - $script:GeoTry).TotalMinutes -lt 10) { return }
        $script:GeoTry = Get-Date
        try { $script:GeoTask = (New-WebClient).DownloadStringTaskAsync("https://ipwho.is/?lang=$(Get-Lang)") }
        catch { $script:GeoTask = $null }
        return
    }
    $script:WxTry = Get-Date
    $lat = $place.lat.ToString($Inv); $lon = $place.lon.ToString($Inv)
    if ($script:WxAlt) {
        $url = 'https://api.met.no/weatherapi/locationforecast/2.0/compact?lat={0}&lon={1}' -f
               $place.lat.ToString('0.####', $Inv), $place.lon.ToString('0.####', $Inv)
    } else {
        $url = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon" +
               '&current=weather_code,temperature_2m,wind_speed_10m&daily=sunrise,sunset&timezone=auto&forecast_days=1'
    }
    try { $script:WxTask = (New-WebClient).DownloadStringTaskAsync($url) } catch { $script:WxTask = $null }
}

function Collect-WeatherProbe {
    if ($script:GeoTask -and $script:GeoTask.IsCompleted) {
        $t = $script:GeoTask
        $script:GeoTask = $null
        if ($t.Status -eq 'RanToCompletion') {
            try {
                $j = $t.Result | ConvertFrom-Json
                if ($j.success -ne $false -and $null -ne $j.latitude) {
                    $script:Geo   = @{ lat = [double]$j.latitude; lon = [double]$j.longitude; city = [string]$j.city }
                    $script:WxTry = [datetime]::MinValue   # have a location - weather right away
                }
            } catch {}
        }
    }
    if (-not $script:WxTask -or -not $script:WxTask.IsCompleted) { return }
    $t = $script:WxTask
    $script:WxTask = $null
    $alt = $script:WxAlt
    $j = $null
    if ($t.Status -eq 'RanToCompletion') { try { $j = $t.Result | ConvertFrom-Json } catch {} }
    if ($alt) {
        if ($j -and $j.properties.timeseries) { $script:Wx = ConvertFrom-MetNo $j; Update-SkyTip }
        return
    }
    if ($null -eq $j -or $null -eq $j.current) {
        # Open-Meteo is unreachable (sometimes blocked) - ask met.no from now on.
        $script:WxAlt = $true
        $script:WxTry = [datetime]::MinValue
        return
    }
    $wx = @{
        code = [int]$j.current.weather_code; temp = [double]$j.current.temperature_2m
        wind = [double]$j.current.wind_speed_10m; sunrise = $null; sunset = $null; at = Get-Date
    }
    # Local time (timezone=auto); drop the date, only the hour is needed.
    try {
        $wx.sunrise = [datetime]::ParseExact([string]$j.daily.sunrise[0], "yyyy-MM-dd'T'HH:mm", $Inv).TimeOfDay
        $wx.sunset  = [datetime]::ParseExact([string]$j.daily.sunset[0],  "yyyy-MM-dd'T'HH:mm", $Inv).TimeOfDay
    } catch {}
    $script:Wx = $wx
    Update-SkyTip
}

# met.no describes weather with a word: "lightrainshowers_day" -> WMO code.
function ConvertFrom-MetNo($j) {
    $d   = $j.properties.timeseries[0].data
    $sym = [string]$d.next_1_hours.summary.symbol_code -replace '_(day|night|polartwilight)$', ''
    $lvl = $(if ($sym -match '^light') { 0 } elseif ($sym -match '^heavy') { 2 } else { 1 })
    $shw = $sym -match 'showers'
    $code = $(switch -regex ($sym) {
        'thunder'      { 95; break }
        'snow'         { $(if ($shw) { @(85, 85, 86)[$lvl] } else { @(71, 73, 75)[$lvl] }); break }
        'sleet'        { $(if ($lvl -eq 2) { 67 } else { 66 }); break }
        'rain'         { $(if ($shw) { @(80, 81, 82)[$lvl] } else { @(61, 63, 65)[$lvl] }); break }
        '^fog'         { 45; break }
        '^cloudy'      { 3; break }
        '^partlycloudy' { 2; break }
        '^fair'        { 1; break }
        '^clearsky'    { 0; break }
        default        { 3 }
    })
    return @{
        code = [int]$code; temp = [double]$d.instant.details.air_temperature
        wind = 3.6 * [double]$d.instant.details.wind_speed   # m/s -> km/h, as in Open-Meteo
        sunrise = $null; sunset = $null; at = Get-Date
    }
}

# Sunrise and sunset from coordinates (NOAA formulas), local time, minutes from midnight.
function Get-SunCalc([double]$lat, [double]$lon) {
    $now = Get-Date
    $gm  = 2 * [math]::PI / 365 * ($now.DayOfYear - 0.5)
    $eq  = 229.18 * (0.000075 + 0.001868 * [math]::Cos($gm) - 0.032077 * [math]::Sin($gm) -
                     0.014615 * [math]::Cos(2 * $gm) - 0.040849 * [math]::Sin(2 * $gm))
    $dec = 0.006918 - 0.399912 * [math]::Cos($gm) + 0.070257 * [math]::Sin($gm) -
           0.006758 * [math]::Cos(2 * $gm) + 0.000907 * [math]::Sin(2 * $gm) -
           0.002697 * [math]::Cos(3 * $gm) + 0.00148 * [math]::Sin(3 * $gm)
    $la  = $lat * [math]::PI / 180
    $c   = [math]::Cos(90.833 * [math]::PI / 180) / ([math]::Cos($la) * [math]::Cos($dec)) -
           [math]::Tan($la) * [math]::Tan($dec)
    # Polar day or night - the sun never sets or never rises.
    $c   = [math]::Max(-0.999, [math]::Min(0.999, $c))
    $ha  = [math]::Acos($c) * 180 / [math]::PI
    $tz  = [System.TimeZoneInfo]::Local.GetUtcOffset($now).TotalMinutes
    return @{
        sr = ((720 - 4 * ($lon + $ha) - $eq + $tz) % 1440 + 1440) % 1440
        ss = ((720 - 4 * ($lon - $ha) - $eq + $tz) % 1440 + 1440) % 1440
    }
}

# Weather to draw: from developer mode or fresh (no older than 3 hours).
function Get-SkyWeather {
    $s = $script:Sky
    if ($null -ne $s.forceWx) { return @{ code = [int]$s.forceWx; wind = 12.0 } }
    $wx = $script:Wx
    if ($wx -and ((Get-Date) - $wx.at).TotalHours -lt 3) { return $wx }
    return $null
}

function Get-SunTimes {
    if ($script:Wx -and $script:Wx.sunrise -and $script:Wx.sunset) {
        return @{ sr = $script:Wx.sunrise.TotalMinutes; ss = $script:Wx.sunset.TotalMinutes }
    }
    $place = Get-WeatherPlace
    if ($place) { return Get-SunCalc $place.lat $place.lon }
    return @{ sr = 420.0; ss = 1140.0 }
}

function Update-SkyTip {
    $parts = @()
    $wx = Get-SkyWeather
    if ($null -ne $script:Sky.forceWx -or $script:Sky.force) {
        $what = @()
        if ($script:Sky.force)           { $what += T "phase.$($script:Sky.force)" }
        if ($null -ne $script:Sky.forceWx) { $what += (Get-WeatherKind $script:Sky.forceWx).name }
        $parts += "dev · $($what -join ', ')"
    } elseif ($wx) {
        $place = Get-WeatherPlace
        $temp  = [int][math]::Round($wx.temp)
        $line  = "$(if ($temp -gt 0) { '+' })$temp°, $((Get-WeatherKind $wx.code).name)"
        if ($place -and $place.city) { $line = "$($place.city) · $line" }
        $parts += $line
        $parts += (T 'sky.wind') -f [math]::Round($wx.wind / 3.6)
    } else {
        $parts += T 'sky.noData'
    }
    $st = Get-SunTimes
    $fmt = { param($m) [timespan]::FromMinutes($m).ToString('hh\:mm') }
    $parts += (T 'sky.sun') -f (& $fmt $st.sr), (& $fmt $st.ss)
    $UI.Sky.ToolTip = $parts -join "`n"
}
