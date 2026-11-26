### Diagrama de bloques del Driver (RX + Compositor + TX)

```mermaid
flowchart LR
    MASTER(["Maestro SPI<br/>cs, sck, mosi"])

    subgraph RX["RX: Recepción SPI"]
        SYNC["Sincronizador 25 MHz<br/>+ detector de flancos"]
        SHREG["Registro de 40 bits<br/>+ contador de bits"]
        DEC["spi_decoder<br/>Byte 0: orden<br/>Bytes 1..4: parámetros"]
        SYNC --> SHREG -- "cs sube con 40 bits" --> DEC
    end

    subgraph COMP["Compositor + Doble Buffer"]
        STATE["Estado confirmado<br/>(BG, slots de sprites)"]
        LAYERS["Sprite > Texto > Fondo<br/>filtro de transparencia"]
        BACK["Buffer trasero"]
        FRONT["Buffer frontal"]
        STATE --> LAYERS --> BACK
        BACK <-- "swap al fin de barrido" --> FRONT
    end

    subgraph TX["TX: Controlador HUB75"]
        CTRL["CTRL (FSM)<br/>START, GET_PIXEL, INC_COL,<br/>SEND_ROW, DELAY_ROW, INC_ROW"]
        CNT["Contadores<br/>COL, ROW, count_delay"]
        SR["Registros de desplazamiento<br/>R0G0B0 / R1G1B1"]
        CTRL -- "INC / RST" --> CNT
        CNT -- "ZC, ZR, ZD" --> CTRL
        CTRL -- "PX_CLK_EN" --> SR
    end

    MASTER --> SYNC
    DEC -- "0x01/0x04 sprites<br/>0x02 fondo" --> STATE
    DEC -- "0x03 commit_pulse" --> STATE
    FRONT -- "pixel (col, row)" --> SR
    CNT -- "col, row" --> FRONT
    TX --> PANEL(["Panel LED HUB75 64x64<br/>A–E, LATCH, nOE, CLK, RGB"])
    PANEL -.->|"inicio de cuadro"| COMP
```

*Figura X. Arquitectura del driver: el bloque RX decodifica los comandos SPI, el compositor arma el cuadro en el buffer trasero y el bloque TX lo envía al panel desde el buffer frontal.*
