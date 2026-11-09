# Hardware Sprite Renderer (Adaptación 64x64)

Módulo lógico para el dibujado de sprites por hardware mediante una máquina de estados finitos (FSM). Esta adaptación está ajustada para pantallas o matrices de baja resolución.


## Arquitectura FSM (Controlador de Dibujado)

El ciclo de evaluación ocurre por cada línea horizontal (Y=0 a Y=63). Los estados base del sistema son:

* **REG_POS:** Latch de las coordenadas base del sprite.
* **ACTIVE:** Validación de presencia del sprite en el eje Y actual.
* **WAIT_POS:** Sincronización del barrido del hardware con el inicio en X del sprite.
* **SPR_LINE:** Extracción de píxeles desde memoria y activación de la señal de dibujado.
* **WAIT_DATA:** Ciclo de latencia / apagado de señal.
* **IDLE:** Reposo hasta recibir la señal `line == 1` de la siguiente iteración.

## Diagrama de Flujo del Controlador

*(Insertar aquí el diagrama de flujo documentando las transiciones de la FSM)*


# Repositorio Base: Generador de Texto para Pantalla LCD 64x64

Este repositorio contiene la arquitectura mínima en Verilog/VHDL para implementar un generador de caracteres en una pantalla gráfica de 64x64 píxeles utilizando una fuente de 8x8.

---

##  Módulos Principales

* **`sync_counters.v`**: Maneja los contadores del barrido (`CounterX` de 0 a 63, `CounterY` de 0 a 63).
* **`character_ram.v`**: Memoria de $8 \times 8$ (64 bytes) que almacena la matriz de texto ASCII actual a desplegar.
* **`font_rom.v`**: Memoria de solo lectura que almacena el patrón gráfico binario de la tipografía (matriz $8 \times 8$).
* **`lcd_controller.v`**: Orquestador principal que toma las direcciones de lectura, concatena los bus de datos y envía los píxeles a la pantalla.

---

## Mapa de Direccionamiento de Memoria

### Character RAM (RAM de Texto)

* **Capacidad**: 64 bytes (8 columnas $\times$ 8 filas de caracteres).
* **Bus de dirección de lectura (`rd_adr`)**: 6 bits.

$$\text{RAM\_addr} = \{\text{CounterY}[5:3], \text{CounterX}[5:3]\}$$



### Font ROM (ROM de Tipografía)

* **Bus de dirección de lectura (`rd_adr`)**: 11 bits (8 bits del código ASCII + 3 bits de la sub-fila del carácter).

$$\text{ROM\_addr} = \{\text{CharacterRAM\_dout}[7:0], \text{CounterY}[2:0]\}$$





## Estructura de Bloques para Diagrama de Flujo

Estructura secuencial limpia diseñada para ser plasmada directamente en tu diagrama:

1. **[INICIO]**: Señal de Reset / Reloj (`clk`).
2. **[PROCESO]**: Asignar `CounterX = 0`, `CounterY = 0`.
3. **[PROCESO]**: Calcular dirección RAM: `RAM_addr = {CounterY[5:3], CounterX[5:3]}`.
4. **[LECTURA MEMORIA]**: Leer `CharacterRAM` $\rightarrow$ Obtener `char_code` (ASCII).
5. **[PROCESO]**: Calcular dirección ROM: `ROM_addr = {char_code, CounterY[2:0]}`.
6. **[LECTURA MEMORIA]**: Leer `FontROM` $\rightarrow$ Obtener `font_row` (Byte de 8 bits).
7. **[I/O SALIDA]**: Extraer bit del píxel actual según `CounterX[2:0]` $\rightarrow$ Enviar a `pixel_out`.
8. **[PROCESO]**: Incrementar `CounterX = CounterX + 1`.
9. **[DECISIÓN]**: ¿`CounterX == 64`?
* **NO** $\rightarrow$ *[Conectar al Paso 3]*
* **SÍ** $\rightarrow$ Avanzar al Paso 10.


10. **[PROCESO]**: Reiniciar `CounterX = 0` e Incrementar `CounterY = CounterY + 1`.
11. **[DECISIÓN]**: ¿`CounterY == 64`?
* **NO** $\rightarrow$ *[Conectar al Paso 3]*
* **SÍ** $\rightarrow$ Reiniciar `CounterY = 0` $\rightarrow$ *[Conectar al Paso 3]*


---

**Referencias:**
* Arquitectura basada en la documentación original de **fpga4fun**: [Graphic LCD panel 4 - Text](https://www.fpga4fun.com/GraphicLCDpanel4.html)
* Arquitectura original basada en: [Hardware Sprites - Project F](https://projectf.io/posts/hardware-sprites/)