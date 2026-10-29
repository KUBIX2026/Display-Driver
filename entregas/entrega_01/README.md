# Entrega 01: Diseño y especificación del Display Driver (PPU)

**Consola NoNIENTENDO · Diseño Digital 1**
Responsable del módulo: Felipe Diaz

Esta carpeta reúne todo lo de la primera entrega del **Display Driver**, el módulo que se encarga de mostrar el juego en el panel LED. La entrega se enfoca en el **diseño y la especificación**; el código que ya existe sirve como base y como evidencia de que la parte de salida al panel funciona en hardware.

## Estructura de la carpeta

```
entrega_01/
├── README.md                     ← este documento
├── 00 … 06 *.md                  ← documentos de la entrega
├── codigos_verilog_sim/          ← Verilog, testbench, Makefile y pines
├── diagramas/                    ← diagramas iniciales (.png)
└── firmware/                     ← código de prueba para la ESP32
```

## ¿Qué hace el módulo?

El Display Driver hace dos cosas:

1. **Recibe órdenes por SPI** de la lógica del juego (en las pruebas, una ESP32): qué fondo mostrar y qué sprite va en qué posición.
2. **Compone la imagen y la envía al panel HUB75 de 64×64**: dibuja el fondo, pone encima los sprites (que pueden tener tamaños distintos) y trata el color `#0F081F` como transparente, para que los sprites no se vean con un recuadro negro alrededor.

El juego no manda imágenes: manda solo identificadores y posiciones. Los píxeles de los sprites y los fondos viven en memorias de la FPGA cargadas desde archivos `.hex`.

| Dato | Valor |
|---|---|
| FPGA | Lattice ECP5-25K (Colorlight 5A-75E v8.2) |
| Reloj | 25 MHz |
| Panel | HUB75E 64×64, escaneo 1/32 |
| Entrada | SPI esclavo, modo 0, tramas de 40 bits (5 bytes) |
| Color de transparencia | `#0F081F` (`0x0843` en RGB565) |

## Documentos de la entrega

| # | Documento | Qué contiene |
|---|---|---|
| 00 | [Protocolos de comunicación y control de pantalla](00%20-%20Protocolos%20de%20Comunicaci%C3%B3n%20y%20Control%20de%20Pantalla%20%28Display%20Driver%29.md) | Primera versión de los protocolos de entrada (SPI) y de salida (HUB75), y la prueba con la ESP32 |
| 01 | [Timing controller](01%20-%20Display%20Driver%20timing%20controller.md) | Explicación detallada del protocolo HUB75: señales, tiempos, `OE`, `LAT` y antighosting |
| 02 | [Diagrama de flujo](02%20-%20Diagrama%20de%20flujo.md) | Diagrama de flujo inicial y diagrama de bloques del módulo `top` |
| 03 | [Especificación del Display Driver](03%20-%20Especificaci%C3%B3n%20del%20Display%20Driver.md) | Documento central: trama SPI, registros, memorias, errores y presupuesto numérico |
| 04 | [Diagramas del Display Driver](04%20-%20Diagramas%20display%20driver.md) | Contexto, bloques internos, compositor, máquinas de estados, secuencia de un cuadro y decisiones de diseño |
| 05 | [Plan de pruebas](05%20-%20Planes%20de%20prueba.md) | Tabla de pruebas, en construcción |
| 06 | [Seguimiento](06%20-%20Seguimiento%20del%20Display%20Driver.md) | Tareas, responsables y estado |

**Por dónde empezar:** el documento 03 explica qué hace el módulo y cómo se le habla; el 04 muestra cómo está construido por dentro.

## Arquitectura en una vista

Verde: ya implementado y probado. Amarillo: diseñado, por implementar.

<img width="1568" height="298" alt="image" src="https://github.com/user-attachments/assets/c76012a0-e1a7-4e2c-a8c6-e10bf9cd8709" />

Las órdenes entran por el receptor SPI y se guardan en registros. El compositor arma la imagen en un buffer trasero usando las memorias de fondos y sprites, y al inicio del siguiente cuadro los buffers se intercambian. El panel siempre lee una imagen terminada. El detalle de cada bloque está en el documento 04.

## Protocolo de entrada (resumen)

Cada orden es una trama de 5 bytes: el primer byte dice qué hacer y los otros cuatro son los datos.

| Orden | Nombre | Qué hace |
|---|---|---|
| `0x01` | `SET_SPRITE` | Pone un sprite (slot, id, X, Y) |
| `0x02` | `SET_BG` | Elige el fondo |
| `0x03` | `COMMIT` | Muestra en pantalla todo lo configurado |
| `0x04` | `HIDE_SPRITE` | Oculta el sprite de un slot |

Nada cambia en pantalla hasta recibir `COMMIT`, así una escena con varios sprites aparece completa. El formato completo está en la sección 5 del documento 03.

## Código incluido

Todo está en [`codigos_verilog_sim/`](codigos_verilog_sim).

| Archivo | Función | Estado |
|---|---|---|
| [`top.v`](codigos_verilog_sim/top.v) | Módulo superior: conecta el receptor SPI, el decodificador, el barrido, el PWM y el control de tiempos | Hecho |
| [`spi_receiver.v`](codigos_verilog_sim/spi_receiver.v) | Sincroniza `cs`, `sck` y `mosi`, desplaza 40 bits en cada flanco de subida de `sck` y entrega la trama cuando `cs` sube | Hecho |
| [`spi_decoder.v`](codigos_verilog_sim/spi_decoder.v) | Decodifica la trama. Hoy entiende el comando de color de la etapa de prueba (`0x01` + color RGB565) | Hecho para la etapa de prueba; se adapta a las órdenes de la sección anterior |
| [`scan_counter.v`](codigos_verilog_sim/scan_counter.v) | Contadores de columna (0–63), fila (0–31), nivel PWM (0–31) y dirección de fila | Hecho |
| [`delay_unit.v`](codigos_verilog_sim/delay_unit.v) | Genera `clk_out`, `latch` y `oe` con el apagado entre filas para evitar ghosting | Hecho |
| [`panel_pwm.v`](codigos_verilog_sim/panel_pwm.v) | Convierte cada color a encendido/apagado según el nivel PWM, para la mitad superior e inferior | Hecho |
| [`top_TB.v`](codigos_verilog_sim/top_TB.v) | Testbench: envía una trama SPI y deja correr el barrido | Hecho |
| [`MAKEFILE`](codigos_verilog_sim/MAKEFILE) | Síntesis (Yosys, NextPNR, Ecppack), programación y simulación | Hecho |
| [`constraints.lpf`](codigos_verilog_sim/constraints.lpf) | Asignación de pines de la FPGA (reloj, SPI y conector HUB75) | Hecho |

**Pendientes de implementar** (ya están especificados en los documentos 03 y 04): compositor, memorias de sprites y fondos, y doble buffer.

### Cómo simular y sintetizar

Desde la carpeta `codigos_verilog_sim`:

```bash
make sim       # simula con Icarus Verilog y genera el archivo de ondas
make view      # abre las ondas en GTKWave
make           # sintetiza y genera el bitstream
make program   # programa la Colorlight 5A-75E
```

Herramientas necesarias: Icarus Verilog, GTKWave, Yosys, NextPNR-ECP5, Ecppack y openFPGALoader.

## Firmware de prueba (ESP32)

Hace de maestro SPI y manda tramas de 40 bits a la FPGA. Está en [`firmware/`](firmware).

| Archivo | Qué hace |
|---|---|
| [`test_spi.ino`](firmware/test_spi.ino) | Cambia el color de todo el panel cada vez que se presiona un botón (con antirrebote) |
| [`test_cambio_color.ino`](firmware/test_cambio_color.ino) | Recorre un degradado de colores de forma continua, como prueba de estrés del bus SPI |

Pines de la ESP32: MOSI = 23, SCK = 18, CS = 5.

## Evidencia

- **Videos del panel funcionando con la ESP32:** [cambio automático](../imgs/test_cambio_auto.mp4) y [cambio con botón](../imgs/test_cambio_boton.mp4).
- **Diagrama de tiempos SPI:** [`spi_timing.png`](../imgs/spi_timing.png).
- **Diagramas de tiempos HUB75:** [`wd1.png`](../imgs/wd1.png) y [`wd2.png`](../imgs/wd2.png).
- **Diagramas iniciales:** [`diagrama_bloques.png`](diagramas/diagrama_bloques.png) y [`diagrama_flujo.png`](diagramas/diagrama_flujo.png).
- **Versión de este módulo con commits originales:** [Panel-Led-Image-Changer](https://github.com/Fdiaz718/Panel-Led-Image-Changer).



Las imágenes y los videos de apoyo están en [`../imgs/`](../imgs). La siguiente entrega continúa en [`../entrega_02/`](../entrega_02).
