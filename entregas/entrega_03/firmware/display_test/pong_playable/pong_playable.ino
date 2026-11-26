#include <Arduino.h>
#include <SPI.h>
#include <NimBLEDevice.h>

// -------------------- Pines SPI hacia la FPGA --------------------
static const int PIN_SCK  = 18;
static const int PIN_MISO = 19;
static const int PIN_MOSI = 23;
static const int PIN_CS   = 5;
static const uint32_t SPI_HZ = 1000000;

SPIClass displaySPI(VSPI);

// -------------------- Estado BLE HID --------------------
static NimBLEAdvertisedDevice* targetKeyboard = nullptr;
static bool doConnect   = false;
static bool kbConnected = false;

volatile bool keyUp   = false;
volatile bool keyDown = false;

static uint32_t totalPackets = 0;
static unsigned long lastSummary = 0;

// Códigos USB HID Usage ID (página 0x07)
static const uint8_t HID_KEY_ARROW_DOWN = 0x51;
static const uint8_t HID_KEY_ARROW_UP   = 0x52;
static const uint8_t HID_KEY_S          = 0x16;
static const uint8_t HID_KEY_W          = 0x1A;

static inline bool checkUsageBitmap(const uint8_t* buf, size_t len, size_t offset, uint8_t usage) {
    size_t byteIdx = offset + (usage >> 3);
    if (byteIdx >= len) return false;
    return (buf[byteIdx] & (1U << (usage & 0x07))) != 0;
}

// Callback de teclas desde el NuPhy Air75 (soporta 6KRO y NKRO)
void hidNotifyCB(NimBLERemoteCharacteristic* pChr, uint8_t* pData, size_t length, bool isNotify) {
    bool up = false;
    bool down = false;

    if (length == 8 || length == 9) {
        size_t startIdx = (length == 9) ? 3 : 2;
        for (size_t i = startIdx; i < length; i++) {
            uint8_t code = pData[i];
            if (code == HID_KEY_ARROW_UP || code == HID_KEY_W)     up = true;
            if (code == HID_KEY_ARROW_DOWN || code == HID_KEY_S) down = true;
        }
    } else if (length >= 14) {
        size_t offset = (length == 16) ? 2 : 1;
        up   = checkUsageBitmap(pData, length, offset, HID_KEY_ARROW_UP) ||
               checkUsageBitmap(pData, length, offset, HID_KEY_W);
        down = checkUsageBitmap(pData, length, offset, HID_KEY_ARROW_DOWN) ||
               checkUsageBitmap(pData, length, offset, HID_KEY_S);
    }

    keyUp = up;
    keyDown = down;
}

class ClientCallbacks : public NimBLEClientCallbacks {
    void onConnect(NimBLEClient* pClient) override {
        Serial.println("[BLE] Conectado al teclado. Negociando enlace seguro...");
    }
    void onDisconnect(NimBLEClient* pClient, int reason) override {
        Serial.printf("[BLE] Desconectado (razon=%d). Reanudando escaneo...\n", reason);
        kbConnected = false;
        keyUp = false;
        keyDown = false;
        if (targetKeyboard) {
            delete targetKeyboard;
            targetKeyboard = nullptr;
        }
        NimBLEDevice::getScan()->start(0, false);
    }
};

class ScanCallbacks : public NimBLEScanCallbacks {
    void onResult(const NimBLEAdvertisedDevice* advertisedDevice) override {
        totalPackets++;
        if (doConnect || kbConnected) return;

        std::string name = advertisedDevice->getName();
        int rssi = advertisedDevice->getRSSI();
        bool hasHidUuid = advertisedDevice->isAdvertisingService(NimBLEUUID((uint16_t)0x1812));
        uint16_t app = advertisedDevice->haveAppearance() ? advertisedDevice->getAppearance() : 0;
        bool hasHidApp = (app == 0x03C1);
        bool hasNuPhy = (name.find("NuPhy") != std::string::npos) ||
                        (name.find("nuphy") != std::string::npos) ||
                        (name.find("Air75") != std::string::npos);

        if (!name.empty() || hasHidUuid || hasHidApp || rssi > -60) {
            Serial.printf("[PKT] MAC: %s | RSSI: %d dBm | Nombre: '%s' | HID:%d | App:0x%04X\n",
                          advertisedDevice->getAddress().toString().c_str(),
                          rssi,
                          name.c_str(),
                          hasHidUuid,
                          app);
        }

        if (hasNuPhy || hasHidUuid || hasHidApp) {
            Serial.println("[BLE] NuPhy Air75 detectado. Conectando...");
            NimBLEDevice::getScan()->stop();
            targetKeyboard = new NimBLEAdvertisedDevice(*advertisedDevice);
            doConnect = true;
        }
    }
};

bool connectToKeyboard() {
    NimBLEClient* pClient = NimBLEDevice::createClient();
    pClient->setClientCallbacks(new ClientCallbacks(), false);
    pClient->setConnectionParams(6, 12, 0, 200);

    if (!pClient->connect(targetKeyboard)) {
        Serial.println("[ERROR] Fallo conexion GATT.");
        return false;
    }

    if (!pClient->secureConnection()) {
        Serial.println("[ERROR] Fallo emparejamiento seguro.");
        pClient->disconnect();
        return false;
    }

    NimBLERemoteService* pHidService = pClient->getService(NimBLEUUID((uint16_t)0x1812));
    if (!pHidService) {
        Serial.println("[ERROR] Servicio HID 0x1812 no encontrado.");
        pClient->disconnect();
        return false;
    }

    int subscribed = 0;
    for (auto* pChr : pHidService->getCharacteristics(true)) {
        if (pChr->getUUID() == NimBLEUUID((uint16_t)0x2A4D) && pChr->canNotify()) {
            if (pChr->subscribe(true, hidNotifyCB)) {
                subscribed++;
            }
        }
    }

    if (subscribed == 0) {
        Serial.println("[ERROR] Sin reportes HID disponibles.");
        pClient->disconnect();
        return false;
    }

    kbConnected = true;
    Serial.printf("[OK] NuPhy Air75 listo (%d canales HID). Juega con flechas o W/S.\n", subscribed);
    return true;
}

// -------------------- Comandos SPI hacia la FPGA --------------------
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

void setBackground(uint8_t id) { sendCommand(0x02, id, 0, 0, 0); }
void setSprite(uint8_t slot, uint8_t id, int8_t x, int8_t y) {
    sendCommand(0x01, slot, id, (uint8_t)x, (uint8_t)y);
}
void setTextCell(uint8_t cell, uint8_t ch, uint16_t color) {
    sendCommand(0x05, cell, ch, (uint8_t)(color >> 8), (uint8_t)(color & 0xFF));
}
void commitScene() { sendCommand(0x03, 0, 0, 0, 0); }

// -------------------- Lógica del juego Pong --------------------
int p1Y = 26;
int p2Y = 26;
const int P1_X = 4;
const int P2_X = 56;

int ballX = 30, ballY = 34;
int vx = 1, vy = 1;

int scoreP1 = 0;
int scoreP2 = 0;
unsigned long lastTick = 0;

void updateHud() {
    setTextCell(0, 'P', 0xFFFF);
    setTextCell(1, 'O', 0xFFFF);
    setTextCell(2, 'N', 0xFFFF);
    setTextCell(3, 'G', 0xFFFF);
    setTextCell(5, '0' + (scoreP1 % 10), 0x07E0);
    setTextCell(7, '0' + (scoreP2 % 10), 0xF800);
}

void resetBall(int dirX) {
    ballX = 30;
    ballY = 34;
    vx = dirX;
    vy = (random(0, 2) == 0) ? 1 : -1;
}

void setup() {
    Serial.begin(115200);
    delay(500);

    pinMode(PIN_CS, OUTPUT);
    digitalWrite(PIN_CS, HIGH);
    displaySPI.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);
    delay(300);

    setBackground(0);
    updateHud();
    commitScene();

    Serial.println("[INIT] Iniciando NimBLE 2.5.2...");
    bool initOk = NimBLEDevice::init("ESP32-Pong");
    Serial.printf("[INIT] NimBLEDevice::init = %d\n", initOk);

    NimBLEDevice::setSecurityAuth(true, false, true);
    NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);

    NimBLEScan* pScan = NimBLEDevice::getScan();
    pScan->setScanCallbacks(new ScanCallbacks(), true);
    pScan->setActiveScan(true);
    pScan->setInterval(80);
    pScan->setWindow(40);
    bool started = pScan->start(0, false);

    Serial.printf("[INIT] Escaneo iniciado = %d\n", started);
}

void loop() {
    if (doConnect) {
        doConnect = false;
        if (!connectToKeyboard()) {
            if (targetKeyboard) {
                delete targetKeyboard;
                targetKeyboard = nullptr;
            }
            NimBLEDevice::getScan()->start(0, false);
        }
    }

    if (!kbConnected && (millis() - lastSummary >= 3000)) {
        lastSummary = millis();
        Serial.printf("[ESTADO] Escaneando... paquetes BLE capturados: %lu\n", totalPackets);
    }

    unsigned long now = millis();
    if (now - lastTick >= 35) {
        lastTick = now;

        if (keyUp && p1Y > 9)    p1Y -= 2;
        if (keyDown && p1Y < 48) p1Y += 2;

        int p2Center = p2Y + 8;
        if (ballX > 24) {
            if (p2Center < ballY + 2 && p2Y < 48) p2Y += 1;
            else if (p2Center > ballY + 2 && p2Y > 9) p2Y -= 1;
        }

        ballX += vx;
        ballY += vy;

        if (ballY <= 9) {
            ballY = 9;
            vy = -vy;
        } else if (ballY >= 60) {
            ballY = 60;
            vy = -vy;
        }

        if (vx < 0 && ballX <= (P1_X + 4) && ballX >= P1_X) {
            if ((ballY + 4) >= p1Y && ballY <= (p1Y + 16)) {
                ballX = P1_X + 4;
                vx = -vx;
            }
        }

        if (vx > 0 && (ballX + 4) >= P2_X && ballX <= (P2_X + 4)) {
            if ((ballY + 4) >= p2Y && ballY <= (p2Y + 16)) {
                ballX = P2_X - 4;
                vx = -vx;
            }
        }

        if (ballX < 0) {
            scoreP2++;
            updateHud();
            resetBall(1);
        } else if (ballX > 60) {
            scoreP1++;
            updateHud();
            resetBall(-1);
        }

        setSprite(0, 2, ballX, ballY);
        setSprite(1, 1, P1_X, p1Y);
        setSprite(2, 1, P2_X, p2Y);
        commitScene();
    }
}