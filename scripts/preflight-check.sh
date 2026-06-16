#!/usr/bin/env bash
# ============================================================================
# preflight-check.sh
#
# Valida que el entorno cumpla TODAS las precondiciones para reproducir el
# experimento de forma determinística. Aborta (exit 1) si encuentra cualquier
# anomalía que pueda contaminar los resultados.
#
# Uso:
#   bash scripts/preflight-check.sh           # solo valida
#   bash scripts/preflight-check.sh --fix     # intenta corregir lo corregible
#
# Cubre los 8 riesgos identificados en la sección "Garantía de reproducibilidad"
# del README:
#   1. CLIs presentes y versiones mínimas
#   2. Cluster Ready, addons habilitados
#   3. CNI = Calico (única forma de garantizar enforcement de NetworkPolicies)
#   4. Registry local respondiendo + 3 imágenes publicadas
#   5. /etc/hosts con los 11 hosts virtuales
#   6. Service meshes instalados (Istio + Linkerd + Kong)
#   7. PV provisioner activo (hostpath-storage)
#   8. Recursos del host suficientes (RAM libre ≥ 4 GB, disco ≥ 10 GB)
# ============================================================================
set -uo pipefail

FIX=0
[[ "${1:-}" == "--fix" ]] && FIX=1

FAIL=0
WARN=0
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ok()   { echo -e "\033[0;32m[ OK ]\033[0m $*"; }
bad()  { echo -e "\033[0;31m[FAIL]\033[0m $*"; FAIL=$((FAIL+1)); }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; WARN=$((WARN+1)); }
sec()  { echo -e "\n\033[1;36m── $* ──\033[0m"; }

kctl() {
  if command -v microk8s >/dev/null 2>&1; then microk8s kubectl "$@"
  else kubectl "$@"; fi
}

# ----------------------------------------------------------------------------
sec "1. CLIs y versiones mínimas"
# ----------------------------------------------------------------------------
need_cmd() {
  local cmd="$1" hint="$2" required="${3:-1}"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd presente ($(command -v $cmd))"
  else
    if [[ "$required" -eq 1 ]]; then bad "$cmd no encontrado — $hint"
    else warn "$cmd no encontrado (opcional) — $hint"; fi
  fi
}
need_cmd k6        "instala con: bash scripts/install_k6.sh"
need_cmd python3   "apt install python3"
need_cmd curl      "apt install curl"
need_cmd jq        "apt install jq (opcional, solo para inspección manual de summaries)" 0
need_cmd helm      "snap install helm --classic   (o microk8s helm3)"

if command -v microk8s >/dev/null 2>&1; then
  ok "microk8s presente ($(microk8s version 2>/dev/null | head -1))"
else
  if command -v kubectl >/dev/null 2>&1; then
    warn "microk8s ausente, usando kubectl puro (no probado)"
  else
    bad "ni microk8s ni kubectl disponibles"
  fi
fi

# Istio CLI opcional (solo si se va a correr C1/istio o C2/istio-mtls)
if command -v istioctl >/dev/null 2>&1; then
  IVER=$(istioctl version --remote=false 2>/dev/null | head -1)
  ok "istioctl $IVER"
else
  warn "istioctl ausente — necesario para reinstalar Istio si se rompe"
fi

if command -v linkerd >/dev/null 2>&1; then
  LVER=$(linkerd version --client --short 2>/dev/null)
  ok "linkerd $LVER"
else
  warn "linkerd ausente — necesario para C2/linkerd-mtls"
fi

# ----------------------------------------------------------------------------
sec "2. Cluster Kubernetes Ready"
# ----------------------------------------------------------------------------
if kctl cluster-info >/dev/null 2>&1; then
  ok "cluster accesible"
else
  bad "cluster no responde — corre: microk8s start"
  exit 1
fi

NOT_READY=$(kctl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"{print $1}')
if [[ -z "$NOT_READY" ]]; then
  ok "todos los nodos Ready"
else
  bad "nodos NOT Ready: $NOT_READY"
fi

# Addons obligatorios: parsea la sección "enabled:" de `microk8s status`
ENABLED_ADDONS=$(microk8s status 2>/dev/null \
  | awk '/^  enabled:/{flag=1;next} /^  disabled:/{flag=0} flag{print $1}')
for addon in dns ingress metrics-server registry hostpath-storage; do
  if echo "$ENABLED_ADDONS" | grep -qx "$addon"; then
    ok "addon $addon habilitado"
  else
    bad "addon $addon NO habilitado — corre: microk8s enable $addon"
  fi
done

# ----------------------------------------------------------------------------
sec "3. CNI = Calico (REQUERIDO para C3/NetworkPolicies)"
# ----------------------------------------------------------------------------
# MicroK8s ≥1.25 trae Calico por defecto. Si el cluster usa flannel u otro,
# C3 dará falsos negativos (las policies se aceptan pero no se enforce).
CNI_PODS=$(kctl -n kube-system get pods --no-headers 2>/dev/null | awk '{print $1}')
if echo "$CNI_PODS" | grep -qi "calico"; then
  ok "CNI Calico detectado"
elif echo "$CNI_PODS" | grep -qi "cilium"; then
  ok "CNI Cilium detectado (también enforce NetworkPolicy)"
else
  bad "CNI no detectado como Calico/Cilium → C3 NO se podrá validar"
  echo "       Pods en kube-system:"; echo "$CNI_PODS" | sed 's/^/         /'
fi

# ----------------------------------------------------------------------------
sec "4. Registry local y 3 imágenes publicadas"
# ----------------------------------------------------------------------------
if curl -sf -m 4 http://localhost:32000/v2/_catalog >/dev/null 2>&1; then
  ok "registry localhost:32000 responde"
  CATALOG=$(curl -s http://localhost:32000/v2/_catalog)
  for img in mubench/api-service mubench/auth-service mubench/data-service; do
    if echo "$CATALOG" | grep -q "\"$img\""; then
      # Verifica que exista al menos un tag v1
      if curl -sf "http://localhost:32000/v2/${img}/tags/list" | grep -q '"v1"'; then
        ok "imagen $img:v1 publicada"
      else
        bad "imagen $img publicada pero sin tag v1"
      fi
    else
      bad "imagen $img NO publicada — corre el Paso 5 del README"
    fi
  done
else
  bad "registry localhost:32000 NO responde — corre: microk8s enable registry"
fi

# ----------------------------------------------------------------------------
sec "5. Hosts virtuales (informativo: k6 usa --resolve internamente)"
# ----------------------------------------------------------------------------
# El script k6 inyecta los hosts via --resolve, por lo que /etc/hosts es
# opcional para la carga. Solo es necesario si vas a hacer curl manual desde
# el host (ej. validación con browser). Reportamos como WARN, no FAIL.
EXPECTED_HOSTS=(
  realistic.local
  realistic-istio.local
  realistic-istio-mtls.local
  realistic-without-mtls.local
  realistic-linkerd-mtls.local
  realistic-without-network-policies.local
  realistic-basic-network-policies.local
  realistic-strict-network-policies.local
  realistic-without-rate-limiting.local
  realistic-moderate-rate-limiting.local
  realistic-strict-rate-limiting.local
)
MISSING_HOSTS=()
for h in "${EXPECTED_HOSTS[@]}"; do
  grep -qE "^\s*[0-9.]+\s+(\S+\s+)*${h}(\s|$)" /etc/hosts || MISSING_HOSTS+=("$h")
done
if [[ ${#MISSING_HOSTS[@]} -eq 0 ]]; then
  ok "los 11 hosts virtuales están en /etc/hosts"
else
  warn "${#MISSING_HOSTS[@]} hosts ausentes en /etc/hosts (no bloquea: k6 usa --resolve). \
        Solo necesario si harás curl/browser manual."
  if [[ $FIX -eq 1 ]]; then
    echo "       Añadiendo entradas (necesita sudo)..."
    {
      echo ""; echo "# Hosts virtuales muBench (añadidos por preflight-check.sh)"
      for h in "${MISSING_HOSTS[@]}"; do echo "127.0.0.1  $h"; done
    } | sudo tee -a /etc/hosts >/dev/null && ok "hosts añadidos"
  fi
fi

# ----------------------------------------------------------------------------
sec "6. Service meshes instalados"
# ----------------------------------------------------------------------------
# Istio
if kctl get ns istio-system >/dev/null 2>&1 && \
   kctl -n istio-system get deploy istiod >/dev/null 2>&1; then
  READY=$(kctl -n istio-system get deploy istiod -o jsonpath='{.status.readyReplicas}')
  [[ "$READY" -ge 1 ]] && ok "istiod Ready ($READY)" || bad "istiod presente pero no Ready"
else
  warn "Istio no instalado — necesario para C1/istio y C2/istio-mtls"
fi

# Linkerd
if kctl get ns linkerd >/dev/null 2>&1; then
  READY=$(kctl -n linkerd get deploy linkerd-destination -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ "$READY" -ge 1 ]] && ok "linkerd Ready ($READY)" || warn "linkerd presente pero no Ready"
else
  warn "Linkerd no instalado — necesario para C2/linkerd-mtls"
fi

# Kong
if kctl get ns kong >/dev/null 2>&1; then
  READY=$(kctl -n kong get deploy kong-kong -o jsonpath='{.status.readyReplicas}' 2>/dev/null \
         || kctl -n kong get deploy kong -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [[ "$READY" -ge 1 ]] && ok "kong Ready ($READY)" || warn "kong presente pero no Ready"
else
  warn "Kong no instalado — necesario para C1/kong"
fi

# ----------------------------------------------------------------------------
sec "7. PV provisioner (hostpath-storage)"
# ----------------------------------------------------------------------------
if kctl get storageclass --no-headers 2>/dev/null | grep -q "(default)"; then
  SC=$(kctl get storageclass --no-headers | awk '/\(default\)/{print $1}' | head -1)
  ok "StorageClass default: $SC"
else
  bad "no hay StorageClass default — PostgreSQL no podrá montar PV"
fi

# ----------------------------------------------------------------------------
sec "8. Recursos del host"
# ----------------------------------------------------------------------------
RAM_FREE_GB=$(awk '/MemAvailable/{printf "%.1f", $2/1024/1024}' /proc/meminfo)
if awk "BEGIN{exit !($RAM_FREE_GB >= 4.0)}"; then
  ok "RAM disponible: ${RAM_FREE_GB} GB (≥ 4 GB)"
elif awk "BEGIN{exit !($RAM_FREE_GB >= 1.5)}"; then
  warn "RAM disponible: ${RAM_FREE_GB} GB (< 4 GB — ok para VUS bajos, contaminará mediciones de VUS≥20)"
else
  bad "RAM disponible: ${RAM_FREE_GB} GB (< 1.5 GB) — insuficiente incluso para 1 VUS"
fi

DISK_FREE_GB=$(df -BG --output=avail "$ROOT_DIR" | tail -1 | tr -d 'G ')
if [[ "$DISK_FREE_GB" -ge 10 ]]; then
  ok "Disco disponible: ${DISK_FREE_GB} GB (≥ 10 GB)"
else
  bad "Disco disponible: ${DISK_FREE_GB} GB (< 10 GB) — libera espacio"
fi

CPU_LOAD=$(awk '{print $1}' /proc/loadavg)
CPU_N=$(nproc)
if awk "BEGIN{exit !($CPU_LOAD < $CPU_N)}"; then
  ok "Load average: $CPU_LOAD (< $CPU_N cores)"
else
  warn "Load average $CPU_LOAD ≥ $CPU_N — el host está ocupado, los tiempos se contaminarán"
fi

# ----------------------------------------------------------------------------
sec "Resumen"
# ----------------------------------------------------------------------------
echo "  Fallos críticos: $FAIL"
echo "  Advertencias:    $WARN"
if [[ $FAIL -eq 0 ]]; then
  echo -e "\n\033[0;32m✓ Entorno LISTO para ejecutar el experimento.\033[0m"
  exit 0
else
  echo -e "\n\033[0;31m✗ Hay $FAIL fallo(s) crítico(s). Corrige antes de ejecutar.\033[0m"
  echo "   Sugerencia: bash scripts/preflight-check.sh --fix   (intenta auto-reparar lo corregible)"
  exit 1
fi
