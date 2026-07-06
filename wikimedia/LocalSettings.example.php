<?php
# ---------------------------------------------------------------------------
# LocalSettings.php — MediaWiki configuration
#
# Copy this file to LocalSettings.php and fill in the values, OR generate
# it via the web installer (http://localhost:8080) and then add the
# getenv() calls to keep secrets out of version control.
#
# Reference: https://www.mediawiki.org/wiki/Manual:LocalSettings.php
# ---------------------------------------------------------------------------

## ---- Secrets (read from environment, never hard-code here) ----------------
$wgSecretKey  = getenv('MEDIAWIKI_SECRET_KEY')  ?: '';
$wgUpgradeKey = getenv('MEDIAWIKI_UPGRADE_KEY') ?: '';

## ---- Database connection ---------------------------------------------------
$wgDBtype    = 'mysql';   # MariaDB is compatible with the 'mysql' driver
$wgDBserver  = getenv('MEDIAWIKI_DB_HOST')     ?: 'database';
$wgDBname    = getenv('MEDIAWIKI_DB_NAME')     ?: 'my_wiki';
$wgDBuser    = getenv('MEDIAWIKI_DB_USER')     ?: 'wikiuser';
$wgDBpassword = getenv('MEDIAWIKI_DB_PASSWORD') ?: '';

# Keep the same table options used during installation.
$wgDBTableOptions = 'ENGINE=InnoDB, DEFAULT CHARSET=binary';

## ---- Site identity ---------------------------------------------------------
$wgSitename   = 'My Wiki';
$wgMetaNamespace = 'My_Wiki';

# $wgServer must match the URL users actually type in their browser.
# Using getenv() lets you switch between dev and prod without editing this file.
$wgServer = getenv('MW_SITE_SERVER') ?: 'http://localhost:8080';

$wgScriptPath   = '';          # MediaWiki installed at the document root
$wgArticlePath  = '/wiki/$1';  # Short URLs (Apache rewrite is already enabled)

## ---- File uploads ----------------------------------------------------------
$wgEnableUploads = true;
$wgUploadDirectory = '/var/www/html/images';  # Persist this volume!
$wgUploadPath      = '/images';

# Optional: restrict allowed file types
# $wgFileExtensions = [ 'png', 'gif', 'jpg', 'jpeg', 'webp', 'svg', 'pdf' ];

## ---- Caching (APCu is pre-installed in the official mediawiki image) -------
$wgMainCacheType    = CACHE_ACCEL;  # APCu for main object cache
$wgMessageCacheType = CACHE_ACCEL;
$wgParserCacheType  = CACHE_DB;     # Parser cache in the database

## ---- Email -----------------------------------------------------------------
# Set these if you want MediaWiki to send password-reset emails etc.
$wgEnableEmail      = false;
$wgEnableUserEmail  = false;
# $wgSMTP = [
#     'host'     => 'smtp.example.com',
#     'IDHost'   => 'example.com',
#     'port'     => 587,
#     'auth'     => true,
#     'username' => 'wiki@example.com',
#     'password' => getenv('SMTP_PASSWORD'),
# ];

## ---- Logo ------------------------------------------------------------------
$wgLogos = [
    '1x' => "$wgResourceBasePath/resources/assets/change-your-logo.svg",
];

## ---- Skins -----------------------------------------------------------------
wfLoadSkin( 'Vector' );      # Default Wikipedia-style skin (bundled)
wfLoadSkin( 'MonoBook' );    # Classic Wikipedia skin (bundled)
$wgDefaultSkin = 'vector';

## ---- Extensions ------------------------------------------------------------
# Bundled extensions (enable as needed):
wfLoadExtension( 'ParserFunctions' );
wfLoadExtension( 'WikiEditor' );       # Toolbar for wikitext editing
# wfLoadExtension( 'VisualEditor' );   # Requires Parsoid (built into MW 1.35+)
# wfLoadExtension( 'Cite' );
# wfLoadExtension( 'ImageMap' );
# wfLoadExtension( 'SyntaxHighlight_GeSHi' );  # Requires Python 3 (bundled)

## ---- Permissions -----------------------------------------------------------
# Sensible defaults: only logged-in users can edit, anyone can read.
# For a private wiki, add: $wgGroupPermissions['*']['read'] = false;
$wgGroupPermissions['*']['createaccount'] = false;  # Disable self-registration
$wgGroupPermissions['*']['edit']          = false;  # Read-only for anonymous users

## ---- Maintenance -----------------------------------------------------------
# Run database updates after upgrading MediaWiki:
#   docker compose exec mediawiki php /var/www/html/maintenance/update.php

## ---- End of LocalSettings.php ---------------------------------------------
