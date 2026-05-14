# ANOVA Factorial Completo (con bloqueo por dia)

## Diseno aplicado
- Factores fijos: control (4), variant_level (3), vus (4).
- Interacciones: dobles y triple (modelo factorial completo).
- Bloque: day (2026-05-09, 2026-05-10) para controlar variacion entre corridas.
- Observaciones: 96 (48 por dia).

## Formula del modelo
- y ~ C(control) * C(variant_level) * C(vus) + C(day)

## Hallazgos significativos (p < 0.05)
- avg_ms | C(control) | F=368.1908, p=1.23057e-32, eta_p2=0.9592
- avg_ms | C(control):C(variant_level) | F=88.0624, p=7.23219e-24, eta_p2=0.9183
- avg_ms | C(vus_f) | F=115.8279, p=1.01412e-21, eta_p2=0.8809
- avg_ms | C(variant_level) | F=22.6030, p=1.32575e-07, eta_p2=0.4903
- avg_ms | C(control):C(vus_f) | F=8.4590, p=2.23749e-07, eta_p2=0.6183
- avg_ms | C(day) | F=23.9464, p=1.20473e-05, eta_p2=0.3375
- avg_ms | C(control):C(variant_level):C(vus_f) | F=4.1237, p=4.80657e-05, eta_p2=0.6123
- avg_ms | C(variant_level):C(vus_f) | F=3.7389, p=0.00402239, eta_p2=0.3231
- cpu_mcores | C(vus_f) | F=109.5920, p=3.16616e-21, eta_p2=0.8749
- cpu_mcores | C(control) | F=13.6474, p=1.56432e-06, eta_p2=0.4656
- cpu_mcores | C(control):C(variant_level) | F=3.2885, p=0.00876322, eta_p2=0.2957
- cpu_mcores | C(control):C(vus_f) | F=2.7350, p=0.0118319, eta_p2=0.3437
- err_pct | C(control) | F=809850103.1927, p=3.01483e-181, eta_p2=1.0000
- err_pct | C(control):C(variant_level) | F=221238842.2720, p=2.50137e-173, eta_p2=1.0000
- err_pct | C(variant_level) | F=221238842.2720, p=1.30572e-164, eta_p2=1.0000
- err_pct | C(control):C(vus_f) | F=21283201.2120, p=3.40196e-152, eta_p2=1.0000
- err_pct | C(control):C(variant_level):C(vus_f) | F=13414891.4881, p=1.80774e-151, eta_p2=1.0000
- err_pct | C(variant_level):C(vus_f) | F=13414891.4881, p=1.00952e-144, eta_p2=1.0000
- err_pct | C(vus_f) | F=21283201.2120, p=4.14855e-144, eta_p2=1.0000
- mem_mib | C(day) | F=49.3849, p=7.42671e-09, eta_p2=0.5124
- mem_mib | C(control) | F=7.3829, p=0.000375606, eta_p2=0.3203
- mem_mib | C(vus_f) | F=2.8618, p=0.04669, eta_p2=0.1545
- p95_ms | C(vus_f) | F=122.9923, p=2.92473e-22, eta_p2=0.8870
- p95_ms | C(control) | F=119.8237, p=5.02801e-22, eta_p2=0.8844
- p95_ms | C(control):C(variant_level) | F=32.3841, p=4.15998e-15, eta_p2=0.8052
- p95_ms | C(control):C(vus_f) | F=11.3728, p=3.35391e-09, eta_p2=0.6853
- p95_ms | C(control):C(variant_level):C(vus_f) | F=4.0701, p=5.58561e-05, eta_p2=0.6092
- p95_ms | C(variant_level) | F=11.0499, p=0.000116574, eta_p2=0.3198
- p95_ms | C(day) | F=9.0682, p=0.00417671, eta_p2=0.1617
- p95_ms | C(variant_level):C(vus_f) | F=2.5110, p=0.0343832, eta_p2=0.2427
- rps | C(vus_f) | F=1075950.0442, p=1.2009e-113, eta_p2=1.0000
- rps | C(control) | F=150.0038, p=4.50673e-24, eta_p2=0.9054
- rps | C(control):C(vus_f) | F=40.7100, p=3.20155e-19, eta_p2=0.8863
- rps | C(control):C(variant_level) | F=35.4232, p=7.75382e-16, eta_p2=0.8189
- rps | C(control):C(variant_level):C(vus_f) | F=9.1015, p=6.42274e-10, eta_p2=0.7771
- rps | C(variant_level) | F=7.7357, p=0.00124678, eta_p2=0.2477
- rps | C(day) | F=11.0683, p=0.0017114, eta_p2=0.1906

## Nota metodologica
- Esta configuracion mejora el rigor al introducir replicacion via dos dias y bloqueo por dia.
- Para valor academico alto, se recomienda >=3 repeticiones por celda para robustez inferencial.

## Archivos
- Testing/results/scaling_tests/anova_factorial_full_blocked_by_day_20260510.csv
- Testing/results/scaling_tests/anova_factorial_matrix_20260510.csv