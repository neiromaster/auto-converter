. .\includes\Write-Log.ps1

function Copy-ToDestinationFolder {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [string]$DestinationRoot
    )

    $FileName = [System.IO.Path]::GetFileName($FilePath)
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)

    Write-Log "🔍 Поиск папки назначения для: $FileName" -Pale

    $normalizedBaseName = $BaseName.Replace('.', ' ').Replace('_', ' ').ToLower()

    $foundDestinationFolder = $null
    $destinationFolders = Get-ChildItem -Path $DestinationRoot -Directory | Select-Object -ExpandProperty Name

    foreach ($folderName in $destinationFolders) {
        $normalizedFolderName = $folderName.Replace('.', ' ').Replace('_', ' ').ToLower()

        if ($normalizedBaseName -like "*$normalizedFolderName*") {
            $foundDestinationFolder = Join-Path $DestinationRoot $folderName
            break
        }
    }

    if (-not $foundDestinationFolder) {
        Write-Log "❌ Не найдена папка назначения для файла: $FileName" -Pale
        return
    }

    Write-Log "✅ Найдена папка назначения: $foundDestinationFolder" -Pale

    try {
        $targetPath = Join-Path $foundDestinationFolder $FileName
        Copy-Item -LiteralPath $FilePath -Destination $targetPath -Force -ErrorAction Stop -ProgressAction Continue
        Write-Log "✅ Скопирован файл: $FileName в $foundDestinationFolder"
    }
    catch {
        Write-Log "❌ Ошибка при копировании файла(ов) в ${foundDestinationFolder}: $($_.Exception.Message)"
    }
}