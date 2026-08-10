# Eclipse 2026 — Pipeline de datos en vivo para el eclipse total de Sol en España

**[→ Dashboard en vivo](https://anverpy.github.io/eclipse2026/)**

El **12 de agosto de 2026**, un eclipse total de Sol cruza la España peninsular en una franja estrecha desde A Coruña hasta Palma de Mallorca — el primero visible desde España en décadas. Este proyecto reúne cinco fuentes de datos públicas e independientes a lo largo de ese camino y las republica como un dashboard público y en vivo

Todo el sistema está pensado para funcionar su único día de evento en vivo por unos pocos dólares, sobre una arquitectura serverless de pago por uso, con una alarma de presupuesto activa desde el primer día.

## Qué datos recoge

Cinco fuentes públicas, todas servidas desde la infraestructura propia del proyecto (nunca mediante llamadas directas en vivo a las APIs originales):

| Fuente | Qué mide | Por qué está aquí |
|---|---|---|
| ⚡ **REE** (Red Eléctrica de España) | Generación solar fotovoltaica en tiempo real, España peninsular | Debería caer visiblemente durante la totalidad — la métrica "estrella" |
| 🌡️ **AEMET** (Agencia Estatal de Meteorología) | Temperatura en 10 estaciones a lo largo del camino de totalidad | El eclipse enfría el aire de forma medible al oscurecerse el cielo |
| 🚦 **DGT Tráfico** (Dirección General de Tráfico) | Incidencias activas en carretera, feed oficial nacional | La gente para a mirar — ¿se nota en el comportamiento del tráfico? |
| ☀️ **DGT Cámaras** (Dirección General de Tráfico) | Brillo medio de 9 cámaras oficiales de carretera | El indicador más directo de que el cielo se oscurece de verdad |
| 🔍 **Google Trends** | Interés de búsqueda nacional del término «eclipse» | Atención pública, antes/durante/después |

La cobertura se limita a las 10 ciudades del camino de totalidad, más España peninsular y Palma — no es un dataset a nivel nacional, y es así a propósito.

## 5 Fuentes de Normalización

```
Fetch + normalización → S3 (data lake particionado)
                                                │
                                                ├── Glue Catalog + Athena (consultas SQL ad-hoc)
                                                │
                                                └── Lambda agregadora → bucket S3 público → dashboard en GitHub Pages
```

- **Ingesta**: una Lambda de AWS por fuente, cada una consultando según su propio horario vía **EventBridge Scheduler**, escribiendo directamente en S3 como JSON particionado línea a línea. Sin Kinesis/Firehose/DynamoDB — un evento en vivo con unas pocas decenas de lecturas por minuto no necesita una plataforma de streaming, y cada pieza adicional es más coste y más riesgo el día del evento.
- La **cadencia** se acelera automáticamente durante la totalidad (hasta ~20s para las dos métricas de mayor señal — brillo de cámara e instantánea del dashboard) y queda totalmente inactiva fuera de dos ventanas acotadas: un simulacro el 11 de agosto y el evento real el 12.
- **Almacenamiento y consulta**: S3 como data lake, catalogado en Glue con **partition projection** (sin crawler — el esquema y el particionado se conocen de antemano), consultable ad-hoc mediante Athena con un límite de datos escaneados como salvaguarda de coste.
- **Dashboard público**: una pequeña Lambda `aggregator` destila los datos en bruto en una instantánea JSON pública y ligera, republicada en un bucket S3 público dedicado cada pocos minutos. El dashboard en sí es un único archivo HTML autocontenido — sin frameworks, sin build, gráficos SVG hechos a mano — servido gratis en GitHub Pages.
- **Infraestructura como código**: todo el stack (Lambdas, roles IAM, S3, Glue, Athena, horarios de EventBridge, alarma de presupuesto) está definido en Terraform, así que se puede desplegar o destruir por completo con un solo comando.

## Estructura del repositorio

```
terraform/    infraestructura como código — todos los recursos AWS del proyecto
lambdas/      una carpeta por fuente de datos, más esquema y escritura a S3 compartidos
docs/         el dashboard público (docs/index.html), servido vía GitHub Pages
admin.sh      punto de entrada único para infra y operativa del día a día (ver abajo)
CHANGELOG.md  historial de construcción y decisiones notables, en orden cronológico
```

## Cómo ejecutarlo en local

El dashboard es un archivo estático — sin paso de build:

```bash
./admin.sh preview          # sirve docs/ en http://localhost:8000
```

Las Lambdas de ingesta también pueden ejecutarse totalmente offline contra datos de prueba guardados, sin necesitar credenciales de AWS ni acceso a red:

```bash
./admin.sh local             # ejecuta las 5 fuentes contra fixtures, valida el esquema
./admin.sh local ree         # o solo una fuente
```

## 🚑 Qué queda fuera del alcance, a propósito

**Ingresos en urgencias hospitalarias.** Al principio, los datos de ingresos en urgencias (por nivel de triaje, motivo, hospital) parecían una métrica interesante para correlacionar con el eclipse — pero ninguna fuente en España publica eso en tiempo real, por el motivo obvio de que son datos de salud protegidos. El único portal de datos abiertos que publica algo parecido (Castilla y León, que está en el camino de totalidad) solo lo hace con actualización **mensual**, así que no puede formar parte de un pipeline en vivo.

#### Es importante tener las precauciones adecuadas el día del evento y evitar algún accidente por desconocimiento u omisión, ya que puede representar un riesgo real para los ojos.

Aquí tienes 3 enlaces confiables con precauciones y consejos sobre la seguridad ocular durante un eclipse:

NASA – Eclipse Safety — https://science.nasa.gov/eclipses/safety/
Guía oficial de la NASA sobre cómo observar el eclipse de forma segura, uso de filtros solares certificados y cuándo es seguro mirar sin protección (solo durante la totalidad).
</br></br>American Astronomical Society (AAS) – Eye Safety — https://eclipse.aas.org/eye-safety,.
Explica el estándar ISO 12312-2 para gafas de eclipse, cómo detectar gafas falsificadas, y recomendaciones para fotografiar el eclipse sin dañar la vista o el equipo.
</br></br>American Academy of Ophthalmology – Solar Eclipse Eye Safety — https://www.aao.org/eye-health/tips-prevention/solar-eclipse-eye-safety
Perspectiva médica sobre la retinopatía solar, síntomas de daño ocular tras mirar el sol sin protección, y consejos prácticos (no usar gafas de sol normales, supervisar a los niños, etc.).
## Fuentes de datos y créditos

- Generación eléctrica: [REE ESIOS](https://www.esios.ree.es/)
- Meteorología: [AEMET OpenData](https://opendata.aemet.es/)
- Incidencias y cámaras de tráfico: [NAP-DGT](https://nap.dgt.es/) (Punto de Acceso Nacional, Dirección General de Tráfico)
- Interés de búsqueda: Google Trends
- Mapa del camino de totalidad e imagen de progresión de fases: [Instituto Geográfico Nacional](https://astronomia.ign.es/eclipses-de-sol-y-luna/eclipse-total-sol-de-12-de-agosto-2026)

El historial completo de construcción y las decisiones de diseño están en [CHANGELOG.md](CHANGELOG.md).
