# Performance Monitor

A lightweight, highly customizable performance monitor for Windows, developed entirely in **PowerShell** with integrated **C#** native code to achieve maximum efficiency and low latency.

Performance Monitor is a **Portable** software. It requires no installation and does not alter your system registry.

## 📸 Screenshots

**Main Window Transparency Examples**

![Main Window Transparency Examples](Transparency%20Examples.jpeg)

**Adjustment & Settings Windows**

![Settings Windows](Adjustment%20%26%20Settings.jpg)

**Compact Mode (No NVIDIA GPU)**

![Compact Mode (No NVIDIA GPU)](Compact%20Mode.png)

## 🚀 Key Features

* **Hybrid Monitoring Engine:** Uses C# code injected at runtime to access native APIs (PDH for CPU, Kernel32 for RAM, and NVML for GPU), ensuring precise readings with minimal processor impact.
* **Opacity Adjustment:** Allows independent control of the transparency for both the window background and the content elements, enabling aesthetic personalization according to user needs.
* **Adaptive Sampling (Discrete Window Sampling):** Features an advanced internal engine that captures multiple rapid hardware samples per UI update cycle. It offers 4 distinct mathematical filters—*Trimmed Mean (Lower Focus)*, *Trimmed Mean (Upper Focus)*, *Max Pooling*, and *Standard Average*—allowing users to perfectly tailor the data processing for smooth stability, sustained load tracking, or raw bottleneck detection.
* **Dynamic UI Layout:** The interface automatically detects the presence of an NVIDIA GPU and seamlessly adjusts its layout, shrinking into a minimalist compact mode (CPU & RAM only) on unsupported hardware.
* **Frequency Adjustment:** Allows the user to manually define the frequency for hardware statistics collection.
* **Window Position:** Enables the user to memorize the current window position on the screen and set it as the default for future launches.
* **Smart Hotkey System:** Supports global shortcuts in three modes: *Single Press*, *Hold Button*, and *Combo*.
* **Startup Options:** Offers full control over how the program starts, allowing it to open directly in Overlay Mode (locked), start hidden in the system tray, or run automatically with Administrator privileges.
* **Windows Auto-start:** Provides an option to configure Performance Monitor to start automatically upon Windows logon, avoiding UAC prompts.
* **Minimize to Tray:** Features options to change the behavior of the minimize and close buttons, allowing the application to be sent to the System Tray.
* **Overlay Mode:** Through the *Lock* button, the window becomes click-through, allowing you to interact with games or programs behind the monitor without mouse command interference.

## 📦 How to Use

### For Common Users (Recommended)
1. Go to the **[Releases]** tab on the right side of this page.
2. Download the latest ZIP file (e.g., `PerformanceMonitor_v1.0_EXE.zip`).
3. Extract the folder anywhere on your computer and run `Performance Monitor.exe`.

> ⚠️ **Important Notice (DPI Scaling):** If you use Windows scaling above 100% (e.g., 125%, 150%), **do not delete** the `Performance Monitor.exe.config` file. It is essential for informing Windows that the program is *DPI Aware*, ensuring the interface remains sharp and correctly sized without blurriness or cuts.

### For Developers (Source Code)
1. Download the `PerformanceMonitor_v1.0.ps1` file.
2. The script can be executed directly via PowerShell or compiled into an executable using the **ps2exe** module.
3. To compile with the same scaling protection and behavior as the official release, use the following command:
   `ps2exe .\PerformanceMonitor_v1.0.ps1 -NoConsole -STA -SupportOS -DPIAware`

## 🛠️ Technical Requirements

* **Operating System:** Windows 10 or 11.
* **Dependencies:** PowerShell 5.1 or higher.
* **Hardware (Optional):** GPU monitoring requires NVIDIA drivers with `nvml.dll` support.

---
**Developed by:** Fabiopsyduck
