`timescale 1ns/1ps
// Prueba de punta a punta: reconstruye lo que realmente sale por los pines HUB75.
module tb_hw_check;
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

    // Captura de lo que entra al panel: 64 bits por línea, en orden de desplazamiento.
    reg [63:0] w_top, w_bot;      // 1 = píxel blanco (r,g,b=1); bit p = p-ésimo píxel desplazado
    integer p;
    reg [63:0] line_top [0:31], line_bot [0:31];
    reg [4:0]  line_addr [0:31];
    integer shifted_in_line;
    reg [63:0] cur_top, cur_bot;
    integer lines_seen;

    // El panel muestrea en el flanco de subida de clk_out.
    always @(posedge clk_out) begin
        if (shifted_in_line < 64) begin
            cur_top[shifted_in_line] = r0 | g0 | b0;
            cur_bot[shifted_in_line] = r1 | g1 | b1;
        end
        shifted_in_line = shifted_in_line + 1;
        if (latch) begin   // último reloj junto con el latch: línea completa
            if (dut.pwm_d == 1) begin
                line_top[dut.scan_row_d] = cur_top;
                line_bot[dut.scan_row_d] = cur_bot;
                line_addr[dut.scan_row_d] = dut.scan_row_d;
            end
            if (shifted_in_line != 64)
                $display("AVISO: %0d relojes entre latches (t=%0t)", shifted_in_line, $time);
            shifted_in_line = 0;
            cur_top = 0; cur_bot = 0;
        end
    end

    task show; input [63:0] v; input [8*14-1:0] name; integer i; reg first; begin
        $write("%0s posiciones(orden de desplazamiento): ", name);
        first = 1;
        for (i=0;i<64;i=i+1) if (v[i]) begin $write("%0d ", i); end
        $write("\n");
    end endtask

    integer k;
    initial begin
        shifted_in_line = 0; cur_top = 0; cur_bot = 0;
        for (k=0;k<32;k=k+1) begin line_top[k]=0; line_bot[k]=0; end
        #200 rst = 1;
        wait(init_done == 1'b1);
        send_spi(40'h02_00_00_00_00);
        send_spi(40'h01_01_01_04_18);   // slot1: pala(id1) 4x16 en (4,24)
        send_spi(40'h01_00_02_1E_1E);   // slot0: pelota(id2) 4x4 en (30,30)
        send_spi(40'h05_00_50_FF_FF);   // texto: celda 0 = 'P' blanca
        send_spi(40'h03_00_00_00_00);
        #12_000_000;                    // render + swap + >2 pasadas completas
        $display("error_flag=%b", error_flag);
        // pala 4x16 en (4,24); pelota 4x4 en (30,30); texto 'P' en la celda 0.
        // Cada máscara es "bit c = columna c encendida" a pwm_level=1.
        if (error_flag !== 1'b0)                                     $display("FAIL: error_flag");
        else if (line_top[26] !== 64'h0000_0000_0000_00F0)           $display("FAIL: pala fila 26: %h", line_top[26]);
        else if (line_top[30] !== 64'h0000_0003_C000_00F0)           $display("FAIL: pala+pelota fila 30: %h", line_top[30]);
        else if (line_bot[6]  !== 64'h0000_0000_0000_00F0)           $display("FAIL: pala fila 38: %h", line_bot[6]);
        else if (line_bot[0]  !== 64'h0000_0003_C000_00F0)           $display("FAIL: pala+pelota fila 32: %h", line_bot[0]);
        else if (line_top[0]  !== 64'h0000_0000_0000_003E)           $display("FAIL: texto P fila 0: %h", line_top[0]);
        else if (line_top[1]  !== 64'h0000_0000_0000_0066)           $display("FAIL: texto P fila 1: %h", line_top[1]);
        else $display("PASS TOTAL: columnas correctas en los pines HUB75 (pala, pelota, texto).");
        $finish;
    end
endmodule
