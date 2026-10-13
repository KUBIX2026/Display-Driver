# Protocolos de Comunicación y Control de Pantalla (Display Driver)

> Este repositorio centraliza el desarrollo del controlador de video (PPU) para el proyecto del curso Diseño Digital 1. Las pruebas iniciales, el control de la matriz LED a 8bpp y 5bpp, y los scripts de conversión de imágenes estáticas fueron desarrollados e iterados previamente. Para consultar el historial de commits, los diagramas iniciales y los videos de funcionamiento de esa etapa temprana, referirse a [Repositorio Base: Panel-Led-Image-Changer](https://github.com/Fdiaz718/Panel-Led-Image-Changer).

En este documento se detalla la interfaz de comunicación del módulo Display Driver. Al ser el driver de video del sistema, el bloque maneja dos protocolos distintos: un **Protocolo de Entrada** (para recibir la información gráfica desde la logica del sistema (en este caso, simulado con una ESP32) vía SPI) y un **Protocolo de Salida** (para controlar físicamente la matriz LED HUB75E y manejo de Sprites en tiempo real).

## 1. Restricciones y Parámetros de Diseño
- **Hardware:** FPGA Lattice ECP5-25K (Colorlight 5A-75E v8.2).
- **Panel LED:** HUB75E 64x64, Escaneo 1/32.
- **Reloj Base:** 25 MHz.
- **Profundidad de Color:** Renderizado por hardware a RGB555 (15 bits efectivos) mediante modulación PWM global de 5 bits por canal para evitar el *flicker* (parpadeo) perceptible en frecuencias de barrido altas.
- **Recepción de información:** Protocolo SPI.
- **Manejo de Sprites:** Se define el color "1xFFFF" como color transparente para mostrar correctamente los sprites sin interrumpir el fondo estatico.


## 2. Protocolo de Entrada: SPI y Decodificación Dinámica

La capa física opera bajo el estándar de comunicación SPI en **Modo 0**; sin embargo, el módulo implementa una capa de aplicación basada en una VRAM interna. La CPU (ESP32) no transmite video crudo, sino que efectúa escrituras directas mediante comandos y coordenadas.

### 2.1. Recepción de Datos y Diagrama de Tiempos
El procesador principal actúa como Maestro y la FPGA como Esclavo. La comunicación sigue el diagrama de tiempos estándar:
- `CS` (Chip Select) baja a 0V para iniciar la transmisión activa.
- Los datos gráficos se envían a través de `MOSI` y son muestreados en la FPGA mediante registros de desplazamiento en cada flanco de subida de `SCK`.
- La línea `MISO` se mantiene inactiva (comunicación unidireccional).
- La trama acordada consta de 40 bits (5 bytes) empaquetados así: `[Comando] [ID_Objeto] [Pos X] [Pos Y] [Color/Datos]`.

## 3. Protocolo de Salida: Control HUB75 (Matriz LED)

Una vez decodificada la trama SPI, la información se almacena en la VRAM de la FPGA y se envía al panel LED operando bajo multiplexación constante. El protocolo paralelo exige una sincronización rigurosa de las siguientes señales lógicas:

- **Datos RGB (`R0, G0, B0, R1, G1, B1`):** Se envían 2 píxeles en paralelo (uno para la mitad superior y otro para la mitad inferior).
- **Reloj (`clk_out`):** 64 pulsos de reloj desplazan y llenan los Shift Registers internos de una fila completa.
- **Output Enable (`OE`):** Señal activa en bajo[cite: 8]. Debe ponerse en ALTO (apagar LEDs) mediante una ventana de *blanking* ampliada durante el cambio de fila para descargar la capacitancia parasitaria de los transistores del panel y evitar *ghosting* lumínico.
- **Latch (`LAT`):** Pulso síncrono para fijar los datos enviados a los registros de la pantalla.
- **Dirección (`addr`):** 5 pines (A, B, C, D, E) para seleccionar cuál de las 32 filas físicas de la matriz se va a encender.

### 3.1. Multiplexación de Video y Manejo de Transparencias (Chroma Key)

Para lograr que los sprites (personajes, obstáculos) se superpongan correctamente sobre el fondo del nivel sin mostrar un área rectangular base, la arquitectura de la PPU implementa un **Multiplexor de Video** digital antes de enviar la señal a los pines RGB.

El sistema gráfico procesa la transparencia de la siguiente manera:

1. **Estructura de la Trama:** La lógica del juego (ESP32) envía los comandos de dibujo a través de SPI utilizando la trama estándar de 40 bits: `[Comando] [ID_Objeto] [Pos X] [Pos Y] [Color/Datos]`.
2. **Definición del Color Transparente:** Por convención técnica con el equipo encargado del desarrollo del software, se define un código de color RGB específico (por ejemplo, `0xFFFF`, u otro valor reservado) que el hardware interpreta exclusivamente como "píxel transparente".
3. **Decisión del Hardware (Multiplexor):** Durante el barrido constante de la pantalla, cuando la FPGA lee la coordenada actual de la VRAM para enviarla al panel, el multiplexor evalúa el valor numérico del color del sprite:
   - Si el color **coincide** con el código de transparencia (ej. `0xFFFF`), el multiplexor descarta la información del sprite y conmuta su salida para mostrar el color de la capa de fondo (Background).
   - Si el color **es distinto**, el multiplexor da prioridad a la capa del sprite (Foreground) y lo dibuja en pantalla.

Esta técnica de enmascaramiento por hardware libera por completo a la CPU (ESP32) de calcular colisiones de píxeles o fusiones de imagen, permitiendo que los sprites tengan formas irregulares exactas sin destruir el escenario de fondo.


## 4. Pruebas de Integración y Firmware (ESP32)

Para validar la integridad del bus SPI y la decodificación de color (RGB565 a RGB555) en hardware, se desarrolló un firmware de prueba en C++ (Arduino IDE) para la ESP32. Este código transmite tramas de color de 40 bits activadas aproximadamente cada 3 segundos, o en una segunda versión, por un botón físico con anti-rebote digital, demostrando la separación de responsabilidades entre el procesamiento lógico (ESP32) y el renderizado (FPGA).

**Código de prueba (Ubicado en la carpeta `firmware/`):**
