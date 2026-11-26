`timescale 1ns/1ps

module tb_framebuffer;

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

    integer bg;
    integer i;
    integer errors;
    integer timeout_count;
    reg old_front;
    reg [15:0] actual;
    reg [15:0] expected;

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

    task wait_for_swap;
        input old_bank;
        begin
            timeout_count = 0;
            while (dut.SCENE.front_sel == old_bank &&
                   timeout_count < 500000) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_framebuffer.vcd");
        $dumpvars(0, tb_framebuffer);

        errors = 0;

        #200;
        rst = 1;

        timeout_count = 0;
        while (init_done !== 1'b1 && timeout_count < 500000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        if (init_done !== 1'b1) begin
            $display("FAIL: INIT_DONE no se activo.");
            $finish;
        end

        $display("PASS: INIT_DONE activado.");

        // Verificar cada uno de los cuatro fondos.
        for (bg = 0; bg < 4; bg = bg + 1) begin

            old_front = dut.SCENE.front_sel;

            send_spi({8'h02, 8'(bg), 8'h00, 8'h00, 8'h00});
            send_spi(40'h03_00_00_00_00);

            wait_for_swap(old_front);

            if (dut.SCENE.front_sel == old_front) begin
                $display("FAIL: timeout esperando intercambio del fondo %0d", bg);
                errors = errors + 1;
            end else begin

                if (dut.SCENE.active_bg !== bg[7:0]) begin
                    $display("FAIL: active_bg esperado=%0d actual=%0d",
                             bg, dut.SCENE.active_bg);
                    errors = errors + 1;
                end

                for (i = 0; i < 4096; i = i + 1) begin
                    if (dut.SCENE.front_sel == 1'b0)
                        actual = ((i < 2048) ? dut.SCENE.fb_a_top[i] : dut.SCENE.fb_a_bot[i-2048]);
                    else
                        actual = ((i < 2048) ? dut.SCENE.fb_b_top[i] : dut.SCENE.fb_b_bot[i-2048]);

                    expected = dut.SCENE.bg_rom[(bg * 4096) + i];

                    if (actual !== expected) begin
                        if (errors < 10)
                            $display("FAIL fondo %0d pixel %0d: esperado=%h actual=%h",
                                     bg, i, expected, actual);
                        errors = errors + 1;
                    end
                end

                if (errors == 0)
                    $display("PASS: fondo %0d: 4096 píxeles correctos.", bg);
                else
                    $display("Resultado acumulado tras fondo %0d: %0d errores.",
                             bg, errors);
            end
        end

        if (error_flag !== 1'b0) begin
            $display("FAIL: error_flag=%b", error_flag);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS TOTAL: los cuatro fondos son correctos.");
        else
            $display("FAIL TOTAL: errores detectados: %0d", errors);

        $finish;
    end

    initial begin
        #50000000;
        $display("FAIL: timeout general.");
        $finish;
    end

endmodule
