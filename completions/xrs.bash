# shellcheck shell=bash
_xrs() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=($(compgen -W "add rm sub status update-geo tun" -- "$cur"))
  elif [[ $COMP_CWORD -eq 2 && "${COMP_WORDS[1]}" == "sub" ]]; then
    COMPREPLY=($(compgen -W "add update rm ls" -- "$cur"))
  elif [[ $COMP_CWORD -eq 2 && "${COMP_WORDS[1]}" == "tun" ]]; then
    COMPREPLY=($(compgen -W "on off status" -- "$cur"))
  fi
}

complete -F _xrs xrs
