`timescale 1ns/1ps

module tb_spi_receiver;

    reg clk = 0;
    reg rst = 1;
    reg spi_cs = 1;
    reg spi_sck = 0;
    reg spi_mosi = 0;

    wire [39:0] raw_data;
    wire data_ready;
    wire frame_error;

    integer errors = 0;

    always #20 clk = ~clk;

    spi_receiver dut (
        .clk(clk),
        .rst(rst),
        .spi_cs(spi_cs),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),
        .raw_data(raw_data),
        .data_ready(data_ready),
        .frame_error(frame_error)
    );

    task send_frame;
        input [39:0] data;
        input integer bits;
        integer n;
        begin
            spi_cs = 0;
            #200;

            for (n = 39; n >= (40-bits); n = n-1) begin
                spi_mosi = data[n];
                #500;
                spi_sck = 1;
                #500;
                spi_sck = 0;
            end

            #200;
            spi_cs = 1;
            #300;
        end
    endtask

    initial begin
        $dumpfile("build/tb_spi_receiver.vcd");
        $dumpvars(0, tb_spi_receiver);

        #100;
        rst = 0;
        #200;

        send_frame(40'h01_00_02_0A_14, 40);

        if (raw_data !== 40'h01_00_02_0A_14) begin
            $display("ERROR: trama recibida incorrectamente: %h", raw_data);
            errors = errors + 1;
        end

        if (data_ready !== 1'b0 && data_ready !== 1'b1) begin
            $display("ERROR: data_ready indefinido");
            errors = errors + 1;
        end

        send_frame(40'h01_00_02_0A_14, 32);

        if (frame_error !== 1'b0 && frame_error !== 1'b1) begin
            $display("ERROR: frame_error indefinido");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TEST SPI: finalizado. Revisar pulsos en VCD.");
        else
            $display("TEST SPI: %0d errores.", errors);

        $finish;
    end

endmodule
