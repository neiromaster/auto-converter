. .\includes\Write-Log.ps1

# === Auto-Update Configuration ===

$GitHubRepoOwner = "neiromaster"
$GitHubRepoName = "auto-converter"

function Check-ForUpdates {
    Write-Log "🔄 Проверяем обновление..." -Pale
    $CurrentScriptPath = $MyInvocation.PSCommandPath
    $ApiUrl = "https://api.github.com/repos/$GitHubRepoOwner/$GitHubRepoName/releases/latest"

    try {
        $CurrentScriptHash = (Get-FileHash -Algorithm SHA256 -Path $CurrentScriptPath).Hash
        Write-Log "🔄 Хэш скрипта: $CurrentScriptHash" -Pale

        $LatestRelease = Invoke-RestMethod -Uri $ApiUrl -Headers @{ "User-Agent" = "PowerShell-Updater" } -TimeoutSec 10
        $ReleaseBody = $LatestRelease.body
        $LatestReleaseHash = ($ReleaseBody | Select-String -Pattern "SHA256: ([a-fA-F0-9]{64})" | ForEach-Object { $_.Matches[0].Groups[1].Value })

        if (-not $LatestReleaseHash) {
            Write-Log "⚠ Предупреждение: хеш SHA256 не найден в теле последнего релиза. Невозможно выполнить проверку обновлений на основе содержимого."
            return
        }

        Write-Log "🔄 Хэш скрипта в последнем релизе: $LatestReleaseHash" -Pale

        $TempUpdatePath = Join-Path ([System.IO.Path]::GetTempPath()) "auto-converter.ps1.new"

        if ($CurrentScriptHash -ne $LatestReleaseHash) {
            Write-Log "🔄 Доступна новая версия. Применяем обновление..."
            $DownloadUrl = $LatestRelease.assets | Where-Object { $_.name -eq "auto-converter.ps1" } | Select-Object -ExpandProperty browser_download_url

            if ($DownloadUrl) {
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempUpdatePath -TimeoutSec 30

                Write-Log "🔄 Обновление загружено в $TempUpdatePath. Применение обновления..." -Pale

                $UpdateScriptContent = @"
param(
    [string]`$CurrentScriptPath,
    [string]`$TempUpdatePath
)

function Write-UpdaterLog {
    param([string]`$Message)
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "`$timestamp | UPDATER | `$Message" | Out-File -FilePath (Join-Path ([System.IO.Path]::GetTempPath()) "auto-converter-updater.log") -Append -Encoding UTF8
    Write-Host `$Message
}

Write-UpdaterLog "Начинаем применение обновления..."

try {
    Start-Sleep -Seconds 2

    `$OldScriptBackupPath = "`$CurrentScriptPath.old"

    if (Test-Path -LiteralPath `$CurrentScriptPath) {
        Write-UpdaterLog "Перемещаем текущий скрипт в резервную копию: `$OldScriptBackupPath"
        Rename-Item -Path `$CurrentScriptPath -NewName `$OldScriptBackupPath -Force -ErrorAction Stop
    } else {
        Write-UpdaterLog "Текущий скрипт не найден по пути: `$CurrentScriptPath. Возможно, уже был перемещен или удален."
    }

    if (Test-Path -LiteralPath `$TempUpdatePath) {
        Write-UpdaterLog "Перемещаем новый скрипт: `$TempUpdatePath -> `$CurrentScriptPath"
        Move-Item -Path `$TempUpdatePath -Destination `$CurrentScriptPath -Force -ErrorAction Stop
    } else {
        throw "Временный файл обновления не найден: `$TempUpdatePath"
    }

    if (Test-Path -LiteralPath `$OldScriptBackupPath) {
        Write-UpdaterLog "Удаляем старую резервную копию: `$OldScriptBackupPath"
        Remove-Item -Path `$OldScriptBackupPath -Force -ErrorAction SilentlyContinue
    }

    Write-UpdaterLog "Обновление завершено. Перезапуск скрипта..."
    Start-Process pwsh.exe -ArgumentList "-NoProfile", "-File", "`"`$CurrentScriptPath`"`" 
    exit 0
}
catch {
    Write-UpdaterLog "ОШИБКА ПРИМЕНЕНИЯ ОБНОВЛЕНИЯ: `$_ "
    if (Test-Path -LiteralPath `$OldScriptBackupPath -and -not (Test-Path -LiteralPath `$CurrentScriptPath)) {
        Write-UpdaterLog "Попытка отката: восстанавливаем старый скрипт из резервной копии."
        try {
            Rename-Item -Path `$OldScriptBackupPath -NewName `$CurrentScriptPath -Force -ErrorAction Stop
            Write-UpdaterLog "Откат успешно выполнен."
        }
        catch {
            Write-UpdaterLog "КРИТИЧЕСКАЯ ОШИБКА ОТКАТА: `$_ . Возможно, потребуется ручное восстановление."
        }
    }
    exit 1
}
finally {
    if (Test-Path -LiteralPath `$TempUpdatePath) {
        Remove-Item -Path `$TempUpdatePath -Force -ErrorAction SilentlyContinue
    }
}
"@
                $TempUpdaterPath = Join-Path ([System.IO.Path]::GetTempPath()) "auto-converter-updater.ps1"
                $UpdateScriptContent | Out-File $TempUpdaterPath -Encoding UTF8

                Write-Log "🔄 Перезапуск для применения обновления..." -Pale
                Start-Process pwsh.exe -ArgumentList "-NoProfile", "-File", "`"$TempUpdaterPath`"", "-CurrentScriptPath", "`"$CurrentScriptPath`"", "-TempUpdatePath", "`"$TempUpdatePath`""
                exit
            }
            else {
                Write-Log "❌ Ошибка: Не удалось найти auto-converter.ps1 в последней версии."
            }
        }
        else {
            Write-Log "🔄 Скрипт обновлён."
            Remove-Item -Path $TempUpdatePath -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Log "❌ Ошибка обновления: $_"
    }
}
