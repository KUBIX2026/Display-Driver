module top(
    input  wire clk,
    input  wire rst,

    // Interfaz SPI (Conector J1)
    input  wire spi_cs,
    input  wire spi_sck,
    input  wire spi_mosi,

    // Interfaz HUB75 (Conector J16)
    output wire r0, g0, b0,
    output wire r1, g1, b1,
    output wire [4:0] addr,
    output wire clk_out,
    output wire latch,
    output wire oe
);

    wire rst_internal = ~rst;

    // Cables del barrido del panel
    wire [5:0] col;
    wire [4:0] scan_row;
    wire [4:0] display_row;
    wire [4:0] pwm_level; 
    wire [5:0] row_top;
    wire [5:0] row_bottom;

    // Cables de interconexión SPI
    wire [39:0] spi_raw_data;
    wire        spi_ready;
    wire [23:0] decoded_color;

    // 1. Mensajero: Recibe la trama física de 40 bits
    spi_receiver SPI_RX (
        .clk(clk), 
        .rst(rst_internal),
        .spi_cs(spi_cs), 
        .spi_sck(spi_sck), 
        .spi_mosi(spi_mosi),
        .raw_data(spi_raw_data),   // Corregido: antes decía data_out
        .data_ready(spi_ready)
    );

    // 2. Cerebro: Decodifica los 40 bits y los convierte al color de 24 bits
    spi_decoder DECODER (
        .clk(clk),
        .rst(rst_internal),
        .raw_data(spi_raw_data),
        .data_ready(spi_ready),
        .color_out(decoded_color)
    );

    // 3. Contadores de barrido
    scan_counters SC(
        .clk(clk),
        .rst(rst_internal),
        .col(col),
        .scan_row(scan_row),
        .addr_out(display_row),
        .pwm_level(pwm_level),
        .row_top(row_top),
        .row_bottom(row_bottom)
    );

    assign addr = display_row;

    // 4. Modulador PWM (alimentado por el decodificador)
    panel_pwm PWM(
        .pix_top(decoded_color),
        .pix_bottom(decoded_color),
        .pwm_level(pwm_level),
        .r0(r0), .g0(g0), .b0(b0),
        .r1(r1), .g1(g1), .b1(b1)
    );

    // 5. Controlador de tiempos HUB75
    delay_unit DU(
        .clk(clk),
        .rst(rst_internal),
        .col(col),
        .clk_out(clk_out),
        .latch(latch),
        .oe(oe)
    );

endmodule    
