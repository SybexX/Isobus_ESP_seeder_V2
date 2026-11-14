<#
  ESP32S3 RCv1.7 (AgOpenGPS Rate Controller panel) – ELSŐ FELTÖLTÉS új, nyers panelre
  ------------------------------------------------------------------------------------
  Miért kell?  A GPIO45 (a flash tápfeszültségét választó "strapping" láb) a W5500 Ethernet INT lábára
  van kötve. Az INT induláskor magas, ezért az ESP32-S3 a flash-t 1,8 V-ról próbálja járatni – a 3,3 V-os
  flash így nem működik: a panel nem indul, és normál módon feltölteni sem lehet.
  Megoldás: a flash feszültségét egyszer, véglegesen eFuse-zal 3,3 V-ra rögzítjük (VDD_SPI). Ehhez a
  böngészős feltöltő (esptool-js) nem elég, az Espressif esptool / espefuse program kell – ez a szkript
  elintézi: letölti az eszközt, ellenőrzi és beégeti az eFuse-t, majd feltölti a FULL firmware-t.

  Használat: dupla katt az ELSO_FELTOLTES_RCV17.bat fájlra (ugyanebben a mappában legyen a
  …RCV17_16MB_…_FULL_0x0.bin is: PERMETEZO_… vagy VETOGEP_…).
#>
# 'Continue': a Windows PowerShell 5.1 a natív programok stderr-kimenetét (2>&1) különben hibaként leállítaná
$ErrorActionPreference = 'Continue'
$EsptoolVer = 'v4.8.1'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Here

function Say($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Pause-Enter($t) { Write-Host ''; Read-Host "$t  [Enter]" | Out-Null }
function Fail($t) { Say ''; Say "HIBA: $t" Red; Pause-Enter 'Kilépés'; exit 1 }

Say '================================================================' Cyan
Say ' ESP32S3 RCv1.7 – első feltöltés (eFuse 3,3 V + FULL firmware)' Cyan
Say '================================================================' Cyan
Say 'Lépések: 1) eszköz  2) COM port  3) eFuse ellenőrzés / égetés  4) firmware feltöltés'
Say ''

# ------------------------------------------------------------------ 1. esptool / espefuse
$Tool = $null   # @{ esptool = {..}; espefuse = {..} }
try {
    $null = & python -m esptool version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $Tool = @{ esptool = { param($a) & python -m esptool @a }; espefuse = { param($a) & python -m espefuse @a }; name = 'python -m esptool' }
    }
} catch { }
if (-not $Tool) {
    $dir = Join-Path $Here 'esptool'
    $ef = Get-ChildItem -Path $dir -Recurse -Filter 'espefuse.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ef) {
        $zip = Join-Path $Here "esptool-$EsptoolVer-win64.zip"
        $url = "https://github.com/espressif/esptool/releases/download/$EsptoolVer/esptool-$EsptoolVer-win64.zip"
        Say "Az esptool letöltése ($EsptoolVer, Espressif GitHub)…"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -ErrorAction Stop
            Expand-Archive -Path $zip -DestinationPath $dir -Force -ErrorAction Stop
            Remove-Item $zip -ErrorAction SilentlyContinue
        } catch {
            Fail "Az esptool nem tölthető le ($url).`nTöltsd le kézzel, és csomagold ki ide egy 'esptool' mappába – vagy telepítsd: pip install esptool"
        }
        $ef = Get-ChildItem -Path $dir -Recurse -Filter 'espefuse.exe' | Select-Object -First 1
        if (-not $ef) { Fail 'A letöltött csomagban nincs espefuse.exe.' }
    }
    $et = Join-Path $ef.DirectoryName 'esptool.exe'
    $Tool = @{ esptool = { param($a) & $et @a }.GetNewClosure(); espefuse = { param($a) & $ef.FullName @a }.GetNewClosure(); name = $ef.DirectoryName }
}
Say "Eszköz: $($Tool.name)" Green

# ------------------------------------------------------------------ 2. COM port
function Choose-Port {
    $ports = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\(COM\d+\)' })
    if ($ports.Count -eq 0) { Fail 'Nincs soros port. Dugd be a panelt USB-n (a natív micro-USB csatlakozó), és indítsd újra a szkriptet.' }
    Say ''
    Say 'Soros portok:'
    for ($i = 0; $i -lt $ports.Count; $i++) { Say ("  {0}) {1}" -f ($i + 1), $ports[$i].Name) }
    Say '  (a panel natív USB-je általában "USB JTAG/serial debug unit" vagy "USB-soros eszköz" néven látszik)' DarkGray
    $sel = if ($ports.Count -eq 1) { '1' } else { Read-Host 'Melyik a panel? (szám)' }
    $n = 0
    if (-not [int]::TryParse($sel, [ref]$n) -or $n -lt 1 -or $n -gt $ports.Count) { Fail 'Érvénytelen választás.' }
    return ([regex]::Match($ports[$n - 1].Name, 'COM\d+')).Value
}
$Port = Choose-Port
Say "Port: $Port" Green

function Download-Mode($why) {
    Say ''
    Say "$why" Yellow
    Say '  Tedd a panelt LETÖLTŐ módba:  tartsd nyomva a BOOT gombot, nyomd meg és engedd el a RESET-et,' Yellow
    Say '  majd engedd el a BOOT-ot.  (Ha nincs RESET gomb: BOOT nyomva tartva dugd be az USB-t.)' Yellow
    Pause-Enter 'Ha kész'
}

# ------------------------------------------------------------------ 3. eFuse
Download-Mode '3. lépés: eFuse ellenőrzés.'
$chip = (& $Tool.esptool @('--chip', 'esp32s3', '--port', $Port, '--before', 'no_reset', '--after', 'no_reset', 'chip_id') 2>&1 | Out-String)
if ($chip -notmatch 'ESP32-S3') {
    Say $chip DarkGray
    Fail 'Nem ESP32-S3 válaszolt (vagy nincs letöltő módban). Ellenőrizd a portot és a BOOT/RESET sorrendet.'
}
Say 'ESP32-S3 megtalálva.' Green

function Read-VddSpi {
    $out = (& $Tool.espefuse @('--chip', 'esp32s3', '--port', $Port, '--before', 'no_reset', '--do-not-confirm', 'summary') 2>&1 | Out-String)
    $bits = @{}
    foreach ($name in 'VDD_SPI_FORCE', 'VDD_SPI_XPD', 'VDD_SPI_TIEH') {
        # a sor elején álló mezőnév, utána (akár a tördelt leírás után) az első "(0bX)"
        $m = [regex]::Match($out, "(?m)^\s*$name\s+\(BLOCK[\s\S]*?\(0b([01])\)")
        $bits[$name] = if ($m.Success) { $m.Groups[1].Value } else { '?' }
    }
    return @{ text = $out; bits = $bits }
}
$st = Read-VddSpi
Say ("VDD_SPI_FORCE={0}  VDD_SPI_XPD={1}  VDD_SPI_TIEH={2}" -f $st.bits.VDD_SPI_FORCE, $st.bits.VDD_SPI_XPD, $st.bits.VDD_SPI_TIEH)
$done = ($st.bits.VDD_SPI_FORCE -eq '1' -and $st.bits.VDD_SPI_XPD -eq '1' -and $st.bits.VDD_SPI_TIEH -eq '1')
if ($st.bits.VDD_SPI_FORCE -eq '?') {
    Say ($st.text) DarkGray
    Fail 'Az eFuse-állapot nem olvasható ki (lásd fent).'
}
if ($done) {
    Say 'A flash feszültsége már 3,3 V-ra van égetve – ez a lépés kimarad.' Green
} else {
    Say ''
    Say 'A flash feszültségét most 3,3 V-ra kell égetni (VDD_SPI eFuse).' Yellow
    Say 'Ez EGYSZERI és VISSZAFORDÍTHATATLAN – ennél a panelnél pontosan ez kell (16 MB, 3,3 V-os flash).' Yellow
    $ok = Read-Host 'Beégessem? Írd be: IGEN'
    if ($ok -ne 'IGEN') { Fail 'Megszakítva, az eFuse nem változott.' }
    Say 'Az espefuse még egyszer megerősítést kér: ott írd be nagybetűvel: BURN' Yellow
    & $Tool.espefuse @('--chip', 'esp32s3', '--port', $Port, '--before', 'no_reset', 'set_flash_voltage', '3.3V')
    if ($LASTEXITCODE -ne 0) { Fail 'Az eFuse égetése nem sikerült.' }
    $st = Read-VddSpi
    if (-not ($st.bits.VDD_SPI_FORCE -eq '1' -and $st.bits.VDD_SPI_XPD -eq '1' -and $st.bits.VDD_SPI_TIEH -eq '1')) {
        Say ($st.text) DarkGray
        Fail 'Égetés után az eFuse nem a várt értéket mutatja (lásd fent).'
    }
    Say 'eFuse beégetve: a flash ezentúl mindig 3,3 V-ról jár.' Green
}

# ------------------------------------------------------------------ 4. firmware
$bins = @(Get-ChildItem -Path $Here -Filter '*_FULL_0x0.bin' | Where-Object { $_.Name -match 'RCV17' } | Sort-Object LastWriteTime -Descending)
$wrong = @(Get-ChildItem -Path $Here -Filter '*_FULL_0x0.bin' | Where-Object { $_.Name -notmatch 'RCV17' })
if ($wrong.Count -gt 0) { Say ("Figyelem: ezek NEM RCv1.7-es fájlok, kihagyom: " + ($wrong.Name -join ', ')) Yellow }
if ($bins.Count -eq 0) {
    Say ''
    Say 'Nincs ...RCV17_16MB_..._FULL_0x0.bin a mappában. Töltsd le a GitHub kiadásból (legujabb), tedd ide,' Yellow
    Say 'és futtasd újra a szkriptet (az eFuse lépés akkor már kimarad) – vagy töltsd fel böngészőből:' Yellow
    Say '  https://espressif.github.io/esptool-js/  →  FULL_0x0.bin a 0x0 címre' Yellow
    Pause-Enter 'Kilépés'; exit 0
}
$bin = $bins[0]
if ($bins.Count -gt 1) {
    Say ''
    for ($i = 0; $i -lt $bins.Count; $i++) { Say ("  {0}) {1}" -f ($i + 1), $bins[$i].Name) }
    $s = Read-Host 'Melyik firmware? (szám, Enter = a legújabb)'
    $n = 0
    if ($s -and [int]::TryParse($s, [ref]$n) -and $n -ge 1 -and $n -le $bins.Count) { $bin = $bins[$n - 1] }
}
Download-Mode ("4. lépés: feltöltés: {0}`n  Ha az eFuse most lett beégetve: előbb húzd ki az USB-t (és a 12 V-ot), majd dugd vissza." -f $bin.Name)
$fid = (& $Tool.esptool @('--chip', 'esp32s3', '--port', $Port, '--before', 'no_reset', '--after', 'no_reset', 'flash_id') 2>&1 | Out-String)
$sz = [regex]::Match($fid, 'Detected flash size:\s*(\S+)').Groups[1].Value
Say "Flash méret: $sz"
if ($sz -and $sz -ne '16MB') {
    Say ($fid) DarkGray
    Fail "Ez a firmware 16 MB-os flash-hez készült, a panelen $sz van. Szólj, és készül hozzá változat."
}
$args1 = @('--chip', 'esp32s3', '--port', $Port, '--baud', '460800', '--before', 'no_reset', '--after', 'hard_reset', 'write_flash', '0x0', $bin.FullName)
& $Tool.esptool $args1
if ($LASTEXITCODE -ne 0) {
    Say 'Gyors feltöltés nem sikerült, újra 115200 baud-dal…' Yellow
    Download-Mode 'Tedd újra letöltő módba a panelt.'
    $args1[5] = '115200'
    & $Tool.esptool $args1
    if ($LASTEXITCODE -ne 0) { Fail 'A feltöltés nem sikerült.' }
}
Say ''
Say '================================================================' Green
Say ' KÉSZ. Nyomd meg a RESET-et (vagy húzd ki / dugd vissza a panelt).' Green
Say '================================================================' Green
if ($bin.Name -match '^PERMETEZO') {
    Say 'Permetező: WiFi "PERMETEZO-xxxx" (jelszó 12345678) → http://192.168.4.1, vagy Etherneten.'
    Say 'A kimenetek alapból TILTVA: bekötés és ellenőrzés után a Beállítások → Kimenetek engedélyezése.'
} else {
    Say 'Vetőgép: a WiFi alapból KI – web Etherneten (192.168.5.130), vagy a VT menü → WiFi,'
    Say 'vagy bekapcsoláskor 3 s-ig nyomd a leforgató gombot (GPIO9). Beállítás: docs/HARDVER_RCV17_HU.md.'
}
Pause-Enter 'Kilépés'
