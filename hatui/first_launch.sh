cat > ~/hatui/first_launch.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${SUDO_USER:-$USER}"
HOME_DIR="/home/${USER_NAME}"
VENV_PY="${HOME_DIR}/hatui/venv/bin/python"
APP_MAIN="${HOME_DIR}/hatui/app/main.py"
SERVICE="/etc/systemd/system/hatui-wayland.service"

if [ ! -x "${VENV_PY}" ]; then
  echo "ERROR: venv python not found: ${VENV_PY}"
  exit 1
fi

if [ ! -f "${APP_MAIN}" ]; then
  echo "ERROR: app main.py not found: ${APP_MAIN}"
  exit 1
fi

if [ ! -f "${SERVICE}" ]; then
  echo "ERROR: service file not found: ${SERVICE}"
  exit 1
fi

echo "Updating service ExecStart to launch dashboard..."
sudo sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/dbus-run-session /usr/bin/cage -s -- /usr/bin/foot -e ${VENV_PY} ${APP_MAIN}|" "${SERVICE}"

echo "Ensuring WorkingDirectory is set..."
sudo bash -c "grep -q '^WorkingDirectory=' '${SERVICE}' || sed -i '/^\[Service\]/a WorkingDirectory=${HOME_DIR}/hatui/app' '${SERVICE}'"

echo "Reloading systemd and restarting service..."
sudo systemctl daemon-reload
sudo systemctl restart hatui-wayland.service

echo "Done. If you need logs:"
echo "  sudo journalctl -u hatui-wayland.service -b --no-pager | tail -200"
EOF

chmod +x ~/hatui/first_launch.sh
