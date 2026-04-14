import os
import glob
import csv

# Directorio raíz de resultados
RESULTS_DIR = "./Testing/results"

# Patrones de archivos por control
controls = [
    ("c1", "c1-realistic-*/*-qos.csv"),
    ("c2", "c2-realistic-*/*-qos.csv"),
    ("c3", "c3-realistic-*/*-qos.csv"),
    ("c4", "c4-realistic-*/*-qos.csv"),
]

headers_by_control = {}

for control, pattern in controls:
    files = glob.glob(os.path.join(RESULTS_DIR, pattern))
    if not files:
        # Buscar en subcarpetas directas si el patrón anterior no encuentra nada
        files = glob.glob(os.path.join(RESULTS_DIR, f"{control}-realistic-*/{control}-realistic-qos.csv"))
    if files:
        with open(files[0], newline='') as f:
            reader = csv.reader(f)
            headers = next(reader)
            headers_by_control[control] = set(headers)
    else:
        headers_by_control[control] = set()

# Intersección de métricas comunes
global_common = set.intersection(*(h for h in headers_by_control.values() if h))

# Métricas específicas por control
specific_by_control = {c: h - global_common for c, h in headers_by_control.items()}

print("Métricas comunes en todos los controles:")
print(sorted(global_common))
print("\nMétricas específicas por control:")
for c, s in specific_by_control.items():
    print(f"{c}: {sorted(s)}")
