# Display Driver (PPU) — Consola NoNIENTENDO

Repositorio de diseño, documentación y desarrollo del controlador de video de la consola **NoNIENTENDO**, para el curso **Diseño Digital 1**.

El Display Driver, también denominado PPU (*Picture Processing Unit*), es el módulo encargado de recibir las órdenes gráficas del sistema de juego, construir la imagen que se mostrará en pantalla y controlar una matriz LED mediante la interfaz HUB75E.

El proyecto utiliza una FPGA Lattice ECP5-25K, implementada en la plataforma Colorlight 5A-75E v8.2, y una ESP32 como plataforma de pruebas para la comunicación SPI.

## Objetivo del proyecto

El diseño del Display Driver se divide en dos funciones principales:

1. **Recepción de comandos por SPI:** recibir las órdenes que indican qué fondo debe utilizarse y qué sprites deben mostrarse, incluyendo sus identificadores y posiciones.
2. **Composición y visualización de la imagen:** combinar el fondo con los sprites, gestionar la transparencia y generar las señales necesarias para controlar el panel LED.

Los píxeles de los gráficos se almacenarán en memorias de la FPGA. De esta manera, el sistema de juego podrá indicar qué elementos deben aparecer y dónde ubicarlos, sin necesidad de transmitir todos los píxeles de cada imagen en cada actualización.

## Plataforma y parámetros principales

| Parámetro | Especificación |
|---|---|
| FPGA | Lattice ECP5-25K |
| Plataforma | Colorlight 5A-75E v8.2 |
| Reloj del sistema | 25 MHz |
| Pantalla | Matriz LED HUB75E de 64 × 64 píxeles |
| Escaneo del panel | 1/32 |
| Interfaz de entrada | SPI esclavo, modo 0 |
| Formato gráfico previsto | RGB565 |
| Color transparente | `#0F081F` (`0x0843` en RGB565) |

## Documentación y entregas

La documentación se organiza en entregas incrementales. La primera se enfoca principalmente en el diseño, la especificación de interfaces, la arquitectura interna y el funcionamiento esperado del Display Driver.

### Entrega 01 — Diseño y especificación

**[Consultar README de la entrega 01](entregas/entrega_01/README.md)**

Esta entrega establece las bases del diseño del periférico. Incluye la definición de los protocolos, el funcionamiento de la interfaz HUB75, la arquitectura propuesta para el compositor de sprites y el plan de verificación.

Documentos principales:

- [00 — Protocolos de comunicación y control de pantalla](entregas/entrega_01/00%20-%20Protocolos%20de%20Comunicaci%C3%B3n%20y%20Control%20de%20Pantalla%20%28Display%20Driver%29.md)
- [01 — Display Driver Timing Controller](entregas/entrega_01/01%20-%20Display%20Driver%20timing%20controller.md)
- [02 — Diagrama de flujo](entregas/entrega_01/02%20-%20Diagrama%20de%20flujo.md)
- [03 — Especificación del Display Driver](entregas/entrega_01/03%20-%20Especificaci%C3%B3n%20del%20Display%20Driver.md)
- [04 — Diagramas del Display Driver](entregas/entrega_01/04%20-%20Diagramas%20display%20driver.md)
- [05 — Plan de pruebas](entregas/entrega_01/05%20-%20Planes%20de%20prueba.md)
- [06 — Seguimiento del Display Driver](entregas/entrega_01/06%20-%20Seguimiento%20del%20Display%20Driver.md)

### Entrega 02 — Avances de implementación

**[Consultar carpeta de la entrega 02](entregas/entrega_02/Readme.md)**

Esta carpeta reúne avances posteriores del código RTL y del firmware de pruebas. Permite dar continuidad a la arquitectura definida en la primera entrega y avanzar hacia su implementación y verificación.

## Arquitectura prevista

El diseño contempla los siguientes bloques funcionales:

- **Receptor SPI:** recibe las tramas enviadas por la ESP32 o por el sistema de juego.
- **Decodificador de comandos:** interpreta las órdenes recibidas y actualiza la información de la escena.
- **Registros de escena:** almacenan el fondo seleccionado y los datos de los sprites activos.
- **Memorias de gráficos:** almacenan los píxeles de los fondos y sprites.
- **Compositor:** genera la imagen final, respetando la transparencia, la posición y la prioridad de los sprites.
- **Framebuffer:** almacena la imagen compuesta para su posterior visualización.
- **Controlador HUB75:** genera las señales de barrido, sincronización y datos RGB para el panel.

La arquitectura se documenta en los diagramas y en la especificación de la entrega 01. Los módulos descritos corresponden al diseño previsto y su implementación se desarrolla progresivamente.

## Transparencia y composición de sprites

Para evitar que los sprites se visualicen como rectángulos opacos, se utiliza un color reservado como clave de transparencia: `#0F081F`, equivalente a `0x0843` en RGB565.

Cuando el compositor encuentra este valor en un píxel del sprite, no escribe ese píxel en la imagen final. De esta manera, se conserva el fondo o el sprite que se encuentre debajo.

El diseño también contempla sprites de diferentes dimensiones, superposición por prioridad y recorte de los píxeles que queden fuera de los límites de la pantalla.

## Código fuente y pruebas

La carpeta `entregas/entrega_01/codigos_verilog_sim/` contiene el prototipo RTL, los módulos de control del panel, el testbench, el archivo de restricciones y el `MAKEFILE`.

La carpeta `entregas/entrega_01/firmware/` contiene programas de prueba para la ESP32 y la comunicación SPI.

Estos archivos documentan los avances de implementación disponibles. Su funcionalidad debe distinguirse de los bloques que forman parte de la arquitectura especificada y que todavía están pendientes de desarrollo o integración.

## Estado del proyecto

El proyecto se desarrolla de forma incremental:

- **Diseño y especificación:** definición de interfaces, restricciones, arquitectura y comportamiento esperado.
- **Implementación:** desarrollo progresivo de los módulos RTL y del firmware asociado.
- **Verificación:** pruebas mediante simulación y, cuando corresponda, validación en la plataforma física.

  
