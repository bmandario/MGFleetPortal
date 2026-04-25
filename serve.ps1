$port = 8000
$root = (Get-Location).Path

$mime = @{
  '.html' = 'text/html; charset=utf-8'
  '.htm'  = 'text/html; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.js'   = 'application/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.png'  = 'image/png'
  '.jpg'  = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.gif'  = 'image/gif'
  '.svg'  = 'image/svg+xml'
  '.ico'  = 'image/x-icon'
  '.mp4'  = 'video/mp4'
  '.webm' = 'video/webm'
  '.txt'  = 'text/plain; charset=utf-8'
  '.woff' = 'font/woff'
  '.woff2'= 'font/woff2'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Prefixes.Add("http://127.0.0.1:$port/")
try { $listener.Start() } catch {
  Write-Output "Failed to start listener: $_"
  exit 1
}

Write-Output "MG Fleet preview server running."
Write-Output "Open: http://localhost:$port/"
Write-Output "Press Ctrl+C in this window to stop."

while ($listener.IsListening) {
  try { $context = $listener.GetContext() } catch { break }
  $req = $context.Request
  $res = $context.Response

  try {
    $rawPath = [Uri]::UnescapeDataString($req.Url.LocalPath).TrimStart('/')
    $full = if ([string]::IsNullOrEmpty($rawPath)) { $root } else { Join-Path $root $rawPath }
    if (Test-Path $full -PathType Container) { $full = Join-Path $full 'index.html' }

    if (-not (Test-Path $full -PathType Leaf)) {
      $res.StatusCode = 404
      $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $rawPath")
      $res.ContentType = 'text/plain; charset=utf-8'
      $res.ContentLength64 = $msg.Length
      $res.OutputStream.Write($msg, 0, $msg.Length)
    } else {
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      $ct = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
      $res.ContentType = $ct
      $res.Headers.Add('Accept-Ranges', 'bytes')
      $res.Headers.Add('Cache-Control', 'no-cache')

      $fs = [System.IO.File]::Open($full, 'Open', 'Read', 'ReadWrite')
      try {
        $totalLen = $fs.Length
        $rangeHeader = $req.Headers['Range']
        $start = 0
        $end = $totalLen - 1

        if ($rangeHeader -and $rangeHeader -match 'bytes=(\d*)-(\d*)') {
          $rs = $matches[1]; $re = $matches[2]
          if ($rs -ne '') { $start = [int64]$rs }
          if ($re -ne '') { $end = [int64]$re }
          if ($end -ge $totalLen) { $end = $totalLen - 1 }
          $res.StatusCode = 206
          $res.Headers.Add('Content-Range', "bytes $start-$end/$totalLen")
        }

        $length = $end - $start + 1
        $res.ContentLength64 = $length
        $fs.Seek($start, 'Begin') | Out-Null
        $buf = New-Object byte[] 65536
        $remaining = $length
        while ($remaining -gt 0) {
          $toRead = [Math]::Min($buf.Length, $remaining)
          $read = $fs.Read($buf, 0, $toRead)
          if ($read -le 0) { break }
          $res.OutputStream.Write($buf, 0, $read)
          $remaining -= $read
        }
      } finally {
        $fs.Close()
      }
    }
  } catch {
    try { $res.StatusCode = 500 } catch {}
  } finally {
    try { $res.Close() } catch {}
  }

  Write-Output "$($req.HttpMethod) $($req.Url.LocalPath) -> $($res.StatusCode)"
}
