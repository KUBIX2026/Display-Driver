# Display-Driver (PPU) - Consola NoNIENTENDO

**Repositorio de entregas, avances y código del proyecto**

Este repositorio centraliza el desarrollo del controlador de video (PPU - *Picture Processing Unit*) para el proyecto de la consola NoNIENTENDO, desarrollado para el curso **Diseño Digital 1**. 

El sistema implementa los periféricos RTL en una FPGA Lattice ECP5-25K (Colorlight 5A-75E v8.2) que actúa como puente de hardware, mientras la lógica del videojuego es procesada por un microcontrolador (ESP32) que se comunica a través de un firmware en C/C++.

---

## Índice de Entregas y Documentación

Para cumplir con la metodología *top-down* del curso, la documentación y el diseño se han estructurado en entregas incrementales. A continuación, puedes acceder a los detalles técnicos de cada fase del proyecto:

#### Primera Tarea: Protocolos y Arquitectura
Esta tarea establece las bases teóricas del hardware. Consiste en la explicación detallada del protocolo de comunicación HUB75 para la matriz LED, la arquitectura de la VRAM y cómo se manejarán los sprites y transparencias mediante hardware (Chroma Key).
* **[Ver Documentación Completa de la (Tarea 1)](entregas/entrega_01/01%20-%20Display%20Driver%20timing%20controller.md)**

#### Segunda Tarea: Lógica y Máquina de Estados
Esta tarea documenta el flujo de control del módulo *Display Driver*. Se detalla cómo el sistema funciona como una máquina de estados con dos modos principales: un modo **Menú** (para la interfaz estática) y un modo **Juegos** (para la actualización dinámica a alta velocidad).
* **[Ver Diagramas de Flujo y Estados (Tarea 2)](entregas/entrega_01/02%20-%20Diagrama%20de%20flujo.md)**

### Primera Entrega: Prototipo de Comunicación SPI y Control de Hardware
Esta entrega demuestra la validación en hardware de la arquitectura. Se implementó un firmware en la ESP32 que actúa como Maestro SPI y se comunica con la FPGA enviando tramas gráficas de 40 bits al presionar un botón físico. La FPGA decodifica exitosamente el color (pasando de RGB565 a RGB555) y modula la pantalla HUB75 en tiempo real.
* **[Ver (Entrega 01)](entregas/entrega_01/README.md)**

---

## 🛠️ Estructura del Repositorio

El código fuente, las simulaciones y el firmware están organizados según los lineamientos de la rúbrica del curso:

* **`codigo_verilog_testbench_waveform/`**: Contiene todo el código RTL (Verilog), los testbenches (`_TB.v`), los archivos de ondas (`.gtkw`) y el `Makefile` para la síntesis y simulación.
* **`diagramas_flujo_bloques_estados/`**: Contiene las exportaciones en alta calidad (`.png` y `.pdf`) de los diagramas de la arquitectura general (`top`).
* **`firmware/`**: Contiene el código en C/C++ (ej. `esp32_spi_test.ino`) para el microcontrolador que se encarga de enviar las tramas de prueba por el bus SPI.
* **`entregas/`**: Carpeta histórica con la documentación `.md` y las imágenes de respaldo de las entregas teóricas.

---
