#!/usr/bin/env bash

sbd_archive_site_dir() {
  printf '%s\n' "${SBD_ARCHIVE_SITE_DIR:-${SBD_INSTALL_DIR}/archive-gateway}"
}

sbd_archive_site_owner() {
  local owner_file="${SBD_DATA_DIR}/archive_site_owner"
  local owner=""
  if [[ -f "$owner_file" ]]; then
    owner="$(tr -dc 'a-z0-9' < "$owner_file" | head -c 7)"
  fi
  if [[ ${#owner} -lt 6 ]]; then
    if command -v openssl >/dev/null 2>&1; then
      owner="$(openssl rand -hex 4 | tr -dc 'a-z0-9' | head -c 7)"
    else
      owner="$(rand_hex_8 | tr -dc 'a-z0-9' | head -c 7)"
    fi
    printf '%s\n' "$owner" > "$owner_file"
    chmod 600 "$owner_file" 2>/dev/null || true
  fi
  printf '%s\n' "$owner"
}

sbd_write_archive_gateway_site() {
  local site_dir owner now style_file manifest_file checksums_file
  site_dir="$(sbd_archive_site_dir)"
  export SBD_ARCHIVE_SITE_DIR="$site_dir"
  owner="$(sbd_archive_site_owner)"
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mkdir -p "$site_dir/assets" "$site_dir/files"

  style_file="${site_dir}/assets/style.css"
  cat > "$style_file" <<'EOF'
:root{color-scheme:light dark;--bg:#f7f7f3;--fg:#23241f;--muted:#6b6d63;--card:#ffffff;--line:#dedfd4;--link:#315c9b}@media(prefers-color-scheme:dark){:root{--bg:#171814;--fg:#eceee5;--muted:#a5a89c;--card:#20221d;--line:#383b33;--link:#8db6ff}}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.65 ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.wrap{max-width:880px;margin:0 auto;padding:48px 22px}header{border-bottom:1px solid var(--line);margin-bottom:28px}.brand{font-size:13px;letter-spacing:.16em;text-transform:uppercase;color:var(--muted)}h1{font-size:34px;line-height:1.2;margin:12px 0 14px}h2{font-size:21px;margin-top:30px}.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:18px 20px;margin:16px 0}.muted{color:var(--muted)}a{color:var(--link);text-decoration:none}a:hover{text-decoration:underline}code{background:rgba(127,127,127,.14);padding:.1em .35em;border-radius:5px}nav a{margin-right:16px}footer{border-top:1px solid var(--line);margin-top:36px;padding-top:18px;color:var(--muted);font-size:14px}ul{padding-left:22px}.pill{display:inline-block;border:1px solid var(--line);border-radius:999px;padding:3px 9px;margin:3px;color:var(--muted);font-size:13px}
EOF

  cat > "${site_dir}/index.html" <<EOF
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${owner} archive gateway</title><link rel="stylesheet" href="/assets/style.css"><link rel="icon" href="/favicon.ico"></head><body><main class="wrap"><header><div class="brand">${owner}</div><h1>Computer Materials Archive Gateway</h1><p class="muted">A small static gateway for selected computer materials, index metadata, and temporary archive synchronization.</p><nav><a href="/archive.html">Archive</a><a href="/knowledge.html">Knowledge</a><a href="/status.html">Status</a><a href="/about.html">About</a><a href="/files/manifest.json">Manifest</a></nav></header><section class="card"><h2>Public index</h2><p>This endpoint only keeps a compact public index. Large artifacts are stored off-site or rotated through private synchronization workflows and are not listed here.</p><p><span class="pill">systems</span><span class="pill">networking</span><span class="pill">programming</span><span class="pill">notes</span><span class="pill">checksums</span></p></section><section class="card"><h2>Access policy</h2><p>Private collections are not exposed on this mirror. Public pages contain only general computer-material metadata and lightweight notes.</p></section><footer>Owner: ${owner}. Last metadata refresh: ${now}.</footer></main></body></html>
EOF

  cat > "${site_dir}/archive.html" <<EOF
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Archive index</title><link rel="stylesheet" href="/assets/style.css"></head><body><main class="wrap"><header><div class="brand">${owner}</div><h1>Archive Index</h1><nav><a href="/">Home</a><a href="/status.html">Status</a></nav></header><section class="card"><h2>Computer materials</h2><ul><li>Operating system notes and package metadata</li><li>Network service configuration references</li><li>Programming language snippets and small examples</li><li>Checksum manifests for rotated artifacts</li></ul></section><section class="card"><h2>Large artifacts</h2><p>Large files are not retained in the public web root. This gateway may be used for temporary transfer, verification, or cross-region access by the maintainer.</p></section><footer>Static archive gateway. Public metadata only.</footer></main></body></html>
EOF

  cat > "${site_dir}/knowledge.html" <<EOF
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Knowledge notes</title><link rel="stylesheet" href="/assets/style.css"></head><body><main class="wrap"><header><div class="brand">${owner}</div><h1>Knowledge Notes</h1><nav><a href="/">Home</a><a href="/archive.html">Archive</a><a href="/status.html">Status</a></nav></header><section class="card"><h2>Topics</h2><ul><li>Algorithm sketches and data-structure summaries</li><li>Unix service operation notes</li><li>Network protocol reading lists</li><li>Compiler, runtime, and storage references</li></ul></section><section class="card"><h2>Format</h2><p>Entries are maintained as small text indexes, checksum notes, and links to off-site archival locations.</p></section><footer>General computer-material notes only.</footer></main></body></html>
EOF

  cat > "${site_dir}/about.html" <<EOF
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>About this gateway</title><link rel="stylesheet" href="/assets/style.css"></head><body><main class="wrap"><header><div class="brand">${owner}</div><h1>About</h1><nav><a href="/">Home</a><a href="/archive.html">Archive</a><a href="/status.html">Status</a></nav></header><section class="card"><p>This is a low-storage static gateway for public computer-material metadata. It intentionally avoids personal profiles, private account pages, and fake login surfaces.</p></section><section class="card"><h2>Storage model</h2><p>Public storage is limited to indexes and verification files. Larger datasets are rotated through private or off-site synchronization paths.</p></section><footer>Contact details are intentionally not published on this static mirror.</footer></main></body></html>
EOF

  cat > "${site_dir}/status.html" <<EOF
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Mirror status</title><link rel="stylesheet" href="/assets/style.css"></head><body><main class="wrap"><header><div class="brand">${owner}</div><h1>Mirror Status</h1><nav><a href="/">Home</a><a href="/archive.html">Archive</a></nav></header><section class="card"><h2>Status</h2><p><strong>Mode:</strong> partial static gateway</p><p><strong>Public storage:</strong> metadata only</p><p><strong>Large artifacts:</strong> off-site / private synchronization</p><p><strong>Updated:</strong> ${now}</p></section><footer>No directory listing is provided.</footer></main></body></html>
EOF

  cat > "${site_dir}/404.html" <<EOF
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Not found</title><link rel="stylesheet" href="/assets/style.css"></head><body><main class="wrap"><header><div class="brand">${owner}</div><h1>Not found</h1></header><section class="card"><p>The requested public archive entry is not available on this static gateway.</p><p><a href="/">Return to index</a></p></section></main></body></html>
EOF

  cat > "${site_dir}/robots.txt" <<EOF
User-agent: *
Allow: /
Disallow: /private
Disallow: /tmp
Sitemap: /sitemap.xml
EOF

  cat > "${site_dir}/sitemap.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>/</loc></url><url><loc>/archive.html</loc></url><url><loc>/knowledge.html</loc></url><url><loc>/status.html</loc></url><url><loc>/about.html</loc></url></urlset>
EOF

  printf '\000\000\001\000\001\000\001\000\001\000\000\000\001\000\040\000\070\000\000\000\026\000\000\000' > "${site_dir}/favicon.ico"
  printf '\050\000\000\000\001\000\000\000\002\000\000\000\001\000\040\000\000\000\000\000\004\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\061\134\233\377' >> "${site_dir}/favicon.ico"

  manifest_file="${site_dir}/files/manifest.json"
  cat > "$manifest_file" <<EOF
{"owner":"${owner}","type":"computer-materials-archive-gateway","public_storage":"metadata-only","large_artifacts":"off-site-or-private-sync","updated":"${now}"}
EOF

  checksums_file="${site_dir}/files/checksums.txt"
  (cd "$site_dir" && sha256sum index.html archive.html knowledge.html status.html about.html 404.html favicon.ico assets/style.css files/manifest.json > "$checksums_file")
  printf 'SBD_ARCHIVE_SITE_DIR=%s\n' "$site_dir" > "${SBD_DATA_DIR}/archive_site.env"
  log_info "$(msg "已生成归档网关静态站: ${site_dir}" "Archive gateway site generated: ${site_dir}")"
}
