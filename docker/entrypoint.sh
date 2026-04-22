#!/usr/bin/env bash

set -Eeuo pipefail

readonly VS_USER="vintagestory"

log() {
  printf '[entrypoint] %s\n' "$*" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

require_numeric_env() {
  local name="$1"
  local value="${!name:-}"

  [[ -z "$value" ]] && return 0
  [[ "$value" =~ ^[0-9]+$ ]] || die "$name must be numeric, got '$value'"
}

to_json_bool() {
  case "$(lower "$1")" in
    1|true|yes|on)
      printf 'true\n'
      ;;
    0|false|no|off)
      printf 'false\n'
      ;;
    *)
      return 1
      ;;
  esac
}

read_default_version() {
  tr -d '[:space:]' < /opt/bootstrap/default-vs-version
}

prepare_runtime_user() {
  if [[ "$(id -u)" -ne 0 ]]; then
    return 0
  fi

  require_numeric_env PUID
  require_numeric_env PGID

  local current_uid current_gid
  current_uid="$(id -u "$VS_USER")"
  current_gid="$(id -g "$VS_USER")"

  if [[ "${PGID}" != "$current_gid" ]]; then
    groupmod -o -g "${PGID}" "$VS_USER"
  fi

  if [[ "${PUID}" != "$current_uid" ]]; then
    usermod -o -u "${PUID}" -g "${PGID}" "$VS_USER"
  fi

  mkdir -p \
    "${VS_ROOT}" \
    "${VS_INSTALL_PATH}" \
    "${VS_DATA_PATH}" \
    "${VS_DATA_PATH}/Logs" \
    "${VS_DATA_PATH}/Mods" \
    "${VS_DATA_PATH}/Saves"
}

switch_to_runtime_user() {
  [[ "$(id -u)" -eq 0 ]] || return 0

  chown -R "${VS_USER}:${VS_USER}" "${VS_ROOT}" "/home/${VS_USER}"
  exec env VS_RUNTIME_USER_READY=1 gosu "${VS_USER}:${VS_USER}" "$0" run "$@"
}

resolve_download_url() {
  if [[ -n "${VS_DOWNLOAD_URL:-}" ]]; then
    printf '%s\n' "${VS_DOWNLOAD_URL}"
    return 0
  fi

  local version="${VS_VERSION:-}"
  if [[ -z "$version" ]]; then
    version="$(read_default_version)"
  fi

  [[ -n "$version" ]] || die "Unable to resolve a Vintage Story version"
  printf 'https://cdn.vintagestory.at/gamefiles/stable/vs_server_linux-x64_%s.tar.gz\n' "$version"
}

has_explicit_source_request() {
  [[ -n "${VS_DOWNLOAD_URL:-}" || -n "${VS_VERSION:-}" ]]
}

install_server() {
  mkdir -p "${VS_INSTALL_PATH}" "${VS_DATA_PATH}" "${VS_DATA_PATH}/Logs" "${VS_DATA_PATH}/Mods" "${VS_DATA_PATH}/Saves"

  local download_url marker
  download_url="$(resolve_download_url)"
  marker="${VS_INSTALL_PATH}/.install-source"

  if [[ -x "${VS_INSTALL_PATH}/VintagestoryServer" ]]; then
    if [[ -f "$marker" ]]; then
      local installed_source
      installed_source="$(cat "$marker")"
      if [[ "$installed_source" == "$download_url" ]]; then
        log "Vintage Story server already installed from ${download_url}"
        return 0
      fi

      log "Requested source differs from installed source. Reinstalling from ${download_url}"
    else
      if ! has_explicit_source_request; then
        log "Vintage Story server already present with unknown source. Keeping existing install."
        return 0
      fi

      log "Vintage Story server already present with unknown source. Reinstalling from explicitly requested source ${download_url}"
    fi
  fi

  local tmp_dir archive extract_dir
  tmp_dir="$(mktemp -d)"
  archive="${tmp_dir}/server.tar.gz"
  extract_dir="${tmp_dir}/extract"
  mkdir -p "$extract_dir"

  log "Downloading Vintage Story server from ${download_url}"
  curl --fail --location --retry 5 --retry-delay 2 --output "$archive" "$download_url"
  tar -xzf "$archive" -C "$extract_dir"

  find "${VS_INSTALL_PATH}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -a "${extract_dir}/." "${VS_INSTALL_PATH}/"
  printf '%s\n' "$download_url" > "$marker"
  rm -rf "$tmp_dir"
}

append_string_setting() {
  local env_name="$1"
  local jq_path="$2"
  local arg_name="$3"
  local value="${!env_name:-}"

  [[ -n "$value" ]] || return 0
  jq_args+=(--arg "$arg_name" "$value")
  jq_filter+=" | ${jq_path} = \$${arg_name}"
}

append_int_setting() {
  local env_name="$1"
  local jq_path="$2"
  local arg_name="$3"
  local value="${!env_name:-}"

  [[ -n "$value" ]] || return 0
  [[ "$value" =~ ^[0-9]+$ ]] || die "$env_name must be numeric, got '$value'"
  jq_args+=(--argjson "$arg_name" "$value")
  jq_filter+=" | ${jq_path} = \$${arg_name}"
}

append_bool_setting() {
  local env_name="$1"
  local jq_path="$2"
  local arg_name="$3"
  local raw_value="${!env_name:-}"

  [[ -n "$raw_value" ]] || return 0

  local bool_value
  bool_value="$(to_json_bool "$raw_value")" || die "$env_name must be a boolean, got '$raw_value'"

  jq_args+=(--argjson "$arg_name" "$bool_value")
  jq_filter+=" | ${jq_path} = \$${arg_name}"
}

append_whitelist_mode_setting() {
  local raw_value="${VS_WHITELIST_MODE:-}"
  local normalized

  [[ -n "$raw_value" ]] || return 0

  normalized="$(lower "$raw_value")"
  case "$normalized" in
    off|on|default)
      jq_args+=(--arg whitelist_mode "$normalized")
      jq_filter+=' | .WhitelistMode = $whitelist_mode'
      ;;
    0|1|2)
      jq_args+=(--argjson whitelist_mode "$normalized")
      jq_filter+=' | .WhitelistMode = $whitelist_mode'
      ;;
    *)
      die "VS_WHITELIST_MODE must be one of: off, on, default, 0, 1, 2; got '$raw_value'"
      ;;
  esac
}

configure_server() {
  local config_path="${VS_DATA_PATH}/serverconfig.json"
  [[ -f "$config_path" ]] || die "Missing ${config_path}"

  jq_args=(
    --arg mods_path "${VS_DATA_PATH}/Mods"
  )

  jq_filter='
    .ModPaths = (
      ["Mods", $mods_path]
      + ((.ModPaths // []) | map(select(. != "Mods" and . != $mods_path)))
    )
  '

  append_string_setting VS_SERVER_NAME '.ServerName' 'server_name'
  append_string_setting VS_SERVER_DESCRIPTION '.ServerDescription' 'server_description'
  append_string_setting VS_WELCOME_MESSAGE '.WelcomeMessage' 'welcome_message'
  append_string_setting VS_SERVER_LANGUAGE '.ServerLanguage' 'server_language'
  append_string_setting VS_PASSWORD '.Password' 'server_password'
  append_string_setting VS_BIND_IP '.Ip' 'bind_ip'
  append_string_setting VS_WORLD_NAME '.WorldConfig.WorldName' 'world_name'
  append_string_setting VS_SAVE_FILE '.WorldConfig.SaveFileLocation' 'save_file'

  append_int_setting VS_PORT '.Port' 'server_port'
  append_int_setting VS_MAX_CLIENTS '.MaxClients' 'max_clients'

  append_bool_setting VS_ADVERTISE_SERVER '.AdvertiseServer' 'advertise_server'
  append_bool_setting VS_VERIFY_PLAYER_AUTH '.VerifyPlayerAuth' 'verify_player_auth'
  append_bool_setting VS_PASS_TIME_WHEN_EMPTY '.PassTimeWhenEmpty' 'pass_time_when_empty'
  append_bool_setting VS_ALLOW_PVP '.AllowPvP' 'allow_pvp'
  append_bool_setting VS_ALLOW_FIRE_SPREAD '.AllowFireSpread' 'allow_fire_spread'
  append_bool_setting VS_ALLOW_FALLING_BLOCKS '.AllowFallingBlocks' 'allow_falling_blocks'
  append_whitelist_mode_setting

  local tmp_config
  tmp_config="$(mktemp)"
  jq "${jq_args[@]}" "$jq_filter" "$config_path" > "$tmp_config"
  mv "$tmp_config" "$config_path"
}

bootstrap_config() {
  local config_path="${VS_DATA_PATH}/serverconfig.json"
  if [[ -f "$config_path" ]]; then
    configure_server
    return 0
  fi

  local timeout_seconds="${VS_BOOTSTRAP_TIMEOUT:-60}"
  [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || die "VS_BOOTSTRAP_TIMEOUT must be numeric, got '$timeout_seconds'"

  local bootstrap_log="${VS_DATA_PATH}/Logs/bootstrap.log"

  log "Generating initial server configuration"
  "${VS_INSTALL_PATH}/VintagestoryServer" --dataPath "${VS_DATA_PATH}" "$@" >"$bootstrap_log" 2>&1 &
  local bootstrap_pid=$!

  local waited=0
  while (( waited < timeout_seconds )); do
    if [[ -f "$config_path" ]]; then
      break
    fi

    if ! kill -0 "$bootstrap_pid" 2>/dev/null; then
      sed -n '1,120p' "$bootstrap_log" >&2 || true
      die "Bootstrap server exited before generating ${config_path}"
    fi

    sleep 1
    (( waited += 1 ))
  done

  if [[ ! -f "$config_path" ]]; then
    kill -TERM "$bootstrap_pid" 2>/dev/null || true
    wait "$bootstrap_pid" || true
    die "Timed out waiting for ${config_path}"
  fi

  configure_server

  kill -TERM "$bootstrap_pid" 2>/dev/null || true
  wait "$bootstrap_pid" || true
}

run_server() {
  log "Starting Vintage Story server"
  exec "${VS_INSTALL_PATH}/VintagestoryServer" --dataPath "${VS_DATA_PATH}" "$@"
}

main() {
  if [[ "${1:-run}" != "run" ]]; then
    exec "$@"
  fi

  shift || true

  local server_args=()
  if [[ -n "${VS_SERVER_ARGS:-}" ]]; then
    read -r -a server_args <<<"${VS_SERVER_ARGS}"
  fi
  server_args+=("$@")

  prepare_runtime_user

  if [[ "$(id -u)" -eq 0 && "${VS_RUNTIME_USER_READY:-0}" != "1" ]]; then
    install_server
    switch_to_runtime_user "${server_args[@]}"
  fi

  if [[ "${VS_RUNTIME_USER_READY:-0}" != "1" ]]; then
    install_server
  fi

  bootstrap_config "${server_args[@]}"
  run_server "${server_args[@]}"
}

main "$@"
