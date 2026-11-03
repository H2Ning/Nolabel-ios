param(
    [string]$Source = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Source)) {
    $sourceRoot = Split-Path -Parent $PSScriptRoot
} else {
    $sourceRoot = (Resolve-Path -LiteralPath $Source).Path
}

$sourceRoot = (Resolve-Path -LiteralPath $sourceRoot).Path
$destination = Join-Path $PSScriptRoot "NolabelApp\Resources\www"

$required = @(
    "index.html",
    "styles.css",
    "app.js",
    "assets\notes"
)

foreach ($item in $required) {
    $path = Join-Path $sourceRoot $item
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing $item under $sourceRoot"
    }
}

if (Test-Path -LiteralPath $destination) {
    Remove-Item -LiteralPath $destination -Recurse -Force
}
New-Item -ItemType Directory -Path $destination | Out-Null

Copy-Item -LiteralPath (Join-Path $sourceRoot "index.html") -Destination $destination
Copy-Item -LiteralPath (Join-Path $sourceRoot "styles.css") -Destination $destination
Copy-Item -LiteralPath (Join-Path $sourceRoot "app.js") -Destination $destination
Copy-Item -LiteralPath (Join-Path $sourceRoot "favicon.svg") -Destination $destination
Copy-Item -LiteralPath (Join-Path $sourceRoot "assets") -Destination (Join-Path $destination "assets") -Recurse

Write-Host "Synced web files from $sourceRoot to $destination"
