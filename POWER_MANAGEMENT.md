# 🔌 Power Management - Shutdown & Startup Scripts

## 📍 Dos Scripts para Apagar y Encender

### 1️⃣ **ANTES DE APAGAR** → `graceful-shutdown.sh`

```bash
bash scripts/graceful-shutdown.sh
```

**Qué hace** (automáticamente):
- ✓ Detiene tests en ejecución (si los hay)
- ✓ Elimina todos los pods Kubernetes
- ✓ Escala deployments a 0
- ✓ Detiene MicroK8s gracefully
- ✓ Preserva todos tus datos

**Tiempo**: 30-60 segundos

**Output esperado**:
```
[INFO] Paso 1/5: Verificando procesos en ejecución...
[✓] Procesos limpios

[INFO] Paso 2/5: Limpiando recursos Kubernetes...
[✓] Recursos Kubernetes limpiados

[INFO] Paso 3/5: Deteniendo servicios...
[✓] Servicios detenidos

[INFO] Paso 4/5: Deteniendo MicroK8s...
[✓] MicroK8s detenido exitosamente

[✓] SHUTDOWN GRACEFUL COMPLETADO
```

Luego **apaga normalmente**:
```bash
shutdown -h now              # Linux
# O cierra WSL desde Windows normalmente
```

---

### 2️⃣ **DESPUÉS DE ENCENDER** → `graceful-startup.sh`

```bash
bash scripts/graceful-startup.sh
```

**Qué hace** (automáticamente):
- ✓ Verifica MicroK8s instalado
- ✓ Levanta MicroK8s
- ✓ Espera a que esté ready
- ✓ Valida cluster status
- ✓ Verifica namespaces y volúmenes
- ✓ Prepara sistema para tests

**Tiempo**: 1-2 minutos (dependiendo de recovery)

**Output esperado**:
```
[INFO] Paso 1/5: Verificando MicroK8s...
[✓] MicroK8s encontrado

[INFO] Paso 2/5: Levantando MicroK8s...
[INFO] Esperando a que MicroK8s esté ready (máx 60s)...
[✓] MicroK8s ready

[INFO] Paso 3/5: Validando cluster...
[✓] Cluster operativo

[INFO] Paso 4/5: Verificando namespaces...
[✓] Namespace 'realistic' disponible

[✓] STARTUP COMPLETADO
```

Luego **ejecuta tests normalmente**:
```bash
bash scripts/run-scaling-tests.sh
# o
bash scripts/run-all-controls-experiments.sh
```

---

## 🎯 Flujo Diario Completo

### Mañana por la mañana:

```bash
# 1. Encender máquina/WSL2
wsl
cd ~/muBench

# 2. Startup (levanta el cluster)
bash scripts/graceful-startup.sh

# 3. Ejecutar tests (sin cambios)
bash scripts/run-scaling-tests.sh
```

### Al final del día (antes de apagar):

```bash
# 1. Shutdown (prepara para apagado)
bash scripts/graceful-shutdown.sh

# 2. Apagar máquina
shutdown -h now  # o cerrar WSL
```

---

## ✨ Características Clave

### Graceful Shutdown:
- ✅ Mata procesos gracefully (no fuerza)
- ✅ Espera a que se terminen (máx 60s)
- ✅ Preserva todos los datos (volúmenes de Docker)
- ✅ Limpia pods fantasma
- ✅ Apaga MicroK8s correctamente

### Graceful Startup:
- ✅ Verifica que MicroK8s esté instalado
- ✅ Levanta automáticamente
- ✅ Espera a que esté ready (máx 300s)
- ✅ Valida cluster status
- ✅ Muestra información útil
- ✅ Listo para tests inmediatamente

---

## 🆘 Si Algo Sale Mal

### Si MicroK8s no levanta después del startup:

```bash
# Opción 1: Reiniciar manualmente
microk8s restart

# Opción 2: Hacer refresh
microk8s refresh

# Opción 3: Verificar status
microk8s status

# Opción 4: Ver logs
journalctl -u snap.microk8s.daemon-kubelet -f
```

### Si quedan pods en estado "Terminating":

```bash
# Limpiar forzadamente
kubectl delete pod -n realistic --all --grace-period=0 --force
```

### Si SQLite/PostgreSQL está corrupto:

```bash
# Se recrea automáticamente en el siguiente test
# Todos los datos se preservan en volúmenes
```

---

## 💡 Tips

- **Ejecuta shutdown SIEMPRE antes de apagar** (solo 30s, vale la pena)
- **Ejecuta startup la primera vez que enciendas** (automático, recomendado)
- Los datos persisten entre apagados (volúmenes de Docker)
- Puedes ejecutar los scripts múltiples veces (idempotentes)
- Si tienes dudas, ejecuta: `bash scripts/graceful-startup.sh --help`

---

## 📊 Comparación: Con vs Sin Shutdown

| Aspecto | Sin Shutdown | Con Shutdown |
|--------|---|---|
| Tiempo de apagado | Inmediato | +30s (graceful) |
| Riesgo de corrupción | Alto | Ninguno |
| Pods fantasma mañana | Sí (limpiar) | No |
| Datos perdidos | Posible | Ninguno |
| Startup mañana | Más lento (recovery) | Normal (1-2 min) |
| Recomendado | ❌ | ✅ |

---

## 🚀 Quick Copy-Paste

Antes de apagar:
```bash
cd ~/muBench && bash scripts/graceful-shutdown.sh
```

Después de encender:
```bash
cd ~/muBench && bash scripts/graceful-startup.sh && bash scripts/run-scaling-tests.sh
```

---

**¡Listo! Ya puedes apagar sin preocupaciones mañana.** 💤
