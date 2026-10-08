[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$htmlFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'html') -Filter '*.html' -File)
$violations = [System.Collections.Generic.List[string]]::new()

foreach ($file in $htmlFiles) {
  $content = Get-Content -Raw -LiteralPath $file.FullName
  foreach ($pattern in @('api\.dev\.example\.com', '(?:href|src)="/(?!api/)', '192\.168\.\d+\.\d+', 'local-minio-access-key', 'MINIO_ROOT_PASSWORD', 'e8280ac0d25d4bc0a1e1', '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', '(?i)w[v]')) {
    if ($content -match $pattern) { $violations.Add("$($file.Name): forbidden public-site content matched '$pattern'") }
  }
}

$download = Get-Content -Raw -LiteralPath (Join-Path $root 'html\download.html')
if ($download -notmatch "'/api/v1/client/releases/latest\?platform='") {
  $violations.Add('download.html: public release query must use the same-origin /api/v1 endpoint')
}
if ($download -notmatch "data\.storeUrl \|\| ''") {
  $violations.Add('download.html: store releases must fall back to the managed storeUrl')
}
if ($download -notmatch 'removeCache\(platform\)') {
  $violations.Add('download.html: an empty release response must invalidate stale release cache')
}
$cancel = Get-Content -Raw -LiteralPath (Join-Path $root 'html\cancel.html')
if ($cancel -notmatch "var API_BASE = '/api/v1';") {
  $violations.Add('cancel.html: account cancellation must use the same-origin /api/v1 endpoint')
}

if ($violations.Count -gt 0) { throw ($violations -join [Environment]::NewLine) }
Write-Host "Website validation passed: $($htmlFiles.Count) HTML files."
