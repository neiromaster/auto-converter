
. .\includes\Write-Log.ps1

# === Конвертация субтитров ===
function Convert-Subtitle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubtitleFilePath,

        [Parameter(Mandatory = $true)]
        [string]$FFmpegPath
    )

    $fileExtension = [System.IO.Path]::GetExtension($SubtitleFilePath).ToLower()

    if ($fileExtension -eq ".srt") {
        Write-Log "ℹ️  Файл субтитров уже в формате SRT: '$SubtitleFilePath'" -Pale
        return $false
    } else {
        $outputFilePath = ([System.IO.Path]::ChangeExtension($SubtitleFilePath, ".srt"))
        Write-Log "🔄 Конвертируем $fileExtension в SRT: '$SubtitleFilePath' -> '$outputFilePath'" -Pale

        $ffmpegOutput = & $FFmpegPath -i $SubtitleFilePath -c:s srt $outputFilePath -y 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "✅ Конвертация $fileExtension в SRT завершена успешно." -Pale
            return $true
        } else {
            Write-Log "❌ Ошибка при конвертации $fileExtension в SRT: $ffmpegOutput"
            return $false
        }
    }
}
