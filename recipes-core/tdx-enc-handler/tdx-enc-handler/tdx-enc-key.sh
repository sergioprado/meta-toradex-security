#!/bin/sh

# CLEARTEXT: prepare system
tdx_enc_key_prepare_cleartext() {
    tdx_enc_log "Preparing and checking system (cleartext)..."
}

# CAAM: prepare system
tdx_enc_key_prepare_caam() {
    tdx_enc_log "Preparing and checking system (caam)..."

    if ! modprobe trusted source=caam; then
        tdx_enc_exit_error "Error loading trusted module!"
    fi
}

# TPM: prepare system
tdx_enc_key_prepare_tpm() {
    tdx_enc_log "Preparing and checking system (tpm)..."

    if ! modprobe trusted source=tpm; then
        tdx_enc_exit_error "Error loading trusted module!"
    fi

    if [ ! -c /dev/tpm0 ]; then
        tdx_enc_exit_error "TPM device node (/dev/tpm0) not found!"
    fi

    if ! echo "deadbeef" | tpm2_hash >/dev/null; then
        tdx_enc_exit_error "Hash calculation via tpm2_hash failed. TPM device might not be functional!"
    fi
}

# TEE: prepare system
tdx_enc_key_prepare_tee() {
    tdx_enc_log "Preparing and checking system (tee)..."

    if [ ! -c /dev/tee0 ]; then
        tdx_enc_exit_error "TEE device node not found!"
    fi

    if ! pgrep "tee-supplicant" > /dev/null; then
        tdx_enc_exit_error "TEE supplicant daemon not running!"
    fi

    if ! modprobe trusted source=tee; then
        tdx_enc_exit_error "Error loading trusted module!"
    fi
}
