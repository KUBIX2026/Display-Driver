`timescale 1ns / 1ps

module top_TB;

    // Entradas
    reg clk;
    reg rst;
    reg spi_cs;
    reg spi_sck;
    reg spi_mosi;

    // Salidas
    wire r0, g0, b0;
    wire r1, g1, b1;
    wire [4:0] addr;
    wire clk_out;
    wire latch;
    wire oe;

    // Instancia del módulo superior (DUT)
    top UUT (
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

    // Generador de Reloj del Sistema (25 MHz -> Periodo de 40ns)
    always #20 clk = ~clk;

    // Tarea para emular la transmisión SPI desde la ESP32 (Modo 0, 1MHz)
    task send_spi_40bit;
        input [39:0] data;
        integer i;
        begin
            spi_cs = 0; // Inicia transmisión (CS bajo)
            #100;
            
            for (i = 39; i >= 0; i = i - 1) begin
                spi_mosi = data[i]; // Coloca el bit
                #500;               // Espera medio ciclo
                spi_sck = 1;        // Flanco de subida (captura)
                #500;               // Mantiene por medio ciclo
                spi_sck = 0;        // Flanco de bajada
            end
            
            #100;
            spi_cs = 1; // Termina transmisión (CS alto)
            #1000;
        end
    endtask

    initial begin
        // Configuración requerida para GTKWave
        $dumpfile("build/hub75_simulation.vcd");
        $dumpvars(0, top_TB);

        // 1. Inicialización
        clk = 0;
        rst = 1; 
        spi_cs = 1; // SPI inactivo
        spi_sck = 0;
        spi_mosi = 0;

        // 2. Liberación del Reset
        #100;
        rst = 0; 
        #200;

        // 3. Emular envío de ESP32: [Cmd:0x01] [ID:0x00] [X:0x0A] [Color:0xF800]
        send_spi_40bit(40'h01_00_0A_F8_00);

        // 4. Dejar correr el barrido HUB75 para observarlo en GTKWave
        #250000;

        $display("Simulación terminada.");
        $finish;
    end

endmodule
