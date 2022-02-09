/// Description: Governs atomic memory oeprations. This module needs to be instantiated
/// in front of an SRAM. It needs to have exclusive access over it.

/// Author: Florian Zaruba <zarubaf@iis.ee.ethz.ch>
module amo_shim #(
    parameter  int unsigned AddrMemWidth = 32,
    parameter  int unsigned DataWidth = 64
) (
    input   logic                     clk_i,
    input   logic                     rst_ni,
    // master side
    input   logic                     in_req_i,     // Bank request
    output  logic                     in_gnt_o,     // Bank grant
    input   logic [AddrMemWidth-1:0]  in_add_i,     // Address
    input   logic [3:0]               in_amo_i,     // Atomic Memory Operation
    input   logic                     in_wen_i,     // 1: Store, 0: Load
    input   logic [DataWidth-1:0]     in_wdata_i,   // Write data
    input   logic [DataWidth/8-1:0]   in_be_i,      // Byte enable
    output  logic [DataWidth-1:0]     in_rdata_o,   // Read data
    // slave side
    output  logic                     out_req_o,    // Bank request
    output  logic [AddrMemWidth-1:0]  out_add_o,    // Address
    output  logic                     out_wen_o,    // 1: Store, 0: Load
    output  logic [DataWidth-1:0]     out_wdata_o,  // Write data
    output  logic [DataWidth/8-1:0]   out_be_o,     // Byte enable
    input   logic [DataWidth-1:0]     out_rdata_i   // Read data
);

    typedef enum logic [3:0] {
        AMONone = 4'h0,
        AMOSwap = 4'h1,
        AMOAdd  = 4'h2,
        AMOAnd  = 4'h3,
        AMOOr   = 4'h4,
        AMOXor  = 4'h5,
        AMOMax  = 4'h6,
        AMOMaxu = 4'h7,
        AMOMin  = 4'h8,
        AMOMinu = 4'h9,
        AMOCAS  = 4'hA
    } amo_op_t;

    enum logic {
        Idle, DoAMO
    } state_q;

    amo_op_t     amo_op_q;

    logic        load_amo;

    logic [AddrMemWidth-1:0] addr_q;

    logic [31:0] amo_operand_a;
    logic [31:0] amo_operand_b_d, amo_operand_b_q;
    // requested amo should be performed on upper 32 bit
    logic        upper_word_d, upper_word_q;
    logic [31:0] swap_value_d, swap_value_q;
   logic [31:0]  amo_res, amo_result; // result of atomic memory operation

    generate
       if (DataWidth == 64) begin
          assign amo_operand_a   = (upper_word_q) ? out_rdata_i [63:32] : out_rdata_i [31:0];
          assign amo_operand_b_d = (!in_be_i [0]) ? in_wdata_i  [63:32] : in_wdata_i  [31:0];
          assign amo_res         = out_rdata_i [63:32];
          assign upper_word_d    = in_be_i [4];
          assign swap_value_d    = in_wdata_i [63:32];
       end
       else begin
          assign amo_operand_a   = out_rdata_i [31:0];
          assign amo_operand_b_d = in_wdata_i  [31:0];
          assign upper_word_d    = '0;
          assign swap_value_d    = '0;
          assign amo_res       = out_rdata_i [31:0];
       end
    endgenerate

    always_comb begin
        // feed-through
        out_req_o   = in_req_i;
        in_gnt_o    = in_req_i;
        out_add_o   = in_add_i;
        out_wen_o   = in_wen_i;
        out_wdata_o = in_wdata_i;
        out_be_o    = in_be_i;
        in_rdata_o  = out_rdata_i;

        load_amo = 1'b0;

        unique case (state_q)
            Idle: begin
                if (in_req_i && amo_op_t'(in_amo_i) != AMONone) begin
                    load_amo = 1'b1;
                    out_wen_o = 1'b0;
                end
            end

            // Claim the memory interface
            DoAMO: begin
                in_gnt_o    = 1'b0;
                // Commit AMO
                out_req_o   = 1'b1;
                out_add_o   = addr_q;
                out_wen_o   = 1'b1;
                // shift up if the address was pointing to the upper 32 bits
                if (DataWidth == 64) begin
                    if (upper_word_q) begin
                        out_be_o = 8'b1111_0000;
                        out_wdata_o = {amo_result, 32'b0};
                        in_rdata_o = {amo_operand_a, 32'b0};
                    end else begin
                        out_be_o = 8'b0000_1111;
                        out_wdata_o = {32'b0, amo_result};
                        in_rdata_o = {32'b0, amo_operand_a};
                    end
                end else begin
                    out_be_o = 4'b1111;
                    out_wdata_o = amo_result;
                    in_rdata_o = amo_operand_a;
                end
            end
            default:;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q         <= Idle;
            amo_op_q        <= amo_op_t'('0);
            addr_q          <= '0;
            amo_operand_b_q <= '0;
            swap_value_q    <= '0;
            upper_word_q    <= '0;
        end else begin
            if (load_amo) begin
                amo_op_q        <= amo_op_t'(in_amo_i);
                addr_q          <= in_add_i;
                amo_operand_b_q <= amo_operand_b_d;
                upper_word_q    <= upper_word_d;
                swap_value_q    <= swap_value_d;
                state_q         <= DoAMO;
            end else begin
                amo_op_q        <= AMONone;
                state_q         <= Idle;
            end
        end
    end

    // ----------------
    // AMO ALU
    // ----------------
    logic [33:0] adder_sum;
    logic [32:0] adder_operand_a, adder_operand_b;

    assign adder_sum = adder_operand_a + adder_operand_b;
    /* verilator lint_off WIDTH */
    always_comb begin : amo_alu

        adder_operand_a = 33'($signed(amo_operand_a));
        adder_operand_b = 33'($signed(amo_operand_b_q));

        amo_result = amo_operand_b_q;

        unique case (amo_op_q)
            // the default is to output operand_b
            AMOSwap:;
            AMOAdd: amo_result = adder_sum[31:0];
            AMOAnd: amo_result = amo_operand_a & amo_operand_b_q;
            AMOOr:  amo_result = amo_operand_a | amo_operand_b_q;
            AMOXor: amo_result = amo_operand_a ^ amo_operand_b_q;
            AMOMax: begin
                adder_operand_b = -$signed(amo_operand_b_q);
                amo_result = adder_sum[32] ? amo_operand_b_q : amo_operand_a;
            end
            AMOMin: begin
                adder_operand_b = -$signed(amo_operand_b_q);
                amo_result = adder_sum[32] ? amo_operand_a : amo_operand_b_q;
            end
            AMOMaxu: begin
                adder_operand_a = 33'($unsigned(amo_operand_a));
                adder_operand_b = -$unsigned(amo_operand_b_q);
                amo_result = adder_sum[32] ? amo_operand_b_q : amo_operand_a;
            end
            AMOMinu: begin
                adder_operand_a = 33'($unsigned(amo_operand_a));
                adder_operand_b = -$unsigned(amo_operand_b_q);
                amo_result = adder_sum[32] ? amo_operand_a : amo_operand_b_q;
            end
            AMOCAS: begin
                if (DataWidth == 64) begin
                    adder_operand_b = -$signed(amo_operand_b_q);
                    // values are equal -> update
                    if (adder_sum == '0) begin
                        amo_result =  swap_value_q;
                    // values are not euqal -> don't update
                    end else begin
                       amo_result = amo_res;
                    end
                `ifndef TARGET_SYNTHESIS
                end else begin
                    $error("AMOCAS not supported for DataWidth = 32 bit");
                `endif
                end
            end
            default: amo_result = '0;
        endcase
    end
    /* verilator lint_on WIDTH */

    `ifndef VERILATOR
    // pragma translate_off
    initial begin
        assert (DataWidth == 32 || DataWidth == 64)
            else $fatal(1, "Unsupported data width!");
    end
    // pragma translate_on
    `endif
endmodule
