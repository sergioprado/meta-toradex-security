SRC_URI:append = "\
    file://optee.cfg \
    ${@oe.utils.conditional('TDX_OPTEE_FTPM', '1', 'file://optee-ftpm.cfg', '', d)} \
"

SRC_URI:append:colibri-imx6 = "\
    file://0001-ARM-dts-imx6qdl-colibri-add-OP-TEE-related-nodes.patch \
"

SRC_URI:append:apalis-imx6 = "\
    file://0001-ARM-dts-imx6qdl-apalis-add-OP-TEE-related-nodes.patch \
"

SRC_URI:append:colibri-imx7-emmc = "\
    file://0001-ARM-dts-imx7d-colibri-emmc-add-OP-TEE-related-nodes.patch \
"
