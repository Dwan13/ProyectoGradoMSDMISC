# Configuración de Base de Datos Realista (Postgres) para muBench

## 1. Desplegar Postgres en un nuevo namespace

```bash
kubectl apply -f RealisticServices/k8s/02-postgres-real.yaml
```
Esto creará:
- Namespace: `mubench-real`
- Secret con credenciales
- ConfigMap para inicialización (puedes editarlo para importar tu dump)
- Deployment y Service de Postgres

## 2. Importar tus datos reales

- Si tienes un dump SQL, puedes cargarlo así:

```bash
kubectl -n mubench-real exec -it deploy/postgres -- bash
psql -U mubench -d mubench_real < /ruta/a/tu/dump.sql
exit
```
- O puedes montar el dump en el ConfigMap/postgres-init y redeployar.

## 3. Apuntar los microservicios al nuevo Postgres

- Edita los deployments de tus servicios (`api-service`, `data-service`, etc.) en el namespace correspondiente (ej: `mubench-real`):
  - Cambia las variables de entorno:
    - `DB_HOST=postgres.mubench-real.svc.cluster.local`
    - `DB_NAME=mubench_real`
    - `DB_USER=mubench`
    - `DB_PASSWORD=mubench`
- Puedes hacerlo con `kubectl edit deployment <servicio> -n mubench-real` o actualizando los manifests y aplicando con `kubectl apply`.

## 4. Validar conectividad

```bash
kubectl -n mubench-real get pods
kubectl -n mubench-real logs deploy/data-service
# Prueba el endpoint /users o /users/{id}
```

## 5. Mantener ambos entornos
- El entorno original (sintético) sigue funcionando en su namespace.
- El entorno realista opera en `mubench-real` y usa la base real.

---

**Listo para comparar ambos escenarios!**
