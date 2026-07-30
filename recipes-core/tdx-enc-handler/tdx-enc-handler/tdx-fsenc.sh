#!/bin/sh

# Toradex filesystem encryption handler
#
# Encrypts directories of a filesystem with fscrypt, using a master key derived
# from a key protected by a hardware trust source (see TDX_FSENC_KEY_BACKEND).
#
# Unlike dm-crypt, fscrypt takes its master key as raw bytes from user space,
# while a Trusted Key never leaves the kernel. The master key is therefore
# derived at runtime by pushing a fixed all-zero sector through a dm-crypt
# mapping keyed by the Trusted Key: dm-crypt is the only interface that lets
# user space compute with a key the kernel refuses to disclose. The result is
# reproducible on every boot, so no additional key material is stored on disk.

# backend used to manage the encryption key
TDX_FSENC_KEY_BACKEND="@@TDX_FSENC_KEY_BACKEND@@"

# cipher preset used by the key derivation step
TDX_FSENC_CIPHER="@@TDX_FSENC_CIPHER@@"

# dm-crypt cipher specification (initialized at runtime)
TDX_FSENC_CIPHER_SPEC=""

# size in bytes of the key protected by the trust source (initialized at runtime)
TDX_FSENC_KEY_SIZE=""

# size in bytes of the fscrypt master key
TDX_FSENC_MASTER_KEY_SIZE="64"

# directory to store encrypted key
TDX_FSENC_KEY_DIR="@@TDX_FSENC_KEY_DIR@@"

# key file name
TDX_FSENC_KEY_FILE="@@TDX_FSENC_KEY_FILE@@"

# filesystem holding the directories to be encrypted
TDX_FSENC_STORAGE_LOCATION="@@TDX_FSENC_STORAGE_LOCATION@@"

# directory to mount the filesystem
TDX_FSENC_STORAGE_MOUNTPOINT="@@TDX_FSENC_STORAGE_MOUNTPOINT@@"

# extra arguments to mount; used when mounting the filesystem
TDX_FSENC_STORAGE_MOUNT_ARGS="@@TDX_FSENC_STORAGE_MOUNT_ARGS@@"

# directories to be encrypted, relative to the mount point
TDX_FSENC_DIRS="@@TDX_FSENC_DIRS@@"

# extra arguments to "fscryptctl set_policy"
TDX_FSENC_POLICY_ARGS="@@TDX_FSENC_POLICY_ARGS@@"

# encryption key full path
TDX_FSENC_KEY_FULLPATH="${TDX_FSENC_KEY_DIR}/${TDX_FSENC_KEY_FILE}"

# name of the key in the kernel keyring
TDX_FSENC_KEY_KEYRING_NAME="tdxfsenc"

# type of the key in the kernel keyring (depends on the backend and initialized at runtime)
TDX_FSENC_KEY_KEYRING_TYPE=""

# dm-crypt device used to derive the fscrypt master key
TDX_FSENC_DM_DEVICE="fsenckdf"

# scratch file and loop device backing the key derivation (initialized at runtime)
TDX_FSENC_KDF_FILE=""
TDX_FSENC_KDF_LOOP=""

# identifier of the fscrypt master key (initialized at runtime)
TDX_FSENC_KEY_ID=""

# file holding the identifier of the fscrypt master key while it is in use
TDX_FSENC_KEY_ID_FILE="/run/tdx-fsenc.keyid"

# log to standard output
tdx_fsenc_log() {
    echo "${TDX_FSENC_KEY_BACKEND}: $*"
}

# log error message and exit
tdx_fsenc_exit_error() {
    tdx_fsenc_log "ERROR: $*"
    tdx_fsenc_kdf_cleanup
    exit 1
}

# setup dm-crypt cipher spec and key size
#
# only AES-XTS is supported: its per block tweak makes every block of the
# derived key distinct, which a chaining mode cannot guarantee for the fixed
# input used by the key derivation
tdx_fsenc_cipher_configure() {
    case "${TDX_FSENC_CIPHER}" in
        aes-xts)
            TDX_FSENC_CIPHER_SPEC="xts(aes)-plain64"
            TDX_FSENC_KEY_SIZE="64"
            ;;
        *)
            tdx_fsenc_exit_error "Unsupported cipher preset '${TDX_FSENC_CIPHER}'!"
            ;;
    esac
    tdx_fsenc_log "Cipher: ${TDX_FSENC_CIPHER} (${TDX_FSENC_CIPHER_SPEC}, key=${TDX_FSENC_KEY_SIZE} bytes)"
}

# All backends: prepare and check system
tdx_fsenc_prepare_generic() {
    tdx_fsenc_log "Preparing and checking system (generic)..."

    if ! modprobe dm-crypt; then
        tdx_fsenc_exit_error "Error loading dm-crypt module!"
    fi

    if ! dmsetup targets | grep crypt -q; then
        tdx_fsenc_exit_error "No support for dm-crypt target!"
    fi

    if ! command -v fscryptctl > /dev/null; then
        tdx_fsenc_exit_error "fscryptctl not found!"
    fi
}

# CLEARTEXT: prepare system
tdx_fsenc_prepare_cleartext() {
    tdx_fsenc_log "Preparing and checking system (cleartext)..."
}

# CAAM: prepare system
tdx_fsenc_prepare_caam() {
    tdx_fsenc_log "Preparing and checking system (caam)..."

    if ! modprobe trusted source=caam; then
        tdx_fsenc_exit_error "Error loading trusted module!"
    fi
}

# TPM: prepare system
tdx_fsenc_prepare_tpm() {
    tdx_fsenc_log "Preparing and checking system (tpm)..."

    if ! modprobe trusted source=tpm; then
        tdx_fsenc_exit_error "Error loading trusted module!"
    fi

    if [ ! -c /dev/tpm0 ]; then
        tdx_fsenc_exit_error "TPM device node (/dev/tpm0) not found!"
    fi

    if ! echo "deadbeef" | tpm2_hash >/dev/null; then
        tdx_fsenc_exit_error "Hash calculation via tpm2_hash failed. TPM device might not be functional!"
    fi
}

# TEE: prepare system
tdx_fsenc_prepare_tee() {
    tdx_fsenc_log "Preparing and checking system (tee)..."

    if [ ! -c /dev/tee0 ]; then
        tdx_fsenc_exit_error "TEE device node not found!"
    fi

    if ! pgrep "tee-supplicant" > /dev/null; then
        tdx_fsenc_exit_error "TEE supplicant daemon not running!"
    fi

    if ! modprobe trusted source=tee; then
        tdx_fsenc_exit_error "Error loading trusted module!"
    fi
}

# configure key in kernel keyring
tdx_fsenc_keyring_configure() {
    TDX_FSENC_KEY_KEYRING_TYPE="$1"
    KEYNAME="$2"
    NEW_KEY_CMD="$3"
    LOAD_KEY_CMD="$4"

    tdx_fsenc_log "Configuring key in kernel keyring (type=$TDX_FSENC_KEY_KEYRING_TYPE keyname=$KEYNAME)..."

    keyctl new_session ${KEYNAME}_session

    if [ ! -e "${TDX_FSENC_KEY_FULLPATH}" ]; then
        tdx_fsenc_log "Key blob not found. Creating it..."
        KEYHANDLE="$(keyctl add "${TDX_FSENC_KEY_KEYRING_TYPE}" "${KEYNAME}" "$(eval echo ${NEW_KEY_CMD})" @s)"
        mkdir -p "${TDX_FSENC_KEY_DIR}"
        TDX_FSENC_KEY_TMPPATH=$(mktemp "${TDX_FSENC_KEY_DIR}/tdx-fsenc.XXXXXXXXXX")
        if ! keyctl pipe "$KEYHANDLE" > "${TDX_FSENC_KEY_TMPPATH}"; then
            rm -f "${TDX_FSENC_KEY_TMPPATH}"
            tdx_fsenc_exit_error "Error saving key blob!"
        fi
        mv "${TDX_FSENC_KEY_TMPPATH}" "${TDX_FSENC_KEY_FULLPATH}"
    else
        tdx_fsenc_log "Encrypted key exists. Importing it..."
        keyctl add "${TDX_FSENC_KEY_KEYRING_TYPE}" "${KEYNAME}" "$(eval echo ${LOAD_KEY_CMD})" @s
    fi

    if ! keyctl list @s | grep -q "${TDX_FSENC_KEY_KEYRING_TYPE}: ${KEYNAME}"; then
        tdx_fsenc_exit_error "Error adding key to kernel keyring!"
    fi
}

# CLEARTEXT: generate/load key
# the key is generated by using the SoM serial number and no salt,
# so it is reproducible and doesn't need to be stored in a
# persistent storage device. This is very insecure, but we
# don't care about it, since the 'cleartext' backend is only
# for testing purposes.
tdx_fsenc_key_gen_cleartext() {
    tdx_fsenc_log "Setting up encryption key for cleartext backend..."
    SN=$(cat /sys/firmware/devicetree/base/serial-number)
    KEY=$(openssl enc -pbkdf2 -aes-256-cbc -nosalt -k "${SN}" -P | grep '^key=' | cut -d'=' -f 2)
    if [ "${TDX_FSENC_KEY_SIZE}" = "64" ]; then
        KEY="${KEY}$(openssl enc -pbkdf2 -aes-256-cbc -nosalt -k "${SN}-2" -P | grep '^key=' | cut -d'=' -f 2)"
    fi
    tdx_fsenc_keyring_configure "user" "${TDX_FSENC_KEY_KEYRING_NAME}" "${KEY}" "${KEY}"
}

# CAAM: generate/load key
tdx_fsenc_key_gen_caam() {
    tdx_fsenc_log "Setting up encryption key for CAAM backend..."
    tdx_fsenc_keyring_configure "trusted" "${TDX_FSENC_KEY_KEYRING_NAME}" "new ${TDX_FSENC_KEY_SIZE}" "load \$(cat ${TDX_FSENC_KEY_FULLPATH})"
}

# TPM: generate/load key
tdx_fsenc_key_gen_tpm() {
    tdx_fsenc_log "Setting up encryption key for TPM backend..."

    if [ ! -e "${TDX_FSENC_KEY_FULLPATH}" ]; then
        TPM_KEY_CTXT=$(mktemp /tmp/tdx-fsenc.XXXXXXXXXX)

        # create a private RSA key in the TPM
        if ! tpm2_createprimary -C o -G rsa2048 -c "${TPM_KEY_CTXT}"; then
            rm -f "${TPM_KEY_CTXT}"
            tdx_fsenc_exit_error "Error creating a private RSA key in the TPM!"
        fi

        # make the key persistent
        TPMKEYHANDLE=$(tpm2_evictcontrol -C o -c "${TPM_KEY_CTXT}" | grep persistent-handle | cut -d' ' -f 2)
        rm -f "${TPM_KEY_CTXT}"
        if [ -z "$TPMKEYHANDLE" ]; then
            tdx_fsenc_exit_error "Error making the TPM key persistent!"
        fi
    fi

    tdx_fsenc_keyring_configure "trusted" "${TDX_FSENC_KEY_KEYRING_NAME}" \
                                "new ${TDX_FSENC_KEY_SIZE} keyhandle=$TPMKEYHANDLE" \
                                "load \$(cat ${TDX_FSENC_KEY_FULLPATH})"
}

# TEE: generate/load key
tdx_fsenc_key_gen_tee() {
    tdx_fsenc_log "Setting up encryption key for TEE backend..."
    tdx_fsenc_keyring_configure "trusted" "${TDX_FSENC_KEY_KEYRING_NAME}" "new ${TDX_FSENC_KEY_SIZE}" "load \$(cat ${TDX_FSENC_KEY_FULLPATH})"
}

# enable filesystem support for encryption if needed
# only ext4 needs a feature flag, and it can only be set while unmounted
tdx_fsenc_storage_prepare() {
    FSTYPE=$(blkid -o value -s TYPE ${TDX_FSENC_STORAGE_LOCATION})
    if [ "${FSTYPE}" != "ext4" ]; then
        tdx_fsenc_log "Filesystem is '${FSTYPE}', no encryption feature flag needed."
        return 0
    fi

    if tune2fs -l ${TDX_FSENC_STORAGE_LOCATION} | grep -q "^Filesystem features:.*encrypt"; then
        return 0
    fi

    tdx_fsenc_log "Enabling the 'encrypt' feature on ${TDX_FSENC_STORAGE_LOCATION}..."
    if ! tune2fs -O encrypt ${TDX_FSENC_STORAGE_LOCATION}; then
        tdx_fsenc_exit_error "Could not enable the 'encrypt' feature on ${TDX_FSENC_STORAGE_LOCATION}!"
    fi
}

# mount the filesystem holding the directories to be encrypted
tdx_fsenc_storage_mount() {
    if source=$(findmnt -no SOURCE "${TDX_FSENC_STORAGE_MOUNTPOINT}"); then
        if [ "${source}" != "${TDX_FSENC_STORAGE_LOCATION}" ]; then
            tdx_fsenc_exit_error "Mount location already points to a different storage location."
        fi
        tdx_fsenc_log "Filesystem is already mounted to the specified location."
        return 0
    fi

    tdx_fsenc_storage_prepare

    tdx_fsenc_log "Mounting filesystem..."
    mkdir -p "${TDX_FSENC_STORAGE_MOUNTPOINT}"
    if ! mount ${TDX_FSENC_STORAGE_LOCATION} "${TDX_FSENC_STORAGE_MOUNTPOINT}" ${TDX_FSENC_STORAGE_MOUNT_ARGS}; then
        tdx_fsenc_exit_error "Could not mount ${TDX_FSENC_STORAGE_LOCATION}!"
    fi
}

# umount the filesystem
tdx_fsenc_storage_umount() {
    if findmnt -no SOURCE "${TDX_FSENC_STORAGE_MOUNTPOINT}" > /dev/null; then
        tdx_fsenc_log "Unmounting filesystem from '${TDX_FSENC_STORAGE_MOUNTPOINT}'..."
        umount "${TDX_FSENC_STORAGE_MOUNTPOINT}"
    fi
}

# release the resources used by the key derivation
tdx_fsenc_kdf_cleanup() {
    if [ -n "${TDX_FSENC_DM_DEVICE}" ]; then
        dmsetup remove ${TDX_FSENC_DM_DEVICE} > /dev/null 2>&1
    fi
    if [ -n "${TDX_FSENC_KDF_LOOP}" ]; then
        losetup -d "${TDX_FSENC_KDF_LOOP}" > /dev/null 2>&1
        TDX_FSENC_KDF_LOOP=""
    fi
    if [ -n "${TDX_FSENC_KDF_FILE}" ]; then
        rm -f "${TDX_FSENC_KDF_FILE}"
        TDX_FSENC_KDF_FILE=""
    fi
    return 0
}

# create the fixed input of the key derivation
#
# the sector is filled with a label instead of being zeroed, so that every 16
# byte block of it differs: with a constant input, a CBC based mapping would
# decrypt every block to the same value and the derived key would degenerate
# into a single block repeated over and over. The label also separates this key
# from any other key that may be derived from the same trust source later on.
tdx_fsenc_kdf_scratch_create() {
    TDX_FSENC_KDF_FILE=$(mktemp /tmp/tdx-fsenc.XXXXXXXXXX)

    i=0
    while [ "${i}" -lt 32 ]; do
        printf 'tdx-fsenc-mk%03d\n' "${i}"
        i=$((i + 1))
    done > "${TDX_FSENC_KDF_FILE}"

    if [ "$(wc -c < "${TDX_FSENC_KDF_FILE}")" != "512" ]; then
        tdx_fsenc_exit_error "Could not create the key derivation scratch file!"
    fi
}

# derive the fscrypt master key and add it to the filesystem
#
# the master key is the result of pushing a fixed sector through a dm-crypt
# mapping keyed by the key held in the kernel keyring, which makes it
# reproducible on every boot without ever exposing the key itself
tdx_fsenc_master_key_add() {
    tdx_fsenc_log "Deriving fscrypt master key..."

    tdx_fsenc_kdf_scratch_create

    TDX_FSENC_KDF_LOOP=$(losetup -f --show "${TDX_FSENC_KDF_FILE}")
    if [ -z "${TDX_FSENC_KDF_LOOP}" ]; then
        tdx_fsenc_exit_error "Could not set up a loop device for the key derivation!"
    fi

    if ! dmsetup -v create ${TDX_FSENC_DM_DEVICE} \
                 --table "0 1 \
                 crypt capi:${TDX_FSENC_CIPHER_SPEC} :${TDX_FSENC_KEY_SIZE}:${TDX_FSENC_KEY_KEYRING_TYPE}:${TDX_FSENC_KEY_KEYRING_NAME} \
                 0 ${TDX_FSENC_KDF_LOOP} 0 1 sector_size:512"; then
        tdx_fsenc_exit_error "Error setting up the key derivation device!"
    fi

    # make sure the derivation really produced a full key before handing it
    # over, otherwise a short read would silently weaken the encryption
    DERIVED_SIZE=$(dd if=/dev/mapper/${TDX_FSENC_DM_DEVICE} bs=${TDX_FSENC_MASTER_KEY_SIZE} count=1 2>/dev/null | wc -c)
    if [ "${DERIVED_SIZE}" != "${TDX_FSENC_MASTER_KEY_SIZE}" ]; then
        tdx_fsenc_exit_error "Key derivation produced ${DERIVED_SIZE} bytes, expected ${TDX_FSENC_MASTER_KEY_SIZE}!"
    fi

    tdx_fsenc_log "Adding fscrypt master key to ${TDX_FSENC_STORAGE_MOUNTPOINT}..."
    TDX_FSENC_KEY_ID=$(dd if=/dev/mapper/${TDX_FSENC_DM_DEVICE} bs=${TDX_FSENC_MASTER_KEY_SIZE} count=1 2>/dev/null \
                       | fscryptctl add_key "${TDX_FSENC_STORAGE_MOUNTPOINT}")

    tdx_fsenc_kdf_cleanup

    if [ -z "${TDX_FSENC_KEY_ID}" ]; then
        tdx_fsenc_exit_error "Error adding the fscrypt master key!"
    fi

    # remember the identifier so it can be removed on shutdown without having
    # to parse it back out of an encryption policy
    echo "${TDX_FSENC_KEY_ID}" > ${TDX_FSENC_KEY_ID_FILE}

    tdx_fsenc_log "fscrypt master key identifier: ${TDX_FSENC_KEY_ID}"
}

# remove the fscrypt master key from the filesystem, locking the encrypted
# directories until the key is added again
tdx_fsenc_master_key_remove() {
    if [ ! -e "${TDX_FSENC_KEY_ID_FILE}" ]; then
        tdx_fsenc_log "No fscrypt master key to remove."
        return 0
    fi

    TDX_FSENC_KEY_ID=$(cat ${TDX_FSENC_KEY_ID_FILE})
    tdx_fsenc_log "Removing fscrypt master key ${TDX_FSENC_KEY_ID}..."
    fscryptctl remove_key "${TDX_FSENC_KEY_ID}" "${TDX_FSENC_STORAGE_MOUNTPOINT}"
    rm -f ${TDX_FSENC_KEY_ID_FILE}
}

# apply the encryption policy to a directory
tdx_fsenc_policy_apply() {
    DIRPATH="${TDX_FSENC_STORAGE_MOUNTPOINT}/$1"

    if [ -d "${DIRPATH}" ]; then
        if fscryptctl get_policy "${DIRPATH}" > /dev/null 2>&1; then
            tdx_fsenc_log "Directory '$1' is already encrypted."
            return 0
        fi

        # a policy can only be set on an empty directory, and existing content
        # would have to be copied into place, which is not done automatically
        if [ -n "$(ls -A "${DIRPATH}" 2>/dev/null)" ]; then
            tdx_fsenc_exit_error "Directory '$1' already exists and is not empty. Refusing to encrypt it."
        fi
    else
        tdx_fsenc_log "Creating directory '$1'..."
        if ! mkdir -p "${DIRPATH}"; then
            tdx_fsenc_exit_error "Could not create directory '$1'!"
        fi
    fi

    tdx_fsenc_log "Setting encryption policy on '$1'..."
    if ! fscryptctl set_policy ${TDX_FSENC_POLICY_ARGS} "${TDX_FSENC_KEY_ID}" "${DIRPATH}"; then
        tdx_fsenc_exit_error "Could not set the encryption policy on '$1'!"
    fi
}

# apply the encryption policy to all configured directories
tdx_fsenc_policy_apply_all() {
    for dir in ${TDX_FSENC_DIRS}; do
        tdx_fsenc_policy_apply "${dir}"
    done
}

# remove key from keyring
tdx_fsenc_clear_keys_keyring() {
    tdx_fsenc_log "Removing key from kernel keyring..."
    keyctl clear @s
}

# unlock the encrypted directories
tdx_fsenc_main_start() {
    tdx_fsenc_cipher_configure
    tdx_fsenc_prepare_generic
    tdx_fsenc_prepare_${TDX_FSENC_KEY_BACKEND}
    tdx_fsenc_key_gen_${TDX_FSENC_KEY_BACKEND}
    tdx_fsenc_storage_mount
    tdx_fsenc_master_key_add
    tdx_fsenc_policy_apply_all
}

# lock the encrypted directories
tdx_fsenc_main_stop() {
    tdx_fsenc_master_key_remove
    tdx_fsenc_storage_umount
    tdx_fsenc_clear_keys_keyring
}

tdx_fsenc_main() {
    case $1 in
        start)
            tdx_fsenc_main_start
            ;;
        stop)
            tdx_fsenc_main_stop
            ;;
        *)
            tdx_fsenc_exit_error "Invalid option! Please use 'start' or 'stop'."
            ;;
    esac

    tdx_fsenc_log "Success!"
}

tdx_fsenc_main "$1"
