SRC_URI:append = "\
    file://fscrypt.cfg \
"

# Required for iMX95 Verdin EVK when using the NXP BSP layer (meta-imx-bsp),
# as its kernel recipe uses a custom kernel config fragments implementation
DELTA_KERNEL_DEFCONFIG:imx95-19x19-verdin += "\
    fscrypt.cfg \
"

# fscrypt takes its master key as raw bytes from user space, so the key is
# derived at runtime from a Trusted Key through a dm-crypt mapping; that means
# dm-crypt and the Trusted Keys subsystem are needed even though no block
# device is encrypted
#
# these fragments are already added by linux-dm-crypt.inc when the block device
# encryption feature is enabled, so they are only added here when it is not
FSENC_KEY_SRC_URI = "\
    file://dm-crypt.cfg \
    file://trusted-keys.cfg \
    file://${TDX_FSENC_KEY_BACKEND}.cfg \
"

FSENC_KEY_DELTA = "\
    dm-crypt.cfg \
    trusted-keys.cfg \
    ${TDX_FSENC_KEY_BACKEND}.cfg \
"

SRC_URI:append = "${@ '' if 'tdx-encrypted' in d.getVar('OVERRIDES').split(':') else ' ${FSENC_KEY_SRC_URI}'}"

DELTA_KERNEL_DEFCONFIG:imx95-19x19-verdin += "${@ '' if 'tdx-encrypted' in d.getVar('OVERRIDES').split(':') else '${FSENC_KEY_DELTA}'}"

# apply a patch on downstream based kernel to prevent an error
# when using the TPM as a source for the Trusted Keys subsystem
FSENC_SRC_URI_TPM = "\
    file://0001-KEYS-trusted-revert-changes-introduced-by-NXP.patch \
"
SRC_URI:append:pn-linux-toradex = "${@ '${FSENC_SRC_URI_TPM}' if d.getVar('TDX_FSENC_KEY_BACKEND') == 'tpm' and 'tdx-encrypted' not in d.getVar('OVERRIDES').split(':') else ''}"
