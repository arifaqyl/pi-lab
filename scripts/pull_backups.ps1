# Pull the Pi's nightly backups to this PC, so a copy survives the Pi's SSD dying.
# Run by the Windows scheduled task "Pi backup pull" (daily 21:00 and at logon).
$dest = 'E:\backup\pi-nightly'
$pi   = 'aqyl@192.168.100.63'
$keep = 30
New-Item -ItemType Directory -Force $dest | Out-Null
$log = Join-Path $dest 'pull.log'
function Log($msg) { "$(Get-Date -Format s) $msg" | Add-Content $log }

$names = & ssh -o BatchMode=yes -o ConnectTimeout=10 $pi 'ls /home/aqyl/backups/nightly/'
if ($LASTEXITCODE -ne 0) { Log 'pi unreachable'; exit 1 }

foreach ($n in $names) {
    if ($n -notmatch '^pi-\d{8}\.tar\.zst$') { continue }
    $local = Join-Path $dest $n
    if (Test-Path $local) { continue }
    & scp -q -o BatchMode=yes "${pi}:/home/aqyl/backups/nightly/$n" "$local.part"
    if ($LASTEXITCODE -eq 0) { Move-Item "$local.part" $local -Force; Log "pulled $n" }
    else { Remove-Item "$local.part" -ErrorAction SilentlyContinue; Log "failed $n" }
}

# keep the newest $keep archives
Get-ChildItem $dest -Filter 'pi-*.tar.zst' | Sort-Object Name -Descending |
    Select-Object -Skip $keep | Remove-Item
