# Checklist Final de Experimentación y Documentación

## 1. Cobertura experimental
- [ ] Todos los escenarios ejecutados: S1, S2, S3, S4
- [ ] Todos los controles aplicados: C1, C2, C3, C4
- [ ] Todas las variantes por control (ej: istio, linkerd, strict, etc.)
- [ ] Matriz completa de VUs: 1, 5, 10, 20
- [ ] Validación de persistencia y equivalencia funcional (S2/S4)
- [ ] Validación de endpoints y JWT (login, create, list)
- [ ] Validación de recursos (CPU/memoria) en cada campaña
- [ ] Anotaciones en Grafana para cada campaña relevante
- [ ] Exportación de CSVs y gráficos comparativos finales

## 2. Consolidación de resultados
- [ ] Consolidar CSVs de métricas y controles:
  - `Testing/results/anova/`, `Testing/results/control_comparison/`
- [ ] Consolidar gráficos clave (PNG):
  - `Testing/plots/high_level_report/`, `Testing/plots/control_comparison/`
- [ ] Exportar dashboards de Grafana (JSON)
- [ ] Tomar snapshots de gráficas clave para el informe

## 3. Documentación y replicabilidad
- [ ] Guía de setup y prerequisitos (K8s, microk8s, Prometheus, Grafana, k6)
- [ ] Guía de ejecución de campañas (scripts, parámetros, ejemplos)
- [ ] Guia operativa de apagado/arranque seguro con restauracion de escenario (`Docs/graceful-shutdown-startup.md`)
- [ ] Guía de validación y troubleshooting
- [ ] Guía de análisis y exportación de resultados
- [ ] Referencias a scripts y rutas de artefactos
- [ ] Instrucciones para importar dashboards y datasets en Grafana
- [ ] Resumen metodológico y justificación experimental
- [ ] Limitaciones y notas de interpretación

## 4. (Opcional) Automatización extra
- [ ] Script para exportar dashboards y snapshots automáticamente
- [ ] Script para re-anotar campañas pasadas si es necesario
- [ ] Script para consolidar todo en un ZIP reproducible

---

> Marca cada punto conforme avances. Si algún ítem no aplica, justifica brevemente en la documentación final.
