#!/usr/bin/env bash
set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
  echo "codex non trovato nel PATH." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq non trovato nel PATH (richiesto da jefe)." >&2
  exit 1
fi

SESSIONS_ROOT="${CODEX_HOME:-$HOME/.codex}/sessions"
TERM_COLS=80
MENU_ACTIVE=0

USE_COLOR=0
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  colors="$(tput colors 2>/dev/null || echo 0)"
  if [[ "$colors" =~ ^[0-9]+$ ]] && (( colors >= 8 )); then
    USE_COLOR=1
  fi
fi

CLR_RESET=""
CLR_DIM=""
CLR_TS=""
CLR_VER=""
CLR_ID=""
CLR_PATH=""
CLR_CURSOR=""
if (( USE_COLOR )); then
  CLR_RESET=$'\033[0m'
  CLR_DIM=$'\033[2m'
  CLR_TS=$'\033[1;33m'
  CLR_VER=$'\033[1;32m'
  CLR_ID=$'\033[1;36m'
  CLR_PATH=$'\033[0;37m'
  CLR_CURSOR=$'\033[1;34m'
fi

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  TERM_COLS="$(tput cols 2>/dev/null || echo 80)"
fi

usage() {
  cat <<'EOF'
Uso:
  jefe                # launcher con resume smart
  jefe clean [giorni] # pulisce sessioni vecchie (default: 180 giorni)
EOF
}

menu_cleanup() {
  if (( MENU_ACTIVE )); then
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    MENU_ACTIVE=0
  fi
}

tty_sanitize() {
  if [[ -t 0 ]] && command -v stty >/dev/null 2>&1; then
    stty sane 2>/dev/null || true
  fi
}

menu_interrupt() {
  menu_cleanup
  tty_sanitize
  exit 130
}

trap menu_cleanup EXIT
trap menu_interrupt INT TERM HUP

truncate_text() {
  local text="$1"
  local max="$2"
  local len="${#text}"
  if (( max <= 0 )); then
    printf '%s\n' ""
    return
  fi
  if (( len <= max )); then
    printf '%s\n' "$text"
    return
  fi
  if (( max <= 3 )); then
    printf '%s\n' "${text:0:max}"
    return
  fi
  printf '%s...\n' "${text:0:max-3}"
}

truncate_path() {
  local text="$1"
  local max="$2"
  local len="${#text}"
  if (( max <= 0 )); then
    printf '%s\n' ""
    return
  fi
  if (( len <= max )); then
    printf '%s\n' "$text"
    return
  fi
  if (( max <= 3 )); then
    printf '%s\n' "${text:0:max}"
    return
  fi
  printf '...%s\n' "${text:len-max+3}"
}

strip_ansi() {
  local text="$1"
  # Labels only use SGR color sequences, so removing CSI ... m is enough here.
  printf '%s' "$text" | sed -E $'s/\x1B\\[[0-9;?]*m//g' 2>/dev/null || printf '%s' "$text"
}

normalize_path() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$p" 2>/dev/null || printf '%s\n' "$p"
    return
  fi
  printf '%s\n' "$p"
}

format_ts() {
  local ts="$1"
  if [[ -z "$ts" ]]; then
    printf '%s\n' "-"
    return
  fi
  if command -v date >/dev/null 2>&1; then
    date -d "$ts" "+%Y-%m-%d %H:%M" 2>/dev/null || printf '%s\n' "$ts"
    return
  fi
  printf '%s\n' "$ts"
}

short_id() {
  local sid="$1"
  printf '%s\n' "${sid:0:8}"
}

build_label() {
  local ts="$1"
  local ver="$2"
  local sid="$3"
  local cwd="${4:-}"
  local tsf short base path_budget cwd_shown
  local out

  tsf="$(format_ts "$ts")"
  short="$(short_id "$sid")"
  base="${tsf} | v${ver} | ${short}"
  out="${CLR_TS}${tsf}${CLR_RESET} | ${CLR_VER}v${ver}${CLR_RESET} | ${CLR_ID}${short}${CLR_RESET}"
  if [[ -n "$cwd" ]]; then
    path_budget=$((TERM_COLS - ${#base} - 7))
    if (( path_budget < 12 )); then
      path_budget=12
    fi
    cwd_shown="$(truncate_path "$cwd" "$path_budget")"
    out+=" | ${CLR_PATH}${cwd_shown}${CLR_RESET}"
  fi
  printf '%b\n' "$out"
}

clean_old_sessions() {
  local days="${1:-180}"
  if ! [[ "$days" =~ ^[0-9]+$ ]]; then
    echo "Valore giorni non valido: $days" >&2
    exit 1
  fi
  if [[ ! -d "$SESSIONS_ROOT" ]]; then
    echo "Nessuna cartella sessioni trovata: $SESSIONS_ROOT"
    exit 0
  fi

  mapfile -t old_files < <(find "$SESSIONS_ROOT" -type f -name "*.jsonl" -mtime +"$days" | sort)
  if [[ ${#old_files[@]} -eq 0 ]]; then
    echo "Nessuna sessione piu vecchia di $days giorni."
    exit 0
  fi

  echo "Trovate ${#old_files[@]} sessioni piu vecchie di $days giorni."
  echo "Anteprima:"
  max_preview=12
  for i in "${!old_files[@]}"; do
    if (( i >= max_preview )); then
      echo "..."
      break
    fi
    echo " - ${old_files[$i]}"
  done

  read -r -p "Confermi eliminazione? [y/N]: " ans
  if [[ ! "${ans,,}" =~ ^y(es)?$ ]]; then
    echo "Annullato."
    exit 0
  fi

  for f in "${old_files[@]}"; do
    rm -f -- "$f"
  done
  find "$SESSIONS_ROOT" -type d -empty -delete
  echo "Pulizia completata."
}

select_menu() {
  local title="$1"
  shift
  local -a items=("$@")
  local total_count="${#items[@]}"
  local count=0
  local idx=0
  local offset=0
  local rows=24
  local cols=80
  local visible=12
  local menu_top=4
  local i line text key rest title_view
  local prev_idx=-1
  local prev_offset=-1
  local old_line new_line
  local query=""
  local query_lc
  local search_mode=0
  local filter_dirty=1
  local filter_view
  local -a filtered_indices=()
  local printable

  if (( total_count == 0 )); then
    return 1
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    REPLY=0
    return 0
  fi

  if command -v tput >/dev/null 2>&1; then
    rows="$(tput lines 2>/dev/null || echo 24)"
    cols="$(tput cols 2>/dev/null || echo 80)"
  fi
  TERM_COLS="$cols"
  visible=$((rows - 8))
  if (( visible < 6 )); then
    visible=6
  fi
  title_view="$(truncate_text "$title" "$cols")"

  tput smcup 2>/dev/null || true
  tput civis 2>/dev/null || true
  MENU_ACTIVE=1
  trap menu_cleanup RETURN

  tput clear 2>/dev/null || printf '\033[H\033[2J'

  while true; do
    if (( filter_dirty )); then
      filtered_indices=()
      if [[ -z "$query" ]]; then
        for ((i = 0; i < total_count; i++)); do
          filtered_indices+=("$i")
        done
      else
        query_lc="${query,,}"
        for ((i = 0; i < total_count; i++)); do
          text="$(strip_ansi "${items[$i]}")"
          if [[ "${text,,}" == *"$query_lc"* ]]; then
            filtered_indices+=("$i")
          fi
        done
      fi

      count="${#filtered_indices[@]}"
      if (( count == 0 )); then
        idx=0
        offset=0
      else
        if (( idx >= count )); then
          idx=$((count - 1))
        fi
        if (( idx < 0 )); then
          idx=0
        fi
      fi

      prev_idx=-1
      prev_offset=-1
      filter_dirty=0
    fi

    if (( count == 0 )); then
      offset=0
    fi
    if (( idx < offset )); then
      offset=$idx
    fi
    if (( idx >= offset + visible )); then
      offset=$((idx - visible + 1))
    fi

    if (( offset != prev_offset )); then
      tput cup 0 0 2>/dev/null || true
      tput el 2>/dev/null || true
      printf '%s\n' "$title_view"
      tput el 2>/dev/null || true
      printf '%sUsa frecce su/giu o j/k, / filtra, Invio conferma, q esce.%s\n' "$CLR_DIM" "$CLR_RESET"
      tput el 2>/dev/null || true
      printf '%sElementi: %d/%d  Pagina: %d-%d%s\n' "$CLR_DIM" "$count" "$total_count" "$(( count > 0 ? offset + 1 : 0 ))" "$(( count > 0 ? (offset + visible < count ? offset + visible : count) : 0 ))" "$CLR_RESET"
      tput el 2>/dev/null || true
      if (( search_mode )); then
        filter_view="$(truncate_text "Filter: /${query}_" "$cols")"
      elif [[ -n "$query" ]]; then
        filter_view="$(truncate_text "Filter: /$query" "$cols")"
      else
        filter_view="$(truncate_text "Filter: / (type to search, Esc clears)" "$cols")"
      fi
      printf '%s%s%s\n' "$CLR_DIM" "$filter_view" "$CLR_RESET"

      for ((line = 0; line < visible; line++)); do
        i=$((offset + line))
        tput cup $((menu_top + line)) 0 2>/dev/null || true
        tput el 2>/dev/null || true
        if (( i >= count )); then
          continue
        fi
        text="${items[${filtered_indices[$i]}]}"
        if (( i == idx )); then
          printf '%b> %s%b\n' "$CLR_CURSOR" "$text" "$CLR_RESET"
        else
          printf '  %s\n' "$text"
        fi
      done
      if (( count == 0 )); then
        tput cup "$menu_top" 0 2>/dev/null || true
        tput el 2>/dev/null || true
        printf '%sNo matches%s\n' "$CLR_DIM" "$CLR_RESET"
      fi
      prev_offset=$offset
      prev_idx=$idx
    elif (( idx != prev_idx )) && (( count > 0 )); then
      old_line=$((prev_idx - offset))
      if (( old_line >= 0 && old_line < visible )); then
        tput cup $((menu_top + old_line)) 0 2>/dev/null || true
        tput el 2>/dev/null || true
        text="${items[${filtered_indices[$prev_idx]}]}"
        printf '  %s\n' "$text"
      fi

      new_line=$((idx - offset))
      if (( new_line >= 0 && new_line < visible )); then
        tput cup $((menu_top + new_line)) 0 2>/dev/null || true
        tput el 2>/dev/null || true
        text="${items[${filtered_indices[$idx]}]}"
        printf '%b> %s%b\n' "$CLR_CURSOR" "$text" "$CLR_RESET"
      fi
      prev_idx=$idx
    fi

    IFS= read -rsn1 key || { menu_cleanup; tty_sanitize; return 1; }
    if (( search_mode )); then
      case "$key" in
        "")
          if (( count > 0 )); then
            REPLY="${filtered_indices[$idx]}"
            menu_cleanup
            return 0
          fi
          ;;
        $'\x7f'|$'\b')
          if [[ -n "$query" ]]; then
            query="${query%?}"
            filter_dirty=1
          fi
          ;;
        $'\x15')
          query=""
          filter_dirty=1
          ;;
        $'\x1b')
          IFS= read -rsn2 -t 0.05 rest || rest=""
          if [[ -z "$rest" ]]; then
            search_mode=0
            query=""
            filter_dirty=1
          else
            case "$rest" in
              "[A") if (( count > 0 )); then ((idx = (idx - 1 + count) % count)); fi ;;
              "[B") if (( count > 0 )); then ((idx = (idx + 1) % count)); fi ;;
            esac
          fi
          ;;
        *)
          printable=0
          if [[ "$key" =~ [[:print:]] ]]; then
            printable=1
          fi
          if (( printable )); then
            query+="$key"
            filter_dirty=1
          fi
          ;;
      esac
      continue
    fi

    case "$key" in
      "")
        if (( count > 0 )); then
          REPLY="${filtered_indices[$idx]}"
          menu_cleanup
          return 0
        fi
        ;;
      /)
        search_mode=1
        query=""
        filter_dirty=1
        ;;
      $'\x1b')
        IFS= read -rsn2 -t 0.05 rest || true
        case "$rest" in
          "[A") if (( count > 0 )); then ((idx = (idx - 1 + count) % count)); fi ;;
          "[B") if (( count > 0 )); then ((idx = (idx + 1) % count)); fi ;;
        esac
        ;;
      k) if (( count > 0 )); then ((idx = (idx - 1 + count) % count)); fi ;;
      j) if (( count > 0 )); then ((idx = (idx + 1) % count)); fi ;;
      q)
        menu_cleanup
        return 1
        ;;
    esac
  done
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "clean" ]]; then
  shift
  clean_old_sessions "${1:-180}"
  exit 0
fi

CURRENT_CWD="$(normalize_path "$(pwd -P)")"

declare -a RECORDS=()
if [[ -d "$SESSIONS_ROOT" ]]; then
  while IFS= read -r file; do
    first_line="$(head -n 1 "$file" 2>/dev/null || true)"
    [[ -z "$first_line" ]] && continue
    rec="$(
      jq -r '
        if .type == "session_meta" and .payload.id and .payload.cwd then
          [(.payload.timestamp // ""), .payload.id, .payload.cwd, (.payload.cli_version // "-")] | @tsv
        else
          empty
        end
      ' <<<"$first_line" 2>/dev/null || true
    )"
    [[ -n "$rec" ]] && RECORDS+=("$rec")
  done < <(find "$SESSIONS_ROOT" -type f -name "*.jsonl" 2>/dev/null)
fi

if [[ ${#RECORDS[@]} -eq 0 ]]; then
  exec codex "$@"
fi

mapfile -t SORTED < <(printf '%s\n' "${RECORDS[@]}" | sort -r)

declare -a LOCAL_ROWS=()
for row in "${SORTED[@]}"; do
  IFS=$'\t' read -r _ts _sid scwd _ver <<<"$row"
  if [[ "$(normalize_path "$scwd")" == "$CURRENT_CWD" ]]; then
    LOCAL_ROWS+=("$row")
  fi
done

if [[ ${#LOCAL_ROWS[@]} -gt 0 ]]; then
  declare -a LOCAL_MENU_ITEMS=()
  declare -a LOCAL_MENU_IDS=()
  for row in "${LOCAL_ROWS[@]}"; do
    IFS=$'\t' read -r ts sid _scwd ver <<<"$row"
    LOCAL_MENU_ITEMS+=("$(build_label "$ts" "$ver" "$sid")")
    LOCAL_MENU_IDS+=("$sid")
  done
  LOCAL_MENU_ITEMS+=("${CLR_VER}Nuova sessione${CLR_RESET}")
  LOCAL_MENU_IDS+=("__NEW__")

  if select_menu "Sessioni in $CURRENT_CWD" "${LOCAL_MENU_ITEMS[@]}"; then
    choice_id="${LOCAL_MENU_IDS[$REPLY]}"
    if [[ "$choice_id" == "__NEW__" ]]; then
      exec codex "$@"
    fi
    exec codex resume "$choice_id" "$@"
  fi
  exit 1
fi

declare -a ALL_IDS=()
declare -a ALL_CWDS=()
declare -a ALL_VERSIONS=()
declare -a ALL_TIMESTAMPS=()
declare -A SEEN=()
for row in "${SORTED[@]}"; do
  IFS=$'\t' read -r ts sid scwd ver <<<"$row"
  [[ -n "${SEEN[$sid]:-}" ]] && continue
  SEEN["$sid"]=1
  ALL_IDS+=("$sid")
  ALL_CWDS+=("$scwd")
  ALL_VERSIONS+=("$ver")
  ALL_TIMESTAMPS+=("$ts")
done

if [[ ${#ALL_IDS[@]} -eq 0 ]]; then
  exec codex "$@"
fi

declare -a GLOBAL_MENU_ITEMS=()
for i in "${!ALL_IDS[@]}"; do
  GLOBAL_MENU_ITEMS+=("$(build_label "${ALL_TIMESTAMPS[$i]}" "${ALL_VERSIONS[$i]}" "${ALL_IDS[$i]}" "${ALL_CWDS[$i]}")")
done

if ! select_menu "Nessuna sessione in $CURRENT_CWD. Seleziona una sessione da riprendere" "${GLOBAL_MENU_ITEMS[@]}"; then
  exit 1
fi

idx="$REPLY"
target_id="${ALL_IDS[$idx]}"
target_cwd="${ALL_CWDS[$idx]}"
target_ver="${ALL_VERSIONS[$idx]}"

if [[ -d "$target_cwd" ]]; then
  echo "Riprendo sessione $(short_id "$target_id") (v$target_ver) in $target_cwd"
  cd "$target_cwd"
  exec codex resume "$target_id" "$@"
fi

echo "Cartella non trovata: $target_cwd" >&2
exit 1
