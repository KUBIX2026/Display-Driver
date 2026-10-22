module spi_decoder(
    input  wire        clk,
    input  wire        rst,
    input  wire [39:0] raw_data,
    input  wire        data_ready,
    
    // Salidas hacia la VRAM
    output reg  [5:0]  x_out,
    output reg  [5:0]  y_out,
    output reg  [23:0] color_out,
    output reg         we_out
);
    wire [7:0] cmd = raw_data[39:32];

    always @(posedge clk) begin
        if (rst) begin
            we_out <= 0;
            x_out  <= 0;
            y_out  <= 0;
            color_out <= 0;
        end
        else begin
            we_out <= 0; // Por defecto no escribe
            
            if (data_ready && cmd == 8'h01) begin
                // Byte 2 y 3: Coordenadas
                x_out <= raw_data[31:24]; 
                y_out <= raw_data[23:16]; 
                
                // Byte 4 y 5: Color RGB565 convertido a 24 bits
                color_out <= {
                    raw_data[15:11], 3'b000, // Rojo
                    raw_data[10:5],  2'b00,  // Verde
                    raw_data[4:0],   3'b000  // Azul
                };
                we_out <= 1; // Envía un pulso para guardar el píxel en la VRAM
            end
        end
    end
endmodule
