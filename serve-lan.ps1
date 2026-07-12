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

$rootFull = [System.IO.Path]::GetFullPath($Root)
$rootBoundary = $rootFull.TrimEnd('\') + '\'

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
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 8192, $true)
      $requestLine = $reader.ReadLine()
      if ([string]::IsNullOrWhiteSpace($requestLine)) { continue }

      while (($line = $reader.ReadLine()) -ne $null -and $line -ne '') {}

      $parts = $requestLine.Split(' ')
      $method = $parts[0]
      $target = if ($parts.Length -gt 1) { $parts[1] } else { '/' }
      $headOnly = $method -eq 'HEAD'

      if ($method -ne 'GET' -and $method -ne 'HEAD') {
        Send-Response $stream '405 Method Not Allowed' ([System.Text.Encoding]::UTF8.GetBytes('Method not allowed'))
        continue
      }

      $urlPath = ($target -split '\?')[0]
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
