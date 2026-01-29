#!/usr/bin/env bash
set -e

USER_NAME="${SUDO_USER:-$USER}"

echo "=== HATUI kiosk setup for user: $USER_NAME ==="

echo "Updating system..."
apt update && apt full-upgrade -y

echo "Installing packages..."
apt install -y \
  cage \
  foot \
  seatd \
  dbus-user-session \
  fonts-terminus \
  htop \
  python3-pip \
  wget

echo "Enabling seatd..."
systemctl enable --now seatd

echo "Adding user to required groups..."
usermod -aG video,input,render,tty "$USER_NAME"

echo "Creating foot config..."
mkdir -p "/home/$USER_NAME/.config/foot"

cat > "/home/$USER_NAME/.config/foot/foot.ini" <<'EOF'
[main]
font=Terminus:size=14
dpi-aware=yes

[colors]
background=000000
foreground=ffb000
EOF

chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config"

echo "Creating Wayland kiosk service..."

cat > /etc/systemd/system/hatui-wayland.service <<EOF
[Unit]
Description=HATUI Wayland Terminal
After=seatd.service systemd-logind.service
Wants=seatd.service

[Service]
User=$USER_NAME
SupplementaryGroups=video input render tty

RuntimeDirectory=hatui
RuntimeDirectoryMode=0700
Environment=XDG_RUNTIME_DIR=/run/hatui
Environment=LIBSEAT_BACKEND=seatd

Environment=XCURSOR_PATH=/usr/share/icons
Environment=XCURSOR_THEME=Adwaita
Environment=WLR_CURSOR_THEME=Adwaita
Environment=WLR_NO_HARDWARE_CURSORS=1

StandardInput=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes

ExecStart=/usr/bin/dbus-run-session /usr/bin/cage -s -- /usr/bin/foot
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF

echo "Disabling console login..."
systemctl disable getty@tty1.service

echo "Installing transparent cursor..."
wget -O /usr/share/icons/transparent.cursor \
https://github.com/celly/transparent-xcursor/raw/refs/heads/master/transparent
chmod 644 /usr/share/icons/transparent.cursor

echo "Neutralising Adwaita cursors..."
CURDIR="/usr/share/icons/Adwaita/cursors"
cp -f /usr/share/icons/transparent.cursor "$CURDIR/transparent"

for f in "$CURDIR"/*; do
  b="$(basename "$f")"
  [ "$b" = "transparent" ] && continue
  ln -sf transparent "$CURDIR/$b"
done

echo "Enabling kiosk service..."
systemctl daemon-reload
systemctl enable hatui-wayland.service

echo "================================================"
echo "Setup complete. Reboot to enter kiosk terminal."
echo "================================================"
