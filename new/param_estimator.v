`include "params.v"

// ================================================================
// param_estimator.v  - 基带 I/Q 脉冲检测 + 频率估计
// * sample_ce：接 FIR 的 m_axis_data_tvalid（与 I/Q 对齐）
// * 频率公式：f = (sum(Δφ)/Nsamp) * (SAMPLE_RATE_HZ/65536)
// * 输出：脉宽、相位累计、锁存频率、实时频率（调试）
// ================================================================
module param_estimator (
    input                             clk,
    input                             rst,
    input                             sample_ce,              // ★ 有效样本使能

    input  signed [IQ_DATA_WIDTH-1:0] i_in,
    input  signed [IQ_DATA_WIDTH-1:0] q_in,

    output                            pulse_detected_flag,
    output reg [31:0]                 measured_pw,            // 脉宽(时钟拍)
    output reg  signed [31:0]         measured_freq_accum,    // 相位累计(LSB)
    output reg  signed [31:0]         measured_freq_hz,       // 锁存频率(Hz)
    output reg  signed [31:0]         freq_hz_live_dbg,       // 实时频率(Hz)

    output       [31:0]               magnitude_squared_debug,
    output                            threshold_exceeded_debug,
    output       [1:0]                fsm_state_debug
);

    // ---------------- I^2+Q^2 与门限 ----------------
    wire [31:0] i_squared = i_in * i_in;
    wire [31:0] q_squared = q_in * q_in;
    wire [31:0] magnitude_squared = i_squared + q_squared;

    reg  [DETECTION_DELAY-1:0] threshold_history;
    wire threshold_raw = (magnitude_squared > MAGNITUDE_THRESHOLD);
    wire threshold_stable = (&threshold_history) | (~|threshold_history);

    // ---------------- CORDIC：相位 -------------------
    wire signed [15:0] cordic_phase_out;
    wire signed [15:0] cordic_mag_out;
    wire [31:0]        cordic_input_bus = {q_in, i_in};

    cordic_0 cordic_inst (
      .aclk                     (clk),
      .s_axis_cartesian_tvalid (1'b1),
      .s_axis_cartesian_tdata  (cordic_input_bus),
      .m_axis_dout_tvalid      (),
      .m_axis_dout_tdata       ({cordic_phase_out, cordic_mag_out})
    );

    // ---------------- 相位差累计 --------------------
    reg  signed [15:0] phase_prev;
    reg  signed [17:0] phase_diff;
    reg  signed [31:0] phase_accumulator;

    // ---------------- 计数/FSM ----------------------
    reg  [31:0] pw_clk_counter;    // 按时钟计脉宽
    reg  [31:0] pw_samp_counter;   // 按样本计 Nsamp

    localparam ST_IDLE      = 2'b00;
    localparam ST_DETECTING = 2'b01;
    localparam ST_LATCH     = 2'b10;
    localparam ST_COOLDOWN  = 2'b11;
    reg [1:0] current_state, next_state;
    reg [7:0] cooldown_counter;

    // ---------------- 调试映射 ----------------------
    assign magnitude_squared_debug  = magnitude_squared;
    assign threshold_exceeded_debug = threshold_raw;
    assign fsm_state_debug          = current_state;
    assign pulse_detected_flag      = (current_state == ST_DETECTING);

    // =================================================
    // 1) 阈值历史：只在 sample_ce 时推进
    // =================================================
    always @(posedge clk or posedge rst) begin
        if (rst) threshold_history <= {DETECTION_DELAY{1'b0}};
        else if (sample_ce) threshold_history <= {threshold_history[DETECTION_DELAY-2:0], threshold_raw};
    end

    // =================================================
    // 2) 相位差/累计：只在 sample_ce 时更新
    // =================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            phase_prev        <= 16'sd0;
            phase_diff        <= 18'sd0;
            phase_accumulator <= 32'sd0;
        end else if (sample_ce) begin
            phase_diff        <= { {2{cordic_phase_out[15]}}, cordic_phase_out } -
                                 { {2{phase_prev[15]}},      phase_prev       };
            phase_prev        <= cordic_phase_out;
            phase_accumulator <= phase_accumulator + {{14{phase_diff[17]}}, phase_diff};
        end
    end

    // =================================================
    // 3) FSM 次态
    // =================================================
    always @(*) begin
        next_state = current_state;
        case (current_state)
            ST_IDLE:      if (threshold_stable && threshold_raw) next_state = ST_DETECTING;
            ST_DETECTING: if (threshold_stable && !threshold_raw)
                              next_state = (pw_clk_counter >= MIN_PULSE_WIDTH) ? ST_LATCH : ST_IDLE;
            ST_LATCH:     next_state = ST_COOLDOWN;
            ST_COOLDOWN:  if (cooldown_counter == 0) next_state = ST_IDLE;
            default:      next_state = ST_IDLE;
        endcase
    end

    // =================================================
    // 4) FSM 寄存 + 计数/频率计算（实时 & 锁存）
    // =================================================
    reg signed [63:0] num64, den64, div64;  // 64 位中间变量（避免语法错误与溢出）

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state        <= ST_IDLE;
            pw_clk_counter       <= 32'd0;
            pw_samp_counter      <= 32'd0;
            measured_pw          <= 32'd0;
            measured_freq_accum  <= 32'sd0;
            measured_freq_hz     <= 32'sd0;
            freq_hz_live_dbg     <= 32'sd0;
            cooldown_counter     <= 8'd0;
        end else begin
            current_state <= next_state;

            case (current_state)
                ST_IDLE: begin
                    if (next_state == ST_DETECTING) begin
                        pw_clk_counter      <= 32'd1;
                        pw_samp_counter     <= sample_ce ? 32'd1 : 32'd0;
                        phase_accumulator   <= 32'sd0;
                        freq_hz_live_dbg    <= 32'sd0;
                    end
                end

                ST_DETECTING: begin
                    pw_clk_counter <= pw_clk_counter + 1;
                    if (sample_ce) pw_samp_counter <= pw_samp_counter + 1;

                    // 实时平均频率（便于调试）
                    if (sample_ce && pw_samp_counter > 4) begin
                        num64 = $signed(phase_accumulator) * $signed(SAMPLE_RATE_HZ);
                        den64 = $signed({16'd0, pw_samp_counter}) <<< 16; // *65536
                        if (den64 != 0) begin
                            div64 = num64 / den64;                 // ★ 先算出来
                            freq_hz_live_dbg <= div64[31:0];       // ★ 再截取 32 位
                        end
                    end
                end

                ST_LATCH: begin
                    measured_pw         <= pw_clk_counter;
                    measured_freq_accum <= phase_accumulator;

                    if (pw_samp_counter != 0) begin
                        num64 = $signed(phase_accumulator) * $signed(SAMPLE_RATE_HZ);
                        den64 = $signed({16'd0, pw_samp_counter}) <<< 16; // *65536
                        if (den64 != 0) begin
                            div64 = num64 / den64;                 // ★ 阻塞计算
                            measured_freq_hz <= div64[31:0];       // ★ 再写寄存器
                        end else begin
                            measured_freq_hz <= 32'sd0;
                        end
                    end else begin
                        measured_freq_hz <= 32'sd0;
                    end

                    cooldown_counter <= 8'd50;
                end

                ST_COOLDOWN: begin
                    if (cooldown_counter != 0) cooldown_counter <= cooldown_counter - 1;
                end
            endcase
        end
    end

endmodule
