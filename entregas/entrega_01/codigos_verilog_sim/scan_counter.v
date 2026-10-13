module scan_counters(
    input  wire clk,
    input  wire rst,

    output reg [5:0] col,
    output reg [4:0] scan_row,
    output reg [4:0] addr_out,
    
    // 8bpp [7:0], 5bpp [4:0]
    output reg [4:0] pwm_level, 
    
    output wire [5:0] row_top,
    output wire [5:0] row_bottom
);

    always @(posedge clk) begin
        if (rst) begin
            col <= 0;
            scan_row <= 0;
            addr_out <= 0;
            pwm_level <= 0;
        end else begin
            // 1. Columnas
            col <= col + 1;
            if (col == 63) begin
                col <= 0;
            end

            // 2. Sincronización de Fila
            if (col == 0) begin
                addr_out <= scan_row; 
            end

            // 3. Filas y Niveles de Brillo
            if (col == 1) begin
                scan_row <= scan_row + 1;
                
                if (scan_row == 31) begin
                    scan_row <= 0;
                    pwm_level <= pwm_level + 1; 
                end
            end
        end
    end

    assign row_top    = {1'b0, scan_row}; 
    assign row_bottom = {1'b1, scan_row}; 

endmodule
