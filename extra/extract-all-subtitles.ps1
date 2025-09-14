# This script extracts all subtitle tracks from a given video file.
# It uses ffprobe to detect the streams and ffmpeg to extract them.
#
# Usage:
# Drag a video file onto this script, or run from the command line:
# .\\extract-all-subtitles.ps1 "path\\to\\your\\video.mkv"
# Use `pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ".\extract-all-subtitles.ps1"` for shortcuts

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$VideoFilePath
)

function Pause-And-Exit {
    param($message)
    if ($message) {
        Write-Host "`n$message"
    }
    Write-Host "Нажмите Enter для выхода..."
    Read-Host
    exit
}

# Find ffmpeg in the system's PATH
$FFmpegPath = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $FFmpegPath) {
    Write-Error "❌ ffmpeg.exe не найден в системных переменных PATH. Пожалуйста, установите FFmpeg и убедитесь, что он доступен."
    Pause-And-Exit
}

# Ensure the video file exists
if (-not (Test-Path $VideoFilePath)) {
    Write-Error "❌ Видеофайл не найден: $VideoFilePath"
    Pause-And-Exit
}

# Setup paths for ffprobe
$FFprobePath = Join-Path (Split-Path $FFmpegPath) "ffprobe.exe"
if (-not (Test-Path $FFprobePath)) {
    Write-Error "❌ FFprobe не найден по ожидаемому пути: $FFprobePath"
    Pause-And-Exit
}

# Get stream information from the video file
$FileInfo = try {
    & $FFprobePath -v quiet -print_format json -show_streams -show_error -i $VideoFilePath | ConvertFrom-Json
}
catch {
    Write-Warning "⚠️ Ошибка при запуске ffprobe для файла: $VideoFilePath. $_"
    Pause-And-Exit
}

# Check if any streams were found
if ($null -eq $FileInfo.streams) {
    Write-Host "ℹ️ В файле не найдены потоки: $VideoFilePath"
    Pause-And-Exit
}

# Filter for subtitle streams
$SubtitleStreams = @($FileInfo.streams | Where-Object { $_.codec_type -eq 'subtitle' })

if ($SubtitleStreams.Count -eq 0) {
    Write-Host "ℹ️ В файле не найдены дорожки субтитров: $VideoFilePath"
    Pause-And-Exit
}

Write-Host "Найдено дорожек субтитров: $($SubtitleStreams.Count). Начинаю извлечение..."

$BaseName = [IO.Path]::GetFileNameWithoutExtension($VideoFilePath)
$Directory = [IO.Path]::GetDirectoryName($VideoFilePath)

# Loop through each subtitle stream and extract it
foreach ($Stream in $SubtitleStreams) {
    $StreamIndex = $Stream.index
    $Language = $Stream.tags.language
    $Title = $Stream.tags.title

    # Construct a unique and descriptive filename
    $fileName = $BaseName

    # Add language if it exists (priority)
    if (-not [string]::IsNullOrEmpty($Language)) {
        $fileName += ".$Language"
    }
    # Otherwise, add title if it exists
    elseif (-not [string]::IsNullOrEmpty($Title)) {
        # Sanitize title to remove characters that are invalid in filenames
        $safeTitle = $Title -replace '[\\/:"*?<>|]', ''
        $fileName += ".$safeTitle"
    }

    # Add the stream index to guarantee uniqueness
    $fileName += "_$($StreamIndex).srt"

    $SubtitleFilePath = Join-Path $Directory $fileName

    Write-Host "  Извлечение потока #$($StreamIndex) в файл '$($fileName)'..."

    # Execute ffmpeg to extract the subtitle track
    $ffmpegArgs = "-loglevel quiet -i `"$VideoFilePath`" -map 0:$StreamIndex -c:s srt -y `"$SubtitleFilePath`""
    try {
        # Using Start-Process to handle paths with spaces and avoid command line parsing issues
        $process = Start-Process -FilePath $FFmpegPath -ArgumentList $ffmpegArgs -NoNewWindow -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Host "  ✅ Успешно извлечено: $fileName"
        }
        else {
            Write-Warning "  ❌ Не удалось извлечь поток #$($StreamIndex). Код выхода FFmpeg: $($process.ExitCode)"
        }
    }
    catch {
        Write-Warning "  ❌ Произошла ошибка при извлечении потока #$($StreamIndex). $_"
    }
}

Pause-And-Exit "Извлечение завершено."