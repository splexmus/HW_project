module cocotb_iverilog_dump();
initial begin
    string dumpfile_path;    if ($value$plusargs("dumpfile_path=%s", dumpfile_path)) begin
        $dumpfile(dumpfile_path);
    end else begin
        $dumpfile("D:\\cu\\hardwareSysLab\\project\\HW_project\\testbench\\sim_build\\debounce.fst");
    end
    $dumpvars(0, debounce);
end
endmodule
