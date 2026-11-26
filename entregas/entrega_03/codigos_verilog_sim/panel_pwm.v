module panel_pwm (
    input  wire [15:0] pix_top,
    input  wire [15:0] pix_bottom,
    input  wire [4:0]  pwm_level,

    output wire r0, g0, b0,
    output wire r1, g1, b1
);

    wire [4:0] tr = pix_top[15:11];
    wire [4:0] tg = pix_top[10:6];
    wire [4:0] tb = pix_top[4:0];

    wire [4:0] br = pix_bottom[15:11];
    wire [4:0] bg = pix_bottom[10:6];
    wire [4:0] bb = pix_bottom[4:0];

    assign r0 = tr > pwm_level;
    assign g0 = tg > pwm_level;
    assign b0 = tb > pwm_level;

    assign r1 = br > pwm_level;
    assign g1 = bg > pwm_level;
    assign b1 = bb > pwm_level;

endmodule
