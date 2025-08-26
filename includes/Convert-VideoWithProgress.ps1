. .\includes\Write-Log.ps1

# === Конвертация с прогрессом и CUDA ===
function Convert-VideoWithProgress {
    param([string]$InputFile, [string]$OutputFile, [string]$DecoderCommand = $null, [string]$FFmpegPath)

    $Arguments = @(
        "-hwaccel", "cuda",
        "-hwaccel_output_format", "cuda"
    )

    if ($DecoderCommand) {
        $Arguments += $DecoderCommand.Split(" ")
    }

    $Arguments += @(
        "-i", "`"$InputFile`"",
        "-map", "0:v:0", "-map", "0:a:0"
        "-vf", "`"scale_cuda=format=nv12`"",
        "-c:v", "h264_nvenc",
        "-preset", "p5",
        "-rc", "constqp",
        "-qp", "32",
        "-c:a", "aac",
        "-b:a", "128k",
        "-sn",
        "-movflags", "+faststart",
        "-f", "matroska",
        "-y",
        "`"$OutputFile`""
    )

    Write-Log "🚀 FFmpeg: $($Arguments -join ' ')"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FFmpegPath
    $psi.Arguments = $Arguments -join " "
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null

    $TotalDuration = $null
    $StartTime = Get-Date
    $Speed = 0

    while (-not $proc.StandardError.EndOfStream) {
        $line = $proc.StandardError.ReadLine()
        if ($line -match "Duration:\s*(\d{2}:\d{2}:\d{2}\.\d{2})") {
            $TotalDuration = [timespan]::Parse($matches[1])
        }
        if ($line -match "time=(\d{2}:\d{2}:\d{2}\.\d{2})") {
            $CurrentTime = [timespan]::Parse($matches[1])
            if ($TotalDuration.TotalSeconds -gt 0) {
                $Percent = [Math]::Min(99.9, ($CurrentTime.TotalSeconds / $TotalDuration.TotalSeconds) * 100)
                $Elapsed = (Get-Date) - $StartTime
                if ($Elapsed.TotalSeconds -gt 0) {
                    $Speed = $CurrentTime.TotalSeconds / $Elapsed.TotalSeconds
                }
                $Remaining = [TimeSpan]::FromSeconds(($TotalDuration.TotalSeconds - $CurrentTime.TotalSeconds) / $Speed)
                Write-Progress -Activity "Конвертируем: $(Split-Path $InputFile -Leaf)" `
                    -Status ("{0:F1}% | {1:F2}x | осталось {2:mm\:ss}" -f $Percent, $Speed, $Remaining) `
                    -PercentComplete $Percent
            }
        }
    }

    $proc.WaitForExit()
    Write-Progress -Activity "Конвертация" -Completed

    return $proc.ExitCode -eq 0
}