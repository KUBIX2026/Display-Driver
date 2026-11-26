module spi_decoder (
    input  wire        clk,
    input  wire        rst,
    input  wire [39:0] raw_data,
    input  wire        data_ready,
    input  wire        frame_error,

    output reg         cmd_valid,
    output reg         cmd_error,
    output reg  [7:0]  cmd,
    output reg  [7:0]  arg0,
    output reg  [7:0]  arg1,
    output reg  [7:0]  arg2,
    output reg  [7:0]  arg3,
    output reg  [15:0] color
);

    wire [7:0] op = raw_data[39:32];
    wire [7:0] b1 = raw_data[31:24];
    wire [7:0] b2 = raw_data[23:16];
    wire [7:0] b3 = raw_data[15:8];
    wire [7:0] b4 = raw_data[7:0];

    always @(posedge clk) begin
        if (rst) begin
            cmd_valid <= 0;
            cmd_error <= 0;
            cmd       <= 0;
            arg0      <= 0;
            arg1      <= 0;
            arg2      <= 0;
            arg3      <= 0;
            color     <= 0;
        end else begin
            cmd_valid <= 0;
            cmd_error <= 0;

            if (frame_error) begin
                cmd_error <= 1;
            end else if (data_ready) begin
                case (op)
                    8'h01: begin
                        // SET_SPRITE: slot, id, X signed, Y signed.
                        cmd       <= op;
                        arg0      <= b1;
                        arg1      <= b2;
                        arg2      <= b3;
                        arg3      <= b4;
                        color     <= 0;
                        cmd_valid <= 1;
                    end

                    8'h02: begin
                        // SET_BG.
                        if ((b2 == 0) && (b3 == 0) && (b4 == 0)) begin
                            cmd       <= op;
                            arg0      <= b1;
                            arg1      <= 0;
                            arg2      <= 0;
                            arg3      <= 0;
                            color     <= 0;
                            cmd_valid <= 1;
                        end else cmd_error <= 1;
                    end

                    8'h03: begin
                        // COMMIT.
                        if ((b1 == 0) && (b2 == 0) &&
                            (b3 == 0) && (b4 == 0)) begin
                            cmd       <= op;
                            arg0      <= 0;
                            arg1      <= 0;
                            arg2      <= 0;
                            arg3      <= 0;
                            color     <= 0;
                            cmd_valid <= 1;
                        end else cmd_error <= 1;
                    end

                    8'h04: begin
                        // HIDE_SPRITE.
                        if ((b2 == 0) && (b3 == 0) && (b4 == 0)) begin
                            cmd       <= op;
                            arg0      <= b1;
                            arg1      <= 0;
                            arg2      <= 0;
                            arg3      <= 0;
                            color     <= 0;
                            cmd_valid <= 1;
                        end else cmd_error <= 1;
                    end

                    8'h05: begin
                        // EXTENSIÓN: SET_TEXT_CELL.
                        if (b1 < 64) begin
                            cmd       <= op;
                            arg0      <= b1;
                            arg1      <= b2;
                            arg2      <= 0;
                            arg3      <= 0;
                            color     <= {b3,b4};
                            cmd_valid <= 1;
                        end else cmd_error <= 1;
                    end

                    8'h06: begin
                        // EXTENSIÓN: HIDE_TEXT_CELL.
                        if ((b1 < 64) && (b2 == 0) &&
                            (b3 == 0) && (b4 == 0)) begin
                            cmd       <= op;
                            arg0      <= b1;
                            arg1      <= 0;
                            arg2      <= 0;
                            arg3      <= 0;
                            color     <= 0;
                            cmd_valid <= 1;
                        end else cmd_error <= 1;
                    end

                    default: cmd_error <= 1;
                endcase
            end
        end
    end
endmodule
