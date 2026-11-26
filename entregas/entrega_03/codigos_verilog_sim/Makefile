# Display Driver - entrega 03 (compositor, sprites, texto, framebuffer A/B, PWM)
# Uso (desde esta carpeta):
#   make sim       corre todos los testbenches (+ comparacion con el modelo de referencia)
#   make report    sintesis + place&route y resumen (LUTs, EBR, frecuencia)
#   make bit       genera el bitstream (.bit y .svf)
#   make program   carga el .bit a la placa
#   make assets    regenera assets/*.hex desde tools/generate_assets.py
#   make clean

TOP      := top
RTL      := top.v spi_receiver.v spi_decoder.v scan_counter.v delay_unit.v \
            panel_pwm.v scene_compositor.v
TESTS    := top spi_receiver spi_invalid framebuffer pending_commit hw_check spec_rules
LPF      := constraints.lpf
DEVICE   := 25k
PACKAGE  := CABGA256
FREQ_MHZ := 25
BUILD    := build

YOSYS     ?= yosys
NEXTPNR   ?= nextpnr-ecp5
ECPPACK   ?= ecppack
IVERILOG  ?= iverilog
VVP       ?= vvp
LOADER    ?= openFPGALoader
LOADER_ARGS ?= --cable ft232RL --pins=0:3:4:1 --freq 3000000 -b colorlight

.PHONY: all sim report bit program assets clean
all: bit

$(BUILD):
	mkdir -p $(BUILD)

# ---------------- simulacion ----------------
# Cada <t>_TB.v contiene el modulo tb_<t>. Se ejecuta desde esta carpeta
# porque el RTL lee assets/*.hex con ruta relativa.
$(BUILD)/run_%: %_TB.v $(RTL) assets/sprites.hex | $(BUILD)
	$(IVERILOG) -g2012 -s tb_$* -o $(BUILD)/tb_$*.vvp $(RTL) $<
	$(VVP) $(BUILD)/tb_$*.vvp > $(BUILD)/tb_$*.log
	@grep -E "PASS|FAIL|TEST TOP" $(BUILD)/tb_$*.log || true
	@! grep -q FAIL $(BUILD)/tb_$*.log
	@touch $@

# spec_rules imprime el cuadro completo; se compara con el modelo en Python.
$(BUILD)/check_ref: $(BUILD)/run_spec_rules tools/ref_model.py
	@grep -v -e ERRFLAG -e finish $(BUILD)/tb_spec_rules.log > $(BUILD)/frame_rtl.txt
	@python3 tools/ref_model.py > $(BUILD)/frame_ref.txt
	@diff -q $(BUILD)/frame_ref.txt $(BUILD)/frame_rtl.txt >/dev/null \
	  && echo "PASS TOTAL: RTL == modelo de referencia (4096 pixeles)" \
	  || { echo "FAIL: RTL difiere del modelo de referencia"; exit 1; }
	@touch $@

sim: $(addprefix $(BUILD)/run_,$(TESTS)) $(BUILD)/check_ref
	@echo "== Todas las simulaciones pasaron =="

# ---------------- sintesis / place&route / bitstream ----------------
$(BUILD)/$(TOP).json: $(RTL) assets/sprites.hex | $(BUILD)
	$(YOSYS) -q -l $(BUILD)/yosys.log -p "read_verilog -sv $(RTL); synth_ecp5 -top $(TOP) -json $@"

$(BUILD)/$(TOP).config: $(BUILD)/$(TOP).json $(LPF)
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) --json $< --lpf $(LPF) \
	  --textcfg $@ --freq $(FREQ_MHZ) --seed 1 2> $(BUILD)/nextpnr.log

report: $(BUILD)/$(TOP).config
	@grep -E "DP16KD|TRELLIS_COMB|TRELLIS_FF|Max frequency" $(BUILD)/nextpnr.log | tail -5

bit: $(BUILD)/$(TOP).config
	$(ECPPACK) --compress --svf $(BUILD)/$(TOP).svf $< $(BUILD)/$(TOP).bit

program: bit
	$(LOADER) $(LOADER_ARGS) $(BUILD)/$(TOP).bit

assets:
	python3 tools/generate_assets.py

clean:
	rm -rf $(BUILD)
