module top (
    input  wire clk,
    inout  wire sda,
    output wire scl
);

reg        i2c_send;
reg  [7:0] i2c_data;
wire       i2c_busy;
wire       i2c_done;

i2c_send u_i2c (
    .clk  (clk),
    .send (i2c_send),
    .data (i2c_data),
    .scl  (scl),
    .sda  (sda),
    .busy (i2c_busy),
    .done (i2c_done)
);

// ------------------------------------------------
// Init sequence (igual que antes)
// ------------------------------------------------
reg [7:0] init_seq [0:27];
initial begin
    init_seq[0]  = 8'h3C; init_seq[1]  = 8'h38;
    init_seq[2]  = 8'h3C; init_seq[3]  = 8'h38;
    init_seq[4]  = 8'h3C; init_seq[5]  = 8'h38;
    init_seq[6]  = 8'h2C; init_seq[7]  = 8'h28;
    init_seq[8]  = 8'h2C; init_seq[9]  = 8'h28;
    init_seq[10] = 8'h8C; init_seq[11] = 8'h88;
    init_seq[12] = 8'h0C; init_seq[13] = 8'h08;
    init_seq[14] = 8'h8C; init_seq[15] = 8'h88;
    init_seq[16] = 8'h0C; init_seq[17] = 8'h08;
    init_seq[18] = 8'h1C; init_seq[19] = 8'h18;
    init_seq[20] = 8'h0C; init_seq[21] = 8'h08;
    init_seq[22] = 8'h6C; init_seq[23] = 8'h68;
    init_seq[24] = 8'h0C; init_seq[25] = 8'h08;
    init_seq[26] = 8'hCC; init_seq[27] = 8'hC8;
end

// ------------------------------------------------
// Texto: "Puto el que lo lea" (18 chars)
// Se escribe UNA SOLA VEZ desde la posicion DDRAM 0x54
// (segunda linea, para que empiece fuera del area visible)
// Usamos linea 1 col 0 + activamos display shift
// Estrategia: ponemos los 18 chars en DDRAM[0..17] (linea 1)
// luego hacemos 34 shifts a la izquierda con delay entre cada uno
// ------------------------------------------------
reg [7:0] txt [0:17];
initial begin
    txt[0]  = 8'h50; txt[1]  = 8'h75; txt[2]  = 8'h74;
    txt[3]  = 8'h6F; txt[4]  = 8'h20; txt[5]  = 8'h65;
    txt[6]  = 8'h6C; txt[7]  = 8'h20; txt[8]  = 8'h71;
    txt[9]  = 8'h75; txt[10] = 8'h65; txt[11] = 8'h20;
    txt[12] = 8'h6C; txt[13] = 8'h6F; txt[14] = 8'h20;
    txt[15] = 8'h6C; txt[16] = 8'h65; txt[17] = 8'h61;
end

// ------------------------------------------------
// Comando "Cursor Home" (0x02): vuelve display al origen
// 4 bytes I2C
// ------------------------------------------------
reg [7:0] home_seq [0:3];
initial begin
    home_seq[0] = 8'h0C; // nibble alto 0x0, EN=1
    home_seq[1] = 8'h08; // EN=0
    home_seq[2] = 8'h2C; // nibble bajo 0x2, EN=1
    home_seq[3] = 8'h28; // EN=0
end

// ------------------------------------------------
// Comando "Shift Display Left" (0x18): 4 bytes I2C
// {0x1, BL=1, EN=1, RW=0, RS=0} = 0x1C
// {0x1, BL=1, EN=0, RW=0, RS=0} = 0x18
// {0x8, BL=1, EN=1, RW=0, RS=0} = 0x8C
// {0x8, BL=1, EN=0, RW=0, RS=0} = 0x88
// ------------------------------------------------
reg [7:0] shift_seq [0:3];
initial begin
    shift_seq[0] = 8'h1C;
    shift_seq[1] = 8'h18;
    shift_seq[2] = 8'h8C;
    shift_seq[3] = 8'h88;
end

// ------------------------------------------------
// Delay
// ------------------------------------------------
reg [24:0] delay_cnt;
reg        delay_done;
reg [24:0] delay_val;

always @(posedge clk) begin
    if (delay_cnt == delay_val) begin
        delay_done <= 1'b1;
        delay_cnt  <= 25'd0;
    end else begin
        delay_done <= 1'b0;
        delay_cnt  <= delay_cnt + 25'd1;
    end
end

// ------------------------------------------------
// FSM
// ------------------------------------------------
localparam S_WAIT_INIT   = 4'd0,
           S_INIT        = 4'd1,
           S_INIT_WAIT   = 4'd2,
           S_INIT_DELAY  = 4'd3,
           S_HOME        = 4'd4,   // cursor home antes de escribir
           S_HOME_WAIT   = 4'd5,
           S_WRITE       = 4'd6,   // escribe los 18 chars una vez
           S_WRITE_WAIT  = 4'd7,
           S_WRITE_DELAY = 4'd8,
           S_SHIFT_WAIT  = 4'd9,   // espera entre shifts (velocidad scroll)
           S_SHIFT        = 4'd10,  // envia un byte del comando shift
           S_SHIFT_BYTE_WAIT = 4'd11, // espera done de cada byte shift
           S_HOME2       = 4'd12,  // cursor home para reiniciar posicion display
           S_HOME2_WAIT  = 4'd13;

reg [3:0]  state;
reg [4:0]  init_idx;
reg [4:0]  txt_idx;
reg [1:0]  nibble_phase;
reg [5:0]  shift_count;   // cuantos shifts llevamos (max 34)
reg [1:0]  seq_idx;       // indice dentro de shift_seq / home_seq
reg        doing_home2;   // flag para reusar estados home

always @(posedge clk) begin
    i2c_send <= 1'b0;

    case (state)

        // ---- Init igual que antes ----
        S_WAIT_INIT: begin
            delay_val <= 25'd2_499_999;
            if (delay_done) begin
                init_idx <= 5'd0;
                state    <= S_INIT;
            end
        end

        S_INIT: begin
            if (!i2c_busy) begin
                i2c_data <= init_seq[init_idx];
                i2c_send <= 1'b1;
                state    <= S_INIT_WAIT;
            end
        end

        S_INIT_WAIT: begin
            if (i2c_done) begin
                delay_val <= (init_idx == 5'd19) ? 25'd99_999 : 25'd4_999;
                state     <= S_INIT_DELAY;
            end
        end

        S_INIT_DELAY: begin
            if (delay_done) begin
                if (init_idx == 5'd27) begin
                    seq_idx <= 2'd0;
                    state   <= S_HOME;
                end else begin
                    init_idx <= init_idx + 5'd1;
                    state    <= S_INIT;
                end
            end
        end

        // ---- Cursor Home: manda home_seq[0..3] ----
        S_HOME: begin
            if (!i2c_busy) begin
                i2c_data <= home_seq[seq_idx];
                i2c_send <= 1'b1;
                state    <= S_HOME_WAIT;
            end
        end

        S_HOME_WAIT: begin
            if (i2c_done) begin
                if (seq_idx == 2'd3) begin
                    delay_val <= 25'd99_999; // 2ms tras home
                    // despues del home, escribir chars
                    txt_idx      <= 5'd0;
                    nibble_phase <= 2'd0;
                    // pequeño delay y a escribir
                    state <= S_WRITE_DELAY; // reutilizamos el delay state
                    // (al llegar ahi con delay_val ya seteado va a S_WRITE)
                    // En realidad usemos un estado de espera distinto:
                    state <= S_HOME_WAIT; // NO — fix: vamos directo
                    // simplificacion: delay breve y luego S_WRITE
                    delay_val <= 25'd4_999;
                    state     <= S_INIT_DELAY; // NO reutilizar — usa delay generico
                    // MEJOR: simplemente ir a S_WRITE directo tras done
                    // y quitar el delay aqui. El home tarda 1.52ms internamente.
                    state <= S_WRITE;
                end else begin
                    seq_idx <= seq_idx + 2'd1;
                    state   <= S_HOME;
                end
            end
        end

        // ---- Escribe los 18 chars (solo la primera vez y al reiniciar) ----
        // Cada char = 4 bytes I2C (2 nibbles × EN hi/lo)
        S_WRITE: begin
            if (!i2c_busy) begin
                case (nibble_phase)
                    2'd0: i2c_data <= {txt[txt_idx][7:4], 4'hD}; // hi EN=1 RS=1
                    2'd1: i2c_data <= {txt[txt_idx][7:4], 4'h9}; // hi EN=0 RS=1
                    2'd2: i2c_data <= {txt[txt_idx][3:0], 4'hD}; // lo EN=1 RS=1
                    2'd3: i2c_data <= {txt[txt_idx][3:0], 4'h9}; // lo EN=0 RS=1
                endcase
                i2c_send <= 1'b1;
                state    <= S_WRITE_WAIT;
            end
        end

        S_WRITE_WAIT: begin
            if (i2c_done) begin
                delay_val <= 25'd4_999; // 100us entre bytes
                state     <= S_WRITE_DELAY;
            end
        end

        S_WRITE_DELAY: begin
            if (delay_done) begin
                if (nibble_phase == 2'd3) begin
                    nibble_phase <= 2'd0;
                    if (txt_idx == 5'd17) begin
                        // texto completo escrito, comenzar scroll
                        // primero hacemos home para llevar display al inicio
                        seq_idx     <= 2'd0;
                        shift_count <= 6'd0;
                        // El display shift va relativo a la posicion actual del display
                        // No necesitamos home aqui — simplemente empezamos a shiftear
                        // 34 shifts = 16 (texto entra) + 18 (texto sale)
                        state <= S_SHIFT_WAIT;
                        delay_val <= 25'd4_999_999; // 100ms antes del primer shift
                    end else begin
                        nibble_phase <= 2'd0;
                        txt_idx      <= txt_idx + 5'd1;
                        state        <= S_WRITE;
                    end
                end else begin
                    nibble_phase <= nibble_phase + 2'd1;
                    state        <= S_WRITE;
                end
            end
        end

        // ---- Espera entre shifts (velocidad del scroll) ----
        S_SHIFT_WAIT: begin
            // 100ms = 5_000_000 ciclos a 50MHz  → scroll lento
            //  80ms = 4_000_000                 → scroll medio
            //  60ms = 3_000_000                 → scroll rapido
            delay_val <= 25'd12_499_999; // ajusta aqui la velocidad
            if (delay_done) begin
                seq_idx <= 2'd0;
                state   <= S_SHIFT;
            end
        end

        // ---- Envia los 4 bytes del comando Shift Display Left ----
        S_SHIFT: begin
            if (!i2c_busy) begin
                i2c_data <= shift_seq[seq_idx];
                i2c_send <= 1'b1;
                state    <= S_SHIFT_BYTE_WAIT;
            end
        end

        S_SHIFT_BYTE_WAIT: begin
    if (i2c_done) begin
        if (seq_idx == 2'd3) begin
            if (shift_count == 6'd39) begin
                shift_count <= 6'd0;
                state       <= S_SHIFT_WAIT;
            end else begin
                shift_count <= shift_count + 6'd1;
                state       <= S_SHIFT_WAIT;
            end
        end else begin
            seq_idx <= seq_idx + 2'd1;
            state   <= S_SHIFT;
        end
    end
end

        // ---- Home + reescritura para reiniciar ciclo ----
        // El HD44780 tiene DDRAM circular: despues de 34 shifts
        // el contenido esta donde empezo. Solo hacemos home del display.
        S_HOME2: begin
            if (!i2c_busy) begin
                i2c_data <= home_seq[seq_idx];
                i2c_send <= 1'b1;
                state    <= S_HOME2_WAIT;
            end
        end

        S_HOME2_WAIT: begin
            if (i2c_done) begin
                if (seq_idx == 2'd3) begin
                    // display volvio al inicio, reiniciar shift counter
                    shift_count <= 6'd0;
                    delay_val   <= 25'd4_999_999; // pausa antes de repetir
                    state       <= S_SHIFT_WAIT;
                end else begin
                    seq_idx <= seq_idx + 2'd1;
                    state   <= S_HOME2;
                end
            end
        end

    endcase
end

endmodule