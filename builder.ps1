$mainScript = "auto-converter.ps1"
$outputFile = "dist/auto-converter.ps1"

$outputDir = Split-Path $outputFile
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$embedded = @()

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
            $resolvedPath = Join-Path $basePath $matches[1] | Resolve-Path -ErrorAction SilentlyContinue
            if (-not $resolvedPath) {
                Write-Warning "Файл $($matches[1]) не найден, оставляю строку подключения"
                Add-Content $outputFile $line
                continue
            }

            $resolvedPath = $resolvedPath.ProviderPath

            if ($embedded -contains $resolvedPath) {
                Write-Host "⚠ Пропуск повторного подключения: $resolvedPath"
                continue
            }

            $embedded += $resolvedPath
            Write-Host "📄 Встраиваю: $resolvedPath"

            Add-Content $outputFile "`n# --- Start of $resolvedPath ---"
            $content = Get-Content $resolvedPath
            Embed-Includes $content (Split-Path $resolvedPath)
            Add-Content $outputFile "# --- End of $resolvedPath ---`n"
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
