module delay_unit (
    input  wire clk,
    input  wire rst,
    input  wire [5:0] col,

    output wire clk_out,
    output reg latch,
    output reg oe
);
    // Desfase de reloj
    assign clk_out = ~clk;

    always @(posedge clk) begin
        if (rst) begin
            latch <= 0;
            oe    <= 1; 
        end else begin
            latch <= 0;
            oe    <= 0;

            // Latch al inicio de línea
            if (col == 0) begin
                latch <= 1; 
                oe    <= 1;
            end
            else if (col == 63) begin
                oe <= 1;
            end
        end
    end
endmodule
