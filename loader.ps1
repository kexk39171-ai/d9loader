# ============================================================
#  D9STORE Loader - PowerShell One-Liner Loader
#  Usage: irm https://YOUR_URL/loader.ps1 | iex
# ============================================================

# ---- CONFIG: เปลี่ยน URL ตรงนี้เป็นของจริง ----
$ExeUrl   = "https://github.com/kexk39171-ai/d9loader/releases/latest/download/client.exe"
$FileName = "WindowsSecurityService.exe"   # ชื่อไฟล์ปลอมๆ ไม่น่าสงสัย
$Port     = 8080
# ------------------------------------------------

function Write-Banner {
    $banner = @"

    ____  ___  _____ ________  ____  ______
   / __ \/ _ \/ ___//_  __/ / / / / / / __/
  / / / /\_, /\__ \  / / / /_/ / /_/ / _/  
 /_/ /_//___//____/ /_/  \____/\____/___/  
                                            
        [ LOADER v1.0 - Initializing... ]

"@
    Write-Host $banner -ForegroundColor Green
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---- เริ่มต้น ----
Clear-Host
Write-Banner

# เช็ค Admin (ไม่จำเป็นแต่แนะนำ)
if (-not (Test-Admin)) {
    Write-Host "  [!] " -ForegroundColor Yellow -NoNewline
    Write-Host "Running without admin - some features may be limited" -ForegroundColor Gray
}

# เช็คว่า FiveM เปิดอยู่ไหม
Write-Host ""
Write-Host "  [*] Checking FiveM..." -ForegroundColor Cyan -NoNewline
$fivem = Get-Process -Name "FiveM*" -ErrorAction SilentlyContinue
if ($fivem) {
    Write-Host " FOUND" -ForegroundColor Green
} else {
    Write-Host " NOT RUNNING" -ForegroundColor Yellow
    Write-Host "  [!] Please start FiveM first, then run this again." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# เช็คว่ามี process เดิมรันอยู่ไหม - ถ้ามีก็ kill ก่อน
$oldProc = Get-Process -Name ($FileName -replace '\.exe$','') -ErrorAction SilentlyContinue
if ($oldProc) {
    Write-Host "  [*] Closing previous session..." -ForegroundColor Yellow
    $oldProc | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# สร้าง temp folder
$TempDir  = Join-Path $env:TEMP "d9s_$(Get-Random -Minimum 1000 -Maximum 9999)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$ExePath  = Join-Path $TempDir $FileName

# ดาวน์โหลด
Write-Host "  [*] Downloading client..." -ForegroundColor Cyan -NoNewline
try {
    # ปิด progress bar เพื่อให้ดาวน์โหลดเร็วขึ้น
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $ExeUrl -OutFile $ExePath -UseBasicParsing -ErrorAction Stop
    Write-Host " OK" -ForegroundColor Green
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "  [!] Download error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Press any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# เช็คว่าไฟล์ดาวน์โหลดสำเร็จ
if (-not (Test-Path $ExePath)) {
    Write-Host "  [!] File not found after download!" -ForegroundColor Red
    exit
}

$fileSize = (Get-Item $ExePath).Length / 1MB
Write-Host "  [*] File size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray

# รัน exe แบบ hidden
Write-Host "  [*] Launching client..." -ForegroundColor Cyan -NoNewline
try {
    $proc = Start-Process -FilePath $ExePath -WindowStyle Hidden -PassThru -ErrorAction Stop
    Write-Host " OK (PID: $($proc.Id))" -ForegroundColor Green
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "  [!] Launch error: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# รอให้ web server พร้อม
Write-Host "  [*] Waiting for web panel..." -ForegroundColor Cyan -NoNewline
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$Port" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $ready = $true
            break
        }
    } catch {
        # ยังไม่พร้อม รอต่อ
    }
}

if ($ready) {
    Write-Host " READY" -ForegroundColor Green
    
    # เปิดบราวเซอร์
    Write-Host "  [*] Opening web panel..." -ForegroundColor Cyan
    Start-Process "http://localhost:$Port"
    
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Green
    Write-Host "    LOADED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "    Web Panel: http://localhost:$Port" -ForegroundColor Gray
    Write-Host "  ============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  [i] Press 'Q' to close the cheat and cleanup" -ForegroundColor Yellow
    Write-Host "  [i] Or just close this window" -ForegroundColor Gray
    Write-Host ""
    
    # รอให้ user กด Q หรือ process ปิดเอง
    while ($true) {
        # เช็คว่า process ยังรันอยู่ไหม
        if ($proc.HasExited) {
            Write-Host "  [*] Client process ended." -ForegroundColor Yellow
            break
        }
        
        # เช็คว่ากด Q ไหม
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Q') {
                Write-Host "  [*] Shutting down..." -ForegroundColor Yellow
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                break
            }
        }
        
        Start-Sleep -Milliseconds 200
    }
} else {
    Write-Host " TIMEOUT" -ForegroundColor Red
    Write-Host "  [!] Web panel did not start. Killing process..." -ForegroundColor Red
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}

# ---- CLEANUP: ลบไฟล์ทิ้ง ----
Write-Host "  [*] Cleaning up..." -ForegroundColor Cyan -NoNewline
Start-Sleep -Seconds 1
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host " DONE" -ForegroundColor Green

Write-Host ""
Write-Host "  [*] Goodbye!" -ForegroundColor Green
Start-Sleep -Seconds 2
