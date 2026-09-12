[private]
default:
    @just --list --unsorted

# Prefer the repo-local venv holding west + Zephyr's build dependencies (see
# docs/build-env.md). Harmless when absent, e.g. inside the nix dev shell, where
# west comes from the shell instead. Without this, a bare `uv tool install west`
# elsewhere on PATH gets picked up and the build dies on a missing `elftools`.
export PATH := absolute_path('.venv/bin') + ':' + env('PATH')

config := absolute_path('config')
build := absolute_path('.build')
out := absolute_path('firmware')
draw := absolute_path('draw')

build_matrix := "build.yaml"

# parse build.yaml and filter targets by expression
_parse_targets $expr: _check_yq_version
    #!/usr/bin/env bash
    attrs="[.board, .shield, .snippet, .\"artifact-name\", .\"cmake-args\"]"
    filter="(($attrs | map(. // [.]) | combinations), ((.include // {})[] | $attrs)) | join(\",\")"
    echo "$(yq -r "$filter" {{build_matrix}} | grep -v "^," | grep -i "${expr/#all/.*}")"

# build firmware for single board & shield combination
_build_single $board $shield $snippet $artifact cmake_args *west_args:
    #!/usr/bin/env bash
    set -euo pipefail
    artifact="${artifact:-${shield:+${shield// /+}-}${board//\//_}}"
    build_dir="{{ build / '$artifact' }}"

    echo "Building firmware for $artifact..."
    west build -s zmk/app -d "$build_dir" -b $board {{ west_args }} ${snippet:+-S "$snippet"} -- \
        -DZMK_CONFIG="{{ config }}" ${shield:+-DSHIELD="$shield"} {{ cmake_args }}

    if [[ -f "$build_dir/zephyr/zmk.uf2" ]]; then
        mkdir -p "{{ out }}" && cp "$build_dir/zephyr/zmk.uf2" "{{ out }}/$artifact.uf2"
    else
        mkdir -p "{{ out }}" && cp "$build_dir/zephyr/zmk.bin" "{{ out }}/$artifact.bin"
    fi

# flash firmware for single board & shield combination
# only needed for boards which do not support UF2
_flash_single $board $shield $artifact:
    #!/usr/bin/env bash
    set -euo pipefail
    artifact="${artifact:-${shield:+${shield// /+}-}${board//\//_}}"
    build_dir="{{ build / '$artifact' }}"

    echo "Flashing firmware for $artifact..."
    west flash -d "$build_dir"

# List build targets. The sed chain removes version and build variants,
# and prints the artifact name if given, otherwise the shield or board.
[group('build & draw')]
[doc('list build targets')]
list:
    @just build_matrix={{build_matrix}} _parse_targets all \
        | awk -F, '{ if ($4 != "") print $4; else if ($2 != "") print $2; else print $1 }' \
        | sed 's|[@/][^,]*$||' \
        | sort \
        | column

# build firmware for targets matching <expr>
[group('build & draw')]
build expr *west_args:
    #!/usr/bin/env bash
    set -euo pipefail
    targets=$(just build_matrix={{build_matrix}} _parse_targets {{ expr }})

    [[ -z $targets ]] && echo "No matching targets found. Aborting..." >&2 && exit 1
    echo "$targets" | while IFS=, read -r board shield snippet artifact cmake_args; do
        just _build_single "$board" "$shield" "$snippet" "$artifact" "$cmake_args" {{ west_args }}
    done

# flash firmware for targets matching <expr>
[group('build & draw')]
flash expr: (build expr)
    #!/usr/bin/env bash
    set -euo pipefail
    targets=$(just build_matrix={{build_matrix}} _parse_targets {{ expr }})

    [[ -z $targets ]] && echo "No matching targets found. Aborting..." >&2 && exit 1
    echo "$targets" | while IFS=, read -r board shield snippet artifact cmake_args; do
        just _flash_single "$board" "$shield" "$artifact"
    done

# parse & plot keymaps for all keyboards matching <expr>
[group('build & draw')]
draw expr="all": _check_yq_version
    #!/usr/bin/env bash
    set -euo pipefail

    # One entry per physical keyboard: "<config/NAME.keymap>|<layout args>".
    # The layout args tell keymap-drawer which physical layout to render; see
    # https://github.com/caksoylar/keymap-drawer/blob/main/PHYSICAL_LAYOUTS.md
    keyboards=(
        "corne|-z corne"
        "handwired_corne|-z corne -l foostan_corne_5col_layout"
    )

    matched=0
    for entry in "${keyboards[@]}"; do
        name="${entry%%|*}"
        layout="${entry#*|}"
        if [[ "{{ expr }}" != "all" && "$name" != *"{{ expr }}"* ]]; then
            continue
        fi
        matched=1

        echo "Drawing $name..."
        keymap -c "{{ draw }}/config.yaml" parse -z "{{ config }}/$name.keymap" \
            --virtual-layers Combos >"{{ draw }}/$name.yaml"
        yq -Yi '.combos.[].l = ["Combos"]' "{{ draw }}/$name.yaml"
        keymap -c "{{ draw }}/config.yaml" draw "{{ draw }}/$name.yaml" $layout \
            >"{{ draw }}/$name.svg"

        # Condensed overview: fold the four non-base layers into corner legends
        # on the base layer. tl=Raise, tr=Lower, bl=Num, br=Admin — matching the
        # --color-* variables in draw/config.yaml.
        #
        # Duplicate legends are dropped: several keys carry the same binding on
        # more than one layer (Lower and Raise share the whole left home row),
        # and printing it in two corners just overprints. A legend is skipped if
        # the base key's tap or hold already shows it, or if an earlier corner
        # claimed it.
        jq_expr='
            def extract_label: if type == "string" then . else .t end;
            def is_transparent: type == "object" and (.type == "trans" or .type == "held");
            def legend: if . == null or is_transparent then null else extract_label end;
            .layers = {
            Base: [
                [.layers.Base, .layers.Lower, .layers.Raise, .layers.Num, .layers.Admin] | transpose[] |
                (.[0] | if type == "string" then {t: .} else . end) as $base |
                [$base.t // empty, $base.h // empty] as $seen |
                [["tr", (.[1] | legend)],
                 ["tl", (.[2] | legend)],
                 ["bl", (.[3] | legend)],
                 ["br", (.[4] | legend)]] as $corners |
                (reduce $corners[] as $c
                    ({seen: $seen, out: {}};
                     if $c[1] != null and (.seen | index($c[1])) == null
                     then {seen: (.seen + [$c[1]]), out: (.out + {($c[0]): $c[1]})}
                     else . end)
                 | .out) as $legends |
                $base + $legends
            ],
            Combos: .layers.Combos
            } |
            .combos = [.combos[] | .l = ["Combos"]]
        '
        yq -y "$jq_expr" "{{ draw }}/$name.yaml" >"{{ draw }}/$name-overview.yaml"
        keymap -c "{{ draw }}/config.yaml" draw "{{ draw }}/$name-overview.yaml" $layout \
            >"{{ draw }}/$name-overview.svg"
        # Portable in-place edit (BSD sed has no GNU-compatible `-i`).
        overview="{{ draw }}/$name-overview.svg"
        sed '/<text.*class="label"/d' "$overview" >"$overview.tmp" && mv "$overview.tmp" "$overview"
    done

    [[ $matched -eq 0 ]] && echo "No matching keyboards found. Aborting..." >&2 && exit 1
    exit 0

# initialize the west workspace
[group('workspace')]
init:
    west init -l config
    west update --fetch-opt=--filter=blob:none
    west zephyr-export

# synchronize the west workspace (after manifest changes)
[group('workspace')]
sync:
    west update --fetch-opt=--filter=blob:none

# clear build cache and artifacts
[group('cleanup')]
clean:
    rm -rf {{ build }} {{ out }}

# warn user if they are using golang-yq and not python-yq
[no-exit-message]
_check_yq_version:
    #!/usr/bin/env bash
    if yq --help 2>&1 | grep -qi 'eval'; then
        echo "This script requires python-yq, but PATH contains golang-yq" >&2
        echo "Please install python-yq or use the included nix shell" >&2
        exit 1
    fi
