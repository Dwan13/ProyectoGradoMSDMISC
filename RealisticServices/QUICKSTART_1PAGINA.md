# Quickstart 1 Pagina

## Objetivo
Levantar todo el proyecto en modo hibrido y validar carga realista (crear y listar usuarios) desde el script principal.

## 1) Requisitos Minimos
```bash
docker --version
microk8s status --wait-ready
k6 version
```

## 2) Preparacion
```bash
cd /home/dwan13/muBench
chmod +x scripts/deploy_microk8s.sh
chmod +x RealisticServices/deploy-realistic.sh
chmod +x RealisticServices/run-k6-users-bulk.sh
```

## 3) Corrida Rapida Recomendada
```bash
./scripts/deploy_microk8s.sh --start --hybrid-quick
```

## 4) Corridas Alternativas
Normal:
```bash
./scripts/deploy_microk8s.sh --start --hybrid
```

Stress:
```bash
./scripts/deploy_microk8s.sh --start --hybrid-stress
```

Con controles realistas C1-C4:
```bash
./scripts/deploy_microk8s.sh --start --hybrid --hybrid-controls
```

## 5) Verificar Resultado
```bash
ls -1t RealisticServices/results/k6-users-bulk-*.json | head -n 1
ls -1t RealisticServices/results/hybrid-k6-summary-*.txt | head -n 1
```

Mostrar ultimo summary:
```bash
latest=$(ls -1t RealisticServices/results/hybrid-k6-summary-*.txt | head -n1)
sed -n '1,80p' "$latest"
```

## 6) Verificar Dashboard
- Grafana: http://localhost:3000
- Dashboard comparativo: debe incluir panel "Resumen Hibrido k6 (Auto)"

## 7) Comando de Stop
```bash
./scripts/deploy_microk8s.sh --stop
```

## 8) Si algo falla
1. Limpiar port-forward:
```bash
pkill -f "port-forward" || true
```
2. Reintentar quick:
```bash
./scripts/deploy_microk8s.sh --start --hybrid-quick
```
