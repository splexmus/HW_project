`timescale 1ns / 1ps

// ============================================================
// OV7670 SCCB / I2C CONFIGURATION MODULE
// ============================================================
//
// Purpose:
// Configure OV7670 camera registers through SCCB
// (OV7670's I2C-like interface).
//
// This module:
//
// 1. Generates slow I2C clock
// 2. Reads configuration values from LUT
// 3. Sends register writes to OV7670
// 4. Reports when configuration is finished
//
// ============================================================

module I2C_AV_Config 
(
    // ========================================================
    // GLOBAL CLOCK / RESET
    // ========================================================

	input				iCLK,		    // 25 MHz system clock
	input				iRST_N,		    // active-low reset
	
	// ========================================================
    // I2C / SCCB INTERFACE
    // ========================================================

	output				I2C_SCLK,	    // SCCB clock
	inout				I2C_SDAT,	    // SCCB data
	
	// ========================================================
    // STATUS OUTPUTS
    // ========================================================

	output	reg			Config_Done,   // becomes 1 when setup finished
	output	reg	[7:0]	LUT_INDEX,	    // current LUT index
	output		[7:0]	I2C_RDATA	    // readback data
);

// ============================================================
// NUMBER OF CONFIGURATION COMMANDS
// ============================================================

parameter LUT_SIZE = 193;

// ============================================================
// I2C CLOCK GENERATION
// ============================================================
//
// Convert 25 MHz clock -> 10 kHz SCCB clock
//
// ============================================================

parameter CLK_Freq = 25_000000;   // input clock = 25 MHz
parameter I2C_Freq = 10_000;      // SCCB clock = 10 kHz

reg [15:0] mI2C_CLK_DIV;          // divider counter
reg        mI2C_CTRL_CLK;         // generated SCCB clock

always @(posedge iCLK or negedge iRST_N)
begin

	if(!iRST_N)
	begin
		mI2C_CLK_DIV <= 0;
		mI2C_CTRL_CLK <= 0;
	end

	else
	begin

        // count until divider reached
		if(mI2C_CLK_DIV < (CLK_Freq/I2C_Freq)/2)
			mI2C_CLK_DIV <= mI2C_CLK_DIV + 1'd1;

		else
		begin
			mI2C_CLK_DIV <= 0;

            // toggle SCCB clock
			mI2C_CTRL_CLK <= ~mI2C_CTRL_CLK;
		end
	end
end

// ============================================================
// EDGE DETECTOR
// ============================================================
//
// Detect negative edge of internal I2C clock
//
// Used to control SCCB transfers
//
// ============================================================

reg i2c_en_r0;
reg i2c_en_r1;

always @(posedge iCLK or negedge iRST_N)
begin

	if(!iRST_N)
	begin
		i2c_en_r0 <= 0;
		i2c_en_r1 <= 0;
	end

	else
	begin
		i2c_en_r0 <= mI2C_CTRL_CLK;
		i2c_en_r1 <= i2c_en_r0;
	end
end

// negative edge detect
wire i2c_negclk =
    (i2c_en_r1 & ~i2c_en_r0) ? 1'b1 : 1'b0;

// ============================================================
// CONFIGURATION CONTROL STATE MACHINE
// ============================================================

// transfer complete flag
wire mI2C_END;

// ACK received flag
wire mI2C_ACK;

// state machine register
reg [1:0] mSetup_ST;

// start transfer pulse
reg mI2C_GO;

// write/read mode
reg mI2C_WR;

// ============================================================
// MAIN CONFIGURATION FSM
// ============================================================
//
// State 0 = IDLE
// State 1 = WAIT FOR TRANSFER COMPLETE
// State 2 = NEXT REGISTER
//
// ============================================================

always @(posedge iCLK or negedge iRST_N)
begin

	if(!iRST_N)
	begin
		Config_Done <= 0;

		LUT_INDEX <= 0;

		mSetup_ST <= 0;

		mI2C_GO <= 0;

		mI2C_WR <= 0;
	end

	else if(i2c_negclk)
	begin

        // ====================================================
        // STILL CONFIGURING CAMERA
        // ====================================================

		if(LUT_INDEX < LUT_SIZE)
		begin

			Config_Done <= 0;

			case(mSetup_ST)

            // =================================================
            // STATE 0 : START TRANSFER
            // =================================================

			0:
			begin

                // if transfer not busy
				if(~mI2C_END)
					mSetup_ST <= 1;
				else
					mSetup_ST <= 0;

                // start SCCB transfer
				mI2C_GO <= 1;

                // first 2 LUT entries are reads
				if(LUT_INDEX < 8'd2)
					mI2C_WR <= 0;
				else
					mI2C_WR <= 1;
			end

            // =================================================
            // STATE 1 : WAIT TRANSFER FINISH
            // =================================================

			1:
			begin

				if(mI2C_END)
				begin

                    // stop transfer request
					mI2C_WR <= 0;
					mI2C_GO <= 0;

                    // ACK successful
					if(~mI2C_ACK)
						mSetup_ST <= 2;

                    // retry transfer
					else
						mSetup_ST <= 0;
				end
			end

            // =================================================
            // STATE 2 : NEXT LUT ENTRY
            // =================================================

			2:
			begin

                // next register config
				LUT_INDEX <= LUT_INDEX + 8'd1;

                // return idle
				mSetup_ST <= 0;

				mI2C_GO <= 0;
				mI2C_WR <= 0;
			end

			endcase
		end

        // ====================================================
        // CONFIGURATION FINISHED
        // ====================================================

		else
		begin

			Config_Done <= 1'b1;

			LUT_INDEX <= LUT_INDEX;

			mSetup_ST <= 0;

			mI2C_GO <= 0;

			mI2C_WR <= 0;
		end
	end
end

// ============================================================
// LOOKUP TABLE
// ============================================================
//
// Provides register address + value
// for OV7670 configuration
//
// LUT_DATA format:
//
// {register_address, register_data}
//
// ============================================================

wire [15:0] LUT_DATA;

I2C_OV7670_RGB565_Config OV7670_RGB565_Config
(
	.LUT_INDEX(LUT_INDEX),
	.LUT_DATA(LUT_DATA)
);

// ============================================================
// LOW-LEVEL SCCB / I2C CONTROLLER
// ============================================================
//
// Sends actual SCCB transactions
//
// ============================================================

I2C_Controller sccb_sender
(	
	.iCLK(iCLK),
	.iRST_N(iRST_N),
							
	.I2C_CLK(mI2C_CTRL_CLK),	    // SCCB working clock
	.I2C_EN(i2c_negclk),		    // transfer timing enable

    // transmit:
    // slave address + register + value
	.I2C_WDATA({8'h42, LUT_DATA}),

	.I2C_SCLK(I2C_SCLK),		    // SCCB clock
	.I2C_SDAT(I2C_SDAT),		    // SCCB data
	
	.GO(mI2C_GO),			        // start transfer
	.WR(mI2C_WR),      	            // write mode

	.ACK(mI2C_ACK),			    // acknowledge received
	.END(mI2C_END),			    // transfer finished

	.I2C_RDATA(I2C_RDATA)		    // readback data
);

endmodule