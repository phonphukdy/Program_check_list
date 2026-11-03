# PC health check - READ ONLY (does not change or delete anything)
# Run:  irm https://raw.githubusercontent.com/YOU/REPO/main/check.ps1 | iex

# ================= CONFIG: edit this block only =================
$RequiredApps      = @('Google Chrome', 'Microsoft Office', 'Adobe Acrobat', '7-Zip')  # partial name match
$RequiredLanguages = @('th-TH', 'en-US')                                                # keyboard/language tags
$FolderLimits      = @(
    @{ Path = "$env:USERPROFILE\Documents"; MaxFiles = 20 },
    @{ Path = "$env:USERPROFILE\Downloads"; MaxFiles = 5  },
    @{ Path = 'D:\';                        MaxFiles = 50 }
)
$ReportFolder      = $env:TEMP    # e.g. '\\server\reports' to collect from all PCs
# ================================================================

$results = New-Object System.Collections.Generic.List[object]
function Add-Result($status, $name, $detail) {
    $results.Add([pscustomobject]@{ Computer = $env:COMPUTERNAME; User = $env:USERNAME; Status = $status; Check = $name; Detail = $detail })
    $color = @{ PASS = 'Green'; FAIL = 'Red'; WARN = 'Yellow'; INFO = 'Cyan' }[$status]
    Write-Host ("[{0}] {1} - {2}" -f $status, $name, $detail) -ForegroundColor $color
}

# --- Windows version ---
$os  = Get-CimInstance Win32_OperatingSystem
$ver = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
Add-Result 'INFO' 'Windows' "$($os.Caption) $ver (build $($os.BuildNumber))"

# --- Installed programs (system + 32-bit + current user) ---
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
$installed = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object DisplayName | Select-Object -ExpandProperty DisplayName
foreach ($app in $RequiredApps) {
    $hit = $installed | Where-Object { $_ -like "*$app*" } | Select-Object -First 1
    if ($hit) { Add-Result 'PASS' "App: $app" $hit } else { Add-Result 'FAIL' "App: $app" 'not installed' }
}

# --- Languages ---
$langs = (Get-WinUserLanguageList).LanguageTag
foreach ($l in $RequiredLanguages) {
    if ($langs -contains $l) { Add-Result 'PASS' "Language: $l" 'present' } else { Add-Result 'FAIL' "Language: $l" "missing (have: $($langs -join ', '))" }
}

# --- Folders that should be clean (counts files recursively; D: may be slow if large) ---
foreach ($f in $FolderLimits) {
    if (-not (Test-Path $f.Path)) { Add-Result 'WARN' "Folder: $($f.Path)" 'path not found'; continue }
    $count = @(Get-ChildItem $f.Path -File -Recurse -Force -ErrorAction SilentlyContinue).Count
    if ($count -le $f.MaxFiles) { Add-Result 'PASS' "Folder: $($f.Path)" "$count files (max $($f.MaxFiles))" }
    else                        { Add-Result 'FAIL' "Folder: $($f.Path)" "$count files (max $($f.MaxFiles))" }
}

# --- Summary + report file ---
$fail = @($results | Where-Object Status -eq 'FAIL').Count
$pass = @($results | Where-Object Status -eq 'PASS').Count
Write-Host "`nSummary: $pass passed, $fail failed" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })

try {
    $file = Join-Path $ReportFolder ("{0}-{1:yyyyMMdd-HHmm}.csv" -f $env:COMPUTERNAME, (Get-Date))
    $results | Export-Csv $file -NoTypeInformation -Encoding UTF8
    Write-Host "Report saved: $file"
} catch {
    Write-Host "Could not save report: $($_.Exception.Message)" -ForegroundColor Yellow
}
