
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

        $arguments = @(
            "-i", "`"$SubtitleFilePath`"",
            "`"$outputFilePath`"",
            "-y"
        )

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FFmpegPath
        $psi.Arguments = $arguments -join " "
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardOutput = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        $proc.Start() | Out-Null
        $proc.WaitForExit()

        if ($proc.ExitCode -eq 0) {
            Write-Log "✅ Конвертация $fileExtension в SRT завершена успешно." -Pale
            return $true
        } else {
            $errorOutput = $proc.StandardError.ReadToEnd()
            Write-Log "❌ Ошибка при конвертации $fileExtension в SRT: $errorOutput"
            return $false
        }
    }
}
