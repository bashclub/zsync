# SPDX-License-Identifier: GPL-3.0-or-later
# Snapshot chains of bashclub-zsync-restore: comparison by GUID, independent of names and hosts, so a later own
# snapshot check can use it as well. A chain is a list of lines "<guid><TAB><snapshot name without dataset>",
# oldest first (zfs list -H -o guid,name -s createtxg -t snapshot -d 1 <dataset>, name cut at @).

# chain <dataset> on stdin from zfs list -H -o guid,name: name without dataset
chain_names() {
    awk -F'\t' '{ sub(/^[^@]*@/, "", $2); print $1 "\t" $2 }'
}

# chain_upto <chain> <snapshot>: the chain up to and including <snapshot> (all with an empty <snapshot>), nothing if
# it is not in the chain
chain_upto() {
    awk -F'\t' -v s="$2" 'NF < 2 { next } { lines = lines $0 "\n" } $2 == s { printf "%s", lines; done = 1; exit }
        END { if (s == "" && !done) printf "%s", lines }' <<< "$1"
}

# chain_compare <source chain> <target chain>: how the target relates to the source, as lines key=value
#   common=<name>     newest snapshot of the target that is in the source (by GUID), empty without one
#   missing=<n>       snapshots of the source after the common one (all without a common one)
#   diverged=<n>      snapshots of the target after the common one that are not in the source
#   newest=<name>     newest snapshot of the target
chain_compare() {
    awk -F'\t' '
        FNR == 1 { file++ }
        file == 1 && NF >= 2 { src[++ns] = $1; srcname[$1] = $2 }
        file == 2 && NF >= 2 { dst[++nd] = $1; dstname[nd] = $2 }
        END {
            common = 0
            for (i = nd; i >= 1; i--) if (dst[i] in srcname) { common = i; break }
            for (j = 1; j <= ns; j++) if (common && src[j] == dst[common]) { pos = j; break }
            missing = common ? ns - pos : ns
            diverged = common ? nd - common : nd
            printf "common=%s\nmissing=%d\ndiverged=%d\nnewest=%s\n", common ? srcname[dst[common]] : "", missing, diverged, nd ? dstname[nd] : ""
        }' <(printf '%s\n' "$1") <(printf '%s\n' "$2")
}

# chain_after <chain> <snapshot>: the snapshots after <snapshot> (names), all with an empty <snapshot>
chain_after() {
    awk -F'\t' -v s="$2" 'NF < 2 { next } s == "" || found { print $2; next } $2 == s { found = 1 }' <<< "$1"
}

# chain_equal <chain a> <chain b>: same snapshots (GUIDs) in the same order
chain_equal() {
    [[ "$(cut -f1 <<< "$1")" == "$(cut -f1 <<< "$2")" ]]
}

# chain_contains <chain> <part>: all GUIDs of <part> are in <chain> in the same order
chain_contains() {
    awk -F'\t' 'FNR == 1 { file++ } file == 1 { have[$1] = FNR } file == 2 && NF { if (!($1 in have) || have[$1] <= last) bad = 1; last = have[$1] } END { exit bad }' \
        <(printf '%s\n' "$1") <(printf '%s\n' "$2")
}
