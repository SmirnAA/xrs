_xrs() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  if [[ $COMP_CWORD -eq 1 ]]; then
    COMPREPLY=($(compgen -W "add rm status update-geo" -- "$cur"))
  fi
}

complete -F _xrs xrs
