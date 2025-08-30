// ddc_module.v (Optimized Version)
// =========================================
// Description: A clean, standard Digital Down-Converter module.
// Takes a real RF input, mixes it with an NCO signal, filters it,
// and outputs complex I/Q data.
// =========================================
`include "params.v"

module ddc_module (
    // --- Control Ports ---
    input  clk,
    input  rst,

    // --- Synchronization Input ---
    //input  phase_load_valid_in,

    // --- Data Ports ---
    input  signed [RF_DATA_WIDTH-1:0]   rf_in,
    output signed [IQ_DATA_WIDTH-1:0]   i_out,
    output signed [IQ_DATA_WIDTH-1:0]   q_out,
    output        iq_valid

);

    // --- Internal Signals ---

    // NCO (DDS) Output
    wire signed [NCO_OUT_WIDTH-1:0]   nco_cos_out;
    wire signed [NCO_OUT_WIDTH-1:0]   nco_sin_out;
    wire [2*NCO_OUT_WIDTH-1:0]        dds_tdata_bus;

    // Mixer Output
    wire signed [RF_DATA_WIDTH+NCO_OUT_WIDTH-1:0]  i_mixed_raw;
    wire signed [RF_DATA_WIDTH+NCO_OUT_WIDTH-1:0]  q_mixed_raw;


    // =========================================================================
    //  1. NCO (Numerical Controlled Oscillator) - DDS IP Core
    // =========================================================================
    // This IP generates the sine and cosine reference signals for mixing.
    dds_compiler_1 dds_nco_inst (
      .aclk(clk),
      .aresetn(~rst), // IP uses active-low reset, our 'rst' is active-high
      .m_axis_data_tvalid(),       // Unconnected output
      .m_axis_data_tdata(dds_tdata_bus)
    );

    // Split the 32-bit DDS output bus into separate sine and cosine signals
    assign nco_cos_out = dds_tdata_bus[NCO_OUT_WIDTH-1 : 0];
    assign nco_sin_out = dds_tdata_bus[2*NCO_OUT_WIDTH-1 : NCO_OUT_WIDTH];


    // =========================================================================
    //  2. Mixers (Simple Multipliers)
    // =========================================================================
    // Mix the incoming RF signal with the NCO's I and Q components.
    assign i_mixed_raw = rf_in * nco_cos_out;
    assign q_mixed_raw = rf_in * nco_sin_out;


    // =========================================================================
    //  3. Low-Pass Filters - FIR IP Cores
    // =========================================================================
    // Filter the mixed signals to remove the high-frequency sum component.
    
 // I-Channel Filter
   wire i_valid;
    fir_compiler_0 fir_i_inst (
      .aclk(clk),
      .s_axis_data_tvalid(1'b1),        // Data is always valid in our design
      .s_axis_data_tready(),            // Unconnected output
      .s_axis_data_tdata(i_mixed_raw),
      .m_axis_data_tvalid(i_valid),            // Unconnected output
      .m_axis_data_tdata(i_out)
    );

    // Q-Channel Filter
    wire q_valid;
    fir_compiler_1 fir_q_inst (
      .aclk(clk),
      .s_axis_data_tvalid(1'b1),        // Data is always valid
      .s_axis_data_tready(),            // Unconnected output
      .s_axis_data_tdata(q_mixed_raw),
      .m_axis_data_tvalid(q_valid),            // Unconnected output
      .m_axis_data_tdata(q_out)
    );
   assign iq_valid = i_valid & q_valid;
endmodule