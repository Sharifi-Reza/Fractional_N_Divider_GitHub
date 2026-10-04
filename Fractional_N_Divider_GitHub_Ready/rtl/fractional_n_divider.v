`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Fractional-N Divider - Week 4 final RTL
//
// Corrected architecture:
//   - No clock mux between raw clk and a generated clock
//   - No break-before-make dead time
//   - Rising edges are produced on clk posedge
//   - In N=1 mode, falling edges are produced on clk negedge
//
// Modes:
//   N=1 : output period = 1 * T_RO, 50% duty cycle
//   N=2 : output period = 2 * T_RO, 1 cycle high / 1 cycle low
//   N=3 : output period = 3 * T_RO, 1 cycle high / 2 cycles low
//
// N_sel is sampled only at a complete output-period boundary.
// Encoding:
//   00 -> 1
//   01 -> 2
//   10 -> 3
//   11 -> 2 (safe default)
//
// INT65K_CLK is generated as the XOR of two edge-triggered registers.
// Only q_pos changes on the rising edge and only q_neg changes on the
// falling edge, so the XOR output cannot produce a combinational glitch
// during normal operation.
//------------------------------------------------------------------------------

module fractional_n_divider (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] N_sel,
    output wire       INT65K_CLK
);

    reg [1:0] counter;
    reg [1:0] N_sel_current;
    reg [1:0] N_decoded;

    // Dual-edge output implementation.
    reg q_pos;
    reg q_neg;

    wire [1:0] active_mode;

    //----------------------------------------------------------------------
    // N_sel decoder
    //
    // Written without a full case statement to avoid the Genus
    // "unreachable default case" warning.
    //----------------------------------------------------------------------
    always @(*) begin
        if (N_sel == 2'b00)
            N_decoded = 2'd1;
        else if (N_sel == 2'b10)
            N_decoded = 2'd3;
        else
            N_decoded = 2'd2; // 01, 11 and unknown-safe fallback
    end

    //----------------------------------------------------------------------
    // When counter is zero, the previous complete period has finished.
    // Therefore the new command may be used for the period starting now.
    //----------------------------------------------------------------------
    assign active_mode =
        (counter == 2'd0) ? N_decoded : N_sel_current;

    //----------------------------------------------------------------------
    // Glitch-free output
    //----------------------------------------------------------------------
    assign INT65K_CLK = q_pos ^ q_neg;

    //----------------------------------------------------------------------
    // Rising-edge process
    //
    // q_pos is chosen so that q_pos XOR q_neg becomes the desired output
    // level immediately after the rising edge.
    //----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter       <= 2'd0;
            N_sel_current <= 2'd2;
            q_pos         <= 1'b0;
        end else begin

            // Sample a new division command only at a full-period boundary.
            if (counter == 2'd0)
                N_sel_current <= N_decoded;

            case (active_mode)

                //----------------------------------------------------------
                // N = 1
                //
                // Output goes high on every rising edge.
                // The negedge process returns it low.
                //----------------------------------------------------------
                2'd1: begin
                    counter <= 2'd0;

                    // q_pos XOR q_neg = 1
                    q_pos <= ~q_neg;
                end

                //----------------------------------------------------------
                // N = 2
                //
                // counter=0: begin high cycle
                // counter=1: begin low cycle
                //----------------------------------------------------------
                2'd2: begin
                    if (counter == 2'd0) begin
                        counter <= 2'd1;

                        // Desired output after this edge: 1
                        q_pos <= ~q_neg;
                    end else begin
                        counter <= 2'd0;

                        // Desired output after this edge: 0
                        q_pos <= q_neg;
                    end
                end

                //----------------------------------------------------------
                // N = 3
                //
                // counter=0: high
                // counter=1: low
                // counter=2: low
                //----------------------------------------------------------
                2'd3: begin
                    if (counter == 2'd0) begin
                        counter <= 2'd1;

                        // Desired output after this edge: 1
                        q_pos <= ~q_neg;
                    end else if (counter == 2'd1) begin
                        counter <= 2'd2;

                        // Desired output after this edge: 0
                        q_pos <= q_neg;
                    end else begin
                        counter <= 2'd0;

                        // Remain low until the following period begins.
                        q_pos <= q_neg;
                    end
                end

                //----------------------------------------------------------
                // Defensive fallback: divide-by-2 behavior
                //----------------------------------------------------------
                default: begin
                    if (counter == 2'd0) begin
                        counter <= 2'd1;
                        q_pos   <= ~q_neg;
                    end else begin
                        counter <= 2'd0;
                        q_pos   <= q_neg;
                    end
                end

            endcase
        end
    end

    //----------------------------------------------------------------------
    // Falling-edge process
    //
    // Only N=1 requires an output transition at the falling edge.
    // For N=2 and N=3, q_neg is held so the output remains unchanged.
    //----------------------------------------------------------------------
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_neg <= 1'b0;
        end else if (N_sel_current == 2'd1) begin

            // q_pos XOR q_neg = 0
            q_neg <= q_pos;
        end
    end

endmodule