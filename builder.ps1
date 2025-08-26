$mainScript = "auto-converter.ps1"
$outputFile = "dist/auto-converter.ps1"

$outputDir = Split-Path $outputFile
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$embedded = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)

if (Test-Path $outputFile) { Remove-Item $outputFile }

function Embed-Includes {
    param(
        [string[]]$lines,
        [string]$basePath
    )

    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $basePath = "."
    }

    foreach ($line in $lines) {
        if ($line -match '^\s*\.\s*["'']?\.\\?([^"'']+\.ps1)') {
            $joinedPath = Join-Path $basePath $matches[1]
            $resolvedItem = Resolve-Path $joinedPath -ErrorAction SilentlyContinue

            if (-not $resolvedItem) {
                Write-Warning "Файл $($matches[1]) не найден, оставляю строку подключения"
                Add-Content $outputFile $line
                continue
            }

            $normalizedPath = (Get-Item $resolvedItem).FullName.Replace('\', '/')

            if ($embedded -contains $normalizedPath) {
                Write-Host "⚠ Пропуск повторного подключения: $normalizedPath"
                continue
            }

            $embedded.Add($normalizedPath)
            Write-Host "📄 Встраиваю: $normalizedPath"

            Add-Content $outputFile "`n# --- Start of $normalizedPath ---"
            $content = Get-Content $normalizedPath
            Embed-Includes $content (Split-Path $normalizedPath)
            Add-Content $outputFile "# --- End of $normalizedPath ---`n"
        }
        else {
            Add-Content $outputFile $line
        }
    }
}

Write-Host "🚀 Начало сборки..."
$mainContent = Get-Content $mainScript
Embed-Includes $mainContent (Split-Path $mainScript)

@'
if ($MyInvocation.InvocationName -notmatch "Import-Module") {
    if (Get-Command -Name Main -ErrorAction SilentlyContinue) {
        Main
    } else {
        Write-Host "В модуле нет функции Main для автозапуска"
    }
}
'@ | Add-Content $outputFile

Write-Host "✅ Модуль собран: $outputFile"
