# Security-Performance Framing of C1-C4 Controls (IEEE/ACM Draft)

## Abstract
This document positions the implemented controls C1-C4 as a defensive, layered security strategy for Kubernetes-based microservices. The goal is to justify these controls not only as isolated best practices, but as a coherent defense-in-depth posture with measurable performance impact.

## 1. Threat Model and Scope
The evaluated system assumes a realistic cloud-native setting where services communicate over east-west traffic and are exposed through north-south API paths. The threat model includes unauthorized access attempts, lateral movement after partial compromise, service impersonation, traffic interception, and abusive request patterns affecting availability.

The model excludes advanced post-exploitation forensics and long-term persistence analysis. Therefore, controls are framed as preventive and resilience-oriented mechanisms rather than incident response tooling.

## 2. Defensive Security Rationale
The four controls are mapped to complementary protection layers:

- C1 (API Gateway): edge enforcement and centralized access governance.
- C2 (mTLS Service Mesh): authenticated and encrypted service-to-service channels.
- C3 (Network Policies): microsegmentation and lateral movement reduction.
- C4 (Rate Limiting): abuse throttling and availability protection.

This layering supports defense in depth: bypassing one mechanism does not imply full loss of protection.

## 3. Control-by-Control Argument

### 3.1 C1 - API Gateway (Edge Control)
C1 provides a centralized policy enforcement point for ingress traffic, enabling uniform authentication, authorization, request filtering, and audit logging. From a defensive viewpoint, this reduces attack surface and prevents direct, inconsistent access paths to internal services.

Security role: preventive, with supporting detective value through observability and traceability.

### 3.2 C2 - mTLS Service Mesh (Cryptographic Internal Control)
C2 enforces mutual authentication and encryption for east-west traffic. This mitigates service spoofing, in-cluster man-in-the-middle risks, and passive traffic inspection. Its primary defensive contribution is cryptographic workload identity and channel integrity/confidentiality.

Security role: preventive.

### 3.3 C3 - Network Policies (Segmentation Control)
C3 constrains pod-level communication using least-privilege connectivity. By explicitly declaring allowed flows, it reduces lateral movement opportunities and limits blast radius under partial compromise.

Security role: preventive and containment-oriented.

### 3.4 C4 - Rate Limiting (Abuse and Availability Control)
C4 limits request rates per client/path and mitigates brute-force behavior, API abuse, and application-layer saturation. It is both a security and service-protection control because it preserves system behavior under hostile or erratic demand.

Security role: preventive, with strong operational resilience impact.

## 4. Defense-in-Depth Interpretation
Jointly, C1-C4 create a multi-layer defensive posture:

- Perimeter and API governance (C1)
- Internal identity and secure transport (C2)
- East-west movement control (C3)
- Abuse and availability control (C4)

This composition aligns with common cloud security principles: least privilege, zero-trust-inspired service identity, and layered risk reduction.

## 5. Performance-Security Trade-off
The experimental objective is not to maximize throughput at any cost, but to quantify overhead introduced by defensive controls and assess whether risk reduction justifies that overhead. Results should therefore be interpreted as a trade-off curve between security guarantees and latency/throughput behavior.

A control is considered acceptable when:

- it mitigates relevant threats in the stated model,
- it meaningfully reduces exploitability or impact,
- and performance remains within operational SLOs.

## 6. Reproducibility and Reporting Guidance
For publication-quality reporting, provide:

- workload profile (VUs, duration, request mix),
- enabled control set per run,
- latency percentiles (p50/p95/p99), error rate, and throughput,
- and a concise security interpretation per metric shift.

This avoids treating performance variance as purely technical noise and frames it as evidence for security engineering decisions.

## 7. Conclusion
C1-C4 can be rigorously defended as a defensive security architecture for microservices. They jointly reduce exposure, constrain unauthorized propagation, protect in-cluster communications, and mitigate abusive traffic patterns. Their overhead is not incidental but a measurable cost of risk reduction, and should be evaluated against explicit security and reliability objectives.
