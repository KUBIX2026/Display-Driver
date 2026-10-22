# ==========================================
# VARIABLES DEL PROYECTO
# ==========================================
PROJ = hub75_controller
TOP  = top
# Lista actualizada de archivos fuente (se elimina panel_memory.v y se añade spi_receiver.v)
SRCS = top.v panel_pwm.v scan_counter.v delay_unit.v spi_receiver.v spi_decoder.v vram.v
LPF  = constraints.lpf
TB   = tb


# Configuración FPGA
DEVICE  = 25k
PACKAGE = CABGA256
BUILD_DIR = build


# Herramientas sim
IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave


# COMPILACIÓN
# 1. Objetivo por defecto
all: $(BUILD_DIR)/$(PROJ).bit
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# 2. Síntesis (Yosys)
$(BUILD_DIR)/$(PROJ).json: $(SRCS) | $(BUILD_DIR)
	yosys -p "read_verilog $(SRCS); synth_ecp5 -top $(TOP) -json $@"

# 3. Place & Route (NextPNR)
$(BUILD_DIR)/$(PROJ).config: $(BUILD_DIR)/$(PROJ).json
	nextpnr-ecp5 --$(DEVICE) --package $(PACKAGE) --json $< --lpf $(LPF) --textcfg $@

# 4. Bitstream (Ecppack)
$(BUILD_DIR)/$(PROJ).bit: $(BUILD_DIR)/$(PROJ).config
	ecppack --compress --svf $(BUILD_DIR)/$(PROJ).svf $< $@

# 5. Programar (openFPGALoader)
program: $(BUILD_DIR)/$(PROJ).bit
	openFPGALoader --cable ft232RL --pins=0:3:4:1 --freq 3000000 -b colorlight $<


# SIMULACIÓN

# 1. Compilar simulación (.vvp)
$(BUILD_DIR)/$(TB).vvp: $(TB).v $(SRCS) | $(BUILD_DIR)
	$(IVERILOG) -o $@ -s $(TB) $(TB).v $(SRCS)

# 2. Ejecutar simulación (.vcd)
$(BUILD_DIR)/hub75_simulation.vcd: $(BUILD_DIR)/$(TB).vvp
	$(VVP) $<

# 3. Target "make sim": Ejecuta todo lo necesario para simular
sim: $(BUILD_DIR)/hub75_simulation.vcd

# 4. Target "make view": Abre GTKWave automáticamente
view: sim
	$(GTKWAVE) $(BUILD_DIR)/hub75_simulation.vcd

# Limpiar
clean:
	rm -rf $(BUILD_DIR)

.PHONY: all program clean
