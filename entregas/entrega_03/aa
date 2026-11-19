### Diagrama de bloques del Controlador HUB75 (Control + Ruta de datos)

```mermaid
flowchart LR
    subgraph CTRL["CTRL: FSM de control"]
        FSM["START → GET_PIXEL → INC_COL →<br/>SEND_ROW → DELAY_ROW →<br/>INC_ROW → READY_FRAME"]
    end

    subgraph DP["Ruta de datos"]
        COL["COL<br/>contador 0..63"]
        ROW["ROW<br/>contador de fila (A–E)"]
        DLY["count_delay<br/>comparador vs DELAY"]
        PIX["Compositor de píxel<br/>sprite > texto > fondo"]
        SR["Registros de desplazamiento<br/>R0G0B0 / R1G1B1"]
    end

    RES([RES]) --> FSM

    FSM -- "INC_COL / RST_COL" --> COL
    FSM -- "INC_ROW" --> ROW
    FSM -- "INC_DELAY / RST_DELAY" --> DLY

    COL -- "ZC" --> FSM
    ROW -- "ZR" --> FSM
    DLY -- "ZD" --> FSM

    COL -- "col" --> PIX
    ROW -- "row" --> PIX
    PIX -- "RGB (2 mitades)" --> SR

    FSM -- "PX_CLK_EN" --> SR
    FSM -- "LATCH, nOE" --> OUT
    ROW -- "A, B, C, D, E" --> OUT
    SR -- "R0G0B0, R1G1B1" --> OUT
    OUT(["Salida HUB75<br/>matriz LED 64x64"])
```

*Figura X. Diagrama de bloques del controlador: la unidad de control (FSM) genera las señales de incremento, reloj y enganche, y recibe de vuelta las banderas ZC, ZR y ZD desde los contadores.*
