# Ubuntu 24.04 Hyper-V Enhanced Session Setup

An automated, idempotent script to get Hyper-V Enhanced Session (XRDP) working on Ubuntu 24.04. 

## The Problem
Setting up Enhanced Session on Ubuntu 24.04 is currently broken out-of-the-box using older methods. Recent Ubuntu updates introduced a performance regression with the default Xorg backend over XRDP, leading to hours upon hours of troubleshooting because the methods out there just aren't covering everything. There is way too much guesswork and they are prone to several errors along the way. I took it upon myself to find a workable solution for the latest `Ubuntu Desktop 24.04.4 LTS` release.

## The Solution
This script automates the necessary workarounds. It abandons the broken Xorg backend entirely and forces the system to use TigerVNC (`tigervnc-standalone-server`). It also injects the correct PAM configuration to allow the GNOME keyring to unlock properly.

### Key Script Features
* **Idempotent Execution:** The script checks if configurations are already applied before modifying files. It is safe to re-run if you think something broke.
* **Active Session Guardrail:** If you accidentally run this script while actively connected via an Enhanced Session, it will detect the `xrdp-chansrv` process and abort. Restarting XRDP while inside it causes a "zombie" session lock, so the script prevents you from nuking your own desktop.

## Prerequisites
1.  A **Generation 2** Hyper-V Virtual Machine.
2.  Installed from the vanilla Canonical Ubuntu Desktop 24.04 ISO.
3.  During Ubuntu installation, **Require my password to log in** MUST be checked. XRDP will not work with auto-login.
4.  Your Hyper-V host must have Enhanced Session Mode allowed in its settings. You can enable this via an Admin PowerShell on Windows:
    ```powershell
    Set-VMHost -EnableEnhancedSessionMode $true
    Set-VM -VMName "Your_VM_Name" -EnhancedSessionTransportType HvSocket
    ```

## Usage
**CRITICAL:** You must run it from the Basic Session console or via SSH.

1. Boot your VM and log in using the Basic Session (the standard Hyper-V window).
2. Open your terminal and run the one-line install command:
    ```bash
    wget -qO- https://raw.githubusercontent.com/Arelius-D/ubuntu-24.04-hyperv-enhanced-session/main/setup_hyperv_2404.sh | sudo bash
    ```
    *(Alternatively, you can manually download `setup_hyperv_2404.sh`, make it executable with `chmod +x`, and run it with `sudo ./setup_hyperv_2404.sh`)*
3. **Cold Boot:** Once the script completes, a simple reboot is not enough for the new kernel modules (`hv_sock`) to initialize correctly. You must completely power off the VM:
    ```bash
    sudo poweroff
    ```
4. Start the VM again from Hyper-V Manager. You should now be prompted with the Enhanced Session resolution slider. If you don't get this behavior, simply press the icon from the top menu bar in the VM main window. Log in using the `Xvnc` session drop-down, followed by your username and password.

## Current Limitations / TODO
* **Audio:** This script currently focuses on getting a stable, high-performance video and clipboard session running. It does not compile `pulseaudio-module-xrdp` for sound redirection.
* **Polkit Color Manager:** You may occasionally see a prompt asking for authentication to "create a color managed device" upon login. This is a known harmless quirk that can be dismissed. (Has never happened to me, but worth mentioning).
