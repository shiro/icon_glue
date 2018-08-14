#!/bin/zsh

SCRIPT_NAME="`basename $0`"

usage(){
  cat <<USAGE
  Usage: $SCRIPT_NAME [OPTION]...
    -c=<config.json>       specify config file
    -i=<path to icon dir>  specify custom icon dir path
        --dry-run          do not actually persist any changes
        --help             print this message
USAGE
}


SHORTCUT_LOATIONS=(
    /mnt/c/ProgramData/Microsoft/Windows/Start\ Menu
    ${HOME}'/AppData/Roaming/Microsoft/Windows/Start Menu'
)


DRY_RUN=false
CONFIG_FILE='config.json'
ICON_DIR='/mnt/d/ext/customization/icons/metro'


# decide which file converter to use
if   [ `command -v cygpath` ]; then
  PATH_CONVERTER='cygpath'
elif [ `command -v wslpath` ]; then
  PATH_CONVERTER='wslpath'
else
  echo 'error: unable to find cygpath or wslpath locally'
  exit 1
fi


while getopts ':c:i:-:' opt; do
  case "$opt" in
    -) case "$OPTARG" in
        help)
          usage; exit 0
          ;;
        dry-run)
          DRY_RUN=true
          ;;
        *)
          usage; exit 1
          ;;
      esac;;
    c)
      if [ ! -e "$OPTARG" ]; then
        echo "$OPTARG: not found"
        exit 1
      fi
      CONFIG_FILE="$OPTARG"
      ;;
    i)
      if [ ! -d "$OPTARG" ]; then
        echo "$OPTARG: not found"
        exit 1
      fi
      ICON_DIR="$OPTARG"
      ;;
    :|\?)
      usage; exit 1
      ;;
  esac
done
shift $((OPTIND-1))

# no additional arguments
[ $# -ne 0 ] && usage && exit 1


# create output dir
mkdir -p out


echo "### FILE TYPES ###"
echo

# generate registry script head
echo 'Windows Registry Editor Version 5.00' > out/ext.reg


for row in `jq -r '.filetypes[] | @base64' "$CONFIG_FILE"`; do
  _value() { echo ${row} | base64 --decode | jq -r ${1} }

  extension=`_value '.extension'`
  openWith=`_value '.openWith'`
  icon=`_value '.icon'`

  iconPath="`$PATH_CONVERTER -w "$ICON_DIR/$icon"`"

  sed -e "s|EXTENSION|${extension}|g" \
    -e "s|ICON|${iconPath//\\/\\/}|g" \
    -e "s|APPLICATION|${openWith//\\/\\\\\\\\}|g" \
    template/ext.reg >> out/ext.reg

  echo >> out/ext.reg

  # set the new extension as the default program
  [ $DRY_RUN = false ] && \
  ./SetUserFTA ".${extension}" "auto.${extension}"

  echo "[SET]    $icon"
done


# apply registry snippet silently
[ $DRY_RUN = false ] && \
regedit.exe /s out/ext.reg


echo
echo "### SHORTCUTS ###"
echo


# build a list of shortcuts from all locations
declare -a SHORTCUTS

for location in "$SHORTCUT_LOATIONS[@]"; do
    local location=$(realpath "$location")

    SHORTCUTS+=("$location"/**/*.lnk) 2>/dev/null
done


declare -A ICONS

for row in `jq -r '.shortcuts[] | @base64' "$CONFIG_FILE"`; do
    _value() { echo ${row} | base64 --decode | jq -r ${1} }

    local pattern=`_value '.pattern'`
    local icon=`_value '.icon'`

    ICONS[$pattern]="$icon"
done


# set the new icons for each shortcut if it's in the icon manifest
for shortcutPath in "${SHORTCUTS[@]}"; do
    # get the name without the prefix
    local shortcut="${shortcutPath##*Start Menu/Programs/}"

    # iterate keys and attempt pattern matching against shortcut
    for key in ${(k)ICONS[@]}; do
        if [[ "$shortcut" =~ "$key" ]]; then

            local icon=${ICONS[$key]}

            local shortcutPath=`$PATH_CONVERTER -w "$shortcutPath"`
            local iconPath=`$PATH_CONVERTER -w "${ICON_DIR}/${icon}"`

            printf '[SET] %s\n' "$shortcutPath"

            # update the registry value
            [ $DRY_RUN = false ] && \
            cmd.exe /c set_icon.vbs "$shortcutPath" "$iconPath"
        fi
    done

    unset ICON
done
