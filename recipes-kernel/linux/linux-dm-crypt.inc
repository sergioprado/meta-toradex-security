SRC_URI:append = "\
    file://dm-crypt.cfg \
    file://${TDX_ENC_KEY_BACKEND}.cfg \
    file://imx8mp-verdin-wifi-dev.dts \
"

do_configure:append() {
    cp ${WORKDIR}/imx8mp-verdin-wifi-dev.dts ${S}/arch/arm64/boot/dts/freescale/imx8mp-verdin-wifi-dev.dts
}
