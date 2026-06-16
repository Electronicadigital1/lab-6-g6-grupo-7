module i2c_send (
    input  wire       clk,
    input  wire       send,
    input  wire [7:0] data,
    output reg        scl,
    inout  wire       sda,
    output reg        busy,
    output reg        done
);

parameter PHASE = 7'd124;

reg [6:0] phase_cnt;
reg [1:0] phase;
reg [2:0] bit_cnt;
reg [2:0] state;
reg [7:0] shift;
reg       sda_out;
reg       sda_oe;

assign sda = sda_oe ? sda_out : 1'bz;

localparam IDLE  = 3'd0,
           START = 3'd1,
           ADDR  = 3'd2,
           ACK1  = 3'd3,
           DATA  = 3'd4,
           ACK2  = 3'd5,
           STOP  = 3'd6,
           DONE  = 3'd7;

always @(posedge clk) begin
    done <= 1'b0;

    case (state)

        IDLE: begin
            scl       <= 1'b1;
            sda_out   <= 1'b1;
            sda_oe    <= 1'b1;
            busy      <= 1'b0;
            phase_cnt <= 7'd0;
            phase     <= 2'd0;
            if (send) begin
                busy  <= 1'b1;
                state <= START;
            end
        end

        START: begin
            if (phase_cnt == PHASE) begin
                phase_cnt <= 7'd0;
                phase     <= phase + 2'd1;
                case (phase)
                    2'd0: begin scl <= 1'b1; sda_out <= 1'b1; end
                    2'd1: begin scl <= 1'b1; sda_out <= 1'b0; end
                    2'd2: begin scl <= 1'b0; sda_out <= 1'b0; end
                    2'd3: begin
                        shift   <= {7'h27, 1'b0};
                        bit_cnt <= 3'd7;
                        phase   <= 2'd0;
                        state   <= ADDR;
                    end
                endcase
            end else begin
                phase_cnt <= phase_cnt + 7'd1;
            end
        end

        ADDR: begin
            if (phase_cnt == PHASE) begin
                phase_cnt <= 7'd0;
                phase     <= phase + 2'd1;
                case (phase)
                    2'd0: begin scl <= 1'b0; sda_out <= shift[7]; end
                    2'd1: begin scl <= 1'b1; end
                    2'd2: begin scl <= 1'b1; end
                    2'd3: begin
                        scl   <= 1'b0;
                        shift <= {shift[6:0], 1'b0};
                        phase <= 2'd0;
                        if (bit_cnt == 3'd0) begin
                            state <= ACK1;
                        end else begin
                            bit_cnt <= bit_cnt - 3'd1;
                        end
                    end
                endcase
            end else begin
                phase_cnt <= phase_cnt + 7'd1;
            end
        end

        ACK1: begin
            if (phase_cnt == PHASE) begin
                phase_cnt <= 7'd0;
                phase     <= phase + 2'd1;
                case (phase)
                    2'd0: begin scl <= 1'b0; sda_oe <= 1'b0; end
                    2'd1: begin scl <= 1'b1; end
                    2'd2: begin scl <= 1'b1; end
                    2'd3: begin
                        scl     <= 1'b0;
                        sda_oe  <= 1'b1;
                        shift   <= data;
                        bit_cnt <= 3'd7;
                        phase   <= 2'd0;
                        state   <= DATA;
                    end
                endcase
            end else begin
                phase_cnt <= phase_cnt + 7'd1;
            end
        end

        DATA: begin
            if (phase_cnt == PHASE) begin
                phase_cnt <= 7'd0;
                phase     <= phase + 2'd1;
                case (phase)
                    2'd0: begin scl <= 1'b0; sda_out <= shift[7]; end
                    2'd1: begin scl <= 1'b1; end
                    2'd2: begin scl <= 1'b1; end
                    2'd3: begin
                        scl   <= 1'b0;
                        shift <= {shift[6:0], 1'b0};
                        phase <= 2'd0;
                        if (bit_cnt == 3'd0) begin
                            state <= ACK2;
                        end else begin
                            bit_cnt <= bit_cnt - 3'd1;
                        end
                    end
                endcase
            end else begin
                phase_cnt <= phase_cnt + 7'd1;
            end
        end

        ACK2: begin
            if (phase_cnt == PHASE) begin
                phase_cnt <= 7'd0;
                phase     <= phase + 2'd1;
                case (phase)
                    2'd0: begin scl <= 1'b0; sda_oe <= 1'b0; end
                    2'd1: begin scl <= 1'b1; end
                    2'd2: begin scl <= 1'b1; end
                    2'd3: begin
                        scl     <= 1'b0;
                        sda_oe  <= 1'b1;
                        sda_out <= 1'b0;
                        phase   <= 2'd0;
                        state   <= STOP;
                    end
                endcase
            end else begin
                phase_cnt <= phase_cnt + 7'd1;
            end
        end

        STOP: begin
            if (phase_cnt == PHASE) begin
                phase_cnt <= 7'd0;
                phase     <= phase + 2'd1;
                case (phase)
                    2'd0: begin scl <= 1'b0; sda_out <= 1'b0; end
                    2'd1: begin scl <= 1'b1; sda_out <= 1'b0; end
                    2'd2: begin scl <= 1'b1; sda_out <= 1'b1; end
                    2'd3: begin
                        state <= DONE;
                    end
                endcase
            end else begin
                phase_cnt <= phase_cnt + 7'd1;
            end
        end

        DONE: begin
            done  <= 1'b1;
            busy  <= 1'b0;
            state <= IDLE;
        end

    endcase
end

endmodule