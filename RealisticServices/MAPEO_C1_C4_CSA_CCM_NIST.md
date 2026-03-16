# Mapeo C1-C4 contra CSA CCM y NIST CSF

## Objetivo
Este documento provee un mapeo argumentativo de los controles C1-C4 implementados en muBench hacia dominios de control de CSA CCM y funciones del marco NIST Cybersecurity Framework (CSF), para reforzar su validez como seguridad defensiva.

## Criterio de mapeo
- El mapeo es funcional y arquitectonico (no auditoria de cumplimiento formal).
- Se prioriza correspondencia por capacidad de mitigacion y efecto operativo.
- Una misma implementacion puede contribuir a varias categorias.

## Tabla de mapeo resumido

| Control | Intencion defensiva | CSA CCM (dominios/categorias relacionadas) | NIST CSF (funciones relacionadas) | Evidencia tecnica en muBench |
|---|---|---|---|---|
| C1 API Gateway | Control de borde, gobernanza de acceso, trazabilidad | IAM, IVS, TVM, LOG | Protect, Detect | Enrutamiento controlado, politicas de acceso y punto central de inspeccion |
| C2 mTLS Service Mesh | Identidad de servicio y cifrado este-oeste | EKM, IAM, IVS, DSI | Protect | Autenticacion mutua y cifrado en trafico interno |
| C3 Network Policies | Microsegmentacion y minimo privilegio de red | IVS, DSI, TVM | Protect | Restriccion explicita de flujos pod-a-pod y reduccion de movimiento lateral |
| C4 Rate Limiting | Mitigacion de abuso y proteccion de disponibilidad | TVM, SEF, LOG | Protect, Detect, Respond | Limitacion de tasa por API/ruta y degradacion controlada ante picos hostiles |

## Detalle por control

### C1 - API Gateway
Contribuciones principales:
- centraliza enforcement de autenticacion/autorizacion,
- reduce superficie de exposicion,
- mejora consistencia de politicas y trazabilidad.

Relaciones marco:
- CSA CCM: IAM e IVS por control de acceso e integracion de servicios; LOG por auditoria; TVM por reduccion de vectores de exposicion.
- NIST CSF: Protect (PR.AC, PR.PT) y Detect (DE.CM) por telemetria centralizada.

### C2 - mTLS Service Mesh
Contribuciones principales:
- identidad criptografica de workloads,
- confidencialidad e integridad de trafico interno,
- mitigacion de suplantacion y MITM interno.

Relaciones marco:
- CSA CCM: EKM (gestion de material criptografico), IAM (identidades de servicio), DSI/IVS (seguridad de interfaces internas).
- NIST CSF: Protect, especialmente controles de comunicaciones seguras y control de acceso entre componentes.

### C3 - Network Policies
Contribuciones principales:
- segmentacion de red declarativa,
- aplicacion de minimo privilegio de conectividad,
- contencion de blast radius.

Relaciones marco:
- CSA CCM: IVS y DSI por aislamiento y proteccion de comunicaciones, TVM por reduccion de superficie explotable.
- NIST CSF: Protect, con enfasis en controles de red y segmentacion.

### C4 - Rate Limiting
Contribuciones principales:
- reduccion de abuso de API y fuerza bruta,
- amortiguacion de picos adversos,
- mejora de continuidad operacional.

Relaciones marco:
- CSA CCM: TVM y SEF por endurecimiento y proteccion de servicios expuestos; LOG por correlacion de eventos de abuso.
- NIST CSF: Protect (limitacion preventiva), Detect (senales de abuso), Respond (contencion automatizada por politica de tasa).

## Uso recomendado en tesis/paper
- Presentar este mapeo como alineamiento tecnico, no certificacion.
- Combinar el mapeo con resultados experimentales de p95/error rate/throughput para demostrar costo-beneficio.
- Enfatizar que la contribucion es una postura de defensa en profundidad medible.

## Texto breve reutilizable
Los controles C1-C4 se alinean funcionalmente con dominios de identidad, proteccion de interfaces, segmentacion y resiliencia operacional de CSA CCM y NIST CSF. Esta alineacion respalda su interpretacion como controles de seguridad defensiva multicapa con impacto cuantificable en desempeno.
