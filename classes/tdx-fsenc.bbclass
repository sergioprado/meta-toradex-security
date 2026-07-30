# override for conditional assignment
DISTROOVERRIDES .= ":tdx-fsenc"

# Encryption key backend
# This variable defines how the encryption key is managed
# Available options:
#    cleartext -> key is stored in clear text (for testing purposes only!)
#    caam      -> use CAAM (available only on iMX6/7/8 based SoMs)
#    tpm       -> use TPM (Trusted Platform Module)
#    tee       -> use TEE (Trusted Execution Environment)
TDX_FSENC_KEY_BACKEND ?= ""
TDX_FSENC_KEY_BACKEND:mx6-generic-bsp ?= "caam"
TDX_FSENC_KEY_BACKEND:mx7-generic-bsp ?= "caam"
TDX_FSENC_KEY_BACKEND:mx8-generic-bsp ?= "caam"

# Cipher preset used to derive the fscrypt master key
# This variable selects the cipher used by the key derivation step, not the
# cipher used by fscrypt itself (see TDX_FSENC_POLICY_ARGS for that)
# WARNING: changing this on a device with encrypted data makes it unrecoverable
# Available options:
#    aes-xts -> AES-XTS with plain64 IV
# Only AES-XTS is supported: the key derivation pushes a fixed input through the
# cipher, and only the per block tweak of XTS guarantees that every block of the
# derived key is distinct
TDX_FSENC_CIPHER ?= "aes-xts"

# directory to store the encryption key blob
TDX_FSENC_KEY_DIR ?= "/var/local/private/.keys"

# encryption key blob file name
TDX_FSENC_KEY_FILE ?= "tdx-fsenc-key.blob"

# Filesystem holding the directories to be encrypted (e.g. /dev/mmcblk1p1)
TDX_FSENC_STORAGE_LOCATION ?= ""

# Defines where the filesystem will be mounted
TDX_FSENC_STORAGE_MOUNTPOINT ?= "/run/fsencdata"

# Extra arguments passed to "mount" when mounting the filesystem
TDX_FSENC_STORAGE_MOUNT_ARGS ?= ""

# Directories to be encrypted, relative to TDX_FSENC_STORAGE_MOUNTPOINT
# They are created on first boot; existing non-empty directories are refused
TDX_FSENC_DIRS ?= ""

# Extra arguments passed to "fscryptctl set_policy"
# Leave empty to use the fscryptctl defaults (AES-256-XTS for file contents and
# AES-256-CTS for file names), e.g. "--contents=AES-256-XTS --filenames=AES-256-CTS"
TDX_FSENC_POLICY_ARGS ?= ""

# tdx-enc-handler provides the scripts to handle encryption
IMAGE_INSTALL:append = " tdx-enc-handler"

# validate encryption parameters
addhandler validate_fsenc_parameters
validate_fsenc_parameters[eventmask] = "bb.event.SanityCheck"
python validate_fsenc_parameters() {
    key_backend = e.data.getVar('TDX_FSENC_KEY_BACKEND')
    if key_backend == "":
        bb.fatal("Please set key backend provider via TDX_FSENC_KEY_BACKEND.")
    supported_key_backends = ['cleartext','caam','tpm','tee']
    if key_backend not in supported_key_backends:
        bb.fatal("'%s' is invalid. Please set a valid key backend provider via TDX_FSENC_KEY_BACKEND." % key_backend)

    storage_location = e.data.getVar('TDX_FSENC_STORAGE_LOCATION')
    if storage_location == "":
        bb.fatal("Please set the filesystem to be encrypted via TDX_FSENC_STORAGE_LOCATION.")

    dirs = e.data.getVar('TDX_FSENC_DIRS')
    if not dirs.strip():
        bb.fatal("Please set the directories to be encrypted via TDX_FSENC_DIRS.")

    cipher = e.data.getVar('TDX_FSENC_CIPHER')
    supported_ciphers = ['aes-xts']
    if cipher not in supported_ciphers:
        bb.fatal("'%s' is invalid. Please set a valid cipher algorithm via TDX_FSENC_CIPHER. Supported: %s" % (cipher, ', '.join(supported_ciphers)))

    # both features share the kernel side configuration of the Trusted Keys
    # subsystem, which can only be built for a single trust source
    if 'tdx-encrypted' in e.data.getVar('OVERRIDES').split(':'):
        if e.data.getVar('TDX_ENC_KEY_BACKEND') != key_backend:
            bb.fatal("TDX_FSENC_KEY_BACKEND and TDX_ENC_KEY_BACKEND must match when both encryption features are enabled.")
}
