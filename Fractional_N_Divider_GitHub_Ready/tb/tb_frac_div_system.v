`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Week-4 self-checking testbench for Divider + external T-FF.
//
// The periods follow the instructor Hint clarification:
//   N=1 -> 1*T_RO, N=2 -> 2*T_RO, N=3 -> 3*T_RO (1H/2L).
//
// The same testbench is used for RTL and post-synthesis simulation.
// Define GATE_SIM when compiling the synthesized divider netlist.
//------------------------------------------------------------------------------
module tb_frac_div_system;

    localparam real T_RO       = 7629.39;
    localparam real HALF_T_RO  = T_RO / 2.0;
    localparam real P_N1       = 1.0 * T_RO;
    localparam real P_N2       = 2.0 * T_RO;
    localparam real P_N3       = 3.0 * T_RO;
    localparam real P_32K      = 4.0 * T_RO;

`ifdef GATE_SIM
    localparam real TOL_NS     = 200.0;
    localparam real GLITCH_MIN = HALF_T_RO - 500.0;
`else
    localparam real TOL_NS     = 2.5;
    localparam real GLITCH_MIN = HALF_T_RO - 2.5;
`endif

    reg        clk;
    reg        rst_n;
    reg  [1:0] N_sel;
    wire       INT65K_CLK;
    wire       CLK32K;

    integer pass_cnt;
    integer fail_cnt;
    integer log_fd;
    integer i;

    realtime last_edge_time;
    realtime pulse_width;
    realtime t1, t2, measured_period;
    realtime start_time, end_time;
    realtime high_w, low_w, edge_a, edge_b, edge_c;
    real measured_avg_freq_khz;
    real theoretical_avg_freq_khz;
    real freq_error_percent;

    frac_div_system dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .N_sel      (N_sel),
        .INT65K_CLK (INT65K_CLK),
        .CLK32K     (CLK32K)
    );

    initial begin
        clk = 1'b0;
        forever #(HALF_T_RO) clk = ~clk;
    end

`ifdef GATE_SIM
    initial begin
        $dumpfile("sim/gate/tb_frac_div_system_gate.vcd");
        $dumpvars(0, tb_frac_div_system);
        log_fd = $fopen("sim/gate/tb_frac_div_system_gate.log", "w");
        if (log_fd == 0) log_fd = 32'h8000_0001;
        $sdf_annotate("netlist/fractional_n_divider_postsyn.sdf",
                      dut.u_div, , , "MAXIMUM");
    end
`else
    initial begin
        $dumpfile("sim/rtl/tb_frac_div_system.vcd");
        $dumpvars(0, tb_frac_div_system);
        log_fd = $fopen("sim/rtl/tb_frac_div_system.log", "w");
        if (log_fd == 0) log_fd = 32'h8000_0001;
    end
`endif


    // Global watchdog prevents a missing output clock from hanging regression.
    initial begin
        #(1.0e8);
        $display("[FATAL] tb_frac_div_system timeout");
        $fdisplay(log_fd, "FATAL: tb_frac_div_system timeout");
        fail_cnt = fail_cnt + 1;
        $fclose(log_fd);
        $finish;
    end

    task log_line;
        input [8*256-1:0] msg;
        begin
            $display("%0s", msg);
            $fdisplay(log_fd, "%0s", msg);
        end
    endtask

    task check_true;
        input [8*80-1:0] name;
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

    task measure_period_of;
        input integer which_clock;
        begin
            #1;
            if (which_clock == 0) begin
                @(posedge INT65K_CLK); t1 = $realtime;
                @(posedge INT65K_CLK); t2 = $realtime;
            end else begin
                @(posedge CLK32K); t1 = $realtime;
                @(posedge CLK32K); t2 = $realtime;
            end
            measured_period = t2 - t1;
        end
    endtask

    task check_period;
        input [8*80-1:0] name;
        input real expected;
        input real tolerance;
        begin
            if ((measured_period >= expected - tolerance) &&
                (measured_period <= expected + tolerance)) begin
                $display(" -> PASS: %0s measured=%0.2f ns expected=%0.2f ns",
                         name, measured_period, expected);
                $fdisplay(log_fd, "PASS: %0s measured=%0.2f expected=%0.2f",
                          name, measured_period, expected);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display(" -> FAIL: %0s measured=%0.2f ns expected=%0.2f +/- %0.2f ns",
                         name, measured_period, expected, tolerance);
                $fdisplay(log_fd, "FAIL: %0s measured=%0.2f expected=%0.2f",
                          name, measured_period, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // One command is presented per output period. The long-term command pattern
    // is nine N=2 periods followed by one N=3 period: average N = 2.1.
    task drive_fractional_pattern;
        integer outer_i;
        integer inner_i;
        begin
            for (outer_i = 0; outer_i < 100; outer_i = outer_i + 1) begin
                for (inner_i = 0; inner_i < 9; inner_i = inner_i + 1) begin
                    @(negedge INT65K_CLK);
                    N_sel = 2'b01;
                end
                @(negedge INT65K_CLK);
                N_sel = 2'b10;
            end
        end
    endtask

    // Continuous runt/glitch monitor. Reset transitions are excluded because
    // reset is allowed to force the clock low asynchronously.
    initial last_edge_time = 0.0;
    always @(negedge rst_n) last_edge_time = 0.0;

    always @(INT65K_CLK) begin
        if (rst_n && (last_edge_time > 0.0)) begin
            pulse_width = $realtime - last_edge_time;
            if (pulse_width < GLITCH_MIN) begin
                $display("[FATAL] INT65K_CLK runt/glitch width=%0.2f ns at t=%0.2f ns",
                         pulse_width, $realtime);
                $fdisplay(log_fd, "FATAL: glitch width=%0.2f time=%0.2f",
                          pulse_width, $realtime);
                fail_cnt = fail_cnt + 1;
                $fclose(log_fd);
                $finish;
            end
        end
        if (rst_n)
            last_edge_time = $realtime;
    end

    // Missing-pulse watchdog for the nominal N=2 mode.
    realtime last_int_posedge;
    reg watch_n2;
    initial begin
        last_int_posedge = 0.0;
        watch_n2 = 1'b0;
    end
    always @(posedge INT65K_CLK) last_int_posedge = $realtime;
    always @(posedge clk) begin
        if (watch_n2 && rst_n &&
            (($realtime - last_int_posedge) > (3.0*T_RO + 10.0))) begin
            $display("[FATAL] Missing INT65K_CLK pulse while N=2 watchdog is armed");
            $fdisplay(log_fd, "FATAL: missing N=2 pulse");
            fail_cnt = fail_cnt + 1;
            $fclose(log_fd);
            $finish;
        end
    end

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        rst_n    = 1'b1;
        N_sel    = 2'b01;
        watch_n2 = 1'b0;

        #1;
        log_line("============================================================");
`ifdef GATE_SIM
        log_line(" Week-4 Divider + T-FF testbench: GATE + MAXIMUM SDF");
`else
        log_line(" Week-4 Divider + T-FF testbench: RTL");
`endif
        log_line("============================================================");

        // Test 1: asynchronous reset
        $display("\n[Test 1] Asynchronous reset");
        #100;
        rst_n = 1'b0;
        #(T_RO * 2.5);
        check_true("INT65K_CLK and CLK32K remain low during reset",
                   (INT65K_CLK === 1'b0) && (CLK32K === 1'b0));
        // Release reset midway between clock edges.
// The divider contains both posedge and negedge flip-flops.
@(negedge clk);
#(T_RO / 4.0);
rst_n = 1'b1;
#(T_RO * 2.0);

        // Test 2: divide by 2
        $display("\n[Test 2] N=2 nominal mode");
        N_sel = 2'b01;
        watch_n2 = 1'b1;
        #(T_RO * 4.0);
        measure_period_of(0);
        check_period("INT65K_CLK N=2 period", P_N2, TOL_NS);
        check_true("INT65K_CLK N=2 frequency is approximately 65.536 kHz",
                   ((1.0e6/measured_period) > 65.4) &&
                   ((1.0e6/measured_period) < 65.7));
        @(posedge INT65K_CLK); edge_a = $realtime;
        @(negedge INT65K_CLK); edge_b = $realtime;
        @(posedge INT65K_CLK); edge_c = $realtime;
        high_w = edge_b - edge_a;
        low_w  = edge_c - edge_b;
        check_true("N=2 duty cycle is approximately 50 percent",
                   (high_w >= T_RO-TOL_NS) && (high_w <= T_RO+TOL_NS) &&
                   (low_w  >= T_RO-TOL_NS) && (low_w  <= T_RO+TOL_NS));
        watch_n2 = 1'b0;

        // Test 3: divide by 1
        $display("\n[Test 3] N=1 bypass mode");
        N_sel = 2'b00;
        #(T_RO * 4.0);
        measure_period_of(0);
        check_period("INT65K_CLK N=1 period", P_N1, TOL_NS);

        // Test 4: divide by 3, asymmetric waveform
        $display("\n[Test 4] N=3 asymmetric mode");
        N_sel = 2'b10;
        #(T_RO * 6.0);
        measure_period_of(0);
        check_period("INT65K_CLK N=3 period", P_N3, TOL_NS);
        @(posedge INT65K_CLK); edge_a = $realtime;
        @(negedge INT65K_CLK); edge_b = $realtime;
        @(posedge INT65K_CLK); edge_c = $realtime;
        high_w = edge_b - edge_a;
        low_w  = edge_c - edge_b;
        check_true("N=3 waveform is 1*T_RO high and 2*T_RO low",
                   (high_w >= T_RO-TOL_NS) && (high_w <= T_RO+TOL_NS) &&
                   (low_w >= 2.0*T_RO-TOL_NS) &&
                   (low_w <= 2.0*T_RO+TOL_NS));

        // Test 5: dynamic transitions
        $display("\n[Test 5] Dynamic N=2 to N=3 transition");
        N_sel = 2'b01;
        @(posedge INT65K_CLK);
        #(T_RO * 1.5);
        N_sel = 2'b10;
        measure_period_of(0);
        check_period("first settled N=3 period after transition", P_N3, TOL_NS);

        $display("\n[Test 5-B] Dynamic N=2 to N=1 transition");
        N_sel = 2'b01;
        @(posedge INT65K_CLK);
        #(T_RO * 1.25);
        N_sel = 2'b00;
        measure_period_of(0);
        check_period("first settled N=1 period after transition", P_N1, TOL_NS);

        // Test 6: invalid code must fall back to N=2
        $display("\n[Test 6] Invalid N_sel=2'b11 safe fallback");
        N_sel = 2'b11;
        #(T_RO * 4.0);
        measure_period_of(0);
        check_period("invalid code behaves as N=2", P_N2, TOL_NS);

        // Test 7: long-term average, measured from real output edges
        $display("\n[Test 7] Long-term average for command average N=2.1");
        theoretical_avg_freq_khz = 131.072 / 2.1;
        N_sel = 2'b01;
        @(posedge INT65K_CLK);
        fork
            drive_fractional_pattern();
            begin
                start_time = $realtime;
                for (i = 0; i < 1000; i = i + 1)
                    @(posedge INT65K_CLK);
                end_time = $realtime;
            end
        join
        measured_avg_freq_khz =
            1000.0 / ((end_time-start_time)/1.0e9) / 1000.0;
        freq_error_percent =
            ((measured_avg_freq_khz-theoretical_avg_freq_khz) /
             theoretical_avg_freq_khz) * 100.0;
        if (freq_error_percent < 0.0)
            freq_error_percent = -freq_error_percent;
        $display(" -> theoretical=%0.6f kHz measured=%0.6f kHz error=%0.6f%%",
                 theoretical_avg_freq_khz, measured_avg_freq_khz,
                 freq_error_percent);
        $fdisplay(log_fd, "AVERAGE: theoretical=%0.6f measured=%0.6f error=%0.6f%%",
                  theoretical_avg_freq_khz, measured_avg_freq_khz,
                  freq_error_percent);
        check_true("average-frequency error is below 0.1 percent",
                   freq_error_percent < 0.1);

        // Test 8: external T-FF
        $display("\n[Test 8] External T-FF output at nominal N=2");
        N_sel = 2'b01;
        #(T_RO * 8.0);
        measure_period_of(1);
        check_period("CLK32K nominal period", P_32K, TOL_NS);
        @(posedge CLK32K); edge_a = $realtime;
        @(negedge CLK32K); edge_b = $realtime;
        @(posedge CLK32K); edge_c = $realtime;
        high_w = edge_b - edge_a;
        low_w  = edge_c - edge_b;
        check_true("CLK32K duty cycle is approximately 50 percent",
                   (high_w >= P_N2-TOL_NS) && (high_w <= P_N2+TOL_NS) &&
                   (low_w  >= P_N2-TOL_NS) && (low_w  <= P_N2+TOL_NS));

        $display("\n============================================================");
        $display("RESULT: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
        $fdisplay(log_fd, "RESULT: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            log_line("ALL WEEK-4 DIRECTED TESTS PASSED.");
        else
            log_line("WEEK-4 DIRECTED TESTS HAD FAILURES.");
        log_line("============================================================");
        $fclose(log_fd);
        $finish;
    end

endmodule
