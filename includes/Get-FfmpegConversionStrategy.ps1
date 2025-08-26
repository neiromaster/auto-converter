. .\includes\Write-Log.ps1

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

    return $decoderCommand
}