. .\includes\Write-Log.ps1

# === Конвертация с прогрессом и CUDA (с поддержкой остановки по Esc) ===
function Convert-VideoWithProgress {
    param(
        [string]$InputFile,
        [string]$OutputFile,
        [string]$DecoderCommand = $null,
        [int]$ScaleWidth = 0,
        [int]$ScaleHeight = 0,
        [int]$QP = 30,
        [string]$FFmpegPath
    )

    $Arguments = @(
        "-hwaccel", "cuda",
        "-hwaccel_output_format", "cuda"
    )

    if ($DecoderCommand) {
        $Arguments += $DecoderCommand.Split(" ")
    }

    if ($ScaleWidth -gt 0 -and $ScaleHeight -gt 0) {
        $scaleFilter = "scale_cuda=w=${ScaleWidth}:h=${ScaleHeight}:format=nv12"
    }
    else {
        $scaleFilter = "scale_cuda=format=nv12"
    }

    $Arguments += @(
        "-i", "`"$InputFile`"",
        "-map", "0:v:0", "-map", "0:a:0",
        "-vf", "`"$scaleFilter`"",
        "-c:v", "h264_nvenc",
        "-preset", "p5",
        "-rc", "constqp",
        "-qp", "$QP",
        "-c:a", "aac",
        "-b:a", "128k",
        "-sn",
        "-movflags", "+faststart",
        "-f", "matroska",
        "-y",
        "`"$OutputFile`""
    )

    Write-Log "🚀 FFmpeg: $($Arguments -join ' ')" -Pale

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FFmpegPath
    $psi.Arguments = $Arguments -join " "
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try {
        $proc.Start() | Out-Null

        $TotalDuration = $null
        $StartTime = Get-Date
        $Speed = 0
        $Cancelled = $false

        $errorReader = $proc.StandardError.BaseStream
        $errorBuffer = New-Object System.IO.StreamReader($errorReader)

        while (-not $proc.HasExited) {
            if (-not [System.Console]::IsInputRedirected -and [System.Console]::KeyAvailable) {
                $key = [System.Console]::ReadKey($true)
                if ($key.Key -eq [System.ConsoleKey]::Escape) {
                    Write-Log "🛑 Принудительная остановка конвертации (Esc)..." -Red
                    $proc.Kill()
                    $Cancelled = $true

                    # Пауза, чтобы система успела освободить файл
                    Start-Sleep -Milliseconds 500

                    if (Test-Path -LiteralPath $OutputFile) {
                        Write-Log "🗑️ Удаление временного файла: $OutputFile" -Pale
                        try {
                            Remove-Item -LiteralPath $OutputFile -Force -ErrorAction Stop
                        }
                        catch {
                            Write-Log "⚠️ Не удалось удалить временный файл: $OutputFile. Ошибка: $($_.Exception.Message)" -Red
                        }
                    }

                    break
                }
            }


            if (-not $errorBuffer.EndOfStream) {
                $line = $errorBuffer.ReadLine()
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

            Start-Sleep -Milliseconds 200
        }

        if (-not $Cancelled) {
            $proc.WaitForExit()
        }

        Write-Progress -Activity "Конвертация" -Completed

        return $proc.ExitCode -eq 0 -and -not $Cancelled
    }
    catch {
        Write-Log "❌ Ошибка во время конвертации: $_" -Red
        return $false
    }
    finally {
        if (-not $proc.HasExited) {
            $proc.Kill()
        }
        $proc.Dispose()
    }
}