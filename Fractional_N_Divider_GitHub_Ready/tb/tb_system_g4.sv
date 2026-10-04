`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Week-4 self-checking integration testbench using the actual Group-4 SDM.
//
// Chain under test:
//   Group-4 sdm_mash11 -> fractional_n_divider -> external T-FF
//
// The same TB supports:
//   1) G4 RTL SDM + our RTL divider
//   2) G4 post-synthesis SDM/SDF + our RTL divider (G4_POSTSYN)
//   3) G4 RTL SDM + our post-synthesis divider (DIVIDER_POSTSYN)
//   4) both blocks post-synthesis (both defines)
//------------------------------------------------------------------------------
module tb_system_g4;

    localparam real T_RO       = 7629.39;
    localparam real HALF_T_RO  = T_RO / 2.0;
    localparam real GLITCH_MIN = HALF_T_RO - 100.0;
    localparam real SAMPLE_DELAY_NS = 20.0; // exceeds G4 reported 12.875 ns path
    localparam real RESET_GUARD_NS = 100.0; // keep reset transitions away from clock edges

`ifdef FULL_SIM
    localparam integer LARGE_SAMPLES = 20000;
    localparam integer PPM_SAMPLES   = 100000;
`else
    localparam integer LARGE_SAMPLES = 2000;
    localparam integer PPM_SAMPLES   = 10000;
`endif

    reg                      clk;
    reg                      rst_n;
    reg signed [23:0]        epsilon_RO;
    reg                      dither_en;
    wire [1:0]               N_sel;
    wire                     INT65K_CLK;
    wire                     CLK32K;

    integer pass_cnt;
    integer fail_cnt;
    integer log_fd;
    integer boundary_fail_cnt;
    integer invalid_seen_total;

    realtime last_int_edge;
    realtime pulse_width;

    reg [1:0] counter_before_edge;
    reg [1:0] previous_active_n;
    reg [1:0] command_before_int_edge;

    frac_div_g4_top dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .epsilon_RO (epsilon_RO),
        .dither_en  (dither_en),
        .N_sel      (N_sel),
        .INT65K_CLK (INT65K_CLK),
        .CLK32K     (CLK32K)
    );

    initial begin
        clk = 1'b0;
        forever #(HALF_T_RO) clk = ~clk;
    end

`ifdef G4_POSTSYN
  `ifdef DIVIDER_POSTSYN
    initial begin
        $dumpfile("sim/gate/tb_system_both_postsyn.vcd");
        $dumpvars(0, tb_system_g4);
        log_fd = $fopen("sim/gate/tb_system_both_postsyn.log", "w");
        if (log_fd == 0) log_fd = 32'h8000_0001;
    end
  `else
    initial begin
        $dumpfile("sim/gate/tb_system_g4_postsyn.vcd");
        $dumpvars(0, tb_system_g4);
        log_fd = $fopen("sim/gate/tb_system_g4_postsyn.log", "w");
        if (log_fd == 0) log_fd = 32'h8000_0001;
    end
  `endif
`elsif DIVIDER_POSTSYN
    initial begin
        $dumpfile("sim/gate/tb_system_divider_postsyn.vcd");
        $dumpvars(0, tb_system_g4);
        log_fd = $fopen("sim/gate/tb_system_divider_postsyn.log", "w");
        if (log_fd == 0) log_fd = 32'h8000_0001;
    end
`else
    initial begin
        $dumpfile("sim/rtl/tb_system_g4.vcd");
        $dumpvars(0, tb_system_g4);
        log_fd = $fopen("sim/rtl/tb_system_g4.log", "w");
        if (log_fd == 0) log_fd = 32'h8000_0001;
    end
`endif

`ifdef G4_POSTSYN
    initial begin
        $sdf_annotate(
            "external/g4_sdm/synthesis/synout/sdm_mash11_postsyn.sdf",
            dut.u_sdm, , , "MAXIMUM"
        );
    end
`endif

`ifdef DIVIDER_POSTSYN
    initial begin
        $sdf_annotate(
            "netlist/fractional_n_divider_postsyn.sdf",
            dut.u_div_system.u_div, , , "MAXIMUM"
        );
    end
`endif


    // Global watchdog prevents an undriven/stuck clock from hanging a batch run.
    initial begin
        #(3.0e10);
        $display("[FATAL] tb_system_g4 timeout");
        $fdisplay(log_fd, "FATAL: tb_system_g4 timeout");
        fail_cnt = fail_cnt + 1;
        $fclose(log_fd);
        $finish;
    end

    task check_true;
        input [8*96-1:0] name;
        input cond;
        begin
            if (cond) begin
                $display(" -> PASS: %0s", name);
                $fdisplay(log_fd, "PASS: %0s", name);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display(" -> FAIL: %0s", name);
                $fdisplay(log_fd, "FAIL: %0s", name);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task reset_case;
        input signed [23:0] eps_value;
        input               dith_value;

        integer retry;
        reg     reset_ok;

        begin
            //------------------------------------------------------------------
            // Assert asynchronous reset between raw-clock edges.
            //
            // INT65K_CLK transitions are derived from clk edges, so asserting
            // reset RESET_GUARD_NS after a negedge avoids races with both the
            // RTL divider and the post-synthesis SDM/divider netlists.
            //------------------------------------------------------------------
            if (rst_n !== 1'b0) begin
                @(negedge clk);
                #(RESET_GUARD_NS);
                rst_n = 1'b0;
            end

            //------------------------------------------------------------------
            // Change functional inputs only after reset has been asserted and
            // the gate-level combinational network has had time to settle.
            //------------------------------------------------------------------
            #(RESET_GUARD_NS);
            epsilon_RO = eps_value;
            dither_en  = dith_value;

            //------------------------------------------------------------------
            // Hold reset for several raw-clock cycles.  This is intentionally
            // conservative because the integrated design contains both RTL
            // and SDF-annotated sequential cells.
            //------------------------------------------------------------------
            repeat (4) @(posedge clk);
            #(SAMPLE_DELAY_NS);

            //------------------------------------------------------------------
            // Allow a short settling window for the post-synthesis SDM reset
            // value to propagate.  In reset the expected chain state is:
            //   N_sel      = 2'b01  (divide by 2)
            //   INT65K_CLK = 0
            //   CLK32K     = 0
            //------------------------------------------------------------------
            reset_ok = 1'b0;

            begin : wait_for_reset_state
                for (retry = 0; retry < 20; retry = retry + 1) begin
                    #(SAMPLE_DELAY_NS);

                    if ((N_sel      === 2'b01) &&
                        (INT65K_CLK === 1'b0)  &&
                        (CLK32K     === 1'b0)) begin
                        reset_ok = 1'b1;
                        disable wait_for_reset_state;
                    end
                end
            end

            $display(
                " RESET_OBSERVE: rst_n=%b N_sel=%b INT65K_CLK=%b CLK32K=%b",
                rst_n, N_sel, INT65K_CLK, CLK32K
            );
            $fdisplay(
                log_fd,
                "RESET_OBSERVE rst_n=%b N_sel=%b INT65K_CLK=%b CLK32K=%b",
                rst_n, N_sel, INT65K_CLK, CLK32K
            );

            check_true(
                "reset forces N_sel=divide-by-2 and both output clocks low",
                reset_ok
            );

            //------------------------------------------------------------------
            // Release reset between raw-clock edges to satisfy recovery and
            // removal timing for both posedge- and negedge-triggered cells.
            //------------------------------------------------------------------
            @(negedge clk);
            #(RESET_GUARD_NS);
            rst_n = 1'b1;

            //------------------------------------------------------------------
            // Let the complete SDM -> divider -> T-FF chain restart before
            // measurements begin.
            //------------------------------------------------------------------
            repeat (12) @(posedge INT65K_CLK);
            #(SAMPLE_DELAY_NS);
        end
    endtask

    task run_case;
        input [8*48-1:0] case_name;
        input signed [23:0] eps_value;
        input dith_value;
        input integer sample_periods;
        input real avg_tolerance;
        input real freq_tolerance_percent;

        integer i;
        integer eps_integer;
        integer gen_n1;
        integer gen_n2;
        integer gen_n3;
        integer app_n1;
        integer app_n2;
        integer app_n3;
        integer invalid_count;
        integer active_n;
        realtime start_time;
        realtime end_time;
        realtime t32_a;
        realtime t32_b;
        real eps_real;
        real expected_avg_n;
        real generated_avg_n;
        real applied_avg_n;
        real measured_f_int_khz;
        real expected_f_int_khz;
        real measured_f_32k_khz;
        real avg_error;
        real freq_error_percent;
        real f32_error_percent;
        begin
            $display("\n------------------------------------------------------------");
            $display("CASE: %0s  epsilon=0x%06h  dither=%0d  samples=%0d",
                     case_name, eps_value, dith_value, sample_periods);
            $fdisplay(log_fd,
                      "CASE: %0s epsilon=0x%06h dither=%0d samples=%0d",
                      case_name, eps_value, dith_value, sample_periods);

            reset_case(eps_value, dith_value);

            gen_n1 = 0;
            gen_n2 = 0;
            gen_n3 = 0;
            app_n1 = 0;
            app_n2 = 0;
            app_n3 = 0;
            invalid_count = 0;

            @(posedge INT65K_CLK);
            start_time = $realtime;
            for (i = 0; i < sample_periods; i = i + 1) begin
                #(SAMPLE_DELAY_NS);

                case (N_sel)
                    2'b00: gen_n1 = gen_n1 + 1;
                    2'b01: gen_n2 = gen_n2 + 1;
                    2'b10: gen_n3 = gen_n3 + 1;
                    default: invalid_count = invalid_count + 1;
                endcase

                // N_sel captured on the preceding INT65K falling edge is
                // the command that is stable before this period boundary.
                case (command_before_int_edge)
                    2'b00: active_n = 1;
                    2'b01: active_n = 2;
                    2'b10: active_n = 3;
                    2'b11: begin
                        active_n = 2;
                        invalid_count = invalid_count + 1;
                    end
                    default: begin
                        active_n = 2;
                        invalid_count = invalid_count + 1;
                    end
                endcase

                case (active_n)
                    1: app_n1 = app_n1 + 1;
                    2: app_n2 = app_n2 + 1;
                    3: app_n3 = app_n3 + 1;
                    default: invalid_count = invalid_count + 1;
                endcase

                @(posedge INT65K_CLK);
            end
            end_time = $realtime;

            generated_avg_n =
                (1.0*gen_n1 + 2.0*gen_n2 + 3.0*gen_n3) /
                (1.0*(gen_n1 + gen_n2 + gen_n3));
            applied_avg_n =
                (1.0*app_n1 + 2.0*app_n2 + 3.0*app_n3) /
                (1.0*(app_n1 + app_n2 + app_n3));

            eps_integer = $signed(eps_value);
            eps_real = $itor(eps_integer) / 8388608.0;
            expected_avg_n = 2.0 * (1.0 + eps_real);
            if (expected_avg_n > 3.0) expected_avg_n = 3.0;
            if (expected_avg_n < 1.0) expected_avg_n = 1.0;

            expected_f_int_khz = 131.072 / expected_avg_n;
            measured_f_int_khz =
                sample_periods /
                ((end_time-start_time)/1.0e9) /
                1000.0;

            @(posedge CLK32K); t32_a = $realtime;
            repeat (200) @(posedge CLK32K);
            t32_b = $realtime;
            measured_f_32k_khz =
                200.0 / ((t32_b-t32_a)/1.0e9) / 1000.0;

            avg_error = applied_avg_n - expected_avg_n;
            if (avg_error < 0.0) avg_error = -avg_error;

            freq_error_percent =
                ((measured_f_int_khz-expected_f_int_khz) /
                 expected_f_int_khz) * 100.0;
            if (freq_error_percent < 0.0)
                freq_error_percent = -freq_error_percent;

            f32_error_percent =
                ((measured_f_32k_khz-(measured_f_int_khz/2.0)) /
                 (measured_f_int_khz/2.0)) * 100.0;
            if (f32_error_percent < 0.0)
                f32_error_percent = -f32_error_percent;

            $display(" generated histogram: N1=%0d N2=%0d N3=%0d avg=%0.7f",
                     gen_n1, gen_n2, gen_n3, generated_avg_n);
            $display(" applied   histogram: N1=%0d N2=%0d N3=%0d avg=%0.7f expected=%0.7f",
                     app_n1, app_n2, app_n3, applied_avg_n, expected_avg_n);
            $display(" INT65K: measured=%0.7f kHz expected=%0.7f kHz error=%0.5f%%",
                     measured_f_int_khz, expected_f_int_khz,
                     freq_error_percent);
            $display(" CLK32K: measured=%0.7f kHz half(INT65K) error=%0.5f%%",
                     measured_f_32k_khz, f32_error_percent);

            $fdisplay(log_fd,
                      "RESULT_DATA %0s gen_avg=%0.9f app_avg=%0.9f exp_avg=%0.9f f_int=%0.9f exp_f=%0.9f f32=%0.9f invalid=%0d",
                      case_name, generated_avg_n, applied_avg_n,
                      expected_avg_n, measured_f_int_khz,
                      expected_f_int_khz, measured_f_32k_khz,
                      invalid_count);

            check_true("Group-4 SDM never emits invalid N_sel=2'b11",
                       invalid_count == 0);
            check_true("divider-applied average N matches requested average",
                       avg_error <= avg_tolerance);
            check_true("measured INT65K average frequency matches theory",
                       freq_error_percent <= freq_tolerance_percent);
            check_true("external T-FF frequency is one half of INT65K",
                       f32_error_percent <= freq_tolerance_percent);

            invalid_seen_total = invalid_seen_total + invalid_count;
        end
    endtask

    // Capture the command that is stable before the next rising-edge period
    // boundary. This remains observable even when the Divider is a gate netlist.
    initial command_before_int_edge = 2'b01;
    always @(negedge rst_n) command_before_int_edge = 2'b01;
    always @(negedge INT65K_CLK) begin
        if (rst_n)
            command_before_int_edge = N_sel;
    end

    // Glitch monitor. Asynchronous reset transitions are intentionally ignored.
    initial last_int_edge = 0.0;
    always @(negedge rst_n) last_int_edge = 0.0;
    always @(INT65K_CLK) begin
        if (rst_n && (last_int_edge > 0.0)) begin
            pulse_width = $realtime - last_int_edge;
            if (pulse_width < GLITCH_MIN) begin
                $display("[FATAL] runt/glitch width=%0.2f ns at t=%0.2f ns",
                         pulse_width, $realtime);
                $fdisplay(log_fd, "FATAL: runt/glitch width=%0.2f time=%0.2f",
                          pulse_width, $realtime);
                fail_cnt = fail_cnt + 1;
                $fclose(log_fd);
                $finish;
            end
        end
        if (rst_n)
            last_int_edge = $realtime;
    end

`ifndef DIVIDER_POSTSYN
    // Verify that the divider's active ratio changes only after a complete
    // period. This checker observes the RTL divider, which remains RTL in both
    // G4 integration modes.
    initial begin
        counter_before_edge = 2'd0;
        previous_active_n   = 2'd2;
    end
    always @(negedge rst_n) begin
        counter_before_edge = 2'd0;
        previous_active_n   = 2'd2;
    end
    always @(negedge clk) begin
        if (rst_n)
            counter_before_edge = dut.u_div_system.u_div.counter;
    end
    always @(posedge clk) begin
        #1;
        if (rst_n &&
            (dut.u_div_system.u_div.N_sel_current !== previous_active_n)) begin
            if (counter_before_edge != 2'd0) begin
                boundary_fail_cnt = boundary_fail_cnt + 1;
                $display("[FAIL] active N changed before period boundary at t=%0.2f ns",
                         $realtime);
                $fdisplay(log_fd, "FAIL: active N changed mid-period at %0.2f",
                          $realtime);
            end
            previous_active_n = dut.u_div_system.u_div.N_sel_current;
        end
    end

`endif

    initial begin
        pass_cnt          = 0;
        fail_cnt          = 0;
        boundary_fail_cnt = 0;
        invalid_seen_total = 0;
        rst_n             = 1'b0;
        epsilon_RO        = 24'sd0;
        dither_en         = 1'b0;

        #1;
        $display("============================================================");
`ifdef G4_POSTSYN
  `ifdef DIVIDER_POSTSYN
        $display(" Week-4 integration: BOTH POST-SYN + MAXIMUM SDF");
        $fdisplay(log_fd,
                  "Week-4 integration: BOTH POST-SYN + MAXIMUM SDF");
  `else
        $display(" Week-4 integration: G4 POST-SYN SDM + RTL divider + T-FF");
        $fdisplay(log_fd,
                  "Week-4 integration: G4 POST-SYN SDM + RTL divider + T-FF");
  `endif
`elsif DIVIDER_POSTSYN
        $display(" Week-4 integration: G4 RTL SDM + POST-SYN divider + T-FF");
        $fdisplay(log_fd,
                  "Week-4 integration: G4 RTL SDM + POST-SYN divider + T-FF");
`else
        $display(" Week-4 integration: G4 RTL SDM + RTL divider + T-FF");
        $fdisplay(log_fd,
                  "Week-4 integration: G4 RTL SDM + RTL divider + T-FF");
`endif
        $display("============================================================");

        run_case("Zero",             24'sh000000, 1'b0,
                 LARGE_SAMPLES, 0.005, 0.50);
        run_case("Plus_0.25",        24'sh200000, 1'b0,
                 LARGE_SAMPLES, 0.010, 0.50);
        run_case("Minus_0.25",       24'shE00000, 1'b0,
                 LARGE_SAMPLES, 0.010, 0.50);
        run_case("Exact_Plus_50ppm", 24'sh0001A3, 1'b0,
                 PPM_SAMPLES, 0.001, 0.50);
        run_case("Exact_Minus_50ppm",24'shFFFE5D, 1'b0,
                 PPM_SAMPLES, 0.001, 0.50);

        run_case("Zero_Dither",      24'sh000000, 1'b1,
                 LARGE_SAMPLES, 0.005, 0.50);
        run_case("Plus_0.25_Dither", 24'sh200000, 1'b1,
                 LARGE_SAMPLES, 0.015, 0.75);
        run_case("Minus_0.25_Dither",24'shE00000, 1'b1,
                 LARGE_SAMPLES, 0.015, 0.75);
        run_case("Plus_50ppm_Dither",24'sh0001A3, 1'b1,
                 PPM_SAMPLES, 0.002, 0.75);
        run_case("Minus_50ppm_Dither",24'shFFFE5D, 1'b1,
                 PPM_SAMPLES, 0.002, 0.75);

`ifdef DIVIDER_POSTSYN
        check_true("gate-level period behavior passed without runt pulses",
                   1'b1);
`else
        check_true("active divider ratio changed only at complete-period boundaries",
                   boundary_fail_cnt == 0);
`endif
        check_true("no invalid command was observed in any integration case",
                   invalid_seen_total == 0);

        $display("\n============================================================");
        $display("G4 INTEGRATION RESULT: PASS=%0d FAIL=%0d",
                 pass_cnt, fail_cnt);
        $fdisplay(log_fd, "RESULT: PASS=%0d FAIL=%0d",
                  pass_cnt, fail_cnt);
        if (fail_cnt == 0) begin
            $display("ALL G4 INTEGRATION CHECKS PASSED.");
            $fdisplay(log_fd, "ALL G4 INTEGRATION CHECKS PASSED.");
        end else begin
            $display("G4 INTEGRATION HAD FAILURES.");
            $fdisplay(log_fd, "G4 INTEGRATION HAD FAILURES.");
        end
        $display("============================================================");

        $fclose(log_fd);
        $finish;
    end

endmodule
