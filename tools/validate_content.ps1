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

$guideEntry = $master.manifests | Where-Object { $_.key -ceq 'guides' } | Select-Object -First 1
if ($null -eq $guideEntry -or $guideEntry.version -ne 1 -or $guideEntry.count -ne 57) {
    throw 'The master manifest guides entry is missing or invalid.'
}

$guideManifest = Read-Json (Join-Path $root 'manifests\guides.json')
$guideAssetManifest = Read-Json (Join-Path $root 'manifests\guide_assets.json')
if ($guideManifest.schema_version -ne 1 -or $guideAssetManifest.schema_version -ne 1) {
    throw 'Unexpected guide manifest schema version.'
}
if ($guideManifest.guides.Count -ne 57 -or $guideManifest.weapons.Count -ne 72 -or $guideManifest.echo_sets.Count -ne 29) {
    throw 'Unexpected guide, weapon, or Echo Set manifest count.'
}
if (($guideManifest.guides | Sort-Object -Unique).Count -ne 57 -or
    ($guideManifest.weapons | Sort-Object -Unique).Count -ne 72 -or
    ($guideManifest.echo_sets | Sort-Object -Unique).Count -ne 29) {
    throw 'Duplicate guide content identifier.'
}
$expectedGuideGaps = @('hsin', 'jingran', 'suoming')
if ($guideManifest.unavailable.Count -ne 3 -or
    @(Compare-Object $expectedGuideGaps @($guideManifest.unavailable.id)).Count -ne 0) {
    throw 'The Prydwen guide gaps are not documented exactly.'
}

$guideWeaponById = @{}
foreach ($id in $guideManifest.weapons) {
    if ($id -cnotmatch '^[a-z0-9]+(?:_[a-z0-9]+)*$') { throw "Invalid weapon content id: $id" }
    $recordPath = Join-Path $root "weapons\$id\data.json"
    if (-not (Test-Path -LiteralPath $recordPath)) { throw "Missing weapon content record: $id" }
    $record = Read-Json $recordPath
    if ($record.schema_version -ne 1 -or $record.id -cne $id -or [string]::IsNullOrWhiteSpace($record.name.en)) {
        throw "Invalid weapon content record: $id"
    }
    if ($record.rarity -notin @(3, 4, 5) -or $record.weapon_type -notin $weapons) {
        throw "Invalid wiki weapon metadata: $id"
    }
    $expectedPath = "weapons/$id/icon.png"
    if ($record.icon -cne $expectedPath -or $record.source.site -cne 'Wuthering Waves Wiki' -or
        $record.source.verified_at -cne '2026-08-29' -or $record.source.revision_id -le 0 -or
        $record.source.page_url -notlike 'https://wutheringwaves.fandom.com/wiki/*') {
        throw "Invalid weapon provenance or icon path: $id"
    }
    $guideWeaponById[$id] = $record
}

$echoSetById = @{}
foreach ($id in $guideManifest.echo_sets) {
    if ($id -cnotmatch '^[a-z0-9]+(?:_[a-z0-9]+)*$') { throw "Invalid Echo Set content id: $id" }
    $recordPath = Join-Path $root "echo_sets\$id\data.json"
    if (-not (Test-Path -LiteralPath $recordPath)) { throw "Missing Echo Set content record: $id" }
    $record = Read-Json $recordPath
    if ($record.schema_version -ne 1 -or $record.id -cne $id -or [string]::IsNullOrWhiteSpace($record.name.en)) {
        throw "Invalid Echo Set content record: $id"
    }
    if ($record.bonuses.Count -lt 1 -or ($record.bonuses.pieces | Sort-Object -Unique).Count -ne $record.bonuses.Count) {
        throw "Invalid Echo Set bonus list: $id"
    }
    foreach ($bonus in $record.bonuses) {
        if ($bonus.pieces -notin @(1, 2, 3, 5) -or [string]::IsNullOrWhiteSpace($bonus.text) -or
            $bonus.text -match '\{\{|\}\}|\[\[|\]\]|<[^>]+>') {
            throw "Invalid plain-text Echo Set bonus: $id"
        }
    }
    $expectedPath = "echo_sets/$id/icon.png"
    if ($record.icon -cne $expectedPath -or $record.source.site -cne 'Wuthering Waves Wiki' -or
        $record.source.verified_at -cne '2026-08-29' -or $record.source.revision_id -le 0 -or
        $record.source.page_url -notlike 'https://wutheringwaves.fandom.com/wiki/*') {
        throw "Invalid Echo Set provenance or icon path: $id"
    }
    $echoSetById[$id] = $record
}

foreach ($id in $guideManifest.guides) {
    if ($id -notin $manifest.characters) { throw "Guide references an unknown character: $id" }
    $recordPath = Join-Path $root "guides\$id\data.json"
    if (-not (Test-Path -LiteralPath $recordPath)) { throw "Missing guide record: $id" }
    $record = Read-Json $recordPath
    if ($record.schema_version -ne 1 -or $record.character_id -cne $id -or
        $record.weapons.Count -lt 1 -or $record.weapons.Count -gt 5) {
        throw "Invalid guide record: $id"
    }
    foreach ($weapon in $record.weapons) {
        if (-not $guideWeaponById.ContainsKey([string]$weapon.content_id) -or $weapon.rank -lt 1 -or $weapon.rank -gt 5) {
            throw "Invalid guide weapon reference: $id"
        }
    }
    if (-not $echoSetById.ContainsKey([string]$record.echo_set_id)) { throw "Invalid guide Echo Set reference: $id" }
    $wikiEchoName = [string]$echoSetById[[string]$record.echo_set_id].name.en
    if ($record.echo_set_source_name -cne $wikiEchoName -and
        -not ($record.echo_set_source_name -ceq 'Endless Resonance' -and $wikiEchoName -ceq 'Lingering Tunes')) {
        throw "Undocumented Prydwen/wiki Echo Set name mismatch: $id"
    }
    $expectedSourceUrl = 'https://www.prydwen.gg/wuthering-waves/characters/' + $id.Replace('_', '-')
    if ($record.source.site -cne 'Prydwen.gg' -or $record.source.page_url -cne $expectedSourceUrl -or
        $record.source.verified_at -cne '2026-08-29' -or $record.source.page_last_updated -notmatch '^2026-\d{2}-\d{2}$') {
        throw "Invalid guide provenance: $id"
    }
}

if ($guideAssetManifest.source_site -cne 'Wuthering Waves Wiki' -or
    $guideAssetManifest.verified_at -cne '2026-08-29' -or $guideAssetManifest.images.Count -ne 101) {
    throw 'Invalid guide asset manifest metadata.'
}
$assetByPath = @{}
foreach ($asset in $guideAssetManifest.images) {
    if ($asset.kind -notin @('weapon', 'echo_set') -or $assetByPath.ContainsKey([string]$asset.path)) {
        throw "Invalid or duplicate guide asset: $($asset.path)"
    }
    $assetByPath[[string]$asset.path] = $asset
    $path = Join-Path $root ([string]$asset.path).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing guide PNG: $($asset.path)" }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 24 -or $bytes[0] -ne 137 -or $bytes[1] -ne 80 -or $bytes[2] -ne 78 -or $bytes[3] -ne 71) {
        throw "Invalid guide PNG signature: $($asset.path)"
    }
    $width = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 16))
    $height = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 20))
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($asset.width -ne $width -or $asset.height -ne $height -or $asset.sha256 -cne $hash) {
        throw "Guide PNG metadata mismatch: $($asset.path)"
    }
}

foreach ($record in $guideWeaponById.Values) {
    if (-not $assetByPath.ContainsKey([string]$record.icon)) { throw "Weapon icon omitted from asset manifest: $($record.id)" }
}
foreach ($record in $echoSetById.Values) {
    if (-not $assetByPath.ContainsKey([string]$record.icon)) { throw "Echo Set icon omitted from asset manifest: $($record.id)" }
}

$guideFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'guides') -Filter data.json -File -Recurse)
$weaponFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'weapons') -Filter data.json -File -Recurse)
$echoSetFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'echo_sets') -Filter data.json -File -Recurse)
if ($guideFiles.Count -ne 57 -or $weaponFiles.Count -ne 72 -or $echoSetFiles.Count -ne 29) {
    throw 'Unexpected generated guide content file count.'
}

"Validated 60 character records, $expectedImageCount character PNGs, 57 guides, 72 wiki weapon records, 29 wiki Echo Sets, 101 exact guide PNGs, documented gaps, provenance, references, hashes, and strict UTF-8."
