module top(
    input  wire clk, rst,
    input  wire spi_cs, spi_sck, spi_mosi,
    output wire r0, g0, b0, r1, g1, b1,
    output wire [4:0] addr,
    output wire clk_out, latch, oe
);
    wire rst_internal = ~rst;

    // Cables del barrido
    wire [6:0] col;
    wire [4:0] scan_row, display_row; 
    wire [4:0] pwm_level;
    wire [5:0] row_top, row_bottom;

    // Cables SPI y VRAM
    wire [39:0] spi_raw_data;
    wire        spi_ready, spi_we;
    wire [5:0]  spi_x, spi_y;
    wire [23:0] spi_color;

    spi_receiver SPI_RX (
        .clk(clk), .rst(rst_internal),
        .spi_cs(spi_cs), .spi_sck(spi_sck), .spi_mosi(spi_mosi),
        .raw_data(spi_raw_data), .data_ready(spi_ready)
    );

    spi_decoder DECODER (
        .clk(clk), .rst(rst_internal),
        .raw_data(spi_raw_data), .data_ready(spi_ready),
        .x_out(spi_x), .y_out(spi_y),
        .color_out(spi_color), .we_out(spi_we)
    );

    scan_counters SC(
        .clk(clk), .rst(rst_internal), .col(col),
        .scan_row(scan_row), .addr_out(display_row),
        .pwm_level(pwm_level), .row_top(row_top), .row_bottom(row_bottom)
    );
    assign addr = display_row;

    // Conectar la VRAM
    wire [10:0] panel_read_addr = {scan_row, col[5:0]};
    wire [23:0] pix_top, pix_bottom;

    vram VRAM (
        .clk(clk),
        .we(spi_we),
        .write_x(spi_x), .write_y(spi_y), .write_color(spi_color),
        .read_addr(panel_read_addr),
        .pix_top(pix_top), .pix_bottom(pix_bottom)
    );

    panel_pwm PWM(
        .pix_top(pix_top), .pix_bottom(pix_bottom), .pwm_level(pwm_level),
        .r0(r0), .g0(g0), .b0(b0), .r1(r1), .g1(g1), .b1(b1)
    );

    delay_unit DU(
        .clk(clk), .rst(rst_internal), .col(col),
        .clk_out(clk_out), .latch(latch), .oe(oe)
    );
endmodule
