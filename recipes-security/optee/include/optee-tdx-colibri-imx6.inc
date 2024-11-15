# compatible machine in OP-TEE source code
OPTEEMACHINE = "imx-mx6dlsabresd"

# required by NXP OP-TEE recipe
PLATFORM_FLAVOR = "mx6dlsabresd"

# uart base address (to print debug messages)
UART_BASE_ADDR = "0x02020000"

# extra arguments to build OP-TEE OS
OPTEE_OS_EXTRA_MACHINE_ARGS = "\
    CFG_DDR_SIZE=0x20000000 \
    CFG_NS_ENTRY_ADDR=0x17800000 \
    CFG_TZDRAM_START=0x1c000000 \
    CFG_TZDRAM_SIZE=0x01000000 \
    CFG_DT=n \
"
