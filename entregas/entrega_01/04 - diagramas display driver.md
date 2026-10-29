# Diagramas y arquitectura del Display Driver - Versión 2

Consola NoNIENTENDO 
## 1. Contexto del sistema

El Display Driver vive en su propia FPGA. La lógica del juego (en las pruebas, una ESP32; en el sistema final, otra FPGA con el SoC) le manda tramas SPI, y él maneja el panel HUB75.

<img width="1568" height="496" alt="image" src="https://github.com/user-attachments/assets/a7863a6f-2036-4aee-aa1d-8b6fd5e276f4" />


**Partición hardware / software**

| Lado | Responsabilidad |
|---|---|
| Lógica del juego (software) | Reglas del juego, posiciones de los sprites, qué fondo usar, cuándo hacer `COMMIT` |
| Display Driver (hardware) | Guardar la tabla de sprites, componer fondo + sprites con transparencia y recorte, doble buffer, barrido HUB75 y PWM |

2. Bloques internos

Las órdenes entran por el receptor SPI, se guardan en registros y el compositor arma la imagen usando las memorias de fondos y sprites. El barrido lee el buffer ya terminado y lo manda al panel. Verde: ya implementado. Amarillo: diseño.

<img width="1568" height="298" alt="image" src="https://github.com/user-attachments/assets/32f90b66-4ed4-49a9-9b2c-5193eaddc157" />


## 3. Datapath y funcionamiento del compositor

Es la parte central del diseño. Primero copia el fondo. Luego dibuja los sprites del slot 15 al 0, así el slot 0 queda encima. Cada píxel se descarta si cae fuera de la pantalla (recorte) o si vale `0x0843` (`#0F081F`, transparente), y por eso no se ve recuadro negro.

<img width="1130" height="3806" alt="image" src="https://github.com/user-attachments/assets/84d50e3e-7407-49f5-b308-9b622a3a6504" />

## 4. Máquinas de estados

### 4.1 Receptor SPI
`cs` es la línea que la ESP32 baja para avisar que empieza una trama y sube cuando termina. Se aceptan solo tramas de exactamente 40 bits con una orden válida; en cualquier otro caso se ignora la trama y se marca error.

<img width="1176" height="1278" alt="image" src="https://github.com/user-attachments/assets/7f54502a-6d79-47ae-bf33-ff3c4c968b25" />


### 4.2 Compositor

<img width="1568" height="168" alt="image" src="https://github.com/user-attachments/assets/021c4550-cd53-4c23-9cba-00d87b1b3d48" />



## 5. Secuencia de un cuadro de juego

<img width="1568" height="606" alt="image" src="https://github.com/user-attachments/assets/42f81f57-c7e0-4164-8198-b03e55639637" />


## 6. Decisiones de diseño y alternativas

| Decisión | Alternativa considerada | Por qué se eligió esta |
|---|---|---|
| **Componer en un framebuffer** y mostrar la imagen terminada | Decidir fondo/sprite píxel a píxel durante el barrido HUB75 | El barrido necesitaría leer N sprites y el fondo en el mismo ciclo (muchos puertos de memoria y comparadores en paralelo). Componiendo aparte basta 1 lectura y 1 escritura por ciclo, es más fácil de verificar y el panel siempre lee una imagen terminada |
| **Doble buffer** (A/B) con cambio en `frame_start` | Un solo buffer | Con uno solo, el panel mostraría a medias la imagen que se está componiendo (parpadeos, sprites partidos). Cuesta 8 EBR de 56 |
| **Color clave `0x0843`** | Un bit de máscara por píxel (la EBR de 18 bits tiene 2 bits libres) | El bit de máscara no reserva ningún color, pero exige otro formato de `.hex` y de herramientas. El color clave se acordó con el equipo de juegos, mantiene los `.hex` de 16 bits y reserva solo un violeta casi negro. Si hiciera falta ese color, el cambio sería local en el compositor |
| **Sprites y fondos en ROM** (`.hex`) | Subirlos por SPI | La trama se reduce a id + posición y no hay que mover cientos de bytes por cuadro. El costo es que cambiar un gráfico exige regenerar el `.hex` y el bitstream |
| **Coordenadas con signo y recorte por hardware** | Rechazar sprites que no caben | Permite entrar y salir de la pantalla de forma suave y sin lógica en el juego |
| **Un solo `COMMIT` pendiente** | Lista de frames esperando | Si el juego va más rápido que el display, solo importa la escena más reciente; no hay que gestionar una cola |
| **Sin estados de hardware Menú/Juego en el PPU** | FSM con `CMD_CHANGE_STATE` | El menú es el fondo 0. Menos estados y la misma funcionalidad: se cambia de pantalla con `SET_BG` + `COMMIT` |
