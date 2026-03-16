# Argumento Academico de Seguridad Defensiva para C1-C4

## Resumen
Este documento fundamenta que los controles C1-C4 implementados en muBench pueden justificarse como una estrategia de seguridad defensiva en profundidad para microservicios sobre Kubernetes. La tesis central es que dichos controles no deben evaluarse de forma aislada, sino como una arquitectura multicapa de mitigacion preventiva y resiliencia operativa, con impacto en rendimiento cuantificado experimentalmente.

## 1. Modelo de Amenaza y Alcance
El sistema evaluado considera un entorno cloud-native con trafico norte-sur (exposicion API) y este-oeste (comunicacion entre microservicios). El modelo de amenaza incluye:

- intentos de acceso no autorizado,
- suplantacion de servicios,
- intercepcion de trafico interno,
- movimiento lateral tras compromiso parcial,
- abuso de API y degradacion por sobrecarga maliciosa.

Este alcance no cubre forensia avanzada post-incidente ni capacidades SOC de investigacion profunda. Por ello, la argumentacion se centra en controles preventivos y de contencion.

## 2. Razonamiento Defensivo General
Los controles C1-C4 actuan en capas complementarias del sistema:

- C1 (API Gateway): control de borde y gobernanza de acceso.
- C2 (mTLS Service Mesh): autenticacion mutua y cifrado interno.
- C3 (Network Policies): microsegmentacion y reduccion de movimiento lateral.
- C4 (Rate Limiting): mitigacion de abuso y proteccion de disponibilidad.

Esta composicion implementa defensa en profundidad: la evasión parcial de un control no implica perdida total de proteccion.

## 3. Justificacion por Control

### 3.1 C1 - API Gateway (Control de Perimetro)
C1 incorpora un punto unificado de enforcement para trafico entrante, habilitando autenticacion, autorizacion, validacion de solicitudes y trazabilidad centralizada. Desde la seguridad defensiva, su valor principal es reducir superficie de ataque y evitar exposicion inconsistente de servicios internos.

Rol de seguridad: preventivo, con soporte detective mediante observabilidad y auditoria.

### 3.2 C2 - mTLS Service Mesh (Control Criptografico Interno)
C2 asegura identidad criptografica de workloads y cifrado en transito entre servicios. Mitiga suplantacion, sniffing interno y ataques man-in-the-middle en el plano este-oeste.

Rol de seguridad: preventivo.

### 3.3 C3 - Network Policies (Control de Segmentacion)
C3 restringe conectividad pod-a-pod bajo minimo privilegio, permitiendo solo flujos explicitamente autorizados. Con ello, disminuye probabilidades de movimiento lateral y limita blast radius ante compromiso parcial.

Rol de seguridad: preventivo y de contencion.

### 3.4 C4 - Rate Limiting (Control de Abuso y Disponibilidad)
C4 regula la tasa de solicitudes por cliente o ruta, mitigando abuso de API, fuerza bruta y saturacion de capa aplicacion. Su valor defensivo combina seguridad y continuidad operacional.

Rol de seguridad: preventivo con efecto directo en resiliencia.

## 4. Interpretacion de Defensa en Profundidad
En conjunto, C1-C4 conforman una postura defensiva multicapa:

- borde y gobernanza de API (C1),
- identidad y transporte interno seguro (C2),
- segmentacion y contencion lateral (C3),
- control de abuso y disponibilidad (C4).

La arquitectura resultante se alinea con principios de minimo privilegio y reduccion progresiva de riesgo tecnico.

## 5. Trade-off Seguridad-Rendimiento
El costo de latencia/throughput no se interpreta como efecto secundario accidental, sino como costo medible de endurecimiento defensivo. El criterio de aceptacion de controles se basa en tres condiciones:

- mitigacion efectiva de amenazas relevantes,
- reduccion tangible de explotabilidad o impacto,
- mantenimiento de SLOs operacionales.

## 6. Recomendaciones de Reporte Experimental
Para sustentar evidencia en tesis/paper, se recomienda reportar:

- perfil de carga (VUs, duracion y mezcla de peticiones),
- conjunto de controles activo por corrida,
- latencias p50/p95/p99, error rate y throughput,
- interpretacion de seguridad asociada a variaciones de metricas.

Este enfoque conecta resultados de performance con decisiones de ingenieria de seguridad.

## 7. Conclusion
C1-C4 pueden argumentarse de forma robusta como seguridad defensiva para microservicios en Kubernetes. Su contribucion conjunta reduce exposicion, dificulta propagacion lateral, protege trafico interno y amortigua patrones de abuso. El overhead observado representa el costo cuantificable de reducir riesgo en una arquitectura cloud-native realista.
