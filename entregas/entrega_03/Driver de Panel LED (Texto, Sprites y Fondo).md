
#  Driver de Panel LED (Texto, Sprites y Fondo)

Documenta e implementa el controlador lógico encargado del dibujado  y la generación de señales de hardware para el LED. La arquitectura utiliza diagramas de flujo  procesa la pantalla píxel a píxel, evaluando múltiples capas visuales concurrentes.

## Jerarquía de Renderizado

El núcleo del controlador determina el color final de cada coordenada (`col`, `row`) aplicando un orden estricto de prioridad de tres niveles (sprite > texto > fondo):

* **Nivel 1 (Sprite):** El módulo comprueba si en la celda actual hay asignado un sprite y si el píxel específico no es de un color transparente. Si `sprite == 1`, se emite su color `Color_out (R, G, B)` y se descartan las capas inferiores.
* **Nivel 2 (Texto):** Si la capa del sprite está vacía o es transparente, se consulta la matriz de caracteres. Si el píxel forma parte del trazo de una letra (`Pixel_text == 1`), se utiliza el color de fuente asignado.
* **Nivel 3 (Fondo):** En ausencia de sprites o texto, el sistema recurre a la memoria de imagen general, extrayendo el píxel base usando la dirección unificada `PIX_ADDR = {ROW<<6, COL}`.

![Diagrama de flujo](/entregas/imgs/flujo_renderizado.png)
 
###  Vista general del sistema
 
```mermaid
flowchart LR
    MCU["Maestro SPI<br/>(cs, sck, mosi)"] --> RX["Recepción SPI<br/>(spi_receiver + spi_decoder)"]
    RX -- "Estado confirmado<br/>(BG, slots de sprites)" --> COMP["Creación de imagen<br/>(Compositor + Doble Buffer)"]
    RX -- "commit_pulse" --> COMP
    COMP -- "Buffer frontal" --> HUB["Salida HUB75<br/>(matriz LED 64x64)"]
    HUB -- "Inicio de cuadro<br/>(fin de barrido)" --> COMP
```
 
###  Recepción SPI (spi_receiver + spi_decoder)
 
```mermaid
flowchart LR
    IN["cs, sck, mosi"] --> SYNC["Sincronizador a 25 MHz<br/>+ Detector de flancos"]
    SYNC --> SHIFT["Registro de 40 bits<br/>+ Contador de bits"]
    SHIFT -- "cs sube con 40 bits" --> DEC["spi_decoder<br/>Byte 0: Orden<br/>Bytes 1..4: Parámetros"]
    DEC -- "0x01 / 0x04" --> SPR_REG["Slots de Sprites<br/>(slot, id, X, Y / hide)"]
    DEC -- "0x02" --> BG_REG["Registro de Fondo<br/>(id_fondo)"]
    DEC -- "0x03 COMMIT" --> TRIG["Señal commit_pulse<br/>hacia Creación de Imagen"]
```
 
###  Creación de imagen (Compositor + Doble Buffer)
 
```mermaid
flowchart LR
    CMD_IN["Estado confirmado<br/>(BG, slots de sprites)"] --> ADDR_GEN["Generador de direcciones<br/>(coordenadas X, Y, tamaño sprite)"]
    ADDR_GEN --> MEM_BG["Memoria de Fondo (.hex)"]
    ADDR_GEN --> MEM_SPR["Memoria de Sprites (.hex)"]
    MEM_BG --> MUX["Selector de capa y<br/>filtro de transparencia"]
    MEM_SPR --> MUX
    TRANS["Comparador color<br/>== #0F081F (0x0843)"] --> MUX
    MUX --> BACK_BUF["Buffer Trasero<br/>(cuadro en construcción)"]
    BACK_BUF <-- "Intercambio al inicio<br/>de cuadro (fin barrido)" --> FRONT_BUF["Buffer Frontal<br/>(leído por salida HUB75)"]
```
 
