# Guia de apagado y arranque seguro (sin perder estado)

Esta guia documenta el flujo para:
- Apagar el equipo sin perder el estado de trabajo del dia.
- Restaurar el entorno al iniciar.
- Elegir explicitamente que escenario levantar (S1, S2, S3, S4).

Scripts oficiales:
- `scripts/graceful-shutdown.sh`
- `scripts/graceful-startup.sh`

## 1) Apagado seguro al terminar la jornada

Comando recomendado (guardando escenario activo):

```bash
bash scripts/graceful-shutdown.sh --scenario s2
```

Que hace:
- Guarda snapshot en `.mubench-state/last-session.env`.
- Guarda el ultimo escenario (`LAST_SCENARIO`) para restauracion.
- Cierra procesos de benchmark y port-forward locales.
- Preserva recursos Kubernetes (no borra pods/PV por limpieza agresiva).
- Escala deployments a 0 (por defecto) para apagar limpio.
- Detiene MicroK8s (por defecto).

Opciones utiles:

```bash
# No detener MicroK8s
bash scripts/graceful-shutdown.sh --scenario s2 --keep-running

# No escalar deployments a 0
bash scripts/graceful-shutdown.sh --scenario s2 --no-scale-down
```

## 2) Arranque al dia siguiente

Restaurar ultimo escenario guardado:

```bash
bash scripts/graceful-startup.sh --scenario last
```

Forzar un escenario especifico:

```bash
bash scripts/graceful-startup.sh --scenario s1
bash scripts/graceful-startup.sh --scenario s2
bash scripts/graceful-startup.sh --scenario s3
bash scripts/graceful-startup.sh --scenario s4
```

Modo interactivo (menu):

```bash
bash scripts/graceful-startup.sh
```

## 3) Que setup ejecuta cada escenario

- `s1` -> `scripts/deploy-realistic-stack.sh`
- `s2` -> `scripts/setup-postgres-real-scenario.sh`
- `s3` -> `scripts/setup-scenario3-mubench-advanced.sh`
- `s4` -> `scripts/setup-scenario4-semantic-equivalent.sh`

## 4) Archivo de estado persistente

Ruta:

```text
.mubench-state/last-session.env
```

Contenido esperado (resumen):
- `LAST_SHUTDOWN_UTC`
- `LAST_SCENARIO`
- `STOP_MICROK8S`
- `SCALE_DOWN`
- Snapshot de replicas por deployment (para trazabilidad)

## 5) Flujo operativo recomendado

1. Antes de apagar: ejecutar `graceful-shutdown.sh` con `--scenario` correcto.
2. Apagar el PC.
3. Al iniciar: ejecutar `graceful-startup.sh --scenario last`.
4. Si se necesita otro escenario: ejecutar `graceful-startup.sh --scenario sX`.

## 6) Verificacion rapida post-arranque

```bash
microk8s kubectl get ns
microk8s kubectl get pods -A
```

Si el escenario quedo levantado correctamente, puedes continuar con pruebas y validaciones normales.
