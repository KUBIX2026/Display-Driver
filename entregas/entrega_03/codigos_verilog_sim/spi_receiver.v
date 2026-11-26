module spi_receiver (
    input  wire        clk,
    input  wire        rst,
    input  wire        spi_cs,
    input  wire        spi_sck,
    input  wire        spi_mosi,
    output reg  [39:0] raw_data,
    output reg         data_ready,
    output reg         frame_error
);

    reg [2:0] cs_sync;
    reg [2:0] sck_sync;
    reg [2:0] mosi_sync;

    reg [39:0] shift_reg;
    reg [5:0] bit_count;
    reg overflow;

    wire cs_falling = (cs_sync[2:1] == 2'b10);
    wire cs_rising  = (cs_sync[2:1] == 2'b01);
    wire sck_rising = (sck_sync[2:1] == 2'b01);

    always @(posedge clk) begin
        if (rst) begin
            cs_sync     <= 3'b111;
            sck_sync    <= 3'b000;
            mosi_sync   <= 3'b000;
            shift_reg   <= 40'd0;
            bit_count   <= 0;
            overflow    <= 0;
            raw_data    <= 0;
            data_ready  <= 0;
            frame_error <= 0;
        end else begin
            cs_sync   <= {cs_sync[1:0], spi_cs};
            sck_sync  <= {sck_sync[1:0], spi_sck};
            mosi_sync <= {mosi_sync[1:0], spi_mosi};

            data_ready  <= 0;
            frame_error <= 0;

            if (cs_falling) begin
                shift_reg <= 0;
                bit_count <= 0;
                overflow  <= 0;
            end

            if (!cs_sync[1] && sck_rising) begin
                if (bit_count < 40) begin
                    shift_reg <= {shift_reg[38:0], mosi_sync[1]};
                    bit_count <= bit_count + 1'b1;
                end else begin
                    overflow <= 1;
                end
            end

            if (cs_rising) begin
                if ((bit_count == 40) && !overflow) begin
                    raw_data   <= shift_reg;
                    data_ready <= 1;
                end else begin
                    frame_error <= 1;
                end
            end
        end
    end
endmodule
