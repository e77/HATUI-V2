#!/usr/bin/env bash
set -euo pipefail

# HATUI Step 3: Install the app scaffold (modular panels + YAML) and Python venv.
# Run: bash install.sh
# Assumes: prerequisites.sh already ran (cage/foot/seatd service etc).

USER_NAME="${SUDO_USER:-$USER}"
HOME_DIR="/home/${USER_NAME}"
BASE_DIR="${HOME_DIR}/hatui"
APP_DIR="${BASE_DIR}/app"
VENV_DIR="${BASE_DIR}/venv"

echo "=== HATUI install.sh (Step 3) for user: ${USER_NAME} ==="

# 1) Create directories
mkdir -p "${APP_DIR}/core"
mkdir -p "${APP_DIR}/panels/left" "${APP_DIR}/panels/center" "${APP_DIR}/panels/right"

# 2) Create venv (PEP 668 safe) + install Python deps
sudo apt update
sudo apt install -y python3-venv python3-full

if [ ! -d "${VENV_DIR}" ]; then
  python3 -m venv "${VENV_DIR}"
fi

"${VENV_DIR}/bin/pip" install --upgrade pip
"${VENV_DIR}/bin/pip" install textual pyyaml rich

# 3) Write core modules (ASCII only)

cat > "${APP_DIR}/core/panel_base.py" <<'EOF'
from __future__ import annotations
from textual.widget import Widget

class Panel(Widget):
    """Base class for panels. Each panel can render itself and receives config from YAML."""
    panel_id: str = ""
    title: str = ""
    config: dict = {}

    def apply_config(self, panel_id: str, title: str, config: dict) -> None:
        self.panel_id = panel_id
        self.title = title
        self.config = config
EOF

cat > "${APP_DIR}/core/loader.py" <<'EOF'
from __future__ import annotations

import importlib
from pathlib import Path
from typing import Any, Dict, List

import yaml

def load_panel_specs(panels_root: Path) -> List[Dict[str, Any]]:
    specs: List[Dict[str, Any]] = []
    for yaml_path in sorted(panels_root.rglob("panel.yaml")):
        spec = yaml.safe_load(yaml_path.read_text()) or {}
        spec["_yaml_path"] = str(yaml_path)
        specs.append(spec)
    return specs

def group_by_slot(specs: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    slots: Dict[str, List[Dict[str, Any]]] = {}
    for s in specs:
        slots.setdefault(s.get("slot", "left"), []).append(s)
    return slots

def instantiate_panel(spec: Dict[str, Any]):
    module_name = spec["module"]
    cls_name = spec["class"]

    mod = importlib.import_module(module_name)
    cls = getattr(mod, cls_name)

    panel = cls()
    panel.apply_config(
        spec["id"],
        spec.get("title", spec["id"]),
        spec.get("config", {}),
    )
    return panel
EOF

# 4) Write main shell (header + 3 columns + footer), ASCII only

cat > "${APP_DIR}/main.py" <<'EOF'
# -*- coding: utf-8 -*-
from __future__ import annotations

from pathlib import Path

from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal
from textual.widgets import Static

from core.loader import load_panel_specs, instantiate_panel, group_by_slot

APP_ROOT = Path(__file__).resolve().parent
PANELS_ROOT = APP_ROOT / "panels"


class HeaderBar(Static):
    DEFAULT_CSS = """
    HeaderBar {
        height: 3;
        padding: 0 1;
        content-align: left middle;
        border: round $accent;
    }
    """
    def on_mount(self) -> None:
        self.update("HATUI  |  Home Assistant Dashboard  |  service mode")


class FooterBar(Static):
    DEFAULT_CSS = """
    FooterBar {
        height: 3;
        padding: 0 1;
        content-align: left middle;
        border: round $accent;
    }
    """
    def on_mount(self) -> None:
        self.update("F1 Help  |  R Reload panels  |  Q Quit")


class Slot(Container):
    pass


class HatuiApp(App):
    CSS = """
    Screen {
        background: black;
        color: #ffb000;
    }

    #root {
        height: 100%;
        width: 100%;
        padding: 0 0;
    }

    #body {
        height: 1fr;
        padding: 0 0;
    }

    Slot {
        border: round #ffb000;
        padding: 0 1;
        margin: 0 0;
    }

    /* Tweak these ratios once you upload the ruler photo / exact widths */
    #slot-left   { width: 1fr; }
    #slot-center { width: 1fr; }
    #slot-right  { width: 1fr; }

    .panel-title {
        height: 1;
        content-align: left middle;
        text-style: bold;
    }
    """

    BINDINGS = [
        ("r", "reload_panels", "Reload panels"),
        ("q", "quit", "Quit"),
    ]

    def compose(self) -> ComposeResult:
        yield Container(
            HeaderBar(id="header"),
            Horizontal(
                Slot(id="slot-left"),
                Slot(id="slot-center"),
                Slot(id="slot-right"),
                id="body",
            ),
            FooterBar(id="footer"),
            id="root",
        )

    def on_mount(self) -> None:
        self.load_and_mount_panels()

    def action_reload_panels(self) -> None:
        self.load_and_mount_panels()

    def load_and_mount_panels(self) -> None:
        for slot_id in ("slot-left", "slot-center", "slot-right"):
            slot = self.query_one(f"#{slot_id}", Slot)
            slot.remove_children()

        specs = load_panel_specs(PANELS_ROOT)
        slots = group_by_slot(specs)

        for slot_name, slot_id in (("left", "slot-left"), ("center", "slot-center"), ("right", "slot-right")):
            slot = self.query_one(f"#{slot_id}", Slot)
            for spec in slots.get(slot_name, []):
                panel = instantiate_panel(spec)
                slot.mount(panel)


if __name__ == "__main__":
    HatuiApp().run()
EOF

# 5) Write panels (each has panel.yaml + panel.py), ASCII only

cat > "${APP_DIR}/panels/left/panel.yaml" <<'EOF'
id: left
slot: left
title: Left Panel
module: panels.left.panel
class: LeftPanel
config:
  lines:
    - "Left: status overview"
    - "Later: HA entities"
EOF

cat > "${APP_DIR}/panels/left/panel.py" <<'EOF'
from __future__ import annotations

from textual.app import ComposeResult
from textual.widgets import Static

from core.panel_base import Panel


class LeftPanel(Panel):
    DEFAULT_CSS = """
    LeftPanel { height: 100%; }
    """

    def compose(self) -> ComposeResult:
        yield Static(self.title, classes="panel-title")
        for line in self.config.get("lines", []):
            yield Static(f"- {line}")
EOF

cat > "${APP_DIR}/panels/center/panel.yaml" <<'EOF'
id: center
slot: center
title: Center Panel
module: panels.center.panel
class: CenterPanel
config:
  lines:
    - "Center: timeline placeholder"
    - "Later: 24h on/off bars"
EOF

cat > "${APP_DIR}/panels/center/panel.py" <<'EOF'
from __future__ import annotations

from textual.app import ComposeResult
from textual.widgets import Static

from core.panel_base import Panel


class CenterPanel(Panel):
    DEFAULT_CSS = """
    CenterPanel { height: 100%; }
    """

    def compose(self) -> ComposeResult:
        yield Static(self.title, classes="panel-title")
        for line in self.config.get("lines", []):
            yield Static(f"- {line}")
        yield Static("")
        yield Static("######......................  24h timeline placeholder")
EOF

cat > "${APP_DIR}/panels/right/panel.yaml" <<'EOF'
id: right
slot: right
title: Right Panel
module: panels.right.panel
class: RightPanel
config:
  lines:
    - "Right: alerts"
    - "Later: warnings/errors"
EOF

cat > "${APP_DIR}/panels/right/panel.py" <<'EOF'
from __future__ import annotations

from textual.app import ComposeResult
from textual.widgets import Static

from core.panel_base import Panel


class RightPanel(Panel):
    DEFAULT_CSS = """
    RightPanel { height: 100%; }
    """

    def compose(self) -> ComposeResult:
        yield Static(self.title, classes="panel-title")
        for line in self.config.get("lines", []):
            yield Static(f"- {line}")
EOF

# 6) Add __init__.py to make imports boring/reliable
touch "${APP_DIR}/core/__init__.py"
touch "${APP_DIR}/panels/__init__.py"
touch "${APP_DIR}/panels/left/__init__.py"
touch "${APP_DIR}/panels/center/__init__.py"
touch "${APP_DIR}/panels/right/__init__.py"

# 7) Clean stale pycache (just in case)
find "${APP_DIR}" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true

# 8) Ownership
chown -R "${USER_NAME}:${USER_NAME}" "${BASE_DIR}"

echo "=== Done. Run the app with: ==="
echo "cd ${APP_DIR} && ${VENV_DIR}/bin/python main.py"
echo ""
echo "Tip: if you want it to run under the kiosk service next, we will update hatui-wayland.service ExecStart"
echo "to call: ${VENV_DIR}/bin/python ${APP_DIR}/main.py"
