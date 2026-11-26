`timescale 1ns/1ps
// Verifica las reglas de la especificación (prioridad, recorte, transparencia,
// ocultar, texto bajo sprite) leyendo SOLO los pines HUB75.
// Imprime el cuadro como 64 líneas de 64 caracteres: W blanco, Y amarillo, . apagado.
// (a pwm_level=1 el fondo 0 queda apagado, así solo se ven sprites y texto)
module tb_spec_rules;
    reg clk = 0, rst = 0, spi_cs = 1, spi_sck = 0, spi_mosi = 0;
    wire r0,g0,b0,r1,g1,b1; wire [4:0] addr; wire clk_out, latch, oe, init_done, error_flag;
    assign init_done = dut.init_done;
    assign error_flag = dut.error_flag;
    always #20 clk = ~clk;

    top dut(.clk(clk),.rst(rst),.spi_cs(spi_cs),.spi_sck(spi_sck),.spi_mosi(spi_mosi),
            .r0(r0),.g0(g0),.b0(b0),.r1(r1),.g1(g1),.b1(b1),
            .addr(addr),.clk_out(clk_out),.latch(latch),.oe(oe));

    task send_spi; input [39:0] d; integer n; begin
        spi_cs = 0; #200;
        for (n=39;n>=0;n=n-1) begin spi_mosi=d[n]; #500; spi_sck=1; #500; spi_sck=0; end
        #200; spi_cs = 1; #1000;
    end endtask

    integer sh;
    reg [63:0] ct_r, ct_g, ct_b, cb_r, cb_g, cb_b;
    reg [63:0] t_r [0:31]; reg [63:0] t_g [0:31]; reg [63:0] t_b [0:31];
    reg [63:0] b_r [0:31]; reg [63:0] b_g [0:31]; reg [63:0] b_b [0:31];

    always @(posedge clk_out) begin
        if (sh < 64) begin
            ct_r[sh] = r0; ct_g[sh] = g0; ct_b[sh] = b0;
            cb_r[sh] = r1; cb_g[sh] = g1; cb_b[sh] = b1;
        end
        sh = sh + 1;
        if (latch) begin
            if (dut.pwm_d == 1) begin
                t_r[dut.scan_row_d] = ct_r; t_g[dut.scan_row_d] = ct_g; t_b[dut.scan_row_d] = ct_b;
                b_r[dut.scan_row_d] = cb_r; b_g[dut.scan_row_d] = cb_g; b_b[dut.scan_row_d] = cb_b;
            end
            sh = 0; ct_r = 0; ct_g = 0; ct_b = 0; cb_r = 0; cb_g = 0; cb_b = 0;
        end
    end

    integer x, y;
    reg [7:0] ch;
    initial begin
        sh = 0;
        #200 rst = 1;
        wait(init_done == 1'b1);
        send_spi(40'h02_00_00_00_00);                 // fondo 0
        send_spi(40'h05_00_50_FF_FF);                 // texto 'P' blanco, celda 0
        send_spi(40'h01_01_01_04_18);                 // slot1 pala  (4,24)
        send_spi(40'h01_00_02_04_18);                 // slot0 pelota (4,24)  -> prioridad
        send_spi(40'h01_02_01_FE_0A);                 // slot2 pala  (-2,10)  -> recorte izq
        send_spi(40'h01_03_02_14_FE);                 // slot3 pelota (20,-2) -> recorte sup
        send_spi(40'h01_04_02_3E_3E);                 // slot4 pelota (62,62) -> recorte der/inf
        send_spi(40'h01_05_02_46_0A);                 // slot5 pelota (70,10) -> fuera, sin error
        send_spi(40'h01_07_01_1E_26);                 // slot7 pala  (30,38)  (debajo)
        send_spi(40'h01_06_03_1E_28);                 // slot6 sprite3 (30,40) encima de la pala -> transparencia
        send_spi(40'h01_08_02_28_28);                 // slot8 pelota (40,40)
        send_spi(40'h04_08_00_00_00);                 // HIDE slot8
        send_spi(40'h01_09_02_02_02);                 // slot9 pelota (2,2) sobre el texto
        send_spi(40'h03_00_00_00_00);                 // COMMIT
        #12_000_000;
        $display("ERRFLAG=%b", error_flag);
        for (y = 0; y < 64; y = y + 1) begin
            for (x = 0; x < 64; x = x + 1) begin
                if (y < 32) begin
                    if (t_r[y][x] & t_g[y][x] & t_b[y][x]) ch = "W";
                    else if (t_r[y][x] & t_g[y][x])        ch = "Y";
                    else if (t_r[y][x] | t_g[y][x] | t_b[y][x]) ch = "?";
                    else ch = ".";
                end else begin
                    if (b_r[y-32][x] & b_g[y-32][x] & b_b[y-32][x]) ch = "W";
                    else if (b_r[y-32][x] & b_g[y-32][x])           ch = "Y";
                    else if (b_r[y-32][x] | b_g[y-32][x] | b_b[y-32][x]) ch = "?";
                    else ch = ".";
                end
                $write("%c", ch);
            end
            $write("\n");
        end
        $finish;
    end
endmodule
