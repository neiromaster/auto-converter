. .\includes\Write-Log.ps1

function Extract-Subtitles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VideoFilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Languages,

        [Parameter(Mandatory = $true)]
        [string]$FFmpegPath
    )

    $FFprobePath = Join-Path (Split-Path $FFmpegPath) "ffprobe.exe"
    if (-not (Test-Path $FFprobePath)) {
        Write-Log "❌ FFprobe не найден: $FFprobePath"
        return
    }

    $FileInfo = try {
        & $FFprobePath -v quiet -print_format json -show_streams -show_error -i $VideoFilePath | ConvertFrom-Json
    }
    catch {
        Write-Log "❌ Ошибка при выполнении ffprobe для файла: $VideoFilePath"
        return
    }

    if ($null -eq $FileInfo.streams) {
        Write-Log "⏭️ Нет доступных потоков для $VideoFilePath" -Pale
        return
    }

    $AllSubtitleStreams = @($FileInfo.streams | Where-Object { $_.codec_type -eq 'subtitle' })

    if ($AllSubtitleStreams.Count -eq 0) {
        Write-Log "⏭️ Субтитры не найдены в файле: $VideoFilePath" -Pale
        return
    }

    $lowerLanguages = $Languages | ForEach-Object { $_.ToLower() }
    $MatchingStreams = @($AllSubtitleStreams | Where-Object { $_.tags -and $_.tags.language -and ($lowerLanguages -contains $_.tags.language.ToLower()) })

    $StreamsToExtract = if ($MatchingStreams.Count -gt 0) {
        $MatchingStreams
    }
    else {
        Write-Log "🤔 Не найдено субтитров с указанными языками, извлекаем все доступные." -Color Yellow
        $AllSubtitleStreams
    }

    $LanguageCounts = @{}
    foreach ($Stream in $StreamsToExtract) {
        $Language = $Stream.tags.language
        if ([string]::IsNullOrEmpty($Language)) {
            $Language = "und" # Undetermined
        }

        if (-not $LanguageCounts.ContainsKey($Language)) {
            $LanguageCounts[$Language] = 0
        }
        $LanguageCounts[$Language]++

        $TrackIndex = $LanguageCounts[$Language]
        $BaseName = [IO.Path]::GetFileNameWithoutExtension($VideoFilePath)
        $Directory = [IO.Path]::GetDirectoryName($VideoFilePath)
        $SubtitleFileName = "${BaseName}_${Language}_${TrackIndex}.srt"
        $SubtitleFilePath = Join-Path $Directory $SubtitleFileName

        $StreamIndex = $Stream.index
        
        Write-Log "📤 Извлечение субтитров: $SubtitleFileName" -Pale
        
        try {
            & $FFmpegPath -i $VideoFilePath -map 0:$StreamIndex -c:s srt -y $SubtitleFilePath
            Write-Log "✅ Субтитры извлечены: $SubtitleFileName"
        }
        catch {
            Write-Log "❌ Ошибка при извлечении субтитров из файла: $VideoFilePath"
        }
    }
}
