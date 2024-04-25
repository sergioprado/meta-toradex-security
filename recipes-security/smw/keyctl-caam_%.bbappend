EXTRA_OEMAKE += "KEYBLOB_LOCATION='${TDX_ENC_CAAM_KEYBLOB_DIR}'"

LIC_FILES_CHKSUM:use-mainline-bsp = "file://LICENSE;md5=8636bd68fc00cc6a3809b7b58b45f982"
SRCBRANCH:use-mainline-bsp = "lf-6.1.36_2.1.0"
SRCREV:use-mainline-bsp = "8dba6d3cac24b5a6c8daaaf1eda70fa18d488139"
DEPENDS:use-mainline-bsp += "openssl"
