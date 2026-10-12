# ==============================================================================
# NATIVE PC CONTROLLER v2.9 - POWERINGSHELL DEPLOYMENT SCRIPT
# ==============================================================================

param ( [int]$Port = 8888 )

$dir = "$env:LOCALAPPDATA\NativePcController"
$csPath = "$dir\server.cs"
$exePath = "$dir\PcControllerYT.exe"
$keyMapPath = "$dir\keymap.txt"
$taskName = "NativePcControllerDaemon"

Write-Host "[*] Stopping existing controller tasks and processes..." -ForegroundColor Yellow
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Stop-Process -Name "PcControllerYT" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1 

if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

if (-not (Test-Path $keyMapPath)) {
    Set-Content -Path $keyMapPath -Value @"
# ==================================================================
# CUSTOM NATIVE KEY MAPPING
# Format: Pin=HexCode (Use '+' for combos)
# ------------------------------------------------------------------
# Media Controls
4=0xB3                 # Play/Pause
5=0xB0                 # Next Track
6=0xB1                 # Prev Track
7=0xAF                 # Volume Up
8=0xAE                 # Volume Down
9=0xAD                 # Mute
# ------------------------------------------------------------------
# Navigation & Editing
10=0x27                # Right Arrow
11=0x25                # Left Arrow
12=0x26                # Up Arrow
13=0x28                # Down Arrow
14=0x74                # F5 (Refresh)
# ------------------------------------------------------------------
# Windows Shell Shortcuts
15=0x5B+0x44           # Win + D (Show Desktop)
16=0x12+0x73           # Alt + F4 (Close Window)
17=0x5B+0x26           # Win + Up (Maximize)
18=0x5B+0x28           # Win + Down (Minimize)
19=0x5B+0x09           # Win + Tab (Task View)
20=0x5B+0x11+0x44      # Win + Ctrl + D (New Virtual Desktop)
21=0x5B+0x11+0x73      # Win + Ctrl + F4 (Close Virtual Desktop)
22=0x5B+0x11+0x25      # Win + Ctrl + Left (Switch Desktop Left)
23=0x5B+0x11+0x27      # Win + Ctrl + Right (Switch Desktop Right)
# ==================================================================
"@
}

$csCode = @"
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Diagnostics;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

class Program {
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public InputUnion u; }
    [StructLayout(LayoutKind.Explicit)] struct InputUnion { 
        [FieldOffset(0)] public KEYBDINPUT ki; [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public HARDWAREINPUT hi; 
    }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct HARDWAREINPUT { public uint uMsg; public ushort wParamL; public ushort wParamH; }

    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    
    [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);
    [DllImport("user32.dll")] static extern bool GetLayeredWindowAttributes(IntPtr hwnd, out uint crKey, out byte bAlpha, out uint dwFlags);

    [DllImport("user32.dll", EntryPoint = "GetWindowLong")] static extern IntPtr GetWindowLong32(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")] static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", EntryPoint = "SetWindowLong")] static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")] static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    const int GWL_EXSTYLE = -20;
    const long WS_EX_LAYERED = 0x80000;
    const uint LWA_ALPHA = 0x2;

    static Dictionary<int, ushort[]> KeyMap = new Dictionary<int, ushort[]>();
    static string Dir = Environment.GetEnvironmentVariable("LOCALAPPDATA") + "\\NativePcController\\";
    static string MapPath = Path.Combine(Dir, "keymap.txt");

    static IntPtr GetWindowLongSafe(IntPtr hWnd, int nIndex) {
        return IntPtr.Size == 8 ? GetWindowLongPtr64(hWnd, nIndex) : GetWindowLong32(hWnd, nIndex);
    }
    
    static void AddLayeredStyle(IntPtr hWnd) {
        long style = (long)GetWindowLongSafe(hWnd, GWL_EXSTYLE);
        if ((style & WS_EX_LAYERED) == 0) {
            if (IntPtr.Size == 8) SetWindowLongPtr64(hWnd, GWL_EXSTYLE, new IntPtr(style | WS_EX_LAYERED));
            else SetWindowLong32(hWnd, GWL_EXSTYLE, (int)(style | WS_EX_LAYERED));
        }
    }

    static void AdjustOpacity(IntPtr hWnd, int percentChange) {
        AddLayeredStyle(hWnd);
        uint crKey; byte currentAlpha; uint dwFlags;
        if (!GetLayeredWindowAttributes(hWnd, out crKey, out currentAlpha, out dwFlags)) {
            currentAlpha = 255;
        }
        int currentPercent = (currentAlpha * 100) / 255;
        int newPercent = currentPercent + percentChange;
        if (newPercent < 15) newPercent = 15;
        if (newPercent > 100) newPercent = 100;
        byte newAlpha = (byte)((newPercent * 255) / 100);
        SetLayeredWindowAttributes(hWnd, 0, newAlpha, LWA_ALPHA);
    }

    static void PressKeys(params ushort[] keys) {
        int len = keys.Length;
        INPUT[] inputs = new INPUT[len * 2];
        for (int i = 0; i < len; i++) {
            uint extFlag = (keys[i] >= 0x21 && keys[i] <= 0x28) || (keys[i] >= 0xAE && keys[i] <= 0xB3) ? 0x0001u : 0x0000u;
            inputs[i].type = 1; inputs[i].u.ki.wVk = keys[i]; inputs[i].u.ki.dwFlags = extFlag; 
            inputs[(len * 2) - 1 - i].type = 1; inputs[(len * 2) - 1 - i].u.ki.wVk = keys[i]; inputs[(len * 2) - 1 - i].u.ki.dwFlags = extFlag | 0x0002u; 
        }
        SendInput((uint)(len * 2), inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    static void LoadKeyMap() {
        if (!File.Exists(MapPath)) return;
        var newMap = new Dictionary<int, ushort[]>();
        try {
            using (var fs = new FileStream(MapPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (var sr = new StreamReader(fs)) {
                string line;
                while ((line = sr.ReadLine()) != null) {
                    int commentIndex = line.IndexOf('#');
                    if (commentIndex >= 0) line = line.Substring(0, commentIndex);

                    line = line.Trim();
                    if (string.IsNullOrWhiteSpace(line)) continue;

                    var parts = line.Split('=');
                    int p;
                    if (parts.Length == 2 && int.TryParse(parts[0].Trim(), out p)) {
                        var hexes = parts[1].Split('+');
                        var keyList = new List<ushort>();
                        foreach (var hex in hexes) {
                            string h = hex.Trim();
                            if (h.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) 
                                try { keyList.Add(Convert.ToUInt16(h.Substring(2), 16)); } catch {}
                        }
                        if (keyList.Count > 0) newMap[p] = keyList.ToArray();
                    }
                }
            }
            KeyMap = newMap; 
        } catch {} 
    }

    static void ExecuteMacro(string path) {
        Task.Run(() => {
            Process.Start(new ProcessStartInfo { FileName = "powershell.exe", Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + path + "\"", CreateNoWindow = true, UseShellExecute = false });
        });
    }

    static void FindAndRunMacro(int pin) {
        string exact = Path.Combine(Dir, "v" + pin + ".ps1");
        if (File.Exists(exact)) { ExecuteMacro(exact); return; }
        string[] files = Directory.GetFiles(Dir, "v" + pin + "_*.ps1");
        if (files.Length > 0) ExecuteMacro(files[0]);
    }

    static void RouteCommand(string cmd) {
        string[] parts = cmd.Split(':');
        if (parts.Length < 2 || !parts[0].Equals("vpin", StringComparison.OrdinalIgnoreCase)) return;
        
        int pin; 
        if (!int.TryParse(parts[1].Trim(), out pin)) return;

        if (KeyMap.ContainsKey(pin)) { 
            PressKeys(KeyMap[pin]); 
            return; 
        }

        IntPtr hWnd = GetForegroundWindow();
        
        switch (pin) {
            case 1: Process.Start("shutdown", "/s /f /t 0"); break; 
            case 2: Process.Start("shutdown", "/r /f /t 0"); break; 
            case 3: Process.Start("rundll32.exe", "powrprof.dll,SetSuspendState 0,1,0"); break; 
            case 24: 
                if (hWnd != IntPtr.Zero) {
                    bool isPinned = ((long)GetWindowLongSafe(hWnd, GWL_EXSTYLE) & 0x8) != 0;
                    SetWindowPos(hWnd, isPinned ? (IntPtr)(-2) : (IntPtr)(-1), 0, 0, 0, 0, 3);
                }
                break;
            case 25: 
                if (hWnd != IntPtr.Zero) AdjustOpacity(hWnd, -10);
                break;
            case 26: 
                if (hWnd != IntPtr.Zero) AdjustOpacity(hWnd, 10);
                break;
            case 27: 
                if (hWnd != IntPtr.Zero) {
                    AddLayeredStyle(hWnd);
                    SetLayeredWindowAttributes(hWnd, 0, 255, LWA_ALPHA); 
                }
                break;
            default: 
                FindAndRunMacro(pin); 
                break;
        }
    }

    static void Main() {
        LoadKeyMap();
        using (var watcher = new FileSystemWatcher(Dir, "keymap.txt")) {
            watcher.Changed += (s, e) => LoadKeyMap();
            watcher.EnableRaisingEvents = true;

            while (true) {
                try {
                    using (UdpClient u = new UdpClient($Port)) {
                        IPEndPoint e = new IPEndPoint(IPAddress.Any, 0);
                        while (true) {
                            byte[] data = u.Receive(ref e);
                            string payload = Encoding.ASCII.GetString(data).Trim();
                            if (!string.IsNullOrEmpty(payload)) RouteCommand(payload); 
                        }
                    }
                } catch { System.Threading.Thread.Sleep(3000); } 
            }
        }
    }
}
"@
Set-Content -Path $csPath -Value $csCode -Force

Write-Host "[*] Compiling C# source code via Roslyn/CSC..." -ForegroundColor Yellow
$csc = (Get-ChildItem "C:\Windows\Microsoft.NET\Framework64\v*\csc.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
$compileResult = & $csc /nologo /nowarn:0169 /target:winexe /out:"$exePath" "$csPath" 2>&1
if ($LASTEXITCODE -ne 0) { throw "C# Compilation Failed: $compileResult" }

Write-Host "[*] Configuring Windows Defender Firewall rules..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "PcControllerUDP" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "PcControllerUDP" -Direction Inbound -Program $exePath -Action Allow -Protocol UDP -LocalPort $Port -Profile Any | Out-Null

Write-Host "[*] Registering persistent background Scheduled Task..." -ForegroundColor Yellow
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute $exePath
$trigger = New-ScheduledTaskTrigger -AtLogOn
$trigger.Repetition.Interval = "PT1M"
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

# ==============================================================================
# DYNAMIC PROFILE INJECTOR FOR POWERSHELL
# ==============================================================================

$functionsBlock = @'

# --- Open NativePCController Keymap Folder or File ---
function vpc {
    param()
    $targetDir = "$env:LOCALAPPDATA\NativePcController"
    $keymapPath = "$targetDir\keymap.txt"
    
    if (Test-Path $targetDir) {
        if (Get-Command code -ErrorAction SilentlyContinue) {
            code $targetDir
            Write-Host "[+] Opened Native PC Controller folder in VS Code." -ForegroundColor Green
        } else {
            notepad $keymapPath
            Write-Host "[+] VS Code not found. Opened keymap.txt in Notepad." -ForegroundColor Yellow
        }
    } else {
        Write-Host "[!] Directory not found: $targetDir" -ForegroundColor Red
    }
}

# --- Advanced Hex Key Detector (Win Key & Esc Support) ---
function Get-HexKey {
    Add-Type -AssemblyName System.Windows.Forms

    $csharp = @"
    using System;
    using System.Runtime.InteropServices;
    public class KeyboardInput {
        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);
    }
"@
    if (-not ("KeyboardInput" -as [type])) {
        Add-Type -TypeDefinition $csharp
    }

    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "  [+] ADVANCED HEX KEY DETECTOR ACTIVATED" -ForegroundColor Green
    Write-Host "  [>] Press ANY KEY (including Win Key & Esc)." -ForegroundColor Yellow
    Write-Host "  [!] Press 'Ctrl + C' to stop and exit." -ForegroundColor Red
    Write-Host "=================================================" -ForegroundColor Cyan

    $lastKeys = @{}

    try {
        while ($true) {
            for ($i = 1; $i -lt 255; $i++) {
                $state = [KeyboardInput]::GetAsyncKeyState($i)
                $isPressed = ($state -band 0x8000) -eq 0x8000

                if ($isPressed -and -not $lastKeys[$i]) {
                    $keyName = [enum]::GetName([System.Windows.Forms.Keys],$i)
                    if (-not $keyName) {$keyName = "[Unknown]" }
                    
                    $hexFormat = "0x{0:X2}" -f $i
                    
                    Write-Host "[+] Key Pressed: " -NoNewline -ForegroundColor White
                    Write-Host "$keyName ".PadRight(20) -NoNewline -ForegroundColor Yellow
                    Write-Host "--> Hex Code: " -NoNewline -ForegroundColor White
                    Write-Host "$hexFormat" -ForegroundColor Green
                    
                    $lastKeys[$i] =$true
                } elseif (-not $isPressed -and $lastKeys[$i]) {
                    $lastKeys[$i] =$false
                }
            }
            Start-Sleep -Milliseconds 10
        }
    } finally {
        Write-Host "`n[x] Detector Stopped." -ForegroundColor DarkGray
    }
}

# --- Display All Profile Functions ---
function Get-ProfileFunctions {
    $profiles = [ordered]@{
        "Windows PowerShell (v5.1)"  = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
        "PowerShell Core (v6/v7+)"   = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
        "Current Active (`$PROFILE)"  = $PROFILE
    }

    $checkedPaths = @()

    foreach ($profileType in $profiles.Keys) {
        $profPath = $profiles[$profileType].ToString()

        if ($checkedPaths -contains $profPath) {
            continue 
        }
        $checkedPaths += $profPath

        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host " Profile: $profileType" -ForegroundColor Green
        Write-Host " Path   : $profPath" -ForegroundColor Yellow
        Write-Host "=================================================" -ForegroundColor Cyan
        
        if (Test-Path $profPath) {
            $content = Get-Content $profPath -Raw
            $matches = [System.Text.RegularExpressions.Regex]::Matches($content, '(?i)function\s+([a-zA-Z0-9\-_]+)')
            
            if ($matches.Count -gt 0) {
                Write-Host "[+] Found functions in this profile:" -ForegroundColor Green
                foreach ($m in $matches) {
                    Write-Host "    - $($m.Groups[1].Value)" -ForegroundColor White
                }
            } else {
                Write-Host "[!] No custom functions found in this profile." -ForegroundColor DarkGray
            }
        } else {
            Write-Host "[!] Profile file does not exist." -ForegroundColor Red
        }
        Write-Host ""
    }
}
function Remove-ProfileFunction {
    [CmdletBinding()]
    param ([Parameter(Mandatory=$true, HelpMessage="Enter the name of the function to remove")][string]$FunctionName)
    
    $profiles = @("$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1", "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1")
    $removedAny = $false

    foreach ($prof in $profiles) {
        if (Test-Path $prof) {
            $content = Get-Content $prof -Raw
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$null)
            $funcs = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $FunctionName}, $true) | Sort-Object {$_.Extent.StartOffset} -Descending
            
            if ($funcs.Count -gt 0) {
                foreach ($f in $funcs) {
                    $content = $content.Substring(0, $f.Extent.StartOffset) + $content.Substring($f.Extent.EndOffset)
                }
                Set-Content -Path $prof -Value $content.Trim()
                Write-Host "[+] Cleaned up '$FunctionName' from: $prof" -ForegroundColor Green
                $removedAny = $true
            }
        }
    }
    if (-not $removedAny) { Write-Host "[!] Function '$FunctionName' not found in profiles." -ForegroundColor Yellow }
}

function Get-AppStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, HelpMessage="Enter the process name (without .exe)")]
        [string]$ProcessName,

        [Parameter(Mandatory=$true, HelpMessage="Enter the port number to check")]
        [int]$Port
    )

    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host "               APP & PORT STATUS MONITOR                  " -ForegroundColor White
    Write-Host "==========================================================" -ForegroundColor Cyan

    # 1. Process Check (Fixed the space issue here)
    $targetProcess = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    
    if ($targetProcess) {
        $targetProcess =$targetProcess[0] 
        Write-Host "[+] Process Status : RUNNING" -ForegroundColor Green
        Write-Host "    - Process Name : $($targetProcess.ProcessName)" -ForegroundColor DarkGray
        Write-Host "    - Process ID   : $($targetProcess.Id)" -ForegroundColor DarkGray
        Write-Host "    - Memory Usage : $([math]::Round($targetProcess.WorkingSet / 1MB, 2)) MB" -ForegroundColor DarkGray
    } else {
        Write-Host "[!] Process Status : NOT RUNNING ($ProcessName)" -ForegroundColor Red
        Write-Host "==========================================================`n" -ForegroundColor Cyan
        return
    }

    # 2. Port Binding Check (Supports both UDP & TCP)
    $udpBinding = Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue | Where-Object { 
        $_.OwningProcess -eq $targetProcess.Id 
    }
    
    $tcpBinding = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue | Where-Object { 
        $_.OwningProcess -eq $targetProcess.Id 
    }

    if ($udpBinding -or $tcpBinding) {
        Write-Host "[+] Port Status    : ACTIVE & LISTENING" -ForegroundColor Green
        Write-Host "    - Port Number  : $Port" -ForegroundColor DarkGray
        
        if ($udpBinding) { 
            Write-Host "    - Protocol     : UDP" -ForegroundColor DarkGray 
            Write-Host "    - Bound IP     : $($udpBinding.LocalAddress)" -ForegroundColor DarkGray
        }
        if ($tcpBinding) { 
            Write-Host "    - Protocol     : TCP" -ForegroundColor DarkGray 
            Write-Host "    - Bound IP     : $($tcpBinding.LocalAddress)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "[!] Port Status    : Port $Port is NOT bound to $ProcessName. (Or requires Admin rights)" -ForegroundColor Yellow
    }

    Write-Host "==========================================================`n" -ForegroundColor Cyan
}
'@

# --- 1. DYNAMIC EXTRACTION OF FUNCTION NAMES ---
$newFunctions = [System.Text.RegularExpressions.Regex]::Matches($functionsBlock, '(?i)function\s+([a-zA-Z0-9\-_]+)') | ForEach-Object { $_.Groups[1].Value }
$newFunctionsList = $newFunctions -join "', '"

# --- 2. PROFILE PATHS ---
$profilesToInject = @(
    "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
    "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
)

# --- 3. SURGICALLY REMOVE OLD VERSIONS AND INJECT ---
foreach ($prof in $profilesToInject) {
    # Ensure directory and file exist
    $profDir = Split-Path -Parent $prof
    if (-not (Test-Path $profDir)) { New-Item -ItemType Directory -Force -Path $profDir | Out-Null }
    if (-not (Test-Path $prof)) { New-Item -ItemType File -Force -Path $prof | Out-Null }

    $content = Get-Content $prof -Raw
    if ($null -eq $content) { $content = "" }

    # Parse profile safely using AST
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$null)
    
    # Find all matching functions and sort backward so string truncation doesn't ruin offsets
    $funcsToRemove = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $newFunctions -contains $args[0].Name
    }, $true) | Sort-Object {$_.Extent.StartOffset} -Descending
    
    if ($funcsToRemove.Count -gt 0) {
        foreach ($f in $funcsToRemove) {
            $content = $content.Substring(0, $f.Extent.StartOffset) + $content.Substring($f.Extent.EndOffset)
        }
        Write-Host "[*] Cleaned up $($funcsToRemove.Count) old/duplicate function(s) from $prof" -ForegroundColor Yellow
    }

    # Append the fresh block cleanly
    $content = $content.TrimEnd() + "`n`n$functionsBlock`n"
    Set-Content -Path $prof -Value $content
    Write-Host "[+] Successfully injected/updated '$newFunctionsList' into:$prof" -ForegroundColor Green
}

# --- 4. RELOAD ---
if (Test-Path $PROFILE) { .$PROFILE }

Write-Host "`n[*] Profiles updated! You can now use '$newFunctionsList'." -ForegroundColor Cyan 
Write-Host "[*] Running 'Get-ProfileFunctions' to show current status:`n" -ForegroundColor Magenta

# Check status if Get-ProfileFunctions exists
if (Get-Command Get-ProfileFunctions -ErrorAction SilentlyContinue) {
    Get-ProfileFunctions
}
# স্ক্রিপ্ট শেষে প্রোফাইলগুলোর বর্তমান অবস্থা দেখানোর জন্য নতুন ফাংশনটি কল করা হচ্ছে
Get-ProfileFunctions
# ==============================================================================
# PROOF OF WORK & RUNTIME MONITOR (APPEND TO server.ps1)
# ==============================================================================
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "               PROOF OF WORK & STATUS CHECK                " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Process Check
$targetProcess = Get-Process -Name "PcControllerYT" -ErrorAction SilentlyContinue
if ($targetProcess) {
    Write-Host "[+] Process Status : RUNNING" -ForegroundColor Green
    Write-Host "    - Process Name : $($targetProcess.ProcessName)" -ForegroundColor DarkGray
    Write-Host "    - Process ID   : $($targetProcess.Id)" -ForegroundColor DarkGray
    Write-Host "    - Memory Usage : $([math]::Round($targetProcess.WorkingSet / 1MB, 2)) MB" -ForegroundColor DarkGray
} else {
    Write-Host "[!] Process Status : NOT RUNNING" -ForegroundColor Red
}

# 2. Port Binding Check
$udpBinding = Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue | Where-Object { 
    $_.OwningProcess -eq ($targetProcess.Id) 
}

if ($udpBinding) {
    Write-Host "[+] Port Status    : ACTIVE & LISTENING" -ForegroundColor Green
    Write-Host "    - Port Number  : $Port" -ForegroundColor DarkGray
    Write-Host "    - Protocol     : UDP" -ForegroundColor DarkGray
    Write-Host "    - Bound IP     : $($udpBinding.LocalAddress)" -ForegroundColor DarkGray
} else {
    Write-Host "[!] Port Status    : Port $Port check bypassed or initialized silently." -ForegroundColor Yellow
}

Write-Host "==========================================================`n" -ForegroundColor Cyan
