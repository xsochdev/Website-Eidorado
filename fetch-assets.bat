@echo off
REM This .bat writes and runs a PowerShell script that downloads CSS and assets.
REM Save this file next to index.html and run it. It will create "css" and "assets" folders.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
" $ps = @'
# PowerShell script: fetch-css-and-assets.ps1
$index = 'index.html'
if (-not (Test-Path $index)) {
  Write-Host 'index.html not found in current folder. Place this .bat next to index.html and re-run.' -ForegroundColor Red
  exit 1
}
$cssDir = 'css'
$assetsDir = 'assets'
New-Item -ItemType Directory -Force -Path $cssDir, $assetsDir | Out-Null

Write-Host 'Reading' $index
$html = Get-Content $index -Raw

# Find external CSS hrefs (http/https)
$cssUrls = [regex]::Matches($html,'href\s*=\s*\"(https?://[^\"']+?\.css)\"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

if ($cssUrls.Count -eq 0) {
  Write-Host 'No external CSS URLs found in' $index -ForegroundColor Yellow
} else {
  Write-Host ('Found {0} CSS URL(s).' -f $cssUrls.Count)
}

$origMap = @{}  # localCssPath -> original URL

foreach ($url in $cssUrls) {
  try {
    $uri = [System.Uri]::new($url)
  } catch {
    Write-Host 'Invalid URL skipped:' $url -ForegroundColor Yellow
    continue
  }
  $fname = [IO.Path]::GetFileName($uri.AbsolutePath)
  if ([string]::IsNullOrEmpty($fname)) {
    # fallback name if URL ends with query only
    $fname = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($url)).Substring(0,16) + '.css'
  }
  $out = Join-Path $cssDir $fname
  Write-Host 'Downloading CSS:' $url '->' $out
  try {
    Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $out -ErrorAction Stop
  } catch {
    Write-Host 'Failed to download:' $url $_.Exception.Message -ForegroundColor Red
    continue
  }
  # Replace exact URL occurrences in index.html with relative path to css/<fname>
  $html = $html -replace [regex]::Escape($url), ('$cssDir' + '/' + $fname)
  $origMap[$out] = $url
}

# Save modified index.html
Set-Content -Path $index -Value $html -Encoding UTF8
Write-Host 'Updated' $index 'to reference local css files.'

# Process each downloaded CSS for url(...) references
foreach ($localCss in Get-ChildItem -Path $cssDir -Filter *.css -File) {
  $cssPath = $localCss.FullName
  Write-Host 'Scanning' $cssPath 'for assets...'
  $cssContent = Get-Content $cssPath -Raw
  $matches = [regex]::Matches($cssContent,'url\(\s*["'']?(.*?)["'']?\s*\)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

  foreach ($asset in $matches) {
    if ([string]::IsNullOrEmpty($asset)) { continue }
    if ($asset -like 'data:*') { Write-Host 'Skipping data URI'; continue }
    if ($asset.StartsWith('/')) {
      Write-Host ('Skipping root-relative asset: {0} (edit CSS manually if needed)' -f $asset) -ForegroundColor Yellow
      continue
    }

    $full = $asset
    if ($asset.StartsWith('//')) {
      $full = 'https:' + $asset
    } elseif ($asset -notmatch '^https?://') {
      # Resolve relative to original CSS URL if we have it
      $origUrl = $origMap[$cssPath]
      if (-not $origUrl) {
        Write-Host ('Cannot resolve relative asset {0} in {1} - no base URL found; skipping' -f $asset, $localCss.Name) -ForegroundColor Yellow
        continue
      }
      try {
        $baseUri = [System.Uri]::new($origUrl)
        $full = [System.Uri]::new($baseUri, $asset).AbsoluteUri
      } catch {
        Write-Host ('Failed to resolve {0} relative to {1}; skipping' -f $asset, $origUrl) -ForegroundColor Yellow
        continue
      }
    }

    try {
      $afname = [IO.Path]::GetFileName([System.Uri]::new($full).AbsolutePath)
    } catch {
      Write-Host 'Invalid asset URL, skipping:' $full -ForegroundColor Yellow
      continue
    }
    if ([string]::IsNullOrEmpty($afname)) {
      $afname = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($full)).Substring(0,12)
    }
    $aout = Join-Path $assetsDir $afname

    if (Test-Path $aout) {
      Write-Host 'Asset already exists:' $aout
    } else {
      Write-Host 'Downloading asset:' $full '->' $aout
      try {
        Invoke-WebRequest -Uri $full -UseBasicParsing -OutFile $aout -ErrorAction Stop
      } catch {
        Write-Host ('Failed to download asset: {0} — {1}' -f $full, $_.Exception.Message) -ForegroundColor Red
        continue
      }
    }

    # Replace asset path in CSS to point to ../assets/<afname> (css files are in css/)
    $cssContent = $cssContent -replace [regex]::Escape($asset), ('../' + $assetsDir + '/' + $afname)
  }

  # Save updated CSS
  Set-Content -Path $cssPath -Value $cssContent -Encoding UTF8
  Write-Host 'Updated CSS:' $cssPath
}

Write-Host 'All done. css/ and assets/ folders populated. index.html updated to use local css/* files.'
'@

# write PS1
Set-Content -Path './fetch-css-and-assets.ps1' -Value $ps -Encoding UTF8
# run it
Write-Host 'Running fetch-css-and-assets.ps1 ...' 
powershell -NoProfile -ExecutionPolicy Bypass -File './fetch-css-and-assets.ps1'
"

pause