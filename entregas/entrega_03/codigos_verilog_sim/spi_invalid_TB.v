`timescale 1ns/1ps

module tb_spi_invalid;

    reg clk = 0;
    reg rst = 0;
    reg spi_cs = 1;
    reg spi_sck = 0;
    reg spi_mosi = 0;

    wire r0, g0, b0, r1, g1, b1;
    wire [4:0] addr;
    wire clk_out, latch, oe;
    wire init_done, error_flag;
    assign init_done = dut.init_done;
    assign error_flag = dut.error_flag;

    integer errors = 0;
    integer tests = 0;

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

    task reset_system;
        begin
            spi_cs = 1;
            spi_sck = 0;
            spi_mosi = 0;
            rst = 0;
            #500;
            rst = 1;
            wait (init_done == 1'b1);
            #200;
        end
    endtask

    // Envía exactamente "bits" bits, MSB primero.
    // data[40:0] permite probar tramas de 39, 40 y 41 bits.
    task send_frame;
        input [40:0] data;
        input integer bits;
        integer n;
        begin
            spi_cs = 0;
            #200;
            for (n = bits-1; n >= 0; n = n-1) begin
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

    task expect_error;
        input [40:0] data;
        input integer bits;
        input [255:0] label_text;
        begin
            send_frame(data, bits);
            tests = tests + 1;
            if (error_flag !== 1'b1) begin
                $display("FAIL: %0s: error_flag no se activo", label_text);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", label_text);
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_spi_invalid.vcd");
        $dumpvars(0, tb_spi_invalid);

        // 1. Trama válida: 40 bits y sin error.
        reset_system();
        send_frame({1'b0, 40'h02_00_00_00_00}, 40);
        tests = tests + 1;
        if (error_flag !== 1'b0) begin
            $display("FAIL: trama valida de 40 bits genero error");
            errors = errors + 1;
        end else begin
            $display("PASS: trama valida de 40 bits");
        end

        // 2. Trama incompleta: 39 bits.
        reset_system();
        expect_error({1'b0, 40'h01_00_01_04_08}, 39,
                     "trama incompleta de 39 bits");

        // 3. Trama excedida: 41 bits.
        reset_system();
        expect_error({1'b0, 40'h01_00_01_04_08}, 41,
                     "trama excedida de 41 bits");

        // 4. Comandos inválidos. Se agrupan porque error_flag es sticky.
        reset_system();

        expect_error({1'b0, 40'h07_00_00_00_00}, 40,
                     "opcode desconocido");

        // COMMIT con argumentos no nulos.
        send_frame({1'b0, 40'h03_01_00_00_00}, 40);
        tests = tests + 1;
        if (error_flag !== 1'b1) begin
            $display("FAIL: COMMIT con argumento invalido");
            errors = errors + 1;
        end else $display("PASS: COMMIT con argumento invalido");

        // SET_BG fuera de rango (N_BG = 4).
        send_frame({1'b0, 40'h02_04_00_00_00}, 40);
        tests = tests + 1;
        if (error_flag !== 1'b1) begin
            $display("FAIL: SET_BG fuera de rango");
            errors = errors + 1;
        end else $display("PASS: SET_BG fuera de rango");

        // SET_BG con byte reservado distinto de cero.
        send_frame({1'b0, 40'h02_00_01_00_00}, 40);
        tests = tests + 1;
        if (error_flag !== 1'b1) begin
            $display("FAIL: SET_BG con byte reservado");
            errors = errors + 1;
        end else $display("PASS: SET_BG con byte reservado");

        // SET_SPRITE con slot 16 (N_SLOTS = 16).
        send_frame({1'b0, 40'h01_10_01_04_08}, 40);
        tests = tests + 1;
        if (error_flag !== 1'b1) begin
            $display("FAIL: SET_SPRITE con slot fuera de rango");
            errors = errors + 1;
        end else $display("PASS: SET_SPRITE con slot fuera de rango");

        // HIDE_SPRITE con slot 16.
        send_frame({1'b0, 40'h04_10_00_00_00}, 40);
        tests = tests + 1;
        if (error_flag !== 1'b1) begin
            $display("FAIL: HIDE_SPRITE con slot fuera de rango");
            errors = errors + 1;
        end else $display("PASS: HIDE_SPRITE con slot fuera de rango");

        // SET_TEXT_CELL con celda 64.
        send_frame({1'b0, 40'h05_40_41_FF_FF}, 40);
        tests = tests + 1;
        if (error_flag !== 1'b1) begin
            $display("FAIL: SET_TEXT_CELL con celda fuera de rango");
            errors = errors + 1;
        end else $display("PASS: SET_TEXT_CELL con celda fuera de rango");

        // HIDE_TEXT_CELL con celda 64.
        send_frame({1'b0, 40'h06_40_00_00_00}, 40);
        tests = tests + 1;
        if (error_flag !== 1'b1) begin
            $display("FAIL: HIDE_TEXT_CELL con celda fuera de rango");
            errors = errors + 1;
        end else $display("PASS: HIDE_TEXT_CELL con celda fuera de rango");

        // Comprobar que los comandos rechazados no cambiaron el fondo shadow.
        tests = tests + 1;
        if (dut.SCENE.shadow_bg !== 0) begin
            $display("FAIL: shadow_bg cambio tras comandos invalidos: %0d",
                     dut.SCENE.shadow_bg);
            errors = errors + 1;
        end else begin
            $display("PASS: shadow_bg no fue modificado");
        end

        // Comprobar que el slot 0 sigue oculto.
        tests = tests + 1;
        if (dut.SCENE.shadow_visible[0] !== 1'b0) begin
            $display("FAIL: slot 0 fue modificado indebidamente");
            errors = errors + 1;
        end else begin
            $display("PASS: slot 0 no fue modificado");
        end

        // Comprobar que la celda 0 sigue oculta.
        tests = tests + 1;
        if (dut.SCENE.shadow_text_visible[0] !== 1'b0) begin
            $display("FAIL: celda de texto 0 fue modificada");
            errors = errors + 1;
        end else begin
            $display("PASS: celda de texto 0 no fue modificada");
        end

        // El error debe permanecer activo hasta reset.
        #2000;
        tests = tests + 1;
        if (error_flag !== 1'b1) begin
            $display("FAIL: error_flag no permanecio activo");
            errors = errors + 1;
        end else begin
            $display("PASS: error_flag sticky");
        end

        if (errors == 0)
            $display("PASS TOTAL: %0d comprobaciones correctas.", tests);
        else
            $display("FAIL TOTAL: %0d errores de %0d comprobaciones.",
                     errors, tests);

        $finish;
    end

endmodule
