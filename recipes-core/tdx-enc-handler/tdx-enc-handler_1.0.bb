SUMMARY = "Scripts to handle encryption on Toradex modules"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "\
    file://tdx-enc-cleartext.sh \
    file://tdx-enc-caam.sh \
    file://tdx-enc-tpm.sh \
    file://tdx-enc-handler.service \
"

RDEPENDS:${PN} = "\
    openssl-bin \
    cryptsetup \
    e2fsprogs-mke2fs \
"

RDEPENDS_CAAM = "\
    keyutils \
    util-linux \
"
RDEPENDS:${PN}:append = "${@ '${RDEPENDS_CAAM}' if d.getVar('TDX_ENC_KEY_BACKEND') == 'caam' else ''}"

RDEPENDS_TPM = "\
    keyutils \
    tpm2-tools \
    strace \
    util-linux \
"
RDEPENDS:${PN}:append = "${@ '${RDEPENDS_TPM}' if d.getVar('TDX_ENC_KEY_BACKEND') == 'tpm' else ''}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "tdx-enc-handler.service"
SYSTEMD_AUTO_ENABLE = "disable"

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/tdx-enc-${TDX_ENC_KEY_BACKEND}.sh ${D}${sbindir}/tdx-enc.sh

    sed -i 's|@@TDX_ENC_KEY_FILE@@|${TDX_ENC_KEY_FILE}|g' ${D}${sbindir}/tdx-enc.sh
    sed -i 's|@@TDX_ENC_STORAGE_LOCATION@@|${TDX_ENC_STORAGE_LOCATION}|g' ${D}${sbindir}/tdx-enc.sh
    sed -i 's|@@TDX_ENC_STORAGE_MOUNTPOINT@@|${TDX_ENC_STORAGE_MOUNTPOINT}|g' ${D}${sbindir}/tdx-enc.sh
    sed -i 's|@@TDX_ENC_KEY_DIR@@|${TDX_ENC_KEY_DIR}|g' ${D}${sbindir}/tdx-enc.sh
    sed -i 's|@@TDX_ENC_PRESERVE_DATA@@|${TDX_ENC_PRESERVE_DATA}|g' ${D}${sbindir}/tdx-enc.sh
    sed -i 's|@@TDX_ENC_BACKUP_STORAGE_PCT@@|${TDX_ENC_BACKUP_STORAGE_PCT}|g' ${D}${sbindir}/tdx-enc.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/tdx-enc-handler.service ${D}${systemd_system_unitdir}
}
