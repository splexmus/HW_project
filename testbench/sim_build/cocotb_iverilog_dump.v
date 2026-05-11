module cocotb_iverilog_dump();
initial begin
    string dumpfile_path;    if ($value$plusargs("dumpfile_path=%s", dumpfile_path)) begin
        $dumpfile(dumpfile_path);
    end else begin
        $dumpfile("D:\\cu\\hardwareSysLab\\project\\HW_project\\testbench\\sim_build\\downscale_32x32.fst");
    end
    $dumpvars(0, downscale_32x32);
end
endmodule
