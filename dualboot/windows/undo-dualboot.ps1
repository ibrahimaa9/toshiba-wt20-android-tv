# WT20 dual boot: puts Windows' boot setup back as it was before prepare-windows.ps1 (run as
# administrator; undo-dualboot.cmd does that). Removes the added firmware boot entry and the boot
# chooser from the EFI partition, and restores Windows Boot Manager's own path. Windows then
# boots directly. The Android partitions stay on the disk (delete them in Disk Management and
# extend C: to get the space back).
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
$work = 'C:\wt20-dualboot'
$done = @()

& bcdedit.exe /set '{bootmgr}' path '\EFI\Microsoft\Boot\bootmgfw.efi' | Out-Null
$done += "Windows Boot Manager path restored ($LASTEXITCODE)"

$guids = @()
$fw = (& bcdedit.exe /enum firmware) -join "`n"
foreach ($block in ($fw -split "`n\s*`n")) {
    if ($block -match 'Android TV \(WT20\)' -and $block -match '(\{[0-9a-fA-F-]{36}\})') { $guids += $Matches[1] }
}
foreach ($g in $guids) {
    & bcdedit.exe /delete $g | Out-Null
    $done += "boot entry $g deleted ($LASTEXITCODE)"
}

$letter = (71..90 | ForEach-Object { [char]$_ } | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -Last 1)
& mountvol.exe "$($letter):" /S
if ($LASTEXITCODE -eq 0) {
    if (Test-Path "$($letter):\EFI\wt20") {
        Remove-Item -Recurse -Force "$($letter):\EFI\wt20"
        $done += 'boot chooser removed from the EFI partition'
    }
    & mountvol.exe "$($letter):" /D
}
$done | ForEach-Object { Write-Host $_ }
if (Test-Path $work) { $done | Add-Content -Path (Join-Path $work 'undo-log.txt') -Encoding UTF8 }
$opt = [System.Windows.Forms.MessageBoxOptions]::RtlReading -bor [System.Windows.Forms.MessageBoxOptions]::RightAlign
[System.Windows.Forms.MessageBox]::Show("رجع إقلاع ويندوز مثل ما كان: التابلت يقلع ويندوز مباشرة.`n`nأقسام أندرويد بعدها على القرص. إذا تريد ترجّع مساحتها: «إدارة الأقراص» ← احذف أقسام أندرويد ← وسّع القرص C.", 'إلغاء الإقلاع المزدوج', 'OK', 'Information', 'Button1', $opt) | Out-Null
