FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:verdin-imx8mp = "\
    file://0001-imx8mp-binman-add-tee-node.patch \
    file://dram-banks.cfg \
"

SRC_URI:append:verdin-imx8mm = "\
    file://0001-imx8mm-binman-add-tee-node.patch \
"

SRC_URI:append:colibri-imx6 = "\
    file://0001-toradex-imx6dl-add-support-to-boot-OP-TEE-from-SPL.patch \
    file://optee-colibri-imx6.cfg \
"

SRC_URI:append:colibri-imx7-emmc = "\
    file://0001-board-colibri_imx7-add-SPL-support.patch \
    file://0001-toradex-imx7d-add-support-to-boot-OP-TEE-from-SPL.patch \
    file://optee-colibri-imx7-emmc.cfg \
"

EXTRA_OEMAKE:append:colibri-imx6 = " TEE=tee.bin"
EXTRA_OEMAKE:append:colibri-imx7-emmc = " TEE=tee.bin"

copy_optee_binary_to_uboot() {
    if [ -n "${UBOOT_CONFIG}" ]; then
        for config in ${UBOOT_MACHINE}; do
            i=$(expr $i + 1);
            for type in ${UBOOT_CONFIG}; do
                j=$(expr $j + 1);
                if [ $j -eq $i ]; then
                    bbnote "Copying tee.bin from ${DEPLOY_DIR_IMAGE} to ${B}/${config}/".
                    cp ${DEPLOY_DIR_IMAGE}/tee.bin ${B}/${config}/
                fi
            done
            unset j
        done
        unset i
    else
        bbnote "Copying tee.bin from ${DEPLOY_DIR_IMAGE} to ${B}/".
        cp ${DEPLOY_DIR_IMAGE}/tee.bin ${B}
    fi
}
do_prepare_uboot_for_optee() {
    bbnote "Nothing to be done for machine ${MACHINE}"
}
do_prepare_uboot_for_optee:colibri-imx6() {
    copy_optee_binary_to_uboot
}
do_prepare_uboot_for_optee:colibri-imx7-emmc() {
    copy_optee_binary_to_uboot
}
do_prepare_uboot_for_optee[depends] += "optee-os:do_deploy"
addtask do_prepare_uboot_for_optee before do_compile after do_configure

IMX_BOOT_CONTAINER_FIRMWARE:append = "tee.bin"
