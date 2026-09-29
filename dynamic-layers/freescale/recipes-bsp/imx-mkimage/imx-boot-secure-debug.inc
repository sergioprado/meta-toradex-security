SRC_URI:append = "\
    file://ele-dc.yaml.in \
    file://ele-dat.yaml.in \
"

# Secure debug is enabled only if both tdx-secure-debug class is inherited and TDX_SECURE_DEBUG_ENABLE="1"
TDX_SECURE_DEBUG_ENABLE_INTERNAL = "0"
TDX_SECURE_DEBUG_ENABLE_INTERNAL:tdx-secure-debug = "${TDX_SECURE_DEBUG_ENABLE}"

# Make sure fuse-cmds.txt is regenerated if a secure debug authentication key changes
do_compile[file-checksums] += "${@ d.getVar('TDX_SECURE_DEBUG_KEY_FILE') + ':True' if d.getVar('TDX_SECURE_DEBUG_KEY_FILE') and d.getVar('TDX_SECURE_DEBUG_ENABLE_INTERNAL') == '1' and d.getVar('TDX_SECURE_DEBUG_MODE') == 'authenticated' and d.getVar('TDX_SECURE_DEBUG_SJC_DISABLE') != '1' else ''}"
do_compile[file-checksums] += "${@ d.getVar('TDX_SECURE_DEBUG_TZ_KEY_FILE') + ':True' if d.getVar('TDX_SECURE_DEBUG_TZ_KEY_FILE') and d.getVar('TDX_SECURE_DEBUG_ENABLE_INTERNAL') == '1' and d.getVar('TDX_SECURE_DEBUG_MODE') == 'authenticated' and d.getVar('TDX_SECURE_DEBUG_SJC_DISABLE') != '1' else ''}"

# Enabled when authenticated debug is used on ELE-based devices
TDX_SECURE_DEBUG_ELE_AUTH_INTERNAL = "${@ '1' if d.getVar('TDX_SECURE_DEBUG_ENABLE_INTERNAL') == '1' and d.getVar('TDX_SECURE_DEBUG_ELE_SPSDK_FAMILY') and d.getVar('TDX_SECURE_DEBUG_MODE') == 'authenticated' and d.getVar('TDX_SECURE_DEBUG_ELE_JTAG_DISABLE') != '1' else '0'}"

# return the SRK private key path or PKCS#11 URI (if HSM is enabled)
def tdx_secure_debug_srk_signer(d):
    import os
    import urllib.parse
    if d.getVar('TDX_SECURE_DEBUG_ELE_AUTH_INTERNAL') != '1':
        return ''
    if d.getVar('TDX_SIGNED_HSM') != '1':
        name = os.path.basename(make_srk_cert_name(d, '')).replace('_crt.pem', '_key.pem')
        return os.path.join(d.getVar('TDX_IMX_HAB_CST_DIR'), 'keys', name)
    else:
        uri = d.getVar('TDX_IMX_HAB_CST_SRK_CERT') or ''
        attrs = dict(a.split('=', 1) for a in uri.split(':', 1)[-1].split(';') if '=' in a)
        if not uri.startswith('pkcs11:') or 'token' not in attrs or 'object' not in attrs:
            bb.fatal("TDX_IMX_HAB_CST_SRK_CERT must be a PKCS#11 URI with 'token' and "
                     "'object' attributes when TDX_SIGNED_HSM=1 (got '%s')." % uri)
        return 'type=pkcs11;so_path=%s;user_pin=$SPSDK_HSM_PIN;token_label=%s;key_label=%s' % (
            d.getVar('TDX_SIGNED_HSM_PKCS11_MODULE_PATH'),
            urllib.parse.unquote(attrs['token']), urllib.parse.unquote(attrs['object']))

# generate the SPSDK configuration files (dc.yaml and dat.yaml) for authenticated debug
secure_debug_ele_templates() {
    rm -rf ${WORKDIR}/secure-debug
    if [ "${TDX_SECURE_DEBUG_ELE_AUTH_INTERNAL}" != "1" ]; then
        return
    fi

    cc_socu=$(echo "${TDX_SECURE_DEBUG_ELE_DC_CC_SOCU}" | tr 'A-FX' 'a-fx')
    cc_socu=$(printf '0x%08X' "0x${cc_socu#0x}")
    uuid=$(echo "${TDX_SECURE_DEBUG_ELE_DC_UUID}" | tr 'A-FX' 'a-fx')
    uuid=${uuid#0x}
    srk_ca="false"
    if [ "${TDX_IMX_HAB_CST_SRK_CA}" = "1" ]; then
        srk_ca="true"
    fi

    srk_cert="${@make_srk_cert_name(d, d.getVar('TDX_IMX_HAB_CST_CERTS_DIR'))}"
    srk_certs_dir=${srk_cert%/*}
    srk_cert_suffix=${srk_cert##*/SRK[1-4]_}

    # generate the configuration files from the templates
    install -d ${WORKDIR}/secure-debug
    for tmpl in dc dat; do
        sed -e 's|@FAMILY@|${TDX_SECURE_DEBUG_ELE_SPSDK_FAMILY}|' \
            -e "s|@CC_SOCU@|${cc_socu}|" \
            -e "s|@UUID@|${uuid:-REPLACE_WITH_DEVICE_UUID}|" \
            -e 's|@DCK_KEY@|${TDX_SECURE_DEBUG_ELE_DCK_KEY}|' \
            -e 's|@SRK_SIGNER@|${@tdx_secure_debug_srk_signer(d)}|' \
            -e "s|@SRK_ID@|$(expr ${TDX_IMX_HAB_CST_SRK_INDEX} - 1)|" \
            -e "s|@SRK_CA@|${srk_ca}|" \
            -e "s|@SRK_CERT_1@|${srk_certs_dir}/SRK1_${srk_cert_suffix}|" \
            -e "s|@SRK_CERT_2@|${srk_certs_dir}/SRK2_${srk_cert_suffix}|" \
            -e "s|@SRK_CERT_3@|${srk_certs_dir}/SRK3_${srk_cert_suffix}|" \
            -e "s|@SRK_CERT_4@|${srk_certs_dir}/SRK4_${srk_cert_suffix}|" \
            ${WORKDIR}/ele-${tmpl}.yaml.in > ${WORKDIR}/secure-debug/${tmpl}.yaml
    done
}
do_compile[postfuncs] += "secure_debug_ele_templates"

do_deploy:append() {
    if [ -d ${WORKDIR}/secure-debug ]; then
        install -d ${DEPLOYDIR}/secure-debug
        install -m 0644 ${WORKDIR}/secure-debug/*.yaml ${DEPLOYDIR}/secure-debug
    fi
}
