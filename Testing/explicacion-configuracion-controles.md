
# Explicación de la Configuración de Controles Experimentales

Este documento describe dónde y cómo se configuraron los controles experimentales (C1–C4) en el entorno de pruebas, y aclara la presencia/ausencia de ciertas tecnologías para tu presentación y defensa.

---

## C1: API Gateway (NGINX, Istio Ingress, Kong)
- **Ubicación de manifiestos:**
  - `experiments/01-api-gateway-realistic/baseline/` (NGINX)
  - `experiments/01-api-gateway-realistic/istio/` (Istio Ingress)
  - `experiments/01-api-gateway-realistic/kong/` (Kong)
- **Cómo se configura:**
  - Cada subcarpeta contiene manifiestos YAML para el gateway correspondiente (Ingress, Gateway, Service, etc.).
  - El script maestro (`scripts/run-all-controls-experiments.sh`) aplica automáticamente los manifiestos de la variante antes de lanzar la prueba k6.
  - Los endpoints de prueba se exponen por HTTPS usando los manifiestos de Ingress o Gateway.

## C2: mTLS (Istio, Linkerd, Baseline)
**Ubicación de manifiestos:**
  - `experiments/02-mtls-service-mesh-realistic/baseline/`
  - `experiments/02-mtls-service-mesh-realistic/istio-mtls/`
  - `experiments/02-mtls-service-mesh-realistic/linkerd-mtls/`
**Cómo se configura:**
  - Los manifiestos de Istio y Linkerd habilitan mTLS en el Service Mesh (ejemplo: `PeerAuthentication`, `DestinationRule`, `MeshPolicy`).
  - El script maestro aplica el manifiesto correspondiente antes de cada prueba.
  - Linkerd fue considerado y está parcialmente integrado (estructura de carpetas y reporte), pero requiere pasos adicionales para su despliegue y automatización completa.

## C3: Network Policies
**Ubicación de manifiestos:**
  - `experiments/03-network-policies-realistic/baseline/` (sin políticas)
  - `experiments/03-network-policies-realistic/basic/` (aislamiento por namespace)
  - `experiments/03-network-policies-realistic/strict/` (microsegmentación por par)
**Cómo se configura:**
  - Cada variante tiene manifiestos YAML de `NetworkPolicy`.
  - `basic`: Permite tráfico solo dentro del namespace.
  - `strict`: Define reglas explícitas para permitir solo el tráfico necesario entre servicios específicos.
  - El script maestro aplica la política antes de lanzar la prueba.
**Nota sobre Calico:**
  - No se incorporó Calico como CNI ni como motor específico de políticas de red. Se usó el CNI por defecto de MicroK8s, por lo que las NetworkPolicies aplicadas son genéricas y compatibles, pero no aprovechan funcionalidades avanzadas de Calico.

## C4: Rate Limiting
**Ubicación de manifiestos:**
  - `experiments/04-rate-limiting-realistic/baseline/` (sin rate limit)
  - `experiments/04-rate-limiting-realistic/moderate/` (100 req/s)
  ---

  ## Tecnologías consideradas pero no desplegadas

  - **Jaeger y Kiali:** No se desplegaron ni usaron en los experimentos. No hay trazabilidad ni visualización de malla de servicios en la campaña final.
  - **Calico:** No se instaló como CNI ni se usó para políticas de red avanzadas; se optó por el CNI por defecto de MicroK8s.
  - **Linkerd:** Estaba comprometido como parte de la comparación de service mesh y mTLS, pero su integración completa requiere pasos adicionales (instalación, inyección de proxy, automatización de experimentos). Está parcialmente reflejado en la estructura y reportes, pero no se ejecutaron experimentos automatizados con Linkerd en la campaña final.
  - `experiments/04-rate-limiting-realistic/strict/` (20 req/s)
- **Cómo se configura:**
  - Los manifiestos pueden incluir recursos como `EnvoyFilter`, `RateLimit`, o variables de entorno en los deployments (`RATE_LIMIT_ENABLED`, `RATE_LIMIT_RPM`).
  - El script maestro aplica el manifiesto y/o setea las variables antes de cada prueba.

---

## Automatización y ejecución
- El script `scripts/run-all-controls-experiments.sh` automatiza la aplicación de cada control y variante, ejecuta k6 con diferentes cargas y recolecta métricas.
- Los resultados se almacenan diferenciados por control, variante y nivel de carga.

## Resumen
- **Cada control experimental se configura aplicando los manifiestos YAML específicos de la variante antes de cada prueba.**
- **La automatización garantiza que la configuración activa siempre corresponde al control/escenario que se está evaluando.**

Esto te permite explicar con claridad cómo se orquestó y aisló cada experimento, asegurando validez y reproducibilidad.
