# ===== USER CONFIG =====
TOP ?= top                # module name (not filename)
SRC_DIR := rtl
BUILD_DIR := build
PCF ?= constraints.pcf

DEVICE := up5k
PACKAGE := sg48

# ===== AUTO FILE COLLECTION =====
SRCS := $(wildcard $(SRC_DIR)/*.v)

# ===== BUILD FILES =====
JSON := $(BUILD_DIR)/$(TOP).json
ASC  := $(BUILD_DIR)/$(TOP).asc
BIN  := $(BUILD_DIR)/$(TOP).bin

# ===== DEFAULT TARGET =====
all: $(BIN)

# ===== CREATE BUILD DIR =====
$(BUILD_DIR):
	mkdir $(BUILD_DIR) 2>nul || echo Build dir exists

# ===== SYNTHESIS =====
$(JSON): $(SRCS) | $(BUILD_DIR)
	yosys -p "synth_ice40 -top $(TOP) -json $(JSON)" $(SRCS)

# ===== PLACE & ROUTE =====
$(ASC): $(JSON) $(PCF)
	nextpnr-ice40 --$(DEVICE) --package $(PACKAGE) \
		--json $(JSON) \
		--pcf $(PCF) \
		--asc $(ASC)

# ===== BITSTREAM =====
$(BIN): $(ASC)
	icepack $(ASC) $(BIN)

# ===== FLASH =====
flash: $(BIN)
	iceprog $(BIN)

# ===== CLEAN =====
clean:
	del /Q $(BUILD_DIR)\* 2>nul || rm -rf $(BUILD_DIR)