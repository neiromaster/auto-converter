# === Функция: вычисление размеров для масштабирования по длинной стороне ===
function Get-ScaledDimensions {
    param(
        [int]$Width = 0,
        [int]$Height = 0,
        [Parameter(Mandatory = $true)]
        [int]$MaxResolution
    )

    $result = @{
        ScaleWidth  = 0
        ScaleHeight = 0
    }

    if ($MaxResolution -le 0) {
        return $result
    }

    $longSide = [Math]::Max($Width, $Height)
    if ($longSide -le $MaxResolution) {
        return $result
    }

    $ratio = $MaxResolution / $longSide
    $result.ScaleWidth = [int][Math]::Round($Width * $ratio / 2) * 2
    $result.ScaleHeight = [int][Math]::Round($Height * $ratio / 2) * 2

    return $result
}
