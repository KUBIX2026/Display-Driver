`timescale 1ns/1ps

module tb_pending_commit;

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

    task check_front_bg;
        input integer bg_id;
        begin
            for (i = 0; i < 4096; i = i + 1) begin
                if (dut.SCENE.front_sel == 0)
                    actual = ((i < 2048) ? dut.SCENE.fb_a_top[i] : dut.SCENE.fb_a_bot[i-2048]);
                else
                    actual = ((i < 2048) ? dut.SCENE.fb_b_top[i] : dut.SCENE.fb_b_bot[i-2048]);

                expected = dut.SCENE.bg_rom[(bg_id * 4096) + i];

                if (actual !== expected) begin
                    if (errors < 10)
                        $display("FAIL fondo %0d pixel %0d esperado=%h actual=%h",
                                 bg_id, i, expected, actual);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_pending_commit.vcd");
        $dumpvars(0, tb_pending_commit);

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

        // Esperar a que el compositor quede libre tras la inicializacion.
        timeout_count = 0;
        while (dut.SCENE.state !== 3'd0 && timeout_count < 500000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        if (dut.SCENE.state !== 3'd0) begin
            $display("FAIL: compositor no llego a ST_IDLE.");
            $finish;
        end

        // Configurar fondo 0 e iniciar primer render.
        send_spi(40'h02_00_00_00_00);

        old_front = dut.SCENE.front_sel;
        send_spi(40'h03_00_00_00_00);

        if (dut.SCENE.render_busy !== 1'b1) begin
            $display("FAIL: el primer render no comenzo.");
            $finish;
        end

        $display("PASS: primer render iniciado.");

        // Esperar hasta que el render este avanzado, pero no terminado.
        timeout_count = 0;
        while (dut.SCENE.render_index < 12'd100 &&
               timeout_count < 10000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        if (dut.SCENE.render_index < 12'd100 ||
            dut.SCENE.render_busy !== 1'b1) begin
            $display("FAIL: no se pudo sincronizar durante el render.");
            $finish;
        end

        // Modificar shadow y solicitar segundo COMMIT durante el primero.
        send_spi(40'h02_01_00_00_00);
        send_spi(40'h03_00_00_00_00);

        if (dut.SCENE.pending_commit !== 1'b1) begin
            $display("FAIL: pending_commit no se activo.");
            errors = errors + 1;
        end else begin
            $display("PASS: COMMIT pendiente registrado.");
        end

        if (dut.SCENE.active_bg !== 0) begin
            $display("FAIL: active_bg cambio durante el primer render.");
            errors = errors + 1;
        end else begin
            $display("PASS: snapshot activo permanecio en fondo 0.");
        end

        // Esperar primer intercambio.
        wait_for_swap(old_front);

        if (dut.SCENE.front_sel == old_front) begin
            $display("FAIL: timeout del primer intercambio.");
            $finish;
        end

        $display("Primer framebuffer intercambiado.");
        check_front_bg(0);

        if (errors == 0)
            $display("PASS: primer framebuffer conserva fondo 0.");

        // El segundo render debe arrancar automaticamente.
        timeout_count = 0;
        while (dut.SCENE.state !== 3'd1 &&
               timeout_count < 500000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        if (dut.SCENE.state !== 3'd1) begin
            $display("FAIL: segundo render pendiente no comenzo.");
            errors = errors + 1;
        end else begin
            $display("PASS: segundo render comenzo.");
        end

        if (dut.SCENE.active_bg !== 1) begin
            $display("FAIL: segundo snapshot no contiene fondo 1.");
            errors = errors + 1;
        end else begin
            $display("PASS: segundo snapshot contiene fondo 1.");
        end

        // Esperar segundo intercambio.
        old_front = dut.SCENE.front_sel;
        wait_for_swap(old_front);

        if (dut.SCENE.front_sel == old_front) begin
            $display("FAIL: timeout del segundo intercambio.");
            $finish;
        end

        $display("Segundo framebuffer intercambiado.");
        check_front_bg(1);

        if (errors == 0)
            $display("PASS: segundo framebuffer conserva fondo 1.");

        if (error_flag !== 1'b0) begin
            $display("FAIL: error_flag=%b", error_flag);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS TOTAL: COMMIT pendiente correcto.");
        else
            $display("FAIL TOTAL: %0d errores.", errors);

        $finish;
    end

    initial begin
        #100000000;
        $display("FAIL: timeout general.");
        $finish;
    end

endmodule
