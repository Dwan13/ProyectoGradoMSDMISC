# Experimento C1: API Gateway (NGINX vs Kong vs Baseline)

- Todos los manifiestos de Ingress (nginx, kong) y secretos TLS están listos para exponer los servicios por HTTPS.
- Asegúrate de que los endpoints de prueba apunten a `https://realistic.local/api` y `https://realistic.local/auth`.
- Para pruebas locales, agrega `127.0.0.1 realistic.local` a tu `/etc/hosts`.
- El script de despliegue aplica automáticamente los manifiestos según el gateway seleccionado.
