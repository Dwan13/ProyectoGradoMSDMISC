# Escenarios Experimentales Propuestos para muBench

**Objetivo:** Permitir la comparación y evolución incremental de experimentos, sin perder avances previos.

---

## Escenario 1: Actual (Datos Sintéticos / Prueba)
- **Stack:** K8s + microservicios + k6 + Prometheus/Grafana
- **Base de datos:** Sintética o mínima (usuarios de prueba, datos generados por scripts)
- **Carga:** k6 con flujo login/profile, usuarios de prueba
- **Ventaja:** 100% reproducible, bajo riesgo, ideal para comparativas de tecnologías de control
- **Limitación:** No refleja comportamiento real de negocio ni volumen de datos realistas

---

## Escenario 2: Base de Datos Real en Postgres
- **Stack:** Igual que Escenario 1, pero conectando los microservicios a una instancia real de Postgres
- **Base de datos:** Real (puedes importar un dump, usar datos de producción anonimizados, o poblar con scripts propios)
- **Carga:** Igual (k6), pero los endpoints `/users`, `/users/{id}` y `/users` (POST) ahora interactúan con datos reales
- **Ventaja:** Permite medir el impacto de volumen, índices, y queries reales en la performance
- **Cómo lograrlo:**
  1. Desplegar Postgres usando `RealisticServices/k8s/01-postgres.yaml` (puedes modificar el `01-init.sql` para importar tus datos)
  2. Cambiar los valores de conexión (`DB_HOST`, `DB_USER`, etc.) en los deployments de los microservicios para apuntar a la nueva base
  3. (Opcional) Usar un namespace diferente para aislar este entorno
- **Limitación:** Sigue usando el mismo flujo de carga (k6), pero ahora con datos reales

---

## Escenario 3: muBench Avanzado (Carga y Datos Realistas)
- **Stack:** muBench en modo completo, activando:
  - Generador de cargas realistas (simulación de flujos de negocio, múltiples endpoints, patrones de acceso realistas)
  - Base de datos realista (poblada con datos representativos, scripts de seed avanzados)
  - Funciones avanzadas de muBench (workmodel, service graph, affinity, etc.)
- **Ventaja:** Permite experimentos de benchmarking con máxima fidelidad al mundo real (tanto en datos como en patrones de uso)
- **Cómo lograrlo:**
  1. Desplegar todos los componentes avanzados de muBench (ver Docs/replication-guide.md)
  2. Usar los scripts de seed/initdb avanzados para poblar la base
  3. Configurar los servicios para usar los flujos de negocio y datos realistas
  4. Ejecutar los experimentos usando los scripts de muBench (no solo k6)
- **Limitación:** Mayor complejidad, requiere más recursos y configuración, pero es el escenario más cercano a producción

---

## Recomendaciones para No Perder Avances
- **Usar namespaces diferentes** para cada escenario (`mubench-sintetico`, `mubench-real`, `mubench-avanzado`)
- **Versionar los manifiestos y scripts** para cada entorno
- **No borrar ni modificar los datos ni la configuración del escenario anterior** al avanzar al siguiente
- **Documentar cada cambio** en Docs/ para poder volver atrás si es necesario

---

## Siguiente Paso
¿Quieres que te ayude a:
- Preparar el manifiesto para importar tu base real?
- Identificar los archivos/configs para activar muBench avanzado?
- Automatizar el cambio de entorno (scripts de switch)?
