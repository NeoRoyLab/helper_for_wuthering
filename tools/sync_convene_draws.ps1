$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = [System.Text.UTF8Encoding]::new($false)
$verifiedAt = '2026-10-02'

$unavailable = [ordered]@{
    jingran = 'No Convene Draw file was returned by the wiki API on 2026-08-29.'
    rover_aero = 'The wiki does not list a Rover character Convene Draw file.'
    rover_electro = 'The wiki does not list a Rover character Convene Draw file.'
    rover_havoc = 'The wiki does not list a Rover character Convene Draw file.'
    rover_spectro = 'The wiki does not list a Rover character Convene Draw file.'
    suoming = 'No Convene Draw file was returned by the wiki API on 2026-08-29.'
}

function Read-Json([string] $path) {
    return [System.IO.File]::ReadAllText($path, $utf8) | ConvertFrom-Json
}

function Write-Json([string] $path, [object] $value) {
    $json = $value | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, $utf8)
}

function Get-PngDimensions([byte[]] $bytes) {
    if ($bytes.Length -lt 24 -or
        $bytes[0] -ne 137 -or $bytes[1] -ne 80 -or $bytes[2] -ne 78 -or $bytes[3] -ne 71 -or
        $bytes[4] -ne 13 -or $bytes[5] -ne 10 -or $bytes[6] -ne 26 -or $bytes[7] -ne 10) {
        throw 'Downloaded file is not a PNG.'
    }

    $width = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 16))
    $height = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 20))
    return [PSCustomObject]@{ width = $width; height = $height }
}

$characterManifest = Read-Json (Join-Path $root 'manifests\characters.json')
$expected = New-Object System.Collections.Generic.List[object]
foreach ($id in $characterManifest.characters) {
    $recordPath = Join-Path $root "characters\$id\data.json"
    $record = Read-Json $recordPath
    if ($unavailable.Contains($id)) {
        continue
    }

    $displayName = [string]$record.name.en
    $wikiName = if ($id -eq 'the_shorekeeper') { 'Shorekeeper' } else { $displayName }
    $isHsin = $id -ceq 'hsin'
    $expected.Add([PSCustomObject]@{
        id = $id
        record_path = $recordPath
        wiki_file = $(if ($isHsin) { 'Hsin Full Sprite.png' } else { "$wikiName Convene Draw.png" })
        width = $(if ($isHsin) { 1440 } else { 404 })
        height = $(if ($isHsin) { 2016 } else { 560 })
    })
}

$wikiByTitle = @{}
for ($start = 0; $start -lt $expected.Count; $start += 50) {
    $end = [Math]::Min($start + 49, $expected.Count - 1)
    $titles = @($expected[$start..$end] | ForEach-Object { "File:$($_.wiki_file)" }) -join '|'
    $encodedTitles = [Uri]::EscapeDataString($titles)
    $apiUrl = "https://wutheringwaves.fandom.com/api.php?action=query&format=json&prop=imageinfo&iiprop=url%7Csize%7Cmime&titles=$encodedTitles"
    $apiJson = & curl.exe -L --fail --silent --show-error $apiUrl
    if ($LASTEXITCODE -ne 0) { throw 'The Wuthering Waves Wiki API request failed.' }
    $response = $apiJson | ConvertFrom-Json
    foreach ($page in $response.query.pages.PSObject.Properties.Value) {
        if ($null -eq $page.imageinfo -or $page.imageinfo.Count -ne 1) {
            throw "The exact wiki file is unavailable: $($page.title)"
        }

        $wikiByTitle[$page.title] = $page.imageinfo[0]
    }
}

$images = New-Object System.Collections.Generic.List[object]
foreach ($item in $expected) {
    $title = "File:$($item.wiki_file)"
    if (-not $wikiByTitle.ContainsKey($title)) { throw "Wiki response omitted $title" }
    $info = $wikiByTitle[$title]
    if ($info.mime -cne 'image/png' -or $info.width -ne $item.width -or $info.height -ne $item.height) {
        throw "Unexpected wiki image metadata for $($item.id): $($info.mime), $($info.width)x$($info.height)"
    }

    $relativePath = "characters/$($item.id)/convene_draw.png"
    $target = Join-Path $root ($relativePath.Replace('/', '\'))
    $needsDownload = $true
    if (Test-Path -LiteralPath $target) {
        try {
            $existingDimensions = Get-PngDimensions ([System.IO.File]::ReadAllBytes($target))
            $needsDownload = $existingDimensions.width -ne $item.width -or $existingDimensions.height -ne $item.height
        }
        catch {
            $needsDownload = $true
        }
    }
    if ($needsDownload) {
        $downloadUrl = [string]$info.url + $(if ([string]$info.url -match '\?') { '&format=original' } else { '?format=original' })
        & curl.exe -L --fail --silent --show-error --output $target $downloadUrl
        if ($LASTEXITCODE -ne 0) { throw "Image download failed for $($item.id)" }
    }

    $bytes = [System.IO.File]::ReadAllBytes($target)
    $dimensions = Get-PngDimensions $bytes
    if ($dimensions.width -ne $item.width -or $dimensions.height -ne $item.height) {
        throw "Downloaded PNG dimensions do not match the wiki metadata for $($item.id)."
    }

    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
    $images.Add([PSCustomObject][ordered]@{
        id = $item.id
        path = $relativePath
        wiki_file = $item.wiki_file
        width = $dimensions.width
        height = $dimensions.height
        sha256 = $sha256
    })
}

foreach ($id in $characterManifest.characters) {
    $recordPath = Join-Path $root "characters\$id\data.json"
    $record = Read-Json $recordPath
    $match = $images | Where-Object { $_.id -ceq $id } | Select-Object -First 1
    $path = if ($null -eq $match) { $null } else { $match.path }
    if ($record.PSObject.Properties.Name -contains 'convene_draw') {
        $record.convene_draw = $path
    }
    else {
        $record | Add-Member -NotePropertyName convene_draw -NotePropertyValue $path
    }
    if ($id -like 'rover_*') {
        if ($record.PSObject.Properties.Name -contains 'icon') { $record.icon = "characters/$id/icon.png" }
        else { $record | Add-Member -NotePropertyName icon -NotePropertyValue "characters/$id/icon.png" }
        if ($record.PSObject.Properties.Name -contains 'full_sprite') { $record.full_sprite = "characters/$id/full_sprite.png" }
        else { $record | Add-Member -NotePropertyName full_sprite -NotePropertyValue "characters/$id/full_sprite.png" }
    }
    Write-Json $recordPath $record
}

$missing = foreach ($entry in $unavailable.GetEnumerator()) {
    if ($entry.Key -like 'rover_*') { continue }
    [PSCustomObject][ordered]@{ id = $entry.Key; reason = $entry.Value }
}
$roverImages = New-Object System.Collections.Generic.List[object]
foreach ($id in @('rover_aero', 'rover_electro', 'rover_havoc', 'rover_spectro')) {
    foreach ($asset in @(
        @{ role = 'list_icon'; path = "characters/$id/icon.png"; wiki_file = 'Resonator Outfit Perpetual Spark.png' },
        @{ role = 'profile_full_sprite'; path = "characters/$id/full_sprite.png"; wiki_file = 'Rover 1.png' }
    )) {
        $assetPath = Join-Path $root $asset.path.Replace('/', '\')
        $bytes = [System.IO.File]::ReadAllBytes($assetPath)
        $dimensions = Get-PngDimensions $bytes
        $roverImages.Add([PSCustomObject][ordered]@{
            id = $id
            role = $asset.role
            path = $asset.path
            wiki_file = $asset.wiki_file
            width = $dimensions.width
            height = $dimensions.height
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $assetPath).Hash.ToLowerInvariant()
        })
    }
}
$imageManifest = [PSCustomObject][ordered]@{
    schema_version = 1
    source_site = 'Wuthering Waves Wiki'
    verified_at = $verifiedAt
    images = $images.ToArray()
    unavailable = @($missing)
    rover_images = $roverImages.ToArray()
}
Write-Json (Join-Path $root 'manifests\character_images.json') $imageManifest

$master = Read-Json (Join-Path $root 'manifest.json')
$charactersEntry = $master.manifests | Where-Object { $_.key -ceq 'characters' } | Select-Object -First 1
if ($null -eq $charactersEntry) { throw 'The master manifest has no characters entry.' }
$charactersEntry.version = 5
Write-Json (Join-Path $root 'manifest.json') $master

"Downloaded and indexed $($images.Count) exact Convene Draw PNG files; recorded $($missing.Count) unavailable entries."
