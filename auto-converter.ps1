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

$AutoUpdateEnabled = $true
$LogFile = $null

# === Преобразование типов и валидация ===
try {
    $AutoUpdateEnabled = [bool]::Parse($config.settings.auto_update_enabled)
    $LogFile = $config.logging.log_file
    $LogFile = Join-Path -Path $PSScriptRoot -ChildPath $LogFile
}
catch {
    Write-Error "❌ Ошибка парсинга настроек: $_"
}

. .\includes\Check-ForUpdates.ps1

# --- Проверка обновления ---
if ($AutoUpdateEnabled) {
    Check-ForUpdates
}


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

# === Преобразование типов и валидация ===
try {
    $MinFileSizeMB = [int]$config.settings.min_file_size_mb
    $StabilizationCheckIntervalSec = [int]$config.stabilization_strategy.stabilization_check_interval_sec
    $StabilizationTimeoutSec = [int]$config.stabilization_strategy.stabilization_timeout_sec
    $TelegramEnabled = [bool]::Parse($config.settings.telegram_enabled)
    $UseFileSizeStabilization = [bool]::Parse($config.stabilization_strategy.use_file_size_stabilization)
    $AutoUpdateEnabled = [bool]::Parse($config.settings.auto_update_enabled)
    $EnabledModules = @{}
    $config.settings.modules | ForEach-Object { $EnabledModules[$_] = $true }
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
$Prefix = if ($config.settings.ContainsKey('prefix')) { $config.settings.prefix } else { '' }
$IgnorePrefix = $config.settings.ignore_prefix
$FFmpegPath = [System.Environment]::ExpandEnvironmentVariables($config.ffmpeg.ffmpeg_path)
$VideoExtensions = $config.video_extensions
$SubtitleExtensions = $config.subtitle_extension
$SubtitleExtractLanguages = $config.subtitles.extract_languages

$TelegramBotToken = $telegramSecrets.TELEGRAM_BOT_TOKEN
$TelegramChannelId = $telegramSecrets.TELEGRAM_CHANNEL_ID
$TelegramChatId = $telegramSecrets.TELEGRAM_CHAT_ID

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

. .\includes\Convert-Subtitle.ps1

. .\includes\Extract-Subtitles.ps1

# === Основной обработчик события ===
$Action = {
    $FilePath = $Event.SourceEventArgs.FullPath
    $FileName = $Event.SourceEventArgs.Name
    $Extension = [IO.Path]::GetExtension($FileName).ToLower()

    if (-not (Test-Path -LiteralPath $FilePath)) {
        Write-Log "⏭  Файл не найден (возможно, перемещен или удален): $FileName" -Pale
        return
    }

    Write-Log "📁 Обнаружен файл: $FileName"

    # Ожидание завершения записи
    if ($UseFileSizeStabilization) {
        Write-Log "⏳ Ожидание стабилизации: $FileName" -Pale
        if (-not (Test-FileSizeStable -Path $FilePath -StabilizationTimeoutSec $StabilizationTimeoutSec -StabilizationCheckIntervalSec $StabilizationCheckIntervalSec)) {
            Write-Log "⚠ Ошибка: Файл не стабилизировался: $FileName"
            return
        }
    }

    if ($SubtitleExtensions -contains $Extension) {
        if ($EnabledModules['convert-subtitles']) {
            Write-Log "📝 Обнаружены субтитры: $FileName" -Pale
            $isSubConverted = Convert-Subtitle -SubtitleFilePath $FilePath -FFmpegPath $FFmpegPath
        }

        if ($EnabledModules['copy-to-destination'] -and $DestinationFolder -and -not $isSubConverted) {
            $msg = Copy-ToDestinationFolder -FilePath $FilePath -DestinationRoot $DestinationFolder

            if ($msg -and -not (Send-TelegramMessage -Message $msg.Trim() -IsTelegramEnabled $TelegramEnabled -BotToken $TelegramBotToken -ChannelId $TelegramChatId)) {
                Write-Log "⚠ Не удалось отправить сообщение в Telegram о скачивании файла: $FileName"
            }
        }
        return
    }

    if ($VideoExtensions -notcontains $Extension) {
        Write-Log "❌ Не видео: $Extension" -Pale
        return
    }

    $FileSizeMB = (Get-Item -LiteralPath $FilePath).Length / 1MB

    if ($EnabledModules['copy-to-destination']) {
        Write-Log "📤 Копирование видеофайла: $FileName"
        if ($DestinationFolder) {
            $msg = Copy-ToDestinationFolder -FilePath $FilePath -DestinationRoot $DestinationFolder
            
            if ($msg -and -not (Send-TelegramMessage -Message $msg.Trim() -IsTelegramEnabled $TelegramEnabled -BotToken $TelegramBotToken -ChannelId $TelegramChatId)) {
                Write-Log "⚠ Не удалось отправить сообщение в Telegram о скачивании файла: $FileName"
            }
            
            if (-not $msg) {
                if ($Prefix -and $FileName -like "$Prefix*") {
                    $text = "Сжатое видео готово"
                }
                else {
                    $text = "Видео скачано"
                }

                $msg = "
🎬 <b>$text</b>

📁 <code>$FileName</code>
📦 $("{0:F1}" -f $FileSizeMB) МБ
⏱ $(Get-Date -Format 'HH:mm:ss')
                "
                if (-not (Send-TelegramMessage -Message $msg.Trim() -IsTelegramEnabled $TelegramEnabled -BotToken $TelegramBotToken -ChannelId $TelegramChannelId)) {
                    Write-Log "⚠ Не удалось отправить сообщение в Telegram о скачивании файла: $FileName"
                }
            }
        }
    }

    if ($IgnorePrefix -and $FileName -like "$IgnorePrefix*") {
        Write-Log "🚫 Игнор: префикс $IgnorePrefix" -Pale
        return
    }

    if ($EnabledModules['extract-subtitles']) {
        Extract-Subtitles -VideoFilePath $FilePath -Languages $SubtitleExtractLanguages -FFmpegPath $FFmpegPath
    }

    if ($FileSizeMB -lt $MinFileSizeMB) {
        Write-Log "📉 Маленький файл ($('{0:F1}' -f $FileSizeMB) МБ): $FileName" -Pale
        return
    }

    if ($EnabledModules['convert-video']) {
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
}


# === Запуск мониторинга ===
Write-Log "✅ Мониторинг запущен: $SourceFolder"
Write-Log "Нажмите Ctrl+C для остановки."

$Watcher = New-Object IO.FileSystemWatcher
$Watcher.Path = $SourceFolder
$Watcher.IncludeSubdirectories = $true
$Watcher.EnableRaisingEvents = $true
$Watcher.Filter = "*.*"

$null = Register-ObjectEvent -InputObject $Watcher -EventName Created -SourceIdentifier "FileCreated" -Action $Action
$null = Register-ObjectEvent -InputObject $Watcher -EventName Renamed -SourceIdentifier "FileRenamed" -Action $Action

try {
    while ($true) { Start-Sleep -Seconds 1 }
}
finally {
    Get-EventSubscriber -SourceIdentifier "FileCreated", "FileRenamed" -ErrorAction SilentlyContinue | ForEach-Object {
        Unregister-Event -SubscriptionId $_.SubscriptionId
    }
    $Watcher.Dispose()
    Write-Log "🛑 Мониторинг остановлен."
}