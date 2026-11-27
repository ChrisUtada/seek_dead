<#
.SYNOPSIS
    run_smoke 日志闸门：退出码为 0 但日志里仍有失败信号时判失败。

.DESCRIPTION
    扫描 -LogDir 下的 -Pattern 日志（UTF-8 读取，不修改任何文件），命中任一即为违规：
      a) "SCRIPT ERROR"
      b) 正则 "RESULT\s+FAIL"                     （RESULT FAIL 连写）
      c) 正则 "FAILED\s+[1-9]"                    （PASSED x / FAILED y 格式）
      d) 数字在前 "\b[1-9]\d*\s+fails?\b"(其后不是 =0 / :0) （"1 fails" / "26 checks, 1 fails"）
         或 关键字在前 "\bfails?\s*[:=]\s*[1-9]\d*\b"（"fails=1" / "fails: 2"）
      e) 正则 "RESULT\s*[:：]\s*FAIL"          （"RESULT: FAIL"）
    0 fails / fails=0 不算违规。
    每行违规输出 "BAD  <文件名>:<行号>  <原文前 120 字符>"。
    有违规 exit 1；否则打印 "LOGCHECK: OK (<N> files)" 并 exit 0。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\check_smoke_logs.ps1 -LogDir "%TEMP%"
#>
param(
    [string]$LogDir = $env:TEMP,
    [string]$Pattern = "smoke_*.log"
)

$bad = 0
$badFiles = 0
# Build full-width colon from char codes: this script may be read with an ANSI codepage.
$reResultFail = '(?i)RESULT\s*[' + [char]0x3A + [char]0xFF1A + ']\s*FAIL'
$files = @(Get-ChildItem -Path (Join-Path $LogDir $Pattern) -File -ErrorAction SilentlyContinue | Sort-Object Name)

foreach ($f in $files) {
    $fileHits = 0
    $lines = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8)
    $lineNo = 0
    foreach ($line in $lines) {
        $lineNo++
        $isBad = $false
        if ($line.Contains("SCRIPT ERROR")) {
            $isBad = $true
        } elseif ($line -match 'RESULT\s+FAIL') {
            $isBad = $true
        } elseif ($line -match 'FAILED\s+[1-9]') {
            $isBad = $true
        } elseif ($line -match '(?i)\b[1-9]\d*\s+fails?\b(?!\s*[:=]\s*0\b)') {
            $isBad = $true
        } elseif ($line -match '(?i)\bfails?\s*[:=]\s*[1-9]\d*\b') {
            $isBad = $true
        } elseif ($line -match $reResultFail) {
            $isBad = $true
        }
        if ($isBad) {
            $excerpt = $line.Trim()
            if ($excerpt.Length -gt 120) {
                $excerpt = $excerpt.Substring(0, 120)
            }
            Write-Host ("BAD  {0}:{1}  {2}" -f $f.Name, $lineNo, $excerpt)
            $bad++
            $fileHits++
        }
    }
    if ($fileHits -gt 0) {
        $badFiles++
    }
}

if ($bad -gt 0) {
    Write-Host ("LOGCHECK: BAD ({0} hits in {1}/{2} files)" -f $bad, $badFiles, $files.Count)
    exit 1
}
Write-Host ("LOGCHECK: OK ({0} files)" -f $files.Count)
exit 0
