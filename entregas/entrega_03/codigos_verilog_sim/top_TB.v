`timescale 1ns/1ps

module tb_top;

    reg clk = 0;
    reg rst = 0;

    reg spi_cs = 1;
    reg spi_sck = 0;
    reg spi_mosi = 0;

    wire r0, g0, b0;
    wire r1, g1, b1;
    wire [4:0] addr;
    wire clk_out, latch, oe;
    wire init_done, error_flag;
    assign init_done = dut.init_done;
    assign error_flag = dut.error_flag;

    integer i;

    always #20 clk = ~clk;

    top dut (
        .clk(clk),
        .rst(rst),
        .spi_cs(spi_cs),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),

        .r0(r0), .g0(g0), .b0(b0),
        .r1(r1), .g1(g1), .b1(b1),

        .addr(addr),
        .clk_out(clk_out),
        .latch(latch),
        .oe(oe)
    );

    task send_spi;
        input [39:0] data;
        integer n;
        begin
            spi_cs = 0;
            #200;

            for (n = 39; n >= 0; n = n-1) begin
                spi_mosi = data[n];
                #500;
                spi_sck = 1;
                #500;
                spi_sck = 0;
            end

            #200;
            spi_cs = 1;
            #1000;
        end
    endtask

    initial begin
        $dumpfile("build/tb_top.vcd");
        $dumpvars(0, tb_top);

        #200;
        rst = 1;

        // Esperar el primer render y el intercambio inicial.
        wait(init_done == 1'b1);
        $display("INIT_DONE activado en t=%0t", $time);

        // Fondo 0.
        send_spi(40'h02_00_00_00_00);

        // Sprite 1 en slot 1, posición (4,24).
        send_spi(40'h01_01_01_04_18);

        // Sprite 2 en slot 0, posición (30,30).
        send_spi(40'h01_00_02_1E_1E);

        // Texto: celda 0, carácter P, color blanco.
        send_spi(40'h05_00_50_FF_FF);

        // Commit.
        send_spi(40'h03_00_00_00_00);

        // Esperar dos ciclos de refresco completos.
        #6000000;

        if (error_flag)
            $display("ERROR: el sistema registró un error.");
        else
            $display("TEST TOP: no se detectaron errores de protocolo.");

        $display("addr=%d RGB_TOP=%b%b%b RGB_BOTTOM=%b%b%b",
                 addr, r0,g0,b0, r1,g1,b1);

        $finish;
    end

endmodule
