# U-Boot configuration
UBOOT_SUFFIX:forcevariable = "itb"
UBOOT_BINARY:forcevariable = "u-boot.${UBOOT_SUFFIX}"
UBOOT_MAKE_TARGET:forcevariable = ""
SPL_BINARY="SPL"

# Easy Installer configuration
OFFSET_BOOTROM_PAYLOAD="2"
OFFSET_SPL_PAYLOAD="138"
