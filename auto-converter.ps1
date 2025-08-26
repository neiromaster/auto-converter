param(
    [string]$EnvFile = ".env"
)

# === Загрузка .env ===
if (-not (Test-Path $EnvFile)) {
    Write-Error "❌ Файл конфигурации не найден: $EnvFile"
    exit 1
}

$env:PS_ENV_LOADED = "true"

Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and $line[0] -ne '#' -and $line -match '^\s*([^=]+)=(.*)') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim().Replace('"', '\"')
        $value = [System.Environment]::ExpandEnvironmentVariables($value)
        Set-Variable -Name $key -Value $value -Scope Script
    }
}

# === Преобразование типов и валидация ===
try {
    $MinFileSizeMB = [int]$MIN_FILE_SIZE_MB
    $StabilizationCheckIntervalSec = [int]$STABILIZATION_CHECK_INTERVAL_SEC
    $StabilizationTimeoutSec = [int]$STABILIZATION_TIMEOUT_SEC
    $StabilizationToleranceBytes = [int]$STABILIZATION_TOLERANCE_BYTES
    $TelegramEnabled = [bool]::Parse($TELEGRAM_ENABLED.ToLower())
    $UseFileSizeStabilization = [bool]::Parse($USE_FILE_SIZE_STABILIZATION.ToLower())
}
catch {
    Write-Error "❌ Ошибка парсинга настроек: $_"
    exit 1
}

$SourceFolder = $SOURCE_FOLDER
$TargetFolder = $TARGET_FOLDER
$TempFolder = $TEMP_FOLDER
$Prefix = $PREFIX
$IgnorePrefix = $IGNORE_PREFIX
$FFmpegPath = $FFMPEG_PATH
$VideoExtensions = $VIDEO_EXTENSIONS -split ',' | ForEach-Object { $_.Trim() }
$TelegramBotToken = $TELEGRAM_BOT_TOKEN
$TelegramChannelId = $TELEGRAM_CHANNEL_ID

# === Проверка путей ===
foreach ($path in $SourceFolder, $TargetFolder, $TempFolder) {
    if (-not (Test-Path $path)) {
        Write-Error "❌ Путь не существует: $path"
        exit 1
    }
}

# Проверка FFmpeg
if (-not (Test-Path $FFmpegPath)) {
    Write-Error "❌ FFmpeg не найден: $FFmpegPath"
    exit 1
}

. .\includes\Write-Log.ps1

. .\includes\Check-ForUpdates.ps1

. .\includes\Send-TelegramMessage.ps1

. .\includes\Test-FileSizeStable.ps1


# === Функция: определение декодера ===
function Get-FfmpegConversionStrategy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LocalInputFile
    )

    $ffmpegInfo = & ffmpeg -i $LocalInputFile 2>&1

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
        Write-Log "🛠  Кодек '$($codec)' определен."
    }
    else {
        Write-Log "🛠  Будет использован программный декодер."
    }

    return [PSCustomObject]@{ 
        DecoderCommand = $decoderCommand
        VideoCodec     = $codec
    }
}


# === Конвертация с прогрессом и CUDA ===
function Convert-VideoWithProgress {
    param([string]$InputFile, [string]$OutputFile, [string]$DecoderCommand = $null)

    $Arguments = @(
        "-hwaccel", "cuda",
        "-hwaccel_output_format", "cuda"
    )

    if ($DecoderCommand) {
        $Arguments += $DecoderCommand.Split(" ")
    }

    $Arguments += @(
        "-i", "`"$InputFile`"",
        "-map", "0:v:0", "-map", "0:a:0"
        "-vf", "`"scale_cuda=format=nv12`"",
        "-c:v", "h264_nvenc",
        "-preset", "p5",
        "-rc", "constqp",
        "-qp", "32",
        "-c:a", "aac",
        "-b:a", "128k",
        "-sn",
        "-movflags", "+faststart",
        "-f", "matroska",
        "-y",
        "`"$OutputFile`""
    )

    Write-Log "🚀 FFmpeg: $($Arguments -join ' ')"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FFmpegPath
    $psi.Arguments = $Arguments -join " "
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null

    $TotalDuration = $null
    $StartTime = Get-Date
    $Speed = 0

    while (-not $proc.StandardError.EndOfStream) {
        $line = $proc.StandardError.ReadLine()
        if ($line -match "Duration:\s*(\d{2}:\d{2}:\d{2}\.\d{2})") {
            $TotalDuration = [timespan]::Parse($matches[1])
        }
        if ($line -match "time=(\d{2}:\d{2}:\d{2}\.\d{2})") {
            $CurrentTime = [timespan]::Parse($matches[1])
            if ($TotalDuration.TotalSeconds -gt 0) {
                $Percent = [Math]::Min(99.9, ($CurrentTime.TotalSeconds / $TotalDuration.TotalSeconds) * 100)
                $Elapsed = (Get-Date) - $StartTime
                if ($Elapsed.TotalSeconds -gt 0) {
                    $Speed = $CurrentTime.TotalSeconds / $Elapsed.TotalSeconds
                }
                $Remaining = [TimeSpan]::FromSeconds(($TotalDuration.TotalSeconds - $CurrentTime.TotalSeconds) / $Speed)
                Write-Progress -Activity "Конвертируем: $(Split-Path $InputFile -Leaf)" `
                    -Status ("{0:F1}% | {1:F2}x | осталось {2:mm\:ss}" -f $Percent, $Speed, $Remaining) `
                    -PercentComplete $Percent
            }
        }
    }

    $proc.WaitForExit()
    Write-Progress -Activity "Конвертация" -Completed

    return $proc.ExitCode -eq 0
}

# --- Проверка обновления ---
Check-ForUpdates

# === Основной обработчик события ===
$Action = {
    $FilePath = $Event.SourceEventArgs.FullPath
    $FileName = $Event.SourceEventArgs.Name
    $Extension = [IO.Path]::GetExtension($FileName).ToLower()

    Write-Log "📁 Обнаружен файл: $FileName"

    if ($VideoExtensions -notcontains $Extension) {
        Write-Log "❌ Не видео: $Extension"
        return
    }

    if ($FileName -like "$IgnorePrefix*") {
        Write-Log "🚫 Игнор: префикс $IgnorePrefix"
        return
    }

    # Ожидание завершения записи
    if ($UseFileSizeStabilization) {
        Write-Log "⏳ Ожидание стабилизации: $FileName"
        if (-not (Test-FileSizeStable -Path $FilePath -StabilizationTimeoutSec $StabilizationTimeoutSec -StabilizationCheckIntervalSec $StabilizationCheckIntervalSec)) {
            Write-Log "<b>⚠ Ошибка</b>`nФайл не стабилизировался: <code>$FileName</code>"
            return
        }
    }

    $FileSizeMB = (Get-Item -LiteralPath $FilePath).Length / 1MB

    $msg = "
🎬 <b>Видео скачано</b>

📁 <code>$FileName</code>
📦 $("{0:F1}" -f $FileSizeMB) МБ
⏱ $(Get-Date -Format 'HH:mm:ss')
                "
    if (-not (Send-TelegramMessage -Message $msg.Trim() -IsTelegramEnabled $TelegramEnabled -BotToken $TelegramBotToken -ChannelId $TelegramChannelId)) {
        Write-Log "⚠ Не удалось отправить сообщение в Telegram о скачивании файла: $FileName"
    }
                
    if ($FileSizeMB -lt $MinFileSizeMB) {
        Write-Log "📉 Маленький файл ($("{0:F1}" -f $FileSizeMB) МБ): $FileName"
        return
    }

    $strategy = Get-FfmpegConversionStrategy -LocalInputFile $FilePath

    if (-not $strategy) {
        Write-Log "❌ ОШИБКА: Не удалось найти видеопоток в файле."
        return
    }

    $BaseName = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $OutputFileName = "$Prefix$BaseName.mkv"
    $TempOutput = Join-Path $TempFolder $OutputFileName
    $FinalOutput = Join-Path $TargetFolder $OutputFileName

    try {
        if (Convert-VideoWithProgress -InputFile $FilePath -OutputFile $TempOutput -DecoderCommand $strategy.DecoderCommand) {
            if (Test-Path -LiteralPath $TempOutput) {
                if (Test-Path -LiteralPath $FinalOutput) { Remove-Item -LiteralPath $FinalOutput -Force }
                Move-Item -LiteralPath $TempOutput $FinalOutput -Force
                $FinalSizeMB = (Get-Item -LiteralPath $FinalOutput).Length / 1MB
                Write-Log "✅✅✅ Готово: $OutputFileName ($("{0:F1}" -f $FinalSizeMB) МБ)"

                $msg = "
🎬 <b>Видео обработано</b>

📁 <code>$OutputFileName</code>
📦 $("{0:F1}" -f $FinalSizeMB) МБ
⏱ $(Get-Date -Format 'HH:mm:ss')
                "
                if (-not (Send-TelegramMessage -Message $msg.Trim() -IsTelegramEnabled $TelegramEnabled -BotToken $TelegramBotToken -ChannelId $TelegramChannelId)) {
                    Write-Log "⚠ Не удалось отправить сообщение в Telegram об обработке файла: $OutputFileName"
                }
            }
        }
        else {
            Write-Log "❌❌❌ Ошибка FFmpeg: $OutputFileName"
        }
    }
    catch {
        Write-Log "❌❌❌ Ошибка: $($_.Exception.Message)"
    }
}


# === Запуск мониторинга ===
Write-Log "✅ Мониторинг запущен: $SourceFolder"
Write-Log "Нажмите Ctrl+C для остановки."

$Watcher = New-Object IO.FileSystemWatcher
$Watcher.Path = $SourceFolder
$Watcher.IncludeSubdirectories = $false
$Watcher.EnableRaisingEvents = $true
$Watcher.Filter = "*.*"

$null = Register-ObjectEvent -InputObject $Watcher -EventName Created -Action $Action

try {
    while ($true) { Start-Sleep -Seconds 1 }
}
finally {
    if (Get-EventSubscriber -SourceIdentifier "FileCreated" -ErrorAction SilentlyContinue) {
        Unregister-Event -SourceIdentifier "FileCreated"
    }
    $Watcher.Dispose()
    Write-Log "🛑 Мониторинг остановлен."
}

