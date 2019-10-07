library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.Interconnect_pkg.all;
entity Mantle is
  generic (
    BUS_ADDR_WIDTH : integer := 64
  );
  port (
    bcd_clk            : in  std_logic;
    bcd_reset          : in  std_logic;
    kcd_clk            : in  std_logic;
    kcd_reset          : in  std_logic;
    mmio_awvalid       : in  std_logic;
    mmio_awready       : out std_logic;
    mmio_awaddr        : in  std_logic_vector(31 downto 0);
    mmio_wvalid        : in  std_logic;
    mmio_wready        : out std_logic;
    mmio_wdata         : in  std_logic_vector(31 downto 0);
    mmio_wstrb         : in  std_logic_vector(3 downto 0);
    mmio_bvalid        : out std_logic;
    mmio_bready        : in  std_logic;
    mmio_bresp         : out std_logic_vector(1 downto 0);
    mmio_arvalid       : in  std_logic;
    mmio_arready       : out std_logic;
    mmio_araddr        : in  std_logic_vector(31 downto 0);
    mmio_rvalid        : out std_logic;
    mmio_rready        : in  std_logic;
    mmio_rdata         : out std_logic_vector(31 downto 0);
    mmio_rresp         : out std_logic_vector(1 downto 0);
    rd_mst_rreq_valid  : out std_logic;
    rd_mst_rreq_ready  : in  std_logic;
    rd_mst_rreq_addr   : out std_logic_vector(63 downto 0);
    rd_mst_rreq_len    : out std_logic_vector(7 downto 0);
    rd_mst_rdat_valid  : in  std_logic;
    rd_mst_rdat_ready  : out std_logic;
    rd_mst_rdat_data   : in  std_logic_vector(63 downto 0);
    rd_mst_rdat_last   : in  std_logic;
    wr_mst_wreq_valid  : out std_logic;
    wr_mst_wreq_ready  : in  std_logic;
    wr_mst_wreq_addr   : out std_logic_vector(63 downto 0);
    wr_mst_wreq_len    : out std_logic_vector(7 downto 0);
    wr_mst_wdat_valid  : out std_logic;
    wr_mst_wdat_ready  : in  std_logic;
    wr_mst_wdat_data   : out std_logic_vector(63 downto 0);
    wr_mst_wdat_strobe : out std_logic_vector(7 downto 0);
    wr_mst_wdat_last   : out std_logic;
    write_busy         : in  std_logic := '0'
  );
end entity;
architecture Implementation of Mantle is
  component Pages is
    generic (
      BUS_ADDR_WIDTH : integer := 64
    );
    port (
      bcd_clk                    : in  std_logic;
      bcd_reset                  : in  std_logic;
      kcd_clk                    : in  std_logic;
      kcd_reset                  : in  std_logic;
      Pages_title_valid          : out std_logic;
      Pages_title_ready          : in  std_logic;
      Pages_title_dvalid         : out std_logic;
      Pages_title_last           : out std_logic;
      Pages_title_length         : out std_logic_vector(31 downto 0);
      Pages_title_count          : out std_logic_vector(0 downto 0);
      Pages_title_chars_valid    : out std_logic;
      Pages_title_chars_ready    : in  std_logic;
      Pages_title_chars_dvalid   : out std_logic;
      Pages_title_chars_last     : out std_logic;
      Pages_title_chars_data     : out std_logic_vector(7 downto 0);
      Pages_title_chars_count    : out std_logic_vector(0 downto 0);
      Pages_title_cmd_valid      : in  std_logic;
      Pages_title_cmd_ready      : out std_logic;
      Pages_title_cmd_firstIdx   : in  std_logic_vector(31 downto 0);
      Pages_title_cmd_lastidx    : in  std_logic_vector(31 downto 0);
      Pages_title_cmd_ctrl       : in  std_logic_vector(2*bus_addr_width-1 downto 0);
      Pages_title_cmd_tag        : in  std_logic_vector(0 downto 0);
      Pages_title_unl_valid      : out std_logic;
      Pages_title_unl_ready      : in  std_logic;
      Pages_title_unl_tag        : out std_logic_vector(0 downto 0);
      Pages_title_bus_rreq_valid : out std_logic;
      Pages_title_bus_rreq_ready : in  std_logic;
      Pages_title_bus_rreq_addr  : out std_logic_vector(63 downto 0);
      Pages_title_bus_rreq_len   : out std_logic_vector(7 downto 0);
      Pages_title_bus_rdat_valid : in  std_logic;
      Pages_title_bus_rdat_ready : out std_logic;
      Pages_title_bus_rdat_data  : in  std_logic_vector(63 downto 0);
      Pages_title_bus_rdat_last  : in  std_logic;
      Pages_text_valid           : out std_logic;
      Pages_text_ready           : in  std_logic;
      Pages_text_dvalid          : out std_logic;
      Pages_text_last            : out std_logic;
      Pages_text_length          : out std_logic_vector(31 downto 0);
      Pages_text_count           : out std_logic_vector(0 downto 0);
      Pages_text_bytes_valid     : out std_logic;
      Pages_text_bytes_ready     : in  std_logic;
      Pages_text_bytes_dvalid    : out std_logic;
      Pages_text_bytes_last      : out std_logic;
      Pages_text_bytes_data      : out std_logic_vector(63 downto 0);
      Pages_text_bytes_count     : out std_logic_vector(3 downto 0);
      Pages_text_cmd_valid       : in  std_logic;
      Pages_text_cmd_ready       : out std_logic;
      Pages_text_cmd_firstIdx    : in  std_logic_vector(31 downto 0);
      Pages_text_cmd_lastidx     : in  std_logic_vector(31 downto 0);
      Pages_text_cmd_ctrl        : in  std_logic_vector(2*bus_addr_width-1 downto 0);
      Pages_text_cmd_tag         : in  std_logic_vector(0 downto 0);
      Pages_text_unl_valid       : out std_logic;
      Pages_text_unl_ready       : in  std_logic;
      Pages_text_unl_tag         : out std_logic_vector(0 downto 0);
      Pages_text_bus_rreq_valid  : out std_logic;
      Pages_text_bus_rreq_ready  : in  std_logic;
      Pages_text_bus_rreq_addr   : out std_logic_vector(63 downto 0);
      Pages_text_bus_rreq_len    : out std_logic_vector(7 downto 0);
      Pages_text_bus_rdat_valid  : in  std_logic;
      Pages_text_bus_rdat_ready  : out std_logic;
      Pages_text_bus_rdat_data   : in  std_logic_vector(63 downto 0);
      Pages_text_bus_rdat_last   : in  std_logic
    );
  end component;
  component Result is
    generic (
      BUS_ADDR_WIDTH : integer := 64
    );
    port (
      bcd_clk                      : in  std_logic;
      bcd_reset                    : in  std_logic;
      kcd_clk                      : in  std_logic;
      kcd_reset                    : in  std_logic;
      Result_title_valid           : in  std_logic;
      Result_title_ready           : out std_logic;
      Result_title_dvalid          : in  std_logic;
      Result_title_last            : in  std_logic;
      Result_title_length          : in  std_logic_vector(31 downto 0);
      Result_title_count           : in  std_logic_vector(0 downto 0);
      Result_title_chars_valid     : in  std_logic;
      Result_title_chars_ready     : out std_logic;
      Result_title_chars_dvalid    : in  std_logic;
      Result_title_chars_last      : in  std_logic;
      Result_title_chars_data      : in  std_logic_vector(7 downto 0);
      Result_title_chars_count     : in  std_logic_vector(0 downto 0);
      Result_title_cmd_valid       : in  std_logic;
      Result_title_cmd_ready       : out std_logic;
      Result_title_cmd_firstIdx    : in  std_logic_vector(31 downto 0);
      Result_title_cmd_lastidx     : in  std_logic_vector(31 downto 0);
      Result_title_cmd_ctrl        : in  std_logic_vector(2*bus_addr_width-1 downto 0);
      Result_title_cmd_tag         : in  std_logic_vector(0 downto 0);
      Result_title_unl_valid       : out std_logic;
      Result_title_unl_ready       : in  std_logic;
      Result_title_unl_tag         : out std_logic_vector(0 downto 0);
      Result_title_bus_wreq_valid  : out std_logic;
      Result_title_bus_wreq_ready  : in  std_logic;
      Result_title_bus_wreq_addr   : out std_logic_vector(63 downto 0);
      Result_title_bus_wreq_len    : out std_logic_vector(7 downto 0);
      Result_title_bus_wdat_valid  : out std_logic;
      Result_title_bus_wdat_ready  : in  std_logic;
      Result_title_bus_wdat_data   : out std_logic_vector(63 downto 0);
      Result_title_bus_wdat_strobe : out std_logic_vector(7 downto 0);
      Result_title_bus_wdat_last   : out std_logic;
      Result_count_valid           : in  std_logic;
      Result_count_ready           : out std_logic;
      Result_count_dvalid          : in  std_logic;
      Result_count_last            : in  std_logic;
      Result_count                 : in  std_logic_vector(31 downto 0);
      Result_count_cmd_valid       : in  std_logic;
      Result_count_cmd_ready       : out std_logic;
      Result_count_cmd_firstIdx    : in  std_logic_vector(31 downto 0);
      Result_count_cmd_lastidx     : in  std_logic_vector(31 downto 0);
      Result_count_cmd_ctrl        : in  std_logic_vector(bus_addr_width-1 downto 0);
      Result_count_cmd_tag         : in  std_logic_vector(0 downto 0);
      Result_count_unl_valid       : out std_logic;
      Result_count_unl_ready       : in  std_logic;
      Result_count_unl_tag         : out std_logic_vector(0 downto 0);
      Result_count_bus_wreq_valid  : out std_logic;
      Result_count_bus_wreq_ready  : in  std_logic;
      Result_count_bus_wreq_addr   : out std_logic_vector(63 downto 0);
      Result_count_bus_wreq_len    : out std_logic_vector(7 downto 0);
      Result_count_bus_wdat_valid  : out std_logic;
      Result_count_bus_wdat_ready  : in  std_logic;
      Result_count_bus_wdat_data   : out std_logic_vector(63 downto 0);
      Result_count_bus_wdat_strobe : out std_logic_vector(7 downto 0);
      Result_count_bus_wdat_last   : out std_logic
    );
  end component;
  component Stats is
    generic (
      BUS_ADDR_WIDTH : integer := 64
    );
    port (
      bcd_clk                     : in  std_logic;
      bcd_reset                   : in  std_logic;
      kcd_clk                     : in  std_logic;
      kcd_reset                   : in  std_logic;
      Stats_stats_valid           : in  std_logic;
      Stats_stats_ready           : out std_logic;
      Stats_stats_dvalid          : in  std_logic;
      Stats_stats_last            : in  std_logic;
      Stats_stats                 : in  std_logic_vector(63 downto 0);
      Stats_stats_cmd_valid       : in  std_logic;
      Stats_stats_cmd_ready       : out std_logic;
      Stats_stats_cmd_firstIdx    : in  std_logic_vector(31 downto 0);
      Stats_stats_cmd_lastidx     : in  std_logic_vector(31 downto 0);
      Stats_stats_cmd_ctrl        : in  std_logic_vector(bus_addr_width-1 downto 0);
      Stats_stats_cmd_tag         : in  std_logic_vector(0 downto 0);
      Stats_stats_unl_valid       : out std_logic;
      Stats_stats_unl_ready       : in  std_logic;
      Stats_stats_unl_tag         : out std_logic_vector(0 downto 0);
      Stats_stats_bus_wreq_valid  : out std_logic;
      Stats_stats_bus_wreq_ready  : in  std_logic;
      Stats_stats_bus_wreq_addr   : out std_logic_vector(63 downto 0);
      Stats_stats_bus_wreq_len    : out std_logic_vector(7 downto 0);
      Stats_stats_bus_wdat_valid  : out std_logic;
      Stats_stats_bus_wdat_ready  : in  std_logic;
      Stats_stats_bus_wdat_data   : out std_logic_vector(63 downto 0);
      Stats_stats_bus_wdat_strobe : out std_logic_vector(7 downto 0);
      Stats_stats_bus_wdat_last   : out std_logic
    );
  end component;
  component word_match is
    generic (
      BUS_ADDR_WIDTH : integer := 64
    );
    port (
      kcd_clk                   : in  std_logic;
      kcd_reset                 : in  std_logic;
      mmio_awvalid              : in  std_logic;
      mmio_awready              : out std_logic;
      mmio_awaddr               : in  std_logic_vector(31 downto 0);
      mmio_wvalid               : in  std_logic;
      mmio_wready               : out std_logic;
      mmio_wdata                : in  std_logic_vector(31 downto 0);
      mmio_wstrb                : in  std_logic_vector(3 downto 0);
      mmio_bvalid               : out std_logic;
      mmio_bready               : in  std_logic;
      mmio_bresp                : out std_logic_vector(1 downto 0);
      mmio_arvalid              : in  std_logic;
      mmio_arready              : out std_logic;
      mmio_araddr               : in  std_logic_vector(31 downto 0);
      mmio_rvalid               : out std_logic;
      mmio_rready               : in  std_logic;
      mmio_rdata                : out std_logic_vector(31 downto 0);
      mmio_rresp                : out std_logic_vector(1 downto 0);
      Pages_title_valid         : in  std_logic;
      Pages_title_ready         : out std_logic;
      Pages_title_dvalid        : in  std_logic;
      Pages_title_last          : in  std_logic;
      Pages_title_length        : in  std_logic_vector(31 downto 0);
      Pages_title_count         : in  std_logic_vector(0 downto 0);
      Pages_title_chars_valid   : in  std_logic;
      Pages_title_chars_ready   : out std_logic;
      Pages_title_chars_dvalid  : in  std_logic;
      Pages_title_chars_last    : in  std_logic;
      Pages_title_chars_data    : in  std_logic_vector(7 downto 0);
      Pages_title_chars_count   : in  std_logic_vector(0 downto 0);
      Pages_title_cmd_valid     : out std_logic;
      Pages_title_cmd_ready     : in  std_logic;
      Pages_title_cmd_firstIdx  : out std_logic_vector(31 downto 0);
      Pages_title_cmd_lastidx   : out std_logic_vector(31 downto 0);
      Pages_title_cmd_ctrl      : out std_logic_vector(2*bus_addr_width-1 downto 0);
      Pages_title_cmd_tag       : out std_logic_vector(0 downto 0);
      Pages_title_unl_valid     : in  std_logic;
      Pages_title_unl_ready     : out std_logic;
      Pages_title_unl_tag       : in  std_logic_vector(0 downto 0);
      Pages_text_valid          : in  std_logic;
      Pages_text_ready          : out std_logic;
      Pages_text_dvalid         : in  std_logic;
      Pages_text_last           : in  std_logic;
      Pages_text_length         : in  std_logic_vector(31 downto 0);
      Pages_text_count          : in  std_logic_vector(0 downto 0);
      Pages_text_bytes_valid    : in  std_logic;
      Pages_text_bytes_ready    : out std_logic;
      Pages_text_bytes_dvalid   : in  std_logic;
      Pages_text_bytes_last     : in  std_logic;
      Pages_text_bytes_data     : in  std_logic_vector(63 downto 0);
      Pages_text_bytes_count    : in  std_logic_vector(3 downto 0);
      Pages_text_cmd_valid      : out std_logic;
      Pages_text_cmd_ready      : in  std_logic;
      Pages_text_cmd_firstIdx   : out std_logic_vector(31 downto 0);
      Pages_text_cmd_lastidx    : out std_logic_vector(31 downto 0);
      Pages_text_cmd_ctrl       : out std_logic_vector(2*bus_addr_width-1 downto 0);
      Pages_text_cmd_tag        : out std_logic_vector(0 downto 0);
      Pages_text_unl_valid      : in  std_logic;
      Pages_text_unl_ready      : out std_logic;
      Pages_text_unl_tag        : in  std_logic_vector(0 downto 0);
      Result_title_valid        : out std_logic;
      Result_title_ready        : in  std_logic;
      Result_title_dvalid       : out std_logic;
      Result_title_last         : out std_logic;
      Result_title_length       : out std_logic_vector(31 downto 0);
      Result_title_count        : out std_logic_vector(0 downto 0);
      Result_title_chars_valid  : out std_logic;
      Result_title_chars_ready  : in  std_logic;
      Result_title_chars_dvalid : out std_logic;
      Result_title_chars_last   : out std_logic;
      Result_title_chars_data   : out std_logic_vector(7 downto 0);
      Result_title_chars_count  : out std_logic_vector(0 downto 0);
      Result_title_cmd_valid    : out std_logic;
      Result_title_cmd_ready    : in  std_logic;
      Result_title_cmd_firstIdx : out std_logic_vector(31 downto 0);
      Result_title_cmd_lastidx  : out std_logic_vector(31 downto 0);
      Result_title_cmd_ctrl     : out std_logic_vector(2*bus_addr_width-1 downto 0);
      Result_title_cmd_tag      : out std_logic_vector(0 downto 0);
      Result_title_unl_valid    : in  std_logic;
      Result_title_unl_ready    : out std_logic;
      Result_title_unl_tag      : in  std_logic_vector(0 downto 0);
      Result_count_valid        : out std_logic;
      Result_count_ready        : in  std_logic;
      Result_count_dvalid       : out std_logic;
      Result_count_last         : out std_logic;
      Result_count              : out std_logic_vector(31 downto 0);
      Result_count_cmd_valid    : out std_logic;
      Result_count_cmd_ready    : in  std_logic;
      Result_count_cmd_firstIdx : out std_logic_vector(31 downto 0);
      Result_count_cmd_lastidx  : out std_logic_vector(31 downto 0);
      Result_count_cmd_ctrl     : out std_logic_vector(bus_addr_width-1 downto 0);
      Result_count_cmd_tag      : out std_logic_vector(0 downto 0);
      Result_count_unl_valid    : in  std_logic;
      Result_count_unl_ready    : out std_logic;
      Result_count_unl_tag      : in  std_logic_vector(0 downto 0);
      Stats_stats_valid         : out std_logic;
      Stats_stats_ready         : in  std_logic;
      Stats_stats_dvalid        : out std_logic;
      Stats_stats_last          : out std_logic;
      Stats_stats               : out std_logic_vector(63 downto 0);
      Stats_stats_cmd_valid     : out std_logic;
      Stats_stats_cmd_ready     : in  std_logic;
      Stats_stats_cmd_firstIdx  : out std_logic_vector(31 downto 0);
      Stats_stats_cmd_lastidx   : out std_logic_vector(31 downto 0);
      Stats_stats_cmd_ctrl      : out std_logic_vector(bus_addr_width-1 downto 0);
      Stats_stats_cmd_tag       : out std_logic_vector(0 downto 0);
      Stats_stats_unl_valid     : in  std_logic;
      Stats_stats_unl_ready     : out std_logic;
      Stats_stats_unl_tag       : in  std_logic_vector(0 downto 0);
      write_busy                : in  std_logic
    );
  end component;
  signal Pages_inst_Pages_title_valid        : std_logic;
  signal Pages_inst_Pages_title_ready        : std_logic;
  signal Pages_inst_Pages_title_dvalid       : std_logic;
  signal Pages_inst_Pages_title_last         : std_logic;
  signal Pages_inst_Pages_title_length       : std_logic_vector(31 downto 0);
  signal Pages_inst_Pages_title_count        : std_logic_vector(0 downto 0);
  signal Pages_inst_Pages_title_chars_valid  : std_logic;
  signal Pages_inst_Pages_title_chars_ready  : std_logic;
  signal Pages_inst_Pages_title_chars_dvalid : std_logic;
  signal Pages_inst_Pages_title_chars_last   : std_logic;
  signal Pages_inst_Pages_title_chars_data   : std_logic_vector(7 downto 0);
  signal Pages_inst_Pages_title_chars_count  : std_logic_vector(0 downto 0);
  signal Pages_inst_Pages_title_unl_valid : std_logic;
  signal Pages_inst_Pages_title_unl_ready : std_logic;
  signal Pages_inst_Pages_title_unl_tag   : std_logic_vector(0 downto 0);
  signal Pages_inst_Pages_title_bus_rreq_valid : std_logic;
  signal Pages_inst_Pages_title_bus_rreq_ready : std_logic;
  signal Pages_inst_Pages_title_bus_rreq_addr  : std_logic_vector(63 downto 0);
  signal Pages_inst_Pages_title_bus_rreq_len   : std_logic_vector(7 downto 0);
  signal Pages_inst_Pages_title_bus_rdat_valid : std_logic;
  signal Pages_inst_Pages_title_bus_rdat_ready : std_logic;
  signal Pages_inst_Pages_title_bus_rdat_data  : std_logic_vector(63 downto 0);
  signal Pages_inst_Pages_title_bus_rdat_last  : std_logic;
  signal Pages_inst_Pages_text_valid        : std_logic;
  signal Pages_inst_Pages_text_ready        : std_logic;
  signal Pages_inst_Pages_text_dvalid       : std_logic;
  signal Pages_inst_Pages_text_last         : std_logic;
  signal Pages_inst_Pages_text_length       : std_logic_vector(31 downto 0);
  signal Pages_inst_Pages_text_count        : std_logic_vector(0 downto 0);
  signal Pages_inst_Pages_text_bytes_valid  : std_logic;
  signal Pages_inst_Pages_text_bytes_ready  : std_logic;
  signal Pages_inst_Pages_text_bytes_dvalid : std_logic;
  signal Pages_inst_Pages_text_bytes_last   : std_logic;
  signal Pages_inst_Pages_text_bytes_data   : std_logic_vector(63 downto 0);
  signal Pages_inst_Pages_text_bytes_count  : std_logic_vector(3 downto 0);
  signal Pages_inst_Pages_text_unl_valid : std_logic;
  signal Pages_inst_Pages_text_unl_ready : std_logic;
  signal Pages_inst_Pages_text_unl_tag   : std_logic_vector(0 downto 0);
  signal Pages_inst_Pages_text_bus_rreq_valid : std_logic;
  signal Pages_inst_Pages_text_bus_rreq_ready : std_logic;
  signal Pages_inst_Pages_text_bus_rreq_addr  : std_logic_vector(63 downto 0);
  signal Pages_inst_Pages_text_bus_rreq_len   : std_logic_vector(7 downto 0);
  signal Pages_inst_Pages_text_bus_rdat_valid : std_logic;
  signal Pages_inst_Pages_text_bus_rdat_ready : std_logic;
  signal Pages_inst_Pages_text_bus_rdat_data  : std_logic_vector(63 downto 0);
  signal Pages_inst_Pages_text_bus_rdat_last  : std_logic;
  signal Result_inst_Result_title_unl_valid : std_logic;
  signal Result_inst_Result_title_unl_ready : std_logic;
  signal Result_inst_Result_title_unl_tag   : std_logic_vector(0 downto 0);
  signal Result_inst_Result_title_bus_wreq_valid  : std_logic;
  signal Result_inst_Result_title_bus_wreq_ready  : std_logic;
  signal Result_inst_Result_title_bus_wreq_addr   : std_logic_vector(63 downto 0);
  signal Result_inst_Result_title_bus_wreq_len    : std_logic_vector(7 downto 0);
  signal Result_inst_Result_title_bus_wdat_valid  : std_logic;
  signal Result_inst_Result_title_bus_wdat_ready  : std_logic;
  signal Result_inst_Result_title_bus_wdat_data   : std_logic_vector(63 downto 0);
  signal Result_inst_Result_title_bus_wdat_strobe : std_logic_vector(7 downto 0);
  signal Result_inst_Result_title_bus_wdat_last   : std_logic;
  signal Result_inst_Result_count_unl_valid : std_logic;
  signal Result_inst_Result_count_unl_ready : std_logic;
  signal Result_inst_Result_count_unl_tag   : std_logic_vector(0 downto 0);
  signal Result_inst_Result_count_bus_wreq_valid  : std_logic;
  signal Result_inst_Result_count_bus_wreq_ready  : std_logic;
  signal Result_inst_Result_count_bus_wreq_addr   : std_logic_vector(63 downto 0);
  signal Result_inst_Result_count_bus_wreq_len    : std_logic_vector(7 downto 0);
  signal Result_inst_Result_count_bus_wdat_valid  : std_logic;
  signal Result_inst_Result_count_bus_wdat_ready  : std_logic;
  signal Result_inst_Result_count_bus_wdat_data   : std_logic_vector(63 downto 0);
  signal Result_inst_Result_count_bus_wdat_strobe : std_logic_vector(7 downto 0);
  signal Result_inst_Result_count_bus_wdat_last   : std_logic;
  signal Stats_inst_Stats_stats_unl_valid : std_logic;
  signal Stats_inst_Stats_stats_unl_ready : std_logic;
  signal Stats_inst_Stats_stats_unl_tag   : std_logic_vector(0 downto 0);
  signal Stats_inst_Stats_stats_bus_wreq_valid  : std_logic;
  signal Stats_inst_Stats_stats_bus_wreq_ready  : std_logic;
  signal Stats_inst_Stats_stats_bus_wreq_addr   : std_logic_vector(63 downto 0);
  signal Stats_inst_Stats_stats_bus_wreq_len    : std_logic_vector(7 downto 0);
  signal Stats_inst_Stats_stats_bus_wdat_valid  : std_logic;
  signal Stats_inst_Stats_stats_bus_wdat_ready  : std_logic;
  signal Stats_inst_Stats_stats_bus_wdat_data   : std_logic_vector(63 downto 0);
  signal Stats_inst_Stats_stats_bus_wdat_strobe : std_logic_vector(7 downto 0);
  signal Stats_inst_Stats_stats_bus_wdat_last   : std_logic;
  signal word_match_inst_Pages_title_cmd_valid    : std_logic;
  signal word_match_inst_Pages_title_cmd_ready    : std_logic;
  signal word_match_inst_Pages_title_cmd_firstIdx : std_logic_vector(31 downto 0);
  signal word_match_inst_Pages_title_cmd_lastidx  : std_logic_vector(31 downto 0);
  signal word_match_inst_Pages_title_cmd_ctrl     : std_logic_vector(2*bus_addr_width-1 downto 0);
  signal word_match_inst_Pages_title_cmd_tag      : std_logic_vector(0 downto 0);
  signal word_match_inst_Pages_text_cmd_valid    : std_logic;
  signal word_match_inst_Pages_text_cmd_ready    : std_logic;
  signal word_match_inst_Pages_text_cmd_firstIdx : std_logic_vector(31 downto 0);
  signal word_match_inst_Pages_text_cmd_lastidx  : std_logic_vector(31 downto 0);
  signal word_match_inst_Pages_text_cmd_ctrl     : std_logic_vector(2*bus_addr_width-1 downto 0);
  signal word_match_inst_Pages_text_cmd_tag      : std_logic_vector(0 downto 0);
  signal word_match_inst_Result_title_valid        : std_logic;
  signal word_match_inst_Result_title_ready        : std_logic;
  signal word_match_inst_Result_title_dvalid       : std_logic;
  signal word_match_inst_Result_title_last         : std_logic;
  signal word_match_inst_Result_title_length       : std_logic_vector(31 downto 0);
  signal word_match_inst_Result_title_count        : std_logic_vector(0 downto 0);
  signal word_match_inst_Result_title_chars_valid  : std_logic;
  signal word_match_inst_Result_title_chars_ready  : std_logic;
  signal word_match_inst_Result_title_chars_dvalid : std_logic;
  signal word_match_inst_Result_title_chars_last   : std_logic;
  signal word_match_inst_Result_title_chars_data   : std_logic_vector(7 downto 0);
  signal word_match_inst_Result_title_chars_count  : std_logic_vector(0 downto 0);
  signal word_match_inst_Result_title_cmd_valid    : std_logic;
  signal word_match_inst_Result_title_cmd_ready    : std_logic;
  signal word_match_inst_Result_title_cmd_firstIdx : std_logic_vector(31 downto 0);
  signal word_match_inst_Result_title_cmd_lastidx  : std_logic_vector(31 downto 0);
  signal word_match_inst_Result_title_cmd_ctrl     : std_logic_vector(2*bus_addr_width-1 downto 0);
  signal word_match_inst_Result_title_cmd_tag      : std_logic_vector(0 downto 0);
  signal word_match_inst_Result_count_valid  : std_logic;
  signal word_match_inst_Result_count_ready  : std_logic;
  signal word_match_inst_Result_count_dvalid : std_logic;
  signal word_match_inst_Result_count_last   : std_logic;
  signal word_match_inst_Result_count        : std_logic_vector(31 downto 0);
  signal word_match_inst_Result_count_cmd_valid    : std_logic;
  signal word_match_inst_Result_count_cmd_ready    : std_logic;
  signal word_match_inst_Result_count_cmd_firstIdx : std_logic_vector(31 downto 0);
  signal word_match_inst_Result_count_cmd_lastidx  : std_logic_vector(31 downto 0);
  signal word_match_inst_Result_count_cmd_ctrl     : std_logic_vector(bus_addr_width-1 downto 0);
  signal word_match_inst_Result_count_cmd_tag      : std_logic_vector(0 downto 0);
  signal word_match_inst_Stats_stats_valid  : std_logic;
  signal word_match_inst_Stats_stats_ready  : std_logic;
  signal word_match_inst_Stats_stats_dvalid : std_logic;
  signal word_match_inst_Stats_stats_last   : std_logic;
  signal word_match_inst_Stats_stats        : std_logic_vector(63 downto 0);
  signal word_match_inst_Stats_stats_cmd_valid    : std_logic;
  signal word_match_inst_Stats_stats_cmd_ready    : std_logic;
  signal word_match_inst_Stats_stats_cmd_firstIdx : std_logic_vector(31 downto 0);
  signal word_match_inst_Stats_stats_cmd_lastidx  : std_logic_vector(31 downto 0);
  signal word_match_inst_Stats_stats_cmd_ctrl     : std_logic_vector(bus_addr_width-1 downto 0);
  signal word_match_inst_Stats_stats_cmd_tag      : std_logic_vector(0 downto 0);
begin
  Pages_inst : Pages
    generic map (
      BUS_ADDR_WIDTH => 64
    )
    port map (
      bcd_clk                    => bcd_clk,
      bcd_reset                  => bcd_reset,
      kcd_clk                    => kcd_clk,
      kcd_reset                  => kcd_reset,
      Pages_title_valid          => Pages_inst_Pages_title_valid,
      Pages_title_ready          => Pages_inst_Pages_title_ready,
      Pages_title_dvalid         => Pages_inst_Pages_title_dvalid,
      Pages_title_last           => Pages_inst_Pages_title_last,
      Pages_title_length         => Pages_inst_Pages_title_length,
      Pages_title_count          => Pages_inst_Pages_title_count,
      Pages_title_chars_valid    => Pages_inst_Pages_title_chars_valid,
      Pages_title_chars_ready    => Pages_inst_Pages_title_chars_ready,
      Pages_title_chars_dvalid   => Pages_inst_Pages_title_chars_dvalid,
      Pages_title_chars_last     => Pages_inst_Pages_title_chars_last,
      Pages_title_chars_data     => Pages_inst_Pages_title_chars_data,
      Pages_title_chars_count    => Pages_inst_Pages_title_chars_count,
      Pages_title_cmd_valid      => word_match_inst_Pages_title_cmd_valid,
      Pages_title_cmd_ready      => word_match_inst_Pages_title_cmd_ready,
      Pages_title_cmd_firstIdx   => word_match_inst_Pages_title_cmd_firstIdx,
      Pages_title_cmd_lastidx    => word_match_inst_Pages_title_cmd_lastidx,
      Pages_title_cmd_ctrl       => word_match_inst_Pages_title_cmd_ctrl,
      Pages_title_cmd_tag        => word_match_inst_Pages_title_cmd_tag,
      Pages_title_unl_valid      => Pages_inst_Pages_title_unl_valid,
      Pages_title_unl_ready      => Pages_inst_Pages_title_unl_ready,
      Pages_title_unl_tag        => Pages_inst_Pages_title_unl_tag,
      Pages_title_bus_rreq_valid => Pages_inst_Pages_title_bus_rreq_valid,
      Pages_title_bus_rreq_ready => Pages_inst_Pages_title_bus_rreq_ready,
      Pages_title_bus_rreq_addr  => Pages_inst_Pages_title_bus_rreq_addr,
      Pages_title_bus_rreq_len   => Pages_inst_Pages_title_bus_rreq_len,
      Pages_title_bus_rdat_valid => Pages_inst_Pages_title_bus_rdat_valid,
      Pages_title_bus_rdat_ready => Pages_inst_Pages_title_bus_rdat_ready,
      Pages_title_bus_rdat_data  => Pages_inst_Pages_title_bus_rdat_data,
      Pages_title_bus_rdat_last  => Pages_inst_Pages_title_bus_rdat_last,
      Pages_text_valid           => Pages_inst_Pages_text_valid,
      Pages_text_ready           => Pages_inst_Pages_text_ready,
      Pages_text_dvalid          => Pages_inst_Pages_text_dvalid,
      Pages_text_last            => Pages_inst_Pages_text_last,
      Pages_text_length          => Pages_inst_Pages_text_length,
      Pages_text_count           => Pages_inst_Pages_text_count,
      Pages_text_bytes_valid     => Pages_inst_Pages_text_bytes_valid,
      Pages_text_bytes_ready     => Pages_inst_Pages_text_bytes_ready,
      Pages_text_bytes_dvalid    => Pages_inst_Pages_text_bytes_dvalid,
      Pages_text_bytes_last      => Pages_inst_Pages_text_bytes_last,
      Pages_text_bytes_data      => Pages_inst_Pages_text_bytes_data,
      Pages_text_bytes_count     => Pages_inst_Pages_text_bytes_count,
      Pages_text_cmd_valid       => word_match_inst_Pages_text_cmd_valid,
      Pages_text_cmd_ready       => word_match_inst_Pages_text_cmd_ready,
      Pages_text_cmd_firstIdx    => word_match_inst_Pages_text_cmd_firstIdx,
      Pages_text_cmd_lastidx     => word_match_inst_Pages_text_cmd_lastidx,
      Pages_text_cmd_ctrl        => word_match_inst_Pages_text_cmd_ctrl,
      Pages_text_cmd_tag         => word_match_inst_Pages_text_cmd_tag,
      Pages_text_unl_valid       => Pages_inst_Pages_text_unl_valid,
      Pages_text_unl_ready       => Pages_inst_Pages_text_unl_ready,
      Pages_text_unl_tag         => Pages_inst_Pages_text_unl_tag,
      Pages_text_bus_rreq_valid  => Pages_inst_Pages_text_bus_rreq_valid,
      Pages_text_bus_rreq_ready  => Pages_inst_Pages_text_bus_rreq_ready,
      Pages_text_bus_rreq_addr   => Pages_inst_Pages_text_bus_rreq_addr,
      Pages_text_bus_rreq_len    => Pages_inst_Pages_text_bus_rreq_len,
      Pages_text_bus_rdat_valid  => Pages_inst_Pages_text_bus_rdat_valid,
      Pages_text_bus_rdat_ready  => Pages_inst_Pages_text_bus_rdat_ready,
      Pages_text_bus_rdat_data   => Pages_inst_Pages_text_bus_rdat_data,
      Pages_text_bus_rdat_last   => Pages_inst_Pages_text_bus_rdat_last
    );
  Result_inst : Result
    generic map (
      BUS_ADDR_WIDTH => 64
    )
    port map (
      bcd_clk                      => bcd_clk,
      bcd_reset                    => bcd_reset,
      kcd_clk                      => kcd_clk,
      kcd_reset                    => kcd_reset,
      Result_title_valid           => word_match_inst_Result_title_valid,
      Result_title_ready           => word_match_inst_Result_title_ready,
      Result_title_dvalid          => word_match_inst_Result_title_dvalid,
      Result_title_last            => word_match_inst_Result_title_last,
      Result_title_length          => word_match_inst_Result_title_length,
      Result_title_count           => word_match_inst_Result_title_count,
      Result_title_chars_valid     => word_match_inst_Result_title_chars_valid,
      Result_title_chars_ready     => word_match_inst_Result_title_chars_ready,
      Result_title_chars_dvalid    => word_match_inst_Result_title_chars_dvalid,
      Result_title_chars_last      => word_match_inst_Result_title_chars_last,
      Result_title_chars_data      => word_match_inst_Result_title_chars_data,
      Result_title_chars_count     => word_match_inst_Result_title_chars_count,
      Result_title_cmd_valid       => word_match_inst_Result_title_cmd_valid,
      Result_title_cmd_ready       => word_match_inst_Result_title_cmd_ready,
      Result_title_cmd_firstIdx    => word_match_inst_Result_title_cmd_firstIdx,
      Result_title_cmd_lastidx     => word_match_inst_Result_title_cmd_lastidx,
      Result_title_cmd_ctrl        => word_match_inst_Result_title_cmd_ctrl,
      Result_title_cmd_tag         => word_match_inst_Result_title_cmd_tag,
      Result_title_unl_valid       => Result_inst_Result_title_unl_valid,
      Result_title_unl_ready       => Result_inst_Result_title_unl_ready,
      Result_title_unl_tag         => Result_inst_Result_title_unl_tag,
      Result_title_bus_wreq_valid  => Result_inst_Result_title_bus_wreq_valid,
      Result_title_bus_wreq_ready  => Result_inst_Result_title_bus_wreq_ready,
      Result_title_bus_wreq_addr   => Result_inst_Result_title_bus_wreq_addr,
      Result_title_bus_wreq_len    => Result_inst_Result_title_bus_wreq_len,
      Result_title_bus_wdat_valid  => Result_inst_Result_title_bus_wdat_valid,
      Result_title_bus_wdat_ready  => Result_inst_Result_title_bus_wdat_ready,
      Result_title_bus_wdat_data   => Result_inst_Result_title_bus_wdat_data,
      Result_title_bus_wdat_strobe => Result_inst_Result_title_bus_wdat_strobe,
      Result_title_bus_wdat_last   => Result_inst_Result_title_bus_wdat_last,
      Result_count_valid           => word_match_inst_Result_count_valid,
      Result_count_ready           => word_match_inst_Result_count_ready,
      Result_count_dvalid          => word_match_inst_Result_count_dvalid,
      Result_count_last            => word_match_inst_Result_count_last,
      Result_count                 => word_match_inst_Result_count,
      Result_count_cmd_valid       => word_match_inst_Result_count_cmd_valid,
      Result_count_cmd_ready       => word_match_inst_Result_count_cmd_ready,
      Result_count_cmd_firstIdx    => word_match_inst_Result_count_cmd_firstIdx,
      Result_count_cmd_lastidx     => word_match_inst_Result_count_cmd_lastidx,
      Result_count_cmd_ctrl        => word_match_inst_Result_count_cmd_ctrl,
      Result_count_cmd_tag         => word_match_inst_Result_count_cmd_tag,
      Result_count_unl_valid       => Result_inst_Result_count_unl_valid,
      Result_count_unl_ready       => Result_inst_Result_count_unl_ready,
      Result_count_unl_tag         => Result_inst_Result_count_unl_tag,
      Result_count_bus_wreq_valid  => Result_inst_Result_count_bus_wreq_valid,
      Result_count_bus_wreq_ready  => Result_inst_Result_count_bus_wreq_ready,
      Result_count_bus_wreq_addr   => Result_inst_Result_count_bus_wreq_addr,
      Result_count_bus_wreq_len    => Result_inst_Result_count_bus_wreq_len,
      Result_count_bus_wdat_valid  => Result_inst_Result_count_bus_wdat_valid,
      Result_count_bus_wdat_ready  => Result_inst_Result_count_bus_wdat_ready,
      Result_count_bus_wdat_data   => Result_inst_Result_count_bus_wdat_data,
      Result_count_bus_wdat_strobe => Result_inst_Result_count_bus_wdat_strobe,
      Result_count_bus_wdat_last   => Result_inst_Result_count_bus_wdat_last
    );
  Stats_inst : Stats
    generic map (
      BUS_ADDR_WIDTH => 64
    )
    port map (
      bcd_clk                     => bcd_clk,
      bcd_reset                   => bcd_reset,
      kcd_clk                     => kcd_clk,
      kcd_reset                   => kcd_reset,
      Stats_stats_valid           => word_match_inst_Stats_stats_valid,
      Stats_stats_ready           => word_match_inst_Stats_stats_ready,
      Stats_stats_dvalid          => word_match_inst_Stats_stats_dvalid,
      Stats_stats_last            => word_match_inst_Stats_stats_last,
      Stats_stats                 => word_match_inst_Stats_stats,
      Stats_stats_cmd_valid       => word_match_inst_Stats_stats_cmd_valid,
      Stats_stats_cmd_ready       => word_match_inst_Stats_stats_cmd_ready,
      Stats_stats_cmd_firstIdx    => word_match_inst_Stats_stats_cmd_firstIdx,
      Stats_stats_cmd_lastidx     => word_match_inst_Stats_stats_cmd_lastidx,
      Stats_stats_cmd_ctrl        => word_match_inst_Stats_stats_cmd_ctrl,
      Stats_stats_cmd_tag         => word_match_inst_Stats_stats_cmd_tag,
      Stats_stats_unl_valid       => Stats_inst_Stats_stats_unl_valid,
      Stats_stats_unl_ready       => Stats_inst_Stats_stats_unl_ready,
      Stats_stats_unl_tag         => Stats_inst_Stats_stats_unl_tag,
      Stats_stats_bus_wreq_valid  => Stats_inst_Stats_stats_bus_wreq_valid,
      Stats_stats_bus_wreq_ready  => Stats_inst_Stats_stats_bus_wreq_ready,
      Stats_stats_bus_wreq_addr   => Stats_inst_Stats_stats_bus_wreq_addr,
      Stats_stats_bus_wreq_len    => Stats_inst_Stats_stats_bus_wreq_len,
      Stats_stats_bus_wdat_valid  => Stats_inst_Stats_stats_bus_wdat_valid,
      Stats_stats_bus_wdat_ready  => Stats_inst_Stats_stats_bus_wdat_ready,
      Stats_stats_bus_wdat_data   => Stats_inst_Stats_stats_bus_wdat_data,
      Stats_stats_bus_wdat_strobe => Stats_inst_Stats_stats_bus_wdat_strobe,
      Stats_stats_bus_wdat_last   => Stats_inst_Stats_stats_bus_wdat_last
    );
  word_match_inst : word_match
    generic map (
      BUS_ADDR_WIDTH => 64
    )
    port map (
      kcd_clk                   => kcd_clk,
      kcd_reset                 => kcd_reset,
      mmio_awvalid              => mmio_awvalid,
      mmio_awready              => mmio_awready,
      mmio_awaddr               => mmio_awaddr,
      mmio_wvalid               => mmio_wvalid,
      mmio_wready               => mmio_wready,
      mmio_wdata                => mmio_wdata,
      mmio_wstrb                => mmio_wstrb,
      mmio_bvalid               => mmio_bvalid,
      mmio_bready               => mmio_bready,
      mmio_bresp                => mmio_bresp,
      mmio_arvalid              => mmio_arvalid,
      mmio_arready              => mmio_arready,
      mmio_araddr               => mmio_araddr,
      mmio_rvalid               => mmio_rvalid,
      mmio_rready               => mmio_rready,
      mmio_rdata                => mmio_rdata,
      mmio_rresp                => mmio_rresp,
      Pages_title_valid         => Pages_inst_Pages_title_valid,
      Pages_title_ready         => Pages_inst_Pages_title_ready,
      Pages_title_dvalid        => Pages_inst_Pages_title_dvalid,
      Pages_title_last          => Pages_inst_Pages_title_last,
      Pages_title_length        => Pages_inst_Pages_title_length,
      Pages_title_count         => Pages_inst_Pages_title_count,
      Pages_title_chars_valid   => Pages_inst_Pages_title_chars_valid,
      Pages_title_chars_ready   => Pages_inst_Pages_title_chars_ready,
      Pages_title_chars_dvalid  => Pages_inst_Pages_title_chars_dvalid,
      Pages_title_chars_last    => Pages_inst_Pages_title_chars_last,
      Pages_title_chars_data    => Pages_inst_Pages_title_chars_data,
      Pages_title_chars_count   => Pages_inst_Pages_title_chars_count,
      Pages_title_cmd_valid     => word_match_inst_Pages_title_cmd_valid,
      Pages_title_cmd_ready     => word_match_inst_Pages_title_cmd_ready,
      Pages_title_cmd_firstIdx  => word_match_inst_Pages_title_cmd_firstIdx,
      Pages_title_cmd_lastidx   => word_match_inst_Pages_title_cmd_lastidx,
      Pages_title_cmd_ctrl      => word_match_inst_Pages_title_cmd_ctrl,
      Pages_title_cmd_tag       => word_match_inst_Pages_title_cmd_tag,
      Pages_title_unl_valid     => Pages_inst_Pages_title_unl_valid,
      Pages_title_unl_ready     => Pages_inst_Pages_title_unl_ready,
      Pages_title_unl_tag       => Pages_inst_Pages_title_unl_tag,
      Pages_text_valid          => Pages_inst_Pages_text_valid,
      Pages_text_ready          => Pages_inst_Pages_text_ready,
      Pages_text_dvalid         => Pages_inst_Pages_text_dvalid,
      Pages_text_last           => Pages_inst_Pages_text_last,
      Pages_text_length         => Pages_inst_Pages_text_length,
      Pages_text_count          => Pages_inst_Pages_text_count,
      Pages_text_bytes_valid    => Pages_inst_Pages_text_bytes_valid,
      Pages_text_bytes_ready    => Pages_inst_Pages_text_bytes_ready,
      Pages_text_bytes_dvalid   => Pages_inst_Pages_text_bytes_dvalid,
      Pages_text_bytes_last     => Pages_inst_Pages_text_bytes_last,
      Pages_text_bytes_data     => Pages_inst_Pages_text_bytes_data,
      Pages_text_bytes_count    => Pages_inst_Pages_text_bytes_count,
      Pages_text_cmd_valid      => word_match_inst_Pages_text_cmd_valid,
      Pages_text_cmd_ready      => word_match_inst_Pages_text_cmd_ready,
      Pages_text_cmd_firstIdx   => word_match_inst_Pages_text_cmd_firstIdx,
      Pages_text_cmd_lastidx    => word_match_inst_Pages_text_cmd_lastidx,
      Pages_text_cmd_ctrl       => word_match_inst_Pages_text_cmd_ctrl,
      Pages_text_cmd_tag        => word_match_inst_Pages_text_cmd_tag,
      Pages_text_unl_valid      => Pages_inst_Pages_text_unl_valid,
      Pages_text_unl_ready      => Pages_inst_Pages_text_unl_ready,
      Pages_text_unl_tag        => Pages_inst_Pages_text_unl_tag,
      Result_title_valid        => word_match_inst_Result_title_valid,
      Result_title_ready        => word_match_inst_Result_title_ready,
      Result_title_dvalid       => word_match_inst_Result_title_dvalid,
      Result_title_last         => word_match_inst_Result_title_last,
      Result_title_length       => word_match_inst_Result_title_length,
      Result_title_count        => word_match_inst_Result_title_count,
      Result_title_chars_valid  => word_match_inst_Result_title_chars_valid,
      Result_title_chars_ready  => word_match_inst_Result_title_chars_ready,
      Result_title_chars_dvalid => word_match_inst_Result_title_chars_dvalid,
      Result_title_chars_last   => word_match_inst_Result_title_chars_last,
      Result_title_chars_data   => word_match_inst_Result_title_chars_data,
      Result_title_chars_count  => word_match_inst_Result_title_chars_count,
      Result_title_cmd_valid    => word_match_inst_Result_title_cmd_valid,
      Result_title_cmd_ready    => word_match_inst_Result_title_cmd_ready,
      Result_title_cmd_firstIdx => word_match_inst_Result_title_cmd_firstIdx,
      Result_title_cmd_lastidx  => word_match_inst_Result_title_cmd_lastidx,
      Result_title_cmd_ctrl     => word_match_inst_Result_title_cmd_ctrl,
      Result_title_cmd_tag      => word_match_inst_Result_title_cmd_tag,
      Result_title_unl_valid    => Result_inst_Result_title_unl_valid,
      Result_title_unl_ready    => Result_inst_Result_title_unl_ready,
      Result_title_unl_tag      => Result_inst_Result_title_unl_tag,
      Result_count_valid        => word_match_inst_Result_count_valid,
      Result_count_ready        => word_match_inst_Result_count_ready,
      Result_count_dvalid       => word_match_inst_Result_count_dvalid,
      Result_count_last         => word_match_inst_Result_count_last,
      Result_count              => word_match_inst_Result_count,
      Result_count_cmd_valid    => word_match_inst_Result_count_cmd_valid,
      Result_count_cmd_ready    => word_match_inst_Result_count_cmd_ready,
      Result_count_cmd_firstIdx => word_match_inst_Result_count_cmd_firstIdx,
      Result_count_cmd_lastidx  => word_match_inst_Result_count_cmd_lastidx,
      Result_count_cmd_ctrl     => word_match_inst_Result_count_cmd_ctrl,
      Result_count_cmd_tag      => word_match_inst_Result_count_cmd_tag,
      Result_count_unl_valid    => Result_inst_Result_count_unl_valid,
      Result_count_unl_ready    => Result_inst_Result_count_unl_ready,
      Result_count_unl_tag      => Result_inst_Result_count_unl_tag,
      Stats_stats_valid         => word_match_inst_Stats_stats_valid,
      Stats_stats_ready         => word_match_inst_Stats_stats_ready,
      Stats_stats_dvalid        => word_match_inst_Stats_stats_dvalid,
      Stats_stats_last          => word_match_inst_Stats_stats_last,
      Stats_stats               => word_match_inst_Stats_stats,
      Stats_stats_cmd_valid     => word_match_inst_Stats_stats_cmd_valid,
      Stats_stats_cmd_ready     => word_match_inst_Stats_stats_cmd_ready,
      Stats_stats_cmd_firstIdx  => word_match_inst_Stats_stats_cmd_firstIdx,
      Stats_stats_cmd_lastidx   => word_match_inst_Stats_stats_cmd_lastidx,
      Stats_stats_cmd_ctrl      => word_match_inst_Stats_stats_cmd_ctrl,
      Stats_stats_cmd_tag       => word_match_inst_Stats_stats_cmd_tag,
      Stats_stats_unl_valid     => Stats_inst_Stats_stats_unl_valid,
      Stats_stats_unl_ready     => Stats_inst_Stats_stats_unl_ready,
      Stats_stats_unl_tag       => Stats_inst_Stats_stats_unl_tag,
      write_busy                => write_busy
    );
  BusReadArbiterVec_inst : BusReadArbiterVec
    generic map (
      BUS_ADDR_WIDTH  => 64,
      BUS_LEN_WIDTH   => 8,
      BUS_DATA_WIDTH  => 64,
      ARB_METHOD      => "ROUND-ROBIN",
      MAX_OUTSTANDING => 4,
      RAM_CONFIG      => "",
      SLV_REQ_SLICES  => true,
      MST_REQ_SLICE   => true,
      MST_DAT_SLICE   => true,
      SLV_DAT_SLICES  => true,
      NUM_SLAVE_PORTS => 2
    )
    port map (
      bcd_clk                        => bcd_clk,
      bcd_reset                      => bcd_reset,
      mst_rreq_valid                 => rd_mst_rreq_valid,
      mst_rreq_ready                 => rd_mst_rreq_ready,
      mst_rreq_addr                  => rd_mst_rreq_addr,
      mst_rreq_len                   => rd_mst_rreq_len,
      mst_rdat_valid                 => rd_mst_rdat_valid,
      mst_rdat_ready                 => rd_mst_rdat_ready,
      mst_rdat_data                  => rd_mst_rdat_data,
      mst_rdat_last                  => rd_mst_rdat_last,
      bsv_rreq_valid(0)              => Pages_inst_Pages_title_bus_rreq_valid,
      bsv_rreq_valid(1)              => Pages_inst_Pages_text_bus_rreq_valid,
      bsv_rreq_ready(0)              => Pages_inst_Pages_title_bus_rreq_ready,
      bsv_rreq_ready(1)              => Pages_inst_Pages_text_bus_rreq_ready,
      bsv_rreq_len(7 downto 0)       => Pages_inst_Pages_title_bus_rreq_len,
      bsv_rreq_len(15 downto 8)      => Pages_inst_Pages_text_bus_rreq_len,
      bsv_rreq_addr(63 downto 0)     => Pages_inst_Pages_title_bus_rreq_addr,
      bsv_rreq_addr(127 downto 64)   => Pages_inst_Pages_text_bus_rreq_addr,
      bsv_rdat_valid(0)              => Pages_inst_Pages_title_bus_rdat_valid,
      bsv_rdat_valid(1)              => Pages_inst_Pages_text_bus_rdat_valid,
      bsv_rdat_ready(0)              => Pages_inst_Pages_title_bus_rdat_ready,
      bsv_rdat_ready(1)              => Pages_inst_Pages_text_bus_rdat_ready,
      bsv_rdat_last(0)               => Pages_inst_Pages_title_bus_rdat_last,
      bsv_rdat_last(1)               => Pages_inst_Pages_text_bus_rdat_last,
      bsv_rdat_data(63 downto 0)    => Pages_inst_Pages_title_bus_rdat_data,
      bsv_rdat_data(127 downto 64) => Pages_inst_Pages_text_bus_rdat_data
    );
  BusWriteArbiterVec_inst : BusWriteArbiterVec
    generic map (
      BUS_ADDR_WIDTH   => 64,
      BUS_LEN_WIDTH    => 8,
      BUS_DATA_WIDTH   => 64,
      BUS_STROBE_WIDTH => 8,
      ARB_METHOD       => "ROUND-ROBIN",
      MAX_OUTSTANDING  => 4,
      RAM_CONFIG       => "",
      SLV_REQ_SLICES   => true,
      MST_REQ_SLICE    => true,
      MST_DAT_SLICE    => true,
      SLV_DAT_SLICES   => true,
      NUM_SLAVE_PORTS  => 3
    )
    port map (
      bcd_clk                         => bcd_clk,
      bcd_reset                       => bcd_reset,
      mst_wreq_valid                  => wr_mst_wreq_valid,
      mst_wreq_ready                  => wr_mst_wreq_ready,
      mst_wreq_addr                   => wr_mst_wreq_addr,
      mst_wreq_len                    => wr_mst_wreq_len,
      mst_wdat_valid                  => wr_mst_wdat_valid,
      mst_wdat_ready                  => wr_mst_wdat_ready,
      mst_wdat_data                   => wr_mst_wdat_data,
      mst_wdat_strobe                 => wr_mst_wdat_strobe,
      mst_wdat_last                   => wr_mst_wdat_last,
      bsv_wreq_valid(0)               => Result_inst_Result_title_bus_wreq_valid,
      bsv_wreq_valid(1)               => Result_inst_Result_count_bus_wreq_valid,
      bsv_wreq_valid(2)               => Stats_inst_Stats_stats_bus_wreq_valid,
      bsv_wreq_ready(0)               => Result_inst_Result_title_bus_wreq_ready,
      bsv_wreq_ready(1)               => Result_inst_Result_count_bus_wreq_ready,
      bsv_wreq_ready(2)               => Stats_inst_Stats_stats_bus_wreq_ready,
      bsv_wreq_len(7 downto 0)        => Result_inst_Result_title_bus_wreq_len,
      bsv_wreq_len(15 downto 8)       => Result_inst_Result_count_bus_wreq_len,
      bsv_wreq_len(23 downto 16)      => Stats_inst_Stats_stats_bus_wreq_len,
      bsv_wreq_addr(63 downto 0)      => Result_inst_Result_title_bus_wreq_addr,
      bsv_wreq_addr(127 downto 64)    => Result_inst_Result_count_bus_wreq_addr,
      bsv_wreq_addr(191 downto 128)   => Stats_inst_Stats_stats_bus_wreq_addr,
      bsv_wdat_valid(0)               => Result_inst_Result_title_bus_wdat_valid,
      bsv_wdat_valid(1)               => Result_inst_Result_count_bus_wdat_valid,
      bsv_wdat_valid(2)               => Stats_inst_Stats_stats_bus_wdat_valid,
      bsv_wdat_strobe(7 downto 0)    => Result_inst_Result_title_bus_wdat_strobe,
      bsv_wdat_strobe(15 downto 8)  => Result_inst_Result_count_bus_wdat_strobe,
      bsv_wdat_strobe(23 downto 16) => Stats_inst_Stats_stats_bus_wdat_strobe,
      bsv_wdat_ready(0)               => Result_inst_Result_title_bus_wdat_ready,
      bsv_wdat_ready(1)               => Result_inst_Result_count_bus_wdat_ready,
      bsv_wdat_ready(2)               => Stats_inst_Stats_stats_bus_wdat_ready,
      bsv_wdat_last(0)                => Result_inst_Result_title_bus_wdat_last,
      bsv_wdat_last(1)                => Result_inst_Result_count_bus_wdat_last,
      bsv_wdat_last(2)                => Stats_inst_Stats_stats_bus_wdat_last,
      bsv_wdat_data(63 downto 0)     => Result_inst_Result_title_bus_wdat_data,
      bsv_wdat_data(127 downto 64)  => Result_inst_Result_count_bus_wdat_data,
      bsv_wdat_data(191 downto 128) => Stats_inst_Stats_stats_bus_wdat_data
    );
end architecture;
