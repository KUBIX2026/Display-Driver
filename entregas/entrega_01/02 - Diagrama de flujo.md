# Diagrama de Flujo del Display Driver

El siguiente diagrama describe el flujo de la pantalla desde su encendido, pasando por la gestión del menú, hasta el bucle de renderizado en tiempo real donde se realiza la multiplexación entre fondos y sprites.
![Diagrama de flujo](diagramas/diagrama_flujo.png)

El siguiente diagrama muestra la arquitectura del módulo `top` y la interconexión entre la recepción SPI, la VRAM y el control del panel HUB75.

![Diagrama de bloques](diagramas/diagrama_bloques.png)
