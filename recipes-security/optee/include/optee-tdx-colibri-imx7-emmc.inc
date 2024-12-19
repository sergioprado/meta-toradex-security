# compatible machine in OP-TEE source code
OPTEEMACHINE = "imx-mx7dsabresd"

# required by NXP OP-TEE recipe
PLATFORM_FLAVOR = "mx7dsabresd"

# uart base address (to print debug messages)
UART_BASE_ADDR = "0x30860000"

# extra arguments to build OP-TEE OS
OPTEE_OS_EXTRA_MACHINE_ARGS = "\
    CFG_NS_ENTRY_ADDR=0x87800000 \
    CFG_TZDRAM_START=0x8c000000 \
    CFG_TZDRAM_SIZE=0x01000000 \
    CFG_DT=n \
"
