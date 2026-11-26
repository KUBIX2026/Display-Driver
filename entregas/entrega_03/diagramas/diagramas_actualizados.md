# Diagramas actualizados (entrega 03)

Cada diagrama dice a qué módulo/estado/señal del código corresponde y qué test
lo verifica. Los colores siguen los del `04 - Diagramas`: verde = implementado y
probado, amarillo = registros/memorias, azul = diagrama de estados.

---

## 1. Secuencia de un cuadro  (reemplaza «Secuencia de un cuadro»)

Cambio: aparece `SET_TEXT`, y el compositor arma fondo → texto → sprites.

```mermaid
flowchart TD
    subgraph A["Mientras tanto, el panel sigue mostrando el cuadro anterior"]
        S1["1. El juego manda SET_BG, SET_TEXT y SET_SPRITE<br/>(solo se guardan en los registros shadow)"]
        S2["2. El juego manda COMMIT<br/>(la escena está lista)"]
        S3["3. El compositor arma la escena en el buffer trasero<br/>fondo → texto → sprites 15…0"]
        S1 --> S2 --> S3
    end
    S4["4. Llega el inicio del cuadro:<br/>se intercambian los buffers"]
    S5["5. El panel muestra la escena nueva<br/>(el buffer que era trasero)"]
    S3 --> S4 --> S5
```

Código: `spi_decoder.v` (órdenes 01–06), `scene_compositor.v` (shadow → `snapshot_scene`
→ render), swap en estado `ST_WAIT` con `frame_start`.
Tests: `pending_commit_TB.v`, `spec_rules_TB.v`.

---

## 2. Contexto del sistema  (cambio menor)

Cambio: la ROM incluye la fuente de texto.

```mermaid
flowchart LR
    subgraph D["FPGA Display: ECP5-25K · clk 25 MHz"]
        ROM[("ROM .hex<br/>fondos, sprites y fuente")]
        DD["Display Driver (PPU)"]
        ROM -->|lee píxeles| DD
    end
    subgraph G["FPGA de juego: SoC femtoRV32 + firmware C"]
        L["Lógica del juego<br/>(en pruebas: ESP32)"]
    end
    L -->|"SPI modo 0 · CS, SCK, MOSI · tramas de 40 bits"| DD
    DD -->|"R0 G0 B0 R1 G1 B1 · CLK, LAT, OE, A..E"| P["Panel HUB75E 64×64<br/>escaneo 1/32"]
```

---

## 3. Máquina de estados del compositor  (reemplaza «FSM del compositor»)

Cambios: (a) el arranque va a FONDO (renderiza el fondo 0 antes de `INIT_DONE`);
(b) aparece TEXTO; (c) SPRITES se descompone en SLOT, META y SPR;
(d) un COMMIT que llegó durante el render (pendiente) reinicia el render directamente
desde ESPERA, sin pasar por LIBRE.

```mermaid
flowchart LR
    R(["Inicio / reset"]) --> F
    L["LIBRE<br/>ST_IDLE<br/>espera un COMMIT"]
    F["FONDO<br/>ST_BG<br/>copia 4096 px"]
    T["TEXTO<br/>ST_TEXT<br/>recorre 4096 px"]
    S["SLOT<br/>ST_SLOT<br/>slot 15 → 0"]
    M["META<br/>ST_META<br/>lee tamaño y base"]
    P["SPRITE<br/>ST_SPR<br/>dibuja los píxeles"]
    W["ESPERA<br/>ST_WAIT<br/>espera inicio de cuadro"]
    L -->|COMMIT| F
    F -->|"fondo copiado"| T
    T -->|"texto dibujado"| S
    S -->|"slot visible"| M
    S -->|"slot oculto: siguiente slot"| S
    M -->|"tamaño leído"| P
    P -->|"sprite listo: siguiente slot"| S
    S -->|"último slot (0)"| W
    P -->|"último slot (0)"| W
    W -->|"inicio de cuadro: intercambia buffers"| L
    W -->|"inicio de cuadro y COMMIT pendiente"| F
```

Código: `localparam ST_*` y `case (state)` en `scene_compositor.v`.
Tests: `framebuffer_TB.v` (FONDO), `pending_commit_TB.v` (flecha ESPERA→FONDO),
`spec_rules_TB.v` (TEXTO/SLOT/META/SPR).

---

## 4. Datapath del compositor  (reemplaza «Datapath del compositor»)

Cambio: se agrega el paso 2 (texto) entre fondo y sprites.

```mermaid
flowchart TD
    A(["COMMIT recibido"]) --> B["1. Copiar el fondo<br/>al buffer trasero"]
    B --> C["2. Dibujar el texto: celdas 8×8<br/>si el bit de la fuente vale 1,<br/>escribir el color de la celda"]
    C --> D["3. Tomar el siguiente sprite visible<br/>(del slot 15 al 0)"]
    D --> E["4. Tomar el siguiente píxel del sprite<br/>posición en pantalla = X+i, Y+j"]
    E --> F{"¿Está dentro<br/>de la pantalla?"}
    F -->|no| K
    F -->|sí| G["Leer el color del sprite"]
    G --> H{"¿Es 0x0843<br/>(#0F081F)?"}
    H -->|"sí, transparente"| K
    H -->|no| I["Escribir el color<br/>en el buffer trasero"]
    I --> K{"¿Quedan píxeles<br/>en este sprite?"}
    K -->|sí| E
    K -->|no| L{"¿Quedan sprites?"}
    L -->|sí| D
    L -->|no| M(["Listo: pedir intercambio<br/>de buffers"])
```

Código: etapa 1 del pipeline en `scene_compositor.v` (`always @*` del puerto de
escritura: `bg_v`, `txt_v`, `spr_v`; recorte `spr_inside`; transparencia
`spr_rd != TRANSPARENT`). Las ROM tienen 1 ciclo de latencia, por eso el
dato se escribe un ciclo después de presentar la dirección.
Test: `spec_rules_TB.v` + `tools/ref_model.py` (4096 píxeles).

---

## 5. Bloques internos  (reemplaza «Bloques internos»)

Cambios: registros de texto, fuente en las memorias fijas, y todo pasa a verde
(ya está implementado y simulado). Se indica la memoria real de cada bloque.

```mermaid
flowchart LR
    RX["Receptor SPI<br/>spi_receiver.v"]:::ok
    DEC["Decodificador de órdenes<br/>spi_decoder.v"]:::ok
    REG["Registros shadow<br/>BG_SEL · 16 sprites · 64 celdas de texto · STATUS<br/>(registros, scene_compositor.v)"]:::mem
    ROM[("Memorias fijas · EBR<br/>fondos · sprites · tamaños · fuente")]:::mem
    COMP["Compositor<br/>scene_compositor.v<br/>fondo → texto → sprites"]:::ok
    FB[("Framebuffer A / B<br/>2 × (2048 + 2048) × 16 bits · 8 EBR")]:::mem
    SCAN["Barrido HUB75 + PWM<br/>scan_counter.v · panel_pwm.v · delay_unit.v"]:::ok
    PAN["Panel"]:::pan
    RX --> DEC --> REG --> COMP
    ROM --> COMP
    COMP --> FB --> SCAN --> PAN
    classDef ok fill:#4CAF50,stroke:#2e7d32,color:#fff;
    classDef mem fill:#FFF3B0,stroke:#b59b00,color:#000;
    classDef pan fill:#ECECFF,stroke:#9370DB,color:#000;
```

Presupuesto de memoria medido en la síntesis (ECP5-25K): **29 de 56 EBR**
(fondos 13, sprites 7, fuente 1, framebuffers 8; la tabla de tamaños de sprites
queda en LUTs). Lógica: **31 % de las LUTs**.

---

## 6. Receptor SPI  (cambio menor)

Cambio: el error también ocurre con **más** de 40 bits (`overflow` en `spi_receiver.v`)
y cuando los bytes no usados de una orden no son 0 (`spi_decoder.v`).

```mermaid
flowchart TD
    R(["Inicio / reset"]) --> E1["ESPERA<br/>no hay trama en curso"]
    E1 -->|"cs baja"| RC["RECIBE<br/>cuenta los bits que llegan"]
    RC -->|"cs sube con 40 bits"| DC["DECODIFICA<br/>revisa la orden"]
    RC -->|"cs sube con menos o más de 40 bits"| ER
    DC -->|"orden válida: escribe el registro"| E1
    DC -->|"orden o dato inválido"| ER["ERROR<br/>STATUS.error = 1 (sticky)"]
    ER -->|"se ignora la trama"| E1
```

Tests: `spi_receiver_TB.v`, `spi_invalid_TB.v` (15 casos).

---

## 7. Barrido HUB75  (reemplaza «Flujo de renderizado» y la FSM de CONTROL)

El código **no** tiene FSM de control ni decide capa por píxel: hay tres contadores
libres y la lectura del framebuffer ya compuesto. La capa (sprite > texto > fondo)
se decide al componer (diagrama 4), no durante el barrido.

```mermaid
flowchart LR
    CNT["scan_counters<br/>col 0..63 · scan_row 0..31 · pwm_level 0..31<br/>addr_out · frame_start"]:::ok
    FBR[("Framebuffer frontal<br/>lectura síncrona (EBR)<br/>mitad superior e inferior a la vez")]:::mem
    PIPE["Registros de 1 ciclo<br/>col_d · addr_d · pwm_d"]:::ok
    PWM["panel_pwm<br/>canal = 1 si valor5 > pwm_d"]:::ok
    DLY["delay_unit<br/>latch · oe · clk_out = ~clk"]:::ok
    PAN["Panel HUB75<br/>R0G0B0 R1G1B1 · A..E · CLK LAT OE"]:::pan
    CNT -->|"col, scan_row"| FBR
    CNT --> PIPE
    FBR -->|"pix_top, pix_bottom"| PWM
    PIPE --> PWM
    PIPE --> DLY
    PWM -->|"r0 g0 b0 r1 g1 b1"| PAN
    DLY --> PAN
    PIPE -->|"addr"| PAN
    classDef ok fill:#4CAF50,stroke:#2e7d32,color:#fff;
    classDef mem fill:#FFF3B0,stroke:#b59b00,color:#000;
    classDef pan fill:#ECECFF,stroke:#9370DB,color:#000;
```

Una línea (64 ciclos de 25 MHz), según `delay_unit.v` y `scan_counter.v`:

| ciclo (`col_d`) | pixel desplazado | `latch` | `oe` | `addr` |
|---|---|---|---|---|
| 0 | columna 0 | 0 | 1 (apagado) | cambia a la fila ya latcheada |
| 1 … 62 | columnas 1 … 62 | 0 | 0 (encendido) | estable |
| 63 | columna 63 | 1 | 1 (apagado) | estable |

Cuentas (reemplazan la tabla de refresco de la sección 8 del `03`):
64 ciclos por línea × 32 líneas × 32 niveles PWM = **65 536 ciclos = 2,62 ms ≈ 381 Hz**.
El brillo máximo es 31/32 y la oe queda encendida 62 de cada 64 ciclos.
Tests: `hw_check_TB.v` (columnas en los pines), `spec_rules_TB.v`.

---

## 8. Cambios de texto en `03 - Especificación`

| Sección | Cambio |
|---|---|
| 5 (órdenes) | agregar `0x05 SET_TEXT` (celda, carácter, color RGB565) y `0x06 HIDE_TEXT` (celda) |
| 4 (puertos) | `spi_miso` no está implementado: marcar «reservado» o quitar |
| 6 (STATUS) | bit 0 = `init_done`, bit 1 = `error` son señales internas, no pines |
| 8 (refresco) | 64 ciclos por línea, 2 de apagado, 381 Hz (ver diagrama 7) |
| nueva | presupuesto de memoria: 29/56 EBR, 31 % LUTs |
| 7.4 | `oe` en bajo durante 62 de 64 ciclos (el `01` dice «ancho − 3») |
