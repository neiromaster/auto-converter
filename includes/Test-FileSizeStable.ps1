
. .\Write-Log.ps1

# === Функция: стабилизация размера ===
function Test-FileSizeStable {
    param(
        [string]$Path,
        [int]$StabilizationTimeoutSec,
        [int]$StabilizationCheckIntervalSec
    )
    $StartTime = Get-Date
    $LastSize = -1

    while (((Get-Date) - $StartTime).TotalSeconds -lt $StabilizationTimeoutSec) {
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Log "⚠ Файл исчез: $Path"
            return $false
        }

        try {
            $CurrentSize = (Get-Item -LiteralPath $Path).Length
        }
        catch {
            Write-Log "🔒 Файл используется: $Path"
            $LastSize = -1
            Start-Sleep -Seconds $StabilizationCheckIntervalSec
        }

        if ($CurrentSize -eq $LastSize) {
            Write-Log "✅ Размер файла стабилизировался: $Path ($CurrentSize байт)"
            return $true
        }

        $LastSize = $CurrentSize
        Start-Sleep -Seconds $StabilizationCheckIntervalSec
    }

    Write-Log "❌ Размер файла не стабилизировался в течение $StabilizationTimeoutSec секунд: $Path"
    return $false
}
