# Justificacion Metodologica: Uso de HTTP en C2, C3 y C4

Fecha: 2026-05-09
Proyecto: muBench
Estado: Aprobado para cierre de experimentacion actual

## 1. Decision experimental

Se mantiene el diseno actual de campaña:

1. C1 ejecutado con HTTPS en el borde (cliente -> gateway/ingress).
2. C2, C3 y C4 ejecutados con HTTP en el borde (cliente -> NodePort).
3. En C2, el cifrado relevante del control se aplica internamente mediante mTLS entre servicios.

Esta configuracion se considera metodologicamente valida para los objetivos actuales del estudio.

## 2. Justificacion tecnica

La comparacion principal del estudio es intra-control, no inter-control.

1. C1 evalua la capa de entrada (API Gateway/Ingress), donde HTTPS forma parte natural del mecanismo evaluado.
2. C2 evalua overhead de service mesh/mTLS interno, independiente de si el borde cliente entra por HTTP o HTTPS.
3. C3 evalua Network Policies (L3/L4), que no dependen de cifrado TLS para su funcionamiento.
4. C4 evalua Rate Limiting, que funciona en HTTP y HTTPS; el mecanismo de limitacion no requiere TLS para ser valido.

Por lo tanto, mantener HTTP en C2/C3/C4 no invalida la medicion del efecto del control en esta fase.

## 3. Control de sesgo

Para preservar objetividad se aplican estas reglas:

1. Homogeneidad por familia de control:
   C1: todas sus variantes con HTTPS.
   C2: todas sus variantes con el mismo esquema de borde (HTTP) y mTLS interno cuando corresponda.
   C3: todas sus variantes con HTTP.
   C4: todas sus variantes con HTTP.
2. Comparaciones permitidas solo dentro del mismo control.
3. Comparaciones entre controles se reportan como descriptivas y no inferenciales, salvo normalizacion explicita.

Con estas reglas, no se introduce sesgo sistematico en la comparativa interna de cada control.

## 4. Alcance y limitaciones declaradas

1. El diseno actual prioriza aislamiento del efecto de cada control y reproducibilidad local.
2. No representa todavia un perfil edge completamente productivo para C2/C3/C4 (donde normalmente hay TLS externo).
3. Esta limitacion queda declarada y no compromete la validez de las conclusiones intra-control.

## 5. Trabajo futuro propuesto

Se define como siguiente etapa una campaña adicional con HTTPS en el borde para C2/C3/C4, manteniendo el resto de condiciones constantes.

Objetivo de la etapa futura:

1. Cuantificar costo adicional de TLS externo sobre controles ya evaluados.
2. Contrastar resultados de aislamiento experimental vs realismo operativo.
3. Reportar diferencias en latencia p95, error rate, throughput y consumo de CPU/memoria.

## 6. Texto listo para informe/tesis

Se adopto un enfoque de comparacion intra-control para preservar validez metodologica. C1 se ejecuto con HTTPS por corresponder a controles de capa de entrada, mientras que C2, C3 y C4 se ejecutaron con HTTP en el borde y, en el caso de C2, con mTLS interno entre servicios. Dado que el objetivo fue medir el efecto propio de cada control bajo condiciones homogeneas dentro de su familia, el diseno no introduce sesgo en las comparativas internas. La incorporacion de HTTPS en C2/C3/C4 se establece como trabajo futuro para extender la validez externa hacia escenarios de produccion con cifrado extremo a extremo.

## 7. Conclusiones ejecutivas

1. Se puede continuar y cerrar la experimentacion actual sin problema metodologico.
2. Los resultados obtenidos son validos para comparativas internas de C1, C2, C3 y C4.
3. HTTPS global para C2/C3/C4 queda correctamente definido como extension futura del estudio.
