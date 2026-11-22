#!/usr/bin/env bash
# Shared repository selection for campaigns whose spec names a product repo.

factory_product_slug_from_spec() {
  local line slug=''
  while IFS= read -r line; do
    if [[ "$line" =~ ^Repository:[[:space:]]*https://github[.]com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)[[:space:]]*$ ]]; then
      [[ -z "$slug" ]] || { echo 'The spec has more than one Repository: link.' >&2; return 1; }
      slug="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
      slug="${slug%.git}"
    fi
  done < "$1"
  [[ -n "$slug" ]] || { echo 'Add a line such as Repository: https://github.com/OWNER/PRODUCT to the spec.' >&2; return 1; }
  printf '%s\n' "$slug"
}

factory_product_context() {
  local factory_dir="$1" config="$HOME/.config/briefing-agents" slug
  if [[ -f "$config/repo-slug" ]]; then
    slug="$(cat "$config/repo-slug")"
    [[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
      echo 'Invalid campaign product repository.' >&2; return 1;
    }
    product_dir="$HOME/factory-products/$slug"
    [[ -d "$product_dir/.git" ]] || { echo "Product checkout missing: $product_dir" >&2; return 1; }
    export GH_REPO="$slug"
  else
    # Existing campaigns created before repository selection still use the factory checkout.
    product_dir="$factory_dir"
    unset GH_REPO
  fi
}
