#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

echo "[tools] Instalando CLIs en $BIN_DIR"

if ! command -v istioctl >/dev/null 2>&1; then
  echo "[tools] Descargando istioctl..."
  ISTIO_VERSION="1.22.3"
  INSTALL_DIR="/tmp/istio-install"
  mkdir -p "$INSTALL_DIR"
  curl -L "https://istio.io/downloadIstio" -o "$INSTALL_DIR/downloadIstio.sh"
  chmod +x "$INSTALL_DIR/downloadIstio.sh"
  (
    cd "$INSTALL_DIR"
    ISTIO_VERSION="$ISTIO_VERSION" TARGET_ARCH=x86_64 ./downloadIstio.sh >/dev/null
  )
  ISTIOCTL_PATH="$(find "$INSTALL_DIR" -type f -path '*/bin/istioctl' | head -n 1 || true)"
  if [[ -z "$ISTIOCTL_PATH" ]]; then
    echo "[tools] ERROR: no se encontro binario istioctl descargado"
    exit 1
  fi
  cp "$ISTIOCTL_PATH" "$BIN_DIR/istioctl"
fi

if ! command -v linkerd >/dev/null 2>&1; then
  echo "[tools] Descargando linkerd CLI..."
  LINKERD_VERSION="stable-2.14.10"
  curl -sL https://run.linkerd.io/install | LINKERD2_VERSION="$LINKERD_VERSION" sh
  cp "$HOME/.linkerd2/bin/linkerd" "$BIN_DIR/linkerd"
fi

echo "[tools] Versiones instaladas:"
"$BIN_DIR/istioctl" version --remote=false || true
"$BIN_DIR/linkerd" version --client || true

echo "[tools] Agrega esto a tu shell si hace falta: export PATH=\"$BIN_DIR:\$PATH\""
