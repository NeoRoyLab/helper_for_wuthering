$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Read-Json([string] $path) {
    $text = $strictUtf8.GetString([System.IO.File]::ReadAllBytes($path))
    return $text | ConvertFrom-Json
}

$master = Read-Json (Join-Path $root 'manifest.json')
$manifest = Read-Json (Join-Path $root 'manifests\characters.json')
$imageManifest = Read-Json (Join-Path $root 'manifests\character_images.json')
if ($master.schema_version -ne 1) { throw 'Unexpected master schema version.' }
if ($manifest.schema_version -ne 1) { throw 'Unexpected character manifest schema version.' }
if ($manifest.characters.Count -ne 60) { throw "Expected 60 ids, got $($manifest.characters.Count)." }
if (($manifest.characters | Sort-Object -Unique).Count -ne 60) { throw 'Duplicate manifest ids.' }

$elements = @('aero', 'electro', 'fusion', 'glacio', 'havoc', 'spectro')
$weapons = @('broadblade', 'gauntlets', 'pistols', 'rectifier', 'sword')
$expectedImageCount = 53
$expectedUnavailableCount = 7
$imageById = @{}
foreach ($image in $imageManifest.images) {
    if ($imageById.ContainsKey([string]$image.id)) { throw "Duplicate image id: $($image.id)" }
    $imageById[[string]$image.id] = $image
}
if ($imageById.Count -ne $expectedImageCount) { throw "Expected $expectedImageCount images, got $($imageById.Count)." }
if ($imageManifest.unavailable.Count -ne $expectedUnavailableCount) { throw "Expected $expectedUnavailableCount unavailable entries." }
foreach ($id in $manifest.characters) {
    if ($id -cnotmatch '^[a-z0-9]+(?:_[a-z0-9]+)*$') { throw "Invalid id: $id" }
    $path = Join-Path $root "characters\$id\data.json"
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing record: $id" }
    $record = Read-Json $path
    if ($record.id -cne $id) { throw "Id mismatch: $id" }
    if ([string]::IsNullOrWhiteSpace($record.name.en)) { throw "Missing English name: $id" }
    if ($record.rarity -notin @(4, 5)) { throw "Invalid rarity: $id" }
    if ($record.element -notin $elements) { throw "Invalid element: $id" }
    if ($record.weapon_type -notin $weapons) { throw "Invalid weapon: $id" }
    if ($record.source.site -cne 'Prydwen.gg') { throw "Invalid source: $id" }
    if ($record.source.verified_at -cne '2026-08-28') { throw "Invalid verification date: $id" }

    if ($imageById.ContainsKey($id)) {
        $image = $imageById[$id]
        $expectedPath = "characters/$id/convene_draw.png"
        if ($record.convene_draw -cne $expectedPath -or $image.path -cne $expectedPath) {
            throw "Invalid Convene Draw path: $id"
        }
        $imagePath = Join-Path $root ($expectedPath.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $imagePath)) { throw "Missing Convene Draw PNG: $id" }
        $bytes = [System.IO.File]::ReadAllBytes($imagePath)
        if ($bytes.Length -lt 24 -or $bytes[0] -ne 137 -or $bytes[1] -ne 80 -or $bytes[2] -ne 78 -or $bytes[3] -ne 71) {
            throw "Invalid PNG signature: $id"
        }
        $width = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 16))
        $height = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 20))
        if ($width -ne 404 -or $height -ne 560 -or $image.width -ne 404 -or $image.height -ne 560) {
            throw "Unexpected PNG dimensions: $id"
        }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $imagePath).Hash.ToLowerInvariant()
        if ($hash -cne $image.sha256) { throw "PNG hash mismatch: $id" }
    }
    elseif ($null -ne $record.convene_draw) {
        throw "Unexpected Convene Draw path for unavailable entry: $id"
    }
}

$files = @(Get-ChildItem -LiteralPath (Join-Path $root 'characters') -Filter data.json -File -Recurse)
if ($files.Count -ne 60) { throw "Expected 60 records, got $($files.Count)." }

"Validated 60 character records, $expectedImageCount exact Convene Draw PNG files, $expectedUnavailableCount documented gaps, manifests, normalized ids, provenance metadata, and strict UTF-8."
