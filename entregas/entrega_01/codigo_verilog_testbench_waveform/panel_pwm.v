module panel_pwm( 
    input  wire [23:0] pix_top,
    input  wire [23:0] pix_bottom,
    
    // s8bpp [7:0], 5bpp [4:0]
    input  wire [4:0]  pwm_level, 
    
    output wire r0, g0, b0,
    output wire r1, g1, b1
);

    // 1. Extraer el BYTE COMPLETO (8 bits) de cada color
    //    Rojo (23..16), Verde (15..8), Azul (7..0)
    /*
    wire [7:0] val_tR = pix_top[23:16];
    wire [7:0] val_tG = pix_top[15:8];
    wire [7:0] val_tB = pix_top[7:0];

    wire [7:0] val_bR = pix_bottom[23:16];
    wire [7:0] val_bG = pix_bottom[15:8];
    wire [7:0] val_bB = pix_bottom[7:0];
    */
    wire [4:0] val_tR = pix_top[23:19];
    wire [4:0] val_tG = pix_top[15:11];
    wire [4:0] val_tB = pix_top[7:3];

    wire [4:0] val_bR = pix_bottom[23:19];
    wire [4:0] val_bG = pix_bottom[15:11];
    wire [4:0] val_bB = pix_bottom[7:3];
    // 2. Lógica de Comparación
    // Esto genera 256 niveles de intensidad.
    
    assign r0 = (val_tR > pwm_level);
    assign g0 = (val_tG > pwm_level);
    assign b0 = (val_tB > pwm_level);

    assign r1 = (val_bR > pwm_level);
    assign g1 = (val_bG > pwm_level);
    assign b1 = (val_bB > pwm_level);

endmodule
