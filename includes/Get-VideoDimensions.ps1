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
