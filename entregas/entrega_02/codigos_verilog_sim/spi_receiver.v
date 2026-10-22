module spi_receiver(
    input  wire        clk,        // Reloj del sistema (25 MHz)
    input  wire        rst,
    input  wire        spi_cs,     // Chip Select
    input  wire        spi_sck,    // Reloj del SPI
    input  wire        spi_mosi,   // Datos de la ESP32
    output reg  [39:0] raw_data,   // Trama cruda de 40 bits
    output reg         data_ready  // Pulso que avisa "¡Llegó un paquete!"
);
    // Sincronizadores para evitar ruido al leer pines externos
    reg [2:0] cs_sync, sck_sync, mosi_sync;
    always @(posedge clk) begin
        if (rst) begin
            cs_sync <= 3'b111; sck_sync <= 3'b000; mosi_sync <= 3'b000;
        end else begin
            cs_sync   <= {cs_sync[1:0], spi_cs};
            sck_sync  <= {sck_sync[1:0], spi_sck};
            mosi_sync <= {mosi_sync[1:0], spi_mosi};
        end
    end

    wire cs_rising  = (cs_sync[2:1] == 2'b01);
    wire sck_rising = (sck_sync[2:1] == 2'b01);

    reg [39:0] shift_reg;

    always @(posedge clk) begin
        if (rst) begin
            raw_data   <= 0;
            data_ready <= 0;
            shift_reg  <= 0;
        end else begin
            data_ready <= 0; // Por defecto apagado
            
            // Si CS está activo (bajo) y el reloj SPI sube, guardamos 1 bit
            if (!cs_sync[1] && sck_rising) begin
                shift_reg <= {shift_reg[38:0], mosi_sync[1]};
            end
            
            // Si CS sube, terminó la transmisión. Entregamos el paquete.
            if (cs_rising) begin
                raw_data   <= shift_reg;
                data_ready <= 1;
            end
        end
    end
endmodule
