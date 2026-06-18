class hera_env extends uvm_env;
    `uvm_component_utils(hera_env)

    hera_axi_agent   axi_agent;
    hera_kv_wr_agent kv_wr_agent;
    hera_kv_rd_agent kv_rd_agent;
    hera_evict_agent evict_agent;
    hera_scoreboard  scoreboard;
    hera_coverage    coverage;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axi_agent    = hera_axi_agent::type_id::create("axi_agent",   this);
        kv_wr_agent  = hera_kv_wr_agent::type_id::create("kv_wr_agent", this);
        kv_rd_agent  = hera_kv_rd_agent::type_id::create("kv_rd_agent", this);
        evict_agent  = hera_evict_agent::type_id::create("evict_agent", this);
        scoreboard   = hera_scoreboard::type_id::create("scoreboard",  this);
        coverage     = hera_coverage::type_id::create("coverage",    this);
    endfunction

    function void connect_phase(uvm_phase phase);
        // Scoreboard connections
        axi_agent.ap.connect(scoreboard.axi_export);
        kv_wr_agent.ap.connect(scoreboard.kv_wr_export);
        kv_rd_agent.ap.connect(scoreboard.kv_rd_export);
        evict_agent.ap.connect(scoreboard.evict_export);

        // Coverage connections
        axi_agent.ap.connect(coverage.axi_cov_export);
        kv_wr_agent.ap.connect(coverage.analysis_export); // from uvm_subscriber
        evict_agent.ap.connect(coverage.evict_cov_export);
    endfunction
endclass
