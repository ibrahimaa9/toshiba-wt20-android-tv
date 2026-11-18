# WT20 dual boot, step 1 (run on the tablet's Windows, as administrator; prepare-windows.cmd does
# that): gets this Windows ready for Android TV to be installed next to it.
#   1. checks: UEFI + GPT disk, BitLocker protection off
#   2. turns hibernation / fast startup off and keeps the hardware clock in UTC (as Android does)
#   3. shrinks C: by 40 GB, leaving that space unallocated for Android (nothing is deleted)
#   4. copies the small boot chooser (grubx64.efi) to Windows' EFI partition and adds a firmware
#      boot entry for it in front of Windows Boot Manager, which stays as it is. The chooser starts
#      Android when it is installed and Windows otherwise, so Windows boots as before until then.
#      Skipped while Secure Boot is on (the chooser is not signed): turn it off, run this again.
# Safe to run more than once. undo-dualboot.cmd removes the boot entry and the chooser.
param([switch]$UseBootmgrPath, [int]$AndroidGB = 40)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$work = 'C:\wt20-dualboot'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$logFile = Join-Path $work 'prepare-log.txt'
$entryName = 'Android TV (WT20)'
$efiRel = '\EFI\wt20\grubx64.efi'

function Log($t) {
    $line = '{0}  {1}' -f (Get-Date -Format 'HH:mm:ss'), $t
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

function Ask($text, $buttons = 'OK', $icon = 'Information') {
    $opt = [System.Windows.Forms.MessageBoxOptions]::RtlReading -bor [System.Windows.Forms.MessageBoxOptions]::RightAlign
    return [System.Windows.Forms.MessageBox]::Show($text, 'تجهيز ويندوز لأندرويد TV', $buttons, $icon, 'Button1', $opt)
}

function Stop-With($text) {
    Log "STOP: $text"
    Ask $text 'OK' 'Error' | Out-Null
    exit 1
}

$report = New-Object System.Collections.Generic.List[string]
try {
    Log "==== prepare-windows $(Get-Date -Format 'yyyy-MM-dd')  (log: $logFile)"

    # ---- 1. checks
    $cs = Get-CimInstance Win32_ComputerSystem
    Log "model: $($cs.Manufacturer) $($cs.Model)"
    if ($cs.Model -notmatch 'WT20') {
        if ((Ask "هذا الجهاز ($($cs.Model)) مو تابلت WT20. السكربت معمول لهذا التابلت فقط.`n`nتريد تكمّل على مسؤوليتك؟" 'YesNo' 'Warning') -ne 'Yes') { exit 1 }
    }
    if ($env:firmware_type -ne 'UEFI') { Stop-With 'ويندوز هذا مو مقلع بوضع UEFI، والإقلاع المزدوج يحتاج UEFI.' }
    $partC = Get-Partition -DriveLetter C
    $disk = Get-Disk -Number $partC.DiskNumber
    Log "disk $($disk.Number): $($disk.FriendlyName), $([math]::Round($disk.Size/1GB,1)) GB, $($disk.PartitionStyle)"
    if ($disk.PartitionStyle -ne 'GPT') { Stop-With 'القرص مو بتقسيم GPT.' }
    Get-Partition -DiskNumber $disk.Number | ForEach-Object {
        Log ("  partition {0}: {1,8:N0} MB  {2}  {3}" -f $_.PartitionNumber, ($_.Size/1MB), $_.Type, $_.DriveLetter)
    }

    $bl = $null
    try { $bl = Get-BitLockerVolume -MountPoint 'C:' } catch { Log "BitLocker state not readable: $($_.Exception.Message)" }
    if ($bl) {
        Log "BitLocker: protection $($bl.ProtectionStatus), volume $($bl.VolumeStatus)"
        if ("$($bl.ProtectionStatus)" -eq 'On') {
            Stop-With "تشفير BitLocker شغّال على القرص C.`n`nطفّيه أول من: الإعدادات ← التحديث والأمان ← تشفير الجهاز (أو لوحة التحكم ← BitLocker ← إيقاف)، وانتظر يخلص فك التشفير، وبعدها شغّل هذا الملف مرة ثانية."
        }
    }

    $secureBoot = $false
    try { $secureBoot = [bool](Confirm-SecureBootUEFI) } catch { Log "Secure Boot state not readable: $($_.Exception.Message)" }
    Log "Secure Boot: $secureBoot"

    # ---- 2. hibernation / fast startup off, clock in UTC
    & powercfg.exe /h off
    Log "powercfg /h off -> $LASTEXITCODE"
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name RealTimeIsUniversal -Value 1 -PropertyType DWord -Force | Out-Null
    $report.Add('✔ السبات والإقلاع السريع مطفيات، والساعة مضبوطة ويه أندرويد')

    # ---- 3. free space for Android
    $want = [int64]$AndroidGB * 1GB
    $minimum = 24GB + 512MB
    $disk = Get-Disk -Number $disk.Number
    Log "largest free extent: $([math]::Round($disk.LargestFreeExtent/1GB,2)) GB"
    if ($disk.LargestFreeExtent -ge ($want - 1GB)) {
        $report.Add("✔ المساحة الفارغة موجودة أصلاً: $([math]::Round($disk.LargestFreeExtent/1GB,1)) كيكا")
    } else {
        $sup = Get-PartitionSupportedSize -DriveLetter C
        $vol = Get-Volume -DriveLetter C
        $maxShrink = $partC.Size - $sup.SizeMin
        Log "C: size $([math]::Round($partC.Size/1GB,2)) GB, free $([math]::Round($vol.SizeRemaining/1GB,2)) GB, can shrink by $([math]::Round($maxShrink/1GB,2)) GB"
        if ($maxShrink -lt $want) {
            Log 'consolidating free space (defrag /X), this can take several minutes'
            & defrag.exe C: /X | Out-Null
            $sup = Get-PartitionSupportedSize -DriveLetter C
            $maxShrink = $partC.Size - $sup.SizeMin
            Log "after defrag: can shrink by $([math]::Round($maxShrink/1GB,2)) GB"
        }
        $shrink = $want
        if ($maxShrink -lt $want) {
            if ($maxShrink -lt $minimum) {
                Stop-With "ما أكدر أفرّغ مساحة كافية من القرص C.`n`nالمتاح للتصغير: $([math]::Round($maxShrink/1GB,1)) كيكا، والمطلوب 24 كيكا على الأقل.`nالمساحة الفارغة بويندوز: $([math]::Round($vol.SizeRemaining/1GB,1)) كيكا.`n`nامسح ملفات أو برامج من ويندوز وشغّل هذا الملف مرة ثانية."
            }
            $shrink = [int64]([math]::Floor(($maxShrink - 256MB) / 1GB)) * 1GB
            if ((Ask "ويندوز يسمح بتصغير القرص C بـ $([math]::Round($shrink/1GB)) كيكا فقط (مو $AndroidGB).`n`nأكمّل وأنطي أندرويد $([math]::Round($shrink/1GB)) كيكا؟" 'YesNo' 'Question') -ne 'Yes') { exit 1 }
        }
        if (($vol.SizeRemaining - $shrink) -lt 6GB) {
            if ((Ask "بعد التصغير يبقى بويندوز أقل من 6 كيكا فارغة، وهذا يضيّقه.`n`nأكمّل؟" 'YesNo' 'Warning') -ne 'Yes') { exit 1 }
        }
        $newSize = $partC.Size - $shrink
        Log "shrinking C: from $($partC.Size) to $newSize bytes"
        Resize-Partition -DriveLetter C -Size $newSize
        $disk = Get-Disk -Number $disk.Number
        Log "largest free extent now: $([math]::Round($disk.LargestFreeExtent/1GB,2)) GB"
        if ($disk.LargestFreeExtent -lt $minimum) { Stop-With 'التصغير ما طلّع المساحة المتوقعة. شوف السجل C:\wt20-dualboot\prepare-log.txt' }
        $report.Add("✔ القرص C تصغّر، وانحجزت $([math]::Round($disk.LargestFreeExtent/1GB,1)) كيكا لأندرويد (ما انمسح شي)")
    }

    # ---- 4. boot chooser on the EFI system partition + firmware boot entry
    $stub = Join-Path $here 'grubx64.efi'
    if (-not (Test-Path $stub)) { Stop-With "الملف grubx64.efi مو موجود بجانب السكربت ($here)." }
    if ($secureBoot) {
        $report.Add('✖ Secure Boot بعده شغّال: ما ضفت خيار الإقلاع. طفّيه من إعدادات الـBIOS وشغّل هذا الملف مرة ثانية')
    } else {
        $letter = (71..90 | ForEach-Object { [char]$_ } | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -Last 1)
        & mountvol.exe "$($letter):" /S
        if ($LASTEXITCODE -ne 0) { Stop-With 'ما كدرت أفتح قسم الإقلاع (EFI).' }
        try {
            $espFree = (New-Object System.IO.DriveInfo("$($letter):\")).AvailableFreeSpace
            Log "EFI system partition mounted at $($letter):, free $([math]::Round($espFree/1MB,1)) MB"
            if ($espFree -lt 6MB) { Stop-With 'قسم الإقلاع (EFI) ممتلي وما بيه مكان لملف الإقلاع.' }
            $dstDir = "$($letter):\EFI\wt20"
            New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
            Copy-Item -Path $stub -Destination "$dstDir\grubx64.efi" -Force
            if ((Get-FileHash $stub).Hash -ne (Get-FileHash "$dstDir\grubx64.efi").Hash) { Stop-With 'نسخ ملف الإقلاع فشل (الملف المنسوخ مختلف).' }
            Log "copied grubx64.efi to $dstDir"
        } finally {
            & mountvol.exe "$($letter):" /D
        }

        if ($UseBootmgrPath) {
            # Fallback for firmware that ignores added entries: Windows Boot Manager's own entry
            # starts the chooser (undo-dualboot.cmd puts the path back)
            & bcdedit.exe /set '{bootmgr}' path $efiRel
            Log "bcdedit {bootmgr} path -> $LASTEXITCODE"
            if ($LASTEXITCODE -ne 0) { Stop-With 'تعديل خيار الإقلاع فشل (bcdedit).' }
            $report.Add('✔ خيار الإقلاع الأساسي صار يشغّل قائمة الاختيار (الطريقة البديلة)')
        } else {
            $guid = $null
            $entryFile = Join-Path $work 'entry.txt'
            $fw = (& bcdedit.exe /enum firmware) -join "`n"
            foreach ($block in ($fw -split "`n\s*`n")) {
                if ($block -match [regex]::Escape($entryName) -and $block -match '(\{[0-9a-fA-F-]{36}\})') { $guid = $Matches[1] }
            }
            if (-not $guid) {
                $out = (& bcdedit.exe /copy '{bootmgr}' /d $entryName) -join ' '
                Log "bcdedit /copy: $out"
                if ($out -match '(\{[0-9a-fA-F-]{36}\})') { $guid = $Matches[1] } else { Stop-With 'إضافة خيار الإقلاع فشلت (bcdedit /copy).' }
            }
            Set-Content -Path $entryFile -Value $guid -Encoding ASCII
            & bcdedit.exe /set $guid path $efiRel
            if ($LASTEXITCODE -ne 0) { Stop-With 'تعديل خيار الإقلاع فشل (bcdedit /set path).' }
            & bcdedit.exe /set '{fwbootmgr}' displayorder $guid /addfirst
            if ($LASTEXITCODE -ne 0) { Stop-With 'ترتيب خيارات الإقلاع فشل (bcdedit displayorder).' }
            Log "firmware boot entry $guid -> $efiRel, first in the boot order"
            $report.Add('✔ خيار الإقلاع انضاف قبل ويندوز (ويندوز يقلع مثل قبل لحد ما يتنصب أندرويد)')
        }
    }
    (& bcdedit.exe /enum firmware) | ForEach-Object { Add-Content -Path $logFile -Value "    $_" -Encoding UTF8 }

    Copy-Item -Path (Join-Path $here 'undo-dualboot.cmd'), (Join-Path $here 'undo-dualboot.ps1') -Destination $work -Force -ErrorAction SilentlyContinue
    try { Copy-Item -Path $logFile -Destination (Join-Path $here 'prepare-log.txt') -Force } catch { }

    $next = "الخطوة الجاية: خلّي الفلاشة مشبوكة، وأعد التشغيل من الفلاشة:`nالإعدادات ← التحديث والأمان ← الاسترداد ← بدء التشغيل المتقدم ← إعادة التشغيل الآن ← استخدام جهاز ← EFI USB Device.`n`nالتنصيب يبدي لوحده بعد 20 ثانية وياخذ حوالي 10 دقايق."
    if ($secureBoot) {
        $next = "لازم تطفّي Secure Boot أول:`nالإعدادات ← التحديث والأمان ← الاسترداد ← بدء التشغيل المتقدم ← إعادة التشغيل الآن ← استكشاف الأخطاء ← خيارات متقدمة ← إعدادات UEFI.`nمن الـBIOS: Security ← Secure Boot ← Disabled، واحفظ.`n`nبعدها ارجع لويندوز وشغّل هذا الملف مرة ثانية."
    }
    $answer = Ask (($report -join "`n") + "`n`n" + $next + "`n`nتريد أفتح شاشة «بدء التشغيل المتقدم» هسه؟") 'YesNo' 'Information'
    if ($answer -eq 'Yes') { & shutdown.exe /r /o /t 3 }
} catch {
    Log "ERROR: $($_.Exception.Message)"
    Log $_.ScriptStackTrace
    Ask ("صار خطأ وما كملت الخطوات:`n`n" + $_.Exception.Message + "`n`nالسجل: $logFile") 'OK' 'Error' | Out-Null
    exit 1
}
