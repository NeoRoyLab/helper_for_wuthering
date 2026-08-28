$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Read-Json([string] $path) {
    $text = $strictUtf8.GetString([System.IO.File]::ReadAllBytes($path))
    return $text | ConvertFrom-Json
}

$master = Read-Json (Join-Path $root 'manifest.json')
$manifest = Read-Json (Join-Path $root 'manifests\characters.json')
if ($master.schema_version -ne 1) { throw 'Unexpected master schema version.' }
if ($manifest.schema_version -ne 1) { throw 'Unexpected character manifest schema version.' }
if ($manifest.characters.Count -ne 60) { throw "Expected 60 ids, got $($manifest.characters.Count)." }
if (($manifest.characters | Sort-Object -Unique).Count -ne 60) { throw 'Duplicate manifest ids.' }

$elements = @('aero', 'electro', 'fusion', 'glacio', 'havoc', 'spectro')
$weapons = @('broadblade', 'gauntlets', 'pistols', 'rectifier', 'sword')
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
}

$files = @(Get-ChildItem -LiteralPath (Join-Path $root 'characters') -Filter data.json -File -Recurse)
if ($files.Count -ne 60) { throw "Expected 60 records, got $($files.Count)." }

'Validated 60 character records, manifests, normalized ids, core fields, provenance metadata, and strict UTF-8.'
