. .\includes\Check-ForUpdates.ps1

# --- Проверка обновления ---
if ($AutoUpdateEnabled) {
    Check-ForUpdates
}

# --- Проверка и установка модуля powershell-yaml ---
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host "Модуль 'powershell-yaml' не найден. Попытка установки..." -ForegroundColor Yellow
    try {
        Install-Module -Name powershell-yaml -Scope CurrentUser -Force -Confirm:$false
        Write-Host "Модуль 'powershell-yaml' успешно установлен." -ForegroundColor Green
    }
    catch {
        Write-Error "❌ Не удалось установить модуль 'powershell-yaml'. Возможно, требуются права администратора или отсутствует подключение к PowerShell Gallery. Ошибка: $($_.Exception.Message)"
        exit 1
    }
}

Import-Module powershell-yaml

$EnvFile = ".env"

# === Загрузка .env (только для секретов Telegram) ===
if (-not (Test-Path $EnvFile)) {
    Write-Error "❌ Файл .env не найден: $EnvFile"
    exit 1
}

$telegramSecrets = @{}
Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and $line[0] -ne '#' -and $line -match '^\s*([^=]+)=(.*)') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim().Replace('"', '"')
        $telegramSecrets[$key] = $value
    }
}

# === Загрузка config.yaml ===
$ConfigFile = "config.yaml"
if (-not (Test-Path $ConfigFile)) {
    Write-Error "❌ Файл конфигурации не найден: $ConfigFile"
    exit 1
}

try {
    $config = Get-Content $ConfigFile | ConvertFrom-Yaml
}
catch {
    Write-Error "❌ Ошибка парсинга config.yaml: $($_.Exception.Message)"
    exit 1
}

# === Преобразование типов и валидация ===
try {
    $MinFileSizeMB = [int]$config.settings.min_file_size_mb
    $StabilizationCheckIntervalSec = [int]$config.stabilization_strategy.stabilization_check_interval_sec
    $StabilizationTimeoutSec = [int]$config.stabilization_strategy.stabilization_timeout_sec
    $TelegramEnabled = [bool]::Parse($config.settings.telegram_enabled)
    $UseFileSizeStabilization = [bool]::Parse($config.stabilization_strategy.use_file_size_stabilization)
    $AutoUpdateEnabled = [bool]::Parse($config.settings.auto_update_enabled)
}
catch {
    Write-Error "❌ Ошибка парсинга настроек: $_"
    exit 1
}

$SourceFolder = [System.Environment]::ExpandEnvironmentVariables($config.paths.source_folder)
$TargetFolder = [System.Environment]::ExpandEnvironmentVariables($config.paths.target_folder)
$TempFolder = [System.Environment]::ExpandEnvironmentVariables($config.paths.temp_folder)
$DestinationFolder = $null
if ($config.paths.destination_folder) {
    $DestinationFolder = [System.Environment]::ExpandEnvironmentVariables($config.paths.destination_folder)
}
$Prefix = $config.settings.prefix
$IgnorePrefix = $config.settings.ignore_prefix
$FFmpegPath = [System.Environment]::ExpandEnvironmentVariables($config.ffmpeg.ffmpeg_path)
$VideoExtensions = $config.video_extensions
$SubtitleExtensions = $config.subtitle_extension
$TelegramBotToken = $telegramSecrets.TELEGRAM_BOT_TOKEN
$TelegramChannelId = $telegramSecrets.TELEGRAM_CHANNEL_ID

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

. .\includes\Send-TelegramMessage.ps1

. .\includes\Test-FileSizeStable.ps1

. .\includes\Get-FfmpegConversionStrategy.ps1

. .\includes\Convert-VideoWithProgress.ps1

. .\includes\Copy-ToDestinationFolder.ps1

# === Основной обработчик события ===
$Action = {
    $FilePath = $Event.SourceEventArgs.FullPath
    $FileName = $Event.SourceEventArgs.Name
    $Extension = [IO.Path]::GetExtension($FileName).ToLower()

    Write-Log "📁 Обнаружен файл: $FileName"

    if ($SubtitleExtensions -contains $Extension) {
        Write-Log "📝 Обнаружены субтитры: $FileName" -Pale
        if ($DestinationFolder) {
            Copy-ToDestinationFolder -FilePath $FilePath -DestinationRoot $DestinationFolder
        }
        return
    }

    if ($VideoExtensions -notcontains $Extension) {
        Write-Log "❌ Не видео: $Extension" -Pale
        return
    }

    if ($FileName -like "$IgnorePrefix*") {
        Write-Log "🚫 Игнор: префикс $IgnorePrefix" -Pale
        return
    }

    # Ожидание завершения записи
    if ($UseFileSizeStabilization) {
        Write-Log "⏳ Ожидание стабилизации: $FileName" -Pale
        if (-not (Test-FileSizeStable -Path $FilePath -StabilizationTimeoutSec $StabilizationTimeoutSec -StabilizationCheckIntervalSec $StabilizationCheckIntervalSec)) {
            Write-Log "⚠ Ошибка: Файл не стабилизировался: $FileName"
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

    Write-Log "📤 Копирование видеофайла: $FileName"
    if ($DestinationFolder) {
        Copy-ToDestinationFolder -FilePath $FilePath -DestinationRoot $DestinationFolder
    }

    if ($FileSizeMB -lt $MinFileSizeMB) {
        Write-Log "📉 Маленький файл ($('{0:F1}' -f $FileSizeMB) МБ): $FileName" -Pale    
        return
    }

    $strategy = Get-FfmpegConversionStrategy -LocalInputFile $FilePath

    if ($null -eq $strategy) {
        Write-Log "❌ ОШИБКА: Не удалось найти видеопоток в файле."
        return
    }

    $BaseName = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $OutputFileName = "$Prefix$BaseName.mkv"
    $TempOutput = Join-Path $TempFolder $OutputFileName
    $FinalOutput = Join-Path $TargetFolder $OutputFileName

    try {
        if (Convert-VideoWithProgress -InputFile $FilePath -OutputFile $TempOutput -DecoderCommand $strategy -FFmpegPath $FFmpegPath) {
            if (Test-Path -LiteralPath $TempOutput) {
                if (Test-Path -LiteralPath $FinalOutput) { Remove-Item -LiteralPath $FinalOutput -Force }
                Move-Item -LiteralPath $TempOutput $FinalOutput -Force
                $FinalSizeMB = (Get-Item -LiteralPath $FinalOutput).Length / 1MB
                Write-Log "✅✅✅ Готово: $OutputFileName ($('{0:F1}' -f $FinalSizeMB) МБ)"

                $msg = "
🎬 <b>Видео обработано</b>

📁 <code>$OutputFileName</code>
📦 $("{0:F1}" -f $FinalSizeMB) МБ
⏱ $(Get-Date -Format 'HH:mm:ss')
                "
                if (-not (Send-TelegramMessage -Message $msg.Trim() -IsTelegramEnabled $TelegramEnabled -BotToken $TelegramBotToken -ChannelId $TelegramChannelId)) {
                    Write-Log "⚠ Не удалось отправить сообщение в Telegram об обработке файла: $OutputFileName"
                }

                Write-Log "📤 Копирование сжатого видеофайла: $OutputFileName" -Pale
                if ($DestinationFolder) {
                    Copy-ToDestinationFolder -FilePath $FinalOutput -DestinationRoot $DestinationFolder
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