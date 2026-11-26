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

// Estado continuo de teclas de juego
volatile bool keyUp    = false;
volatile bool keyDown  = false;
volatile bool keyLeft  = false;
volatile bool keyRight = false;
volatile bool keyFire  = false;
volatile bool keyBack  = false;

// Cola de teclas pulsadas (flancos) para el modo escritura
static const int KEY_QUEUE_SIZE = 16;
volatile char keyQueue[KEY_QUEUE_SIZE];
volatile uint8_t qHead = 0;
volatile uint8_t qTail = 0;
static uint8_t prevActiveKeys[6] = {0};

// Códigos USB HID Usage ID (página 0x07)
static const uint8_t HID_KEY_A           = 0x04;
static const uint8_t HID_KEY_Z           = 0x1D;
static const uint8_t HID_KEY_1           = 0x1E;
static const uint8_t HID_KEY_0           = 0x27;
static const uint8_t HID_KEY_ENTER       = 0x28;
static const uint8_t HID_KEY_ESC         = 0x29;
static const uint8_t HID_KEY_BACKSPACE   = 0x2A;
static const uint8_t HID_KEY_SPACE       = 0x2C;
static const uint8_t HID_KEY_MINUS       = 0x2D;
static const uint8_t HID_KEY_EQUAL       = 0x2E;
static const uint8_t HID_KEY_SEMICOLON   = 0x33;
static const uint8_t HID_KEY_COMMA       = 0x36;
static const uint8_t HID_KEY_PERIOD      = 0x37;
static const uint8_t HID_KEY_SLASH       = 0x38;
static const uint8_t HID_KEY_ARROW_RIGHT = 0x4F;
static const uint8_t HID_KEY_ARROW_LEFT  = 0x50;
static const uint8_t HID_KEY_ARROW_DOWN  = 0x51;
static const uint8_t HID_KEY_ARROW_UP    = 0x52;

void enqueueChar(char c) {
    if (c == 0) return;
    uint8_t next = (qHead + 1) % KEY_QUEUE_SIZE;
    if (next != qTail) {
        keyQueue[qHead] = c;
        qHead = next;
    }
}

char dequeueChar() {
    if (qHead == qTail) return 0;
    char c = keyQueue[qTail];
    qTail = (qTail + 1) % KEY_QUEUE_SIZE;
    return c;
}

char hidToAscii(uint8_t code, bool shift) {
    if (code >= HID_KEY_A && code <= HID_KEY_Z) {
        char base = shift ? 'A' : 'a';
        return base + (code - HID_KEY_A);
    }
    if (code >= HID_KEY_1 && code <= 0x26) {
        const char shiftedNums[] = "!@#$%^&*(";
        return shift ? shiftedNums[code - HID_KEY_1] : ('1' + (code - HID_KEY_1));
    }
    if (code == HID_KEY_0)         return shift ? ')' : '0';
    if (code == HID_KEY_SPACE)     return ' ';
    if (code == HID_KEY_ENTER)     return '\n';
    if (code == HID_KEY_BACKSPACE) return '\b';
    if (code == HID_KEY_MINUS)     return shift ? '_' : '-';
    if (code == HID_KEY_EQUAL)     return shift ? '+' : '=';
    if (code == HID_KEY_SEMICOLON) return shift ? ':' : ';';
    if (code == HID_KEY_COMMA)     return shift ? '<' : ',';
    if (code == HID_KEY_PERIOD)    return shift ? '>' : '.';
    if (code == HID_KEY_SLASH)     return shift ? '?' : '/';
    return 0;
}

static inline bool checkUsageBitmap(const uint8_t* buf, size_t len, size_t offset, uint8_t usage) {
    size_t byteIdx = offset + (usage >> 3);
    if (byteIdx >= len) return false;
    return (buf[byteIdx] & (1U << (usage & 0x07))) != 0;
}

void hidNotifyCB(NimBLERemoteCharacteristic* pChr, uint8_t* pData, size_t length, bool isNotify) {
    bool up = false, down = false, left = false, right = false, fire = false, back = false;
    uint8_t currentKeys[6] = {0};
    int kCount = 0;
    bool shift = false;

    if (length == 8 || length == 9) {
        size_t modIdx = (length == 9) ? 1 : 0;
        size_t startIdx = (length == 9) ? 3 : 2;
        shift = (pData[modIdx] & 0x22) != 0; // Left Shift (0x02) o Right Shift (0x20)

        for (size_t i = startIdx; i < length; i++) {
            uint8_t c = pData[i];
            if (c == 0) continue;
            if (kCount < 6) currentKeys[kCount++] = c;
            if (c == HID_KEY_ARROW_UP)    up = true;
            if (c == HID_KEY_ARROW_DOWN)  down = true;
            if (c == HID_KEY_ARROW_LEFT)  left = true;
            if (c == HID_KEY_ARROW_RIGHT) right = true;
            if (c == HID_KEY_SPACE || c == HID_KEY_ENTER) fire = true;
            if (c == HID_KEY_ESC)         back = true;
        }
    } else if (length >= 14) {
        size_t modIdx = (length == 16) ? 1 : 0;
        size_t off = (length == 16) ? 2 : 1;
        shift = (pData[modIdx] & 0x22) != 0;

        up    = checkUsageBitmap(pData, length, off, HID_KEY_ARROW_UP);
        down  = checkUsageBitmap(pData, length, off, HID_KEY_ARROW_DOWN);
        left  = checkUsageBitmap(pData, length, off, HID_KEY_ARROW_LEFT);
        right = checkUsageBitmap(pData, length, off, HID_KEY_ARROW_RIGHT);
        fire  = checkUsageBitmap(pData, length, off, HID_KEY_SPACE) || checkUsageBitmap(pData, length, off, HID_KEY_ENTER);
        back  = checkUsageBitmap(pData, length, off, HID_KEY_ESC);

        for (uint8_t code = HID_KEY_A; code <= HID_KEY_SLASH && kCount < 6; code++) {
            if (checkUsageBitmap(pData, length, off, code)) {
                currentKeys[kCount++] = code;
            }
        }
    }

    // Encolar únicamente teclas recién presionadas (flanco de bajada)
    for (int i = 0; i < kCount; i++) {
        uint8_t code = currentKeys[i];
        bool wasPressed = false;
        for (int j = 0; j < 6; j++) {
            if (prevActiveKeys[j] == code) {
                wasPressed = true;
                break;
            }
        }
        if (!wasPressed) {
            enqueueChar(hidToAscii(code, shift));
        }
    }
    memcpy(prevActiveKeys, currentKeys, 6);

    keyUp = up;
    keyDown = down;
    keyLeft = left;
    keyRight = right;
    keyFire = fire;
    keyBack = back;
}

class ClientCallbacks : public NimBLEClientCallbacks {
    void onConnect(NimBLEClient* pClient) override {
        Serial.println("[BLE] Conectado al NuPhy Air75...");
    }
    void onDisconnect(NimBLEClient* pClient, int reason) override {
        Serial.printf("[BLE] Desconectado (razon=%d). Reanudando escaneo...\n", reason);
        kbConnected = false;
        keyUp = keyDown = keyLeft = keyRight = keyFire = keyBack = false;
        memset(prevActiveKeys, 0, 6);
        if (targetKeyboard) {
            delete targetKeyboard;
            targetKeyboard = nullptr;
        }
        NimBLEDevice::getScan()->start(0, false);
    }
};

class ScanCallbacks : public NimBLEScanCallbacks {
    void onResult(const NimBLEAdvertisedDevice* advertisedDevice) override {
        if (doConnect || kbConnected) return;

        std::string name = advertisedDevice->getName();
        bool hasHidUuid = advertisedDevice->isAdvertisingService(NimBLEUUID((uint16_t)0x1812));
        uint16_t app = advertisedDevice->haveAppearance() ? advertisedDevice->getAppearance() : 0;
        bool hasHidApp = (app == 0x03C1);
        bool hasNuPhy = (name.find("NuPhy") != std::string::npos) ||
                        (name.find("nuphy") != std::string::npos) ||
                        (name.find("Air75") != std::string::npos);

        if (hasNuPhy || hasHidUuid || hasHidApp) {
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

    if (!pClient->connect(targetKeyboard)) return false;
    if (!pClient->secureConnection()) {
        pClient->disconnect();
        return false;
    }

    NimBLERemoteService* pHidService = pClient->getService(NimBLEUUID((uint16_t)0x1812));
    if (!pHidService) {
        pClient->disconnect();
        return false;
    }

    int subscribed = 0;
    for (auto* pChr : pHidService->getCharacteristics(true)) {
        if (pChr->getUUID() == NimBLEUUID((uint16_t)0x2A4D) && pChr->canNotify()) {
            if (pChr->subscribe(true, hidNotifyCB)) subscribed++;
        }
    }

    if (subscribed == 0) {
        pClient->disconnect();
        return false;
    }

    kbConnected = true;
    Serial.println("[OK] NuPhy Air75 listo.");
    return true;
}

// -------------------- Protocolo SPI hacia la FPGA --------------------
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

void setBackground(uint8_t id) { sendCommand(0x02, id & 0x03, 0, 0, 0); }
void setSprite(uint8_t slot, uint8_t id, int8_t x, int8_t y) {
    sendCommand(0x01, slot, id, (uint8_t)x, (uint8_t)y);
}
void hideSprite(uint8_t slot) { sendCommand(0x04, slot, 0, 0, 0); }
void setTextCell(uint8_t cell, uint8_t ch, uint16_t color) {
    sendCommand(0x05, cell, ch, (uint8_t)(color >> 8), (uint8_t)(color & 0xFF));
}
void hideTextCell(uint8_t cell) { sendCommand(0x06, cell, 0, 0, 0); }
void commitScene() { sendCommand(0x03, 0, 0, 0, 0); }

void clearAllSprites() {
    for (uint8_t s = 0; s < 16; s++) hideSprite(s);
}

void clearAllText() {
    for (uint8_t c = 0; c < 64; c++) hideTextCell(c);
}

void printTextRow(uint8_t row, uint8_t colStart, const char* str, uint16_t color) {
    for (uint8_t i = 0; str[i] != '\0' && (colStart + i) < 8; i++) {
        uint8_t cell = (row * 8) + colStart + i;
        if (str[i] == ' ') hideTextCell(cell);
        else setTextCell(cell, (uint8_t)str[i], color);
    }
}

// -------------------- Máquina de estados --------------------
enum AppState {
    STATE_MENU,
    STATE_PONG,
    STATE_INVADERS,
    STATE_TYPE
};

AppState currentState = STATE_MENU;
int menuOption = 0;      // 0 = PONG, 1 = SPACE, 2 = TEXTO
uint8_t selectedBg = 0;  // 0..3
unsigned long lastTick = 0;

bool prevUp = false, prevDown = false, prevLeft = false, prevRight = false, prevFire = false, prevBack = false;

// -------------------- Variables de PONG --------------------
int p1Y = 26, p2Y = 26;
const int P1_X = 4, P2_X = 56;
int ballX = 30, ballY = 34;
int vx = 1, vy = 1;
int scoreP1 = 0, scoreP2 = 0;

// -------------------- Variables de SPACE INVADERS --------------------
const int NUM_ALIENS = 12;
int shipX = 30;
const int SHIP_Y = 58;
bool pBulletActive = false;
int pBulletX = 0, pBulletY = 0;
bool eBulletActive = false;
int eBulletX = 0, eBulletY = 0;
int alienX[NUM_ALIENS], alienY[NUM_ALIENS];
bool alienAlive[NUM_ALIENS];
int alienDir = 1, alienMoveCounter = 0;
int invScore = 0, invLives = 3;

// -------------------- Variables de MODO ESCRITURA --------------------
uint8_t typeCursor = 0; // Celda 0..63
const uint16_t textPalette[] = {
    0xFFFF, // Blanco
    0x07FF, // Cian
    0xFFE0, // Amarillo
    0x07E0, // Verde
    0xF800, // Rojo
    0xF81F  // Magenta
};
const int PALETTE_SIZE = 6;
int colorIdx = 0;

// -------------------- MENÚ PRINCIPAL --------------------
void renderMenu() {
    clearAllSprites();
    clearAllText();
    setBackground(selectedBg);

    printTextRow(0, 2, "MENU", 0x07FF);
    printTextRow(2, 1, "1 PONG",  (menuOption == 0) ? 0xFFE0 : 0xFFFF);
    printTextRow(3, 1, "2 SPACE", (menuOption == 1) ? 0xFFE0 : 0xFFFF);
    printTextRow(4, 1, "3 TEXTO", (menuOption == 2) ? 0xFFE0 : 0xFFFF);

    uint8_t cursorY = (2 + menuOption) * 8 + 2;
    setSprite(0, 2, 2, cursorY);

    char bgLine[9];
    snprintf(bgLine, sizeof(bgLine), "BG:%d  OK", selectedBg);
    printTextRow(6, 0, bgLine, 0x07E0);

    commitScene();
}

void enterMenu() {
    currentState = STATE_MENU;
    renderMenu();
}

// -------------------- MODO ESCRITURA EN VIVO --------------------
void updateTypeCursorSprite() {
    uint8_t col = typeCursor & 0x07;
    uint8_t row = typeCursor >> 3;
    setSprite(0, 2, col * 8 + 2, row * 8 + 2);
}

void enterTypeMode() {
    currentState = STATE_TYPE;
    clearAllSprites();
    clearAllText();
    setBackground(selectedBg);
    // Vaciar cola de teclas residuales
    while (dequeueChar() != 0) {}

    typeCursor = 0;
    colorIdx = 0;
    updateTypeCursorSprite();
    commitScene();
}

void stepTypeMode(bool edgeUp, bool edgeDown) {
    bool dirty = false;

    // Flechas arriba/abajo cambian el color del pincel de texto
    if (edgeUp) {
        colorIdx = (colorIdx + 1) % PALETTE_SIZE;
        dirty = true;
    }
    if (edgeDown) {
        colorIdx = (colorIdx + PALETTE_SIZE - 1) % PALETTE_SIZE;
        dirty = true;
    }

    char ch;
    while ((ch = dequeueChar()) != 0) {
        dirty = true;
        if (ch == '\b') {
            if (typeCursor > 0) typeCursor--;
            hideTextCell(typeCursor);
        } else if (ch == '\n') {
            uint8_t nextRow = (typeCursor >> 3) + 1;
            if (nextRow >= 8) {
                clearAllText();
                typeCursor = 0;
            } else {
                typeCursor = nextRow * 8;
            }
        } else {
            if (ch == ' ') hideTextCell(typeCursor);
            else setTextCell(typeCursor, (uint8_t)ch, textPalette[colorIdx]);

            typeCursor++;
            if (typeCursor >= 64) {
                typeCursor = 0;
            }
        }
    }

    if (dirty) {
        updateTypeCursorSprite();
        commitScene();
    }
}

// -------------------- PONG --------------------
void updatePongHud() {
    printTextRow(0, 0, "PONG", 0xFFFF);
    setTextCell(5, '0' + (scoreP1 % 10), 0x07E0);
    setTextCell(7, '0' + (scoreP2 % 10), 0xF800);
}

void resetPongBall(int dirX) {
    ballX = 30;
    ballY = 34;
    vx = dirX;
    vy = (random(0, 2) == 0) ? 1 : -1;
}

void enterPong() {
    currentState = STATE_PONG;
    clearAllSprites();
    clearAllText();
    setBackground(selectedBg);
    scoreP1 = 0;
    scoreP2 = 0;
    p1Y = 26;
    p2Y = 26;
    resetPongBall(1);
    updatePongHud();
    commitScene();
}

void stepPong() {
    if (keyUp && p1Y > 9)    p1Y -= 2;
    if (keyDown && p1Y < 48) p1Y += 2;

    int p2Center = p2Y + 8;
    if (ballX > 24) {
        if (p2Center < ballY + 2 && p2Y < 48) p2Y += 1;
        else if (p2Center > ballY + 2 && p2Y > 9) p2Y -= 1;
    }

    ballX += vx;
    ballY += vy;

    if (ballY <= 9) { ballY = 9; vy = -vy; }
    else if (ballY >= 60) { ballY = 60; vy = -vy; }

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
        updatePongHud();
        resetPongBall(1);
    } else if (ballX > 60) {
        scoreP1++;
        updatePongHud();
        resetPongBall(-1);
    }

    setSprite(0, 2, ballX, ballY);
    setSprite(1, 1, P1_X, p1Y);
    setSprite(2, 1, P2_X, p2Y);
    commitScene();
}

// -------------------- SPACE INVADERS --------------------
void updateInvadersHud() {
    printTextRow(0, 0, "SC", 0x07FF);
    setTextCell(3, '0' + ((invScore / 10) % 10), 0xFFFF);
    setTextCell(4, '0' + (invScore % 10), 0xFFFF);
    setTextCell(7, '0' + (invLives % 10), 0x07E0);
}

void spawnAlienWave() {
    for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 4; c++) {
            int idx = r * 4 + c;
            alienX[idx] = 8 + c * 13;
            alienY[idx] = 11 + r * 8;
            alienAlive[idx] = true;
        }
    }
    alienDir = 1;
    alienMoveCounter = 0;
}

void enterInvaders() {
    currentState = STATE_INVADERS;
    clearAllSprites();
    clearAllText();
    setBackground(selectedBg);
    shipX = 30;
    pBulletActive = false;
    eBulletActive = false;
    invScore = 0;
    invLives = 3;
    spawnAlienWave();
    updateInvadersHud();
    commitScene();
}

void stepInvaders() {
    if (keyLeft && shipX > 1)   shipX -= 2;
    if (keyRight && shipX < 59) shipX += 2;

    if ((keyFire || keyUp) && !pBulletActive) {
        pBulletActive = true;
        pBulletX = shipX;
        pBulletY = SHIP_Y - 4;
    }

    if (pBulletActive) {
        pBulletY -= 3;
        if (pBulletY < 8) pBulletActive = false;
    }

    alienMoveCounter++;
    if (alienMoveCounter >= 6) {
        alienMoveCounter = 0;
        bool hitEdge = false;
        for (int i = 0; i < NUM_ALIENS; i++) {
            if (!alienAlive[i]) continue;
            if ((alienDir > 0 && alienX[i] >= 58) || (alienDir < 0 && alienX[i] <= 2)) {
                hitEdge = true;
                break;
            }
        }
        if (hitEdge) {
            alienDir = -alienDir;
            for (int i = 0; i < NUM_ALIENS; i++) {
                if (alienAlive[i]) alienY[i] += 3;
            }
        } else {
            for (int i = 0; i < NUM_ALIENS; i++) {
                if (alienAlive[i]) alienX[i] += alienDir * 2;
            }
        }
    }

    if (!eBulletActive) {
        int shooter = random(0, NUM_ALIENS);
        if (alienAlive[shooter]) {
            eBulletActive = true;
            eBulletX = alienX[shooter];
            eBulletY = alienY[shooter] + 4;
        }
    } else {
        eBulletY += 2;
        if (eBulletY >= 64) eBulletActive = false;
    }

    int aliveCount = 0;
    for (int i = 0; i < NUM_ALIENS; i++) {
        if (!alienAlive[i]) continue;
        aliveCount++;

        if (pBulletActive && abs(pBulletX - alienX[i]) < 4 && abs(pBulletY - alienY[i]) < 4) {
            alienAlive[i] = false;
            pBulletActive = false;
            invScore++;
            aliveCount--;
            updateInvadersHud();
        }

        if (alienAlive[i] && alienY[i] >= (SHIP_Y - 3)) invLives = 0;
    }

    if (aliveCount == 0) spawnAlienWave();

    if (eBulletActive && abs(eBulletX - shipX) < 4 && abs(eBulletY - SHIP_Y) < 4) {
        eBulletActive = false;
        invLives--;
        updateInvadersHud();
    }

    if (invLives <= 0) {
        delay(600);
        enterMenu();
        return;
    }

    setSprite(0, 2, shipX, SHIP_Y);
    if (pBulletActive) setSprite(1, 2, pBulletX, pBulletY);
    else hideSprite(1);

    if (eBulletActive) setSprite(2, 2, eBulletX, eBulletY);
    else hideSprite(2);

    for (int i = 0; i < NUM_ALIENS; i++) {
        uint8_t slot = 3 + i;
        if (alienAlive[i]) {
            uint8_t sprId = (i < 4) ? 3 : 2;
            setSprite(slot, sprId, alienX[i], alienY[i]);
        } else {
            hideSprite(slot);
        }
    }

    commitScene();
}

// -------------------- Setup y Loop --------------------
void setup() {
    Serial.begin(115200);
    delay(300);

    pinMode(PIN_CS, OUTPUT);
    digitalWrite(PIN_CS, HIGH);
    displaySPI.begin(PIN_SCK, PIN_MISO, PIN_MOSI, PIN_CS);
    delay(300);

    enterMenu();

    NimBLEDevice::init("ESP32-Arcade");
    NimBLEDevice::setSecurityAuth(true, false, true);
    NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);

    NimBLEScan* pScan = NimBLEDevice::getScan();
    pScan->setScanCallbacks(new ScanCallbacks(), true);
    pScan->setActiveScan(true);
    pScan->setInterval(80);
    pScan->setWindow(40);
    pScan->start(0, false);
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

    unsigned long now = millis();
    if (now - lastTick >= 35) {
        lastTick = now;

        bool edgeUp    = keyUp && !prevUp;
        bool edgeDown  = keyDown && !prevDown;
        bool edgeLeft  = keyLeft && !prevLeft;
        bool edgeRight = keyRight && !prevRight;
        bool edgeFire  = keyFire && !prevFire;
        bool edgeBack  = keyBack && !prevBack;

        prevUp = keyUp; prevDown = keyDown;
        prevLeft = keyLeft; prevRight = keyRight;
        prevFire = keyFire; prevBack = keyBack;

        if (currentState == STATE_MENU) {
            bool dirty = false;
            if (edgeUp) {
                menuOption = (menuOption + 2) % 3;
                dirty = true;
            }
            if (edgeDown) {
                menuOption = (menuOption + 1) % 3;
                dirty = true;
            }
            if (edgeLeft) {
                selectedBg = (selectedBg + 3) & 0x03;
                dirty = true;
            }
            if (edgeRight) {
                selectedBg = (selectedBg + 1) & 0x03;
                dirty = true;
            }
            if (dirty) renderMenu();

            if (edgeFire) {
                if (menuOption == 0) enterPong();
                else if (menuOption == 1) enterInvaders();
                else enterTypeMode();
            }
        } else {
            if (edgeBack) {
                enterMenu();
            } else if (currentState == STATE_PONG) {
                stepPong();
            } else if (currentState == STATE_INVADERS) {
                stepInvaders();
            } else if (currentState == STATE_TYPE) {
                stepTypeMode(edgeUp, edgeDown);
            }
        }
    }
}