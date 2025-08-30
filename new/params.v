`ifndef PARAMS_V_INCLUDED
`define PARAMS_V_INCLUDED

// --- System Parameters ---
parameter CLK_FREQ = 100_000_000; // System clock frequency in Hz (100 MHz)

// --- Data Widths ---
parameter RF_DATA_WIDTH   = 16;   // Input RF signal data width (from BRAM)
parameter IQ_DATA_WIDTH   = 16;   // I/Q data width after DDC
parameter NCO_PHASE_WIDTH = 32;   // NCO phase accumulator width
parameter NCO_OUT_WIDTH   = 16;   // NCO sin/cos output width

// --- BRAM Parameters ---
parameter BRAM_DEPTH      = 20000; // Must match or be larger than your .coe file length
parameter BRAM_ADDR_WIDTH = 15;   // ceil(log2(BRAM_DEPTH)), 2^15 = 32768
parameter SAMPLE_RATE_HZ = 100_000_000;
// --- Parameter Estimator Thresholds ---
// Adjusted based on your waveform analysis
// Your I/Q values appear to be around ¡À1797 and ¡À3726
// Magnitude squared would be roughly: 1797^2 + 3726^2 ¡Ö 17,100,000
// Set threshold lower to ensure detection
parameter MAGNITUDE_THRESHOLD = 5000000;  // Adjusted threshold

// --- Pulse Detection Parameters ---
parameter MIN_PULSE_WIDTH = 10;   // Minimum pulse width in clock cycles
parameter DETECTION_DELAY = 3;    // Delay for stable detection

`endif // PARAMS_V_INCLUDED