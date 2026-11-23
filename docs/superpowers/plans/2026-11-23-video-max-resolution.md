# Масштабирование видео до max_resolution — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Видео с длинной стороной больше `settings.max_resolution` уменьшается до этого порога (пропорционально, чётные размеры), QP выносится в конфиг.

**Architecture:** Размеры видео парсятся из вывода `ffmpeg -i` (который и так вызывается для определения декодера) новой чистой функцией `Get-VideoDimensions`; целевые размеры считает чистая функция `Get-ScaledDimensions`; `Convert-VideoWithProgress` получает `ScaleWidth/ScaleHeight/QP` параметрами и строит `-vf scale_cuda=w=W:h=H:format=nv12`. Новые включения подключаются dot-source'ом (builder.ps1 встраивает их автоматически — правок сборки не нужно).

**Tech Stack:** PowerShell 5.1+, ffmpeg (CUDA/NVENC), powershell-yaml. Тестов в репо нет — проверка через временные PowerShell-снипеты и синтетические видео, генерируемые самим ffmpeg (testsrc2 + sine).

**Спека:** `docs/superpowers/specs/2026-11-23-video-max-resolution-design.md`

**Отклонения от спеки (сознательные):**
- `Get-VideoDimensions` и `Get-ScaledDimensions` — отдельные файлы в `includes/` (в репо принят паттерн «одна функция — один файл», и это даёт юнит-тестирование чистых функций; спека описывала их внутри других файлов).
- В `Convert-VideoWithProgress` добавлен guard `[System.Console]::IsInputRedirected` перед `KeyAvailable`: при перенаправленном stdin (запуск как службы, из CI, из неинтерактивной консоли) `KeyAvailable` бросает исключение, которое ломало бы конвертацию на первом же шаге цикла. Без guard невозможно прогнать интеграционный тест. На интерактивный сценарий (Esc) не влияет.

**Контекст для исполнителя:**
- Все команды PowerShell выполнять из `E:\projects\converters` (включения используют относительные пути `.\includes\...`).
- ffmpeg: `D:/scoop/shims/ffmpeg.exe` (из config.yaml).
- `Write-Log` при незаданной `$LogFile` пишет только в консоль — в тестах безопасен.
- В коммитах только файлы фичи; временные тесты — инлайн-команды, не файлы.

---

### Task 1: `Get-VideoDimensions` — парсер размеров из вывода ffmpeg

**Files:**
- Create: `includes/Get-VideoDimensions.ps1`

- [ ] **Step 1: Падающий тест**

Выполнить (PowerShell):

```powershell
& {
    $ErrorActionPreference = 'Stop'
    Set-Location E:\projects\converters
    . .\includes\Get-VideoDimensions.ps1

    $landscape = Get-VideoDimensions -FfmpegOutput @(
        'Stream #0:0(und): Video: h264 (High) (avc1 / 0x31637661), yuv420p(tv, bt709), 1920x1080 [SAR 1:1 DAR 16:9], 2501 kb/s, 23.98 fps'
        'Stream #0:1(und): Audio: aac (LC), 48000 Hz, stereo'
    )
    if ("$($landscape.Width)x$($landscape.Height)" -ne '1920x1080') { throw "FAIL landscape: $($landscape.Width)x$($landscape.Height)" }

    $portrait = Get-VideoDimensions -FfmpegOutput @(
        'Stream #0:0(und): Video: hevc (Main 10), yuv420p10le(tv), 1080x1920 [SAR 1:1 DAR 9:16], 5170 kb/s, 30 fps'
    )
    if ("$($portrait.Width)x$($portrait.Height)" -ne '1080x1920') { throw "FAIL portrait: $($portrait.Width)x$($portrait.Height)" }

    $noDims = Get-VideoDimensions -FfmpegOutput @('Input #0, mov,mp4:', '  Duration: 00:00:02.00')
    if ($null -ne $noDims) { throw "FAIL noDims: $noDims" }

    Write-Host 'PASS'
}
```

Ожидание: ошибка `The term 'Get-VideoDimensions' is not recognized` (файла ещё нет) — тест падает, как и задумано.

- [ ] **Step 2: Минимальная реализация**

Создать `includes/Get-VideoDimensions.ps1`:

```powershell
# === Функция: определение размеров видео из вывода ffmpeg -i ===
function Get-VideoDimensions {
    param(
        [Parameter(Mandatory = $true)]
        $FfmpegOutput
    )

    $videoStreamLine = $FfmpegOutput | Select-String -Pattern "Stream #\d+:\d+.*: Video:" | Select-Object -First 1

    if (-not $videoStreamLine) {
        return $null
    }

    if ("$videoStreamLine" -match '(\d{2,5})x(\d{2,5})') {
        return @{
            Width  = [int]$matches[1]
            Height = [int]$matches[2]
        }
    }

    return $null
}
```

Примечание: первый матч `\d{2,5}x\d{2,5}` в строке видеопотока — всегда разрешение (`0x31637661` не матчится: до `x` одна цифра; SAR/DAR идут после разрешения в формате `1:1`/`16:9`).

- [ ] **Step 3: Тест проходит**

Повторить команду из Step 1. Ожидание: `PASS`.

- [ ] **Step 4: Commit**

```bash
git add includes/Get-VideoDimensions.ps1
git commit -m "feat(auto-converter): add Get-VideoDimensions parser for ffmpeg output"
```

---

### Task 2: `Get-ScaledDimensions` — вычисление целевых размеров

**Files:**
- Create: `includes/Get-ScaledDimensions.ps1`

- [ ] **Step 1: Падающий тест**

```powershell
& {
    $ErrorActionPreference = 'Stop'
    Set-Location E:\projects\converters
    . .\includes\Get-ScaledDimensions.ps1

    function Assert-Scale($w, $h, $max, $ew, $eh) {
        $r = Get-ScaledDimensions -Width $w -Height $h -MaxResolution $max
        if ($r.ScaleWidth -ne $ew -or $r.ScaleHeight -ne $eh) { throw "FAIL ($w,$h,max=$max): $($r.ScaleWidth)x$($r.ScaleHeight), ожидалось ${ew}x${eh}" }
    }

    Assert-Scale 1920 1080 1280 1280 720    # ландшафт 1080p
    Assert-Scale 1080 1920 1280 720 1280    # вертикальное
    Assert-Scale 3840 2160 1280 1280 720    # 4K
    Assert-Scale 1280 720 1280 0 0          # порог не превышен
    Assert-Scale 1920 1080 0 0 0            # max_resolution=0 — выключено
    Assert-Scale 2560 1440 720 720 404      # нечётный расчёт → чётное (Math.Round(202.5)=202)

    Write-Host 'PASS'
}
```

Ожидание: ошибка `The term 'Get-ScaledDimensions' is not recognized`.

- [ ] **Step 2: Минимальная реализация**

Создать `includes/Get-ScaledDimensions.ps1`:

```powershell
# === Функция: вычисление размеров для масштабирования по длинной стороне ===
function Get-ScaledDimensions {
    param(
        [int]$Width = 0,
        [int]$Height = 0,
        [Parameter(Mandatory = $true)]
        [int]$MaxResolution
    )

    $result = @{
        ScaleWidth  = 0
        ScaleHeight = 0
    }

    if ($MaxResolution -le 0) {
        return $result
    }

    $longSide = [Math]::Max($Width, $Height)
    if ($longSide -le $MaxResolution) {
        return $result
    }

    $ratio = $MaxResolution / $longSide
    $result.ScaleWidth = [int][Math]::Round($Width * $ratio / 2) * 2
    $result.ScaleHeight = [int][Math]::Round($Height * $ratio / 2) * 2

    return $result
}
```

Примечания: параметры `$Width`/`$Height` НЕ Mandatory — при `$null` из нераспарсенных размеров `[int]$null` даст 0 и вернётся «без масштабирования» (обязательный параметр с `$null` вызвал бы интерактивный prompt в watcher'е). Округление до чётного через `Round(v/2)*2`.

- [ ] **Step 3: Тест проходит**

Повторить команду из Step 1. Ожидание: `PASS`.

- [ ] **Step 4: Commit**

```bash
git add includes/Get-ScaledDimensions.ps1
git commit -m "feat(auto-converter): add Get-ScaledDimensions helper"
```

---

### Task 3: `Get-FfmpegConversionStrategy` возвращает декодер + размеры

**Files:**
- Modify: `includes/Get-FfmpegConversionStrategy.ps1` (полная замена содержимого)
- Create (тестовые данные): `%TEMP%\vfr-test\sample-1080p.mp4` (в git не попадает)

- [ ] **Step 1: Подготовка тестового видео и падающий тест**

```powershell
& {
    $ErrorActionPreference = 'Stop'
    New-Item -ItemType Directory -Force "$env:TEMP\vfr-test" | Out-Null
    & 'D:/scoop/shims/ffmpeg.exe' -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=1920x1080:rate=30:duration=2' -f lavfi -i 'sine=frequency=1000:duration=2' -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest -y "$env:TEMP\vfr-test\sample-1080p.mp4"
    if ($LASTEXITCODE -ne 0) { throw 'ffmpeg sample generation failed' }

    Set-Location E:\projects\converters
    . .\includes\Get-FfmpegConversionStrategy.ps1
    $s = Get-FfmpegConversionStrategy -LocalInputFile "$env:TEMP\vfr-test\sample-1080p.mp4" -FFmpegPath 'D:/scoop/shims/ffmpeg.exe'
    if ($s.DecoderCommand -ne '-c:v h264_cuvid' -or $s.Width -ne 1920 -or $s.Height -ne 1080) { throw "FAIL: '$($s.DecoderCommand)' $($s.Width)x$($s.Height)" }
    Write-Host 'PASS'
}
```

Ожидание падения: сейчас функция возвращает строку `'-c:v h264_cuvid'`, у строки `.Width` → `$null` → `throw "FAIL: ..."`.

- [ ] **Step 2: Реализация — полная замена `includes/Get-FfmpegConversionStrategy.ps1`**

```powershell
. .\includes\Write-Log.ps1
. .\includes\Get-VideoDimensions.ps1

# === Функция: определение декодера и разрешения ===
function Get-FfmpegConversionStrategy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LocalInputFile,
        [string]$FFmpegPath = "ffmpeg"
    )

    $ffmpegInfo = & $FFmpegPath -i $LocalInputFile 2>&1

    $videoStreamLine = $ffmpegInfo | Select-String -Pattern "Stream #\d+:\d+.*: Video:" | Select-Object -First 1

    if (-not $videoStreamLine) {
        return $null
    }

    $codec = ""
    $decoderCommand = ""

    if ($videoStreamLine -match 'hevc') {
        $codec = "hevc"
    }
    elseif ($videoStreamLine -match 'h264') {
        $codec = "h264"
    }

    if ($codec) {
        $decoderCommand = "-c:v $($codec)_cuvid"
        Write-Log "🛠  Кодек '$($codec)' определен." -Pale
    }
    else {
        Write-Log "🛠  Будет использован программный декодер." -Pale
    }

    $Width = $null
    $Height = $null
    $dims = Get-VideoDimensions -FfmpegOutput $ffmpegInfo
    if ($dims) {
        $Width = $dims.Width
        $Height = $dims.Height
        Write-Log "📐 Разрешение: $($Width)x$($Height)" -Pale
    }
    else {
        Write-Log "⚠ Не удалось определить разрешение видео." -Pale
    }

    return [PSCustomObject]@{
        DecoderCommand = $decoderCommand
        Width = $Width
        Height = $Height
    }
}
```

- [ ] **Step 3: Тест проходит**

Повторить команду из Step 1 (генерация сэмпла повторно перезапишет файл — не страшно). Ожидание: `PASS`.

- [ ] **Step 4: Commit**

```bash
git add includes/Get-FfmpegConversionStrategy.ps1
git commit -m "refactor(auto-converter): strategy returns decoder and dimensions, uses FFmpegPath"
```

---

### Task 4: `Convert-VideoWithProgress` — параметры ScaleWidth/ScaleHeight/QP + guard для KeyAvailable

**Files:**
- Modify: `includes/Convert-VideoWithProgress.ps1`

- [ ] **Step 1: Изменить сигнатуру и построение аргументов**

Заменить начало функции (строки 4–36: `param(...)` и оба блока `$Arguments`) на:

```powershell
function Convert-VideoWithProgress {
    param(
        [string]$InputFile,
        [string]$OutputFile,
        [string]$DecoderCommand = $null,
        [int]$ScaleWidth = 0,
        [int]$ScaleHeight = 0,
        [int]$QP = 30,
        [string]$FFmpegPath
    )

    $Arguments = @(
        "-hwaccel", "cuda",
        "-hwaccel_output_format", "cuda"
    )

    if ($DecoderCommand) {
        $Arguments += $DecoderCommand.Split(" ")
    }

    if ($ScaleWidth -gt 0 -and $ScaleHeight -gt 0) {
        $scaleFilter = "scale_cuda=w=${ScaleWidth}:h=${ScaleHeight}:format=nv12"
    }
    else {
        $scaleFilter = "scale_cuda=format=nv12"
    }

    $Arguments += @(
        "-i", "`"$InputFile`"",
        "-map", "0:v:0", "-map", "0:a:0",
        "-vf", "`"$scaleFilter`"",
        "-c:v", "h264_nvenc",
        "-preset", "p5",
        "-rc", "constqp",
        "-qp", "$QP",
        "-c:a", "aac",
        "-b:a", "128k",
        "-sn",
        "-movflags", "+faststart",
        "-f", "matroska",
        "-y",
        "`"$OutputFile`""
    )
```

(Остальное тело функции без изменений; старые строки `-qp`, `"32",` и `"-vf", "`"scale_cuda=format=nv12`"` из блока удалены — теперь значения приходят из переменных.)

Важно: в строке фильтра обязательно `${ScaleWidth}`/`${ScaleHeight}` с фигурными скобками — без них PowerShell попробует разобрать `$ScaleWidth:h` как drive-qualified переменную.

- [ ] **Step 2: Guard для KeyAvailable**

Заменить строку 63:

```powershell
            if ([System.Console]::KeyAvailable) {
```

на:

```powershell
            if (-not [System.Console]::IsInputRedirected -and [System.Console]::KeyAvailable) {
```

- [ ] **Step 3: Проверка синтаксиса**

```powershell
& {
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile('E:\projects\converters\includes\Convert-VideoWithProgress.ps1', [ref]$null, [ref]$errs) | Out-Null
    if ($errs) { throw ($errs | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }) -join "`n" }
    Write-Host 'PASS'
}
```

Ожидание: `PASS`.

- [ ] **Step 4: Commit**

```bash
git add includes/Convert-VideoWithProgress.ps1
git commit -m "feat(auto-converter): scale and qp parameters in Convert-VideoWithProgress"
```

---

### Task 5: Связывание в `auto-converter.ps1` + ключи config.yaml

**Files:**
- Modify: `auto-converter.ps1` (3 места: dot-source'ы, чтение конфига, call site)
- Modify: `config.yaml`

- [ ] **Step 1: Dot-source новых включений**

После строки 124 `. .\includes\Get-FfmpegConversionStrategy.ps1` вставить:

```powershell

. .\includes\Get-VideoDimensions.ps1

. .\includes\Get-ScaledDimensions.ps1
```

(builder.ps1 встраивает их автоматически — проверка сборки в Task 7.)

- [ ] **Step 2: Чтение новых ключей конфига**

В блоке `try` (строки 71–80), после строки `$MinFileSizeMB = [int]$config.settings.min_file_size_mb`, вставить:

```powershell
    $MaxResolution = 0
    if ($config.settings.ContainsKey('max_resolution')) { $MaxResolution = [int]$config.settings.max_resolution }
    $QP = 30
    if ($config.settings.ContainsKey('qp')) { $QP = [int]$config.settings.qp }
```

(идиом `ContainsKey` уже используется в скрипте на строке 93 для `prefix`).

- [ ] **Step 3: Call site — расчёт масштаба и передача параметров**

Заменить (строки 225–231):

```powershell
        $strategy = Get-FfmpegConversionStrategy -LocalInputFile $FilePath

        if ($null -eq $strategy) {
            Write-Log "❌ ОШИБКА: Не удалось найти видеопоток в файле."
            return
        }
```

на:

```powershell
        $strategy = Get-FfmpegConversionStrategy -LocalInputFile $FilePath -FFmpegPath $FFmpegPath

        if ($null -eq $strategy) {
            Write-Log "❌ ОШИБКА: Не удалось найти видеопоток в файле."
            return
        }

        $scale = Get-ScaledDimensions -Width $strategy.Width -Height $strategy.Height -MaxResolution $MaxResolution
        if ($scale.ScaleWidth -gt 0) {
            Write-Log "📐 Разрешение $($strategy.Width)x$($strategy.Height) → $($scale.ScaleWidth)x$($scale.ScaleHeight)"
        }
```

И заменить вызов (строка 238):

```powershell
            if (Convert-VideoWithProgress -InputFile $FilePath -OutputFile $TempOutput -DecoderCommand $strategy -FFmpegPath $FFmpegPath) {
```

на:

```powershell
            if (Convert-VideoWithProgress -InputFile $FilePath -OutputFile $TempOutput -DecoderCommand $strategy.DecoderCommand -ScaleWidth $scale.ScaleWidth -ScaleHeight $scale.ScaleHeight -QP $QP -FFmpegPath $FFmpegPath) {
```

- [ ] **Step 4: config.yaml — добавить ключи в секцию `settings`**

После строки `min_file_size_mb: 800` вставить:

```yaml
  max_resolution: 1280 # длинная сторона > этого значения → уменьшение до него; 0 — без изменения разрешения
  qp: 30 # качество h264_nvenc (constqp); меньше — лучше и тяжелее
```

- [ ] **Step 5: Проверка синтаксиса + YAML**

```powershell
& {
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile('E:\projects\converters\auto-converter.ps1', [ref]$null, [ref]$errs) | Out-Null
    if ($errs) { throw ($errs | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }) -join "`n" }
    Import-Module powershell-yaml
    $cfg = Get-Content -Raw E:\projects\converters\config.yaml | ConvertFrom-Yaml
    if ($cfg.settings.max_resolution -ne 1280 -or $cfg.settings.qp -ne 30) { throw "yaml: $($cfg.settings.max_resolution)/$($cfg.settings.qp)" }
    Write-Host 'PASS'
}
```

Ожидание: `PASS`.

- [ ] **Step 6: Commit**

```bash
git add auto-converter.ps1 config.yaml
git commit -m "feat(auto-converter): downscale video to max_resolution from config"
```

---

### Task 6: Интеграционный прогон (без коммита)

**Files:** только тестовые данные в `%TEMP%\vfr-test\`

- [ ] **Step 1: Полный прогон трёх сценариев через изменённые функции**

```powershell
& {
    $ErrorActionPreference = 'Stop'
    Set-Location E:\projects\converters
    $ff = 'D:/scoop/shims/ffmpeg.exe'

    . .\includes\Get-FfmpegConversionStrategy.ps1
    . .\includes\Convert-VideoWithProgress.ps1
    . .\includes\Get-ScaledDimensions.ps1
    . .\includes\Get-VideoDimensions.ps1

    # Захват лога Write-Log для проверки строки аргументов ffmpeg
    $global:Captured = @()
    function global:Write-Log { param([string]$Message, [switch]$Pale) $global:Captured += $Message }

    function New-Sample($size, $name) {
        & $ff -hide_banner -loglevel error -f lavfi -i "testsrc2=size=${size}:rate=30:duration=2" -f lavfi -i 'sine=frequency=1000:duration=2' -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest -y "$env:TEMP\vfr-test\$name"
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed for $name" }
    }
    New-Sample '1920x1080' 'sample-1080p.mp4'
    New-Sample '1080x1920' 'sample-portrait.mp4'
    New-Sample '1280x720'  'sample-720p.mp4'

    function Test-Case($sample, $expectedW, $expectedH, $expectScaleInVf) {
        $global:Captured = @()
        $s = Get-FfmpegConversionStrategy -LocalInputFile "$env:TEMP\vfr-test\$sample" -FFmpegPath $ff
        if ($s.Width -ne $expectedW -or $s.Height -ne $expectedH) { throw "$sample strategy: $($s.Width)x$($s.Height)" }
        $sc = Get-ScaledDimensions -Width $s.Width -Height $s.Height -MaxResolution 1280
        $out = "$env:TEMP\vfr-test\out-$sample"
        if (-not (Convert-VideoWithProgress -InputFile "$env:TEMP\vfr-test\$sample" -OutputFile $out -DecoderCommand $s.DecoderCommand -ScaleWidth $sc.ScaleWidth -ScaleHeight $sc.ScaleHeight -QP 30 -FFmpegPath $ff)) { throw "$sample conversion failed" }
        $d = Get-VideoDimensions -FfmpegOutput (& $ff -i $out 2>&1)
        $ew = if ($expectScaleInVf) { $sc.ScaleWidth } else { $s.Width }
        $eh = if ($expectScaleInVf) { $sc.ScaleHeight } else { $s.Height }
        if ("$($d.Width)x$($d.Height)" -ne "${ew}x${eh}") { throw "$sample out dims: $($d.Width)x$($d.Height), ожидалось ${ew}x${eh}" }
        $argsLine = ($global:Captured | Where-Object { $_ -like '*FFmpeg:*' } | Select-Object -First 1)
        if ($argsLine -notmatch '-qp 30') { throw "$sample qp: $argsLine" }
        if ($expectScaleInVf -and $argsLine -notmatch "scale_cuda=w=${ew}:h=${eh}:format=nv12") { throw "$sample vf: $argsLine" }
        if (-not $expectScaleInVf -and $argsLine -notmatch 'scale_cuda=format=nv12') { throw "$sample vf(no scale): $argsLine" }
        Write-Host "OK $sample -> ${ew}x${eh}"
    }

    Test-Case 'sample-1080p.mp4'   1920 1080 $true    # → 1280x720
    Test-Case 'sample-portrait.mp4' 1080 1920 $true   # → 720x1280
    Test-Case 'sample-720p.mp4'     1280 720 $false   # без масштабирования
    Write-Host 'PASS'
}
```

Ожидание: `OK sample-1080p.mp4 -> 1280x720`, `OK sample-portrait.mp4 -> 720x1280`, `OK sample-720p.mp4 -> 1280x720`, `PASS`. Прогресс-бар `Write-Progress` в неинтерактивной консоли безопасен; Esc-ветка отключена guard'ом из Task 4.

- [ ] **Step 2: Очистка тестовых данных**

```powershell
Remove-Item -Recurse -Force "$env:TEMP\vfr-test"
```

---

### Task 7: Документация + проверка сборки

**Files:**
- Modify: `README.md`
- Modify: `docs/README_ru.md`

- [ ] **Step 1: README.md — пример конфига**

В yaml-блоке (строки 50–55), после `min_file_size_mb: 800` вставить:

```yaml
  max_resolution: 1280 # long side > this value is downscaled to it; 0 disables resizing
  qp: 30 # h264_nvenc quality (constqp); lower = better quality, bigger files
```

- [ ] **Step 2: README.md — Features**

После пункта `- **FFmpeg Integration**: ...` (строка 27) вставить:

```markdown
- **Resolution Downscaling**: Videos whose long side exceeds `max_resolution` are proportionally downscaled to it (e.g., 1920x1080 → 1280x720, vertical 1080x1920 → 720x1280). Set `max_resolution: 0` to disable.
```

- [ ] **Step 3: docs/README_ru.md — пример конфига**

После строки `min_file_size_mb: 800` вставить:

```yaml
  max_resolution: 1280 # длинная сторона больше этого значения уменьшается до него; 0 — без изменения разрешения
  qp: 30 # качество h264_nvenc (constqp); меньше — лучше качество, больше файл
```

- [ ] **Step 4: docs/README_ru.md — Возможности**

После пункта `- **FFmpeg Integration**: ...` вставить:

```markdown
- **Уменьшение разрешения**: Видео, у которых длинная сторона больше `max_resolution`, пропорционально уменьшается до него (например, 1920x1080 → 1280x720, вертикальное 1080x1920 → 720x1280). Значение `0` отключает уменьшение.
```

- [ ] **Step 5: Проверка сборки builder.ps1**

```powershell
& {
    $ErrorActionPreference = 'Stop'
    Set-Location E:\projects\converters
    .\builder.ps1
    $dist = Get-Content -Raw dist\auto-converter.ps1
    foreach ($needle in 'function Get-VideoDimensions', 'function Get-ScaledDimensions', 'scale_cuda', '-qp', 'max_resolution') {
        if ($dist -notlike "*$needle*") { throw "dist missing: $needle" }
    }
    Write-Host 'PASS'
}
```

Ожидание: вывод builder'а со строками «Встраиваю: .../Get-VideoDimensions.ps1» и «.../Get-ScaledDimensions.ps1», затем `PASS`. Собранный `dist/auto-converter.ps1` не коммитится, если он не в git (проверить `git status` — файл `dist/` если закоммичен, оставить как есть: обновить коммитом `chore(dist): rebuild` только если dist уже отслеживается).

- [ ] **Step 6: Commit**

```bash
git add README.md docs/README_ru.md
git commit -m "docs: document max_resolution and qp settings"
```

---

## Self-review плана

1. **Покрытие спеки**: парсинг размеров (Task 1+3), чётные целевые размеры и правило «строго больше» (Task 2), вертикальные видео (Task 2, Task 6), ключи max_resolution (дефолт 0) и qp (дефолт 30) (Task 5), пример конфига 1280/30 (Task 5), FFmpegPath в стратегии (Task 3), масштабирование не ломает конвертацию при нераспознанных размерах (Task 2: Width/Height не mandatory, [int]$null=0; Task 5: лог только при ScaleWidth>0), qp в Convert-VideoWithProgress (Task 4), README (Task 7). Всё покрыто.
2. **Плейсхолдеров нет** — все шаги с полным кодом/командами.
3. **Типы согласованы**: `Get-ScaledDimensions` возвращает hashtable `ScaleWidth/ScaleHeight` — используется в Task 5 и Task 6 одинаково; `Get-FfmpegConversionStrategy` возвращает `DecoderCommand/Width/Height` — используется в Task 5, Task 6; имена файлов включений совпадают во всех dot-source'ах.
