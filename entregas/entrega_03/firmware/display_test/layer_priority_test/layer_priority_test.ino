#include <Arduino.h>
#include <SPI.h>

// -------------------- Pines SPI hacia la FPGA --------------------
static const int PIN_SCK  = 18;
static const int PIN_MISO = 19;
static const int PIN_MOSI = 23;
static const int PIN_CS   = 5;
static const uint32_t SPI_HZ = 1000000;

SPIClass displaySPI(VSPI);

// -------------------- Protocolo SPI (40 bits) --------------------
void sendCommand(uint8_t opcode, uint8_t b1 = 0, uint8_t b2 = 0, uint8_t b3 = 0, uint8_t b4 = 0) {
    displaySPI.beginTransaction(SPISettings(SPI_HZ, MSBFIRST, SPI_MODE0));
    digitalWrite(PIN_CS, LOW);
    displaySPI.transfer(opcode);
    displaySPI.transfer(b1);
    displaySPI.transfer(b2);
    displaySPI.transfer(b3);
    displaySPI.transfer(b4);
    digitalWrite(PIN_CS, HIGH);
    displaySPI.endTransaction();
    delayMicroseconds(20);
}

void setBackground(uint8_t id) {
    sendCommand(0x02, id & 0x03, 0, 0, 0);
}

void setSprite(uint8_t slot, uint8_t spriteId, int8_t x, int8_t y) {
    sendCommand(0x01, slot, spriteId, (uint8_t)x, (uint8_t)y);
}

void hideSprite(uint8_t slot) {
    sendCommand(0x04, slot, 0, 0, 0);
}

void setTextCell(uint8_t cell, uint8_t ch, uint16_t color) {
    sendCommand(0x05, cell, ch, (uint8_t)(color >> 8), (uint8_t)(color & 0xFF));
}

void hideTextCell(uint8_t cell) {
    sendCommand(0x06, cell, 0, 0, 0);
}

void commitScene() {
    sendCommand(0x03, 0, 0, 0, 0);
}

void printTextRow(uint8_t row, uint8_t colStart, const char* str, uint16_t color) {
    for (uint8_t i = 0; str[i] != '\0' && (colStart + i) < 8; i++) {
        uint8_t cell = (row * 8) + colStart + i;
        if (str[i] == ' ') hideTextCell(cell);
        else setTextCell(cell, (uint8_t)str[i], color);
    }
}

void setupStaticText() {
    for (uint8_t s = 0; s < 16; s++) hideSprite(s);
    for (uint8_t c = 0; c < 64; c++) hideTextCell(c);

    // Cuatro filas de texto en distintos colores RGB565 como referencia fija
    printTextRow(0, 0, "FPGA PPU", 0xFFFF); // Fila 0 (Y = 0..7): Blanco
    printTextRow(2, 0, "ABCDEF01", 0x07FF); // Fila 2 (Y = 16..23): Cian
    printTextRow(4, 0, "PONG 123", 0x07E0); // Fila 4 (Y = 32..39): Verde
    printTextRow(6, 0, "CAPA 456", 0xF800); // Fila 6 (Y = 48..55): Rojo
}

void setup() {
    Serial.begin(115200);
    delay(300);

    pinMode(PIN_CS, OUTPUT);
    digitalWrite(PIN_CS, HIGH);
    displaySPI.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);
    delay(300);

    setBackground(0);
    setupStaticText();
    commitScene();

    Serial.println("=== Prueba de capas, prioridad y transparencia iniciada ===");
}

void loop() {
    // Coordenadas animadas para demostrar todas las interacciones a la vez
    static int8_t sweepX = -3;   // Empieza parcialmente fuera del borde izquierdo (recorte)
    static int8_t dirX   = 1;
    static uint8_t bgId  = 0;
    static uint16_t step = 0;

    // 1. Slot 5 (prioridad media): Barra blanca fija (ID 1, 4x16) cruzando filas de texto 2 y 3
    setSprite(5, 1, 28, 16);

    // 2. Slot 0 (máxima prioridad): Pelota amarilla (ID 2, 4x4)
    //    - Pasa POR ENCIMA del texto de la Fila 2 (Y = 18)
    //    - Pasa POR ENCIMA de la barra blanca del Slot 5 cuando llega a X = 28
    //    - Se recorta en los bordes X = -3 y X = 62
    setSprite(0, 2, sweepX, 18);

    // 3. Slot 1 (alta prioridad): Damero transparente (ID 3, 4x4 con 0x0843)
    //    - Pasa POR ENCIMA del texto verde (Fila 4, Y = 34) y de la barra blanca (X = 28, Y = 26)
    //    - Permite ver los píxeles de abajo a través de sus cuadros transparentes
    int8_t checkerX = 60 - sweepX;
    setSprite(1, 3, checkerX, 34);
    setSprite(2, 3, sweepX, 26);

    // 4. Slot 10 (baja prioridad, pero aún > Texto): Barra blanca (ID 1) en borde inferior
    //    - Demuestra recorte vertical (Y = 52..67 -> filas 64..67 recortadas) y tapa texto rojo
    setSprite(10, 1, 10, 52);

    commitScene();

    // Avanzar movimiento
    sweepX += dirX;
    if (sweepX >= 62 || sweepX <= -3) {
        dirX = -dirX;
    }

    // Cambiar fondo cada ~4 segundos para ver que texto y sprites se mantienen encima
    step++;
    if (step % 80 == 0) {
        bgId = (bgId + 1) & 0x03;
        setBackground(bgId);
        Serial.printf("Fondo cambiado a BG %u (prioridad: Sprites > Texto > Fondo)\n", bgId);
    }

    delay(50);
}