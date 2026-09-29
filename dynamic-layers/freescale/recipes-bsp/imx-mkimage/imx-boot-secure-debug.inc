# Secure debug is enabled only if both tdx-secure-debug class is inherited and TDX_SECURE_DEBUG_ENABLE="1"
TDX_SECURE_DEBUG_ENABLE_INTERNAL = "0"
TDX_SECURE_DEBUG_ENABLE_INTERNAL:tdx-secure-debug = "${TDX_SECURE_DEBUG_ENABLE}"

# Make sure fuse-cmds.txt is regenerated if a secure debug authentication key changes
do_compile[file-checksums] += "${@ d.getVar('TDX_SECURE_DEBUG_KEY_FILE') + ':True' if d.getVar('TDX_SECURE_DEBUG_KEY_FILE') and d.getVar('TDX_SECURE_DEBUG_ENABLE_INTERNAL') == '1' and d.getVar('TDX_SECURE_DEBUG_MODE') == 'authenticated' and d.getVar('TDX_SECURE_DEBUG_SJC_DISABLE') != '1' else ''}"
do_compile[file-checksums] += "${@ d.getVar('TDX_SECURE_DEBUG_TZ_KEY_FILE') + ':True' if d.getVar('TDX_SECURE_DEBUG_TZ_KEY_FILE') and d.getVar('TDX_SECURE_DEBUG_ENABLE_INTERNAL') == '1' and d.getVar('TDX_SECURE_DEBUG_MODE') == 'authenticated' and d.getVar('TDX_SECURE_DEBUG_SJC_DISABLE') != '1' else ''}"
