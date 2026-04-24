# fetch-css-and-assets-fixed.ps1
param(
  [string]$IndexFile = "index.html",
  [string]$CssDir = "css",
  [string]$AssetsDir = "assets"
)

function Write-Err([string]$m){ Write-Host $m -ForegroundColor Red }
function Write-Warn([string]$m){ Write-Host $m -ForegroundColor Yellow }
function Write-OK([string]$m){ Write-Host $m -ForegroundColor Green }

if (-not (Test-Path $IndexFile)) {
  Write-Err "Could not find '$IndexFile' in current directory: $(Get-Location)"
  exit 1
}

# Backup index.html (again) just in case
$backup = "$IndexFile.bak2"
Copy-Item -Path $IndexFile -Destination $backup -Force
Write-OK "Backed up $IndexFile -> $backup"

New-Item -ItemType Directory -Force -Path $CssDir, $AssetsDir | Out-Null

$html = Get-Content -Path $IndexFile -Raw -ErrorAction Stop

# Better pattern: match a single <link ...> tag and capture the href that ends with .css
# This avoids spanning multiple tags when many links are on one line.
$linkPattern = @'
<link\b[^>]*\bhref\s*=\s*(?:"(?<u>[^"]+?\.css(?:\?[^"]*)?)|'(?<u>[^']+?\.css(?:\?[^']*)?)|(?<u2>[^>\s]+?\.css(?:\?[^>\s]*)?))[^>]*>
'@ 

$matches = [System.Text.RegularExpressions.Regex]::Matches($html, $linkPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

if ($matches.Count -eq 0) {
  Write-Warn "No external .css hrefs found in $IndexFile"
} else {
  Write-OK "Found $($matches.Count) CSS link(s)."
}

# Map local css path -> original URL
$cssOriginMap = @{}

foreach ($m in $matches) {
  $url = $m.Groups['u'].Value
  if (-not $url) { $url = $m.Groups['u2'].Value }
  if ($url.StartsWith("//")) { $url = "https:$url" }

  # Only process http/https URLs (skip data:, blob:, mailto:, root-relative /...)
  if (-not ($url -match '^https?://')) {
    Write-Warn "Skipping non-http(s) CSS href: $url"
    continue
  }

  try {
    $uri = [System.Uri]::new($url)
  } catch {
    Write-Warn "Skipping invalid URL: $url"
    continue
  }

  $fname = [IO.Path]::GetFileName($uri.AbsolutePath)
  if ([string]::IsNullOrEmpty($fname)) {
    $fname = ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($url))).Substring(0,16) + ".css"
  }

  $localCssPath = Join-Path $CssDir $fname
  Write-Host "Downloading CSS: $url -> $localCssPath"
  try {
    Invoke-WebRequest -Uri $url -OutFile $localCssPath -UseBasicParsing -ErrorAction Stop
    $cssOriginMap[$localCssPath] = $url
  } catch {
    Write-Err "Failed to download $url : $($_.Exception.Message)"
    continue
  }

  # Replace exact occurrences of the original url in index.html with local path css/<fname>
  $html = $html -replace [regex]::Escape($url), ($CssDir + "/" + $fname)
}

# Save modified index.html
Set-Content -Path $IndexFile -Value $html -Encoding UTF8
Write-OK "Updated $IndexFile to reference local CSS files."

# Regex for url(...) occurrences (no literal quotes in string)
$assetUrlPattern = 'url\(\s*["' + "'" + ']?(?<p>[^)"' + "'" + ']+)["' + "'" + ']?\s*\)'

Get-ChildItem -Path $CssDir -Filter *.css -File | ForEach-Object {
  $cssFile = $_.FullName
  Write-Host "Scanning CSS: $cssFile"
  $content = Get-Content -Path $cssFile -Raw -ErrorAction Stop

  $assetMatches = [System.Text.RegularExpressions.Regex]::Matches($content, $assetUrlPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

  foreach ($am in $assetMatches) {
    $asset = $am.Groups['p'].Value
    if ([string]::IsNullOrEmpty($asset)) { continue }
    if ($asset -like 'data:*') { Write-Host "  Skipping data URI"; continue }
    if ($asset.StartsWith("/")) {
      Write-Warn "  Skipping root-relative asset: $asset (manual handling may be required)"
      continue
    }

    # Resolve absolute URL for the asset
    if ($asset.StartsWith("//")) { $assetUrl = "https:$asset" }
    elseif ($asset -match '^https?://') { $assetUrl = $asset }
    else {
      $origUrl = $null
      if ($cssOriginMap.ContainsKey($cssFile)) { $origUrl = $cssOriginMap[$cssFile] }
      if (-not $origUrl) {
        Write-Warn "  Cannot resolve relative asset '$asset' in $cssFile because original CSS URL is unknown. Skipping."
        continue
      }
      try {
        $baseUri = [System.Uri]::new($origUrl)
        $assetUrl = [System.Uri]::new($baseUri, $asset).AbsoluteUri
      } catch {
        Write-Warn "  Failed to resolve '$asset' relative to $origUrl. Skipping."
        continue
      }
    }

    try {
      $assetUri = [System.Uri]::new($assetUrl)
      $afname = [IO.Path]::GetFileName($assetUri.AbsolutePath)
      if ([string]::IsNullOrEmpty($afname)) {
        $afname = ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($assetUrl))).Substring(0,12)
      }
    } catch {
      Write-Warn "  Invalid asset URL: $assetUrl"
      continue
    }

    $assetLocal = Join-Path $AssetsDir $afname
    if (-not (Test-Path $assetLocal)) {
      Write-Host "  Downloading asset: $assetUrl -> $assetLocal"
      try {
        Invoke-WebRequest -Uri $assetUrl -OutFile $assetLocal -UseBasicParsing -ErrorAction Stop
      } catch {
        Write-Err "  Failed to download asset $assetUrl : $($_.Exception.Message)"
        continue
      }
    } else {
      Write-Host "  Asset already exists: $assetLocal"
    }

    $newPath = "../$AssetsDir/$afname"
    $escapedAsset = [regex]::Escape($asset)
    $content = [System.Text.RegularExpressions.Regex]::Replace($content, $escapedAsset, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) return $newPath }, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  }

  Set-Content -Path $cssFile -Value $content -Encoding UTF8
  Write-OK "  Updated CSS: $cssFile"
}

Write-OK "Done. CSS files are in '$CssDir' and assets are in '$AssetsDir'. Please serve the site and check DevTools for any 404s."