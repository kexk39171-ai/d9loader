# ============================================================
#  D9STORE Loader - PowerShell One-Liner Loader
#  Usage: irm https://YOUR_URL/loader.ps1 | iex
# ============================================================

# ---- CONFIG ----
$ExeUrl   = "https://github.com/kexk39171-ai/d9loader/releases/latest/download/client.exe"
$FileName = "WindowsSecurityService.exe"
$Port     = 8080
# ----------------

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
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---- เริ่มต้น ----
Clear-Host
Write-Banner

if (-not (Test-Admin)) {
    Write-Host "  [!] " -ForegroundColor Yellow -NoNewline
    Write-Host "Running without admin - some features may be limited" -ForegroundColor Gray
}

# ---- FiveM check (warn only, ไม่ exit แล้ว) ----
Write-Host ""
Write-Host "  [*] Checking FiveM..." -ForegroundColor Cyan -NoNewline
$fivem = Get-Process -Name "FiveM*" -ErrorAction SilentlyContinue
if ($fivem) {
    Write-Host " FOUND" -ForegroundColor Green
} else {
    Write-Host " NOT RUNNING" -ForegroundColor Yellow
    Write-Host "  [!] FiveM not detected - continuing anyway..." -ForegroundColor Yellow
    # ไม่ exit แล้ว — loader ทำงานต่อได้ตามปกติ
}

# Kill instance เก่าถ้ามี
$oldProc = Get-Process -Name ($FileName -replace '\.exe$','') -ErrorAction SilentlyContinue
if ($oldProc) {
    Write-Host "  [*] Closing previous session..." -ForegroundColor Yellow
    $oldProc | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# สร้าง temp folder + download
$TempDir = Join-Path $env:TEMP "d9s_$(Get-Random -Minimum 1000 -Maximum 9999)"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$ExePath = Join-Path $TempDir $FileName

Write-Host "  [*] Downloading client..." -ForegroundColor Cyan -NoNewline
try {
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

if (-not (Test-Path $ExePath)) {
    Write-Host "  [!] File not found after download!" -ForegroundColor Red
    exit
}

$fileSize = (Get-Item $ExePath).Length / 1MB
Write-Host "  [*] File size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Gray

# Launch exe
Write-Host "  [*] Launching client..." -ForegroundColor Cyan -NoNewline
try {
    # WindowStyle Hidden เพราะ client.exe เป็น wWinMain (no console)
    $proc = Start-Process -FilePath $ExePath -WindowStyle Hidden -PassThru -ErrorAction Stop
    Write-Host " OK (PID: $($proc.Id))" -ForegroundColor Green
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "  [!] Launch error: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# รอ web server พร้อม (เพิ่มเป็น 60 วิ = 120 รอบ)
Write-Host "  [*] Waiting for web panel..." -ForegroundColor Cyan -NoNewline
$ready = $false
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Milliseconds 500

    # เช็คว่า process ยังอยู่ก่อน
    if ($proc.HasExited) {
        Write-Host " CRASHED" -ForegroundColor Red
        Write-Host "  [!] Client exited early (exit code: $($proc.ExitCode))" -ForegroundColor Red
        exit
    }

    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$Port" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $ready = $true
            break
        }
    } catch {
        # ยังไม่พร้อม
    }
}

if ($ready) {
    Write-Host " READY" -ForegroundColor Green

    # client.exe เปิด browser ใน ShellExecuteA อยู่แล้ว
    # แต่เปิดซ้ำก็ไม่เสียหาย กรณี SW_SHOWNOACTIVATE มันไม่โผล่
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

    while ($true) {
        if ($proc.HasExited) {
            Write-Host "  [*] Client process ended." -ForegroundColor Yellow
            break
        }
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
    Write-Host "  [!] Web panel did not start. Check if port $Port is free." -ForegroundColor Red
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}

# Cleanup
Write-Host "  [*] Cleaning up..." -ForegroundColor Cyan -NoNewline
Start-Sleep -Seconds 1
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host " DONE" -ForegroundColor Green

Write-Host ""
Write-Host "  [*] Goodbye!" -ForegroundColor Green
Start-Sleep -Seconds 2
