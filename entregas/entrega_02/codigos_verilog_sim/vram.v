module vram(
    input  wire        clk,
    
    // Puerto de escritura (Desde SPI Decoder)
    input  wire        we,           // Write Enable
    input  wire [5:0]  write_x,      // Posición X (0-63)
    input  wire [5:0]  write_y,      // Posición Y (0-63)
    input  wire [23:0] write_color,  // Color a pintar
    
    // Puerto de lectura (Hacia el panel HUB75)
    input  wire [10:0] read_addr,    // Dirección generada por scan_counters
    output reg  [23:0] pix_top,
    output reg  [23:0] pix_bottom
);
    // Memoria dividida en Mitad Superior (Filas 0-31) e Inferior (Filas 32-63)
    reg [23:0] mem_top [0:2047];
    reg [23:0] mem_bottom [0:2047];

    wire [10:0] write_addr = {write_y[4:0], write_x}; // Y (5 bits) + X (6 bits)

    // Inicializar memoria en negro
    integer i;
    initial begin
        for (i = 0; i < 2048; i = i + 1) begin
            mem_top[i] = 24'd0;
            mem_bottom[i] = 24'd0;
        end
    end

    always @(posedge clk) begin
        // 1. Escritura desde SPI (Actualización síncrona del framebuffer)
        if (we) begin
            if (write_y < 32)
                mem_top[write_addr] <= write_color;
            else
                mem_bottom[write_addr] <= write_color;
        end

        // 2. Lectura constante hacia el panel LED
        pix_top    <= mem_top[read_addr];
        pix_bottom <= mem_bottom[read_addr];
    end
endmodule
