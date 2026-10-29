# Especificación del Display Driver (PPU)

Consola NoNIENTENDO 

Este documento define **qué hace** el Display Driver, **cómo se le habla** y **cómo se decide que algo está bien**. Los diagramas están en [`04 - Diagramas display driver.md`](04%20-%20Diagramas%20display%20driver.md).

---

## 1. Función

El Display Driver es el controlador de video de la consola. Hace dos cosas:

1. **Recibe órdenes por SPI** de la lógica del juego: qué fondo mostrar y qué sprite va en qué posición.
2. **Compone la imagen y la envía al panel HUB75**: dibuja el fondo, pone los sprites encima (sin rectángulos negros), guarda el resultado en un framebuffer y lo muestra de una vez.

La lógica del juego no envia imagenes completas, solo manda identificadores y posiciones. Los píxeles de sprites y fondos están en memorias internas de la FPGA, cargadas desde archivos `.hex`.

## 2. Restricciones y parámetros

| Parámetro | Valor |
|---|---|
| FPGA | Lattice ECP5-25 (Colorlight 5A-75E v8.2) |
| Reloj del sistema | 25 MHz |
| Panel | HUB75E 64×64, escaneo 1/32 (32 pares de filas, 64 columnas) |
| Formato de píxel en memoria | **RGB565**, 16 bits (R[15:11], G[10:5], B[4:0]) |
| Formato hacia el panel | 6 bits por canal (R5 = c[15:11], G6 = c[10:6], B5 = c[4:0]) con PWM global de 32 niveles |
| Enlace de entrada | SPI esclavo, modo 0 (CPOL=0, CPHA=0), MSB primero, solo MOSI (MISO se usará solo para la verficación al iniciar el sistema) |
| Máx. SCK | 5 MHz (≤ clk/5, para muestrear SCK con sincronizador de 2 FF y evitar inestabilidad) |
| Slots de sprites activos | Por definir |
| Sprites en la biblioteca | hasta 256 (`N_SPRITES`), 8192 píxeles en total en `sprite_rom`, calculado con el espacio de memoria reservado, se podría expandir para mas sprites |
| Tamaño de sprite | Variados, maximo 64×64 (toda la pantalla) |
| Fondos en la biblioteca | 4 (`N_BG`) + Menús, cada uno de 64×64 |

> Los valores de `N_SPRITES` y `N_BG` dependen de los juegos. Son parámetros de Verilog; el presupuesto de memoria (sección 9) muestra el margen para subirlos.

## 3. Color transparente (chroma key)

- El color transparente es **#0F081F**, que en RGB565 es **`0x0843`**.
- Conversión de 8 bits por canal a RGB565 por **truncamiento**: `R5 = R>>3`, `G6 = G>>2`, `B5 = B>>3`. Con #0F081F: R=1, G=2, B=3 → `00001 000010 00011` = `0x0843`.
- Un píxel de sprite igual a `0x0843` **nunca se escribe**: queda visible lo que hay debajo (fondo u otro sprite).
- Los fondos no tienen transparencia: todos sus píxeles se dibujan a menos que haya un sprite por encima.
- **Colores reservados:** cualquier color de arte cuyo RGB565 sea `0x0843` es transparente.
- El script de conversión PNG → `.hex` será utilizado antes de cargar los archivos, no se harán conversiones de imagenes dentro de la FPGA.

## 4. Entradas y salidas

| Señal | Dir. | Descripción |
|---|---|---|
| `clk` | in | 25 MHz |
| `rst` | in | Reinicio |
| `spi_cs` | in | Chip select, activo en bajo |
| `spi_sck` | in | Reloj SPI |
| `spi_mosi` | in | Datos, MSB primero |
| `spi_miso` | out | Sin uso, posibilidad en verificación |
| `r0 g0 b0` | out | Color de la mitad superior (filas 0–31) |
| `r1 g1 b1` | out | Color de la mitad inferior (filas 32–63) |
| `clk_out` | out | Reloj de desplazamiento del panel |
| `latch` | out | Pulso que fija la fila desplazada |
| `oe` | out | Output enable, activo en bajo |
| `addr[4:0]` | out | Fila seleccionada (A, B, C, D, E) |

## 5. Protocolo SPI: tramas de 5 bytes

Cada orden que el juego le manda al Display Driver es una trama de **5 bytes (40 bits)**, enviada con `spi_cs` en bajo y el bit más significativo primero. El **primer byte dice qué hacer** y los otros cuatro son los datos de esa orden. Los bytes que una orden no usa se envían en 0.

| Byte 0 (orden) | Nombre | Byte 1 | Byte 2 | Byte 3 | Byte 4 | Qué hace |
|---|---|---|---|---|---|---|
| `0x01` | `SET_SPRITE` | slot | ID del sprite | X | Y | Pone el sprite en esa posición y lo hace visible |
| `0x02` | `SET_BG` | ID del fondo | 0 | 0 | 0 | Elige el fondo |
| `0x03` | `COMMIT` | 0 | 0 | 0 | 0 | Muestra en pantalla todo lo que se configuró |
| `0x04` | `HIDE_SPRITE` | slot | 0 | 0 | 0 | Oculta el sprite de ese slot |

- **Slot** (0 a 15): es la "casilla" donde vive un sprite. Sirve para poder moverlo u ocultarlo después sin tocar los demás. El slot 0 se dibuja encima de los otros.
- **X, Y:** posición de la esquina superior izquierda del sprite; la pantalla va de 0 a 63. Se envían como número con signo de 8 bits..
- **Nada cambia en pantalla hasta recibir `COMMIT`**, así una escena con varios sprites aparece completa y no a medias.
- Una trama que no tenga exactamente 40 bits, o con una orden desconocida, se ignora y se marca error.

Temporización SPI:
Explicación detallada [aquí](https://github.com/KUBIX2026/Display-Driver/blob/main/entregas/entrega_01/01%20-%20Display%20Driver%20timing%20controller.md)

## 6. Registros y memorias

Los registros son las "casillas" donde el Display Driver guarda lo que el juego le pidió. Cada orden SPI escribe en una de ellas. Están dentro de la ventana de memoria asignada al Display (**`0x480000 – 0x4FFFFF`**), así que si más adelante el procesador del juego los quiere escribir directamente por el bus del SoC, el mapa ya está definido.

| Offset (desde `0x480000`) | Registro | Acceso | Qué guarda |
|---|---|---|---|
| `0x000` | `COMMIT` | escritura | Escribir 1 hace que se muestre la imagen |
| `0x004` | `BG_SEL` | lectura/escritura | Número de ID de fondo |
| `0x008` | `STATUS` | lectura | Bit 0: listo (ya mostró el primer fondo). Bit 1: error (trama o dato inválido; queda en 1 hasta el siguiente reset) |
| `0x100 + 4·n` | `SPRITE n` (n = 0 a 15) | lectura/escritura | Bits 7:0 id · 15:8 X · 23:16 Y · 24 visible |

Cada orden SPI escribe en un registro: `SET_SPRITE` → `SPRITE n` · `HIDE_SPRITE` → pone `visible` = 0 · `SET_BG` → `BG_SEL` · `COMMIT` → `COMMIT`.

**Memorias internas** (el juego no las ve; se cargan desde archivos `.hex`, con un color RGB565 de 16 bits por píxel):

| Memoria | Qué contiene |
|---|---|
| Sprites | Los píxeles de todos los sprites y una tabla con el tamaño de cada uno (dónde empieza, ancho y alto) |
| Fondos | Fondos de 64×64 píxeles. Los primeros ID seran asignados a los menús |
| Framebuffer | Dos imágenes completas de 64×64: una se muestra en el panel mientras la otra se está preparando |


## 7. Comportamiento

### 7.1 Composición de la imagen
1. Al recibir `COMMIT` (con el buffer trasero libre) se comienza la secuencia de procesamiento.
2. Se copia el fondo seleccionado al **buffer trasero** (4096 píxeles).
3. Se dibujan los sprites visibles, píxel a píxel y de izquierda a derecha, de arriba abajo. Para cada píxel del sprite:
   - si queda fuera de 0..63 en X o Y → se descarta (recorte);
   - si el color es `0x0843` → se descarta (transparente);
   - en caso contrario se escribe en el buffer trasero.
4. Al terminar, el buffer trasero queda listo y espera el siguiente `frame_start`; entonces **se intercambian** buffer frontal y trasero.

### 7.2 Reglas de superposición y recorte
- **Prioridad:** el **sprite 0 queda siempre arriba**, el sprite 2 abajo, y todos sobre el fondo. Como se dibuja del 2 al 0, lo que el slot 0 cubre con píxeles tapa a los demás.
- Donde un sprite de prioridad alta es transparente (`0x0843`), **se ve el sprite de abajo** (o el fondo). Eso es el comportamiento correcto, no un corte.
- **Recorte (clipping):** los píxeles fuera de la pantalla no se dibujan; el sprite se ve cortado en el borde y **no da la vuelta** al otro lado. Un sprite totalmente fuera no dibuja nada y no es un error.

### 7.3 Inicio
Tras el reset: se limpian los buffers, se compone el fondo 0 (menú basico) sin sprites y se activa `INIT_DONE` con el primer cambio de buffer. Mientras `INIT_DONE`=0 la pantalla permanece apagada.

### 7.4 Salida al panel
El barrido lee **siempre el buffer frontal**, que no cambia durante un frame. La fila se desplaza con `oe` bajo mientras se muestra la anterior; luego `oe`=1, `latch`=1, cambia `addr`, y se vuelve a `oe`=0. `latch` y `addr` solo cambian con `oe`=1 (evita fantasmeo). El tiempo de `oe` bajo es igual en todas las filas. Explicación detallada [aquí](https://github.com/KUBIX2026/Display-Driver/blob/main/entregas/entrega_01/01%20-%20Display%20Driver%20timing%20controller.md)

## 8. Presupuesto numérico

**Refresco del panel** (reloj 25 MHz, 32 pares de filas, 64 columnas, PWM global de 32 niveles, ~8 ciclos de bloqueo por fila — *supuesto a validar en simulación*):

| Reloj de desplazamiento | Ciclos por fila | Ciclos por nivel PWM (32 filas) | Ciclos por frame (32 niveles) | Tiempo | Refresco |
|---|---|---|---|---|---|
| `clk_out` = `clk` (1 ciclo por píxel) | 64 + 8 = 72 | 2304 | 73 728 | 2,95 ms | ≈ 339 Hz |
| `clk_out` = `clk`/2 (2 ciclos por píxel) | 128 + 8 = 136 | 4352 | 139 264 | 5,57 ms | ≈ 179 Hz |

Ambos casos superan el mínimo de 60 Hz fijado como criterio.


## 9. Relación con lo ya implementado

El diseño anterior (entrega 01) escribía **un píxel por trama** con color de 24 bits. Esa parte se **adapta**: la trama deja de llevar color (salvo `SET_BG_COLOR`, útil para reutilizar la prueba de colores con la ESP32), la memoria pasa de 24 a 16 bits por píxel y se añaden la tabla de sprites(indica la resolución de cada sprite), las ROM, el compositor y el doble buffer. Los bloques de salida al panel (`scan_counters`, `delay_unit`, `panel_pwm`) y el receptor SPI se reutilizan. El estado de cada bloque está en el diagrama de bloques y en [`06_seguimiento_y_correcciones.md`](06_seguimiento_y_correcciones.md).

Cambio respecto al diagrama de flujo anterior: ya no hay un estado de hardware "Menú" y otro "Juego" con `CMD_CHANGE_STATE`. El menú es simplemente el fondo 0, y el juego cambia de fondo con `SET_BG` + `COMMIT`.
