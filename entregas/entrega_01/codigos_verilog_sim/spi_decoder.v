module spi_decoder(
    input  wire        clk,
    input  wire        rst,
    input  wire [39:0] raw_data,
    input  wire        data_ready,
    output reg  [23:0] color_out
);
    wire [7:0] cmd = raw_data[39:32];

    always @(posedge clk) begin
        if (rst) begin
            // Rojo brillante por defecto al iniciar
            color_out <= {5'b11111, 3'b000, 5'b00000, 3'b000, 5'b00000, 3'b000};
        end 
        else if (data_ready) begin
            if (cmd == 8'h01) begin
                // Extracción de RGB565 escalada a 24 bits
                color_out <= {
                    raw_data[15:11], 3'b000, // Rojo
                    raw_data[10:6],  3'b000, // Verde
                    raw_data[4:0],   3'b000  // Azul
                };
            end else begin
                // Verde por defecto si llega un comando desconocido
                color_out <= {5'b00000, 3'b000, 5'b11111, 3'b000, 5'b00000, 3'b000};
            end
        end
    end
endmodule
