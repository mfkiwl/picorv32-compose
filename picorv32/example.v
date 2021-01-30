`timescale 1 ns / 1 ps
`include "../cores/LedDisplay.v"
`include "../cores/uart.v"

module top (
	input clk,
	output reg led1, led2, led3, led4, led5, led6, led7, led8,
	output lcol1, lcol2, lcol3, lcol4, uart_tx
);
	// -------------------------------
	// Reset Generator

	reg [7:0] resetn_counter = 0;
	wire resetn = &resetn_counter;

	always @(posedge clk) begin
		if (!resetn)
			resetn_counter <= resetn_counter + 1;
	end


    // -------------------------------
	// LED Display

	reg [31:0] leds = 32'b0;

	reg [2:0] brightness = 3'b111;

	LedDisplay display (
		.clk12MHz(clk),
		.led1,
		.led2,
		.led3,
		.led4,
		.led5,
		.led6,
		.led7,
		.led8,
		.lcol1,
		.lcol2,
		.lcol3,
		.lcol4,

		.leds1(leds[7:0]),
		.leds2(leds[15:8]),
		.leds3(leds[23:16]),
		.leds4(leds[31:24]),
		.leds_pwm(brightness)
	);

	// -------------------------------
	// PicoRV32 Core

	wire mem_valid;
	wire [31:0] mem_addr;
	wire [31:0] mem_wdata;
	wire [3:0] mem_wstrb;

	reg mem_ready;
	reg [31:0] mem_rdata;

    wire trapped;

	picorv32 #(
		.ENABLE_COUNTERS(1),
		.LATCHED_MEM_RDATA(1),
		.TWO_STAGE_SHIFT(0),
		.TWO_CYCLE_ALU(0),
		.CATCH_MISALIGN(1),
		.CATCH_ILLINSN(0),
        .HART_ID(0)
	) cpu (
		.clk      (clk      ),
		.resetn   (resetn   ),
		.mem_valid(mem_valid),
		.mem_ready(mem_ready),
		.mem_addr (mem_addr ),
		.mem_wdata(mem_wdata),
		.mem_wstrb(mem_wstrb),
		.mem_rdata(mem_rdata),
        .trap(trapped)
	);

    reg [7:0] tx_data;
	reg tx_send;
	wire uart_ready;
	uart uart0 (
		.clk12MHz(clk),
		.tx(uart_tx),
		.sendData(tx_data),
		.sendReq(tx_send),
		.ready(uart_ready)
	);

	// -------------------------------
	// Memory/IO Interface

	// 2048 32bit words = 8192 bytes memory
	localparam MEM_SIZE = 2048;
	reg [31:0] memory [0:MEM_SIZE-1];
	initial $readmemh("firmware.hex", memory);

	always @(posedge clk) begin
        leds[31] <= trapped;
		mem_ready <= 0;
        tx_send <= 0;
		if (resetn && mem_valid && !mem_ready) begin
			(* parallel_case *)
			case (1)
				!(|mem_wstrb) && (mem_addr >> 2) < MEM_SIZE: begin
					mem_rdata <= memory[mem_addr >> 2];
					mem_ready <= 1;
				end
				|mem_wstrb && (mem_addr >> 2) < MEM_SIZE: begin
					if (mem_wstrb[0]) memory[mem_addr >> 2][ 7: 0] <= mem_wdata[ 7: 0];
					if (mem_wstrb[1]) memory[mem_addr >> 2][15: 8] <= mem_wdata[15: 8];
					if (mem_wstrb[2]) memory[mem_addr >> 2][23:16] <= mem_wdata[23:16];
					if (mem_wstrb[3]) memory[mem_addr >> 2][31:24] <= mem_wdata[31:24];
					mem_ready <= 1;
				end
				|mem_wstrb && mem_addr == 32'h1000_0000: begin
					leds[7:0] <= mem_wdata[7:0];
					mem_ready <= 1;
				end
                !(|mem_wstrb) && mem_addr == 32'h2000_0000: begin
					mem_rdata <= {31'b0, uart_ready};
					mem_ready <= 1;
				end
                |mem_wstrb && mem_addr == 32'h2000_0000: begin
					tx_data <= mem_wdata[7:0];
					tx_send <= 1;
					mem_ready <= 1;
				end
			endcase
		end
	end
endmodule
