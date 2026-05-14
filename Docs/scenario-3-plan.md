# Escenario 3 - muBench Avanzado (Plan Ejecutable)

## Objetivo
Levantar una experimentación basada en funciones avanzadas nativas de muBench (ServiceGraphGenerator, WorkModelGenerator, K8sDeployer), aislada del escenario 1 y 2.

## Aislamiento
- Namespace: `mubench-advanced`
- Configuración y salida en: `experiments/05-mubench-advanced/`

## Pipeline
1. Generar grafo de servicios avanzado
2. Generar workmodel avanzado desde ese grafo
3. Generar yamls y desplegar con K8sDeployer
4. Verificar pods y services
5. Reutilizar observabilidad para mediciones comparables

## Archivos de configuración
- `experiments/05-mubench-advanced/Configs/ServiceGraphParameters.advanced.json`
- `experiments/05-mubench-advanced/Configs/WorkModelParameters.advanced.json`
- `experiments/05-mubench-advanced/Configs/K8sParameters.advanced.json`

## Script de arranque
- `scripts/setup-scenario3-mubench-advanced.sh`

## Ejecución
```bash
bash scripts/setup-scenario3-mubench-advanced.sh
```
