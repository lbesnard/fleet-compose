# bash completion for fleet-compose's `fleet` script.
# Install: source this file from ~/.bashrc (or copy to /etc/bash_completion.d/fleet).

_fleet_machines() {
  local d=${FLEET_DIR:-}
  if [[ -z $d ]]; then
    local f; f=$(command -v fleet 2>/dev/null)
    [[ -n $f ]] && d=$(dirname "$(readlink -f "$f")")
  fi
  [[ -z $d && -x ./fleet ]] && d=$PWD
  if [[ -d $d/machines ]]; then
    ls -1 "$d/machines" 2>/dev/null
  else
    echo "beefunk brownfunk evryfunk evryfunknuc"
  fi
}

_fleet() {
  local cur=${COMP_WORDS[COMP_CWORD]}
  local cmd=${COMP_WORDS[1]}
  COMPREPLY=()
  if (( COMP_CWORD == 1 )); then
    COMPREPLY=($(compgen -W "decrypt encrypt vendor sync rekey keygen edit" -- "$cur"))
    return
  fi
  case $cmd in
    encrypt)              (( COMP_CWORD == 2 )) && COMPREPLY=($(compgen -W "$(_fleet_machines) all" -- "$cur")) ;;
    decrypt|vendor|sync)  (( COMP_CWORD == 2 )) && COMPREPLY=($(compgen -W "$(_fleet_machines)" -- "$cur")) ;;
    edit)                 compopt -o filenames 2>/dev/null
                          COMPREPLY=($(compgen -f -X '!*.vault' -- "$cur") $(compgen -d -- "$cur")) ;;
  esac
}
complete -F _fleet fleet ./fleet
