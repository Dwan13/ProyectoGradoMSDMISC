#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ok() { echo "[OK] $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[ERROR] $*"; exit 1; }

MISSING_CMDS=()

need_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "Comando disponible: $cmd"
  else
    warn "No se encontro comando requerido: $cmd"
    MISSING_CMDS+=("$cmd")
  fi
}

echo "== Precheck Cero Absoluto =="
echo "Repo: $ROOT_DIR"

need_cmd python3
need_cmd pip3
need_cmd docker
need_cmd microk8s
need_cmd k6
need_cmd jq
need_cmd curl

if [[ ${#MISSING_CMDS[@]} -gt 0 ]]; then
  echo
  echo "Faltan comandos requeridos: ${MISSING_CMDS[*]}"
  echo "Instalacion sugerida (Ubuntu/Debian):"
  echo "  sudo apt update && sudo apt install -y jq curl python3 python3-pip docker.io"
  echo "  # k6 y microk8s requieren pasos dedicados del protocolo"
  exit 1
fi

python3 --version || fail "python3 no responde"
pip3 --version || fail "pip3 no responde"
docker --version || fail "docker no responde"
k6 version || fail "k6 no responde"

microk8s status --wait-ready >/dev/null 2>&1 || fail "MicroK8s no esta listo"
ok "MicroK8s listo"

if microk8s kubectl version --client=true >/dev/null 2>&1; then
  ok "microk8s kubectl operativo"
else
  fail "microk8s kubectl no operativo"
fi

if [[ -f "$ROOT_DIR/requirements.txt" ]]; then
  ok "requirements.txt encontrado"
else
  fail "No se encontro requirements.txt en raiz"
fi

if [[ -x "$ROOT_DIR/scripts/deploy_microk8s.sh" ]]; then
  ok "deploy script ejecutable"
else
  warn "scripts/deploy_microk8s.sh no es ejecutable, corrigiendo permiso..."
  chmod +x "$ROOT_DIR/scripts/deploy_microk8s.sh"
  ok "permiso corregido"
fi

if [[ -d "$ROOT_DIR/RealisticServices" ]]; then
  ok "RealisticServices presente"
else
  fail "No se encontro carpeta RealisticServices"
fi

echo
echo "Precheck completado sin errores fatales."
