module scan_counters (
    input  wire       clk,
    input  wire       rst,

    output reg  [5:0] col,
    output reg  [4:0] scan_row,
    output reg  [4:0] addr_out,
    output reg  [4:0] pwm_level,

    output wire [5:0] row_top,
    output wire [5:0] row_bottom,
    output reg        frame_start
);

    always @(posedge clk) begin
        if (rst) begin
            col         <= 0;
            scan_row    <= 0;
            addr_out    <= 0;
            pwm_level   <= 0;
            frame_start <= 0;
        end else begin
            frame_start <= 0;

            if (col == 63)
                col <= 0;
            else
                col <= col + 1'b1;

            // Cada línea son exactamente las columnas 0..63.
            // La fila, la dirección y el nivel PWM cambian en el borde
            // que pasa de col 63 a col 0.
            if (col == 63) begin
                addr_out <= scan_row;

                if (scan_row == 31) begin
                    scan_row  <= 0;
                    pwm_level <= pwm_level + 1'b1;
                end else begin
                    scan_row <= scan_row + 1'b1;
                end
            end

            // frame_start en el ciclo col=63 de la última línea del último
            // nivel PWM: el intercambio de buffer queda efectivo en col=0.
            if ((col == 62) && (scan_row == 31) && (pwm_level == 31))
                frame_start <= 1;
        end
    end

    assign row_top    = {1'b0, scan_row};
    assign row_bottom = {1'b1, scan_row};

endmodule
