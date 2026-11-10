#  Driver de Panel LED (Texto, Sprites y Fondo)

Documenta e implementa el controlador lógico encargado del dibujado  y la generación de señales de hardware para el LED. La arquitectura utiliza diagramas de flujo  procesa la pantalla píxel a píxel, evaluando múltiples capas visuales concurrentes.

## Jerarquía de Renderizado

El núcleo del controlador determina el color final de cada coordenada (`col`, `row`) aplicando un orden estricto de prioridad de tres niveles (sprite > texto > fondo):

* **Nivel 1 (Sprite):** El módulo comprueba si en la celda actual hay asignado un sprite y si el píxel específico no es de un color transparente. Si `sprite == 1`, se emite su color `Color_out (R, G, B)` y se descartan las capas inferiores.
* **Nivel 2 (Texto):** Si la capa del sprite está vacía o es transparente, se consulta la matriz de caracteres. Si el píxel forma parte del trazo de una letra (`Pixel_text == 1`), se utiliza el color de fuente asignado.
* **Nivel 3 (Fondo):** En ausencia de sprites o texto, el sistema recurre a la memoria de imagen general, extrayendo el píxel base usando la dirección unificada `PIX_ADDR = {ROW<<6, COL}`.

![Diagrama de flujo: Jerarquía de renderizado y algoritmo de prioridad](espacio_para_imagen_flujo_renderizado.png)
*(Reemplaza `espacio_para_imagen_flujo_renderizado.png` con la ruta de tu imagen en el repositorio)*

## Generador de Hardware Sprites

Basado en arquitecturas tradicionales de rasterización por hardware, la pantalla de 64x64 píxeles se segmenta conceptualmente en una cuadrícula de celdas de 8x8 píxeles.

* **Indexación de RAM:** Los bits superiores de las coordenadas de dibujo (`Row[5:3]` y `Col[5:3]`) se concatenan para calcular `ram_addr`, la dirección en la memoria RAM que indica qué `Sprite_ID` ocupa esa celda.
* **Extracción en ROM:** Si el identificador no es 0 (celda vacía), los bits inferiores (`Row[2:0]`) se combinan con el identificador para leer la fila de píxeles correcta desde la ROM del sprite (`Sprite_row`).
* **Manejo de Transparencia:** Cada píxel almacena datos RGB en 3 bits. El valor `000` se designa como canal alfa puro (transparente), forzando a la lógica a ignorar el sprite e imprimir el contenido de la capa inferior.

![Esquemático: Generador de Píxel de Sprite y direccionamiento RAM/ROM](espacio_para_imagen_generador_sprite.png)

## Generador de Texto

Para procesar las fuentes y cadenas de caracteres, se reutiliza la división de celdas de 8x8 con memorias de propósito específico.

* **Decodificación de Caracteres:** La dirección base `Ram_text` apunta a una memoria que devuelve el código ASCII/alfanumérico del carácter (ej. 65 para 'A') contenido en esa cuadrícula.
* **Mapeo de Fuentes:** Se lee un vector binario desde la ROM de fuentes usando la fila del píxel (`font_rom = ROM[ROM_addr]`). Se verifica si el bit posicional correspondiente a `Col[2:0]` está en estado alto (activo) o bajo (vacío) para decidir si se emite el texto o el fondo.

![Esquemático: Generador de Píxel de Texto e indexación de fuentes](espacio_para_imagen_generador_texto.png)

## Síntesis del Driver y Controlador HUB75 (FSM)

La interconexión de la lógica de píxeles con la matriz física se orquesta mediante una máquina de estados finitos (FSM) acoplada a una ruta de datos basada en contadores. El hardware se encarga de bombear ráfagas de 64 píxeles en serie para la mitad superior e inferior de la matriz simultáneamente.

### Contadores (Ruta de datos)

* **COL:** Lleva la cuenta del píxel actual (0 a 63) y su desbordamiento activa la señal `ZC` (Zero Column).
* **ROW:** Maneja la fila activa del panel, mapeada directamente a las señales `A, B, C, D, E`. Su desbordamiento activa `ZR` (Zero Row), indicando el fin del cuadro.
* **count_delay:** Un tercer contador que regula el brillo de la fila comparándose con una constante `DELAY` y disparando la bandera `ZD`.

### Estados de la Máquina de Control (FSM)

* **START / GET_PIXEL:** Reinicia variables y genera un retraso de 1 ciclo para leer la SRAM/BRAM sin colisiones.
* **INC_COL:** Mantiene el habilitador de reloj del panel en alto (`PX_CLK_EN = 1`) cargando secuencialmente cada pixel en los registros de desplazamiento `R0G0B0` y `R1G1B1`.
* **SEND_ROW:** Al finalizar la columna de 64 pixeles, levanta el enganche (`LATCH = 1`) volcando los datos a los LEDs, y activa la emisión del panel (`nOE = 0`).
* **DELAY_ROW:** Bucle que sostiene el estado de encendido (`nOE = 0`) incrementando `count_delay` hasta alcanzar el límite establecido.
* **INC_ROW & READY_FRAME:** Apaga la matriz (`nOE = 1`), avanza de fila y revisa el fin del dibujo (32 ciclos en total al trabajar en paralelo con las mitades superior e inferior).

![Diagrama de Máquina de Estados (FSM) del Driver de Panel](espacio_para_imagen_fsm.png)

![Diagrama de Bloques: Interconexión y Ruta de Datos del Driver](espacio_para_imagen_ruta_de_datos.png)
