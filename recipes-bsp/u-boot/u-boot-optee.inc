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
    file://spl-fit-optee.cfg \
"

EXTRA_OEMAKE:append:colibri-imx6 = " TEE=tee.bin"

do_prepare_uboot_for_optee() {
    bbnote "Nothing to be done for machine ${MACHINE}"
}
do_prepare_uboot_for_optee:colibri-imx6() {
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
}
do_prepare_uboot_for_optee[depends] += "optee-os:do_deploy"
addtask do_prepare_uboot_for_optee before do_compile after do_configure

IMX_BOOT_CONTAINER_FIRMWARE:append = "tee.bin"
