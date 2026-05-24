# Controles de Seguridad — Descripción Completa

> **Fecha:** 2026-05-14  
> **Experimento:** S6 Integrated Dual-Mode (muBench / mubench-real)  
> **Namespace Kubernetes:** `mubench-real`

---

## Resumen General

Se implementaron **4 controles de seguridad (C1–C4)**, cada uno con **3 variantes** (baseline + 2 especializadas), totalizando **12 celdas experimentales**. Los controles se aplican sobre los microservicios desplegados en el namespace `mubench-real` de un clúster MicroK8s single-node.

| Control | Categoría | Variantes | Fichero(s) clave |
|---------|-----------|-----------|-----------------|
| C1 | API Gateway / Ingress | baseline · istio · kong | `07-c1-ingress-gateway-real.yaml`, `07-c1-istio-real.yaml`, `07-c1-kong-real.yaml` |
| C2 | Encriptación mTLS | baseline · istio-mtls · linkerd-mtls | `02-services-istio-mtls-real.yaml`, `02-services-linkerd-mtls-real.yaml` |
| C3 | Network Policy | baseline · basic · strict | `08-c3-networkpolicy-real.yaml`, `08-c3-networkpolicy-moderate-real.yaml`, `08-c3-networkpolicy-strict-real.yaml` |
| C4 | Rate Limiting | baseline · moderate · strict | Parámetros en `scripts/s6-integrated-profile.env` y configuración en nginx/kong |

---

## C1 — API Gateway / Ingress

### ¿Qué es?
Un API Gateway actúa como punto de entrada único a los microservicios, terminando TLS y enrutando peticiones según rutas HTTP hacia el servicio backend correspondiente.

### ¿Dónde se aplica?
- Namespace: `mubench-real`
- Recurso: `Ingress` (NGINX o Kong) o `Gateway + VirtualService` (Istio)
- Servicios detrás del gateway: `auth-service:8080`, `api-service:8080`

### Variantes

#### C1/baseline — NGINX Ingress
```yaml
# 07-c1-ingress-gateway-real.yaml
annotations:
  nginx.ingress.kubernetes.io/use-regex: "true"
  nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  tls: [{hosts: [real-postgres.local], secretName: mubench-tls}]
  rules:
    - path: /auth(/|$)(.*) → auth-service:8080
    - path: /api(/|$)(.*)  → api-service:8080
```
- TLS terminado en ingress, rutas `/auth` y `/api` separadas
- Sin política de autenticación adicional (punto de referencia)

#### C1/istio — Istio Ingress Gateway
```yaml
# 07-c1-istio-real.yaml
kind: Gateway
spec:
  selector: {istio: ingressgateway}
  servers: [HTTP:80, HTTPS:443 (SIMPLE TLS)]
---
kind: VirtualService
  http:
    - match: {uri.exact: /profile, method: GET} → api-service:8080
    - match: {uri.exact: /login, method: POST}   → auth-service:8080
```
- Routing gestionado por Envoy sidecar; permite políticas adicionales (AuthorizationPolicy, PeerAuthentication)
- TLS con `credentialName: mubench-tls`

#### C1/kong — Kong Ingress Controller
```yaml
# 07-c1-kong-real.yaml
annotations:
  kubernetes.io/ingress.class: kong
  konghq.com/protocols: "https"
  konghq.com/strip-path: "false"
spec:
  ingressClassName: kong
  tls: [{hosts: [real-postgres.local], secretName: realistic-tls}]
  rules:
    - /profile → api-service:8080
    - /login   → auth-service:8080
```
- Permite plugins Kong (rate limiting, JWT, key-auth) sin modificar la aplicación
- Enforcement en capa 7

### ¿Por qué C1?
Evaluar el overhead de latencia y CPU de distintos mecanismos de ingress. NGINX es la referencia estándar; Istio añade sidecar routing; Kong añade plugin execution. La hipótesis es que Kong e Istio incrementan la latencia media pero aportan capacidad de enforcement.

---

## C2 — Encriptación mTLS (Mutual TLS)

### ¿Qué es?
mTLS encripta el tráfico **inter-servicio** (Este-Oeste) y valida la identidad de **ambos** extremos de la conexión, no solo el servidor. Protege contra ataques de intercepción dentro del clúster.

### ¿Dónde se aplica?
- Tráfico entre pods: `auth-service ↔ api-service ↔ data-service ↔ postgres`
- Namespace: `mubench-real`
- Nivel: sidecar proxy (Istio Envoy) o linkerd-proxy (Linkerd)

### Variantes

#### C2/baseline
- Sin mTLS. Tráfico inter-servicio en texto plano dentro del clúster
- Punto de referencia para overhead de encriptación

#### C2/istio-mtls
- `PeerAuthentication` en modo `STRICT` en namespace `mubench-real`
- Todos los pods requieren certificado cliente emitido por la CA de Istio (SPIFFE/SPIRE)
- Sidecar: `istio-proxy` (Envoy) — add CPU y memoria por pod
- Observado: +45% CPU respecto a baseline, +163 MiB memoria

#### C2/linkerd-mtls
- `linkerd.io/inject: enabled` annotation en Deployments
- Proxy ligero `linkerd-proxy` (Rust) — menor overhead que Istio
- mTLS automático entre todos los pods anotados
- Observado: +15% CPU respecto a baseline, +12 MiB memoria

### ¿Por qué C2?
Cuantificar el costo operativo de encriptación East-West. En entornos de producción esto es fundamental pero pocas veces se mide empíricamente bajo carga variable.

---

## C3 — Network Policy (Micro-segmentación)

### ¿Qué es?
Las `NetworkPolicy` de Kubernetes definen reglas de firewall a nivel de pod usando etiquetas (`matchLabels`). Implementan el principio de **mínimo privilegio de red**: cada pod solo puede comunicarse con los pods que necesita.

### ¿Dónde se aplica?
- Namespace: `mubench-real`
- Pods afectados: `data-service`, `postgres`, `api-service`
- Enforced por: plugin CNI (Calico/Cilium en MicroK8s)

### Variantes

#### C3/baseline
- Sin NetworkPolicy. Tráfico libre entre todos los pods del namespace (flat network)

#### C3/basic
```yaml
# data-service: solo acepta de api-service y observability
# postgres: solo acepta de data-service en puerto 5432
# api-service: puede hacer egress a data-service
```
- Segmenta los servicios de datos pero permite tráfico normal de negocio
- Overhead mínimo (procesamiento en kernel via iptables/eBPF)

#### C3/strict
```yaml
# api-service-egress-restrict:
egress:
  - to: [kube-system]  # SOLO DNS
    ports: [53/UDP, 53/TCP]
# api-service NO puede llegar a data-service
```
- Bloquea deliberadamente `api-service → data-service`
- Produce **impacto medible en disponibilidad**: todas las peticiones que requieren datos fallan (HTTP 500/503)
- Útil como caso extremo para validar detección de degradación

### ¿Por qué C3?
Evaluar el trade-off entre segmentación de red y disponibilidad. `strict` es intencionalmente disruptivo para crear un contraste claro con `basic` y `baseline`, permitiendo medir qué tan sensibles son las métricas de latencia/error.

---

## C4 — Rate Limiting

### ¿Qué es?
El rate limiting restringe el número de peticiones por unidad de tiempo que puede procesar el gateway, protegiendo contra DDoS, brute-force y abuso de API.

### ¿Dónde se aplica?
- Nivel: API Gateway (NGINX Ingress annotations o Kong plugin)
- Namespace: `mubench-real`
- Parámetros calibrados en `scripts/s6-integrated-profile.env`

### Variantes

| Variante | Límite (rpm) | Comportamiento |
|----------|-------------|----------------|
| baseline | Sin límite | Referencia libre |
| moderate | 1,200 rpm | Permite tráfico normal (k6 genera ~100-400 rpm según VUS) |
| strict | 300 rpm | Throttle visible a VUS ≥ 10 |

#### C4/baseline
- Sin configuración de rate limiting en el gateway
- Todo el tráfico k6 pasa sin restricción

#### C4/moderate (1,200 rpm = 20 req/s)
- Calibrado para **no afectar** el tráfico legítimo a VUS ≤ 5
- Comienza a limitar a VUS = 10–20 con perfiles de ataque simultáneo
- Respuesta al límite: HTTP 429 Too Many Requests

#### C4/strict (300 rpm = 5 req/s)
- Limita incluso el tráfico legítimo a VUS ≥ 5 (flujo: login + profile + users = 3 req/VU/iter)
- Diseñado para producir señal clara en `err_pct` y `rps`
- Calibrado en S2 para generar separación estadística medible

### ¿Por qué C4?
Demostrar que el rate limiting es efectivo contra ataques de volumen (DDoS brute-force) pero tiene un costo en tráfico legítimo si los umbrales son demasiado estrictos. Quantifica el umbral de trade-off.

---

## Resumen de Impacto Medido (S6 — todos los modos)

| Control | Variante | avg_ms | p95_ms | cpu_mcores | mem_mib | rps |
|---------|----------|--------|--------|------------|---------|-----|
| C1 | baseline | 11.2 | 28.8 | 323 | 176 | 96.9 |
| C1 | istio | 6.8 | 20.9 | 185 | 182 | 105 |
| C1 | kong | 5.8 | 20.3 | 188 | 179 | 108 |
| C2 | baseline | 10.5 | 27.4 | 326 | 179 | 98.4 |
| C2 | istio-mtls | 14.4 | 41.0 | 421 | 343 | 93.7 |
| C2 | linkerd-mtls | 11.2 | 28.8 | 374 | 191 | 98.9 |
| C3 | baseline | 10.1 | 25.9 | 314 | 177 | 98.4 |
| C3 | basic | 10.2 | 26.4 | 324 | 177 | 98.9 |
| C3 | strict | 1306 | 3013 | 30 | 180 | 8.9 |
| C4 | baseline | 10.2 | 26.5 | 322 | 178 | 98.5 |
| C4 | moderate | 10.5 | 27.7 | 326 | 179 | 98.1 |
| C4 | strict | 10.3 | 27.0 | 325 | 179 | 99.2 |

> Valores promediados sobre todos los VUS y security_modes. C3/strict produce latencia extrema (>1s) y baja de ~100 rps a ~9 rps debido al bloqueo del egress de api-service.
