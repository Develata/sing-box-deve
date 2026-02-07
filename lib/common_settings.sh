#!/usr/bin/env bash

load_settings() {
  if [[ "$SETTINGS_INITIALIZED" == "true" ]]; then
    return 0
  fi

  mkdir -p "$SBD_CONFIG_DIR" >/dev/null 2>&1 || true

  if [[ ! -f "$SBD_SETTINGS_FILE" && -f "${SBD_CONFIG_DIR}/lang" ]]; then
    local legacy_lang
    legacy_lang="$(tr -d '[:space:]' < "${SBD_CONFIG_DIR}/lang" 2>/dev/null || true)"
    [[ "$legacy_lang" == "zh" || "$legacy_lang" == "en" ]] || legacy_lang="en"
    LANG_CODE="$legacy_lang"
    save_settings
    rm -f "${SBD_CONFIG_DIR}/lang"
  fi

  if [[ -f "$SBD_SETTINGS_FILE" ]]; then
    local line
    line="$(head -n1 "$SBD_SETTINGS_FILE" 2>/dev/null || true)"
    if [[ -n "$line" ]]; then
      local IFS=';'
      local kv
      read -r -a _pairs <<< "$line"
      for kv in "${_pairs[@]}"; do
        local key="${kv%%=*}"
        local val="${kv#*=}"
        case "$key" in
          lang) [[ "$val" == "zh" || "$val" == "en" ]] && LANG_CODE="$val" ;;
          auto_yes) [[ "$val" == "true" || "$val" == "false" ]] && AUTO_YES="$val" ;;
          update_channel) [[ -n "$val" ]] && UPDATE_CHANNEL="$val" ;;
        esac
      done
    fi
  fi

  SETTINGS_INITIALIZED="true"
}

save_settings() {
  mkdir -p "$SBD_CONFIG_DIR" >/dev/null 2>&1 || true
  if [[ -w "$SBD_CONFIG_DIR" || "${EUID}" -eq 0 ]]; then
    printf 'lang=%s;auto_yes=%s;update_channel=%s\n' "$LANG_CODE" "$AUTO_YES" "$UPDATE_CHANNEL" > "$SBD_SETTINGS_FILE"
  fi
}

set_setting() {
  local key="$1"
  local value="$2"
  load_settings
  case "$key" in
    lang)
      [[ "$value" == "zh" || "$value" == "en" ]] || die "Invalid lang: $value"
      LANG_CODE="$value"
      ;;
    auto_yes)
      [[ "$value" == "true" || "$value" == "false" ]] || die "Invalid auto_yes: $value"
      AUTO_YES="$value"
      ;;
    update_channel)
      [[ -n "$value" ]] || die "update_channel cannot be empty"
      UPDATE_CHANNEL="$value"
      ;;
    *)
      die "Unknown setting key: $key"
      ;;
  esac
  save_settings
}

show_settings() {
  load_settings
  printf 'lang=%s;auto_yes=%s;update_channel=%s\n' "$LANG_CODE" "$AUTO_YES" "$UPDATE_CHANNEL"
}

init_i18n() {
  load_settings

  if [[ -f "$SBD_SETTINGS_FILE" ]]; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    LANG_CODE="en"
    save_settings
    return 0
  fi

  local choose
  echo "Select language / 选择语言"
  echo "1) 中文"
  echo "2) English"
  read -r -p "Choose [1/2] (default: 1): " choose
  case "${choose:-1}" in
    1) LANG_CODE="zh" ;;
    2) LANG_CODE="en" ;;
    *) LANG_CODE="zh" ;;
  esac

  save_settings
}
