`timescale 1ns / 1ps
`include "xdefs.vh"
`include "xaludefs.vh"

module xalu (
      // Control 
      input                            clk,
      input                            rst, 
      
      // Data
      input [`N*`DATA_W-1:0] 	         data_bus,
      input [`N*`DATA_W-1:0] 	         data_bus_prev,
      output reg signed [`DATA_W-1:0]  result,
      
      // Config data
      input [`ALU_CONF_BITS - 1:0]     configdata	
      );
   
   reg 					             rst_reg;
   
   reg [`DATA_W:0] 			     ai;
   reg [`DATA_W:0] 			     bz;
   wire [`DATA_W:0] 			   temp_adder;
   wire [5:0] 				       data_out_clz_i;
   reg 					             cin;

   reg signed [`DATA_W-1:0]  result_int;

   wire [`N_W-1: 0]          sela;
   wire [`N_W-1: 0]          selb;

   wire [`DATA_W-1:0]        op_a;
   wire [`DATA_W-1:0]        op_b;
   reg 					             op_a_msb;
   reg 					             op_b_msb;
   reg [`DATA_W-1:0] 			   op_a_reg;
   reg [`DATA_W-1:0] 			   op_b_reg;
   wire [`ALU_FNS_W-1:0] 		 fns;

   wire 				             enablea;
   wire 				             enableb;
   wire 				             enabled;
   
   // Unpack config data
   assign sela = configdata[`ALU_CONF_BITS-1 -: `N_W];
   assign selb = configdata[`ALU_CONF_BITS-`N_W-1 -: `N_W];
   assign fns = configdata[`ALU_FNS_W-1 : 0];

   // Input selection 
   xinmux muxa (
		.sel(sela),
		.data_bus_prev(data_bus_prev),
    .data_bus(data_bus),
		.data_out(op_a),
    .enabled(enablea)
		);
   
   xinmux muxb (
		.sel(selb),
		.data_bus(data_bus),
		.data_bus_prev(data_bus_prev),
		.data_out(op_b),
    .enabled(enableb)
		);

   assign enabled = enablea & enableb;
   
   always @ (posedge clk)
     rst_reg <= rst;
   
   always @ (posedge clk)
     if (rst_reg) begin
	op_b_reg <= `DATA_W'h00000000;
	op_a_reg <= `DATA_W'h00000000;
     end else begin
	op_b_reg <= op_b;
	op_a_reg <= op_a;
     end // else: !if(rst)
   
   // Computes result_int
   always @ * begin
      
      result_int = temp_adder[31:0] ;

      case (fns)
	`ALU_OR : begin
	   result_int = op_a_reg | op_b_reg;
	end
	`ALU_AND : begin
	   result_int = op_a_reg & op_b_reg;
	end
	`ALU_XOR : begin
	   result_int = op_a_reg ^ op_b_reg;
	end 	
	`ALU_SEXT8 : begin      
	   result_int = {{24{op_a_reg[7]}}, op_a_reg[7:0]};
	end
	`ALU_SEXT16 : begin
	   result_int = {{16{op_a_reg[15]}}, op_a_reg[15:0]};  
	end
	`ALU_SHIFTR_ARTH : begin
	   result_int = {op_a_reg[31] ,op_a_reg[31:1] };
	end
	`ALU_SHIFTR_LOG : begin
	   result_int = {1'b 0,op_a_reg[31:1] };
	end
	`ALU_CMP_SIG : begin
	   result_int[31] = temp_adder[32] ;
	end
	`ALU_CMP_UNS : begin
	   result_int[31] = temp_adder[32] ;
	end
	`ALU_MUX : begin
	   result_int = op_b_reg;
	   
	   if(op_a_reg[31])
	     result_int = `DATA_W'b0;
	end
	`ALU_SUB : begin
	end
	`ALU_ADD : begin
	end
	`ALU_CLZ : begin
           result_int = {{26{1'b0}},data_out_clz_i};
	end
	`ALU_MAX : begin
           if (temp_adder[32] == 1'b 0) begin
              result_int = op_b_reg;
           end
           else begin
              result_int = op_a_reg;
           end
	end
	`ALU_MIN : begin
           if (temp_adder[32] == 1'b 0) begin
              result_int = op_a_reg;
           end
           else begin
              result_int = op_b_reg;
           end
	end
	default : begin
	end
      endcase // case (fns)
   end

   // Computes temp_adder
   assign temp_adder = ((bz & ({op_b_msb,op_b_reg}))) + ((ai ^ ({op_a_msb,op_a_reg}))) + {{32{1'b0}},cin};

   // Compute ai, cin, bz
   always @ * begin
      cin = 1'b 0;
      ai = {33{1'b0}}; // will invert op_a_reg if set to all ones
      bz = {33{1'b1}}; // will zero op_b_reg if set to all zeros

      op_a_msb = 1'b0;
      op_b_msb = 1'b0;
      
      case(fns)
	`ALU_CMP_SIG : begin
	   ai = {33{1'b1}};
	   cin = 1'b 1;
	   op_a_msb = op_a_reg[31];
	   op_b_msb = op_b_reg[31];
	end
	`ALU_CMP_UNS : begin
	   ai = {33{1'b1}};
	   cin = 1'b 1;
	end
	`ALU_SUB : begin
	   ai = {33{1'b1}};
	   cin = 1'b 1;
	end
	`ALU_MAX : begin
           ai = {33{1'b1}};
           cin = 1'b 1;
	   op_a_msb = op_a_reg[31];
	   op_b_msb = op_b_reg[31];
	end
	`ALU_MIN : begin
           ai = {33{1'b1}};
           cin = 1'b 1;
	   op_a_msb = op_a_reg[31];
	   op_b_msb = op_b_reg[31];
	end
	`ALU_ABS : begin
           if (op_a_reg[31]  == 1'b 1) begin
              // ra is negative
              ai = {33{1'b1}};
              cin = 1'b 1;
           end
           bz = {33{1'b0}};
	end
	default : begin
	end
      endcase
   end

   // Count leading zeros
   xclz clz (
             .data_in(op_a_reg),
	           .data_out(data_out_clz_i)
	     );

   always @ (posedge clk)
     if (rst_reg)
       result <= `DATA_W'h00000000;
     else if (enabled) begin
	     result <= result_int;
     end
   
endmodule
