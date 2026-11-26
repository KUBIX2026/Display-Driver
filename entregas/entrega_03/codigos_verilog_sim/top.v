module top (
    input  wire clk,
    input  wire rst,

    // SPI desde ESP32.
    input  wire spi_cs,
    input  wire spi_sck,
    input  wire spi_mosi,

    // Salida HUB75.
    output wire r0, g0, b0,
    output wire r1, g1, b1,
    output wire [4:0] addr,
    output wire clk_out,
    output wire latch,
    output wire oe
);

    // STATUS (spec 03, sección 6): bit 0 = listo (init_done), bit 1 = error.
    // No son pines del panel; quedan como señales internas (se ven en simulación
    // como dut.init_done / dut.error_flag y quedarán para el registro STATUS).
    wire init_done;
    wire error_flag;

    // Mantener la polaridad del top original.
    wire rst_internal = ~rst;

    // SPI.
    wire [39:0] spi_raw_data;
    wire spi_ready;
    wire spi_frame_error;

    wire cmd_valid;
    wire cmd_error;
    wire [7:0] cmd;
    wire [7:0] arg0, arg1, arg2, arg3;
    wire [15:0] cmd_color;

    // Barrido.
    wire [5:0] col;
    wire [4:0] scan_row;
    wire [4:0] display_row;
    wire [4:0] pwm_level;
    wire [5:0] row_top;
    wire [5:0] row_bottom;
    wire frame_start;

    // Píxeles RGB565.
    wire [15:0] pix_top;
    wire [15:0] pix_bottom;

    // Salidas HUB75 retrasadas 1 ciclo: las memorias del compositor tienen
    // lectura síncrona, así que el píxel llega 1 ciclo después de col.
    reg [5:0] col_d;
    reg [4:0] addr_d;
    reg [4:0] pwm_d;
    reg [4:0] scan_row_d;

    always @(posedge clk) begin
        col_d      <= col;
        addr_d     <= display_row;
        pwm_d      <= pwm_level;
        scan_row_d <= scan_row;
    end

    // Error sticky del sistema.
    reg error_latched;
    wire scene_error;

    always @(posedge clk) begin
        if (rst_internal)
            error_latched <= 1'b0;
        else if (cmd_error || spi_frame_error)
            error_latched <= 1'b1;
    end

    assign error_flag = error_latched | scene_error;

    spi_receiver SPI_RX (
        .clk(clk),
        .rst(rst_internal),
        .spi_cs(spi_cs),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),
        .raw_data(spi_raw_data),
        .data_ready(spi_ready),
        .frame_error(spi_frame_error)
    );

    spi_decoder DECODER (
        .clk(clk),
        .rst(rst_internal),
        .raw_data(spi_raw_data),
        .data_ready(spi_ready),
        .frame_error(spi_frame_error),
        .cmd_valid(cmd_valid),
        .cmd_error(cmd_error),
        .cmd(cmd),
        .arg0(arg0),
        .arg1(arg1),
        .arg2(arg2),
        .arg3(arg3),
        .color(cmd_color)
    );

    scan_counters SCAN (
        .clk(clk),
        .rst(rst_internal),
        .col(col),
        .scan_row(scan_row),
        .addr_out(display_row),
        .pwm_level(pwm_level),
        .row_top(row_top),
        .row_bottom(row_bottom),
        .frame_start(frame_start)
    );

    assign addr = addr_d;

    scene_compositor SCENE (
        .clk(clk),
        .rst(rst_internal),

        .cmd_valid(cmd_valid),
        .cmd_error(cmd_error),
        .cmd(cmd),
        .arg0(arg0),
        .arg1(arg1),
        .arg2(arg2),
        .arg3(arg3),
        .color(cmd_color),

        .frame_start(frame_start),
        .pwm_level(pwm_level),

        .col(col),
        .row_top(row_top),
        .row_bottom(row_bottom),

        .pix_top(pix_top),
        .pix_bottom(pix_bottom),

        .init_done(init_done),
        .error_sticky(scene_error),
        .render_busy()
    );

    panel_pwm PWM (
        .pix_top(init_done ? pix_top : 16'h0000),
        .pix_bottom(init_done ? pix_bottom : 16'h0000),
        .pwm_level(pwm_d),
        .r0(r0), .g0(g0), .b0(b0),
        .r1(r1), .g1(g1), .b1(b1)
    );

    delay_unit DU (
        .clk(clk),
        .rst(rst_internal),
        .col(col_d),
        .clk_out(clk_out),
        .latch(latch),
        .oe(oe)
    );

endmodule
