# Гейт конвертации «размер ИЛИ разрешение» — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Файл конвертируется, если размер ≥ `min_file_size_mb` ИЛИ длинная сторона > `max_resolution`; пропуск — только когда оба условия ложны.

**Architecture:** Чистый предикат `Test-ConversionNeeded` в новом include (паттерн «функция = файл»); в `auto-converter.ps1` вызов стратегии и расчёт масштаба переезжают до гейта, гейт — одна строка через предикат. Спека: `docs/superpowers/specs/2026-11-25-conversion-gate-or-design.md`.

**Tech Stack:** PowerShell 5.1+/pwsh, powershell-yaml. Тесты — инлайн-снипеты через `pwsh.exe -NoProfile -File` (ВАЖНО: PowerShell-инструмент хоста сессии отравлен накопленными event-подписчиками и падает на любой команде — весь pwsh запускать только через Bash-инструмент свежими процессами). После каждого Edit проверять `git diff --stat` — Edit-инструмент перезаписывает LF→CRLF (см. память `edit-tool-crlf-churn`).

**Контекст:** ffmpeg `D:/scoop/shims/ffmpeg.exe`; тестовые данные только в `%TEMP%\gate-test` (в git не попадают); тестовые скрипты писать во временную папку `C:\Users\loris\AppData\Local\Temp\cc-gate\` инструментом Write и запускать через Bash. Коммиты без атрибуции/co-authored-by. НЕ пушить (пуш = публикация релиза, отдельно согласуется с пользователем).

---

### Task 1: Гейт «размер ИЛИ разрешение»

**Files:**
- Create: `includes/Test-ConversionNeeded.ps1`
- Modify: `auto-converter.ps1:127-136` (dot-source) и `auto-converter.ps1:227-243` (блок convert-video)
- Modify: `README.md`, `docs/README_ru.md`

- [ ] **Step 1: Падающий тест предиката**

Записать `C:\Users\loris\AppData\Local\Temp\cc-gate\test-predicate.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location E:\projects\converters
. .\includes\Test-ConversionNeeded.ps1

function Assert-Need($size, $min, $sw, $sh, $expected, $tag) {
    $r = Test-ConversionNeeded -FileSizeMB $size -MinFileSizeMB $min -ScaleWidth $sw -ScaleHeight $sh
    if ($r -ne $expected) { throw "FAIL $tag: got $r, expected $expected" }
}

Assert-Need 600 800 0 0 $false 'small+lowres'
Assert-Need 600 800 1280 720 $true 'small+hires'
Assert-Need 1000 800 0 0 $true 'big+lowres'
Assert-Need 1000 800 1280 720 $true 'big+hires'
Assert-Need 599.9 800 0 0 $false 'boundary-below'
Assert-Need 800 800 0 0 $true 'boundary-equal'
Assert-Need 600 800 $null $null $false 'null-scale-small'
Assert-Need 1000 800 $null $null $true 'null-scale-big'

Write-Host 'PASS-PREDICATE'
```

Выполнить: `pwsh.exe -NoProfile -File "C:\Users\loris\AppData\Local\Temp\cc-gate\test-predicate.ps1"` (создав папку).
Ожидание: ошибка «команда Test-ConversionNeeded не распознана»/dot-source несуществующего файла — красный шаг.

- [ ] **Step 2: Реализация**

Создать `includes/Test-ConversionNeeded.ps1` ровно с содержимым:

```powershell
# === Функция: нужен ли конверт (размер ИЛИ разрешение) ===
function Test-ConversionNeeded {
    param(
        [double]$FileSizeMB = 0,
        [int]$MinFileSizeMB = 0,
        [int]$ScaleWidth = 0,
        [int]$ScaleHeight = 0
    )

    if ($FileSizeMB -ge $MinFileSizeMB) {
        return $true
    }

    return ($ScaleWidth -gt 0 -and $ScaleHeight -gt 0)
}
```

Примечания: Scale-параметры НЕ Mandatory — `$null` коэрцится в 0 (безопасно в watcher-контексте, паттерн `Get-ScaledDimensions`); граница `≥` (800/800 → true) соответствует прежнему «пропуск если `<`».

- [ ] **Step 3: Тест проходит**

Повторить команду из Step 1. Ожидание: `PASS-PREDICATE`.

- [ ] **Step 4: Dot-source нового include**

В `auto-converter.ps1` после строки `. .\includes\Get-ScaledDimensions.ps1` вставить:

```powershell

. .\includes\Test-ConversionNeeded.ps1
```

- [ ] **Step 5: Перестройка блока convert-video**

Заменить в `auto-converter.ps1` (строки 227–243):

```powershell
    if ($EnabledModules['convert-video']) {
        if ($FileSizeMB -lt $MinFileSizeMB) {
            Write-Log "📉 Маленький файл ($('{0:F1}' -f $FileSizeMB) МБ): $FileName" -Pale
            return
        }

        $strategy = Get-FfmpegConversionStrategy -LocalInputFile $FilePath -FFmpegPath $FFmpegPath

        if ($null -eq $strategy) {
            Write-Log "❌ ОШИБКА: Не удалось найти видеопоток в файле."
            return
        }

        $scale = Get-ScaledDimensions -Width $strategy.Width -Height $strategy.Height -MaxResolution $MaxResolution
        if ($scale.ScaleWidth -gt 0 -and $scale.ScaleHeight -gt 0) {
            Write-Log "📐 Разрешение $($strategy.Width)x$($strategy.Height) → $($scale.ScaleWidth)x$($scale.ScaleHeight)"
        }
```

на:

```powershell
    if ($EnabledModules['convert-video']) {
        $strategy = Get-FfmpegConversionStrategy -LocalInputFile $FilePath -FFmpegPath $FFmpegPath

        if ($null -eq $strategy) {
            Write-Log "❌ ОШИБКА: Не удалось найти видеопоток в файле."
            return
        }

        $scale = Get-ScaledDimensions -Width $strategy.Width -Height $strategy.Height -MaxResolution $MaxResolution
        if ($scale.ScaleWidth -gt 0 -and $scale.ScaleHeight -gt 0) {
            Write-Log "📐 Разрешение $($strategy.Width)x$($strategy.Height) → $($scale.ScaleWidth)x$($scale.ScaleHeight)"
        }

        if (-not (Test-ConversionNeeded -FileSizeMB $FileSizeMB -MinFileSizeMB $MinFileSizeMB -ScaleWidth $scale.ScaleWidth -ScaleHeight $scale.ScaleHeight)) {
            Write-Log "📉 Пропуск: $('{0:F1}' -f $FileSizeMB) МБ, разрешение не выше $MaxResolution: $FileName" -Pale
            return
        }
```

(строки от `$BaseName = ...` и далее — без изменений).

- [ ] **Step 6: Парс + дифф-гигиена**

```bash
pwsh.exe -NoProfile -Command "& { $errs = $null; [System.Management.Automation.Language.Parser]::ParseFile('E:\projects\converters\auto-converter.ps1', [ref]$null, [ref]$errs) | Out-Null; if ($errs) { $errs | ForEach-Object { Write-Host "$($_.Extent.StartLineNumber): $($_.Message)" }; exit 1 }; Write-Host 'PARSE-OK' }"
cd /e/projects/converters && git diff --stat
```

Ожидание: `PARSE-OK`; дифф — только два файла, в auto-converter.ps1 ≤ ~20 строк (если сотни — CRLF-чурн: нормализовать LF через .NET ReadAllText/`-replace "\r\n","\n"`/WriteAllText `UTF8Encoding($false)` и перекоммитить).

- [ ] **Step 7: Коммит кода**

```bash
cd /e/projects/converters && git add includes/Test-ConversionNeeded.ps1 auto-converter.ps1 && git commit -m "feat(auto-converter): convert when size or resolution exceeds threshold"
```

- [ ] **Step 8: Интеграционный smoke**

Записать `C:\Users\loris\AppData\Local\Temp\cc-gate\smoke.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
Set-Location E:\projects\converters
$ff = 'D:/scoop/shims/ffmpeg.exe'
. .\includes\Get-FfmpegConversionStrategy.ps1
. .\includes\Convert-VideoWithProgress.ps1
. .\includes\Get-ScaledDimensions.ps1
. .\includes\Test-ConversionNeeded.ps1
. .\includes\Get-VideoDimensions.ps1

$dir = "$env:TEMP\gate-test"
New-Item -ItemType Directory -Force $dir | Out-Null
& $ff -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=1280x720:rate=30:duration=2' -f lavfi -i 'sine=frequency=1000:duration=2' -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest -y "$dir\small-720p.mp4"
& $ff -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=3840x2160:rate=30:duration=2' -f lavfi -i 'sine=frequency=1000:duration=2' -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest -y "$dir\small-4k.mp4"
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg sample failed' }

function Decide($path, $maxRes) {
    $sizeMB = (Get-Item -LiteralPath $path).Length / 1MB
    $s = Get-FfmpegConversionStrategy -LocalInputFile $path -FFmpegPath $ff
    if ($null -eq $s) { throw "no video stream: $path" }
    $sc = Get-ScaledDimensions -Width $s.Width -Height $s.Height -MaxResolution $maxRes
    [pscustomobject]@{ Need = (Test-ConversionNeeded -FileSizeMB $sizeMB -MinFileSizeMB 800 -ScaleWidth $sc.ScaleWidth -ScaleHeight $sc.ScaleHeight); Scale = "$($sc.ScaleWidth)x$($sc.ScaleHeight)" }
}

$skip = Decide "$dir\small-720p.mp4" 1280
if ($skip.Need) { throw "FAIL: small-720p должен быть пропущен" }
Write-Host "OK small-720p -> skip (scale $($skip.Scale))"

$go = Decide "$dir\small-4k.mp4" 1280
if (-not $go.Need) { throw "FAIL: small-4k должен конвертироваться" }
$out = "$dir\out-4k.mkv"
if (-not (Convert-VideoWithProgress -InputFile "$dir\small-4k.mp4" -OutputFile $out -DecoderCommand (Get-FfmpegConversionStrategy -LocalInputFile "$dir\small-4k.mp4" -FFmpegPath $ff).DecoderCommand -ScaleWidth $go.Scale.Split('x')[0] -ScaleHeight $go.Scale.Split('x')[1] -QP 30 -FFmpegPath $ff)) { throw 'conversion failed' }
$d = Get-VideoDimensions -FfmpegOutput (& $ff -i $out 2>&1)
if ("$($d.Width)x$($d.Height)" -ne '1280x720') { throw "out dims: $($d.Width)x$($d.Height)" }
Write-Host "OK small-4k -> converted 1280x720"

Write-Host 'PASS-SMOKE'
```

Выполнить через Bash: `pwsh.exe -NoProfile -File "C:\Users\loris\AppData\Local\Temp\cc-gate\smoke.ps1" 2>&1 | cat`.
Ожидание: `OK small-720p -> skip (scale 0x0)`, `OK small-4k -> converted 1280x720`, `PASS-SMOKE`.

- [ ] **Step 9: Сборка builder**

```bash
cd /e/projects/converters && pwsh.exe -NoProfile -Command "& { .\builder.ps1; \$dist = Get-Content -Raw .\dist\auto-converter.ps1; foreach (\$n in 'function Test-ConversionNeeded', 'Test-ConversionNeeded -FileSizeMB') { if (\$dist -notlike \"*\$n*\") { throw \"dist missing: \$n\" } }; Write-Host 'PASS-BUILD' }"
```

Ожидание: «Встраиваю: ...Test-ConversionNeeded.ps1» + `PASS-BUILD`. dist в .gitignore — не коммитить.

- [ ] **Step 10: Документация**

`README.md` — заменить пункт (после FFmpeg Integration):

```markdown
- **Resolution Downscaling**: Videos whose long side exceeds `max_resolution` are proportionally downscaled to it (e.g., 1920x1080 → 1280x720, vertical 1080x1920 → 720x1280). Set `max_resolution: 0` to disable.
```

на:

```markdown
- **Conversion Gate & Resolution Downscaling**: A video is converted when its size reaches `min_file_size_mb` OR its long side exceeds `max_resolution` — downscaled proportionally to that threshold (e.g., 1920x1080 → 1280x720, vertical 1080x1920 → 720x1280). Small low-resolution files are skipped. Set `max_resolution: 0` to gate by size only.
```

`docs/README_ru.md` — заменить пункт:

```markdown
- **Уменьшение разрешения**: Видео, у которых длинная сторона больше `max_resolution`, пропорционально уменьшаются до него (например, 1920x1080 → 1280x720, вертикальное 1080x1920 → 720x1280). Значение `0` отключает уменьшение.
```

на:

```markdown
- **Условие конвертации и уменьшение разрешения**: Видео конвертируется, если его размер достиг `min_file_size_mb` ИЛИ длинная сторона больше `max_resolution` — в последнем случае пропорционально уменьшается до порога (например, 1920x1080 → 1280x720, вертикальное 1080x1920 → 720x1280). Маленькие файлы с низким разрешением пропускаются. Значение `0` включает гейт только по размеру.
```

После правок: `git diff --stat` (если сотни строк — CRLF-чурн, нормализовать LF), затем коммит:

```bash
cd /e/projects/converters && git add README.md docs/README_ru.md && git commit -m "docs: describe OR-based conversion gate"
```

- [ ] **Step 11: Очистка**

```bash
rm -rf "C:\Users\loris\AppData\Local\Temp\cc-gate" "$TEMP/gate-test" 2>/dev/null; echo cleaned
```

---

## Self-review плана

1. **Спека → план**: предикат с сигнатурой из спеки (Step 1–3), перенос стратегии/масштаба до гейта + лог пропуска с обеими причинами (Step 5), `$null`-безопасность (Step 1 cases 7–8), README en/ru (Step 10). Всё покрыто.
2. **Плейсхолдеров нет** — все шаги с полным кодом/командами.
3. **Типы согласованы**: `Test-ConversionNeeded(-FileSizeMB, -MinFileSizeMB, -ScaleWidth, -ScaleHeight)` одинаково в тесте, реализации и вызове; `$scale.ScaleWidth/$scale.ScaleHeight` из `Get-ScaledDimensions` совпадают с потреблением.
