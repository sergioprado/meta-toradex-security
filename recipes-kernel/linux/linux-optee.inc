SRC_URI:append = "\
    file://optee.cfg \
    ${@oe.utils.conditional('TDX_OPTEE_FTPM', '1', 'file://optee-ftpm.cfg', '', d)} \
"

SRC_URI:append:colibri-imx6 = "\
    file://0001-ARM-dts-imx6qdl-colibri-add-OP-TEE-related-nodes.patch \
"
