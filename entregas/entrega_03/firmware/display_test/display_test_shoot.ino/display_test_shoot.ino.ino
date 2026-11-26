#include <Arduino.h>
#include <SPI.h>

static const int PIN_SCK  = 18;
static const int PIN_MISO = 19;
static const int PIN_MOSI = 23;
static const int PIN_CS   = 5;
static const int PIN_BTN  = 4;   // Pin D4 del ESP32 (conectar botón entre D4 y GND)

static const uint32_t SPI_HZ = 1000000;

SPIClass displaySPI(VSPI);

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
    sendCommand(0x02, id, 0, 0, 0);
}

void setSprite(uint8_t slot, uint8_t spriteId, int8_t x, int8_t y) {
    sendCommand(0x01, slot, spriteId, (uint8_t)x, (uint8_t)y);
}

void hideSprite(uint8_t slot) {
    sendCommand(0x04, slot, 0, 0, 0);
}

void setTextCell(uint8_t cell, uint8_t character, uint16_t color) {
    sendCommand(0x05, cell, character, (uint8_t)(color >> 8), (uint8_t)(color & 0xFF));
}

void commitScene() {
    sendCommand(0x03, 0, 0, 0, 0);
}

void initScene() {
    setBackground(0);

    // Texto superior en celdas 0..4 (8x8 px cada celda).
    setTextCell(0, 'P', 0xFFFF);
    setTextCell(1, 'P', 0xFFFF);
    setTextCell(2, 'U', 0xFFFF);
    setTextCell(3, 'N', 0xFFFF);
    setTextCell(4, 'G', 0xFFFF);

    // Ocultar bala al inicio.
    hideSprite(2);
    commitScene();
}

void runDemo() {
    int ballX = 30, ballY = 30;
    int vx = 1, vy = 1;

    const int paddleX = 4;
    const int paddleY = 24;

    // Estado de la bala (slot 2).
    bool bulletActive = false;
    int bulletX = 0;
    int bulletY = 0;
    bool lastBtnState = HIGH;

    while (true) {
        // Lectura del botón en D4 (activo en LOW).
        bool btnState = digitalRead(PIN_BTN);
        if (lastBtnState == HIGH && btnState == LOW && !bulletActive) {
            bulletActive = true;
            bulletX = paddleX + 4;   // Sale desde el frente de la pala
            bulletY = paddleY + 6;   // Centrada verticalmente en la pala (16 px de alto)
        }
        lastBtnState = btnState;

        // Actualizar pelota (slot 0) y pala (slot 1).
        setSprite(0, 2, ballX, ballY);
        setSprite(1, 1, paddleX, paddleY);

        // Actualizar bala (slot 2) si está activa.
        if (bulletActive) {
            setSprite(2, 2, bulletX, bulletY);
            bulletX += 2;
            if (bulletX >= 64) {
                hideSprite(2);
                bulletActive = false;
            }
        }

        commitScene();

        // Rebote de la pelota.
        ballX += vx;
        ballY += vy;
        if (ballX <= 0 || ballX >= 60) vx = -vx;
        if (ballY <= 0 || ballY >= 60) vy = -vy;

        delay(40);
    }
}

void setup() {
    pinMode(PIN_CS, OUTPUT);
    digitalWrite(PIN_CS, HIGH);
    pinMode(PIN_BTN, INPUT_PULLUP);

    displaySPI.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);
    delay(500);

    initScene();
    runDemo();
}

void loop() {}