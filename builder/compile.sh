#!/bin/bash
set -eo pipefail
source $(dirname $0)/config/paths.sh

# Helper functions
function echo_title() {
  echo $'\e[1G----->' $*
}

function echo_normal() {
  echo $'\e[1G      ' $*
}

function ensure_indent() {
  while read line; do
    if [[ "$line" == --* ]]; then
      echo $'\e[1G'$line
    else
      echo $'\e[1G      ' "$line"
    fi
  done
}

cd $app_dir

## Get custom buildpack

if [[ -f ".env" ]]; then
  source ".env"
fi

## Buildpack fixes

export APP_DIR="$app_dir"
export HOME="$app_dir"
export REQUEST_ID=$(openssl rand -base64 32)
export STACK=cedar-14
export CURL_CONNECT_TIMEOUT=30

## Buildpack detection

buildpacks=($buildpack_root/*)
selected_buildpack=

if [[ -n "$BUILDPACK_URL" ]]; then
  echo_title "Fetching custom buildpack"

  buildpack="$buildpack_root/custom"
  rm -rf "$buildpack"
  /build/install-buildpack "$buildpack_root" "$BUILDPACK_URL" custom &> /dev/null
  selected_buildpack="$buildpack"
  buildpack_name=$($buildpack/bin/detect "$app_dir") && selected_buildpack=$buildpack
else
  for buildpack in "${buildpacks[@]}"; do
    buildpack_name=$($buildpack/bin/detect "$app_dir") && selected_buildpack=$buildpack && break
  done
fi

if [[ -n "$selected_buildpack" ]]; then
  echo_title "$buildpack_name app detected"
else
  echo_title "Unable to select a buildpack"
  exit 1
fi

## Buildpack compile

$selected_buildpack/bin/compile "$app_dir" "$cache_root" "$env_dir" | ensure_indent
$selected_buildpack/bin/release "$app_dir" "$cache_root" > $app_dir/.release

## Display process types

echo_title "Discovering process types"
if [[ -f "$app_dir/Procfile" ]]; then
  types=$(ruby -e "require 'yaml';puts YAML.load_file('$app_dir/Procfile').keys().join(', ')")
  echo_normal "Procfile declares types -> $types"
fi
default_types=""
if [[ -f "$app_dir/.release" ]]; then
  default_types=$(ruby -e "require 'yaml';puts ((YAML.load_file('$app_dir/.release') || {})['default_process_types'] || {}).keys().join(', ')")
  [[ $default_types ]] && echo_normal "Default process types for $buildpack_name -> $default_types"
fi

## Export release config

if [[ -f "$app_dir/.release" ]]; then
  ruby -e "require 'yaml';((YAML.load_file('$app_dir/.release') || {})['config_vars'] || {}).each{|k,v| puts \"export #{k}='#{v}'\"}" > $app_dir/.profile.d/00_config_vars.sh
fi
