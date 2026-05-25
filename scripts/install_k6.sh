#!/bin/bash
# ================================================================
# k6 Installation Script for MuBench
# ================================================================

set -euo pipefail

GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

log() { echo -e "${CYAN}[k6]${RESET} $*"; }
success() { echo -e "${GREEN}✅ $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠️ $*${RESET}"; }
error() { echo -e "${RED}❌ $*${RESET}" >&2; exit 1; }

# Check if k6 is already installed
if command -v k6 >/dev/null 2>&1; then
    success "k6 ya está instalado"
    k6 version
    exit 0
fi

log "Instalando k6..."

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    log "Detectado Linux, instalando desde repositorio APT..."
    
    # Import GPG key
    sudo gpg -k >/dev/null 2>&1 || error "gpg no encontrado. Instalar con: sudo apt-get install gnupg"
    
    sudo gpg --no-default-keyring \
        --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
        --keyserver hkp://keyserver.ubuntu.com:80 \
        --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 2>/dev/null || warn "GPG key already exists"
    
    # Add repository
    echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
        sudo tee /etc/apt/sources.list.d/k6.list >/dev/null
    
    # Update and install
    sudo apt-get update -qq
    sudo apt-get install -y k6
    
    success "k6 instalado correctamente"
    k6 version
    
elif [[ "$OSTYPE" == "darwin"* ]]; then
    log "Detectado macOS, instalando con Homebrew..."
    
    if ! command -v brew >/dev/null 2>&1; then
        error "Homebrew no encontrado. Instalar desde: https://brew.sh"
    fi
    
    brew install k6
    success "k6 instalado correctamente"
    k6 version
    
else
    error "Sistema operativo no soportado: $OSTYPE\n\nInstalación manual: https://k6.io/docs/get-started/installation/"
fi

log "Verificando instalación..."
k6 version || error "Error al verificar instalación de k6"

success "¡Instalación completada!"
echo ""
echo "Siguiente paso: Ejecutar la campaña CRUD"
echo "  bash scripts/run-crud-experiment.sh"
echo ""
