# ============================================================
# Real Digital Urbana - RISC-V FPGA
# Spartan-7 XC7S50-CSGA324
# ============================================================

# ------------------------------------------------------------
# 100 MHz board oscillator
# ------------------------------------------------------------

set_property PACKAGE_PIN N15 [get_ports {clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk}]

#create_clock -name sys_clk -period 10.000 \
#    -waveform {0.000 5.000} [get_ports {clk}]


# ------------------------------------------------------------
# CPU Reset - Urbana BTN0 (general-purpose pushbutton)
# Active high: pressing BTN0 resets the processor
# ------------------------------------------------------------

set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS25} [get_ports {rst}]


# ------------------------------------------------------------
# Debug data - LEDs 0 through 7
# ------------------------------------------------------------

set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports {debug_data[0]}]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports {debug_data[1]}]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports {debug_data[2]}]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports {debug_data[3]}]
set_property -dict {PACKAGE_PIN D16 IOSTANDARD LVCMOS33} [get_ports {debug_data[4]}]
set_property -dict {PACKAGE_PIN F18 IOSTANDARD LVCMOS33} [get_ports {debug_data[5]}]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports {debug_data[6]}]
set_property -dict {PACKAGE_PIN D17 IOSTANDARD LVCMOS33} [get_ports {debug_data[7]}]


# ------------------------------------------------------------
# Processor status - LEDs 8 through 10
# ------------------------------------------------------------

set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33} [get_ports {test_done}]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports {fetch_error}]
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS33} [get_ports {data_access_fault}]


# ------------------------------------------------------------
# FPGA configuration voltage
# ------------------------------------------------------------

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
