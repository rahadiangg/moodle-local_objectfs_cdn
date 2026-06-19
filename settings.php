<?php
// Admin settings for local_objectfs_cdn.
// In the Helm deployment these are written by moosh during the configure Job;
// this page exists for completeness, defaults, and manual/admin-UI use.

defined('MOODLE_INTERNAL') || die();

if ($hassiteconfig) {
    $settings = new admin_settingpage(
        'local_objectfs_cdn',
        get_string('pluginname', 'local_objectfs_cdn')
    );
    $ADMIN->add('localplugins', $settings);

    $settings->add(new admin_setting_configcheckbox(
        'local_objectfs_cdn/enabled',
        get_string('enabled', 'local_objectfs_cdn'),
        get_string('enabled_desc', 'local_objectfs_cdn'),
        0
    ));

    $settings->add(new admin_setting_configtext(
        'local_objectfs_cdn/cdndomain',
        get_string('cdndomain', 'local_objectfs_cdn'),
        get_string('cdndomain_desc', 'local_objectfs_cdn'),
        '',
        PARAM_HOST
    ));

    $settings->add(new admin_setting_configselect(
        'local_objectfs_cdn/cdnscheme',
        get_string('cdnscheme', 'local_objectfs_cdn'),
        get_string('cdnscheme_desc', 'local_objectfs_cdn'),
        'https',
        ['https' => 'https', 'http' => 'http']
    ));

    // Only Method A for now; extensible to other CDN token schemes later.
    $settings->add(new admin_setting_configselect(
        'local_objectfs_cdn/signingmethod',
        get_string('signingmethod', 'local_objectfs_cdn'),
        get_string('signingmethod_desc', 'local_objectfs_cdn'),
        'tokenA',
        ['tokenA' => get_string('signingmethod:tokenA', 'local_objectfs_cdn')]
    ));

    // Hash algorithm — must match the CDN's "Encryption Algorithm" setting.
    $settings->add(new admin_setting_configselect(
        'local_objectfs_cdn/algorithm',
        get_string('algorithm', 'local_objectfs_cdn'),
        get_string('algorithm_desc', 'local_objectfs_cdn'),
        'sha256',
        ['sha256' => 'SHA256', 'md5' => 'MD5']
    ));

    $settings->add(new admin_setting_configpasswordunmask(
        'local_objectfs_cdn/signingkey',
        get_string('signingkey', 'local_objectfs_cdn'),
        get_string('signingkey_desc', 'local_objectfs_cdn'),
        ''
    ));

    $settings->add(new admin_setting_configtext(
        'local_objectfs_cdn/authparam',
        get_string('authparam', 'local_objectfs_cdn'),
        get_string('authparam_desc', 'local_objectfs_cdn'),
        'auth_key',
        PARAM_ALPHANUMEXT
    ));

    $settings->add(new admin_setting_configtext(
        'local_objectfs_cdn/validity',
        get_string('validity', 'local_objectfs_cdn'),
        get_string('validity_desc', 'local_objectfs_cdn'),
        '1800',
        PARAM_INT
    ));

    $settings->add(new admin_setting_configtext(
        'local_objectfs_cdn/uid',
        get_string('uid', 'local_objectfs_cdn'),
        get_string('uid_desc', 'local_objectfs_cdn'),
        '0',
        PARAM_ALPHANUMEXT
    ));
}
