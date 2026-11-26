// Compositor de escena con memorias de lectura síncrona (inferibles como EBR).
//
// Pipeline de render (todas las memorias tienen 1 ciclo de latencia):
//   etapa 0: la FSM presenta la dirección y registra los datos que acompañan
//   etapa 1: llega el dato de la memoria; se calcula el píxel y se escribe
//            en el framebuffer trasero (puerto de escritura único).
//
// Framebuffers: cada uno dividido en mitad superior (filas 0..31) e inferior
// (filas 32..63). Así cada memoria tiene 1 puerto de escritura + 1 de lectura
// y el barrido lee las dos mitades a la vez con la misma dirección.
(* keep_hierarchy *)
module scene_compositor #(
    parameter integer N_SLOTS  = 16,
    parameter integer N_BG     = 4,
    parameter integer FB_SIZE  = 4096,
    parameter integer SPR_SIZE = 8192
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        cmd_valid,
    input  wire        cmd_error,
    input  wire [7:0]  cmd,
    input  wire [7:0]  arg0,
    input  wire [7:0]  arg1,
    input  wire [7:0]  arg2,
    input  wire [7:0]  arg3,
    input  wire [15:0] color,

    input  wire        frame_start,
    input  wire [4:0]  pwm_level,

    input  wire [5:0]  col,
    input  wire [5:0]  row_top,
    input  wire [5:0]  row_bottom,

    // pix_* están retrasados 1 ciclo respecto de col/row_*.
    output wire [15:0] pix_top,
    output wire [15:0] pix_bottom,

    output reg         init_done,
    output reg         error_sticky,
    output wire        render_busy
);

    localparam [15:0] TRANSPARENT = 16'h0843;

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_BG   = 3'd1;
    localparam [2:0] ST_TEXT = 3'd2;
    localparam [2:0] ST_SLOT = 3'd3;
    localparam [2:0] ST_SPR  = 3'd4;
    localparam [2:0] ST_WAIT = 3'd5;
    localparam [2:0] ST_META = 3'd6;

    reg [2:0] state;

    // -----------------------------------------------------
    // ROMs (lectura síncrona).
    // -----------------------------------------------------

    reg [15:0] bg_rom [0:(N_BG*FB_SIZE)-1];
    reg [15:0] sprite_rom [0:SPR_SIZE-1];
    reg [31:0] sprite_meta [0:255];
    reg [7:0]  font_rom [0:2047];

    initial begin
        $readmemh("assets/backgrounds.hex", bg_rom);
        $readmemh("assets/sprites.hex", sprite_rom);
        $readmemh("assets/sprite_meta.hex", sprite_meta);
        $readmemh("assets/font8x8.hex", font_rom);
    end

    reg [15:0] bg_rd;
    reg [15:0] spr_rd;
    reg [31:0] meta_rd;
    reg [7:0]  font_rd;

    // Direcciones (se presentan en la etapa 0).
    reg  [11:0] render_index;
    reg  [7:0]  active_bg;
    reg  [12:0] spr_addr;
    reg  [4:0]  slot_index;

    // Estado activo/shadow como vectores empaquetados (registros simples,
    // sin depender de cómo cada versión de yosys trate los arrays).
    reg [N_SLOTS*8-1:0]  active_id_v;
    reg [N_SLOTS*8-1:0]  active_x_v;     // enteros con signo de 8 bits
    reg [N_SLOTS*8-1:0]  active_y_v;
    reg [N_SLOTS-1:0]    active_visible;
    reg [64*8-1:0]       active_char_v;
    reg [64*16-1:0]      active_text_color_v;
    reg [63:0]           active_text_visible;

    wire [13:0] bg_raddr   = {active_bg[1:0], render_index};
    wire [5:0]  cell_index = {render_index[11:9], render_index[5:3]};

    // Lecturas de la celda de texto y del slot activo como AND-OR de
    // índices constantes (evita desplazadores anchos).
    reg [7:0]  cell_char;
    reg [15:0] cell_color;
    reg        cell_vis;
    reg [7:0]  slot_id, slot_ax, slot_ay;
    reg [3:0]  slot_dummy;
    reg        slot_vis;
    integer    q;

    always @* begin
        cell_char  = 8'd0;
        cell_color = 16'd0;
        cell_vis   = 1'b0;
        for (q = 0; q < 64; q = q + 1) begin
            cell_char  = cell_char  | ({8{cell_index == q}}  & active_char_v[q*8 +: 8]);
            cell_color = cell_color | ({16{cell_index == q}} & active_text_color_v[q*16 +: 16]);
            cell_vis   = cell_vis   | ((cell_index == q)     & active_text_visible[q]);
        end
    end

    wire [10:0] font_addr  = {cell_char, render_index[8:6]};

    always @* begin
        slot_id  = 8'd0;
        slot_vis = 1'b0;
        for (q = 0; q < N_SLOTS; q = q + 1) begin
            slot_id  = slot_id  | ({8{slot_index[3:0] == q}} & active_id_v[q*8 +: 8]);
            slot_vis = slot_vis | ((slot_index[3:0] == q)    & active_visible[q]);
        end
    end

    wire [7:0]  meta_addr  = slot_id;

    always @(posedge clk) begin
        bg_rd   <= bg_rom[bg_raddr];
        spr_rd  <= sprite_rom[spr_addr];
        meta_rd <= sprite_meta[meta_addr];
        font_rd <= font_rom[font_addr];
    end

    // -----------------------------------------------------
    // Framebuffers A/B, mitades superior/inferior.
    // front_sel=0: A visible, B se escribe.
    // front_sel=1: B visible, A se escribe.
    // -----------------------------------------------------

    reg [15:0] fb_a_top [0:2047];
    reg [15:0] fb_a_bot [0:2047];
    reg [15:0] fb_b_top [0:2047];
    reg [15:0] fb_b_bot [0:2047];

    reg front_sel;

    // Lectura del barrido (misma dirección para ambas mitades).
    wire [10:0] raddr = {row_top[4:0], col};

    reg [15:0] rd_a_top, rd_a_bot, rd_b_top, rd_b_bot;
    reg        sel_d;

    always @(posedge clk) begin
        rd_a_top <= fb_a_top[raddr];
        rd_a_bot <= fb_a_bot[raddr];
        rd_b_top <= fb_b_top[raddr];
        rd_b_bot <= fb_b_bot[raddr];
        sel_d    <= front_sel;
    end

    assign pix_top    = sel_d ? rd_b_top : rd_a_top;
    assign pix_bottom = sel_d ? rd_b_bot : rd_a_bot;

    assign render_busy = (state != ST_IDLE) && (state != ST_WAIT);

    // Puerto de escritura único hacia el framebuffer trasero.
    reg         w_en;
    reg  [11:0] w_addr;
    reg  [15:0] w_data;

    wire w_hi = w_addr[11];
    wire [10:0] w_lo = w_addr[10:0];

    always @(posedge clk) begin
        if (w_en && front_sel && !w_hi)  fb_a_top[w_lo] <= w_data;
        if (w_en && front_sel &&  w_hi)  fb_a_bot[w_lo] <= w_data;
        if (w_en && !front_sel && !w_hi) fb_b_top[w_lo] <= w_data;
        if (w_en && !front_sel &&  w_hi) fb_b_bot[w_lo] <= w_data;
    end

    // -----------------------------------------------------
    // Estado shadow / active.
    // -----------------------------------------------------

    reg [7:0] shadow_bg;

    reg [N_SLOTS*8-1:0]  shadow_id_v;
    reg [N_SLOTS*8-1:0]  shadow_x_v;
    reg [N_SLOTS*8-1:0]  shadow_y_v;
    reg [N_SLOTS-1:0]    shadow_visible;
    reg [64*8-1:0]       shadow_char_v;
    reg [64*16-1:0]      shadow_text_color_v;
    reg [63:0]           shadow_text_visible;

    reg pending_commit;

    integer i;

    // -----------------------------------------------------
    // Contadores / registros de la FSM.
    // -----------------------------------------------------

    reg [6:0] spr_x;
    reg [6:0] spr_y;

    reg [7:0] sprite_width;
    reg [7:0] sprite_height;

    // -----------------------------------------------------
    // Registros de la etapa 0 -> 1 (acompañan al dato de memoria).
    // -----------------------------------------------------

    reg         bg_v;
    reg  [11:0] bg_idx_d;

    reg         txt_v;
    reg  [11:0] txt_idx_d;
    reg         txt_vis_d;
    reg  [15:0] txt_col_d;
    reg  [2:0]  txt_x_d;

    reg         spr_v;
    reg  [6:0]  spr_x_d;
    reg  [6:0]  spr_y_d;
    reg  [3:0]  spr_slot_d;

    // -----------------------------------------------------
    // Etapa 1: cálculo del píxel y escritura.
    // -----------------------------------------------------

    reg [7:0] ax, ay;
    integer   r;
    always @* begin
        ax = 8'd0;
        ay = 8'd0;
        for (r = 0; r < N_SLOTS; r = r + 1) begin
            ax = ax | ({8{spr_slot_d == r}} & active_x_v[r*8 +: 8]);
            ay = ay | ({8{spr_slot_d == r}} & active_y_v[r*8 +: 8]);
        end
    end

    wire signed [9:0] sx = {{2{ax[7]}}, ax} + {3'b000, spr_x_d};
    wire signed [9:0] sy = {{2{ay[7]}}, ay} + {3'b000, spr_y_d};

    wire spr_inside = !sx[9] && (sx[8:6] == 3'b000) &&
                      !sy[9] && (sy[8:6] == 3'b000);

    wire txt_on = txt_v && txt_vis_d && font_rd[7 - txt_x_d];

    always @* begin
        w_en   = 1'b0;
        w_addr = 12'd0;
        w_data = 16'd0;

        if (bg_v) begin
            w_en   = 1'b1;
            w_addr = bg_idx_d;
            w_data = bg_rd;
        end else if (txt_v) begin
            w_en   = txt_on;
            w_addr = txt_idx_d;
            w_data = txt_col_d;
        end else if (spr_v) begin
            w_en   = spr_inside && (spr_rd != TRANSPARENT);
            w_addr = {sy[5:0], sx[5:0]};
            w_data = spr_rd;
        end
    end


    // -----------------------------------------------------
    // Registros shadow: un decodificador de escritura por slot / celda
    // (índices constantes: cada elemento es solo FF + habilitación).
    // -----------------------------------------------------

    genvar g;

    generate
        for (g = 0; g < N_SLOTS; g = g + 1) begin : G_SLOT
            always @(posedge clk) begin
                if (rst) begin
                    shadow_id_v[g*8 +: 8] <= 8'd0;
                    shadow_x_v[g*8 +: 8]  <= 8'd0;
                    shadow_y_v[g*8 +: 8]  <= 8'd0;
                    shadow_visible[g]     <= 1'b0;
                end else if (cmd_valid) begin
                    if ((cmd == 8'h01) && (arg0 == g)) begin
                        shadow_id_v[g*8 +: 8] <= arg1;
                        shadow_x_v[g*8 +: 8]  <= arg2;
                        shadow_y_v[g*8 +: 8]  <= arg3;
                        shadow_visible[g]     <= 1'b1;
                    end
                    if ((cmd == 8'h04) && (arg0 == g))
                        shadow_visible[g] <= 1'b0;
                end
            end
        end

        for (g = 0; g < 64; g = g + 1) begin : G_CELL
            always @(posedge clk) begin
                if (rst) begin
                    shadow_char_v[g*8 +: 8]         <= 8'h20;
                    shadow_text_color_v[g*16 +: 16] <= 16'hFFFF;
                    shadow_text_visible[g]          <= 1'b0;
                end else if (cmd_valid) begin
                    if ((cmd == 8'h05) && (arg0 == g)) begin
                        shadow_char_v[g*8 +: 8]         <= arg1;
                        shadow_text_color_v[g*16 +: 16] <= color;
                        shadow_text_visible[g]          <= 1'b1;
                    end
                    if ((cmd == 8'h06) && (arg0 == g))
                        shadow_text_visible[g] <= 1'b0;
                end
            end
        end
    endgenerate

    // -----------------------------------------------------
    // Snapshot.
    // -----------------------------------------------------

    task snapshot_scene;
        begin
            active_bg           <= shadow_bg;
            active_id_v         <= shadow_id_v;
            active_x_v          <= shadow_x_v;
            active_y_v          <= shadow_y_v;
            active_visible      <= shadow_visible;
            active_char_v       <= shadow_char_v;
            active_text_color_v <= shadow_text_color_v;
            active_text_visible <= shadow_text_visible;
        end
    endtask

    // Siguiente slot, o espera si era el último.
    task next_slot;
        begin
            if (slot_index == 0)
                state <= ST_WAIT;
            else begin
                slot_index <= slot_index - 1'b1;
                state <= ST_SLOT;
            end
        end
    endtask

    // -----------------------------------------------------
    // Control principal.
    // -----------------------------------------------------

    always @(posedge clk) begin
        if (rst) begin
            state          <= ST_BG;
            front_sel      <= 1'b0;
            init_done      <= 1'b0;
            error_sticky   <= 1'b0;
            pending_commit <= 1'b0;

            shadow_bg <= 0;
            active_bg <= 0;

            render_index <= 0;
            slot_index   <= 0;
            spr_addr     <= 0;
            spr_x <= 0;
            spr_y <= 0;

            sprite_width  <= 0;
            sprite_height <= 0;

            bg_v  <= 0;
            txt_v <= 0;
            spr_v <= 0;

            active_id_v         <= 0;
            active_x_v          <= 0;
            active_y_v          <= 0;
            active_visible      <= 0;
            active_text_visible <= 0;

            for (i = 0; i < 64; i = i + 1) begin
                active_char_v[i*8 +: 8]         <= 8'h20;
                active_text_color_v[i*16 +: 16] <= 16'hFFFF;
            end
        end else begin

            // Etapa 0 -> 1: banderas y datos que acompañan a la lectura.
            bg_v      <= (state == ST_BG);
            bg_idx_d  <= render_index;

            txt_v     <= (state == ST_TEXT);
            txt_idx_d <= render_index;
            txt_vis_d <= cell_vis;
            txt_col_d <= cell_color;
            txt_x_d   <= render_index[2:0];

            spr_v      <= (state == ST_SPR);
            spr_x_d    <= spr_x;
            spr_y_d    <= spr_y;
            spr_slot_d <= slot_index[3:0];

            // Error sticky: solo se limpia con reset.
            if (cmd_error)
                error_sticky <= 1'b1;

            // ---------------------------------------------
            // Recepción de comandos y actualización shadow.
            // ---------------------------------------------

            if (cmd_valid) begin
                case (cmd)

                    8'h01: begin
                        // Escritura en generate (G_SLOT); aquí solo el error.
                        if (!(arg0 < N_SLOTS))
                            error_sticky <= 1'b1;
                    end

                    8'h02: begin
                        if (arg0 < N_BG)
                            shadow_bg <= arg0;
                        else
                            error_sticky <= 1'b1;
                    end

                    8'h03: begin
                        if ((state == ST_IDLE) && !pending_commit) begin
                            snapshot_scene();
                            render_index <= 0;
                            state <= ST_BG;
                        end else begin
                            // Un único COMMIT pendiente:
                            // la escena shadow más reciente gana.
                            pending_commit <= 1'b1;
                        end
                    end

                    8'h04: begin
                        if (!(arg0 < N_SLOTS))
                            error_sticky <= 1'b1;
                    end

                    8'h05: begin
                        if (!(arg0 < 64))
                            error_sticky <= 1'b1;
                    end

                    8'h06: begin
                        if (!(arg0 < 64))
                            error_sticky <= 1'b1;
                    end

                    default: error_sticky <= 1'b1;

                endcase
            end

            case (state)

                // Fase 1: fondo -> framebuffer trasero.
                ST_BG: begin
                    if (render_index == 4095) begin
                        render_index <= 0;
                        state <= ST_TEXT;
                    end else begin
                        render_index <= render_index + 1'b1;
                    end
                end

                // Fase 2: texto sobre el fondo.
                ST_TEXT: begin
                    if (render_index == 4095) begin
                        render_index <= 0;
                        slot_index <= 15;
                        state <= ST_SLOT;
                    end else begin
                        render_index <= render_index + 1'b1;
                    end
                end

                // Fase 3: slot de sprite (15 -> 0; el slot 0 queda encima).
                // Se presenta la dirección de metadatos.
                ST_SLOT: begin
                    if (slot_vis)
                        state <= ST_META;
                    else
                        next_slot();
                end

                // Metadatos disponibles.
                ST_META: begin
                    sprite_height <= meta_rd[31:24];
                    sprite_width  <= meta_rd[23:16];
                    spr_addr      <= meta_rd[12:0];
                    spr_x         <= 0;
                    spr_y         <= 0;

                    if ((meta_rd[31:24] != 0) && (meta_rd[23:16] != 0))
                        state <= ST_SPR;
                    else
                        next_slot();
                end

                // Fase 4: píxeles del sprite (dirección incremental).
                ST_SPR: begin
                    spr_addr <= spr_addr + 1'b1;

                    if ({1'b0, spr_x} == sprite_width - 8'd1) begin
                        spr_x <= 0;

                        if ({1'b0, spr_y} == sprite_height - 8'd1)
                            next_slot();
                        else
                            spr_y <= spr_y + 1'b1;
                    end else begin
                        spr_x <= spr_x + 1'b1;
                    end
                end

                // Fase 5: esperar el punto seguro de intercambio.
                // El último píxel aún pendiente se escribe en el primer
                // ciclo de espera, antes de que front_sel pueda cambiar.
                ST_WAIT: begin
                    if (frame_start && (pwm_level == 5'd31)) begin
                        front_sel <= ~front_sel;
                        init_done <= 1'b1;
                        state <= ST_IDLE;

                        if (pending_commit) begin
                            pending_commit <= 1'b0;
                            snapshot_scene();
                            render_index <= 0;
                            state <= ST_BG;
                        end
                    end
                end

                ST_IDLE: begin
                    if (pending_commit) begin
                        pending_commit <= 1'b0;
                        snapshot_scene();
                        render_index <= 0;
                        state <= ST_BG;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    error_sticky <= 1'b1;
                end

            endcase
        end
    end

endmodule
