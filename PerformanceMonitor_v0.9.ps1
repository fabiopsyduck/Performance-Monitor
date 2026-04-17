# ==============================================================================
# AUTO-RELAUNCH TURBO & DUAL-MODE (PS1 / EXE)
# ==============================================================================
param([switch]$GhostMode)

# Descobre o caminho real do processo que esta rodando
$Script:ProcessPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$Script:IsCompiled = -not ($Script:ProcessPath -match "(?i)powershell\.exe$|pwsh\.exe$|powershell_ise\.exe$")
$Global:ArquivoReal = if ($Script:IsCompiled) { $Script:ProcessPath } else { $PSCommandPath }

# --- LEITURA RAPIDA DO CONFIG.INI PARA ELEVACAO DINAMICA ---
$BaseDir = if ($Script:IsCompiled) { [System.IO.Path]::GetDirectoryName($Script:ProcessPath) } else { $PSScriptRoot }
if ([string]::IsNullOrEmpty($BaseDir)) { $BaseDir = (Get-Location).Path }
$quickConfigFile = "$BaseDir\Config.ini"

$requireAdmin = $false
if (Test-Path $quickConfigFile) {
    $quickContent = Get-Content $quickConfigFile -Raw -ErrorAction SilentlyContinue
    if ($quickContent -match '"RequireAdmin"\s*:\s*true') {
        $requireAdmin = $true
    }
}

# Verifica Privilegios Atuais
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
$script:IsAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

# Logica de Inicializacao Mestra
if ($requireAdmin -and -not $script:IsAdmin) {
    # Precisa de Admin mas nao e. Relanca pedindo UAC e com GhostMode
    if ($Script:IsCompiled) {
        Start-Process -FilePath $Script:ProcessPath -WindowStyle Hidden -ArgumentList "-GhostMode" -Verb RunAs
    } else {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile", "-NoLogo", "-ExecutionPolicy Bypass", "-File `"$PSCommandPath`"", "-GhostMode" -Verb RunAs
    }
    Exit
}
elseif (-not $GhostMode) {
    # Relanca silencioso normal
    if ($Script:IsCompiled) {
        Start-Process -FilePath $Script:ProcessPath -WindowStyle Hidden -ArgumentList "-GhostMode"
    } else {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile", "-NoLogo", "-ExecutionPolicy Bypass", "-File `"$PSCommandPath`"", "-GhostMode"
    }
    Exit
}

# Carrega bibliotecas graficas
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web.Extensions 

# ==============================================================================
# 0. GLOBAL MUTEX (Instancia Unica)
# ==============================================================================
# Nome atualizado e limpo (Pode alterar como quiser, mas mantenha o Global\)
$mutexName = "Global\PerformanceMonitor_Fabiopsyduck" 
$createdNew = $false
$script:AppMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)

if (-not $createdNew) {
    # POPUP CUSTOMIZADO DE AVISO (Caminho 2 - 100% Blindado)
    $frmMutex = New-Object System.Windows.Forms.Form; $frmMutex.Size = New-Object System.Drawing.Size(350, 150); $frmMutex.StartPosition = "CenterScreen"; $frmMutex.TopMost = $true; $frmMutex.FormBorderStyle = "None"; $frmMutex.BackColor = [System.Drawing.Color]::DimGray; $frmMutex.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None; $frmMutex.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    
    $pnlMHeader = New-Object System.Windows.Forms.Panel; $pnlMHeader.Size = "350, 30"; $pnlMHeader.Location = "0, 0"; $pnlMHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmMutex.Controls.Add($pnlMHeader)
    $lblMHeader = New-Object System.Windows.Forms.Label; $lblMHeader.Text = "Warning"; $lblMHeader.Location = "10, 7"; $lblMHeader.AutoSize = $true; $lblMHeader.ForeColor = [System.Drawing.Color]::White; $lblMHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlMHeader.Controls.Add($lblMHeader)
    
    $btnMClose = New-Object System.Windows.Forms.Button; $btnMClose.Text = "X"; $btnMClose.Size = "40, 30"; $btnMClose.Location = "310, 0"; $btnMClose.FlatStyle = "Flat"; $btnMClose.FlatAppearance.BorderSize = 0; $btnMClose.ForeColor = [System.Drawing.Color]::White; $btnMClose.BackColor = [System.Drawing.Color]::Transparent; $btnMClose.Cursor = [System.Windows.Forms.Cursors]::Hand; $pnlMHeader.Controls.Add($btnMClose)
    $btnMClose.Add_Click({ $frmMutex.Close() }); $btnMClose.Add_MouseEnter({ $btnMClose.BackColor = [System.Drawing.Color]::Firebrick }); $btnMClose.Add_MouseLeave({ $btnMClose.BackColor = [System.Drawing.Color]::Transparent })

    $Script:MDragging = $false; $Script:MStartX = 0; $Script:MStartY = 0; $Script:MFormStartX = 0; $Script:MFormStartY = 0
    $MDragDown = { param($s, $e) if ($e.Button -eq 'Left') { $Script:MDragging = $true; $Script:MStartX = [System.Windows.Forms.Cursor]::Position.X; $Script:MStartY = [System.Windows.Forms.Cursor]::Position.Y; $Script:MFormStartX = $frmMutex.Location.X; $Script:MFormStartY = $frmMutex.Location.Y } }
    $MDragMove = { param($s, $e) if ($Script:MDragging) { $diffX = [System.Windows.Forms.Cursor]::Position.X - $Script:MStartX; $diffY = [System.Windows.Forms.Cursor]::Position.Y - $Script:MStartY; $frmMutex.Location = New-Object System.Drawing.Point(($Script:MFormStartX + $diffX), ($Script:MFormStartY + $diffY)) } }
    $MDragUp = { $Script:MDragging = $false }
    $pnlMHeader.Add_MouseDown($MDragDown); $pnlMHeader.Add_MouseMove($MDragMove); $pnlMHeader.Add_MouseUp($MDragUp); $lblMHeader.Add_MouseDown($MDragDown); $lblMHeader.Add_MouseMove($MDragMove); $lblMHeader.Add_MouseUp($MDragUp)

    $pnlMContent = New-Object System.Windows.Forms.Panel; $pnlMContent.Size = "348, 119"; $pnlMContent.Location = "1, 30"; $pnlMContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmMutex.Controls.Add($pnlMContent)
    
    $lblMMsg = New-Object System.Windows.Forms.Label; $lblMMsg.Text = "Performance Monitor is already running!"; $lblMMsg.Location = "20, 25"; $lblMMsg.Size = "310, 40"; $lblMMsg.AutoSize = $false; $pnlMContent.Controls.Add($lblMMsg)
    
    $btnMOk = New-Object System.Windows.Forms.Button; $btnMOk.Text = "OK"; $btnMOk.Location = "115, 70"; $btnMOk.Size = "120, 30"; $btnMOk.BackColor = [System.Drawing.Color]::DarkOrange; $btnMOk.ForeColor = [System.Drawing.Color]::White; $btnMOk.FlatStyle = "Flat"; $btnMOk.Add_Click({ $frmMutex.Close() }); $pnlMContent.Controls.Add($btnMOk)
    
    [void]$frmMutex.ShowDialog()
    exit
}

# ==============================================================================
# 0.1. DEFINIÇÃO C# (WIN32 API)
# ==============================================================================
$win32Source = @'
using System;
using System.Runtime.InteropServices;

public class Win32Native {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
}
'@

if (-not ([System.Management.Automation.PSTypeName]'Win32Native').Type) {
    Add-Type -TypeDefinition $win32Source -Language CSharp
}

$GWL_EXSTYLE = -20
$WS_EX_LAYERED = 0x80000
$WS_EX_TRANSPARENT = 0x20

# ==============================================================================
# 1. GESTÃO DE CONFIGURAÇÃO (Config.ini)
# ==============================================================================

# Define o diretório base corretamente, independente de ser .ps1 ou .exe
if ($Script:IsCompiled) {
    # Pega a pasta onde o .exe está localizado fisicamente
    $BaseDir = [System.IO.Path]::GetDirectoryName($Script:ProcessPath)
} else {
    # Pega a pasta do .ps1
    $BaseDir = $PSScriptRoot
    
    # Fallback de segurança (caso a variável venha vazia)
    if ([string]::IsNullOrEmpty($BaseDir)) { 
        $BaseDir = (Get-Location).Path 
    }
}

$ConfigFile = "$BaseDir\Config.ini"

if (-not (Test-Path $ConfigFile)) {
    New-Item -Path $ConfigFile -ItemType File -Force | Out-Null
}

# Dados Padrão
$Global:ConfigData = @{ 
    BackOpacity = 0.99; 
    ContentOpacity = 1.0; 
    PosX = $null; 
    PosY = $null; 
    StartLocked = $false;
    RequireAdmin = $false;
    
    # Adaptive Sampling
    AdaptiveEnabled = $false;
    AdaptiveTrigger = $null;
    AdaptiveApplyText = $false;
    AdaptiveApplyBar = $false;
    
    # Frequency Control
    FreqEnabled = $false;
    FreqValue = 200; 

    # SPIKE PROTECTION
    SpikeProtection = $false;
    SpikeTolerance = 15;
    
    # FILTROS
    AdaptiveRolling = $false;
    AdaptiveEma = $false;
    AdaptiveDema = $false;
    AdaptiveAlma = $false; 
    AdaptiveHysteresis = $false;
    
    # Alvos
    AdaptiveTargetCpu = $false;
    AdaptiveTargetRam = $false;
    AdaptiveTargetGpu = $false;
    AdaptiveTargetVram = $false;

    # Hotkey
    HotkeyEnabled = $false;
    HotkeyMode = $null;
    HotkeyPrimary = $null;
    HotkeySecondary = $null;
    HotkeySeconds = $null;
    
    # Hidden Start & Minimize & Close
    StartHidden = $false;
    MinimizeToTray = $false;
    CloseToTray = $false
}

$Content = Get-Content $ConfigFile -Raw -ErrorAction SilentlyContinue
if ($Content) {
    try {
        $Loaded = $Content | ConvertFrom-Json
        foreach ($key in $Loaded.PSObject.Properties.Name) {
            $Global:ConfigData[$key] = $Loaded.$key
        }
        if ($Global:ConfigData.BackOpacity -ge 1.0) { $Global:ConfigData.BackOpacity = 0.99 }
        # Validação Freq
        if (-not $Global:ConfigData.FreqValue) { $Global:ConfigData.FreqValue = 200 }
        $Global:HasPreviousConfig = $true
    } catch {
        $Global:HasPreviousConfig = $false
    }
} else {
    $Global:HasPreviousConfig = $false
}

$Script:AdvancedChanged = $false
$Script:IsHidden = $false
$Script:HoldStartTime = 0
$Script:KeyLatch = $false

# === DEFINIÇÃO INICIAL DE VISIBILIDADE ===
if ($Global:ConfigData.StartHidden) {
    $Script:IsHidden = $true
    $InitialBackOp = 0
    $InitialContOp = 0
    $InitialOverOp = 0
} else {
    $Script:IsHidden = $false
    $InitialBackOp = $Global:ConfigData.BackOpacity
    if ($InitialBackOp -lt 0.01) { $InitialBackOp = 0.01 }
    $InitialContOp = $Global:ConfigData.ContentOpacity
    $InitialOverOp = 1.0
}

# ==============================================================================
# 2. BUFFER & WORKER (NATIVE C# ENGINE - HIGH PERFORMANCE)
# ==============================================================================
$SyncHash = [hashtable]::Synchronized(@{})
$SyncHash.CpuVal = 0; $SyncHash.CpuPercText = "0"
$SyncHash.RamVal = 0; $SyncHash.RamPercText = "0"; $SyncHash.RamDetText = "..."
$SyncHash.GpuVal = 0; $SyncHash.GpuPercText = "0"; $SyncHash.GpuTempText = "Temp: -- C"
$SyncHash.VramVal = 0; $SyncHash.VramPercText = "0"; $SyncHash.VramDetText = "..."
$SyncHash.Rodar = $true

# Configuração Inicial de Frequência (Prioridade: Adaptive 150ms > Freq Manual > Padrão 50ms)
$SyncHash.SleepTime = if ($Global:ConfigData.AdaptiveEnabled) { 
    150 
} elseif ($Global:ConfigData.FreqEnabled) { 
    $Global:ConfigData.FreqValue 
} else { 
    200 
}

$WorkerScript = {
    param($Hash)

    # --- COMPILAÇÃO DO MOTOR C# NATIVO DENTRO DA THREAD ---
    $engineSource = @"
    using System;
    using System.Runtime.InteropServices;

    public class FastSensor {
        // RAM (Kernel32)
        [StructLayout(LayoutKind.Sequential)] public struct MEMORYSTATUSEX {
            public uint dwLength; public uint dwMemoryLoad; public ulong ullTotalPhys; public ulong ullAvailPhys;
            public ulong ullTotalPageFile; public ulong ullAvailPageFile; public ulong ullTotalVirtual;
            public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual;
        }
        [DllImport("kernel32.dll", EntryPoint="GlobalMemoryStatusEx")] public static extern bool GetMemStruct(ref MEMORYSTATUSEX lpBuffer);

        // CPU (PDH)
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)] public static extern uint PdhOpenQuery(IntPtr dataSource, IntPtr userData, out IntPtr query);
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)] public static extern uint PdhAddEnglishCounter(IntPtr query, string counterPath, IntPtr userData, out IntPtr counter);
        [DllImport("pdh.dll")] public static extern uint PdhCollectQueryData(IntPtr query);
        [DllImport("pdh.dll")] public static extern uint PdhGetFormattedCounterValue(IntPtr counter, uint format, out uint type, out PDH_FMT_COUNTERVALUE value);
        [StructLayout(LayoutKind.Explicit)] public struct PDH_FMT_COUNTERVALUE { [FieldOffset(0)] public uint CStatus; [FieldOffset(8)] public double doubleValue; }
        
        // --- FUNÇÕES DE LIMPEZA (MEMORY LEAK PREVENTION) ---
        [DllImport("pdh.dll")] public static extern uint PdhCloseQuery(IntPtr query);
        [DllImport("nvml.dll")] public static extern int nvmlShutdown();
        
        private static IntPtr hQueryCpu = IntPtr.Zero, hCounterCpu = IntPtr.Zero;

        // GPU & VRAM (NVML)
        [DllImport("nvml.dll")] public static extern int nvmlInit_v2();
        [DllImport("nvml.dll")] public static extern int nvmlDeviceGetHandleByIndex_v2(uint index, out IntPtr device);
        [DllImport("nvml.dll")] public static extern int nvmlDeviceGetUtilizationRates(IntPtr device, out nvmlUtilization_t utilization);
        [DllImport("nvml.dll")] public static extern int nvmlDeviceGetMemoryInfo(IntPtr device, out nvmlMemory_t memory);
        [DllImport("nvml.dll")] public static extern int nvmlDeviceGetTemperature(IntPtr device, int sensorType, out uint temp);

        [StructLayout(LayoutKind.Sequential)] public struct nvmlUtilization_t { public uint gpu; public uint memory; }
        [StructLayout(LayoutKind.Sequential)] public struct nvmlMemory_t { public ulong total; public ulong free; public ulong used; }

        private static IntPtr nvmlDevice = IntPtr.Zero;
        private static bool nvmlReady = false;

        public static void Init() {
            try {
                PdhOpenQuery(IntPtr.Zero, IntPtr.Zero, out hQueryCpu);
                PdhAddEnglishCounter(hQueryCpu, "\\Processor Information(_Total)\\% Processor Utility", IntPtr.Zero, out hCounterCpu);
                PdhCollectQueryData(hQueryCpu);
            } catch {}

            try {
                if (nvmlInit_v2() == 0 && nvmlDeviceGetHandleByIndex_v2(0, out nvmlDevice) == 0) nvmlReady = true;
            } catch {}
        }

        // === EXECUTA QUANDO O SCRIPT FECHA ===
        public static void CloseAll() {
            if (hQueryCpu != IntPtr.Zero) { PdhCloseQuery(hQueryCpu); hQueryCpu = IntPtr.Zero; }
            if (nvmlReady) { try { nvmlShutdown(); } catch {} }
        }

        public static int GetCpu() {
            uint type; PDH_FMT_COUNTERVALUE val;
            PdhCollectQueryData(hQueryCpu);
            if (PdhGetFormattedCounterValue(hCounterCpu, 0x200, out type, out val) == 0) return (int)Math.Round(val.doubleValue);
            return 0;
        }

        public static string GetRam() {
            MEMORYSTATUSEX mem = new MEMORYSTATUSEX(); mem.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            if (GetMemStruct(ref mem)) {
                ulong totalMB = mem.ullTotalPhys >> 20;
                ulong freeMB = mem.ullAvailPhys >> 20;
                ulong usedMB = totalMB - freeMB;
                double load = ((double)usedMB / totalMB) * 100.0;
                return Math.Round(load) + ";" + usedMB + ";" + freeMB;
            }
            return "0;0;0";
        }

        public static string GetGpu() {
            if (!nvmlReady) return "-1";
            nvmlUtilization_t ut = new nvmlUtilization_t();
            nvmlMemory_t mi = new nvmlMemory_t();
            uint temp = 0;
            
            nvmlDeviceGetUtilizationRates(nvmlDevice, out ut);
            nvmlDeviceGetMemoryInfo(nvmlDevice, out mi);
            nvmlDeviceGetTemperature(nvmlDevice, 0, out temp);

            ulong vTotal = mi.total >> 20; 
            ulong vUsed = mi.used >> 20; 
            ulong vFree = mi.free >> 20;
            double vLoad = vTotal > 0 ? ((double)vUsed / vTotal) * 100.0 : 0;

            return ut.gpu + ";" + temp + ";" + Math.Round(vLoad) + ";" + vUsed + ";" + vFree;
        }
    }
"@
    Add-Type -TypeDefinition $engineSource -Language CSharp -ErrorAction SilentlyContinue

    # Inicializa os sensores nativos
    [FastSensor]::Init()

    function Format-MB ($val) { 
        $str = ([int]$val).ToString("N0").Replace(",", ".")
        return $str.PadLeft(7) 
    }

    while ($Hash.Rodar) {
        # --- CPU (PDH) ---
        try {
            $newCpu = [FastSensor]::GetCpu()
            $Hash.CpuVal = $newCpu
            $Hash.CpuPercText = "$newCpu"
        } catch { $Hash.CpuPercText = "Err" }

        # --- RAM (Kernel32) ---
        try {
            $ramData = [FastSensor]::GetRam().Split(';')
            $Hash.RamVal = [int]$ramData[0]
            $Hash.RamPercText = $ramData[0]
            $Hash.RamDetText = "Used: $(Format-MB $ramData[1]) MB / Free: $(Format-MB $ramData[2]) MB"
        } catch { $Hash.RamPercText = "Err" }

        # --- GPU & VRAM (NVML) ---
        try {
            $gpuData = [FastSensor]::GetGpu()
            if ($gpuData -ne "-1") {
                $g = $gpuData.Split(';')
                $Hash.GpuVal = [int]$g[0]
                $Hash.GpuPercText = $g[0]
                $Hash.GpuTempText = "Temp: $($g[1]) C"
                
                $Hash.VramVal = [int]$g[2]
                $Hash.VramPercText = $g[2]
                $Hash.VramDetText = "Used: $(Format-MB $g[3]) MB / Free: $(Format-MB $g[4]) MB"
            } else {
                $Hash.GpuPercText = "--"; $Hash.VramPercText = "--"
            }
        } catch { $Hash.GpuPercText = "Err"; $Hash.VramPercText = "Err" }
        
        # SLEEP DINAMICO (HOT RELOAD)
        Start-Sleep -Milliseconds $Hash.SleepTime
    }

    # === PREVENÇÃO DE MEMORY LEAK (Roda quando $Hash.Rodar vira $false) ===
    [FastSensor]::CloseAll()
}

$Runspace = [powershell]::Create()
[void]$Runspace.AddScript($WorkerScript).AddArgument($SyncHash)
$AsyncResult = $Runspace.BeginInvoke()

# ==============================================================================
# 3. INTERFACE PRINCIPAL
# ==============================================================================
$formBack = New-Object System.Windows.Forms.Form; $formBack.Text = "Performance Monitor"; $formBack.FormBorderStyle = "None"; $formBack.ShowInTaskbar = -not $Global:ConfigData.StartHidden; $formBack.Size = New-Object System.Drawing.Size(335, 215); $formBack.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$formBack.Opacity = $InitialBackOp
$formBack.TopMost = $true
$formBack.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None # <--- TRAVA ABSOLUTA DA JANELA APLICADA AQUI
if ($Global:ConfigData.PosX -ne $null) { $formBack.StartPosition = "Manual"; $formBack.Location = New-Object System.Drawing.Point($Global:ConfigData.PosX, $Global:ConfigData.PosY) } else { $formBack.StartPosition = "CenterScreen" }

$form = New-Object System.Windows.Forms.Form; $form.Text = "Performance Monitor"; $form.Size = New-Object System.Drawing.Size(335, 215); $form.FormBorderStyle = "None"; $form.MaximizeBox = $false; $form.ShowInTaskbar = $false; $form.TopMost = $true; $form.BackColor = [System.Drawing.Color]::Black; $form.TransparencyKey = [System.Drawing.Color]::Black
$form.Opacity = $InitialContOp
$form.Owner = $formBack; $form.StartPosition = "Manual" 
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None # <--- TRAVA ABSOLUTA DA JANELA APLICADA AQUI

# <--- TRAVA DE PÍXEIS APLICADA NAS 3 FONTES DA INTERFACE --->
$fontTitle = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fontVal = New-Object System.Drawing.Font("Consolas", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fontDet = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

$colText = [System.Drawing.Color]::White; $colGray = [System.Drawing.Color]::LightGray; $colFrame = [System.Drawing.Color]::FromArgb(80, 80, 80); $colBackBar = [System.Drawing.Color]::FromArgb(40, 40, 40); $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(20, 20, 20))

function New-MonitorBlock {
    param($YPos, $Title, $HasBottomText)
    $AddShadow = { param($sender, $e) $g = $e.Graphics; $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit; $g.DrawString($sender.Text, $sender.Font, $script:shadowBrush, 1, 1); $foreBrush = New-Object System.Drawing.SolidBrush($sender.Tag); $g.DrawString($sender.Text, $sender.Font, $foreBrush, 0, 0) }
    $lblTitle = New-Object System.Windows.Forms.Label; $lblTitle.Text = $Title; $lblTitle.Location = New-Object System.Drawing.Point(5, ($YPos - 5)); $lblTitle.Tag = [System.Drawing.Color]::LimeGreen; $lblTitle.ForeColor = [System.Drawing.Color]::Empty; $lblTitle.Font = $fontTitle; $lblTitle.AutoSize = $true; $lblTitle.Add_Paint($AddShadow); [void]$form.Controls.Add($lblTitle)
    $pnlFrame = New-Object System.Windows.Forms.Panel; $pnlFrame.Location = New-Object System.Drawing.Point(5, ($YPos + 17)); $pnlFrame.Size = New-Object System.Drawing.Size(282, 14); $pnlFrame.BackColor = $colFrame; [void]$form.Controls.Add($pnlFrame)
    $pnlBack = New-Object System.Windows.Forms.Panel; $pnlBack.Location = New-Object System.Drawing.Point(1, 1); $pnlBack.Size = New-Object System.Drawing.Size(280, 12); $pnlBack.BackColor = $colBackBar; [void]$pnlFrame.Controls.Add($pnlBack)
    $pnlFill = New-Object System.Windows.Forms.Panel; $pnlFill.Location = New-Object System.Drawing.Point(0, 0); $pnlFill.Size = New-Object System.Drawing.Size(0, 12); $pnlFill.BackColor = [System.Drawing.Color]::White; [void]$pnlBack.Controls.Add($pnlFill)
    
    # Nota: A posição e o tamanho do lblVal mantêm-se exatamente iguais (Size: 30, 20), mas agora o texto caberá perfeitamente sem cortar.
    $lblVal = New-Object System.Windows.Forms.Label; $lblVal.Text = "0"; $lblVal.Location = New-Object System.Drawing.Point(288, ($YPos + 16)); $lblVal.Size = New-Object System.Drawing.Size(30, 20); $lblVal.Tag = $colText; $lblVal.ForeColor = [System.Drawing.Color]::Empty; $lblVal.Font = $fontVal; $lblVal.AutoSize = $false; $lblVal.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight; $lblVal.Add_Paint($AddShadow); [void]$form.Controls.Add($lblVal)
    
    $lblSym = New-Object System.Windows.Forms.Label; $lblSym.Text = "%"; $lblSym.Location = New-Object System.Drawing.Point(318, ($YPos + 16)); $lblSym.Tag = $colText; $lblSym.ForeColor = [System.Drawing.Color]::Empty; $lblSym.Font = $fontVal; $lblSym.AutoSize = $true; $lblSym.Add_Paint($AddShadow); [void]$form.Controls.Add($lblSym)
    
    $lblBottom = $null
    if ($HasBottomText) { $lblBottom = New-Object System.Windows.Forms.Label; $lblBottom.Text = "..."; $lblBottom.Location = New-Object System.Drawing.Point(5, ($YPos + 32)); $lblBottom.Tag = $colGray; $lblBottom.ForeColor = [System.Drawing.Color]::Empty; $lblBottom.Font = $fontDet; $lblBottom.AutoSize = $true; $lblBottom.Add_Paint($AddShadow); [void]$form.Controls.Add($lblBottom) }
    
    return @{ "Bar"=$pnlFill; "LblVal"=$lblVal; "LblBottom"=$lblBottom; "MaxWidth"=280; "Frame"=$pnlFrame }
}

$uiCpu = New-MonitorBlock 15 "CPU Usage" $false; $uiRam = New-MonitorBlock 58 "RAM Usage" $true; $uiGpu = New-MonitorBlock 113 "GPU Usage" $true; $uiVram = New-MonitorBlock 168 "GPU Memory Usage" $true

# ==============================================================================
# 4. OVERLAY
# ==============================================================================
if ($overlay -and !$overlay.IsDisposed) { $overlay.Close() }
$overlay = New-Object System.Windows.Forms.Form; $overlay.FormBorderStyle = "None"; $overlay.ControlBox = $false; $overlay.ShowInTaskbar = $false; $overlay.TopMost = $true; $overlay.StartPosition = "Manual"; $overlay.Size = New-Object System.Drawing.Size(335, 25); $overlay.Owner = $formBack; $colTrans = [System.Drawing.Color]::Magenta; $overlay.BackColor = $colTrans; $overlay.TransparencyKey = $colTrans
$overlay.Opacity = $InitialOverOp
$overlay.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None # <--- TRAVA ABSOLUTA NO OVERLAY

$pnlCfg = New-Object System.Windows.Forms.Panel; $pnlCfg.Size = New-Object System.Drawing.Size(30, 18); $pnlCfg.Location = New-Object System.Drawing.Point(187, 4); $pnlCfg.BackColor = [System.Drawing.Color]::DodgerBlue; $pnlCfg.Cursor = [System.Windows.Forms.Cursors]::Hand
# <--- FONTE DO CFG TRAVADA EM 9 PÍXEIS --->
$lblCfg = New-Object System.Windows.Forms.Label; $lblCfg.Text = "CFG"; $lblCfg.Dock = "Fill"; $lblCfg.TextAlign = "MiddleCenter"; $lblCfg.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $lblCfg.ForeColor = [System.Drawing.Color]::White; [void]$pnlCfg.Controls.Add($lblCfg); [void]$overlay.Controls.Add($pnlCfg)

$pnlLock = New-Object System.Windows.Forms.Panel; $pnlLock.Size = New-Object System.Drawing.Size(45, 18); $pnlLock.Location = New-Object System.Drawing.Point(221, 4); $pnlLock.BackColor = [System.Drawing.Color]::Orange; $pnlLock.Cursor = [System.Windows.Forms.Cursors]::Hand
# <--- FONTE DO LOCK TRAVADA EM 9 PÍXEIS --->
$lblSat = New-Object System.Windows.Forms.Label; $lblSat.Text = "LOCK"; $lblSat.Dock = "Fill"; $lblSat.TextAlign = "MiddleCenter"; $lblSat.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); [void]$pnlLock.Controls.Add($lblSat); [void]$overlay.Controls.Add($pnlLock)

# <--- FONTE DO MINIMIZAR (_) TRAVADA EM 11 PÍXEIS --->
$btnMinRep = New-Object System.Windows.Forms.Label; $btnMinRep.Text = "_"; $btnMinRep.Size = New-Object System.Drawing.Size(30, 18); $btnMinRep.Location = New-Object System.Drawing.Point(268, 4); $btnMinRep.ForeColor = [System.Drawing.Color]::White; $btnMinRep.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60); $btnMinRep.TextAlign = "MiddleCenter"; $btnMinRep.Font = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $btnMinRep.Cursor = [System.Windows.Forms.Cursors]::Hand; 

# LÓGICA DE MINIMIZAR ATUALIZADA (V52)
$btnMinRep.Add_Click({ 
    if ($Global:ConfigData.MinimizeToTray) { & $script:ToggleViewState } 
    else { $formBack.WindowState = "Minimized" } 
})
[void]$overlay.Controls.Add($btnMinRep)

# <--- FONTE DO FECHAR (X) TRAVADA EM 11 PÍXEIS --->
$btnCloseRep = New-Object System.Windows.Forms.Label; $btnCloseRep.Text = "X"; $btnCloseRep.Size = New-Object System.Drawing.Size(30, 18); $btnCloseRep.Location = New-Object System.Drawing.Point(300, 4); $btnCloseRep.ForeColor = [System.Drawing.Color]::White; $btnCloseRep.BackColor = [System.Drawing.Color]::FromArgb(192, 0, 0); $btnCloseRep.TextAlign = "MiddleCenter"; $btnCloseRep.Font = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $btnCloseRep.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnCloseRep.Add_Click({ $formBack.Close() }); [void]$overlay.Controls.Add($btnCloseRep)

# =========================================================
# 5. LÓGICA DE TRAVA (LOCK/UNLOCK)
# =========================================================
$script:ModoFantasma = $false 
$ClickLock = {
    if ($script:ModoFantasma) {
        $script:ModoFantasma = $false
        if ($formBack.Opacity -ge 1.0) { $formBack.Opacity = $Global:ConfigData.BackOpacity } 
        $hBack = $formBack.Handle; $styleB = [Win32Native]::GetWindowLong($hBack, $GWL_EXSTYLE)
        if ($styleB -band $WS_EX_TRANSPARENT) { [Win32Native]::SetWindowLong($hBack, $GWL_EXSTYLE, $styleB -bxor $WS_EX_TRANSPARENT) }
        $hFore = $form.Handle; $styleF = [Win32Native]::GetWindowLong($hFore, $GWL_EXSTYLE)
        if ($styleF -band $WS_EX_TRANSPARENT) { [Win32Native]::SetWindowLong($hFore, $GWL_EXSTYLE, $styleF -bxor $WS_EX_TRANSPARENT) }
        $pnlLock.BackColor = [System.Drawing.Color]::Orange; $lblSat.Text = "LOCK"; $btnMinRep.Visible = $true; $btnCloseRep.Visible = $true; $pnlCfg.Visible = $true 
    } else {
        $script:ModoFantasma = $true
        if ($formBack.Opacity -ge 1.0) { $formBack.Opacity = 0.99 } 
        $hBack = $formBack.Handle; $styleB = [Win32Native]::GetWindowLong($hBack, $GWL_EXSTYLE)
        [Win32Native]::SetWindowLong($hBack, $GWL_EXSTYLE, $styleB -bor $WS_EX_TRANSPARENT -bor $WS_EX_LAYERED)
        $hFore = $form.Handle; $styleF = [Win32Native]::GetWindowLong($hFore, $GWL_EXSTYLE)
        [Win32Native]::SetWindowLong($hFore, $GWL_EXSTYLE, $styleF -bor $WS_EX_TRANSPARENT -bor $WS_EX_LAYERED)
        $pnlLock.BackColor = [System.Drawing.Color]::LimeGreen; $lblSat.Text = "UNLOCK"; $btnMinRep.Visible = $false; $btnCloseRep.Visible = $false; $pnlCfg.Visible = $false 
    }
}
$lblSat.Add_Click($ClickLock); $pnlLock.Add_Click($ClickLock)

# =========================================================
# 6. SINCRONIA TOTAL
# =========================================================
$script:SyncOverlayPosition = {
    if ($formBack.WindowState -eq "Minimized") {
        # DO NOTHING
    } 
    else {
        if (-not $Script:IsHidden) {
            if (-not $overlay.Visible) { $overlay.Show() }; if (-not $form.Visible) { $form.Show() }
            $form.Location = $formBack.Location; $overlay.Location = New-Object System.Drawing.Point($formBack.Location.X, $formBack.Location.Y)
        }
    }
}
$formBack.Add_Move({ & $script:SyncOverlayPosition }); $formBack.Add_Resize({ & $script:SyncOverlayPosition })

# ==============================================================================
# LÓGICA DE SHOW/HIDE (CORRIGIDA - RESTAURA OPACIDADE E BOTOES)
# ==============================================================================
$script:ToggleViewState = {
    # Verifica se a janela está visível E se tem opacidade
    if ($formBack.Visible -and $formBack.Opacity -gt 0.01) {
        # --- HIDE (ESCONDER) ---
        $Script:IsHidden = $true
        
        # Minimiza para garantir limpeza
        $formBack.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
        
        # === AQUI ESTÁ O SEGREDO DO ICONE ===
        # Remove o icone da barra de tarefas explicitamente
        $formBack.ShowInTaskbar = $false 
        
        $formBack.Hide()
        $form.Hide()
        $overlay.Hide()
    } else {
        # --- SHOW (MOSTRAR) ---
        $Script:IsHidden = $false
        
        # === TRAZ O ÍCONE DE VOLTA ANTES DE MOSTRAR ===
        $formBack.ShowInTaskbar = $true
        
        $formBack.Show()
        $form.Show()
        $overlay.Show()
        
        # Restaura a opacidade
        $restoredOp = $Global:ConfigData.BackOpacity
        if ($restoredOp -lt 0.01) { $restoredOp = 0.99 }
        
        $formBack.Opacity = $restoredOp
        $form.Opacity = $Global:ConfigData.ContentOpacity
        $overlay.Opacity = 1.0 
        
        # Restaura estado da janela para Normal (tira do minimizado)
        $formBack.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $formBack.Activate()
        
        # Ressincroniza
        $form.Location = $formBack.Location
        $form.Size = $formBack.Size
        $overlay.Location = New-Object System.Drawing.Point($formBack.Location.X, $formBack.Location.Y)
        $overlay.BringToFront()
    }
}

# =========================================================
# 8. SYSTEM TRAY ICON (SEGOE MDL2 ASSETS DYNAMIC ICON)
# =========================================================
$script:RealExit = $false

# 1. Detecta o Tema do Windows (Claro = 1, Escuro = 0 ou Não Encontrado)
$themeRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
$useLightTheme = 0
try { 
    $useLightTheme = (Get-ItemProperty -Path $themeRegPath -Name SystemUsesLightTheme -ErrorAction SilentlyContinue).SystemUsesLightTheme 
} catch {}

# Se for claro (1), desenha preto. Se for escuro (0), desenha branco.
$iconColor = if ($useLightTheme -eq 1) { [System.Drawing.Color]::Black } else { [System.Drawing.Color]::White }

# 2. Função que desenha o Ícone na memória
function Create-DynamicTrayIcon {
    param([System.Drawing.Color]$Color)
    
    # Usar 32x32 garante alta resolução (High DPI)
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    
    # Fonte e Pincel
    $font = New-Object System.Drawing.Font("Segoe MDL2 Assets", 22, [System.Drawing.FontStyle]::Regular)
    $brush = New-Object System.Drawing.SolidBrush($Color)
    
    # Centralização Matemática
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF(0, 0, 32, 32)
    
    # O caractere E9D9 (Diagnostic / Heartbeat)
    $g.DrawString([char]0xE9D9, $font, $brush, $rect, $format)
    
    # Converte a imagem gerada para um Ícone do Windows
    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    
    # Limpa a memória de desenho
    $g.Dispose(); $font.Dispose(); $brush.Dispose()
    
    return $icon
}

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon

# Tenta usar o ícone dinâmico. Se a fonte não existir no PC, usa um ícone padrão.
try { 
    $notifyIcon.Icon = Create-DynamicTrayIcon -Color $iconColor 
} catch { 
    $notifyIcon.Icon = [System.Drawing.SystemIcons]::Application 
}

# --- APLICA O ÍCONE DINÂMICO NA BARRA DE TAREFAS E NAS JANELAS ---
$formBack.Icon = $notifyIcon.Icon
$form.Icon = $notifyIcon.Icon

$notifyIcon.Text = "Performance Monitor"
$ctxMenu = New-Object System.Windows.Forms.ContextMenuStrip
$itemShow = $ctxMenu.Items.Add("Show / Hide"); $itemShow.Add_Click({ & $script:ToggleViewState })
$itemSep  = $ctxMenu.Items.Add("-")

# --- BOTÃO EXIT COM A CHAVE MESTRA ---
$itemExit = $ctxMenu.Items.Add("Exit"); 
$itemExit.Add_Click({ 
    $script:RealExit = $true   # <--- ISSO AUTORIZA O FECHAMENTO REAL
    $formBack.Close() 
})
# -----------------------------------------------------

$notifyIcon.ContextMenuStrip = $ctxMenu; $notifyIcon.Visible = $true; $notifyIcon.Add_DoubleClick({ & $script:ToggleViewState })

# =========================================================
# 9. LÓGICA DE AMOSTRAGEM ADAPTATIVA (PIPELINE COMPLETO V43)
# =========================================================
$script:QueueCpu = New-Object System.Collections.Queue; $script:QueueRam = New-Object System.Collections.Queue
$script:QueueGpu = New-Object System.Collections.Queue; $script:QueueVram = New-Object System.Collections.Queue
$script:LastCpu = 0; $script:LastRam = 0; $script:LastGpu = 0; $script:LastVram = 0

# EMA Memory
$script:EmaCpu = 0; $script:EmaRam = 0; $script:EmaGpu = 0; $script:EmaVram = 0
# DEMA Extra Memory
$script:DemaEma1Cpu = 0; $script:DemaEma2Cpu = 0
$script:DemaEma1Ram = 0; $script:DemaEma2Ram = 0
$script:DemaEma1Gpu = 0; $script:DemaEma2Gpu = 0
$script:DemaEma1Vram = 0; $script:DemaEma2Vram = 0
# KAMA Memory
$script:KamaCpu = 0; $script:KamaRam = 0; $script:KamaGpu = 0; $script:KamaVram = 0

function Get-Median {
    param($Queue)
    $arr = $Queue.ToArray()
    [Array]::Sort($arr)
    return $arr[[math]::Floor($arr.Length / 2)]
}

# --- PRÉ-CÁLCULO ALMA ---
$script:AlmaWindow = 9; $script:AlmaOffset = 0.85; $script:AlmaSigma = 6
$script:AlmaWeights = New-Object Double[] $script:AlmaWindow
$m = [math]::Floor($script:AlmaOffset * ($script:AlmaWindow - 1))
$s = $script:AlmaWindow / $script:AlmaSigma
$wSum = 0
for ($i = 0; $i -lt $script:AlmaWindow; $i++) {
    $ex = -1 * [math]::Pow($i - $m, 2) / (2 * [math]::Pow($s, 2))
    $script:AlmaWeights[$i] = [math]::Exp($ex)
    $wSum += $script:AlmaWeights[$i]
}

function Apply-AdaptiveFilter {
    param($RawVal, $QueueRef, $LastRef, $EmaRef, $DemaRef1, $DemaRef2, $KamaRef)
    $Result = $RawVal
    
    # Gerenciamento de Filas
    $QueueRef.Enqueue($RawVal)
    if ($QueueRef.Count -gt 10) { $null = $QueueRef.Dequeue() }
    
    # SPIKE PROTECTION (Mantido)
    if ($Global:ConfigData.SpikeProtection) {
        if ($QueueRef.Count -ge 3) {
            $arr = $QueueRef.ToArray()
            $idx = $arr.Count - 1
            $nextVal = $arr[$idx]; $currVal = $arr[$idx - 1]; $prevVal = $arr[$idx - 2]
            
            if ($currVal -lt 80) {
                $isHigh = ($currVal -gt $prevVal) -and ($currVal -gt $nextVal)
                $isLow = ($currVal -lt $prevVal) -and ($currVal -lt $nextVal)
                if ($isHigh -or $isLow) {
                    $avgNeighbors = ($prevVal + $nextVal) / 2
                    $diff = [math]::Abs($currVal - $avgNeighbors)
                    if ($diff -gt $Global:ConfigData.SpikeTolerance) {
                        $dampened = ($prevVal + (2 * $currVal) + $nextVal) / 4
                        $Result = [math]::Round($dampened)
                    } else { $Result = $currVal }
                } else { $Result = $currVal }
            }
        }
    }

    # SELEÇÃO DE FILTRO (REMOVIDO MEDIAN E KAMA)
    if ($Global:ConfigData.AdaptiveRolling) {
        if ($QueueRef.Count -gt 0) {
             $arr = $QueueRef.ToArray(); $cnt = $arr.Count; $start = if($cnt -gt 5){ $cnt - 5 } else { 0 }
             $sum = 0; for($k=$start; $k -lt $cnt; $k++){ $sum += $arr[$k] }
             $div = $cnt - $start
             if ($div -gt 0) { $Result = [math]::Round($sum / $div) }
        }
    } elseif ($Global:ConfigData.AdaptiveEma) {
        $alpha = 0.3
        if ($EmaRef.Value -eq 0) { $EmaRef.Value = $Result }
        $EmaRef.Value = ($Result * $alpha) + ($EmaRef.Value * (1 - $alpha)) 
        $Result = [math]::Round($EmaRef.Value)
    } elseif ($Global:ConfigData.AdaptiveDema) {
        $alpha = 0.25
        if ($DemaRef1.Value -eq 0) { $DemaRef1.Value = $Result; $DemaRef2.Value = $Result }
        $DemaRef1.Value = ($Result * $alpha) + ($DemaRef1.Value * (1 - $alpha))
        $DemaRef2.Value = ($DemaRef1.Value * $alpha) + ($DemaRef2.Value * (1 - $alpha))
        $calcDema = (2 * $DemaRef1.Value) - $DemaRef2.Value
        if ($calcDema -lt 0) { $calcDema = 0 }; if ($calcDema -gt 100) { $calcDema = 100 }
        $Result = [math]::Round($calcDema)
    } elseif ($Global:ConfigData.AdaptiveAlma) {
        # ALMA (Window 9, Sigma 6, Offset 0.85)
        $arr = $QueueRef.ToArray()
        if ($arr.Count -ge 9) {
             $window = 9; $sigma = 6; $offset = 0.85
             $m = [math]::Floor($offset * ($window - 1))
             $s = $window / $sigma
             $num = 0; $den = 0
             $startIdx = $arr.Count - $window
             for ($i = 0; $i -lt $window; $i++) {
                 $wVal = $arr[$startIdx + $i]
                 $ex = -1 * [math]::Pow($i - $m, 2) / (2 * [math]::Pow($s, 2))
                 $weight = [math]::Exp($ex)
                 $num += ($wVal * $weight)
                 $den += $weight
             }
             if ($den -ne 0) { $Result = [math]::Round($num / $den) }
        }
    } elseif ($Global:ConfigData.AdaptiveHysteresis) {
        $diff = [math]::Abs($Result - $LastRef.Value)
        if ($diff -lt 2 -and $Result -ne 0 -and $Result -ne 100) { $Result = $LastRef.Value } else { $LastRef.Value = $Result }
    }

    return $Result
}

# =========================================================
# 10. LÓGICA DE HOTKEY
# =========================================================
$script:HotkeyIsWaiting = $false; $script:CapturedKey = $null

function Capture-Key {
    param($ButtonObj)
    $ButtonObj.Text = "Press any key..."
    $script:HotkeyIsWaiting = $true
    while ($script:HotkeyIsWaiting) {
        [System.Windows.Forms.Application]::DoEvents()
        for ($k = 1; $k -le 254; $k++) {
            $state = [Win32Native]::GetAsyncKeyState($k)
            if ($state -band 0x8000) {
                if ($k -gt 2) {
                    $keyName = [System.Windows.Forms.Keys]$k; $ButtonObj.Text = "$keyName"; $ButtonObj.Tag = $k; $script:HotkeyIsWaiting = $false; break
                }
            }
        }
        Start-Sleep -Milliseconds 10
    }
}

function Show-HotkeySettings {
    # 1. JANELA BLINDADA (CAMINHO 2)
    $frmHot = New-Object System.Windows.Forms.Form; $frmHot.Size = New-Object System.Drawing.Size(350, 480); $frmHot.StartPosition = "CenterScreen"; $frmHot.TopMost = $true; 
    $frmHot.FormBorderStyle = "None"; $frmHot.BackColor = [System.Drawing.Color]::DimGray
    $frmHot.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $frmHot.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

    # --- HEADER FRMHOT ---
    $pnlHotHeader = New-Object System.Windows.Forms.Panel; $pnlHotHeader.Size = "350, 30"; $pnlHotHeader.Location = "0, 0"; $pnlHotHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmHot.Controls.Add($pnlHotHeader)
    $lblHotHeader = New-Object System.Windows.Forms.Label; $lblHotHeader.Text = "Hotkey Settings"; $lblHotHeader.Location = "10, 7"; $lblHotHeader.AutoSize = $true; $lblHotHeader.ForeColor = [System.Drawing.Color]::White; $lblHotHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlHotHeader.Controls.Add($lblHotHeader)
    $btnHotClose = New-Object System.Windows.Forms.Button; $btnHotClose.Text = "X"; $btnHotClose.Size = "40, 30"; $btnHotClose.Location = "310, 0"; $btnHotClose.FlatStyle = "Flat"; $btnHotClose.FlatAppearance.BorderSize = 0; $btnHotClose.ForeColor = [System.Drawing.Color]::White; $btnHotClose.BackColor = [System.Drawing.Color]::Transparent; $btnHotClose.Cursor = [System.Windows.Forms.Cursors]::Hand; $pnlHotHeader.Controls.Add($btnHotClose)
    $btnHotClose.Add_Click({ $frmHot.Close() }); $btnHotClose.Add_MouseEnter({ $btnHotClose.BackColor = [System.Drawing.Color]::Firebrick }); $btnHotClose.Add_MouseLeave({ $btnHotClose.BackColor = [System.Drawing.Color]::Transparent })
    
    # --- DRAG FRMHOT ---
    $Script:HotDragging = $false; $Script:HotStartX = 0; $Script:HotStartY = 0; $Script:HotFormStartX = 0; $Script:HotFormStartY = 0
    $HotDragDown = { param($s, $e) if ($e.Button -eq 'Left') { $Script:HotDragging = $true; $Script:HotStartX = [System.Windows.Forms.Cursor]::Position.X; $Script:HotStartY = [System.Windows.Forms.Cursor]::Position.Y; $Script:HotFormStartX = $frmHot.Location.X; $Script:HotFormStartY = $frmHot.Location.Y } }
    $HotDragMove = { param($s, $e) if ($Script:HotDragging) { $diffX = [System.Windows.Forms.Cursor]::Position.X - $Script:HotStartX; $diffY = [System.Windows.Forms.Cursor]::Position.Y - $Script:HotStartY; $frmHot.Location = New-Object System.Drawing.Point(($Script:HotFormStartX + $diffX), ($Script:HotFormStartY + $diffY)) } }
    $HotDragUp = { $Script:HotDragging = $false }
    $pnlHotHeader.Add_MouseDown($HotDragDown); $pnlHotHeader.Add_MouseMove($HotDragMove); $pnlHotHeader.Add_MouseUp($HotDragUp); $lblHotHeader.Add_MouseDown($HotDragDown); $lblHotHeader.Add_MouseMove($HotDragMove); $lblHotHeader.Add_MouseUp($HotDragUp)

    # --- MAIN CONTENT PANEL ---
    $pnlHotContent = New-Object System.Windows.Forms.Panel; $pnlHotContent.Size = "348, 449"; $pnlHotContent.Location = "1, 30"; $pnlHotContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmHot.Controls.Add($pnlHotContent)

    $grpMode = New-Object System.Windows.Forms.GroupBox; $grpMode.Text = "Operation Mode:"; $grpMode.Location = "10, 10"; $grpMode.Size = "315, 100"
    $rSingle = New-Object System.Windows.Forms.RadioButton; $rSingle.Text = "Single Press (Toggle)"; $rSingle.Location = "20, 20"; $rSingle.AutoSize = $true; $rSingle.FlatStyle = "System"; $grpMode.Controls.Add($rSingle)
    $rHold = New-Object System.Windows.Forms.RadioButton; $rHold.Text = "Hold Button (Show)"; $rHold.Location = "20, 45"; $rHold.AutoSize = $true; $rHold.FlatStyle = "System"; $grpMode.Controls.Add($rHold)
    $rCombo = New-Object System.Windows.Forms.RadioButton; $rCombo.Text = "Combo (2 Buttons)"; $rCombo.Location = "20, 70"; $rCombo.AutoSize = $true; $rCombo.FlatStyle = "System"; $grpMode.Controls.Add($rCombo)
    $pnlHotContent.Controls.Add($grpMode)

    # Botões (Tamanho 140x40)
    $btnPrim = New-Object System.Windows.Forms.Button; $btnPrim.Text = "Set Primary Key"; $btnPrim.Location = "20, 130"; $btnPrim.Size = "140, 40"; $btnPrim.BackColor = [System.Drawing.Color]::Silver; $btnPrim.FlatStyle = "Flat"
    $btnSec = New-Object System.Windows.Forms.Button; $btnSec.Text = "Set Secondary Key"; $btnSec.Location = "180, 130"; $btnSec.Size = "140, 40"; $btnSec.BackColor = [System.Drawing.Color]::Silver; $btnSec.FlatStyle = "Flat"
    
    # Previews
    $lblPrim = New-Object System.Windows.Forms.Label; $lblPrim.Text = "None"; $lblPrim.Location = "20, 175"; $lblPrim.Size = "140, 25"; $lblPrim.AutoSize = $false; $lblPrim.TextAlign = "MiddleCenter"; $lblPrim.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $lblPrim.ForeColor = [System.Drawing.Color]::DarkBlue; $pnlHotContent.Controls.Add($lblPrim)
    $lblSec = New-Object System.Windows.Forms.Label; $lblSec.Text = "None"; $lblSec.Location = "180, 175"; $lblSec.Size = "140, 25"; $lblSec.AutoSize = $false; $lblSec.TextAlign = "MiddleCenter"; $lblSec.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $lblSec.ForeColor = [System.Drawing.Color]::DarkBlue; $pnlHotContent.Controls.Add($lblSec)
    
    # Input Seconds
    $lblSecs = New-Object System.Windows.Forms.Label; $lblSecs.Text = "Seconds:"; $lblSecs.Location = "20, 215"; $lblSecs.AutoSize = $true
    $txtSecs = New-Object System.Windows.Forms.TextBox; $txtSecs.Location = "80, 212"; $txtSecs.Size = "30, 20"; $txtSecs.MaxLength = 1
    $pnlHotContent.Controls.Add($btnPrim); $pnlHotContent.Controls.Add($btnSec); $pnlHotContent.Controls.Add($lblSecs); $pnlHotContent.Controls.Add($txtSecs)

    # Load Values
    if ($Global:ConfigData.HotkeyMode -eq "Single") { $rSingle.Checked = $true } elseif ($Global:ConfigData.HotkeyMode -eq "Hold") { $rHold.Checked = $true } elseif ($Global:ConfigData.HotkeyMode -eq "Combo") { $rCombo.Checked = $true }
    if ($Global:ConfigData.HotkeyPrimary) { $lblPrim.Text = [System.Windows.Forms.Keys]$Global:ConfigData.HotkeyPrimary; $btnPrim.Tag = $Global:ConfigData.HotkeyPrimary }
    if ($Global:ConfigData.HotkeySecondary) { $lblSec.Text = [System.Windows.Forms.Keys]$Global:ConfigData.HotkeySecondary; $btnSec.Tag = $Global:ConfigData.HotkeySecondary }
    if ($Global:ConfigData.HotkeySeconds) { $txtSecs.Text = $Global:ConfigData.HotkeySeconds }

    $UpdateUI = {
        $btnPrim.Enabled = $false; $btnPrim.BackColor = [System.Drawing.Color]::LightGray
        $btnSec.Enabled = $false; $btnSec.BackColor = [System.Drawing.Color]::LightGray
        $txtSecs.Enabled = $false

        if ($rSingle.Checked) { $btnPrim.Enabled = $true; $btnPrim.BackColor = [System.Drawing.Color]::LightBlue }
        if ($rHold.Checked) { $btnPrim.Enabled = $true; $btnPrim.BackColor = [System.Drawing.Color]::LightBlue; $txtSecs.Enabled = $true }
        if ($rCombo.Checked) { $btnPrim.Enabled = $true; $btnPrim.BackColor = [System.Drawing.Color]::LightBlue; $btnSec.Enabled = $true; $btnSec.BackColor = [System.Drawing.Color]::LightBlue }
        
        $valid = $false
        if ($rSingle.Checked -and $btnPrim.Tag) { $valid = $true }
        if ($rHold.Checked -and $btnPrim.Tag -and $txtSecs.Text -match "^[2-9]$") { $valid = $true }
        if ($rCombo.Checked -and $btnPrim.Tag -and $btnSec.Tag) { $valid = $true }
        
        if ($valid) { $btnDone.Enabled = $true; $btnDone.BackColor = [System.Drawing.Color]::SeaGreen; $btnDone.ForeColor = [System.Drawing.Color]::White }
        else { $btnDone.Enabled = $false; $btnDone.BackColor = [System.Drawing.Color]::LightGray; $btnDone.ForeColor = [System.Drawing.Color]::Gray }
    }

    $rSingle.Add_CheckedChanged($UpdateUI); $rHold.Add_CheckedChanged($UpdateUI); $rCombo.Add_CheckedChanged($UpdateUI)
    $txtSecs.Add_TextChanged($UpdateUI)
    $txtSecs.Add_KeyPress({ if (-not [char]::IsDigit($_.KeyChar) -and -not [char]::IsControl($_.KeyChar)) { $_.Handled = $true } })
    
    $btnPrim.Add_Click({ Capture-Key $btnPrim; if ($btnPrim.Tag) { $lblPrim.Text = [System.Windows.Forms.Keys][int]$btnPrim.Tag }; $btnPrim.Text = "Set Primary Key"; & $UpdateUI })
    $btnSec.Add_Click({ Capture-Key $btnSec; if ($btnSec.Tag) { $lblSec.Text = [System.Windows.Forms.Keys][int]$btnSec.Tag }; $btnSec.Text = "Set Secondary Key"; & $UpdateUI })

    $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = "Cancel"; $btnCancel.Location = "35, 400"; $btnCancel.Size = "130, 30"; $btnCancel.BackColor = [System.Drawing.Color]::Firebrick; $btnCancel.ForeColor = [System.Drawing.Color]::White; $btnCancel.FlatStyle = "Flat"
    $btnCancel.Add_Click({ $frmHot.Close() })
    $pnlHotContent.Controls.Add($btnCancel)

    $btnDone = New-Object System.Windows.Forms.Button; $btnDone.Text = "Done"; $btnDone.Location = "175, 400"; $btnDone.Size = "130, 30"; $btnDone.BackColor = [System.Drawing.Color]::LightGray; $btnDone.Enabled = $false; $btnDone.FlatStyle = "Flat"
    $btnDone.Add_Click({
        if ($rSingle.Checked) { $Global:ConfigData.HotkeyMode = "Single" } elseif ($rHold.Checked) { $Global:ConfigData.HotkeyMode = "Hold" } else { $Global:ConfigData.HotkeyMode = "Combo" }
        $Global:ConfigData.HotkeyPrimary = $btnPrim.Tag; $Global:ConfigData.HotkeySecondary = $btnSec.Tag; $Global:ConfigData.HotkeySeconds = $txtSecs.Text
        $Script:AdvancedChanged = $true
        
        # Popup Customizado de "Settings Applied"
        $frmHotDone = New-Object System.Windows.Forms.Form; $frmHotDone.Size = New-Object System.Drawing.Size(350, 150); $frmHotDone.StartPosition = "CenterParent"; $frmHotDone.TopMost = $true; $frmHotDone.FormBorderStyle = "None"; $frmHotDone.BackColor = [System.Drawing.Color]::DimGray; $frmHotDone.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None; $frmHotDone.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $pnlHotDoneHeader = New-Object System.Windows.Forms.Panel; $pnlHotDoneHeader.Size = "350, 30"; $pnlHotDoneHeader.Location = "0, 0"; $pnlHotDoneHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmHotDone.Controls.Add($pnlHotDoneHeader)
        $lblHotDoneHeader = New-Object System.Windows.Forms.Label; $lblHotDoneHeader.Text = "Information"; $lblHotDoneHeader.Location = "10, 7"; $lblHotDoneHeader.AutoSize = $true; $lblHotDoneHeader.ForeColor = [System.Drawing.Color]::White; $lblHotDoneHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlHotDoneHeader.Controls.Add($lblHotDoneHeader)
        $pnlHotDoneContent = New-Object System.Windows.Forms.Panel; $pnlHotDoneContent.Size = "348, 119"; $pnlHotDoneContent.Location = "1, 30"; $pnlHotDoneContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmHotDone.Controls.Add($pnlHotDoneContent)
        $lblHotDoneMsg = New-Object System.Windows.Forms.Label; $lblHotDoneMsg.Text = "Settings applied! Click 'SAVE CONFIGURATION' to keep them."; $lblHotDoneMsg.Location = "20, 20"; $lblHotDoneMsg.Size = "310, 40"; $lblHotDoneMsg.AutoSize = $false; $pnlHotDoneContent.Controls.Add($lblHotDoneMsg)
        $btnHotDoneOk = New-Object System.Windows.Forms.Button; $btnHotDoneOk.Text = "OK"; $btnHotDoneOk.Location = "115, 70"; $btnHotDoneOk.Size = "120, 30"; $btnHotDoneOk.BackColor = [System.Drawing.Color]::DodgerBlue; $btnHotDoneOk.ForeColor = [System.Drawing.Color]::White; $btnHotDoneOk.FlatStyle = "Flat"; $btnHotDoneOk.Add_Click({ $frmHotDone.Close() }); $pnlHotDoneContent.Controls.Add($btnHotDoneOk)
        [void]$frmHotDone.ShowDialog()

        $frmHot.Close()
    })
    $pnlHotContent.Controls.Add($btnDone)
    & $UpdateUI; [void]$frmHot.ShowDialog()
}

# ---------------------------------------------------------
# LÓGICA DO FREQ POPUP (JANELA LARGA - ÚNICA VERSÃO)
# ---------------------------------------------------------
function Show-FreqSettings {
    $frmFreq = New-Object System.Windows.Forms.Form; $frmFreq.Size = New-Object System.Drawing.Size(500, 200); $frmFreq.StartPosition = "CenterParent"; $frmFreq.TopMost = $true; 
    $frmFreq.FormBorderStyle = "None"; # <--- SEM BORDA DO WINDOWS
    $frmFreq.BackColor = [System.Drawing.Color]::DimGray # <--- Borda de 1 Pixel
    $frmFreq.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $frmFreq.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    
    # --- HEADER FRMFREQ ---
    $pnlFreqHeader = New-Object System.Windows.Forms.Panel; $pnlFreqHeader.Size = "500, 30"; $pnlFreqHeader.Location = "0, 0"; $pnlFreqHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmFreq.Controls.Add($pnlFreqHeader)
    $lblFreqHeader = New-Object System.Windows.Forms.Label; $lblFreqHeader.Text = "Frequency Settings"; $lblFreqHeader.Location = "10, 7"; $lblFreqHeader.AutoSize = $true; $lblFreqHeader.ForeColor = [System.Drawing.Color]::White; $lblFreqHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlFreqHeader.Controls.Add($lblFreqHeader)
    $btnFreqClose = New-Object System.Windows.Forms.Button; $btnFreqClose.Text = "X"; $btnFreqClose.Size = "40, 30"; $btnFreqClose.Location = "460, 0"; $btnFreqClose.FlatStyle = "Flat"; $btnFreqClose.FlatAppearance.BorderSize = 0; $btnFreqClose.ForeColor = [System.Drawing.Color]::White; $btnFreqClose.BackColor = [System.Drawing.Color]::Transparent; $btnFreqClose.Cursor = [System.Windows.Forms.Cursors]::Hand; $pnlFreqHeader.Controls.Add($btnFreqClose)
    $btnFreqClose.Add_Click({ $frmFreq.Close() }); $btnFreqClose.Add_MouseEnter({ $btnFreqClose.BackColor = [System.Drawing.Color]::Firebrick }); $btnFreqClose.Add_MouseLeave({ $btnFreqClose.BackColor = [System.Drawing.Color]::Transparent })
    
    # --- DRAG FRMFREQ (Blindada com Inteiros) ---
    $Script:FreqDragging = $false; $Script:FreqStartX = 0; $Script:FreqStartY = 0; $Script:FreqFormStartX = 0; $Script:FreqFormStartY = 0
    $FreqDragDown = { param($s, $e) if ($e.Button -eq 'Left') { $Script:FreqDragging = $true; $Script:FreqStartX = [System.Windows.Forms.Cursor]::Position.X; $Script:FreqStartY = [System.Windows.Forms.Cursor]::Position.Y; $Script:FreqFormStartX = $frmFreq.Location.X; $Script:FreqFormStartY = $frmFreq.Location.Y } }
    $FreqDragMove = { param($s, $e) if ($Script:FreqDragging) { $diffX = [System.Windows.Forms.Cursor]::Position.X - $Script:FreqStartX; $diffY = [System.Windows.Forms.Cursor]::Position.Y - $Script:FreqStartY; $frmFreq.Location = New-Object System.Drawing.Point(($Script:FreqFormStartX + $diffX), ($Script:FreqFormStartY + $diffY)) } }
    $FreqDragUp = { $Script:FreqDragging = $false }
    $pnlFreqHeader.Add_MouseDown($FreqDragDown); $pnlFreqHeader.Add_MouseMove($FreqDragMove); $pnlFreqHeader.Add_MouseUp($FreqDragUp); $lblFreqHeader.Add_MouseDown($FreqDragDown); $lblFreqHeader.Add_MouseMove($FreqDragMove); $lblFreqHeader.Add_MouseUp($FreqDragUp)

    # --- MAIN CONTENT PANEL ---
    $pnlFreqContent = New-Object System.Windows.Forms.Panel; $pnlFreqContent.Size = "498, 169"; $pnlFreqContent.Location = "1, 30"; $pnlFreqContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmFreq.Controls.Add($pnlFreqContent)
    
    $lblVal = New-Object System.Windows.Forms.Label; $lblVal.Text = "Backend Update: $($Global:ConfigData.FreqValue) ms"; $lblVal.Location = "10, 10"; $lblVal.AutoSize = $true; $lblVal.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlFreqContent.Controls.Add($lblVal)
    
    $trackFreq = New-Object System.Windows.Forms.TrackBar; $trackFreq.AutoSize = $false; $trackFreq.Location = "20, 40"; $trackFreq.Size = "440, 45"; $trackFreq.Minimum = 10; $trackFreq.Maximum = 1000; $trackFreq.TickFrequency = 10; $trackFreq.SmallChange = 10; $trackFreq.LargeChange = 10; $trackFreq.Value = $Global:ConfigData.FreqValue; $pnlFreqContent.Controls.Add($trackFreq)
    
    $btnReset = New-Object System.Windows.Forms.Button; $btnReset.Text = "Reset (200ms)"; $btnReset.Location = "20, 100"; $btnReset.Size = "120, 30"; $btnReset.FlatStyle = "Flat"
    $pnlFreqContent.Controls.Add($btnReset)
    
    $btnDone = New-Object System.Windows.Forms.Button; $btnDone.Text = "Done"; $btnDone.Location = "340, 100"; $btnDone.Size = "120, 30"; $btnDone.BackColor = [System.Drawing.Color]::SeaGreen; $btnDone.ForeColor = [System.Drawing.Color]::White; $btnDone.FlatStyle = "Flat"; $pnlFreqContent.Controls.Add($btnDone)
    
    $UpdateFreqUI = {
        $val = [math]::Round($trackFreq.Value / 10) * 10 # Snap to 10
        if ($val -lt 10) { $val = 10 }
        $trackFreq.Value = $val
        $lblVal.Text = "Backend Update: $val ms"
        
        if ($val -ne 200) {
             $btnReset.BackColor = [System.Drawing.Color]::Firebrick; $btnReset.ForeColor = [System.Drawing.Color]::White
        } else {
             $btnReset.BackColor = [System.Drawing.Color]::Silver; $btnReset.ForeColor = [System.Drawing.Color]::Black
        }
    }
    
    $trackFreq.Add_Scroll({ & $UpdateFreqUI })
    $btnReset.Add_Click({ $trackFreq.Value = 200; & $UpdateFreqUI })
    
    # === HOT RELOAD LOGIC ===
    $btnDone.Add_Click({ 
        $newFreq = $trackFreq.Value
        $Global:ConfigData.FreqValue = $newFreq
        # 1. Update Backend
        $SyncHash.SleepTime = $newFreq
        # 2. Update Frontend
        $newFront = $newFreq - 10
        if ($newFront -lt 1) { $newFront = 1 }
        $timer.Interval = $newFront
        
        $Script:AdvancedChanged = $true
        $frmFreq.Close() 
    })
    
    & $UpdateFreqUI
    [void]$frmFreq.ShowDialog()
}

# ---------------------------------------------------------
# LÓGICA DE JANELA AVANÇADA (ADAPTIVE SAMPLING)
# ---------------------------------------------------------
function Show-AdvancedSettings {
    # 1. JANELA AUMENTADA E BLINDADA (CAMINHO 2)
    $frmAdv = New-Object System.Windows.Forms.Form; $frmAdv.Size = New-Object System.Drawing.Size(920, 680); $frmAdv.StartPosition = "CenterScreen"; $frmAdv.TopMost = $true; 
    $frmAdv.FormBorderStyle = "None"; # <--- SEM BORDA DO WINDOWS
    $frmAdv.BackColor = [System.Drawing.Color]::DimGray # <--- Borda de 1 Pixel
    $frmAdv.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $frmAdv.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    
    # --- HEADER FRMADV ---
    $pnlAdvHeader = New-Object System.Windows.Forms.Panel; $pnlAdvHeader.Size = "920, 30"; $pnlAdvHeader.Location = "0, 0"; $pnlAdvHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmAdv.Controls.Add($pnlAdvHeader)
    $lblAdvHeader = New-Object System.Windows.Forms.Label; $lblAdvHeader.Text = "Adaptive Settings"; $lblAdvHeader.Location = "10, 7"; $lblAdvHeader.AutoSize = $true; $lblAdvHeader.ForeColor = [System.Drawing.Color]::White; $lblAdvHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlAdvHeader.Controls.Add($lblAdvHeader)
    $btnAdvClose = New-Object System.Windows.Forms.Button; $btnAdvClose.Text = "X"; $btnAdvClose.Size = "40, 30"; $btnAdvClose.Location = "880, 0"; $btnAdvClose.FlatStyle = "Flat"; $btnAdvClose.FlatAppearance.BorderSize = 0; $btnAdvClose.ForeColor = [System.Drawing.Color]::White; $btnAdvClose.BackColor = [System.Drawing.Color]::Transparent; $btnAdvClose.Cursor = [System.Windows.Forms.Cursors]::Hand; $pnlAdvHeader.Controls.Add($btnAdvClose)
    $btnAdvClose.Add_Click({ $frmAdv.Close() }); $btnAdvClose.Add_MouseEnter({ $btnAdvClose.BackColor = [System.Drawing.Color]::Firebrick }); $btnAdvClose.Add_MouseLeave({ $btnAdvClose.BackColor = [System.Drawing.Color]::Transparent })
    
    # --- DRAG FRMADV (Blindada com Inteiros) ---
    $Script:AdvDragging = $false; $Script:AdvStartX = 0; $Script:AdvStartY = 0; $Script:AdvFormStartX = 0; $Script:AdvFormStartY = 0
    $AdvDragDown = { param($s, $e) if ($e.Button -eq 'Left') { $Script:AdvDragging = $true; $Script:AdvStartX = [System.Windows.Forms.Cursor]::Position.X; $Script:AdvStartY = [System.Windows.Forms.Cursor]::Position.Y; $Script:AdvFormStartX = $frmAdv.Location.X; $Script:AdvFormStartY = $frmAdv.Location.Y } }
    $AdvDragMove = { param($s, $e) if ($Script:AdvDragging) { $diffX = [System.Windows.Forms.Cursor]::Position.X - $Script:AdvStartX; $diffY = [System.Windows.Forms.Cursor]::Position.Y - $Script:AdvStartY; $frmAdv.Location = New-Object System.Drawing.Point(($Script:AdvFormStartX + $diffX), ($Script:AdvFormStartY + $diffY)) } }
    $AdvDragUp = { $Script:AdvDragging = $false }
    $pnlAdvHeader.Add_MouseDown($AdvDragDown); $pnlAdvHeader.Add_MouseMove($AdvDragMove); $pnlAdvHeader.Add_MouseUp($AdvDragUp); $lblAdvHeader.Add_MouseDown($AdvDragDown); $lblAdvHeader.Add_MouseMove($AdvDragMove); $lblAdvHeader.Add_MouseUp($AdvDragUp)

    # --- MAIN CONTENT PANEL ---
    $pnlAdvContent = New-Object System.Windows.Forms.Panel; $pnlAdvContent.Size = "918, 649"; $pnlAdvContent.Location = "1, 30"; $pnlAdvContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmAdv.Controls.Add($pnlAdvContent)

    $lblFreqInfo = New-Object System.Windows.Forms.Label; $lblFreqInfo.Text = "Fixed Data Collection Frequency: 200ms"; $lblFreqInfo.Location = "10, 15"; $lblFreqInfo.AutoSize = $true; $lblFreqInfo.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $lblFreqInfo.ForeColor = [System.Drawing.Color]::DarkSlateBlue; $pnlAdvContent.Controls.Add($lblFreqInfo)
    
    $lblInfo = New-Object System.Windows.Forms.Label; $lblInfo.Text = "Adaptive mode requires a stable frequency to calculate filters correctly."; $lblInfo.Location = "10, 40"; $lblInfo.AutoSize = $true; $lblInfo.ForeColor = [System.Drawing.Color]::Gray; $pnlAdvContent.Controls.Add($lblInfo)

    # 2. GRUPOS ALARGADOS
    $grpTarg = New-Object System.Windows.Forms.GroupBox; $grpTarg.Text = "Target Components:"; $grpTarg.Location = "10, 70"; $grpTarg.Size = "880, 70"
    $chkCpu = New-Object System.Windows.Forms.CheckBox; $chkCpu.Text = "CPU"; $chkCpu.Location = "20, 25"; $chkCpu.Size = "60,20"; $chkCpu.Checked = $Global:ConfigData.AdaptiveTargetCpu; $chkCpu.FlatStyle = "System"; $grpTarg.Controls.Add($chkCpu)
    $chkRam = New-Object System.Windows.Forms.CheckBox; $chkRam.Text = "RAM"; $chkRam.Location = "90, 25"; $chkRam.Size = "60,20"; $chkRam.Checked = $Global:ConfigData.AdaptiveTargetRam; $chkRam.FlatStyle = "System"; $grpTarg.Controls.Add($chkRam)
    $chkGpu = New-Object System.Windows.Forms.CheckBox; $chkGpu.Text = "GPU"; $chkGpu.Location = "160, 25"; $chkGpu.Size = "60,20"; $chkGpu.Checked = $Global:ConfigData.AdaptiveTargetGpu; $chkGpu.FlatStyle = "System"; $grpTarg.Controls.Add($chkGpu)
    $chkVram = New-Object System.Windows.Forms.CheckBox; $chkVram.Text = "VRAM"; $chkVram.Location = "230, 25"; $chkVram.Size = "60,20"; $chkVram.Checked = $Global:ConfigData.AdaptiveTargetVram; $chkVram.FlatStyle = "System"; $grpTarg.Controls.Add($chkVram)
    $pnlAdvContent.Controls.Add($grpTarg)

    $grpApp = New-Object System.Windows.Forms.GroupBox; $grpApp.Text = "Apply Filter To:"; $grpApp.Location = "10, 150"; $grpApp.Size = "880, 70"
    $chkTxt = New-Object System.Windows.Forms.CheckBox; $chkTxt.Text = "Text Values"; $chkTxt.Location = "20, 25"; $chkTxt.Checked = $Global:ConfigData.AdaptiveApplyText; $chkTxt.FlatStyle = "System"; $grpApp.Controls.Add($chkTxt)
    $chkBar = New-Object System.Windows.Forms.CheckBox; $chkBar.Text = "Visual Bars"; $chkBar.Location = "150, 25"; $chkBar.Checked = $Global:ConfigData.AdaptiveApplyBar; $chkBar.FlatStyle = "System"; $grpApp.Controls.Add($chkBar)
    $pnlAdvContent.Controls.Add($grpApp)

    # 3. SPIKE PROTECTION GROUP
    $grpSpike = New-Object System.Windows.Forms.GroupBox; $grpSpike.Text = "Pre-Processing (Spike Protection):"; $grpSpike.Location = "10, 230"; $grpSpike.Size = "880, 60"
    
    $chkSpike = New-Object System.Windows.Forms.CheckBox; $chkSpike.Text = "Enable Spike Dampener"; $chkSpike.Location = "20, 25"; $chkSpike.Width = 150; $chkSpike.AutoSize = $false; $chkSpike.Checked = $Global:ConfigData.SpikeProtection; $chkSpike.FlatStyle = "System"; $grpSpike.Controls.Add($chkSpike)
    
    $lblTol = New-Object System.Windows.Forms.Label; $lblTol.Text = "Tolerance:"; $lblTol.Location = "180, 27"; $lblTol.AutoSize = $true; $grpSpike.Controls.Add($lblTol)
    $txtTol = New-Object System.Windows.Forms.TextBox; $txtTol.Location = "240, 24"; $txtTol.Size = "40, 20"; $txtTol.MaxLength = 2; $txtTol.Text = $Global:ConfigData.SpikeTolerance; $txtTol.Add_KeyPress({ if (-not [char]::IsDigit($_.KeyChar) -and -not [char]::IsControl($_.KeyChar)) { $_.Handled = $true } }); $grpSpike.Controls.Add($txtTol)
    $lblTolPct = New-Object System.Windows.Forms.Label; $lblTolPct.Text = "%"; $lblTolPct.Location = "285, 27"; $lblTolPct.AutoSize = $true; $grpSpike.Controls.Add($lblTolPct)
    
    $lblSpikeInfo = New-Object System.Windows.Forms.Label; $lblSpikeInfo.Text = "(Smoothes out sudden spikes if value < 80%. Safety: It disables itself if value >= 80% to warn user)"; $lblSpikeInfo.Location = "315, 27"; $lblSpikeInfo.AutoSize = $true; $lblSpikeInfo.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel); $lblSpikeInfo.ForeColor = [System.Drawing.Color]::DimGray; $grpSpike.Controls.Add($lblSpikeInfo)
    $pnlAdvContent.Controls.Add($grpSpike)

    $grpM = New-Object System.Windows.Forms.GroupBox; $grpM.Text = "Filtering Method (Pipeline):"; $grpM.Location = "10, 300"; $grpM.Size = "880, 260"
    
    # 4. HELP BUTTON (JANELA CUSTOMIZADA AMPLIADA)
    $btnHelp = New-Object System.Windows.Forms.Button; $btnHelp.Text = "?"; $btnHelp.Location = "850, 10"; $btnHelp.Size = "20, 20"; $btnHelp.FlatStyle = "Flat"; $btnHelp.BackColor = [System.Drawing.Color]::LightGray
    
    $btnHelp.Add_Click({ 
        # Construindo a nossa própria janela de ajuda blindada E MAIS ALTA
        $frmHelp = New-Object System.Windows.Forms.Form; $frmHelp.Size = New-Object System.Drawing.Size(600, 460); $frmHelp.StartPosition = "CenterParent"; $frmHelp.TopMost = $true; 
        $frmHelp.FormBorderStyle = "None"; $frmHelp.BackColor = [System.Drawing.Color]::DimGray
        $frmHelp.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
        $frmHelp.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

        # Header da Ajuda
        $pnlHelpHeader = New-Object System.Windows.Forms.Panel; $pnlHelpHeader.Size = "600, 30"; $pnlHelpHeader.Location = "0, 0"; $pnlHelpHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmHelp.Controls.Add($pnlHelpHeader)
        $lblHelpHeader = New-Object System.Windows.Forms.Label; $lblHelpHeader.Text = "Filter Details"; $lblHelpHeader.Location = "10, 7"; $lblHelpHeader.AutoSize = $true; $lblHelpHeader.ForeColor = [System.Drawing.Color]::White; $lblHelpHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlHelpHeader.Controls.Add($lblHelpHeader)
        $btnHelpClose = New-Object System.Windows.Forms.Button; $btnHelpClose.Text = "X"; $btnHelpClose.Size = "40, 30"; $btnHelpClose.Location = "560, 0"; $btnHelpClose.FlatStyle = "Flat"; $btnHelpClose.FlatAppearance.BorderSize = 0; $btnHelpClose.ForeColor = [System.Drawing.Color]::White; $btnHelpClose.BackColor = [System.Drawing.Color]::Transparent; $btnHelpClose.Cursor = [System.Windows.Forms.Cursors]::Hand; $pnlHelpHeader.Controls.Add($btnHelpClose)
        $btnHelpClose.Add_Click({ $frmHelp.Close() }); $btnHelpClose.Add_MouseEnter({ $btnHelpClose.BackColor = [System.Drawing.Color]::Firebrick }); $btnHelpClose.Add_MouseLeave({ $btnHelpClose.BackColor = [System.Drawing.Color]::Transparent })
        
        # Drag da Ajuda
        $Script:HelpDragging = $false; $Script:HelpStartX = 0; $Script:HelpStartY = 0; $Script:HelpFormStartX = 0; $Script:HelpFormStartY = 0
        $HelpDragDown = { param($s, $e) if ($e.Button -eq 'Left') { $Script:HelpDragging = $true; $Script:HelpStartX = [System.Windows.Forms.Cursor]::Position.X; $Script:HelpStartY = [System.Windows.Forms.Cursor]::Position.Y; $Script:HelpFormStartX = $frmHelp.Location.X; $Script:HelpFormStartY = $frmHelp.Location.Y } }
        $HelpDragMove = { param($s, $e) if ($Script:HelpDragging) { $diffX = [System.Windows.Forms.Cursor]::Position.X - $Script:HelpStartX; $diffY = [System.Windows.Forms.Cursor]::Position.Y - $Script:HelpStartY; $frmHelp.Location = New-Object System.Drawing.Point(($Script:HelpFormStartX + $diffX), ($Script:HelpFormStartY + $diffY)) } }
        $HelpDragUp = { $Script:HelpDragging = $false }
        $pnlHelpHeader.Add_MouseDown($HelpDragDown); $pnlHelpHeader.Add_MouseMove($HelpDragMove); $pnlHelpHeader.Add_MouseUp($HelpDragUp); $lblHelpHeader.Add_MouseDown($HelpDragDown); $lblHelpHeader.Add_MouseMove($HelpDragMove); $lblHelpHeader.Add_MouseUp($HelpDragUp)

        # Fundo Branco da Ajuda Expandido
        $pnlHelpContent = New-Object System.Windows.Forms.Panel; $pnlHelpContent.Size = "598, 429"; $pnlHelpContent.Location = "1, 30"; $pnlHelpContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmHelp.Controls.Add($pnlHelpContent)

        $lblMsg = New-Object System.Windows.Forms.Label
        $lblMsg.Text = "1. Rolling Average (Moving Average)`nHow it works: The script takes the last 5 received values and calculates their average.`n`n2. Hysteresis (Noise Filter)`nHow it works: It's like a rigid 'doorman'. It looks at the new value and compares it with the old one. If the difference is less than 2%, it ignores the change and keeps the old number on the screen.`n`n3. EMA (Exponential Moving Average)`nHow it works: Unlike the common average (which treats all 5 past numbers with equal importance), the EMA gives much more weight to the most recent datum.`n`n4. DEMA (Double Exponential Moving Average)`nHow it works: It calculates the EMA of the EMA to correct the natural delay of the smoothing. It provides a result that is smooth like the average but reacts much faster to sudden changes.`n`n5. ALMA (Arnaud Legoux Moving Average)`nHow it works: While common averages look at data from back to front, ALMA applies a Gaussian distribution (a bell-shaped curve) over the data window, but shifted to the right (towards the most recent data)."
        $lblMsg.Location = "20, 20"
        $lblMsg.Size = "560, 340" # <--- Muito mais espaço vertical para o texto
        $lblMsg.AutoSize = $false
        $lblMsg.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $pnlHelpContent.Controls.Add($lblMsg)

        $btnHelpOk = New-Object System.Windows.Forms.Button; $btnHelpOk.Text = "OK"; $btnHelpOk.Location = "240, 370"; $btnHelpOk.Size = "120, 30"; $btnHelpOk.BackColor = [System.Drawing.Color]::DodgerBlue; $btnHelpOk.ForeColor = [System.Drawing.Color]::White; $btnHelpOk.FlatStyle = "Flat"
        $btnHelpOk.Add_Click({ $frmHelp.Close() })
        $pnlHelpContent.Controls.Add($btnHelpOk)

        [void]$frmHelp.ShowDialog()
    })
    $grpM.Controls.Add($btnHelp)

    $chkM2 = New-Object System.Windows.Forms.CheckBox; $chkM2.Text = "Rolling Average"; $chkM2.Location = "20, 25"; $chkM2.AutoSize = $true; $chkM2.Checked = $Global:ConfigData.AdaptiveRolling; $chkM2.FlatStyle = "System"; $grpM.Controls.Add($chkM2)
    $lblM2 = New-Object System.Windows.Forms.Label; $lblM2.Text = "(High Smoothing / High Latency)"; $lblM2.Location = "150, 26"; $lblM2.AutoSize = $true; $lblM2.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel); $lblM2.ForeColor = [System.Drawing.Color]::DimGray; $grpM.Controls.Add($lblM2)

    $chkM3 = New-Object System.Windows.Forms.CheckBox; $chkM3.Text = "EMA"; $chkM3.Location = "20, 50"; $chkM3.AutoSize = $true; $chkM3.Checked = $Global:ConfigData.AdaptiveEma; $chkM3.FlatStyle = "System"; $grpM.Controls.Add($chkM3)
    $lblM3 = New-Object System.Windows.Forms.Label; $lblM3.Text = "(Average overall performance / Medium Latency)"; $lblM3.Location = "150, 51"; $lblM3.AutoSize = $true; $lblM3.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel); $lblM3.ForeColor = [System.Drawing.Color]::DimGray; $grpM.Controls.Add($lblM3)

    $chkM5 = New-Object System.Windows.Forms.CheckBox; $chkM5.Text = "DEMA (Double)"; $chkM5.Location = "20, 75"; $chkM5.AutoSize = $true; $chkM5.Checked = $Global:ConfigData.AdaptiveDema; $chkM5.FlatStyle = "System"; $grpM.Controls.Add($chkM5)
    $lblM5 = New-Object System.Windows.Forms.Label; $lblM5.Text = "(High Precision, Low Latency / Low Smoothing)"; $lblM5.Location = "150, 76"; $lblM5.AutoSize = $true; $lblM5.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel); $lblM5.ForeColor = [System.Drawing.Color]::DimGray; $grpM.Controls.Add($lblM5)
    
    $chkM6 = New-Object System.Windows.Forms.CheckBox; $chkM6.Text = "ALMA"; $chkM6.Location = "20, 100"; $chkM6.AutoSize = $true; $chkM6.Checked = $Global:ConfigData.AdaptiveAlma; $chkM6.FlatStyle = "System"; $grpM.Controls.Add($chkM6)
    $lblM6 = New-Object System.Windows.Forms.Label; $lblM6.Text = "(High Smoothing, Medium Latency / Low Precision)"; $lblM6.Location = "150, 101"; $lblM6.AutoSize = $true; $lblM6.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel); $lblM6.ForeColor = [System.Drawing.Color]::DimGray; $grpM.Controls.Add($lblM6)

    $pnlSep = New-Object System.Windows.Forms.Panel; $pnlSep.Size = New-Object System.Drawing.Size(840, 1); $pnlSep.Location = New-Object System.Drawing.Point(20, 130); $pnlSep.BackColor = [System.Drawing.Color]::LightGray; $grpM.Controls.Add($pnlSep)

    $chkM4 = New-Object System.Windows.Forms.CheckBox; $chkM4.Text = "Hysteresis"; $chkM4.Location = "20, 145"; $chkM4.AutoSize = $true; $chkM4.Checked = $Global:ConfigData.AdaptiveHysteresis; $chkM4.FlatStyle = "System"; $grpM.Controls.Add($chkM4)
    $lblM4 = New-Object System.Windows.Forms.Label; $lblM4.Text = "(Low Latency / Precision and smoothing may vary)"; $lblM4.Location = "150, 146"; $lblM4.AutoSize = $true; $lblM4.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel); $lblM4.ForeColor = [System.Drawing.Color]::DimGray; $grpM.Controls.Add($lblM4)

    $pnlAdvContent.Controls.Add($grpM)

    $chkM2.Add_Click({ if ($chkM2.Checked) { $chkM3.Checked=$false;$chkM5.Checked=$false;$chkM6.Checked=$false;$chkM4.Checked=$false } })
    $chkM3.Add_Click({ if ($chkM3.Checked) { $chkM2.Checked=$false;$chkM5.Checked=$false;$chkM6.Checked=$false;$chkM4.Checked=$false } })
    $chkM5.Add_Click({ if ($chkM5.Checked) { $chkM2.Checked=$false;$chkM3.Checked=$false;$chkM6.Checked=$false;$chkM4.Checked=$false } })
    $chkM6.Add_Click({ if ($chkM6.Checked) { $chkM2.Checked=$false;$chkM3.Checked=$false;$chkM5.Checked=$false;$chkM4.Checked=$false } })
    $chkM4.Add_Click({ if ($chkM4.Checked) { $chkM2.Checked=$false;$chkM3.Checked=$false;$chkM5.Checked=$false;$chkM6.Checked=$false } })

    # 5. BOTÕES
    $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = "Cancel"; $btnCancel.Location = "330, 580"; $btnCancel.Size = "130, 30"; $btnCancel.BackColor = [System.Drawing.Color]::Firebrick; $btnCancel.ForeColor = [System.Drawing.Color]::White; $btnCancel.FlatStyle = "Flat"; $btnCancel.Add_Click({ $frmAdv.Close() }); $pnlAdvContent.Controls.Add($btnCancel)
    $btnOk = New-Object System.Windows.Forms.Button; $btnOk.Text = "Done"; $btnOk.Location = "480, 580"; $btnOk.Size = "130, 30"; $btnOk.BackColor = [System.Drawing.Color]::LightGray; $btnOk.ForeColor = [System.Drawing.Color]::Gray; $btnOk.FlatStyle = "Flat"; $btnOk.Enabled = $false
    
    $ValidateForm = {
        $validTol = ([int]::TryParse($txtTol.Text, [ref]$null)) -and ([int]$txtTol.Text -ge 0) -and ([int]$txtTol.Text -le 100)
        $validTargets = ($chkCpu.Checked -or $chkRam.Checked -or $chkGpu.Checked -or $chkVram.Checked)
        $validApply = ($chkTxt.Checked -or $chkBar.Checked)
        $mainFilterSelected = ($chkM2.Checked -or $chkM3.Checked -or $chkM4.Checked -or $chkM5.Checked -or $chkM6.Checked)
        $validMode = $mainFilterSelected -or $chkSpike.Checked
        
        if ($validTargets -and $validApply -and $validMode -and $validTol) { $btnOk.BackColor = [System.Drawing.Color]::SeaGreen; $btnOk.ForeColor = [System.Drawing.Color]::White; $btnOk.Enabled = $true } else { $btnOk.BackColor = [System.Drawing.Color]::LightGray; $btnOk.ForeColor = [System.Drawing.Color]::Gray; $btnOk.Enabled = $false }
    }
    
    $txtTol.Add_TextChanged($ValidateForm)
    $chkCpu.Add_CheckedChanged($ValidateForm); $chkRam.Add_CheckedChanged($ValidateForm); $chkGpu.Add_CheckedChanged($ValidateForm); $chkVram.Add_CheckedChanged($ValidateForm); $chkTxt.Add_CheckedChanged($ValidateForm); $chkBar.Add_CheckedChanged($ValidateForm)
    $chkM2.Add_CheckedChanged($ValidateForm); $chkM3.Add_CheckedChanged($ValidateForm); $chkM4.Add_CheckedChanged($ValidateForm); $chkM5.Add_CheckedChanged($ValidateForm); $chkM6.Add_CheckedChanged($ValidateForm)
    $chkSpike.Add_CheckedChanged($ValidateForm)
    
    & $ValidateForm

    $btnOk.Add_Click({
        $Global:ConfigData.SpikeProtection = $chkSpike.Checked;
        $Global:ConfigData.SpikeTolerance = [int]$txtTol.Text;
        $Global:ConfigData.AdaptiveTargetCpu = $chkCpu.Checked; $Global:ConfigData.AdaptiveTargetRam = $chkRam.Checked; $Global:ConfigData.AdaptiveTargetGpu = $chkGpu.Checked; $Global:ConfigData.AdaptiveTargetVram = $chkVram.Checked; $Global:ConfigData.AdaptiveApplyText = $chkTxt.Checked; $Global:ConfigData.AdaptiveApplyBar = $chkBar.Checked
        $Global:ConfigData.AdaptiveRolling = $chkM2.Checked
        $Global:ConfigData.AdaptiveEma = $chkM3.Checked
        $Global:ConfigData.AdaptiveDema = $chkM5.Checked
        $Global:ConfigData.AdaptiveAlma = $chkM6.Checked
        $Global:ConfigData.AdaptiveHysteresis = $chkM4.Checked
        $Script:AdvancedChanged = $true
        
        # Substituímos o MessageBox final por uma janela customizada também!
        $frmDone = New-Object System.Windows.Forms.Form; $frmDone.Size = New-Object System.Drawing.Size(400, 150); $frmDone.StartPosition = "CenterParent"; $frmDone.TopMost = $true; $frmDone.FormBorderStyle = "None"; $frmDone.BackColor = [System.Drawing.Color]::DimGray; $frmDone.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None; $frmDone.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $pnlDoneHeader = New-Object System.Windows.Forms.Panel; $pnlDoneHeader.Size = "400, 30"; $pnlDoneHeader.Location = "0, 0"; $pnlDoneHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmDone.Controls.Add($pnlDoneHeader)
        $lblDoneHeader = New-Object System.Windows.Forms.Label; $lblDoneHeader.Text = "Information"; $lblDoneHeader.Location = "10, 7"; $lblDoneHeader.AutoSize = $true; $lblDoneHeader.ForeColor = [System.Drawing.Color]::White; $lblDoneHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlDoneHeader.Controls.Add($lblDoneHeader)
        $pnlDoneContent = New-Object System.Windows.Forms.Panel; $pnlDoneContent.Size = "398, 119"; $pnlDoneContent.Location = "1, 30"; $pnlDoneContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmDone.Controls.Add($pnlDoneContent)
        $lblDoneMsg = New-Object System.Windows.Forms.Label; $lblDoneMsg.Text = "Settings applied! Click 'SAVE CONFIGURATION' to keep them.`nAdaptive frequency locked to 200ms."; $lblDoneMsg.Location = "20, 20"; $lblDoneMsg.Size = "360, 40"; $lblDoneMsg.AutoSize = $false; $pnlDoneContent.Controls.Add($lblDoneMsg)
        $btnDoneOk = New-Object System.Windows.Forms.Button; $btnDoneOk.Text = "OK"; $btnDoneOk.Location = "140, 70"; $btnDoneOk.Size = "120, 30"; $btnDoneOk.BackColor = [System.Drawing.Color]::DodgerBlue; $btnDoneOk.ForeColor = [System.Drawing.Color]::White; $btnDoneOk.FlatStyle = "Flat"; $btnDoneOk.Add_Click({ $frmDone.Close() }); $pnlDoneContent.Controls.Add($btnDoneOk)
        [void]$frmDone.ShowDialog()

        $frmAdv.Close()
    })
    $pnlAdvContent.Controls.Add($btnOk); [void]$frmAdv.ShowDialog()
}

# ---------------------------------------------------------
# LOGICA DO CFG (Janela de Configuracao)
# ---------------------------------------------------------
$OpenConfig = {
    $Script:SavedChanges = $false; $Script:HardResetPosActive = $false; $Script:HardResetOpActive = $false; $Script:HardResetContOp = $false   
    if ($Global:ConfigData.PosX -ne $null) { $Script:PendingPos = New-Object System.Drawing.Point($Global:ConfigData.PosX, $Global:ConfigData.PosY) } else { $Script:PendingPos = $null }

    $frmCfg = New-Object System.Windows.Forms.Form; $frmCfg.Size = New-Object System.Drawing.Size(450, 945); $frmCfg.StartPosition = "CenterScreen"; $frmCfg.TopMost = $true; 
    $frmCfg.FormBorderStyle = "None"; 
    $frmCfg.BackColor = [System.Drawing.Color]::DimGray; 
    $frmCfg.ForeColor = [System.Drawing.Color]::Black 
    $frmCfg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $frmCfg.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

    # --- CUSTOM HEADER BAR ---
    $pnlHeader = New-Object System.Windows.Forms.Panel; $pnlHeader.Size = "450, 30"; $pnlHeader.Location = "0, 0"; $pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmCfg.Controls.Add($pnlHeader)
    $lblHeader = New-Object System.Windows.Forms.Label; $lblHeader.Text = "Configuration"; $lblHeader.Location = "10, 7"; $lblHeader.AutoSize = $true; $lblHeader.ForeColor = [System.Drawing.Color]::White; $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlHeader.Controls.Add($lblHeader)
    $btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = "X"; $btnClose.Size = "40, 30"; $btnClose.Location = "410, 0"; $btnClose.FlatStyle = "Flat"; $btnClose.FlatAppearance.BorderSize = 0; $btnClose.ForeColor = [System.Drawing.Color]::White; $btnClose.BackColor = [System.Drawing.Color]::Transparent; $btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand; $pnlHeader.Controls.Add($btnClose)
    $btnClose.Add_Click({ $frmCfg.Close() }); $btnClose.Add_MouseEnter({ $btnClose.BackColor = [System.Drawing.Color]::Firebrick }); $btnClose.Add_MouseLeave({ $btnClose.BackColor = [System.Drawing.Color]::Transparent })

    # --- DRAG LOGIC ---
    $Script:CfgDragging = $false; $Script:CfgStartX = 0; $Script:CfgStartY = 0; $Script:FormStartX = 0; $Script:FormStartY = 0
    $DragDown = { param($s, $e) if ($e.Button -eq 'Left') { $Script:CfgDragging = $true; $Script:CfgStartX = [System.Windows.Forms.Cursor]::Position.X; $Script:CfgStartY = [System.Windows.Forms.Cursor]::Position.Y; $Script:FormStartX = $frmCfg.Location.X; $Script:FormStartY = $frmCfg.Location.Y } }
    $DragMove = { param($s, $e) if ($Script:CfgDragging) { $diffX = [System.Windows.Forms.Cursor]::Position.X - $Script:CfgStartX; $diffY = [System.Windows.Forms.Cursor]::Position.Y - $Script:CfgStartY; $frmCfg.Location = New-Object System.Drawing.Point(($Script:FormStartX + $diffX), ($Script:FormStartY + $diffY)) } }
    $DragUp = { $Script:CfgDragging = $false }
    $pnlHeader.Add_MouseDown($DragDown); $pnlHeader.Add_MouseMove($DragMove); $pnlHeader.Add_MouseUp($DragUp)
    $lblHeader.Add_MouseDown($DragDown); $lblHeader.Add_MouseMove($DragMove); $lblHeader.Add_MouseUp($DragUp)

    # --- MAIN CONTENT PANEL ---
    $pnlContent = New-Object System.Windows.Forms.Panel; $pnlContent.Size = "448, 914"; $pnlContent.Location = "1, 30"; $pnlContent.BackColor = [System.Drawing.Color]::Gainsboro; $frmCfg.Controls.Add($pnlContent)

    # --- OPACIDADE E POSICAO ---
    $lblBackOp = New-Object System.Windows.Forms.Label; $lblBackOp.Text = "Background Opacity:"; $lblBackOp.Location = "10, 10"; $lblBackOp.AutoSize = $true; $pnlContent.Controls.Add($lblBackOp)
    $lblBackOpPct = New-Object System.Windows.Forms.Label; $lblBackOpPct.Text = "$([int]($formBack.Opacity * 100))%"; $lblBackOpPct.Location = "130, 10"; $lblBackOpPct.AutoSize = $true; $lblBackOpPct.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlContent.Controls.Add($lblBackOpPct)
    $trackBackOp = New-Object System.Windows.Forms.TrackBar; $trackBackOp.AutoSize = $false; $trackBackOp.Location = "30, 30"; $trackBackOp.Size = "220, 45"; $trackBackOp.Minimum = 0; $trackBackOp.Maximum = 99; $trackBackOp.TickFrequency = 10; $trackBackOp.Value = [int]($formBack.Opacity * 100); $pnlContent.Controls.Add($trackBackOp)
    $btnResetBackOp = New-Object System.Windows.Forms.Button; $btnResetBackOp.Text = "Reset Back (Only)"; $btnResetBackOp.Location = "260, 30"; $btnResetBackOp.Size = "160, 30"; $btnResetBackOp.BackColor = [System.Drawing.Color]::Silver; $btnResetBackOp.FlatStyle = "Flat"; $pnlContent.Controls.Add($btnResetBackOp)

    $sep1 = New-Object System.Windows.Forms.Panel; $sep1.Height = 1; $sep1.Width = 415; $sep1.Location = "10, 85"; $sep1.BackColor = [System.Drawing.Color]::DarkGray; $pnlContent.Controls.Add($sep1)

    $lblContOp = New-Object System.Windows.Forms.Label; $lblContOp.Text = "Content Opacity:"; $lblContOp.Location = "10, 100"; $lblContOp.AutoSize = $true; $pnlContent.Controls.Add($lblContOp)
    $lblContOpPct = New-Object System.Windows.Forms.Label; $lblContOpPct.Text = "$([int]($form.Opacity * 100))%"; $lblContOpPct.Location = "130, 100"; $lblContOpPct.AutoSize = $true; $lblContOpPct.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlContent.Controls.Add($lblContOpPct)
    $trackContOp = New-Object System.Windows.Forms.TrackBar; $trackContOp.AutoSize = $false; $trackContOp.Location = "30, 120"; $trackContOp.Size = "220, 45"; $trackContOp.Minimum = 20; $trackContOp.Maximum = 100; $trackContOp.TickFrequency = 10; $trackContOp.Value = [int]($form.Opacity * 100); $pnlContent.Controls.Add($trackContOp)
    $btnResetContOp = New-Object System.Windows.Forms.Button; $btnResetContOp.Text = "Reset Content (Only)"; $btnResetContOp.Location = "260, 120"; $btnResetContOp.Size = "160, 30"; $btnResetContOp.BackColor = [System.Drawing.Color]::Silver; $btnResetContOp.FlatStyle = "Flat"; $pnlContent.Controls.Add($btnResetContOp)

    $sep2 = New-Object System.Windows.Forms.Panel; $sep2.Height = 1; $sep2.Width = 415; $sep2.Location = "10, 175"; $sep2.BackColor = [System.Drawing.Color]::DarkGray; $pnlContent.Controls.Add($sep2)

    $lblPos = New-Object System.Windows.Forms.Label; $lblPos.Text = "Window Position:"; $lblPos.Location = "10, 190"; $lblPos.AutoSize = $true; $pnlContent.Controls.Add($lblPos)
    $btnMemPos = New-Object System.Windows.Forms.Button; $btnMemPos.Text = "Remember Position"; $btnMemPos.Location = "40, 215"; $btnMemPos.Size = "180, 30"; $btnMemPos.BackColor = [System.Drawing.Color]::SeaGreen; $btnMemPos.ForeColor = [System.Drawing.Color]::White; $btnMemPos.FlatStyle = "Flat"; $pnlContent.Controls.Add($btnMemPos)
    $btnResetPos = New-Object System.Windows.Forms.Button; $btnResetPos.Text = "Reset Position (Only)"; $btnResetPos.Location = "230, 215"; $btnResetPos.Size = "180, 30"; $btnResetPos.BackColor = [System.Drawing.Color]::Silver; $btnResetPos.FlatStyle = "Flat"; $pnlContent.Controls.Add($btnResetPos)

    $sep3 = New-Object System.Windows.Forms.Panel; $sep3.Height = 1; $sep3.Width = 415; $sep3.Location = "10, 260"; $sep3.BackColor = [System.Drawing.Color]::DarkGray; $pnlContent.Controls.Add($sep3)

    # --- START OPTIONS ---
    $chkStartLock = New-Object System.Windows.Forms.CheckBox; $chkStartLock.Text = "Start Locked (Overlay Mode)"; $chkStartLock.Location = "10, 270"; $chkStartLock.Size = "200, 20"; $chkStartLock.Checked = $Global:ConfigData.StartLocked; $chkStartLock.FlatStyle = "System"; $pnlContent.Controls.Add($chkStartLock)
    $chkStartHidden = New-Object System.Windows.Forms.CheckBox; $chkStartHidden.Text = "Start Hidden (Tray Mode)"; $chkStartHidden.Location = "220, 270"; $chkStartHidden.Size = "200, 20"; $chkStartHidden.Checked = $Global:ConfigData.StartHidden; $chkStartHidden.FlatStyle = "System"; $pnlContent.Controls.Add($chkStartHidden)

    $chkReqAdmin = New-Object System.Windows.Forms.CheckBox; $chkReqAdmin.Text = "Always run as Administrator"; $chkReqAdmin.Location = "10, 295"; $chkReqAdmin.Width = 300; $chkReqAdmin.Checked = $Global:ConfigData.RequireAdmin; $chkReqAdmin.FlatStyle = "System"; $pnlContent.Controls.Add($chkReqAdmin)
    
    $lblReqAdminNote = New-Object System.Windows.Forms.Label; $lblReqAdminNote.Text = "Note: Prompts for permission (UAC) when starting the app manually."; $lblReqAdminNote.Location = "28, 320"; $lblReqAdminNote.AutoSize = $true; $lblReqAdminNote.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel); $lblReqAdminNote.ForeColor = [System.Drawing.Color]::DimGray; $pnlContent.Controls.Add($lblReqAdminNote)

    $sepFreq = New-Object System.Windows.Forms.Panel; $sepFreq.Height = 1; $sepFreq.Width = 415; $sepFreq.Location = "10, 345"; $sepFreq.BackColor = [System.Drawing.Color]::DarkGray; $pnlContent.Controls.Add($sepFreq)
    
    # --- FREQ CONTROL ---
    $chkFreq = New-Object System.Windows.Forms.CheckBox; $chkFreq.Text = "Enable data update frequency adjustment"; $chkFreq.Location = "10, 355"; $chkFreq.Width = 300; $chkFreq.Checked = $Global:ConfigData.FreqEnabled; $chkFreq.FlatStyle = "System"; $pnlContent.Controls.Add($chkFreq)
    $btnFreq = New-Object System.Windows.Forms.Button; $btnFreq.Text = "Frequency settings..."; $btnFreq.Location = "190, 380"; $btnFreq.Size = "150, 25"; $btnFreq.FlatStyle = "Flat"; $btnFreq.Enabled = $chkFreq.Checked; $pnlContent.Controls.Add($btnFreq)
    $btnFreq.Add_Click({ Show-FreqSettings })

    $sep4 = New-Object System.Windows.Forms.Panel; $sep4.Height = 1; $sep4.Width = 415; $sep4.Location = "10, 415"; $sep4.BackColor = [System.Drawing.Color]::DarkGray; $pnlContent.Controls.Add($sep4)

    # --- ADAPTIVE SAMPLING ---
    $chkAdaptive = New-Object System.Windows.Forms.CheckBox; $chkAdaptive.Text = "Enable Adaptive Sampling"; $chkAdaptive.Location = "10, 430"; $chkAdaptive.Size = "170, 25"; $chkAdaptive.Checked = $Global:ConfigData.AdaptiveEnabled; $chkAdaptive.FlatStyle = "System"; $pnlContent.Controls.Add($chkAdaptive)
    $btnAdvanced = New-Object System.Windows.Forms.Button; $btnAdvanced.Text = "Adaptive Settings..."; $btnAdvanced.Location = "190, 427"; $btnAdvanced.Size = "150, 25"; $btnAdvanced.FlatStyle = "Flat"; $btnAdvanced.Enabled = $chkAdaptive.Checked
    $btnAdvanced.Add_Click({ Show-AdvancedSettings }); $pnlContent.Controls.Add($btnAdvanced)

    $lblAdaptNote = New-Object System.Windows.Forms.Label; 
    $lblAdaptNote.Text = "Note: Activates intelligent data processing. Replaces raw readings with a mathematical pipeline that calculates a real-time average, delivering statistically treated numbers to be more reliable and easier to read."; 
    $lblAdaptNote.Location = "10, 460"; 
    $lblAdaptNote.Size = "420, 60"; 
    $lblAdaptNote.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel); 
    $lblAdaptNote.ForeColor = [System.Drawing.Color]::DimGray; 
    $pnlContent.Controls.Add($lblAdaptNote)

    $sepAdaptiveHot = New-Object System.Windows.Forms.Panel; $sepAdaptiveHot.Height = 1; $sepAdaptiveHot.Width = 415; $sepAdaptiveHot.Location = "10, 525"; $sepAdaptiveHot.BackColor = [System.Drawing.Color]::DarkGray; $pnlContent.Controls.Add($sepAdaptiveHot)

    # --- HOTKEYS ---
    $chkHot = New-Object System.Windows.Forms.CheckBox; $chkHot.Text = "Enable Hide/Show Hotkey"; $chkHot.Location = "10, 540"; $chkHot.Size = "170, 25"; $chkHot.FlatStyle = "System"; $pnlContent.Controls.Add($chkHot)
    $btnHot = New-Object System.Windows.Forms.Button; $btnHot.Text = "Hotkey Settings..."; $btnHot.Location = "190, 537"; $btnHot.Size = "150, 25"; $btnHot.FlatStyle = "Flat"; $pnlContent.Controls.Add($btnHot)
    $btnHot.Add_Click({ Show-HotkeySettings })

    $lblHotAdminNote = New-Object System.Windows.Forms.Label; $lblHotAdminNote.Text = "Note: Requires administrator privileges to function correctly."; $lblHotAdminNote.Location = "10, 565"; $lblHotAdminNote.AutoSize = $true; $lblHotAdminNote.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel); $lblHotAdminNote.ForeColor = [System.Drawing.Color]::DimGray; $pnlContent.Controls.Add($lblHotAdminNote)

    if ($script:IsAdmin) { $chkHot.Checked = $Global:ConfigData.HotkeyEnabled; $chkHot.Enabled = $true } else { $chkHot.Checked = $false; $chkHot.Enabled = $false }

    # =========================================================
    # AUTO-START VIA TASK SCHEDULER
    # =========================================================
    $sepAutoStart = New-Object System.Windows.Forms.Panel; $sepAutoStart.Height = 1; $sepAutoStart.Width = 415; $sepAutoStart.Location = "10, 590"; $sepAutoStart.BackColor = [System.Drawing.Color]::DarkGray; $pnlContent.Controls.Add($sepAutoStart)

    $lblAutoStartTitle = New-Object System.Windows.Forms.Label; $lblAutoStartTitle.Text = "Windows Auto-Start:"; $lblAutoStartTitle.Location = "10, 600"; $lblAutoStartTitle.AutoSize = $true; $lblAutoStartTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlContent.Controls.Add($lblAutoStartTitle)

    $btnAutoStartToggle = New-Object System.Windows.Forms.Button; $btnAutoStartToggle.Location = "10, 625"; $btnAutoStartToggle.Size = "250, 30"; $btnAutoStartToggle.FlatStyle = "Flat"; $btnAutoStartToggle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlContent.Controls.Add($btnAutoStartToggle)

    $lblTaskAdminNote = New-Object System.Windows.Forms.Label; $lblTaskAdminNote.Text = "Note: Starts monitor silently at logon with Highest Privileges."; $lblTaskAdminNote.Location = "10, 660"; $lblTaskAdminNote.AutoSize = $true; $lblTaskAdminNote.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel); $lblTaskAdminNote.ForeColor = [System.Drawing.Color]::DimGray; $pnlContent.Controls.Add($lblTaskAdminNote)

    $Script:TaskIsConfigured = $false
    $Script:TaskState = "None" 

    $UpdateTaskButtonState = {
        $taskName = "Performance Monitor"
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        $Script:TaskState = "None"
        $Script:TaskIsConfigured = $false

        if ($null -ne $task) {
            $Script:TaskIsConfigured = $true
            $action = $task.Actions[0]
            $fullActionStr = "$($action.Execute) $($action.Arguments)"
            $cleanActionStr = $fullActionStr.Replace('"', '')
            $cleanRealFile = $Global:ArquivoReal.Replace('"', '')

            if ($cleanActionStr -match [regex]::Escape($cleanRealFile)) {
                $Script:TaskState = "OK"
            } else {
                $Script:TaskState = "Broken"
            }
        }

        if ($Script:TaskState -eq "Broken") {
            $btnAutoStartToggle.Text = "Fix / Update Auto-Start"
            $btnAutoStartToggle.BackColor = [System.Drawing.Color]::DarkOrange
            $btnAutoStartToggle.ForeColor = [System.Drawing.Color]::White
            $btnAutoStartToggle.Enabled = $true
            
            $lblTaskAdminNote.Text = "Warning: Auto-Start is broken because the file was moved or renamed.`nClick 'Fix / Update Auto-Start' to resolve this."
            $lblTaskAdminNote.ForeColor = [System.Drawing.Color]::Firebrick
            $lblTaskAdminNote.AutoSize = $false
            $lblTaskAdminNote.Size = New-Object System.Drawing.Size(400, 30)
        } else {
            $lblTaskAdminNote.AutoSize = $true
            $lblTaskAdminNote.Size = New-Object System.Drawing.Size(400, 15)
            
            if (-not $script:IsAdmin) {
                $btnAutoStartToggle.Text = "Auto-Start (Admin Required)"
                $btnAutoStartToggle.BackColor = [System.Drawing.Color]::LightGray
                $btnAutoStartToggle.ForeColor = [System.Drawing.Color]::Gray
                $btnAutoStartToggle.Enabled = $false
                $lblTaskAdminNote.Text = "Note: Starts monitor silently at logon with Highest Privileges."
                $lblTaskAdminNote.ForeColor = [System.Drawing.Color]::DimGray
            } else {
                $btnAutoStartToggle.Enabled = $true
                if ($Script:TaskState -eq "OK") {
                    $btnAutoStartToggle.Text = "Disable Auto-Start"
                    $btnAutoStartToggle.BackColor = [System.Drawing.Color]::Firebrick
                    $btnAutoStartToggle.ForeColor = [System.Drawing.Color]::White
                    $lblTaskAdminNote.Text = "Note: Starts monitor silently at logon with Highest Privileges."
                    $lblTaskAdminNote.ForeColor = [System.Drawing.Color]::DimGray
                } else {
                    $btnAutoStartToggle.Text = "Enable Auto-Start"
                    $btnAutoStartToggle.BackColor = [System.Drawing.Color]::SeaGreen
                    $btnAutoStartToggle.ForeColor = [System.Drawing.Color]::White
                    $lblTaskAdminNote.Text = "Note: Starts monitor silently at logon with Highest Privileges."
                    $lblTaskAdminNote.ForeColor = [System.Drawing.Color]::DimGray
                }
            }
        }
    }

    & $UpdateTaskButtonState

    $btnAutoStartToggle.Add_Click({
        $taskName = "Performance Monitor"
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        
        if ($Script:TaskState -eq "OK") {
            try {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
                
                # POPUP DE SUCESSO (Caminho 2)
                $frmAutoDone = New-Object System.Windows.Forms.Form; $frmAutoDone.Size = New-Object System.Drawing.Size(350, 150); $frmAutoDone.StartPosition = "CenterParent"; $frmAutoDone.TopMost = $true; $frmAutoDone.FormBorderStyle = "None"; $frmAutoDone.BackColor = [System.Drawing.Color]::DimGray; $frmAutoDone.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None; $frmAutoDone.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
                $pnlADHeader = New-Object System.Windows.Forms.Panel; $pnlADHeader.Size = "350, 30"; $pnlADHeader.Location = "0, 0"; $pnlADHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmAutoDone.Controls.Add($pnlADHeader)
                $lblADHeader = New-Object System.Windows.Forms.Label; $lblADHeader.Text = "Success"; $lblADHeader.Location = "10, 7"; $lblADHeader.AutoSize = $true; $lblADHeader.ForeColor = [System.Drawing.Color]::White; $lblADHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlADHeader.Controls.Add($lblADHeader)
                $pnlADContent = New-Object System.Windows.Forms.Panel; $pnlADContent.Size = "348, 119"; $pnlADContent.Location = "1, 30"; $pnlADContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmAutoDone.Controls.Add($pnlADContent)
                $lblADMsg = New-Object System.Windows.Forms.Label; $lblADMsg.Text = "Auto-Start disabled successfully."; $lblADMsg.Location = "20, 20"; $lblADMsg.Size = "310, 40"; $lblADMsg.AutoSize = $false; $pnlADContent.Controls.Add($lblADMsg)
                $btnADOk = New-Object System.Windows.Forms.Button; $btnADOk.Text = "OK"; $btnADOk.Location = "115, 70"; $btnADOk.Size = "120, 30"; $btnADOk.BackColor = [System.Drawing.Color]::DodgerBlue; $btnADOk.ForeColor = [System.Drawing.Color]::White; $btnADOk.FlatStyle = "Flat"; $btnADOk.Add_Click({ $frmAutoDone.Close() }); $pnlADContent.Controls.Add($btnADOk)
                [void]$frmAutoDone.ShowDialog()
                
            } catch { [System.Windows.Forms.MessageBox]::Show("Error removing task:`n$_", "Error", "OK", "Error") }
            
        } elseif ($Script:TaskState -eq "None") {
            try {
                if ($Script:IsCompiled) { $act = New-ScheduledTaskAction -Execute $Global:ArquivoReal } 
                else { $act = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Global:ArquivoReal`"" }
                $trig = New-ScheduledTaskTrigger -AtLogon
                $princ = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
                $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 0)
                
                Register-ScheduledTask -Action $act -Trigger $trig -Principal $princ -Settings $set -TaskName $taskName -Force | Out-Null
                
                # POPUP DE SUCESSO (Caminho 2)
                $frmAutoDone = New-Object System.Windows.Forms.Form; $frmAutoDone.Size = New-Object System.Drawing.Size(350, 150); $frmAutoDone.StartPosition = "CenterParent"; $frmAutoDone.TopMost = $true; $frmAutoDone.FormBorderStyle = "None"; $frmAutoDone.BackColor = [System.Drawing.Color]::DimGray; $frmAutoDone.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None; $frmAutoDone.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
                $pnlADHeader = New-Object System.Windows.Forms.Panel; $pnlADHeader.Size = "350, 30"; $pnlADHeader.Location = "0, 0"; $pnlADHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmAutoDone.Controls.Add($pnlADHeader)
                $lblADHeader = New-Object System.Windows.Forms.Label; $lblADHeader.Text = "Success"; $lblADHeader.Location = "10, 7"; $lblADHeader.AutoSize = $true; $lblADHeader.ForeColor = [System.Drawing.Color]::White; $lblADHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlADHeader.Controls.Add($lblADHeader)
                $pnlADContent = New-Object System.Windows.Forms.Panel; $pnlADContent.Size = "348, 119"; $pnlADContent.Location = "1, 30"; $pnlADContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmAutoDone.Controls.Add($pnlADContent)
                $lblADMsg = New-Object System.Windows.Forms.Label; $lblADMsg.Text = "Auto-Start enabled successfully!`nThe monitor will start with Windows as Administrator."; $lblADMsg.Location = "20, 20"; $lblADMsg.Size = "310, 40"; $lblADMsg.AutoSize = $false; $pnlADContent.Controls.Add($lblADMsg)
                $btnADOk = New-Object System.Windows.Forms.Button; $btnADOk.Text = "OK"; $btnADOk.Location = "115, 70"; $btnADOk.Size = "120, 30"; $btnADOk.BackColor = [System.Drawing.Color]::DodgerBlue; $btnADOk.ForeColor = [System.Drawing.Color]::White; $btnADOk.FlatStyle = "Flat"; $btnADOk.Add_Click({ $frmAutoDone.Close() }); $pnlADContent.Controls.Add($btnADOk)
                [void]$frmAutoDone.ShowDialog()
                
            } catch { [System.Windows.Forms.MessageBox]::Show("Error creating task:`n$_", "Error", "OK", "Error") }
            
        } elseif ($Script:TaskState -eq "Broken") {
            $fixCmd = "Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false -ErrorAction SilentlyContinue; "
            if ($Script:IsCompiled) { $fixCmd += "`$act = New-ScheduledTaskAction -Execute '$Global:ArquivoReal'; " } 
            else { $fixCmd += "`$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Global:ArquivoReal`"'; " }
            $fixCmd += "`$trig = New-ScheduledTaskTrigger -AtLogon; `$princ = New-ScheduledTaskPrincipal -UserId '$user' -LogonType Interactive -RunLevel Highest; `$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 0); Register-ScheduledTask -Action `$act -Trigger `$trig -Principal `$princ -Settings `$set -TaskName '$taskName' -Force"
            
            if ($script:IsAdmin) {
                Invoke-Expression $fixCmd
                
                # POPUP DE SUCESSO (Caminho 2)
                $frmAutoDone = New-Object System.Windows.Forms.Form; $frmAutoDone.Size = New-Object System.Drawing.Size(350, 150); $frmAutoDone.StartPosition = "CenterParent"; $frmAutoDone.TopMost = $true; $frmAutoDone.FormBorderStyle = "None"; $frmAutoDone.BackColor = [System.Drawing.Color]::DimGray; $frmAutoDone.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None; $frmAutoDone.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
                $pnlADHeader = New-Object System.Windows.Forms.Panel; $pnlADHeader.Size = "350, 30"; $pnlADHeader.Location = "0, 0"; $pnlADHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmAutoDone.Controls.Add($pnlADHeader)
                $lblADHeader = New-Object System.Windows.Forms.Label; $lblADHeader.Text = "Fixed"; $lblADHeader.Location = "10, 7"; $lblADHeader.AutoSize = $true; $lblADHeader.ForeColor = [System.Drawing.Color]::White; $lblADHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlADHeader.Controls.Add($lblADHeader)
                $pnlADContent = New-Object System.Windows.Forms.Panel; $pnlADContent.Size = "348, 119"; $pnlADContent.Location = "1, 30"; $pnlADContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmAutoDone.Controls.Add($pnlADContent)
                $lblADMsg = New-Object System.Windows.Forms.Label; $lblADMsg.Text = "Auto-Start fixed successfully!"; $lblADMsg.Location = "20, 20"; $lblADMsg.Size = "310, 40"; $lblADMsg.AutoSize = $false; $pnlADContent.Controls.Add($lblADMsg)
                $btnADOk = New-Object System.Windows.Forms.Button; $btnADOk.Text = "OK"; $btnADOk.Location = "115, 70"; $btnADOk.Size = "120, 30"; $btnADOk.BackColor = [System.Drawing.Color]::DodgerBlue; $btnADOk.ForeColor = [System.Drawing.Color]::White; $btnADOk.FlatStyle = "Flat"; $btnADOk.Add_Click({ $frmAutoDone.Close() }); $pnlADContent.Controls.Add($btnADOk)
                [void]$frmAutoDone.ShowDialog()
                
            } else {
                $frmFix = New-Object System.Windows.Forms.Form; $frmFix.Size = New-Object System.Drawing.Size(420, 240); $frmFix.StartPosition = "CenterParent"; $frmFix.TopMost = $true; 
                $frmFix.FormBorderStyle = "None"; $frmFix.BackColor = [System.Drawing.Color]::DimGray
                $frmFix.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
                $frmFix.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

                # --- HEADER FRMFIX ---
                $pnlFixHeader = New-Object System.Windows.Forms.Panel; $pnlFixHeader.Size = "420, 30"; $pnlFixHeader.Location = "0, 0"; $pnlFixHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmFix.Controls.Add($pnlFixHeader)
                $lblFixHeader = New-Object System.Windows.Forms.Label; $lblFixHeader.Text = "Action Required"; $lblFixHeader.Location = "10, 7"; $lblFixHeader.AutoSize = $true; $lblFixHeader.ForeColor = [System.Drawing.Color]::White; $lblFixHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlFixHeader.Controls.Add($lblFixHeader)
                $btnFixClose = New-Object System.Windows.Forms.Button; $btnFixClose.Text = "X"; $btnFixClose.Size = "40, 30"; $btnFixClose.Location = "380, 0"; $btnFixClose.FlatStyle = "Flat"; $btnFixClose.FlatAppearance.BorderSize = 0; $btnFixClose.ForeColor = [System.Drawing.Color]::White; $btnFixClose.BackColor = [System.Drawing.Color]::Transparent; $btnFixClose.Cursor = [System.Windows.Forms.Cursors]::Hand; $pnlFixHeader.Controls.Add($btnFixClose)
                $btnFixClose.Add_Click({ $frmFix.Close() }); $btnFixClose.Add_MouseEnter({ $btnFixClose.BackColor = [System.Drawing.Color]::Firebrick }); $btnFixClose.Add_MouseLeave({ $btnFixClose.BackColor = [System.Drawing.Color]::Transparent })
                
                # --- DRAG FRMFIX ---
                $Script:FixDragging = $false; $Script:FixStartX = 0; $Script:FixStartY = 0; $Script:FixFormStartX = 0; $Script:FixFormStartY = 0
                $FixDragDown = { param($s, $e) if ($e.Button -eq 'Left') { $Script:FixDragging = $true; $Script:FixStartX = [System.Windows.Forms.Cursor]::Position.X; $Script:FixStartY = [System.Windows.Forms.Cursor]::Position.Y; $Script:FixFormStartX = $frmFix.Location.X; $Script:FixFormStartY = $frmFix.Location.Y } }
                $FixDragMove = { param($s, $e) if ($Script:FixDragging) { $diffX = [System.Windows.Forms.Cursor]::Position.X - $Script:FixStartX; $diffY = [System.Windows.Forms.Cursor]::Position.Y - $Script:FixStartY; $frmFix.Location = New-Object System.Drawing.Point(($Script:FixFormStartX + $diffX), ($Script:FixFormStartY + $diffY)) } }
                $FixDragUp = { $Script:FixDragging = $false }
                $pnlFixHeader.Add_MouseDown($FixDragDown); $pnlFixHeader.Add_MouseMove($FixDragMove); $pnlFixHeader.Add_MouseUp($FixDragUp); $lblFixHeader.Add_MouseDown($FixDragDown); $lblFixHeader.Add_MouseMove($FixDragMove); $lblFixHeader.Add_MouseUp($FixDragUp)

                $pnlFixContent = New-Object System.Windows.Forms.Panel; $pnlFixContent.Size = "418, 209"; $pnlFixContent.Location = "1, 30"; $pnlFixContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmFix.Controls.Add($pnlFixContent)

                $lblFixMsg = New-Object System.Windows.Forms.Label
                $lblFixMsg.Text = "We detected that the monitor file was moved or renamed.`nTo make Auto-Start work again, we need to update the Windows Task Scheduler."
                $lblFixMsg.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
                $lblFixMsg.Location = New-Object System.Drawing.Point(10, 15)
                $lblFixMsg.Size = New-Object System.Drawing.Size(380, 50)
                $lblFixMsg.AutoSize = $false
                $lblFixMsg.TextAlign = [System.Drawing.ContentAlignment]::TopCenter
                $lblFixMsg.ForeColor = [System.Drawing.Color]::Firebrick
                $pnlFixContent.Controls.Add($lblFixMsg)

                $btnDoFix = New-Object System.Windows.Forms.Button
                $btnDoFix.Text = "Fix Auto-Start now`n(Requires administrator privileges)"
                $btnDoFix.Size = New-Object System.Drawing.Size(380, 50)
                $btnDoFix.Location = New-Object System.Drawing.Point(10, 80)
                $btnDoFix.BackColor = [System.Drawing.Color]::DarkOrange
                $btnDoFix.ForeColor = [System.Drawing.Color]::White
                $btnDoFix.FlatStyle = "Flat"
                $btnDoFix.Add_Click({
                    try {
                        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($fixCmd))
                        Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -EncodedCommand $encoded" -Verb RunAs -Wait
                    } catch {}
                    $frmFix.Close()
                })
                $pnlFixContent.Controls.Add($btnDoFix)

                $btnCancelFix = New-Object System.Windows.Forms.Button
                $btnCancelFix.Text = "Cancel"
                $btnCancelFix.Size = New-Object System.Drawing.Size(380, 40)
                $btnCancelFix.Location = New-Object System.Drawing.Point(10, 140)
                $btnCancelFix.BackColor = [System.Drawing.Color]::LightGray
                $btnCancelFix.FlatStyle = "Flat"
                $btnCancelFix.Add_Click({ $frmFix.Close() })
                $pnlFixContent.Controls.Add($btnCancelFix)

                [void]$frmFix.ShowDialog()
            }
        }
        & $UpdateTaskButtonState
    })
    # =========================================================

    $sepMin = New-Object System.Windows.Forms.Panel; $sepMin.Height = 1; $sepMin.Width = 415; $sepMin.Location = "10, 685"; $sepMin.BackColor = [System.Drawing.Color]::DarkGray; $pnlContent.Controls.Add($sepMin)

    # --- MINIMIZE BEHAVIOR ---
    $lblMin = New-Object System.Windows.Forms.Label; $lblMin.Text = "Minimize Button Action:"; $lblMin.Location = "10, 695"; $lblMin.AutoSize = $true; $lblMin.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlContent.Controls.Add($lblMin)
    
    $pnlMinGroup = New-Object System.Windows.Forms.Panel; $pnlMinGroup.Location = "10, 715"; $pnlMinGroup.Size = "420, 25"; $pnlContent.Controls.Add($pnlMinGroup)
    
    $chkMinStd = New-Object System.Windows.Forms.RadioButton; $chkMinStd.Text = "Standard Minimize (Taskbar)"; $chkMinStd.Location = "10, 0"; $chkMinStd.Width = 200; $chkMinStd.Checked = -not $Global:ConfigData.MinimizeToTray; $chkMinStd.FlatStyle = "System"; $pnlMinGroup.Controls.Add($chkMinStd)
    $chkMinTray = New-Object System.Windows.Forms.RadioButton; $chkMinTray.Text = "Hide to System Tray"; $chkMinTray.Location = "220, 0"; $chkMinTray.Width = 150; $chkMinTray.Checked = $Global:ConfigData.MinimizeToTray; $chkMinTray.FlatStyle = "System"; $pnlMinGroup.Controls.Add($chkMinTray)

    $sepClose = New-Object System.Windows.Forms.Panel; $sepClose.Height = 1; $sepClose.Width = 415; $sepClose.Location = "10, 745"; $sepClose.BackColor = [System.Drawing.Color]::LightGray; $pnlContent.Controls.Add($sepClose)

    # --- CLOSE BUTTON ACTION ---
    $lblClose = New-Object System.Windows.Forms.Label; $lblClose.Text = "Close Button Action:"; $lblClose.Location = "10, 755"; $lblClose.AutoSize = $true; $lblClose.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlContent.Controls.Add($lblClose)
    
    $pnlCloseGroup = New-Object System.Windows.Forms.Panel; $pnlCloseGroup.Location = "10, 775"; $pnlCloseGroup.Size = "420, 25"; $pnlContent.Controls.Add($pnlCloseGroup)
    
    $chkCloseStd = New-Object System.Windows.Forms.RadioButton; $chkCloseStd.Text = "Standard Close (Exit App)"; $chkCloseStd.Location = "10, 0"; $chkCloseStd.Width = 200; $chkCloseStd.Checked = -not $Global:ConfigData.CloseToTray; $chkCloseStd.FlatStyle = "System"; $pnlCloseGroup.Controls.Add($chkCloseStd)
    $chkCloseTray = New-Object System.Windows.Forms.RadioButton; $chkCloseTray.Text = "Hide to System Tray"; $chkCloseTray.Location = "220, 0"; $chkCloseTray.Width = 150; $chkCloseTray.Checked = $Global:ConfigData.CloseToTray; $chkCloseTray.FlatStyle = "System"; $pnlCloseGroup.Controls.Add($chkCloseTray)

    $sepEnd = New-Object System.Windows.Forms.Panel; $sepEnd.Height = 1; $sepEnd.Width = 415; $sepEnd.Location = "10, 805"; $sepEnd.BackColor = [System.Drawing.Color]::DarkGray; $pnlContent.Controls.Add($sepEnd)

    # --- ACTIONS ---
    $btnSave = New-Object System.Windows.Forms.Button; $btnSave.Text = "SAVE CONFIGURATION"; $btnSave.Location = "10, 815"; $btnSave.Size = "415, 35"; $btnSave.BackColor = [System.Drawing.Color]::LightGray; $btnSave.ForeColor = [System.Drawing.Color]::Gray; $btnSave.FlatStyle = "Flat"; $btnSave.Enabled = $false; $pnlContent.Controls.Add($btnSave)
    $btnCfgCancel = New-Object System.Windows.Forms.Button; $btnCfgCancel.Text = "Cancel"; $btnCfgCancel.Location = "10, 860"; $btnCfgCancel.Size = "250, 25"; $btnCfgCancel.BackColor = [System.Drawing.Color]::Firebrick; $btnCfgCancel.ForeColor = [System.Drawing.Color]::White; $btnCfgCancel.FlatStyle = "Flat"; $btnCfgCancel.Add_Click({ $frmCfg.Close() }); $pnlContent.Controls.Add($btnCfgCancel)
    
    $btnFactory = New-Object System.Windows.Forms.Button; $btnFactory.Text = "CLEAR ALL SETTINGS"; $btnFactory.Location = "275, 860"; $btnFactory.Size = "150, 25"; $btnFactory.BackColor = [System.Drawing.Color]::DarkOrchid; $btnFactory.ForeColor = [System.Drawing.Color]::White; $btnFactory.FlatStyle = "Flat"; $btnFactory.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlContent.Controls.Add($btnFactory)

    # --- RODAPÉ / VERSÃO ---
    $lblVersion = New-Object System.Windows.Forms.Label
    $lblVersion.Text = "Performance Monitor v0.9  |  Developed by Fabiopsyduck"
    $lblVersion.Location = "10, 890"  
    $lblVersion.Size = "415, 15"
    $lblVersion.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblVersion.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $lblVersion.ForeColor = [System.Drawing.Color]::DimGray
    $pnlContent.Controls.Add($lblVersion)

    # =========================================================
    # ESTADOS E REGRAS DE BLOQUEIO (Timer)
    # =========================================================
    $UpdateBtnStates = {
        if ($chkFreq.Checked) { $btnFreq.BackColor = [System.Drawing.Color]::SeaGreen; $btnFreq.ForeColor = [System.Drawing.Color]::White; $btnFreq.Enabled = $true } else { $btnFreq.BackColor = [System.Drawing.Color]::LightGray; $btnFreq.ForeColor = [System.Drawing.Color]::Black; $btnFreq.Enabled = $false }
        if ($chkAdaptive.Checked) { $btnAdvanced.BackColor = [System.Drawing.Color]::SeaGreen; $btnAdvanced.ForeColor = [System.Drawing.Color]::White; $btnAdvanced.Enabled = $true } else { $btnAdvanced.BackColor = [System.Drawing.Color]::LightGray; $btnAdvanced.ForeColor = [System.Drawing.Color]::Black; $btnAdvanced.Enabled = $false }
        
        if ($script:IsAdmin) {
            if ($chkHot.Checked) { $btnHot.BackColor = [System.Drawing.Color]::SeaGreen; $btnHot.ForeColor = [System.Drawing.Color]::White; $btnHot.Enabled = $true } else { $btnHot.BackColor = [System.Drawing.Color]::LightGray; $btnHot.ForeColor = [System.Drawing.Color]::Black; $btnHot.Enabled = $false }
        } else { 
            $btnHot.BackColor = [System.Drawing.Color]::LightGray; $btnHot.ForeColor = [System.Drawing.Color]::Black; $btnHot.Enabled = $false 
        }

        $isFactBack = ($Global:ConfigData.BackOpacity -ne 0.99); $isFactCont = ($Global:ConfigData.ContentOpacity -ne 1.0); $isFactPos = ($Global:ConfigData.PosX -ne $null); $isFactLock = ($Global:ConfigData.StartLocked -eq $true); $isFactHidden = ($Global:ConfigData.StartHidden -eq $true); $isFactReqAdmin = ($Global:ConfigData.RequireAdmin -eq $true)
        $isFactAdapt = ($Global:ConfigData.AdaptiveEnabled -eq $true); $isFactHot = ($Global:ConfigData.HotkeyEnabled -eq $true)
        $isFreqChanged = ($chkFreq.Checked -ne $Global:ConfigData.FreqEnabled) -or ($Global:ConfigData.FreqValue -ne 200)
        $isSpikeChanged = ($Global:ConfigData.SpikeProtection -ne $false) -or ($Global:ConfigData.SpikeTolerance -ne 15)
        $isMinChanged = ($chkMinTray.Checked -ne $Global:ConfigData.MinimizeToTray)
        $isCloseChanged = ($chkCloseTray.Checked -ne $Global:ConfigData.CloseToTray)
        $isFactClose = ($Global:ConfigData.CloseToTray -eq $true)
        $isFactTask = $Script:TaskIsConfigured 

        if ($isFactBack -or $isFactCont -or $isFactPos -or $isFactLock -or $isFactHidden -or $isFactReqAdmin -or $isFactAdapt -or $isFactHot -or $isFreqChanged -or $isSpikeChanged -or $isMinChanged -or $isCloseChanged -or $isFactClose -or $isFactTask) { 
            $btnFactory.Enabled = $true; $btnFactory.BackColor = [System.Drawing.Color]::DarkOrchid; $btnFactory.ForeColor = [System.Drawing.Color]::White 
        } else { 
            $btnFactory.Enabled = $false; $btnFactory.BackColor = [System.Drawing.Color]::LightGray; $btnFactory.ForeColor = [System.Drawing.Color]::Gray 
        }

        $dirty = $false
        $currentBackOp = $trackBackOp.Value / 100; if ($currentBackOp -eq 0) { $currentBackOp = 0.01 }; if ([math]::Abs($currentBackOp - $Global:ConfigData.BackOpacity) -gt 0.001) { $dirty = $true }
        $currentContOp = $trackContOp.Value / 100; if ([math]::Abs($currentContOp - $Global:ConfigData.ContentOpacity) -gt 0.001) { $dirty = $true }
        if ($Script:PendingPos -ne $null) { if ($Global:ConfigData.PosX -eq $null) { $dirty = $true } elseif ($Script:PendingPos.X -ne $Global:ConfigData.PosX -or $Script:PendingPos.Y -ne $Global:ConfigData.PosY) { $dirty = $true } } elseif ($Script:HardResetPosActive) { $dirty = $true }
        if ($chkStartLock.Checked -ne $Global:ConfigData.StartLocked) { $dirty = $true }
        if ($chkStartHidden.Checked -ne $Global:ConfigData.StartHidden) { $dirty = $true }
        if ($chkReqAdmin.Checked -ne $Global:ConfigData.RequireAdmin) { $dirty = $true }
        if ($script:IsAdmin) { if ($chkHot.Checked -ne $Global:ConfigData.HotkeyEnabled) { $dirty = $true } }
        if ($chkAdaptive.Checked -ne $Global:ConfigData.AdaptiveEnabled) { $dirty = $true }
        if ($chkFreq.Checked -ne $Global:ConfigData.FreqEnabled) { $dirty = $true }
        if ($chkMinTray.Checked -ne $Global:ConfigData.MinimizeToTray) { $dirty = $true }
        if ($chkCloseTray.Checked -ne $Global:ConfigData.CloseToTray) { $dirty = $true }
        if ($Script:AdvancedChanged) { $dirty = $true }

        if ($dirty) { $btnSave.Enabled = $true; $btnSave.BackColor = [System.Drawing.Color]::DodgerBlue; $btnSave.ForeColor = [System.Drawing.Color]::White } else { $btnSave.Enabled = $false; $btnSave.BackColor = [System.Drawing.Color]::LightGray; $btnSave.ForeColor = [System.Drawing.Color]::Gray }

        if ($Script:HardResetOpActive) { $btnResetBackOp.Text = "Reset Back (Only)"; $btnResetBackOp.BackColor = [System.Drawing.Color]::Silver; $btnResetBackOp.ForeColor = [System.Drawing.Color]::Black; $btnResetBackOp.Enabled = $false } else { $isOpDiff = ($formBack.Opacity -ne $Global:ConfigData.BackOpacity); $isOpNotDef = ($Global:ConfigData.BackOpacity -ne 0.99); if ($isOpDiff) { $btnResetBackOp.Text = "Undo change"; $btnResetBackOp.BackColor = [System.Drawing.Color]::Orange; $btnResetBackOp.ForeColor = [System.Drawing.Color]::Black; $btnResetBackOp.Enabled = $true } elseif ($isOpNotDef) { $btnResetBackOp.Text = "Reset Back (Only)"; $btnResetBackOp.BackColor = [System.Drawing.Color]::Firebrick; $btnResetBackOp.ForeColor = [System.Drawing.Color]::White; $btnResetBackOp.Enabled = $true } else { $btnResetBackOp.Text = "Reset Back (Only)"; $btnResetBackOp.BackColor = [System.Drawing.Color]::Silver; $btnResetBackOp.ForeColor = [System.Drawing.Color]::Black; $btnResetBackOp.Enabled = $false } }
        if ($Script:HardResetContOp) { $btnResetContOp.Text = "Reset Content (Only)"; $btnResetContOp.BackColor = [System.Drawing.Color]::Silver; $btnResetContOp.ForeColor = [System.Drawing.Color]::Black; $btnResetContOp.Enabled = $false } else { $isContDiff = ($form.Opacity -ne $Global:ConfigData.ContentOpacity); $isContNotDef = ($Global:ConfigData.ContentOpacity -ne 1.0); if ($isContDiff) { $btnResetContOp.Text = "Undo change"; $btnResetContOp.BackColor = [System.Drawing.Color]::Orange; $btnResetContOp.ForeColor = [System.Drawing.Color]::Black; $btnResetContOp.Enabled = $true } elseif ($isContNotDef) { $btnResetContOp.Text = "Reset Content (Only)"; $btnResetContOp.BackColor = [System.Drawing.Color]::Firebrick; $btnResetContOp.ForeColor = [System.Drawing.Color]::White; $btnResetContOp.Enabled = $true } else { $btnResetContOp.Text = "Reset Content (Only)"; $btnResetContOp.BackColor = [System.Drawing.Color]::Silver; $btnResetContOp.ForeColor = [System.Drawing.Color]::Black; $btnResetContOp.Enabled = $false } }
        $curLoc = $formBack.Location; $targetLoc = $null; if ($Script:PendingPos -ne $null) { $targetLoc = $Script:PendingPos } elseif ($Global:ConfigData.PosX -ne $null) { $targetLoc = New-Object System.Drawing.Point($Global:ConfigData.PosX, $Global:ConfigData.PosY) } else { $screen = [System.Windows.Forms.Screen]::FromControl($formBack); $cx = $screen.WorkingArea.X + ($screen.WorkingArea.Width - $formBack.Width) / 2; $cy = $screen.WorkingArea.Y + ($screen.WorkingArea.Height - $formBack.Height) / 2; $targetLoc = New-Object System.Drawing.Point($cx, $cy) }; if ($curLoc.X -eq $targetLoc.X -and $curLoc.Y -eq $targetLoc.Y) { $btnMemPos.Enabled = $false; $btnMemPos.BackColor = [System.Drawing.Color]::Silver } else { $btnMemPos.Enabled = $true; $btnMemPos.BackColor = [System.Drawing.Color]::SeaGreen }
        if ($Script:HardResetPosActive) { $btnResetPos.Text = "Reset Position (Only)"; $btnResetPos.BackColor = [System.Drawing.Color]::Silver; $btnResetPos.ForeColor = [System.Drawing.Color]::Black; $btnResetPos.Enabled = $false } else { $isPosUnsaved = $false; if ($Script:PendingPos -ne $null -and $Global:ConfigData.PosX -ne $null) { if ($Script:PendingPos.X -ne $Global:ConfigData.PosX -or $Script:PendingPos.Y -ne $Global:ConfigData.PosY) { $isPosUnsaved = $true } } elseif ($Script:PendingPos -ne $null -and $Global:ConfigData.PosX -eq $null) { $isPosUnsaved = $true } elseif ($Script:PendingPos -eq $null -and $Global:ConfigData.PosX -ne $null) { $isPosUnsaved = $true }; if ($isPosUnsaved) { $btnResetPos.Text = "Undo change"; $btnResetPos.BackColor = [System.Drawing.Color]::Orange; $btnResetPos.ForeColor = [System.Drawing.Color]::Black; $btnResetPos.Enabled = $true } elseif ($Global:ConfigData.PosX -ne $null) { $btnResetPos.Text = "Reset Position (Only)"; $btnResetPos.BackColor = [System.Drawing.Color]::Firebrick; $btnResetPos.ForeColor = [System.Drawing.Color]::White; $btnResetPos.Enabled = $true } else { $btnResetPos.Text = "Reset Position (Only)"; $btnResetPos.BackColor = [System.Drawing.Color]::Silver; $btnResetPos.ForeColor = [System.Drawing.Color]::Black; $btnResetPos.Enabled = $false } }
    }

    $chkFreq.Add_Click({ if ($chkFreq.Checked) { $chkAdaptive.Checked = $false }; & $UpdateBtnStates })
    $chkAdaptive.Add_Click({ if ($chkAdaptive.Checked) { $chkFreq.Checked = $false }; & $UpdateBtnStates })
    $chkMinStd.Add_Click({ & $UpdateBtnStates }); $chkMinTray.Add_Click({ & $UpdateBtnStates })
    $chkCloseStd.Add_Click({ & $UpdateBtnStates }); $chkCloseTray.Add_Click({ & $UpdateBtnStates })
    
    $trackBackOp.Add_Scroll({ $val = $trackBackOp.Value; $newOp = $val / 100; if ($newOp -eq 0) { $newOp = 0.01 }; $formBack.Opacity = $newOp; $lblBackOpPct.Text = "$val%"; $Script:HardResetOpActive = $false; & $UpdateBtnStates })
    $trackContOp.Add_Scroll({ $val = $trackContOp.Value; $form.Opacity = $val / 100; $lblContOpPct.Text = "$val%"; $Script:HardResetContOp = $false; & $UpdateBtnStates })
    $chkStartLock.Add_Click({ & $UpdateBtnStates }); $chkStartHidden.Add_Click({ & $UpdateBtnStates }); $chkReqAdmin.Add_Click({ & $UpdateBtnStates })
    $chkHot.Add_Click({ if ($script:IsAdmin) { & $UpdateBtnStates } })
    
    $cfgTimer = New-Object System.Windows.Forms.Timer; $cfgTimer.Interval = 200; $cfgTimer.Add_Tick({ if ($frmCfg.Visible) { & $UpdateBtnStates } }); $cfgTimer.Start()

    $btnResetBackOp.Add_Click({ if ($btnResetBackOp.Text -eq "Undo change") { $restoredOp = $Global:ConfigData.BackOpacity; if ($restoredOp -lt 0.01) { $restoredOp = 0.01 }; $formBack.Opacity = $restoredOp; $trackBackOp.Value = [int]($Global:ConfigData.BackOpacity * 100); $lblBackOpPct.Text = "$($trackBackOp.Value)%"; $Script:HardResetOpActive = $false } else { $res = [System.Windows.Forms.MessageBox]::Show("Reset Background Opacity to default (99%)?", "Reset Opacity", "YesNo", "Warning"); if ($res -eq "Yes") { $formBack.Opacity = 0.99; $trackBackOp.Value = 99; $lblBackOpPct.Text = "99%"; $Script:HardResetOpActive = $true } }; & $UpdateBtnStates })
    $btnResetContOp.Add_Click({ if ($btnResetContOp.Text -eq "Undo change") { $form.Opacity = $Global:ConfigData.ContentOpacity; $trackContOp.Value = [int]($form.Opacity * 100); $lblContOpPct.Text = "$($trackContOp.Value)%"; $Script:HardResetContOp = $false } else { $res = [System.Windows.Forms.MessageBox]::Show("Reset Content Opacity to default (100%)?", "Reset Opacity", "YesNo", "Warning"); if ($res -eq "Yes") { $form.Opacity = 1.0; $trackContOp.Value = 100; $lblContOpPct.Text = "100%"; $Script:HardResetContOp = $true } }; & $UpdateBtnStates })
    $btnMemPos.Add_Click({ $Script:PendingPos = $formBack.Location; $Script:HardResetPosActive = $false; 
        
        # POPUP CUSTOMIZADO (Memorized Position)
        $frmPosDone = New-Object System.Windows.Forms.Form; $frmPosDone.Size = New-Object System.Drawing.Size(350, 150); $frmPosDone.StartPosition = "CenterParent"; $frmPosDone.TopMost = $true; $frmPosDone.FormBorderStyle = "None"; $frmPosDone.BackColor = [System.Drawing.Color]::DimGray; $frmPosDone.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None; $frmPosDone.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $pnlPDHeader = New-Object System.Windows.Forms.Panel; $pnlPDHeader.Size = "350, 30"; $pnlPDHeader.Location = "0, 0"; $pnlPDHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmPosDone.Controls.Add($pnlPDHeader)
        $lblPDHeader = New-Object System.Windows.Forms.Label; $lblPDHeader.Text = "Information"; $lblPDHeader.Location = "10, 7"; $lblPDHeader.AutoSize = $true; $lblPDHeader.ForeColor = [System.Drawing.Color]::White; $lblPDHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlPDHeader.Controls.Add($lblPDHeader)
        $pnlPDContent = New-Object System.Windows.Forms.Panel; $pnlPDContent.Size = "348, 119"; $pnlPDContent.Location = "1, 30"; $pnlPDContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmPosDone.Controls.Add($pnlPDContent)
        $lblPDMsg = New-Object System.Windows.Forms.Label; $lblPDMsg.Text = "Position Memorized! (Click Save to confirm)"; $lblPDMsg.Location = "20, 20"; $lblPDMsg.Size = "310, 40"; $lblPDMsg.AutoSize = $false; $pnlPDContent.Controls.Add($lblPDMsg)
        $btnPDOk = New-Object System.Windows.Forms.Button; $btnPDOk.Text = "OK"; $btnPDOk.Location = "115, 70"; $btnPDOk.Size = "120, 30"; $btnPDOk.BackColor = [System.Drawing.Color]::DodgerBlue; $btnPDOk.ForeColor = [System.Drawing.Color]::White; $btnPDOk.FlatStyle = "Flat"; $btnPDOk.Add_Click({ $frmPosDone.Close() }); $pnlPDContent.Controls.Add($btnPDOk)
        [void]$frmPosDone.ShowDialog()
        
        & $UpdateBtnStates 
    })
    $btnResetPos.Add_Click({ if ($btnResetPos.Text -eq "Undo change") { if ($Global:ConfigData.PosX -ne $null) { $Script:PendingPos = New-Object System.Drawing.Point($Global:ConfigData.PosX, $Global:ConfigData.PosY); $formBack.Location = $Script:PendingPos } else { $formBack.StartPosition = "CenterScreen"; $screen = [System.Windows.Forms.Screen]::FromControl($formBack); $x = $screen.WorkingArea.X + ($screen.WorkingArea.Width - $formBack.Width) / 2; $y = $screen.WorkingArea.Y + ($screen.WorkingArea.Height - $formBack.Height) / 2; $formBack.Location = New-Object System.Drawing.Point($x, $y); $Script:PendingPos = $null }; $Script:HardResetPosActive = $false } else { $res = [System.Windows.Forms.MessageBox]::Show("Reset Position to default (Center Screen)?", "Reset Position", "YesNo", "Warning"); if ($res -eq "Yes") { $formBack.StartPosition = "CenterScreen"; $screen = [System.Windows.Forms.Screen]::FromControl($formBack); $x = $screen.WorkingArea.X + ($screen.WorkingArea.Width - $formBack.Width) / 2; $y = $screen.WorkingArea.Y + ($screen.WorkingArea.Height - $formBack.Height) / 2; $formBack.Location = New-Object System.Drawing.Point($x, $y); $Script:PendingPos = $null; $Script:HardResetPosActive = $true } }; & $UpdateBtnStates })
    
    $btnFactory.Add_Click({ 
        # POPUP CUSTOMIZADO DE CUIDADO (YES / NO) COM ESCOPO CORRIGIDO
        $frmWarn = New-Object System.Windows.Forms.Form; $frmWarn.Size = New-Object System.Drawing.Size(400, 180); $frmWarn.StartPosition = "CenterParent"; $frmWarn.TopMost = $true; $frmWarn.FormBorderStyle = "None"; $frmWarn.BackColor = [System.Drawing.Color]::DimGray; $frmWarn.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None; $frmWarn.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $pnlWHeader = New-Object System.Windows.Forms.Panel; $pnlWHeader.Size = "400, 30"; $pnlWHeader.Location = "0, 0"; $pnlWHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmWarn.Controls.Add($pnlWHeader)
        $lblWHeader = New-Object System.Windows.Forms.Label; $lblWHeader.Text = "CLEAR ALL SETTINGS"; $lblWHeader.Location = "10, 7"; $lblWHeader.AutoSize = $true; $lblWHeader.ForeColor = [System.Drawing.Color]::White; $lblWHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlWHeader.Controls.Add($lblWHeader)
        $pnlWContent = New-Object System.Windows.Forms.Panel; $pnlWContent.Size = "398, 149"; $pnlWContent.Location = "1, 30"; $pnlWContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmWarn.Controls.Add($pnlWContent)
        $lblWMsg = New-Object System.Windows.Forms.Label; $lblWMsg.Text = "WARNING: This will delete 'Config.ini' and reset everything to factory defaults.`nAre you sure?"; $lblWMsg.Location = "20, 20"; $lblWMsg.Size = "360, 50"; $lblWMsg.AutoSize = $false; $lblWMsg.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $lblWMsg.ForeColor = [System.Drawing.Color]::Firebrick; $pnlWContent.Controls.Add($lblWMsg)
        
        $Script:FactoryConfirm = $false
        
        $btnWYes = New-Object System.Windows.Forms.Button; $btnWYes.Text = "Yes"; $btnWYes.Location = "60, 90"; $btnWYes.Size = "120, 30"; $btnWYes.BackColor = [System.Drawing.Color]::Firebrick; $btnWYes.ForeColor = [System.Drawing.Color]::White; $btnWYes.FlatStyle = "Flat"; $btnWYes.Add_Click({ $Script:FactoryConfirm = $true; $frmWarn.Close() }); $pnlWContent.Controls.Add($btnWYes)
        $btnWNo = New-Object System.Windows.Forms.Button; $btnWNo.Text = "No"; $btnWNo.Location = "210, 90"; $btnWNo.Size = "120, 30"; $btnWNo.BackColor = [System.Drawing.Color]::LightGray; $btnWNo.ForeColor = [System.Drawing.Color]::Black; $btnWNo.FlatStyle = "Flat"; $btnWNo.Add_Click({ $Script:FactoryConfirm = $false; $frmWarn.Close() }); $pnlWContent.Controls.Add($btnWNo)
        [void]$frmWarn.ShowDialog()
        
        if ($Script:FactoryConfirm) { 
            if (Test-Path $ConfigFile) { Remove-Item $ConfigFile }; 
            $Global:ConfigData = @{ BackOpacity = 0.99; ContentOpacity = 1.0; PosX = $null; PosY = $null; StartLocked = $false; StartHidden = $false; RequireAdmin = $false; AdaptiveEnabled = $false; AdaptiveTrigger = $null; AdaptiveApplyText = $false; AdaptiveApplyBar = $false; AdaptiveMode = $null; AdaptiveTargetCpu = $false; AdaptiveTargetRam = $false; AdaptiveTargetGpu = $false; AdaptiveTargetVram = $false; HotkeyEnabled = $false; HotkeyMode = $null; HotkeyPrimary = $null; HotkeySecondary = $null; HotkeySeconds = $null; AdaptiveRolling = $false; AdaptiveEma = $false; AdaptiveHysteresis = $false; AdaptiveDema = $false; AdaptiveAlma = $false; SpikeProtection = $false; SpikeTolerance = 15; FreqEnabled = $false; FreqValue = 200; MinimizeToTray = $false; CloseToTray = $false }; 
            $Global:HasPreviousConfig = $false; 
            $formBack.Opacity = 0.99; $trackBackOp.Value = 99; $lblBackOpPct.Text = "99%"; 
            $form.Opacity = 1.0; $trackContOp.Value = 100; $lblContOpPct.Text = "100%"; 
            $chkStartLock.Checked = $false; $chkStartHidden.Checked = $false; $chkReqAdmin.Checked = $false; $chkAdaptive.Checked = $false; $chkHot.Checked = $false; $btnAdvanced.Enabled = $false; $btnHot.Enabled = $false; $chkFreq.Checked = $false; $btnFreq.Enabled = $false; $chkMinStd.Checked = $true; $chkCloseStd.Checked = $true
            $formBack.StartPosition = "CenterScreen"; $screen = [System.Windows.Forms.Screen]::FromControl($formBack); $x = $screen.WorkingArea.X + ($screen.WorkingArea.Width - $formBack.Width) / 2; $y = $screen.WorkingArea.Y + ($screen.WorkingArea.Height - $formBack.Height) / 2; $formBack.Location = New-Object System.Drawing.Point($x, $y); 
            $Script:PendingPos = $null; $Script:HardResetPosActive = $false; $Script:HardResetOpActive = $false; $Script:HardResetContOp = $false; $Script:AdvancedChanged = $false; 
            
            $taskName = "Performance Monitor"
            $taskExists = $false
            $checkTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($null -ne $checkTask) { $taskExists = $true }

            if ($taskExists) {
                if ($script:IsAdmin) {
                    try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}
                    
                    # POPUP SUCESSO
                    $frmRst = New-Object System.Windows.Forms.Form; $frmRst.Size = New-Object System.Drawing.Size(350, 150); $frmRst.StartPosition = "CenterParent"; $frmRst.TopMost = $true; $frmRst.FormBorderStyle = "None"; $frmRst.BackColor = [System.Drawing.Color]::DimGray; $frmRst.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None; $frmRst.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
                    $pnlRHeader = New-Object System.Windows.Forms.Panel; $pnlRHeader.Size = "350, 30"; $pnlRHeader.Location = "0, 0"; $pnlRHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmRst.Controls.Add($pnlRHeader)
                    $lblRHeader = New-Object System.Windows.Forms.Label; $lblRHeader.Text = "Reset Complete"; $lblRHeader.Location = "10, 7"; $lblRHeader.AutoSize = $true; $lblRHeader.ForeColor = [System.Drawing.Color]::White; $lblRHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlRHeader.Controls.Add($lblRHeader)
                    $pnlRContent = New-Object System.Windows.Forms.Panel; $pnlRContent.Size = "348, 119"; $pnlRContent.Location = "1, 30"; $pnlRContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmRst.Controls.Add($pnlRContent)
                    $lblRMsg = New-Object System.Windows.Forms.Label; $lblRMsg.Text = "All configurations deleted and reset."; $lblRMsg.Location = "20, 20"; $lblRMsg.Size = "310, 40"; $lblRMsg.AutoSize = $false; $pnlRContent.Controls.Add($lblRMsg)
                    $btnROk = New-Object System.Windows.Forms.Button; $btnROk.Text = "OK"; $btnROk.Location = "115, 70"; $btnROk.Size = "120, 30"; $btnROk.BackColor = [System.Drawing.Color]::DodgerBlue; $btnROk.ForeColor = [System.Drawing.Color]::White; $btnROk.FlatStyle = "Flat"; $btnROk.Add_Click({ $frmRst.Close() }); $pnlRContent.Controls.Add($btnROk)
                    [void]$frmRst.ShowDialog()

                } else {
                    $frmTask = New-Object System.Windows.Forms.Form; $frmTask.Size = New-Object System.Drawing.Size(420, 310); $frmTask.StartPosition = "CenterParent"; $frmTask.TopMost = $true; 
                    $frmTask.FormBorderStyle = "None"; $frmTask.BackColor = [System.Drawing.Color]::DimGray
                    $frmTask.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
                    $frmTask.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

                    # --- HEADER FRMTASK ---
                    $pnlTaskHeader = New-Object System.Windows.Forms.Panel; $pnlTaskHeader.Size = "420, 30"; $pnlTaskHeader.Location = "0, 0"; $pnlTaskHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmTask.Controls.Add($pnlTaskHeader)
                    $lblTaskHeader = New-Object System.Windows.Forms.Label; $lblTaskHeader.Text = "Action Required"; $lblTaskHeader.Location = "10, 7"; $lblTaskHeader.AutoSize = $true; $lblTaskHeader.ForeColor = [System.Drawing.Color]::White; $lblTaskHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlTaskHeader.Controls.Add($lblTaskHeader)
                    $btnTaskClose = New-Object System.Windows.Forms.Button; $btnTaskClose.Text = "X"; $btnTaskClose.Size = "40, 30"; $btnTaskClose.Location = "380, 0"; $btnTaskClose.FlatStyle = "Flat"; $btnTaskClose.FlatAppearance.BorderSize = 0; $btnTaskClose.ForeColor = [System.Drawing.Color]::White; $btnTaskClose.BackColor = [System.Drawing.Color]::Transparent; $btnTaskClose.Cursor = [System.Windows.Forms.Cursors]::Hand; $pnlTaskHeader.Controls.Add($btnTaskClose)
                    $btnTaskClose.Add_Click({ $frmTask.Close() }); $btnTaskClose.Add_MouseEnter({ $btnTaskClose.BackColor = [System.Drawing.Color]::Firebrick }); $btnTaskClose.Add_MouseLeave({ $btnTaskClose.BackColor = [System.Drawing.Color]::Transparent })
                    
                    # --- DRAG FRMTASK ---
                    $Script:TaskDragging = $false; $Script:TaskStartX = 0; $Script:TaskStartY = 0; $Script:TaskFormStartX = 0; $Script:TaskFormStartY = 0
                    $TaskDragDown = { param($s, $e) if ($e.Button -eq 'Left') { $Script:TaskDragging = $true; $Script:TaskStartX = [System.Windows.Forms.Cursor]::Position.X; $Script:TaskStartY = [System.Windows.Forms.Cursor]::Position.Y; $Script:TaskFormStartX = $frmTask.Location.X; $Script:TaskFormStartY = $frmTask.Location.Y } }
                    $TaskDragMove = { param($s, $e) if ($Script:TaskDragging) { $diffX = [System.Windows.Forms.Cursor]::Position.X - $Script:TaskStartX; $diffY = [System.Windows.Forms.Cursor]::Position.Y - $Script:TaskStartY; $frmTask.Location = New-Object System.Drawing.Point(($Script:TaskFormStartX + $diffX), ($Script:TaskFormStartY + $diffY)) } }
                    $TaskDragUp = { $Script:TaskDragging = $false }
                    $pnlTaskHeader.Add_MouseDown($TaskDragDown); $pnlTaskHeader.Add_MouseMove($TaskDragMove); $pnlTaskHeader.Add_MouseUp($TaskDragUp); $lblTaskHeader.Add_MouseDown($TaskDragDown); $lblTaskHeader.Add_MouseMove($TaskDragMove); $lblTaskHeader.Add_MouseUp($TaskDragUp)

                    $pnlTaskContent = New-Object System.Windows.Forms.Panel; $pnlTaskContent.Size = "418, 279"; $pnlTaskContent.Location = "1, 30"; $pnlTaskContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmTask.Controls.Add($pnlTaskContent)

                    $lblWarning = New-Object System.Windows.Forms.Label
                    $lblWarning.Text = "All settings have been successfully reset!`nHowever, 'Performance Monitor' is still active in Windows startup.`nChoose below how you wish to proceed:"
                    $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
                    $lblWarning.Location = New-Object System.Drawing.Point(10, 10)
                    $lblWarning.Size = New-Object System.Drawing.Size(380, 80)
                    $lblWarning.AutoSize = $false
                    $lblWarning.TextAlign = [System.Drawing.ContentAlignment]::TopCenter
                    $lblWarning.ForeColor = [System.Drawing.Color]::Firebrick
                    $pnlTaskContent.Controls.Add($lblWarning)

                    $btnKeep = New-Object System.Windows.Forms.Button
                    $btnKeep.Text = "I do not want to delete this configuration"
                    $btnKeep.Size = New-Object System.Drawing.Size(380, 40)
                    $btnKeep.Location = New-Object System.Drawing.Point(10, 95)
                    $btnKeep.BackColor = [System.Drawing.Color]::LightGray
                    $btnKeep.FlatStyle = "Flat"
                    $btnKeep.Add_Click({ $frmTask.Close() })
                    $pnlTaskContent.Controls.Add($btnKeep)

                    $btnAuto = New-Object System.Windows.Forms.Button
                    $btnAuto.Text = "I want 'Performance Monitor' to delete it for me.`n(Requires administrator privileges)"
                    $btnAuto.Size = New-Object System.Drawing.Size(380, 50)
                    $btnAuto.Location = New-Object System.Drawing.Point(10, 145)
                    $btnAuto.BackColor = [System.Drawing.Color]::SeaGreen
                    $btnAuto.ForeColor = [System.Drawing.Color]::White
                    $btnAuto.FlatStyle = "Flat"
                    $btnAuto.Add_Click({
                        try { Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -Command `"Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false`"" -Verb RunAs -Wait } catch {}
                        $frmTask.Close()
                    })
                    $pnlTaskContent.Controls.Add($btnAuto)

                    $btnManual = New-Object System.Windows.Forms.Button
                    $btnManual.Text = "I want to delete this configuration manually"
                    $btnManual.Size = New-Object System.Drawing.Size(380, 40)
                    $btnManual.Location = New-Object System.Drawing.Point(10, 205)
                    $btnManual.BackColor = [System.Drawing.Color]::DodgerBlue
                    $btnManual.ForeColor = [System.Drawing.Color]::White
                    $btnManual.FlatStyle = "Flat"
                    $btnManual.Add_Click({
                        Start-Process "taskschd.msc"
                        $frmTask.Close()
                    })
                    $pnlTaskContent.Controls.Add($btnManual)
                    [void]$frmTask.ShowDialog()
                }
            } else {
                # POPUP SUCESSO
                $frmRst = New-Object System.Windows.Forms.Form; $frmRst.Size = New-Object System.Drawing.Size(350, 150); $frmRst.StartPosition = "CenterParent"; $frmRst.TopMost = $true; $frmRst.FormBorderStyle = "None"; $frmRst.BackColor = [System.Drawing.Color]::DimGray; $frmRst.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None; $frmRst.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
                $pnlRHeader = New-Object System.Windows.Forms.Panel; $pnlRHeader.Size = "350, 30"; $pnlRHeader.Location = "0, 0"; $pnlRHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmRst.Controls.Add($pnlRHeader)
                $lblRHeader = New-Object System.Windows.Forms.Label; $lblRHeader.Text = "Reset Complete"; $lblRHeader.Location = "10, 7"; $lblRHeader.AutoSize = $true; $lblRHeader.ForeColor = [System.Drawing.Color]::White; $lblRHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlRHeader.Controls.Add($lblRHeader)
                $pnlRContent = New-Object System.Windows.Forms.Panel; $pnlRContent.Size = "348, 119"; $pnlRContent.Location = "1, 30"; $pnlRContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmRst.Controls.Add($pnlRContent)
                $lblRMsg = New-Object System.Windows.Forms.Label; $lblRMsg.Text = "All configurations deleted and reset."; $lblRMsg.Location = "20, 20"; $lblRMsg.Size = "310, 40"; $lblRMsg.AutoSize = $false; $pnlRContent.Controls.Add($lblRMsg)
                $btnROk = New-Object System.Windows.Forms.Button; $btnROk.Text = "OK"; $btnROk.Location = "115, 70"; $btnROk.Size = "120, 30"; $btnROk.BackColor = [System.Drawing.Color]::DodgerBlue; $btnROk.ForeColor = [System.Drawing.Color]::White; $btnROk.FlatStyle = "Flat"; $btnROk.Add_Click({ $frmRst.Close() }); $pnlRContent.Controls.Add($btnROk)
                [void]$frmRst.ShowDialog()
            }
            & $UpdateTaskButtonState
            & $UpdateBtnStates
        } 
    })
    
    $btnSave.Add_Click({ 
        $finalX = $null; $finalY = $null; 
        if (-not $Script:HardResetPosActive) { if ($Script:PendingPos -ne $null) { $finalX = $Script:PendingPos.X; $finalY = $Script:PendingPos.Y } }; 
        $realBackOp = $trackBackOp.Value / 100; 
        $finalHotEnable = if ($script:IsAdmin) { $chkHot.Checked } else { $Global:ConfigData.HotkeyEnabled }

        $wasAdminRequired = $Global:ConfigData.RequireAdmin
        $nowAdminRequired = $chkReqAdmin.Checked

        $SaveData = @{ 
            BackOpacity = $realBackOp; ContentOpacity = $form.Opacity; PosX = $finalX; PosY = $finalY; 
            StartLocked = $chkStartLock.Checked; StartHidden = $chkStartHidden.Checked; RequireAdmin = $chkReqAdmin.Checked;
            AdaptiveEnabled = $chkAdaptive.Checked; AdaptiveTrigger = $Global:ConfigData.AdaptiveTrigger; AdaptiveApplyText = $Global:ConfigData.AdaptiveApplyText; AdaptiveApplyBar = $Global:ConfigData.AdaptiveApplyBar; AdaptiveMode = $Global:ConfigData.AdaptiveMode; 
            AdaptiveTargetCpu = $Global:ConfigData.AdaptiveTargetCpu; AdaptiveTargetRam = $Global:ConfigData.AdaptiveTargetRam; AdaptiveTargetGpu = $Global:ConfigData.AdaptiveTargetGpu; AdaptiveTargetVram = $Global:ConfigData.AdaptiveTargetVram; 
            HotkeyEnabled = $finalHotEnable; HotkeyMode = $Global:ConfigData.HotkeyMode; HotkeyPrimary = $Global:ConfigData.HotkeyPrimary; HotkeySecondary = $Global:ConfigData.HotkeySecondary; HotkeySeconds = $Global:ConfigData.HotkeySeconds; 
            AdaptiveRolling = $Global:ConfigData.AdaptiveRolling; AdaptiveEma = $Global:ConfigData.AdaptiveEma; AdaptiveHysteresis = $Global:ConfigData.AdaptiveHysteresis; AdaptiveDema = $Global:ConfigData.AdaptiveDema; AdaptiveAlma = $Global:ConfigData.AdaptiveAlma; 
            SpikeProtection = $Global:ConfigData.SpikeProtection; SpikeTolerance = $Global:ConfigData.SpikeTolerance; 
            FreqEnabled = $chkFreq.Checked; FreqValue = $Global:ConfigData.FreqValue; 
            MinimizeToTray = $chkMinTray.Checked; CloseToTray = $chkCloseTray.Checked
        }; 
        $SaveData | ConvertTo-Json | Out-File $ConfigFile; 
        $Global:ConfigData = $SaveData; 
        $Global:HasPreviousConfig = $true; 
        $Script:SavedChanges = $true; 
        $Script:AdvancedChanged = $false; 
        
        # POPUP FINAL DE CONFIGURAÇÃO (BLINDADO E EXPANDIDO)
        $frmCfgDone = New-Object System.Windows.Forms.Form; $frmCfgDone.Size = New-Object System.Drawing.Size(420, 240); $frmCfgDone.StartPosition = "CenterParent"; $frmCfgDone.TopMost = $true; $frmCfgDone.FormBorderStyle = "None"; $frmCfgDone.BackColor = [System.Drawing.Color]::DimGray; $frmCfgDone.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None; $frmCfgDone.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $pnlCDHeader = New-Object System.Windows.Forms.Panel; $pnlCDHeader.Size = "420, 30"; $pnlCDHeader.Location = "0, 0"; $pnlCDHeader.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40); $frmCfgDone.Controls.Add($pnlCDHeader)
        $lblCDHeader = New-Object System.Windows.Forms.Label; $lblCDHeader.Location = "10, 7"; $lblCDHeader.AutoSize = $true; $lblCDHeader.ForeColor = [System.Drawing.Color]::White; $lblCDHeader.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel); $pnlCDHeader.Controls.Add($lblCDHeader)
        $pnlCDContent = New-Object System.Windows.Forms.Panel; $pnlCDContent.Size = "418, 209"; $pnlCDContent.Location = "1, 30"; $pnlCDContent.BackColor = [System.Drawing.Color]::WhiteSmoke; $frmCfgDone.Controls.Add($pnlCDContent)
        $lblCDMsg = New-Object System.Windows.Forms.Label; $lblCDMsg.Location = "20, 20"; $lblCDMsg.Size = "380, 110"; $lblCDMsg.AutoSize = $false; $pnlCDContent.Controls.Add($lblCDMsg)
        $btnCDOk = New-Object System.Windows.Forms.Button; $btnCDOk.Text = "OK"; $btnCDOk.Location = "150, 150"; $btnCDOk.Size = "120, 30"; $btnCDOk.BackColor = [System.Drawing.Color]::DodgerBlue; $btnCDOk.ForeColor = [System.Drawing.Color]::White; $btnCDOk.FlatStyle = "Flat"; $btnCDOk.Add_Click({ $frmCfgDone.Close() }); $pnlCDContent.Controls.Add($btnCDOk)

        if (-not $script:IsAdmin -and $nowAdminRequired -and -not $wasAdminRequired) {
            $lblCDHeader.Text = "Restart Required"
            $lblCDMsg.Text = "Configuration Saved!`n`nYou have enabled 'Always run as Administrator'. Since the app is currently running without these privileges, please close and reopen the Performance Monitor to use them."
        } else {
            $lblCDHeader.Text = "Success"
            $lblCDMsg.Text = "Configuration Saved!"
        }
        [void]$frmCfgDone.ShowDialog()
        
        $frmCfg.Close() 
    })
    $frmCfg.Add_FormClosing({ $cfgTimer.Stop(); if (-not $Script:SavedChanges) { $restoredOp = $Global:ConfigData.BackOpacity; if ($restoredOp -lt 0.01) { $restoredOp = 0.01 }; $formBack.Opacity = $restoredOp; $form.Opacity = $Global:ConfigData.ContentOpacity; if ($Global:ConfigData.PosX -ne $null) { $formBack.Location = New-Object System.Drawing.Point($Global:ConfigData.PosX, $Global:ConfigData.PosY) } else { $screen = [System.Windows.Forms.Screen]::FromControl($formBack); $x = $screen.WorkingArea.X + ($screen.WorkingArea.Width - $formBack.Width) / 2; $y = $screen.WorkingArea.Y + ($screen.WorkingArea.Height - $formBack.Height) / 2; $formBack.Location = New-Object System.Drawing.Point($x, $y) } } })
    & $UpdateBtnStates; [void]$frmCfg.ShowDialog()
}

$lblCfg.Add_Click($OpenConfig); $pnlCfg.Add_Click($OpenConfig)

# ==============================================================================
# 6. ATUALIZAÇÃO E ARRASTE
# ==============================================================================
# DEFINIDO COMO SCRIPT: PARA EVITAR ERRO NO TIMER
$script:UpdateBlock = {
    param($UiObj, $RawVal, $PercText, $BottomText, $QueueRef, $LastRef, $TargetEnabled, $EmaRef, $DemaRef1, $DemaRef2, $KamaRef) 
    
    # 1. Filtra (Se Adaptive Ligado E TARGET HABILITADO) -> Trigger removido pois agora é forçado
    $FinalVal = $RawVal
    if ($Global:ConfigData.AdaptiveEnabled -and $TargetEnabled) {
        $FinalVal = Apply-AdaptiveFilter $RawVal $QueueRef $LastRef $EmaRef $DemaRef1 $DemaRef2 $KamaRef 
    }

    # 2. Aplica Texto (Filtrada ou Raw)
    $ValForText = if ($Global:ConfigData.AdaptiveEnabled -and $Global:ConfigData.AdaptiveApplyText -and $TargetEnabled) { $FinalVal } else { $RawVal }
    $TextToUse = if ($PercText -eq "Err" -or $PercText -eq "--") { $PercText } else { "$ValForText" }
    
    if ($UiObj.LblVal.Text -ne $TextToUse) { $UiObj.LblVal.Text = $TextToUse }
    if ($UiObj.LblBottom -and $UiObj.LblBottom.Text -ne $BottomText) { $UiObj.LblBottom.Text = $BottomText }

    # 3. Aplica Barra (Filtrada ou Raw)
    $ValForBar = if ($Global:ConfigData.AdaptiveEnabled -and $Global:ConfigData.AdaptiveApplyBar -and $TargetEnabled) { $FinalVal } else { $RawVal }
    if ($ValForBar -gt 100) { $ValForBar = 100 } ; if ($ValForBar -lt 0) { $ValForBar = 0 }
    
    $targetWidth = [math]::Round(($ValForBar / 100) * $UiObj.MaxWidth)
    $currentWidth = $UiObj.Bar.Width
    if ($currentWidth -ne $targetWidth) {
        $diff = $targetWidth - $currentWidth; $absDiff = [math]::Abs($diff)
        if ($absDiff -lt 15) { $step = [math]::Truncate($diff / 10) } else { $step = [math]::Truncate($diff / 4) }
        if ($step -eq 0) { if ($diff -gt 0) { $step = 1 } else { $step = -1 } }
        $UiObj.Bar.Width = $currentWidth + $step
    }
    if ($ValForBar -ge 90) { $UiObj.Bar.BackColor = [System.Drawing.Color]::Red } elseif ($ValForBar -ge 80) { $UiObj.Bar.BackColor = [System.Drawing.Color]::Orange } else { $UiObj.Bar.BackColor = [System.Drawing.Color]::White }
}

$script:DragAction = { if ($_.Button -eq 'Left' -and -not $script:ModoFantasma) { [Win32Native]::ReleaseCapture(); [Win32Native]::SendMessage($formBack.Handle, 0xA1, 0x2, 0) | Out-Null; & $script:SyncOverlayPosition } }

# === FREQ CONTROL: DYNAMIC FRONTEND TIMER ===
# Prioridade: Adaptive (140ms) > Freq Manual > Default (40ms)
$frontendInterval = if ($Global:ConfigData.AdaptiveEnabled) {
    190 # (200ms - 10ms overhead)
} elseif ($Global:ConfigData.FreqEnabled) { 
    $Global:ConfigData.FreqValue - 10 
} else { 
    190 
}
if ($frontendInterval -lt 1) { $frontendInterval = 1 }

$timer = New-Object System.Windows.Forms.Timer; $timer.Interval = $frontendInterval
$timer.Add_Tick({
    # --- PARTE VISUAL (SÓ RODA SE A JANELA ESTIVER VISÍVEL) ---
    if (-not $Script:IsHidden) {
        # ATUALIZADO: Passa Refs do DEMA tambem
        & $script:UpdateBlock $uiCpu $SyncHash.CpuVal $SyncHash.CpuPercText $null $script:QueueCpu ([ref]$script:LastCpu) $Global:ConfigData.AdaptiveTargetCpu ([ref]$script:EmaCpu) ([ref]$script:DemaEma1Cpu) ([ref]$script:DemaEma2Cpu) ([ref]$script:KamaCpu)
        & $script:UpdateBlock $uiRam $SyncHash.RamVal $SyncHash.RamPercText $SyncHash.RamDetText $script:QueueRam ([ref]$script:LastRam) $Global:ConfigData.AdaptiveTargetRam ([ref]$script:EmaRam) ([ref]$script:DemaEma1Ram) ([ref]$script:DemaEma2Ram) ([ref]$script:KamaRam)
        & $script:UpdateBlock $uiGpu $SyncHash.GpuVal $SyncHash.GpuPercText $SyncHash.GpuTempText $script:QueueGpu ([ref]$script:LastGpu) $Global:ConfigData.AdaptiveTargetGpu ([ref]$script:EmaGpu) ([ref]$script:DemaEma1Gpu) ([ref]$script:DemaEma2Gpu) ([ref]$script:KamaGpu)
        & $script:UpdateBlock $uiVram $SyncHash.VramVal $SyncHash.VramPercText $SyncHash.VramDetText $script:QueueVram ([ref]$script:LastVram) $Global:ConfigData.AdaptiveTargetVram ([ref]$script:EmaVram) ([ref]$script:DemaEma1Vram) ([ref]$script:DemaEma2Vram) ([ref]$script:KamaVram)
        & $script:SyncOverlayPosition
    }

    # --- VERIFICAÇÃO DE HOTKEY (RODA SEMPRE, MESMO ESCONDIDO) ---
    # AGORA COM VERIFICAÇÃO DE ADMIN (Se não for admin, ignora totalmente a leitura de teclas)
    if ($Global:ConfigData.HotkeyEnabled -and $Global:ConfigData.HotkeyMode -and $script:IsAdmin) {
        $trigger = $false
        
        # Modo: Single
        if ($Global:ConfigData.HotkeyMode -eq "Single" -and $Global:ConfigData.HotkeyPrimary) {
            $state = [Win32Native]::GetAsyncKeyState($Global:ConfigData.HotkeyPrimary)
            if ($state -band 0x8000) {
                if (-not $Script:KeyLatch) { $trigger = $true; $Script:KeyLatch = $true }
            } else { $Script:KeyLatch = $false }
        }
        
        # Modo: Combo
        if ($Global:ConfigData.HotkeyMode -eq "Combo" -and $Global:ConfigData.HotkeyPrimary -and $Global:ConfigData.HotkeySecondary) {
            $s1 = [Win32Native]::GetAsyncKeyState($Global:ConfigData.HotkeyPrimary)
            $s2 = [Win32Native]::GetAsyncKeyState($Global:ConfigData.HotkeySecondary)
            if (($s1 -band 0x8000) -and ($s2 -band 0x8000)) {
                if (-not $Script:KeyLatch) { $trigger = $true; $Script:KeyLatch = $true }
            } else { $Script:KeyLatch = $false }
        }

        # Modo: Hold
        if ($Global:ConfigData.HotkeyMode -eq "Hold" -and $Global:ConfigData.HotkeyPrimary -and $Global:ConfigData.HotkeySeconds) {
            $state = [Win32Native]::GetAsyncKeyState($Global:ConfigData.HotkeyPrimary)
            if ($state -band 0x8000) {
                if (-not $Script:KeyLatch) {
                    $Script:HoldStartTime += $frontendInterval # Use dynamic interval
                    $target = [int]$Global:ConfigData.HotkeySeconds * 1000
                    if ($Script:HoldStartTime -ge $target) { $trigger = $true; $Script:KeyLatch = $true }
                }
            } else { $Script:HoldStartTime = 0; $Script:KeyLatch = $false }
        }

        # Executa Ação
        if ($trigger) { & $script:ToggleViewState }
    }
})

# ==============================================================================
# FIX: HABILITAR MINIMIZAR AO CLICAR NA BARRA DE TAREFAS
# ==============================================================================
$formBack.Add_Load({
    # Códigos Hexadecimais para estilos do Windows
    $GWL_STYLE = -16
    $WS_MINIMIZEBOX = 0x00020000
    $WS_SYSMENU = 0x00080000

    # Pega o estilo atual da janela
    $hwnd = $formBack.Handle
    $currentStyle = [Win32Native]::GetWindowLong($hwnd, $GWL_STYLE)

    # Adiciona os estilos de "Minimizar" e "Menu de Sistema" (necessário para o clique funcionar)
    # mas sem trazer a borda de volta.
    [Win32Native]::SetWindowLong($hwnd, $GWL_STYLE, ($currentStyle -bor $WS_MINIMIZEBOX -bor $WS_SYSMENU))
})

$formBack.Add_MouseDown($script:DragAction); $form.Add_MouseDown($script:DragAction)

function Add-DragToControls ($controls) { foreach ($ctrl in $controls) { $ctrl.Add_MouseDown({ if ($_.Button -eq 'Left' -and -not $script:ModoFantasma) { [Win32Native]::ReleaseCapture(); [Win32Native]::SendMessage($formBack.Handle, 0xA1, 0x2, 0) | Out-Null; & $script:SyncOverlayPosition } }); if ($ctrl.Controls.Count -gt 0) { Add-DragToControls $ctrl.Controls } } }
Add-DragToControls $form.Controls

# ==============================================================================
# FINALIZAÇÃO (LÓGICA BLINDADA)
# ==============================================================================
$formBack.Add_FormClosing({ 
    # Lógica: Clicou no X + Opção Ativada + Não é Sair Real (Menu Tray)
    if ($_.CloseReason -eq 'UserClosing' -and $Global:ConfigData.CloseToTray -and -not $script:RealExit) {
        $_.Cancel = $true  
        
        # 1. Minimiza para limpar o buffer gráfico (Remove o Fantasma Transparente)
        $formBack.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
        
        # 2. Esconde efetivamente
        $formBack.Hide()
        $form.Hide()
        
        # 3. Aviso opcional
        $notifyIcon.BalloonTipTitle = "Performance Monitor"
        $notifyIcon.BalloonTipText = "App is running in background"
        $notifyIcon.ShowBalloonTip(1000)
    } else {
        # Encerramento Total
        $SyncHash.Rodar = $false
        
        # Dá um fôlego rápido (150ms) para a thread secundária encerrar e limpar a memória antes de matar o processo
        Start-Sleep -Milliseconds 150
        
        # 1. Para o Timer Gráfico
        if ($timer) { $timer.Stop(); $timer.Dispose() }
        
        $overlay.Close()
        $form.Close()
        
        # 2. Mata o Ícone da Bandeja
        if ($notifyIcon) { 
            $notifyIcon.Visible = $false
            $notifyIcon.Dispose() 
        }
        
        # 3. Fecha a Thread Secundária corretamente
        if ($Runspace) { 
            $Runspace.Dispose() 
        }
        
        # 4. Libera a trava (Mutex)
        if ($script:AppMutex) { $script:AppMutex.Dispose() }
        
        [System.Windows.Forms.Application]::Exit() 
    }
})

$timer.Start()
[System.Windows.Forms.Application]::Run($formBack)