#!/usr/bin/env bash
# fix-scans.sh — batch-repair date + GPS metadata on scanned film frames.
#
# Film scans carry the scanner's timestamp, not the shot date, and no location.
# This stamps a whole roll with its real capture date (one frame per --step
# seconds so ordering survives in photo apps) and optionally a GPS position.
#
# Usage:
#   fix-scans.sh --dir <scans/> --date "1994:07:21 12:00:00" \
#     [--gps "47.3769,8.5417"] [--step 60] [--tz +02:00] [--apply] [--no-backup]
#
# Dry-run by default: prints the plan, writes nothing. --apply writes via
# exiftool, which keeps originals as *_original next to each file;
# --no-backup overwrites in place.
set -euo pipefail

DIR="" DATE="" GPS="" STEP=60 TZ_OFF="+00:00" APPLY=0 BACKUP=1

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR=$2; shift 2 ;;
    --date) DATE=$2; shift 2 ;;
    --gps) GPS=$2; shift 2 ;;
    --step) STEP=$2; shift 2 ;;
    --tz) TZ_OFF=$2; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --no-backup) BACKUP=0; shift ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage 1 ;;
  esac
done

[ -n "$DIR" ] && [ -n "$DATE" ] || { echo "error: --dir and --date are required" >&2; usage 1; }
[ -d "$DIR" ] || { echo "error: no such directory: $DIR" >&2; exit 1; }
command -v exiftool >/dev/null || { echo "error: exiftool not found in PATH" >&2; exit 1; }
echo "$DATE" | grep -Eq '^[0-9]{4}:[0-9]{2}:[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' \
  || { echo "error: --date must be 'YYYY:MM:DD HH:MM:SS' (EXIF format)" >&2; exit 1; }

LAT="" LON=""
if [ -n "$GPS" ]; then
  LAT=${GPS%%,*}; LON=${GPS##*,}
  [ "$LAT" != "$GPS" ] && [ -n "$LON" ] || { echo "error: --gps must be 'lat,lon'" >&2; exit 1; }
fi

# Frames sorted by filename = frame order (holds for every scanner naming scheme).
mapfile -t FRAMES < <(find "$DIR" -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.png' -o -iname '*.dng' \) \
  ! -name '*_original' | sort)
[ ${#FRAMES[@]} -gt 0 ] || { echo "error: no image files in $DIR" >&2; exit 1; }

epoch=$(date -d "$(echo "$DATE" | sed 's/:/-/;s/:/-/')" +%s)

MODE="DRY-RUN (pass --apply to write)"; [ $APPLY -eq 1 ] && MODE="APPLY"
echo "== fix-scans: ${#FRAMES[@]} frames in $DIR — $MODE"
echo "   roll date $DATE ($TZ_OFF), +${STEP}s/frame${GPS:+, GPS $LAT,$LON}"

i=0
for f in "${FRAMES[@]}"; do
  ts=$(date -d "@$((epoch + i * STEP))" '+%Y:%m:%d %H:%M:%S')
  printf '%3d  %-40s -> %s\n' "$i" "$(basename "$f")" "$ts"
  if [ $APPLY -eq 1 ]; then
    args=( -q "-AllDates=$ts" "-OffsetTime*=$TZ_OFF" )
    [ $BACKUP -eq 0 ] && args+=( -overwrite_original )
    if [ -n "$GPS" ]; then
      args+=( "-GPSLatitude=$LAT" "-GPSLongitude=$LON"
        "-GPSLatitudeRef=$([ "${LAT#-}" = "$LAT" ] && echo N || echo S)"
        "-GPSLongitudeRef=$([ "${LON#-}" = "$LON" ] && echo E || echo W)" )
    fi
    exiftool "${args[@]}" "$f"
  fi
  i=$((i + 1))
done

if [ $APPLY -eq 1 ]; then
  echo "== verifying..."
  bad=0
  for f in "${FRAMES[@]}"; do
    got=$(exiftool -s3 -DateTimeOriginal "$f")
    [ -n "$got" ] || { echo "   MISSING DateTimeOriginal: $f" >&2; bad=1; }
  done
  [ $bad -eq 0 ] && echo "== OK: all ${#FRAMES[@]} frames stamped" || { echo "== FAILED verification" >&2; exit 1; }
fi
