#include <Arduino.h>
#include <SPI.h>

// Cambiar según el modelo de ESP32 y cableado.
static const int PIN_SCK  = 18;
static const int PIN_MISO = 19;
static const int PIN_MOSI = 23;
static const int PIN_CS   = 5;

static const uint32_t SPI_HZ = 1000000;

SPIClass displaySPI(VSPI);

void sendCommand(
    uint8_t opcode,
    uint8_t b1 = 0,
    uint8_t b2 = 0,
    uint8_t b3 = 0,
    uint8_t b4 = 0
) {
    displaySPI.beginTransaction(
        SPISettings(SPI_HZ, MSBFIRST, SPI_MODE0)
    );

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
    sendCommand(0x02, id, 0, 0, 0);
}

void setSprite(
    uint8_t slot,
    uint8_t spriteId,
    int8_t x,
    int8_t y
) {
    sendCommand(
        0x01,
        slot,
        spriteId,
        (uint8_t)x,
        (uint8_t)y
    );
}

void hideSprite(uint8_t slot) {
    sendCommand(0x04, slot, 0, 0, 0);
}

void setTextCell(
    uint8_t cell,
    uint8_t character,
    uint16_t color
) {
    sendCommand(
        0x05,
        cell,
        character,
        (uint8_t)(color >> 8),
        (uint8_t)(color & 0xFF)
    );
}

void commitScene() {
    sendCommand(0x03, 0, 0, 0, 0);
}

void testScene() {
    setBackground(0);

    // Pala y pelota.
    setSprite(0, 2, 30, 30);
    setSprite(1, 1, 4, 24);

    setTextCell(0, 'P', 0xFFFF);
    setTextCell(1, 'P', 0xFFFF);
    setTextCell(2, 'O', 0xFFFF);
    setTextCell(3, 'N', 0xFFFF);
    setTextCell(4, 'G', 0xFFFF);
    

    commitScene();
}

void pongTest() {
    int ballX = 30;
    int ballY = 30;

    int vx = 1;
    int vy = 1;

    const int paddleX = 4;
    const int paddleY = 24;

    while (true) {
        setSprite(0, 2, ballX, ballY);
        setSprite(1, 1, paddleX, paddleY);
        commitScene();

        ballX += vx;
        ballY += vy;

        if (ballX <= 0 || ballX >= 60)
            vx = -vx;

        if (ballY <= 0 || ballY >= 60)
            vy = -vy;

        delay(50);
    }
}

void setup() {
    pinMode(PIN_CS, OUTPUT);
    digitalWrite(PIN_CS, HIGH);

    displaySPI.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);

    delay(500);

    // Prueba inicial de escena.
    testScene();

    delay(500);

    // Prueba de movimiento.
    pongTest();
}

void loop() {
    // pongTest() mantiene el control.
}
