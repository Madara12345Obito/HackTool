param(
  [int]$Port = 8080,
  [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

function Get-ContentType {
  param([string]$Path)
  switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    '.html' { 'text/html; charset=utf-8' }
    '.htm'  { 'text/html; charset=utf-8' }
    '.css'  { 'text/css; charset=utf-8' }
    '.js'   { 'application/javascript; charset=utf-8' }
    '.json' { 'application/json; charset=utf-8' }
    '.txt'  { 'text/plain; charset=utf-8' }
    '.svg'  { 'image/svg+xml' }
    '.png'  { 'image/png' }
    '.jpg'  { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.gif'  { 'image/gif' }
    '.ico'  { 'image/x-icon' }
    '.pdf'  { 'application/pdf' }
    default { 'application/octet-stream' }
  }
}

function Send-Response {
  param(
    [System.Net.Sockets.NetworkStream]$Stream,
    [string]$Status,
    [byte[]]$Body,
    [string]$ContentType = 'text/plain; charset=utf-8',
    [bool]$HeadOnly = $false
  )
  $headers = "HTTP/1.1 $Status`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`nCache-Control: no-store`r`n`r`n"
  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)
  if (-not $HeadOnly -and $Body.Length -gt 0) {
    $Stream.Write($Body, 0, $Body.Length)
  }
}

function Find-HeaderEnd {
  param([byte[]]$Bytes)
  for ($i = 0; $i -le $Bytes.Length - 4; $i++) {
    if ($Bytes[$i] -eq 13 -and $Bytes[$i + 1] -eq 10 -and $Bytes[$i + 2] -eq 13 -and $Bytes[$i + 3] -eq 10) {
      return $i
    }
  }
  return -1
}

function Read-HttpRequest {
  param([System.Net.Sockets.NetworkStream]$Stream)
  $memory = [System.IO.MemoryStream]::new()
  $buffer = New-Object byte[] 4096
  $headerEnd = -1

  while ($headerEnd -lt 0) {
    $read = $Stream.Read($buffer, 0, $buffer.Length)
    if ($read -le 0) { break }
    $memory.Write($buffer, 0, $read)
    if ($memory.Length -gt 65536) { throw 'Request headers too large' }
    $headerEnd = Find-HeaderEnd $memory.ToArray()
  }

  if ($headerEnd -lt 0) { return $null }

  $rawBytes = $memory.ToArray()
  $headerText = [System.Text.Encoding]::ASCII.GetString($rawBytes, 0, $headerEnd)
  $headerLines = $headerText -split "`r`n"
  if (-not $headerLines.Length) { return $null }

  $requestParts = $headerLines[0].Split(' ', 3, [System.StringSplitOptions]::RemoveEmptyEntries)
  if ($requestParts.Length -lt 2) { return $null }

  $headers = @{}
  $contentLength = 0
  for ($i = 1; $i -lt $headerLines.Length; $i++) {
    $line = $headerLines[$i]
    $colon = $line.IndexOf(':')
    if ($colon -le 0) { continue }
    $name = $line.Substring(0, $colon).Trim()
    $value = $line.Substring($colon + 1).Trim()
    $headers[$name] = $value
    if ($name -ieq 'Content-Length') {
      [int]::TryParse($value, [ref]$contentLength) | Out-Null
    }
  }

  $body = New-Object byte[] 0
  if ($contentLength -gt 0) {
    if ($contentLength -gt 5242880) { throw 'Request body too large' }
    $body = New-Object byte[] $contentLength
    $bodyStart = $headerEnd + 4
    $alreadyBuffered = [Math]::Max(0, $rawBytes.Length - $bodyStart)
    $copied = [Math]::Min($alreadyBuffered, $contentLength)
    if ($copied -gt 0) {
      [Array]::Copy($rawBytes, $bodyStart, $body, 0, $copied)
    }
    while ($copied -lt $contentLength) {
      $read = $Stream.Read($body, $copied, $contentLength - $copied)
      if ($read -le 0) { break }
      $copied += $read
    }
    if ($copied -lt $contentLength) { throw 'Incomplete request body' }
  }

  [pscustomobject]@{
    Method = $requestParts[0].ToUpperInvariant()
    Target = $requestParts[1]
    Headers = $headers
    Body = $body
  }
}

$rootFull = [System.IO.Path]::GetFullPath($Root)
$rootBoundary = $rootFull.TrimEnd('\') + '\'
$sharedStorePath = Join-Path $rootFull 'output\shared-editor-store.json'
$defaultSharedStore = '{"version":1,"edits":{},"deleted":[],"custom":[]}'

function Read-SharedStore {
  if (Test-Path -LiteralPath $sharedStorePath -PathType Leaf) {
    $text = [System.IO.File]::ReadAllText($sharedStorePath, [System.Text.Encoding]::UTF8).Trim()
    if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
  }
  return $defaultSharedStore
}

function Write-SharedStore {
  param([string]$Json)
  $dir = Split-Path -Parent $sharedStorePath
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  [System.IO.File]::WriteAllText($sharedStorePath, $Json, [System.Text.UTF8Encoding]::new($false))
}

function Handle-EditorStoreApi {
  param(
    [System.Net.Sockets.NetworkStream]$Stream,
    $Request,
    [bool]$HeadOnly
  )
  if ($Request.Method -eq 'GET' -or $Request.Method -eq 'HEAD') {
    Send-Response $Stream '200 OK' ([System.Text.Encoding]::UTF8.GetBytes((Read-SharedStore))) 'application/json; charset=utf-8' $HeadOnly
    return
  }
  if ($Request.Method -eq 'POST') {
    $json = [System.Text.Encoding]::UTF8.GetString($Request.Body).Trim()
    if ([string]::IsNullOrWhiteSpace($json)) {
      Send-Response $Stream '400 Bad Request' ([System.Text.Encoding]::UTF8.GetBytes('Empty body'))
      return
    }
    try {
      $null = $json | ConvertFrom-Json
      Write-SharedStore $json
      Send-Response $Stream '200 OK' ([System.Text.Encoding]::UTF8.GetBytes('{"ok":true}')) 'application/json; charset=utf-8'
    } catch {
      Send-Response $Stream '400 Bad Request' ([System.Text.Encoding]::UTF8.GetBytes('Invalid JSON'))
    }
    return
  }
  Send-Response $Stream '405 Method Not Allowed' ([System.Text.Encoding]::UTF8.GetBytes('Method not allowed')) -HeadOnly $HeadOnly
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
$listener.Start()

Write-Host "Serving $rootFull"
Write-Host "Local:   http://localhost:$Port/"
try {
  $ips = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -ExpandProperty IPAddress
  foreach ($ip in $ips) {
    Write-Host "Network: http://$ip`:$Port/"
  }
} catch {
  Write-Host "Network: run ipconfig and open http://YOUR_IPV4:$Port/ from another machine."
}
Write-Host "Press Ctrl+C to stop."

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $request = Read-HttpRequest $stream
      if ($null -eq $request) { continue }

      $method = $request.Method
      $target = if ($request.Target) { $request.Target } else { '/' }
      $headOnly = $method -eq 'HEAD'

      $urlPath = ($target -split '\?')[0]
      if ($urlPath -ieq '/api/editor-store') {
        Handle-EditorStoreApi $stream $request $headOnly
        continue
      }

      if ($method -ne 'GET' -and $method -ne 'HEAD') {
        Send-Response $stream '405 Method Not Allowed' ([System.Text.Encoding]::UTF8.GetBytes('Method not allowed')) -HeadOnly $headOnly
        continue
      }

      if ([string]::IsNullOrWhiteSpace($urlPath) -or $urlPath -eq '/') {
        $urlPath = '/index.html'
      }
      $relative = [Uri]::UnescapeDataString($urlPath).TrimStart('/').Replace('/', '\')
      $fullPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootFull, $relative))

      if (-not ($fullPath.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or $fullPath.StartsWith($rootBoundary, [System.StringComparison]::OrdinalIgnoreCase))) {
        Send-Response $stream '403 Forbidden' ([System.Text.Encoding]::UTF8.GetBytes('Forbidden')) -HeadOnly $headOnly
        continue
      }

      if ((Test-Path -LiteralPath $fullPath -PathType Container)) {
        $fullPath = [System.IO.Path]::Combine($fullPath, 'index.html')
      }

      if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        Send-Response $stream '404 Not Found' ([System.Text.Encoding]::UTF8.GetBytes('Not found')) -HeadOnly $headOnly
        continue
      }

      $body = [System.IO.File]::ReadAllBytes($fullPath)
      Send-Response $stream '200 OK' $body (Get-ContentType $fullPath) $headOnly
    } catch {
      try {
        Send-Response $stream '500 Internal Server Error' ([System.Text.Encoding]::UTF8.GetBytes('Internal server error'))
      } catch {}
    } finally {
      $client.Close()
    }
  }
} finally {
  $listener.Stop()
}
