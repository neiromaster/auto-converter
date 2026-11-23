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
