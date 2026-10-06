`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.08.2026 14:35:32
// Design Name: 
// Module Name: crc32_8bit_parallel
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module crc32_8bit_parallel (
    input  wire [31:0] current_crc, 
    input  wire [7:0]  data_in,     
    output reg  [31:0] next_crc     
 );
   integer i;
    reg [31:0] temp_crc;
    always @(*) begin
        temp_crc = current_crc;
        
        for (i = 0; i < 8; i = i + 1) begin
          
            if ((temp_crc[0] ^ data_in[i]) == 1'b1) begin
                temp_crc = (temp_crc >> 1) ^ 32'hEDB88320;
            end else begin
                temp_crc = (temp_crc >> 1);
            end
        end
        
        next_crc = temp_crc;
    end

 endmodule
