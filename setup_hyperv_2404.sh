#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

CURRENT_USER=${SUDO_USER:-$USER}
if pgrep -u "$CURRENT_USER" -x "xrdp-chansrv" > /dev/null; then
    echo "ABORT: Enhanced Session (XRDP) detected for user: $CURRENT_USER!"
    echo "Your Hyper-V Enhanced Session is already fully functional."
    exit 1
fi

echo "--- Starting Smart Configuration for Ubuntu 24.04 on Hyper-V ---"

echo "[1/9] Checking Packages..."
REQUIRED_PKGS="xrdp tigervnc-standalone-server tigervnc-xorg-extension linux-tools-virtual-hwe-24.04 linux-cloud-tools-virtual-hwe-24.04"
NEEDS_INSTALL=false

for pkg in $REQUIRED_PKGS; do
    if ! dpkg -l | grep -q "$pkg"; then
        echo "  -> Missing package: $pkg"
        NEEDS_INSTALL=true
    fi
done

if [ "$NEEDS_INSTALL" = true ]; then
    echo "  -> Installing missing packages..."
    apt update && apt install -y $REQUIRED_PKGS
else
    echo "  -> All packages already installed."
fi

echo "[2/9] Configuring xrdp.ini..."
INI_FILE="/etc/xrdp/xrdp.ini"

if ! grep -q "port=vsock://-1:3389" "$INI_FILE"; then
    echo "  -> Setting port to vsock..."
    sed -i -e 's/^port=3389/port=vsock:\/\/-1:3389/g' "$INI_FILE"
fi

if ! grep -q "security_layer=rdp" "$INI_FILE"; then
    echo "  -> Setting security_layer to rdp..."
    sed -i -e 's/security_layer=negotiate/security_layer=rdp/g' "$INI_FILE"
fi

if ! grep -q "crypt_level=none" "$INI_FILE"; then
    echo "  -> Setting crypt_level to none..."
    sed -i -e 's/crypt_level=high/crypt_level=none/g' "$INI_FILE"
fi

if ! grep -q "bitmap_compression=false" "$INI_FILE"; then
    echo "  -> Disabling bitmap compression..."
    sed -i -e 's/bitmap_compression=true/bitmap_compression=false/g' "$INI_FILE"
fi

if grep -q "\[Xorg\]" "$INI_FILE"; then
    echo "  -> Removing [Xorg] block to enforce TigerVNC..."
    sed -z -i -e 's/\[Xorg\].*\ncode=20\n\n\[/\[/gi' "$INI_FILE"
fi

echo "[3/9] Configuring sesman.ini..."
SESMAN_FILE="/etc/xrdp/sesman.ini"

if ! grep -q "FuseMountName=shared-drives" "$SESMAN_FILE"; then
    echo "  -> Renaming drives to shared-drives..."
    sed -i -e 's/FuseMountName=thinclient_drives/FuseMountName=shared-drives/g' "$SESMAN_FILE"
fi

if ! grep -q "param=-CompareFB" "$SESMAN_FILE"; then
    echo "  -> Configuring TigerVNC backend parameters..."
    sed -z -i -e 's/\[Xvnc\].*\nparam=96\n/\[Xvnc\]\nparam=-CompareFB\nparam=1\nparam=-ZlibLevel\nparam=0\nparam=-geometry\nparam=1920x1080\n/gi' "$SESMAN_FILE"
fi

if ! grep -q "UserWindowManager=startubuntu" "$SESMAN_FILE"; then
    echo "  -> Pointing window manager to startubuntu.sh..."
    sed -i -e 's/startwm/startubuntu/g' "$SESMAN_FILE"
fi

echo "[4/9] Checking startup script..."
START_SCRIPT="/etc/xrdp/startubuntu.sh"
EXPECTED_SCRIPT="#!/bin/sh
export GNOME_SHELL_SESSION_MODE=ubuntu
export XDG_CURRENT_DESKTOP=ubuntu:GNOME
exec /etc/xrdp/startwm.sh"

if [ ! -f "$START_SCRIPT" ] || [ "$(cat "$START_SCRIPT")" != "$EXPECTED_SCRIPT" ]; then
    echo "  -> Creating/Updating startubuntu.sh..."
    echo "$EXPECTED_SCRIPT" > "$START_SCRIPT"
    chmod a+x "$START_SCRIPT"
else
    echo "  -> Startup script verified."
fi

echo "[5/9] Checking PAM configuration..."
PAM_FILE="/etc/pam.d/xrdp-sesman"
if ! grep -q "auth required pam_env.so readenv=1" "$PAM_FILE"; then
    echo "  -> Applying PAM fix for keyring..."
    cat > "$PAM_FILE" <<'EOF'
#%PAM-1.0
auth required pam_env.so readenv=1
auth required pam_env.so readenv=1 envfile=/etc/default/locale
@include common-auth
-auth optional pam_gnome_keyring.so
-auth optional pam_kwallet5.so
@include common-account
@include common-password
session required pam_limits.so
session required pam_loginuid.so
session optional pam_lastlog.so quiet
@include common-session
-session optional pam_gnome_keyring.so auto_start
-session optional pam_kwallet5.so auto_start
EOF
else
    echo "  -> PAM configuration verified."
fi

echo "[6/9] Checking Kernel Modules..."
if ! grep -q "blacklist vmw_vsock_vmci_transport" /etc/modprobe.d/blacklist-vmw_vsock_vmci_transport.conf 2>/dev/null; then
    echo "  -> Blacklisting VMW module..."
    echo "blacklist vmw_vsock_vmci_transport" > /etc/modprobe.d/blacklist-vmw_vsock_vmci_transport.conf
fi

if ! grep -q "hv_sock" /etc/modules-load.d/hv_sock.conf 2>/dev/null; then
    echo "  -> Loading hv_sock module..."
    echo "hv_sock" > /etc/modules-load.d/hv_sock.conf
fi

echo "[7/9] Checking KVP Daemon paths..."
mkdir -p /usr/libexec/hypervkvpd/
if [ ! -L "/usr/libexec/hypervkvpd/hv_get_dhcp_info" ]; then
    echo "  -> Creating DHCP info symlink..."
    ln -s /usr/sbin/hv_get_dhcp_info /usr/libexec/hypervkvpd/hv_get_dhcp_info
fi
if [ ! -L "/usr/libexec/hypervkvpd/hv_get_dns_info" ]; then
    echo "  -> Creating DNS info symlink..."
    ln -s /usr/sbin/hv_get_dns_info /usr/libexec/hypervkvpd/hv_get_dns_info
fi

echo "[8/9] Checking Xwrapper config..."
if ! grep -q "allowed_users=anybody" /etc/X11/Xwrapper.config; then
    echo "  -> Allowing anybody to start X..."
    sed -i -e 's/allowed_users=console/allowed_users=anybody/g' /etc/X11/Xwrapper.config
fi

echo "[9/9] Restarting services..."
systemctl daemon-reload
systemctl enable xrdp
systemctl restart xrdp

echo "--- Configuration Complete ---"
echo "If this is a fresh install or kernel modules were changed, please POWER OFF the VM completely and start it again."
