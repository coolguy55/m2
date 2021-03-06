/*
Copyright by Pouya Taatizadeh
Developed for the Digital Systems Design course (COE3DQ5)
Department of Electrical and Computer Engineering
McMaster University
Ontario, Canada
*/

`timescale 1ns/100ps
`default_nettype none

`include "define_state.h"

module M2 (

	input logic CLOCK_50_I,                   // 50 MHz clock
	input logic resetn, 					  // top level master reset
	input logic M2_start,
	output logic M2_done, 
	// signals for the SRAM
	input logic [15:0] M2_SRAM_read_data,
	output logic [15:0] M2_SRAM_write_data,
	output logic [17:0] M2_SRAM_address,
	output logic M2_SRAM_we_n,
	
	/////// signals for multipliers in top level
	output logic [31:0] M2_mult_1_in1,
	output logic [31:0] M2_mult_1_in2,
	output logic [31:0] M2_mult_2_in1,
	output logic [31:0] M2_mult_2_in2,
	output logic [31:0] M2_mult_3_in1,
	output logic [31:0] M2_mult_3_in2,

	input logic signed [63:0] M2_mult_res_1,
	input logic signed [63:0] M2_mult_res_2,
	input logic signed [63:0] M2_mult_res_3
);


M2_state_type top_state;

logic [5:0] C_address_a,C_address_b;
logic signed [31:0] C_write_a,C_write_b;
logic signed [31:0] C_read_a,C_read_b;

logic signed C_wren_a,C_wren_b;

logic [5:0] S_prime_address_a,S_prime_address_b;
logic signed [31:0] S_prime_write_a,S_prime_write_b,S_prime_read_a,S_prime_read_b;

logic S_prime_wren_a,S_prime_wren_b;

logic write_c2, last_c2_loop, start_c2,temp_odd_assigned, fetching_u_now;


logic signed [5:0] block_counter,C_column_offset,C_row_offset;
logic signed [5:0]S_prime_row_offset,S_prime_column_offset; // this is used in C1 (S'*C))


logic signed [5:0] temp_address_a,temp_address_b,temp_address;
logic signed [31:0] temp_write_a,temp_write_b,temp_read_a,temp_read_b;

logic signed [31:0] tBuff1, tBuff2, tBuff3, tBuff4, tBuff5, tBuff6, tBuff7, tBuff8;
logic signed [31:0] cTBuff1, cTBuff2, cTBuff3, cTBuff4, cTBuff5, cTBuff6, cTBuff7, cTBuff8;

logic [5:0] temp_addr_buff1, temp_addr_buff2, c_addr_buff1, c_addr_buff2, temp_addr_even_buff1, temp_addr_even_buff2, c_addr_even_buff1, c_addr_even_buff2;

logic signed temp_wren_a,temp_wren_b;

logic [1:0] current_yuv;

logic signed [63:0] temp_c1;
logic signed [7:0] temp_c2_clipped_even, temp_c2_clipped_odd;

logic signed [17:0] sram_fetch_offset, block_number_counter, sram_fetch_u_offset, sram_address_to_write_next;
logic signed [17:0] sram_write_u_offset;
logic signed [63:0] temp;

DUAL_PORT_C DUAL_PORT_C (
	.address_a ( C_address_a ),
	.address_b ( C_address_b ),
	.clock ( CLOCK_50_I ),
	.data_a ( C_write_a ),
	.data_b ( C_write_b ),
	.wren_a ( C_wren_a ),
	.wren_b ( C_wren_b ),
	.q_a ( C_read_a ),
	.q_b ( C_read_b )
	);

sPrimeDPRam sPrimeDPRam (
	.address_a ( S_prime_address_a ),
	.address_b ( S_prime_address_b ),
	.clock ( CLOCK_50_I ),
	.data_a ( S_prime_write_a ),
	.data_b ( S_prime_write_b ),
	.wren_a ( S_prime_wren_a ),
	.wren_b ( S_prime_wren_b ),
	.q_a ( S_prime_read_a ),
	.q_b ( S_prime_read_b )
	);

	
tempDPRAM tempDPRAM (
	.address_a ( temp_address_a ),
	.address_b ( temp_address_b ),
	.clock ( CLOCK_50_I ),
	.data_a ( temp_write_a ),
	.data_b ( temp_write_b ),
	.wren_a ( temp_wren_a ),
	.wren_b ( temp_wren_b ),
	.q_a ( temp_read_a ),
	.q_b ( temp_read_b )
	);

	

logic [17:0] inner_column_offset,inner_row_offset,block_row_offset,block_column_offset, block_row_address, block_column_address;
logic [17:0] prev_block_column_address, prev_block_row_address, yuv_row, yuv_col;

logic start_write,start_temp_write,C1_done,c2_done;

logic[5:0] temp_column_offset,temp_row_offset, c2_write_count;


/// multipliers signal in M2 ///////////////////////////////////////////

logic signed [31:0] mult_op_1, mult_op_2, mult_op_3, mult_op_4, mult_op_5, mult_op_6;
logic signed [63:0] mult_res_1, mult_res_2, mult_res_3;

assign M2_mult_1_in1 = mult_op_1;
assign M2_mult_1_in2 = mult_op_2;
assign M2_mult_2_in1 = mult_op_3;
assign M2_mult_2_in2 = mult_op_4;
assign M2_mult_3_in1 = mult_op_5;
assign M2_mult_3_in2 = mult_op_6;

assign mult_res_1 = M2_mult_res_1;
assign mult_res_2 = M2_mult_res_2;
assign mult_res_3 = M2_mult_res_3;

////////////////////////////////////////////////////////////////////////

logic start_buf,final_C2_write;

//////// M2_signals

always @(posedge CLOCK_50_I or negedge resetn) begin
	if (~resetn) begin
		top_state <= S_M2_IDLE;
		start_buf <= 1'b0;
		M2_done <= 1'b0;

		mult_op_1 <= 32'd0;
		mult_op_2 <= 32'd0;
		mult_op_3 <= 32'd0;
		mult_op_4 <= 32'd0;
		mult_op_5 <= 32'd0;
		mult_op_6 <= 32'd0;

		M2_SRAM_address <= 18'd0;
		M2_SRAM_write_data <= 16'd0;
		M2_SRAM_we_n <= 1'b1;
		C_wren_a<=1'd0;
		C_wren_b<=1'd0;
		C_write_a<=32'd0;
		C_write_b<=32'd0;
		C_address_a<=5'd0;
		C_address_b<=5'd0;
		write_c2<=1'd0;
		sram_fetch_offset <= 18'd76800;
		sram_fetch_u_offset <= 18'd153600;
		S_prime_address_a<=6'd0;
		S_prime_wren_a <= 1'd0;
		S_prime_wren_b <= 1'd0;
		S_prime_row_offset<=6'd0;
		S_prime_column_offset<=6'd0;
		
		C_column_offset<=6'd0;
		C_row_offset<=6'd0;
		
		inner_column_offset<=18'd0;
		inner_row_offset<=18'd0;
		block_row_offset<=18'd0;
		block_column_offset<=18'd0;
		block_row_address<=18'd0;
		block_column_address<=18'd0;
		
		C1_done <= 1'd0;
		c2_done <= 1'd0;
		temp_address<=6'd0;
		prev_block_column_address <= 16'd0;
		prev_block_row_address <= 16'd0;
		yuv_row <= 18'd0;
		yuv_col <= 18'd0;
		start_write <= 16'd0;
		start_temp_write <= 16'd0;
		last_c2_loop <= 1'd0;
		
		temp_column_offset <= 6'd0;
		temp_row_offset <= 6'd0;
		
		temp_c2_clipped_even <= 8'd0;
		temp_c2_clipped_odd <= 8'd0;
		temp <= 64'd0;
		start_c2 <= 1'd0;
		temp_wren_b <= 1'd0;	// Read
		temp_wren_a <= 1'd0;	// Read
		temp_odd_assigned<=1'd0;
		block_number_counter <= 18'd0;
		sram_write_u_offset <= 18'd38400;
		current_yuv <= 2'd0;
		fetching_u_now <= 1'd0;
		c2_write_count <= 6'd0;
		sram_address_to_write_next <= 18'd0;
		tBuff1 <= 32'd0;
		tBuff2 <= 32'd0;
		tBuff3 <= 32'd0;
		tBuff4 <= 32'd0;
		tBuff5 <= 32'd0;
		tBuff6 <= 32'd0;
		tBuff7 <= 32'd0;
		tBuff8 <= 32'd0;
		cTBuff1 <= 32'd0;
		cTBuff2 <= 32'd0;
		cTBuff3 <= 32'd0;
		cTBuff4 <= 32'd0;
		cTBuff5 <= 32'd0;
		cTBuff6 <= 32'd0;
		cTBuff7 <= 32'd0;
		cTBuff8 <= 32'd0;
		temp_addr_buff1 <= 6'd0;
		temp_addr_buff1 <= 6'd0;
		c_addr_buff1 <= 6'd0;
		c_addr_buff2 <= 6'd0;
		temp_addr_even_buff1 <= 6'd0;
		temp_addr_even_buff2 <= 6'd0;
		c_addr_even_buff1 <= 6'd0;
		c_addr_even_buff2 <= 6'd0;
		
	end else begin

		case (top_state)
		S_M2_IDLE: begin
			if(M2_start && ~start_buf) begin
				top_state <= S_M2_0;
			end 

		end
		//// ADD YOUR CODE HERE
		S_M2_0: begin
			
			top_state <= S_M2_1;
		end
		S_M2_1: begin
			M2_SRAM_we_n <= 1'd1;
			
			M2_SRAM_address<=block_row_offset+block_column_offset+inner_column_offset+inner_row_offset + sram_fetch_offset;
			inner_column_offset<=inner_column_offset+16'd1;
			
			if(start_write) begin
				S_prime_address_a<=S_prime_address_a+16'd1;

				S_prime_write_a<={M2_SRAM_read_data[15] ? 16'hffff : 16'h0000, M2_SRAM_read_data};
			
			end
			
			top_state <= S_M2_2;
		end
		S_M2_2: begin
			M2_SRAM_address<=block_row_offset+block_column_offset+inner_column_offset+inner_row_offset + sram_fetch_offset;
			inner_column_offset<=inner_column_offset+16'd1;
			
			if(start_write) begin
			S_prime_address_a<=S_prime_address_a+16'd1;
				S_prime_write_a<={M2_SRAM_read_data[15] ? 16'hffff : 16'h0000, M2_SRAM_read_data};
			
			end
			
			top_state <= S_M2_3;
		end
		S_M2_3: begin
			M2_SRAM_address<=block_row_offset+block_column_offset+inner_column_offset+inner_row_offset + sram_fetch_offset;
			inner_column_offset<=inner_column_offset+16'd1;
			
			if(start_write) begin
			S_prime_address_a<=S_prime_address_a+16'd1;
				S_prime_write_a<={M2_SRAM_read_data[15] ? 16'hffff : 16'h0000, M2_SRAM_read_data};
			
			end
			
			top_state <= S_M2_4;
						
			start_write<=1'b1;
		end
		S_M2_4: begin
			M2_SRAM_address<=block_row_offset+block_column_offset+inner_column_offset+inner_row_offset + sram_fetch_offset;
			inner_column_offset<=inner_column_offset+16'd1;
			
			if(S_prime_address_a==6'd0)
				S_prime_address_a<=S_prime_address_a;
			else
				S_prime_address_a<=S_prime_address_a+16'd1;
			
				S_prime_write_a<={M2_SRAM_read_data[15] ? 16'hffff : 16'h0000, M2_SRAM_read_data};
			S_prime_wren_a<=1'b1;
			
			top_state <= S_M2_5;
		
			
		end
		S_M2_5: begin
			M2_SRAM_address<=block_row_offset+block_column_offset+inner_column_offset+inner_row_offset + sram_fetch_offset;
			inner_column_offset<=inner_column_offset+16'd1;
			
			S_prime_address_a<=S_prime_address_a+16'd1;
				S_prime_write_a<={M2_SRAM_read_data[15] ? 16'hffff : 16'h0000, M2_SRAM_read_data};
			
			top_state <= S_M2_6;
		end
		S_M2_6: begin
			M2_SRAM_address<=block_row_offset+block_column_offset+inner_column_offset+inner_row_offset + sram_fetch_offset;
			inner_column_offset<=inner_column_offset+16'd1;
			
			S_prime_address_a<=S_prime_address_a+16'd1;
				S_prime_write_a<={M2_SRAM_read_data[15] ? 16'hffff : 16'h0000, M2_SRAM_read_data};
			
			top_state <= S_M2_7;
		end
		
		S_M2_7: begin
			M2_SRAM_address<=block_row_offset+block_column_offset+inner_column_offset+inner_row_offset + sram_fetch_offset;
			inner_column_offset<=inner_column_offset+16'd1;
			
			S_prime_address_a<=S_prime_address_a+16'd1;
				S_prime_write_a<={M2_SRAM_read_data[15] ? 16'hffff : 16'h0000, M2_SRAM_read_data};
			
			top_state <= S_M2_8;
		end	
		S_M2_8: begin
			M2_SRAM_address<=block_row_offset+block_column_offset+inner_column_offset+inner_row_offset + sram_fetch_offset;
			
			
			
			S_prime_address_a<=S_prime_address_a+16'd1;
				S_prime_write_a<={M2_SRAM_read_data[15] ? 16'hffff : 16'h0000, M2_SRAM_read_data};	
			
			if(inner_row_offset==16'd2240) begin
				inner_column_offset <= 16'd8;
				inner_row_offset <= 16'd0;
				top_state <= S_M2_9;
				
			end else begin
				inner_column_offset<=16'd0; 
				inner_row_offset<=inner_row_offset+16'd320;	// Next row
				top_state <= S_M2_1;
			end
			
		end
		S_M2_9: begin

			
			S_prime_address_a<=S_prime_address_a+16'd1;
				S_prime_write_a<={M2_SRAM_read_data[15] ? 16'hffff : 16'h0000, M2_SRAM_read_data};
			
			top_state <= S_M2_10;
		end	
		S_M2_10: begin
	
			S_prime_address_a<=S_prime_address_a+16'd1;
				S_prime_write_a<={M2_SRAM_read_data[15] ? 16'hffff : 16'h0000, M2_SRAM_read_data};
			
			top_state <= S_M2_11;
		end	
		S_M2_11: begin
				// the last data fetch for S'
			S_prime_address_a<=S_prime_address_a+16'd1;
				S_prime_write_a<={M2_SRAM_read_data[15] ? 16'hffff : 16'h0000, M2_SRAM_read_data};
			
			//block_column_offset <= block_column_offset + 16'd1;
			block_row_offset <= 16'd0;
			inner_column_offset<=16'd0; 
			inner_row_offset <= 16'd0;
			
			top_state <= S_M2_12;
		end	
		S_M2_12: begin
		
			M2_SRAM_we_n <= 1'd1;
			S_prime_address_a<=S_prime_row_offset+ S_prime_column_offset;
			S_prime_wren_a<=1'd0;
			
			S_prime_address_b<=S_prime_row_offset+ S_prime_column_offset+6'd1;
			S_prime_wren_b<=1'd0;
			
			S_prime_column_offset<=S_prime_column_offset+6'd2;
			
			C_address_a<=C_column_offset+C_row_offset;
			C_wren_a<=1'd0;
			
			
			C_address_b<=C_column_offset+C_row_offset+6'd8;
			C_wren_b<=1'd0;
			
			C_row_offset<=C_row_offset+6'd16;
			final_C2_write<=1'd0;
			top_state <= S_M2_13;
		end	
		S_M2_13: begin
			
			S_prime_address_a<=S_prime_row_offset+ S_prime_column_offset;
			S_prime_address_b<=S_prime_row_offset+ S_prime_column_offset+6'd1;
			S_prime_column_offset<=S_prime_column_offset+6'd2;
			
			C_address_a<=C_column_offset+C_row_offset;
			C_address_b<=C_column_offset+C_row_offset+6'd8;
			C_row_offset<=C_row_offset+6'd16;
			temp <= 64'd0;
			top_state <= S_M2_14;
		end	
		
      S_M2_14: begin

			S_prime_address_a<=S_prime_row_offset+ S_prime_column_offset;
			S_prime_address_b<=S_prime_row_offset+ S_prime_column_offset+6'd1;
			S_prime_column_offset<=S_prime_column_offset+6'd2;
			
			C_address_a<=C_column_offset+C_row_offset;
			C_address_b<=C_column_offset+C_row_offset+6'd8;
			C_row_offset<=C_row_offset+6'd16;		
		
			mult_op_1 <= {S_prime_read_a};
			mult_op_2 <= {C_read_a};
			mult_op_3 <= {S_prime_read_b};
			mult_op_4 <= {C_read_b};
			
			start_temp_write<=1'd1;		
			
			if(start_temp_write) begin
				temp_address_a<=temp_address;		// Can start writing after the first loop
				temp_address<=temp_address+6'd1;
				temp_write_a<= temp_c1[39:8];
				temp_wren_a <= 1'd1;
				temp <= 64'd0;
			end
			
			top_state<=S_M2_15;
      end

      S_M2_15: begin
			
			temp<=temp+M2_mult_res_1+M2_mult_res_2;
			mult_op_1 <= {S_prime_read_a};
			mult_op_2 <= {C_read_a};
			mult_op_3 <= {S_prime_read_b};
			mult_op_4 <= {C_read_b};
						
			S_prime_address_a<=S_prime_row_offset + S_prime_column_offset;
			S_prime_address_b<=S_prime_row_offset + S_prime_column_offset+6'd1;
			S_prime_column_offset<=S_prime_column_offset+6'd2;
			
			C_address_a<=C_column_offset+C_row_offset;
			C_address_b<=C_column_offset+C_row_offset+6'd8;
			temp_wren_a <= 1'd0; 	// Stop writing
			if(C_column_offset==6'd7 && C_row_offset ==6'd48) begin
				if(S_prime_row_offset==6'd56 && S_prime_column_offset==6'd6) begin
					// done C1 for this block
					C_row_offset<=6'd0;
					C_column_offset<=6'd0;
					C1_done<=1'd1;
				end else begin
					// move to a different row in S' block
					C_row_offset<=6'd0;
					C_column_offset<=6'd0;
					
					S_prime_row_offset<=S_prime_row_offset+6'd8;
					S_prime_column_offset<=6'd0;
					//top_state<=S_M2_16;				
				end
			end else begin
				C_column_offset<=C_column_offset+6'd1;
				C_row_offset<=6'd0;
				S_prime_column_offset<=6'd0;
				//top_state<=S_M2_16;
			end  
			top_state<=S_M2_16;					
      end

      S_M2_16: begin
		
		
			temp<=temp+M2_mult_res_1+M2_mult_res_2;
			mult_op_1 <= {S_prime_read_a};
			mult_op_2 <= {C_read_a};
			mult_op_3 <= {S_prime_read_b};
			mult_op_4 <= {C_read_b};
			
			if(~C1_done) begin	
				S_prime_address_a<=S_prime_row_offset+ S_prime_column_offset;
				S_prime_address_b<=S_prime_row_offset+ S_prime_column_offset+6'd1;
				S_prime_column_offset<=S_prime_column_offset+6'd2;
				
				C_address_a<=C_column_offset+C_row_offset;
				C_address_b<=C_column_offset+C_row_offset+6'd8;
				C_row_offset<=C_row_offset+6'd16;		
			end
         top_state<=S_M2_17;
      end

      S_M2_17: begin
		
			temp<=temp+M2_mult_res_1+M2_mult_res_2;
			mult_op_1 <= {S_prime_read_a};
			mult_op_2 <= {C_read_a};
			mult_op_3 <= {S_prime_read_b};
			mult_op_4 <= {C_read_b};
			
			if(C1_done)
				top_state<=S_M2_18;
			else begin
				S_prime_address_a<=S_prime_row_offset+ S_prime_column_offset;
				S_prime_address_b<=S_prime_row_offset+ S_prime_column_offset+6'd1;
				S_prime_column_offset<=S_prime_column_offset+6'd2;
				
				C_address_a<=C_column_offset+C_row_offset;
				C_address_b<=C_column_offset+C_row_offset+6'd8;
				C_row_offset<=C_row_offset+6'd16;		
			
				top_state<=S_M2_14; // Contine reading for C1
			end
				
      end

      S_M2_18: begin
			
			temp_address_a<=temp_address;	// Last write for C1
			temp_address<=temp_address+6'd1;
			temp_write_a<= temp_c1[39:8];
			temp_wren_a <= 1'd1;
			C_column_offset<= 6'd0;
			C_row_offset<= 6'd0;
			C_wren_b<=1'd0;
			C_wren_a<=1'd0;			
			temp_column_offset <= 6'd0;
			temp_row_offset <= 6'd0;	

         top_state<=S_M2_19;
      end

      S_M2_19: begin
			temp_wren_a <= 1'd0;	// stop writing
			block_column_offset <= block_column_offset + 16'd1;
			C_address_a<=C_column_offset+C_row_offset;
			C_address_b<=C_column_offset+C_row_offset+6'd8;
			C_row_offset<=C_row_offset+6'd16;
			
			temp_address_a <= temp_column_offset + temp_row_offset;
			temp_address_b <= temp_column_offset + temp_row_offset + 6'd8;	
			temp_row_offset <= temp_row_offset + 6'd16;
			temp <= 16'd0;
			
			S_prime_row_offset <= 6'd0;
			S_prime_column_offset <= 6'd0;
			S_prime_address_a <= 6'd63;
			mult_op_5 <= 32'd2560;
			mult_op_6 <= block_row_offset;
			c2_done <= 1'd0;
			C1_done <= 1'd0;
			last_c2_loop <= 1'd0;
			yuv_row <= 18'd0;
			start_c2 <= 1'd0;
			c2_write_count <= 6'd0;
			temp_addr_buff1 <= 6'd0;
			temp_addr_buff2 <= 6'd0;
			c_addr_buff1 <= 6'd0;
			c_addr_buff2 <= 6'd0;
			
         top_state<=S_M2_intermediate;
      end
		S_M2_intermediate: begin
			if(block_column_offset==16'd40 && current_yuv == 2'd0) begin
				block_column_offset<=16'd0;
				block_row_offset<= block_row_offset+16'd1;
				mult_op_6 <= block_row_offset+16'd1;
			end else if (block_column_offset==16'd20 && current_yuv == 2'd1) begin		// u
				block_column_offset<=16'd0;
				block_row_offset<= block_row_offset+16'd1;
				mult_op_6 <= block_row_offset+16'd1;			
			end
			block_number_counter <= block_number_counter + 18'd1;
		
			top_state<=S_M2_20;
		end
      S_M2_20: begin
			if (block_number_counter == 18'd1200) begin
				fetching_u_now <= 1'd1;
			end
			block_row_address <= mult_res_3;							// row * 2560
			block_column_address <= block_column_offset << 3;		// column * 8
		
			prev_block_column_address <= block_column_address >> 1;
			prev_block_row_address <= block_row_address >> 1;
		
			C_address_a<=C_column_offset+C_row_offset;
			C_address_b<=C_column_offset+C_row_offset+6'd8;
			C_row_offset<=C_row_offset+6'd16;
			
			inner_column_offset <= 16'd0;
			inner_row_offset <= 16'd0;
			temp_address_a <= temp_column_offset + temp_row_offset;
			temp_wren_a <= 1'd0;	// Read

			
			temp_address_b <= temp_column_offset + temp_row_offset + 6'd8;	
			temp_row_offset <= temp_row_offset + 6'd16;
			
			write_c2 <= 1'd0;	// Don't write in the first c2 loop
		
		
         top_state<=S_M2_21;
      end

      S_M2_21: begin
			M2_SRAM_we_n <= 1'd1;	// Set reading for sram
			S_prime_wren_a <= 1'd0; // stop writing the fetched value
			M2_SRAM_address<=block_row_address+block_column_address+inner_column_offset+inner_row_offset + sram_fetch_offset;		// Fetch S8, then S9, .. S15. Then S328 etc
			inner_column_offset<=inner_column_offset+16'd1;
			

			
			if (inner_column_offset == 16'd7 && inner_row_offset == 16'd2560) begin	
				c2_done <= 1'd1;
				
				if (block_column_offset < 16'd7) begin		// Go to the right block
					block_column_offset <= block_column_offset + 16'd1;
					block_row_offset <= 16'd0;
					inner_column_offset <= 16'd0;
					inner_row_offset <= 16'd0;
				
				end else if (block_column_offset == 16'd7) begin	// If at rightmost block
					
					if (block_row_offset < 16'd7) begin		// If not at bottom right, go down left
						block_row_offset <= block_row_offset + 16'd1;
						block_column_offset <= 16'd0;
						inner_column_offset <= 16'd0;
						inner_row_offset <= 16'd0;
					
					end else if (block_row_offset == 16'd7) begin	// at the bottom right (ie last block)
						
						// Finished m2					
					end
				
				end
			end else if (inner_column_offset == 16'd7 && fetching_u_now) begin
				inner_row_offset <= inner_row_offset + 16'd160;
				inner_column_offset <= 16'd0;
			end else if (inner_column_offset == 16'd7 && ~fetching_u_now) begin
				inner_row_offset <= inner_row_offset + 16'd320;
				inner_column_offset <= 16'd0;			
			end
			
			
						
			C_address_a<=C_column_offset+C_row_offset;
			C_address_b<=C_column_offset+C_row_offset+6'd8;
			C_row_offset<=C_row_offset+6'd16;
			
			temp_address_a <= temp_column_offset + temp_row_offset;
			temp_address_b <= temp_column_offset + temp_row_offset + 6'd8;	
			temp_row_offset <= temp_row_offset + 6'd16;
			if (c2_write_count == 6'd31 && current_yuv == 2'd0) begin
				temp_addr_buff1 <= temp_column_offset + temp_row_offset;
				temp_addr_buff2 <= temp_column_offset + temp_row_offset + 6'd8;	
				c_addr_buff1 <= C_column_offset+C_row_offset;
				c_addr_buff2 <= C_column_offset+C_row_offset+6'd8;
			end else if (c2_write_count == 6'd31 && current_yuv == 2'd1) begin
				temp_addr_buff1 <= temp_column_offset + temp_row_offset;
				temp_addr_buff2 <= temp_column_offset + temp_row_offset + 6'd8;	
				c_addr_buff1 <= C_column_offset+C_row_offset;
				c_addr_buff2 <= C_column_offset+C_row_offset+6'd8;			
			end
			
			mult_op_1 <= {temp_read_a};
			mult_op_2 <= {C_read_a};
			mult_op_3 <= {temp_read_b};
			mult_op_4 <= {C_read_b};	
	
			if (start_c2) begin
				temp<=temp+M2_mult_res_1+M2_mult_res_2;
				if (write_c2) begin
					temp_c2_clipped_odd <= temp_c1[63]? 8'd0:(|temp_c1[62:24] ? 8'd255:temp_c1[23:16]);	// Clipping Y1
					temp_odd_assigned<=1'd1;
				end else begin
					temp_c2_clipped_even <= temp_c1[63]? 8'd0:(|temp_c1[62:24] ? 8'd255:temp_c1[23:16]);	// Clipping Y0
					write_c2 <= 1'd1;
		
				
				end
			temp<=64'd0;
			end else 
				start_c2 <= 1'd1;
			
//			if(start_c2)
//				write_c2 <= ~write_c2;
				
			
         top_state<=S_M2_22;
      end
		
		
		

      S_M2_22: begin
			mult_op_5 <= 32'd2560;
			mult_op_6 <= block_row_offset;
			
			temp<=temp+M2_mult_res_1+M2_mult_res_2;
		
			if(temp_column_offset == 6'd7 && temp_row_offset == 6'd48) begin		// either go to next temp, or done (next temp, same c)
			
				if(C_row_offset==6'd56 && C_column_offset==6'd6) begin	// done all c and temp
					// done C2 for this block
					temp_row_offset<=6'd0;
					temp_column_offset<=6'd0;
					c2_done <= 1'd1;
					
				end else begin		
					// move to a different column in c block
					temp_row_offset<=6'd0;
					temp_column_offset<=6'd0;
					
					C_row_offset <= 6'd0;
					C_column_offset <= C_column_offset + 6'd1;
							
				end
					
			end else begin	// temp is not done, go to next temp column. keep c same.
			
				temp_column_offset <= temp_column_offset + 6'd1;
				temp_row_offset <= temp_row_offset + 6'd16;
				
				C_row_offset <= C_row_offset + 6'd16;
				
			
			end
			
			if (write_c2 && temp_odd_assigned) begin	// Write Y01
				c2_write_count <= c2_write_count + 1;
				if (c2_write_count == 6'd30 && current_yuv == 2'd0)
					sram_address_to_write_next <= prev_block_row_address + prev_block_column_address + yuv_row + yuv_col + 18'd1;
				else if (c2_write_count == 6'd30 && current_yuv == 2'd1)
					sram_address_to_write_next <= prev_block_row_address + prev_block_column_address + yuv_row + yuv_col + 18'd1;
				M2_SRAM_we_n <= 1'd0;	// Write for sram
				M2_SRAM_write_data <= {temp_c2_clipped_even, temp_c2_clipped_odd};
				M2_SRAM_address <= prev_block_row_address + prev_block_column_address + yuv_row + yuv_col;
				if (prev_block_row_address + prev_block_column_address + yuv_row + yuv_col == 18'd76800) begin
				         top_state<=S_M2_DONE;
							M2_done <= 1'b1;
				end
				temp_odd_assigned<=1'd0;
				write_c2 <= 1'd0;
				//temp <= 64'd0;		// temp back to zero
				if (yuv_col == 18'd3 && current_yuv == 1'd0) begin // for y
					yuv_row <= yuv_row + 18'd160;
					yuv_col <= 18'd0;
				end else if (yuv_col == 18'd3 && current_yuv == 1'd1) begin		// for u
					yuv_row <= yuv_row + 18'd80;
					yuv_col <= 18'd0;				
				end else begin
					yuv_col <= yuv_col + 18'd1;
				end
			end
			
		
		
			C_address_a<=C_column_offset+C_row_offset;
			C_address_b<=C_column_offset+C_row_offset+6'd8;
			
			temp_address_a <= temp_column_offset + temp_row_offset;
			temp_address_b <= temp_column_offset + temp_row_offset + 6'd8;	

			C_row_offset <= C_row_offset + 6'd16;
			temp_row_offset <= temp_row_offset + 6'd16;			
				
				
			mult_op_1 <= {temp_read_a};
			mult_op_2 <= {C_read_a};
			mult_op_3 <= {temp_read_b};
			mult_op_4 <= {C_read_b};	
			if (prev_block_row_address + prev_block_column_address + yuv_row + yuv_col != 18'd76800) begin
				top_state<=S_M2_23;
			end else if (prev_block_row_address + prev_block_column_address + yuv_row + yuv_col == 18'd76800) begin
				top_state<=S_M2_DONE;
				M2_done <= 1'b1;
			end
      end

      S_M2_23: begin
			M2_SRAM_we_n <= 1'd1;
			block_row_address <= mult_res_3;							// row * 2560
			mult_op_5 <= 32'd8;
			mult_op_6 <= block_column_offset;
						
			temp<=temp+M2_mult_res_1+M2_mult_res_2;
			
			
 			if (block_number_counter < 16'd1200 && yuv_col == 18'd3 && yuv_row == 18'd1120) begin		// Done this block, can go back to c1
				c2_done <= 1'd1;
			end else if (block_number_counter >= 16'd1200 && yuv_col == 18'd3 && yuv_row == 18'd560) begin	// for u
				c2_done <= 1'd1;
			
			end else if(!c2_done) begin	// no more multiplications, just do the last write for this block
				C_address_a<=C_column_offset+C_row_offset;
				C_address_b<=C_column_offset+C_row_offset+6'd8;
				
				temp_address_a <= temp_column_offset + temp_row_offset;
				temp_address_b <= temp_column_offset + temp_row_offset + 6'd8;
				
				mult_op_1 <= {temp_read_a};
				mult_op_2 <= {C_read_a};
				mult_op_3 <= {temp_read_b};
				mult_op_4 <= {C_read_b};	
				
				C_row_offset <= C_row_offset + 6'd16;
				temp_row_offset <= temp_row_offset + 6'd16;
				
			end
			
			if (prev_block_row_address + prev_block_column_address + yuv_row + yuv_col == 18'd230399) begin
				top_state<=S_M2_DONE;
			end else begin
				top_state<=S_M2_24;
			end
      end

      S_M2_24: begin
			//M2_SRAM_address<=block_row_address+block_column_address+inner_column_offset+inner_row_offset + sram_fetch_offset;		// Fetch S8, then S9, .. S15. Then S328 etc
			block_column_address <= mult_res_3;
			M2_SRAM_we_n <= 1'd1;	// Stop writing for sram
		
			// Write s'
			S_prime_address_a<=S_prime_address_a+16'd1;
			S_prime_wren_a <= 1'd1;
			S_prime_write_a<={M2_SRAM_read_data[15] ? 16'hffff : 16'h0000, M2_SRAM_read_data};
			
			
			temp<=temp+M2_mult_res_1+M2_mult_res_2;
			if (block_number_counter == 18'd1200 && M2_SRAM_address == 18'd38399) begin
				S_prime_wren_a <= 1'd0;
				top_state <= S_M2_12;		// Now do c1 for u
				inner_column_offset <= 16'd0; 
				inner_row_offset <= 16'd0;
				current_yuv <= 2'd1;		// 1 = doing u values now
				C_column_offset <= 6'd0;
				C_row_offset <= 6'd0;
				yuv_row <= 18'd0;		// copied these 5 from below
				yuv_col <= 18'd0;
				temp_row_offset <= 6'd0;
				temp_column_offset <= 6'd0;
				start_temp_write <= 1'd0;				
			end else if (!c2_done) begin
			
				C_address_a<=C_column_offset+C_row_offset;
				C_address_b<=C_column_offset+C_row_offset+6'd8;

				temp_address_a <= temp_column_offset + temp_row_offset;
				temp_address_b <= temp_column_offset + temp_row_offset + 6'd8;			
			
				C_row_offset <= C_row_offset + 6'd16;
				temp_row_offset <= temp_row_offset + 6'd16;
			
				mult_op_1 <= {temp_read_a};
				mult_op_2 <= {C_read_a};
				mult_op_3 <= {temp_read_b};
				mult_op_4 <= {C_read_b};	
				top_state<=S_M2_21;		// loop back to 21
			end	else if (c2_done && !last_c2_loop)begin
				last_c2_loop <= 1'd1;
				top_state<=S_M2_21;
			end else if (c2_done && last_c2_loop) begin
				C_column_offset <= 6'd0;
				C_row_offset <= 6'd0;
				yuv_row <= 18'd0;
				yuv_col <= 18'd0;
				temp_row_offset <= 6'd0;
				temp_column_offset <= 6'd0;
				start_temp_write <= 1'd0;
				if (current_yuv == 2'd1)
					S_prime_wren_a <= 1'd0;
				if (c2_write_count == 6'd31 && current_yuv == 2'd0) 
					top_state<=S_M2_INT_1;
				else if (c2_write_count == 6'd31 && current_yuv == 2'd1)
					top_state<=S_M2_INT_1;
				else
					top_state<=S_M2_12;
			end 
					// Write every 2nd loop
		end
		
		S_M2_INT_1: begin	// just do multiplications and then the write. no need to fetch
			temp_addr_even_buff1 <= temp_addr_buff1 - 6'd1;		// For odd - will do this later
			temp_addr_even_buff2 <= temp_addr_buff2 - 6'd1;
			c_addr_even_buff1 <= c_addr_buff1;
			c_addr_even_buff2 <= c_addr_buff2;
			
			temp_address_a <= temp_addr_buff1;
			temp_address_b <= temp_addr_buff2;
			C_address_a <= c_addr_buff1;
			C_address_b <= c_addr_buff2;
			
			temp_addr_buff1 <= temp_addr_buff1 + 6'd16;
			temp_addr_buff2 <= temp_addr_buff2 + 6'd16;
			c_addr_buff1 <= c_addr_buff1 + 6'd16;
			c_addr_buff2 <= c_addr_buff2 + 6'd16;			
			
			temp_wren_a <= 1'd0;
			temp_wren_b <= 1'd0;
			C_wren_a <= 1'd0;
			C_wren_b <= 1'd0;
			top_state<=S_M2_INT_2;
			temp<= 64'd0;
			temp_c2_clipped_even <= 8'd0;
			temp_c2_clipped_odd <= 8'd0;
		end
		
		S_M2_INT_2: begin
			temp_address_a <= temp_addr_buff1;
			temp_address_b <= temp_addr_buff2;
			C_address_a <= c_addr_buff1;
			C_address_b <= c_addr_buff2;
			
			temp_addr_buff1 <= temp_addr_buff1 + 6'd16;
			temp_addr_buff2 <= temp_addr_buff2 + 6'd16;
			c_addr_buff1 <= c_addr_buff1 + 6'd16;
			c_addr_buff2 <= c_addr_buff2 + 6'd16;			
			
			top_state<=S_M2_INT_3;			
		end

		S_M2_INT_3: begin		// got values from int_1
			mult_op_1 <= temp_read_a;
			mult_op_2 <= C_read_a;
			mult_op_3 <= temp_read_b;
			mult_op_4 <= C_read_b;
			
			temp_address_a <= temp_addr_buff1;
			temp_address_b <= temp_addr_buff2;
			C_address_a <= c_addr_buff1;
			C_address_b <= c_addr_buff2;
			
			temp_addr_buff1 <= temp_addr_buff1 + 6'd16;
			temp_addr_buff2 <= temp_addr_buff2 + 6'd16;
			c_addr_buff1 <= c_addr_buff1 + 6'd16;
			c_addr_buff2 <= c_addr_buff2 + 6'd16;			
			
			top_state<=S_M2_INT_4;			
		end
		S_M2_INT_4: begin		// values from int_2
			temp <= mult_res_1 + mult_res_2 + temp;
			
			// last read for odd
			temp_address_a <= temp_addr_buff1;
			temp_address_b <= temp_addr_buff2;
			C_address_a <= c_addr_buff1;
			C_address_b <= c_addr_buff2;
	
			mult_op_1 <= temp_read_a;
			mult_op_2 <= C_read_a;
			mult_op_3 <= temp_read_b;
			mult_op_4 <= C_read_b;
			top_state<=S_M2_INT_5;	
		end
		S_M2_INT_5: begin // values from int_3
			temp <= mult_res_1 + mult_res_2 + temp;
			mult_op_1 <= temp_read_a;
			mult_op_2 <= C_read_a;
			mult_op_3 <= temp_read_b;
			mult_op_4 <= C_read_b;

				// Switch to reading for even		
			temp_address_a <= temp_addr_even_buff1;
			temp_address_b <= temp_addr_even_buff2;
			C_address_a <= c_addr_even_buff1;
			C_address_b <= c_addr_even_buff2;

			temp_addr_even_buff1 <= temp_addr_even_buff1 + 6'd16;
			temp_addr_even_buff2 <= temp_addr_even_buff2 + 6'd16;
			c_addr_even_buff1 <= c_addr_even_buff1 + 6'd16;
			c_addr_even_buff2 <= c_addr_even_buff2 + 6'd16;			
	
			top_state<=S_M2_INT_6;	
		end
		S_M2_INT_6: begin // values from int_4
			temp <= mult_res_1 + mult_res_2 + temp;
			mult_op_1 <= temp_read_a;
			mult_op_2 <= C_read_a;
			mult_op_3 <= temp_read_b;
			mult_op_4 <= C_read_b;	
			
			temp_address_a <= temp_addr_even_buff1;
			temp_address_b <= temp_addr_even_buff2;
			C_address_a <= c_addr_even_buff1;
			C_address_b <= c_addr_even_buff2;
			
			temp_addr_even_buff1 <= temp_addr_even_buff1 + 6'd16;
			temp_addr_even_buff2 <= temp_addr_even_buff2 + 6'd16;
			c_addr_even_buff1 <= c_addr_even_buff1 + 6'd16;
			c_addr_even_buff2 <= c_addr_even_buff2 + 6'd16;		
			
			top_state<=S_M2_INT_7;				
		end
		S_M2_INT_7: begin			
			temp <= mult_res_1 + mult_res_2 + temp;
			
			// first multiplication for even
			mult_op_1 <= temp_read_a;
			mult_op_2 <= C_read_a;
			mult_op_3 <= temp_read_b;
			mult_op_4 <= C_read_b;
			
			temp_address_a <= temp_addr_even_buff1;
			temp_address_b <= temp_addr_even_buff2;
			C_address_a <= c_addr_even_buff1;
			C_address_b <= c_addr_even_buff2;
		
			temp_addr_even_buff1 <= temp_addr_even_buff1 + 6'd16;
			temp_addr_even_buff2 <= temp_addr_even_buff2 + 6'd16;
			c_addr_even_buff1 <= c_addr_even_buff1 + 6'd16;
			c_addr_even_buff2 <= c_addr_even_buff2 + 6'd16;		
			
			top_state<=S_M2_INT_8;			
		end	
		S_M2_INT_8: begin		// 2nd mult
			temp <= mult_res_1 + mult_res_2;
		
			mult_op_1 <= temp_read_a;
			mult_op_2 <= C_read_a;
			mult_op_3 <= temp_read_b;
			mult_op_4 <= C_read_b;	
	
			temp_address_a <= temp_addr_even_buff1;
			temp_address_b <= temp_addr_even_buff2;
			C_address_a <= c_addr_even_buff1;
			C_address_b <= c_addr_even_buff2;
			
			temp_c2_clipped_odd <= temp[63]? 8'd0:(|temp[62:24] ? 8'd255:temp[23:16]);
			
			top_state<=S_M2_INT_9;			
		end		
		
		
		S_M2_INT_9: begin
			temp <= mult_res_1 + mult_res_2 + temp;	
	
			mult_op_1 <= temp_read_a;	// 3rd mult
			mult_op_2 <= C_read_a;
			mult_op_3 <= temp_read_b;
			mult_op_4 <= C_read_b;
			top_state<=S_M2_INT_10;			
		end		
		
		S_M2_INT_10: begin
			temp <= mult_res_1 + mult_res_2 + temp;	
		
			mult_op_1 <= temp_read_a;		// 4th mult
			mult_op_2 <= C_read_a;
			mult_op_3 <= temp_read_b;
			mult_op_4 <= C_read_b;
	
		
			top_state<=S_M2_INT_11;			
		end		

		S_M2_INT_11: begin
	
			temp <= mult_res_1 + mult_res_2 + temp;
			top_state<=S_M2_INT_12;			
		end		
				
		S_M2_INT_12: begin
	
			temp_c2_clipped_even <= temp[63]? 8'd0:(|temp[62:24] ? 8'd255:temp[23:16]);
			top_state<=S_M2_INT_13;			
		end	
	
	
		S_M2_INT_13: begin
	
			M2_SRAM_address <= sram_address_to_write_next;
			M2_SRAM_we_n<= 1'd0;	// for write
			M2_SRAM_write_data <= {temp_c2_clipped_even, temp_c2_clipped_odd};
			
			top_state<=S_M2_12;		// c1 next block			
		end		
						
	
		S_M2_DONE: begin
			if(C_address_a== 5'd63) begin
				M2_done <= 1'b1;
				top_state <= S_M2_IDLE;
			end else begin
				top_state<=S_M2_1;
			end
		end

		default: top_state <= S_M2_IDLE;
		endcase
	end
end

always_comb begin
	temp_c1=temp+M2_mult_res_1+M2_mult_res_2;
end

endmodule
