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
