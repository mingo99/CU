///==------------------------------------------------------------------==///
/// testbench of top level conv kernel
///==------------------------------------------------------------------==///

module tb_conv2d_1x1;

    reg clk, rstn, start_conv;

    // configuration signals
    reg cfg_stride;
    reg [`CHN_WIDTH-1:0] cfg_ci, cfg_co;
    reg [`FMS_WIDTH-1:0] cfg_ifm_size;

    // tile offset
    reg [`PC_ROW_WIDTH-1:0] tile_row_offset;
    reg [`PC_COL_WIDTH-1:0] tile_col_offset;
    reg [`TC_ROW_WIDTH-1:0] tc_row_max;
    reg [`TC_COL_WIDTH-1:0] tc_col_max;

    // data input
    reg [`PEA11_IFM_WIDTH-1:0] ifm_group;
    reg [`PEA11_WGT_WIDTH-1:0] wgt_group;

    // output of dut
    wire sum_t sum[`PEA11_COL];
    wire [`PEA11_COL-1:0] sum_valid;
    wire ifm_read, wgt_read, conv_done;

    reg [32:0] ifm_cnt;
    reg [32:0] wgt_cnt;

    /// Store weight and ifm
    reg [7:0] ifm_in[`IFM_LEN];
    reg [7:0] wgt_in[`WGT_LEN];

    integer fp_w[`PEA11_COL];
    sum_q sum_group[`PEA11_COL];

    string ifm_file_name;
    string wgt_file_name;

    event conv_started;
    event conv_ended;

    /// Ifm dispatcher
    initial begin
        ifm_file_name =
            $sformatf("../data/exp/ifm_hex_c%0d_h%0d_w%0d.txt", `CHI, `IFM_SIZE, `IFM_SIZE);
        $readmemh(ifm_file_name, ifm_in);
    end

    /// Wgt dispatcher
    initial begin
        wgt_file_name = $sformatf("../data/exp/weight_hex_co%0d_ci%0d_k1_k1.txt", `CHO, `CHI);
        $readmemh(wgt_file_name, wgt_in);
    end

    always @(*) begin
        if (ifm_read)
            for (int i = 0; i < (`PEA11_COL + `PEA11_ROW - 1); ++i) begin
                ifm_group[i*8+:8] = ifm_in[ifm_cnt+i];
            end
        else ifm_group = 0;
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) ifm_cnt <= 0;
        else if (ifm_cnt == `IFM_LEN && !ifm_read) ifm_cnt <= 0;
        else if (ifm_read) ifm_cnt <= ifm_cnt + (`PEA11_COL + `PEA11_ROW - 1);
        else ifm_cnt <= ifm_cnt;
    end

    always @(*) begin
        if (wgt_read) begin
            wgt_group = wgt_in[wgt_cnt];
        end else begin
            wgt_group = 0;
        end
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) wgt_cnt <= 0;
        else if (wgt_cnt == `WGT_LEN && !wgt_read) wgt_cnt <= 0;
        else if (wgt_read) wgt_cnt <= wgt_cnt + 1;
        else wgt_cnt <= wgt_cnt;
    end

    function static open_out_files();
        string ofm_file_name;
        for (int i = 0; i < `PEA11_COL; ++i) begin
            ofm_file_name = $sformatf("../data/act/ofm_tile_lines_%0d.txt", i);
            fp_w[i] = $fopen(ofm_file_name);
        end
    endfunction

    task automatic get_sum();
        $display("Start to get sum...");
        for (int i = 0; i < `PEA11_COL; ++i) begin
            fork
                automatic int col = i;
                forever begin
                    @(posedge clk iff sum_valid[col]);
                    sum_group[col].push_back(sum[col]);
                end
            join_none
        end
    endtask

    task automatic write_ofm();
        $display("Start to write sum...");
        for (int i = 0; i < `PEA11_COL; ++i) begin
            fork
                automatic int col = i;
                automatic int j = 0;
                forever begin
                    @(posedge clk);
                    if (sum_group[col].size() != 0) begin
                        $fwrite(fp_w[col], "%0d,", sum_group[col].pop_front());
                        j = j + 1;
                        if (j == `TILE_LEN) begin
                            $fwrite(fp_w[col], "\n");
                            j = 0;
                        end
                    end
                end
            join_none
        end
    endtask

    // generate clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    /// reset and other control signal from master side
    initial begin
        rstn            = 1;
        start_conv      = 0;
        cfg_ci          = `CHN_64;
        cfg_co          = `CHN_64;
        cfg_stride      = `STRIDE;
        cfg_ifm_size    = `IFM_SIZE;

        tile_row_offset = `TILE_ROW_OFFSET;
        tile_col_offset = `TILE_COL_OFFSET;

        if (`TILE_ROW_OFFSET == 0) tc_row_max = `TC_ROW_MAX - 1;
        else tc_row_max = `TC_ROW_MAX;

        if (`TILE_COL_OFFSET == 0) tc_col_max = `TC_COL_MAX - 1;
        else tc_col_max = `TC_COL_MAX;

        #10 rstn = 0;
        #10 rstn = 1;

        $display("InChannel num: %0d,  OutChannel num: %0d", `CHI, `CHO);
        $display("IFM size: %0d, OFM size: %0d", `IFM_SIZE, `OFM_SIZE);
        $display("Tile row: %0d, Tile col: %0d", `TILE_ROW_NUM, `TILE_COL_NUM);
        $display(`IFM_LEN, `WGT_LEN);

        #10 @(posedge clk) start_conv <= 1;
        #10 @(posedge clk) start_conv <= 0;

        $display("\n\033[32m[ConvKernel: ] Set the clock period to 10ns\033[0m");
        $display("\033[32m[ConvKernel: ] Start to compute conv\033[0m");

        ->conv_started;
        while (!conv_done) @(posedge clk);

        #1000;
        $display("\033[32m Finish computing \033[0m");
        $finish();
    end

    initial begin
        @conv_started;
        open_out_files();
        fork
            get_sum();
            write_ofm();
        join
    end

    // extract wave information
    initial begin
        $fsdbDumpfile("sim_output_pluson.fsdb");
        $fsdbDumpvars(0);
        $fsdbDumpMDA(0);
    end

    // dut
    conv2d_1x1 #(
        .COL          (`PEA11_COL),
        .WGT_WIDTH    (`PEA11_WGT_WIDTH),
        .IFM_WIDTH    (`PEA11_IFM_WIDTH),
        .OFM_WIDTH    (`OFM_WIDTH),
        .RF_AWIDTH    (`RF_AWIDTH),
        .PE_DWIDTH    (`PE_DWIDTH),
        .TILE_LEN     (`TILE_LEN),
        .CHN_WIDTH    (`CHN_WIDTH),
        .CHN_OFT_WIDTH(`CHN_OFT_WIDTH),
        .FMS_WIDTH    (`FMS_WIDTH),
        .TC_ROW_WIDTH (`TC_ROW_WIDTH),
        .TC_COL_WIDTH (`TC_COL_WIDTH),
        .PC_ROW_WIDTH (`PC_ROW_WIDTH),
        .PC_COL_WIDTH (`PC_COL_WIDTH)
    ) u_conv2d_1x1 (
        .clk            (clk),
        .rstn           (rstn),
        .cfg_ci         (cfg_ci),
        .cfg_co         (cfg_co),
        .cfg_stride     (cfg_stride),
        .cfg_ifm_size   (cfg_ifm_size),
        .start_conv     (start_conv),
        .ifm_group      (ifm_group),
        .wgt_group      (wgt_group),
        .tile_row_offset(tile_row_offset),
        .tile_col_offset(tile_col_offset),
        .tc_row_max     (tc_row_max),
        .tc_col_max     (tc_col_max),
        .ifm_read       (ifm_read),
        .wgt_read       (wgt_read),
        .conv_done      (conv_done),
        .sum_valid      (sum_valid),
        .sum            (sum)
    );

endmodule
