// top_module.v - Enhanced Top Module
// =========================================
`include "params.v"

module top_module (
    input clk,
    input rst
);

// --- Wires for Inter-module Connection ---
wire [BRAM_ADDR_WIDTH-1:0]  bram_addr;
wire signed [RF_DATA_WIDTH-1:0] rf_signal_from_bram;
wire signed [IQ_DATA_WIDTH-1:0] i_data_from_ddc;
wire signed [IQ_DATA_WIDTH-1:0] q_data_from_ddc;

// --- Enhanced ILA Debug Wires ---
wire pulse_detected_flag_ila;
wire [31:0] measured_pw_ila;
wire [31:0] measured_freq_accum_ila;
wire [31:0] magnitude_squared_ila;
wire threshold_exceeded_ila;
wire [1:0] fsm_state_ila;

// =========================================================================
//  1. BRAM Reader with Improved Address Management
// =========================================================================
reg [BRAM_ADDR_WIDTH-1:0] addr_counter = 0;
reg [3:0] startup_delay = 4'hF; // Delay for system startup

always @(posedge clk or posedge rst) begin
    if (rst) begin
        addr_counter <= 0;
        startup_delay <= 4'hF;
    end else begin
        // Wait for system to stabilize before starting
        if (startup_delay != 0) begin
            startup_delay <= startup_delay - 1;
        end else begin
            if (addr_counter == BRAM_DEPTH - 1) begin
                addr_counter <= 0; // Wrap around
            end else begin
                addr_counter <= addr_counter + 1;
            end
        end
    end
end

assign bram_addr = addr_counter;

// =========================================================================
//  2. BRAM Instantiation
// =========================================================================
blk_mem_gen_0 bram_inst (
    .clka(clk),
    .addra(bram_addr),
    .ena(startup_delay == 0), // Enable after startup delay
    .douta(rf_signal_from_bram)
);

// =========================================================================
//  3. DDC Module Instantiation  
// =========================================================================
ddc_module ddc_unit (
    .clk(clk),
    .rst(rst),
    .rf_in(rf_signal_from_bram),
    .i_out(i_data_from_ddc),
    .q_out(q_data_from_ddc),
    .iq_valid(iq_valid)  
);

// =========================================================================
//  4. Enhanced Parameter Estimator Instantiation
// =========================================================================
param_estimator estimator_unit (
    .clk(clk),
    .rst(rst),
    .i_in(i_data_from_ddc),
    .q_in(q_data_from_ddc),
    .pulse_detected_flag(pulse_detected_flag_ila),
    .measured_pw(measured_pw_ila),
    .measured_freq_accum(measured_freq_accum_ila),
    .magnitude_squared_debug(magnitude_squared_ila),
    .threshold_exceeded_debug(threshold_exceeded_ila),
    .fsm_state_debug(fsm_state_ila),
    .sample_ce(iq_valid)
);

// =========================================================================
//  5. Enhanced ILA Debug Signals
// =========================================================================
// Connect these additional signals to ILA for better debugging:
// - magnitude_squared_ila      (to verify threshold settings)
// - threshold_exceeded_ila     (to see when threshold is crossed)
// - fsm_state_ila             (to observe FSM transitions)
// - measured_freq_accum_ila    (to verify frequency accumulation)
// - rf_signal_from_bram        (original RF signal)
// - i_data_from_ddc, q_data_from_ddc (I/Q outputs)
// - pulse_detected_flag_ila    (pulse detection status)
// - measured_pw_ila            (measured pulse width)

endmodule