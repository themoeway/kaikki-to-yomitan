#!/bin/bash

source .env
export DEBUG_WORD
export DICT_NAME
max_memory_mb=${MAX_MEMORY_MB:-8192}


# Check for the source_language and target_language arguments
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <source_language> <target_language> [flags]"
  exit 1
fi

# Parse flags
redownload=false
force_tidy=false
force_ymt=false
force=false
keep_files=false

flags=('S' 'T' 'd' 't' 'y' 'F' 'k')
for flag in "${flags[@]}"; do
  case "$3" in 
    *"$flag"*) 
      case "$flag" in
        'd') redownload=true ;;
        't') force_tidy=true ;;
        'y') force_ymt=true ;;
        'F') force=true ;;
        'k') keep_files=true ;;
      esac
      ;;
  esac
done

if [ "$force" = true ]; then
  force_tidy=true
  force_ymt=true
fi

if [ "$force_tidy" = true ]; then
  force_ymt=true
fi

echo "[d] redownload: $redownload"
echo "[F] force: $force"
echo "[t] force_tidy: $force_tidy"
echo "[y] force_ymt: $force_ymt"
echo "[k] keep_files: $keep_files"

# Step 1: Install dependencies
npm i

# Step 2: Run create-folder.js
node 1-create-folders.js

language_source="$1"
language_target="$2"

declare -a languages="($(
  jq -r '.[] | @json | @sh' languages.json
))"

for target_lang in "${languages[@]}"; do
  target_iso=$(echo "${target_lang}" | jq -r '.iso')
  target_language_name=$(echo "${target_lang}" | jq -r '.language')
    
  if [ "$target_language_name" != "$language_target" ] && [ "$language_target" != "?" ]; then
      continue
  fi

    target_languages="de en es fr ru zh"
    if [[ ! "$target_languages" == *"$target_iso"* ]]; then
      echo "Unsupported target language: $target_iso"
      continue
    fi

  export target_iso="$target_iso"
  export target_language="$target_language_name"
  downloaded_target_extract=false

  for source_lang in "${languages[@]}"; do
    iso=$(echo "${source_lang}" | jq -r '.iso')
    language=$(echo "${source_lang}" | jq -r '.language')
    flag=$(echo "${source_lang}" | jq -r '.flag')
    
    if [ "$language" != "$language_source" ] && [ "$language_source" != "?" ]; then
      continue
    fi

    export source_language="$language"
    export source_iso="$iso"

    echo "------------------------------- $source_language -> $target_language -------------------------------"

    # Step 3: Download JSON data if it doesn't exist
    if [ "$target_language" = "English" ]; then
      language_no_special_chars=$(echo "$language" | tr -d '[:space:]-') #Serbo-Croatian, Ancient Greek and such cases
      filename="kaikki.org-dictionary-$language_no_special_chars.jsonl"
      filepath="data/kaikki/$filename"
      

      if [ ! -f "$filepath" ] || [ "$redownload" = true ]; then
        url="https://kaikki.org/dictionary/$language/$filename"
        echo "Downloading $filename from $url"
        wget "$url" -O "$filepath"
      else
        echo "Kaikki dict already exists. Skipping download."
      fi
    else
      target_extract="$target_iso-extract.jsonl"
      target_extract_path="data/kaikki/$target_extract"

      if [ ! -f "$target_extract_path" ] || [ "$redownload" = true ] && [ "$downloaded_target_extract" = false ]; then
        url="https://kaikki.org/dictionary/downloads/$target_iso/$target_extract.gz"
        echo "Downloading $target_extract from $url"
        wget "$url" -O "$target_extract_path".gz
        echo "Extracting $target_extract"
        gunzip -f "$target_extract_path".gz
        downloaded_target_extract=true
      else
        echo "Kaikki dict already exists. Skipping download."
      fi

      filename="$source_iso-$target_iso-extract.jsonl"
      filepath="data/kaikki/$filename"

      if [ ! -f "$filepath" ]; then
        echo "Extracting $filename"
        python3 2-extract-language.py
      else
        echo "Extracted file already exists. Skipping extraction."
      fi
    fi

    export kaikki_file="data/kaikki/$filename"
    export tidy_folder="data/tidy"

    # Step 4: Run tidy-up.js if the tidy files don't exist
    if \
      [ ! -f "data/tidy/$source_iso-$target_iso-forms-0.json" ] || \
      [ ! -f "data/tidy/$source_iso-$target_iso-lemmas.json" ] || \
      [ "$force_tidy" = true ]; then
        node --max-old-space-size="$max_memory_mb" 3-tidy-up.js
      else
        echo "Tidy file already exists. Skipping tidying."
    fi

    if [ "$keep_files" = false ]; then
      rm -f "$kaikki_file"
    fi

    export temp_folder="data/temp"
    temp_dict_folder="$temp_folder/dict"
    temp_ipa_folder="$temp_folder/ipa"
    dict_file="${DICT_NAME}-$source_iso-$target_iso.zip"
    ipa_file="${DICT_NAME}-$source_iso-$target_iso-ipa.zip"

    # Step 5: Create Yomitan files
    if \
      [ ! -f "data/language/$source_iso/$target_iso/$dict_file" ] || \
      [ ! -f "data/language/$source_iso/$target_iso/$ipa_file" ] || \
      [ "$force_ymt" = true ]; then
      echo "Creating Yomitan dict and IPA files"
      if node --max-old-space-size="$max_memory_mb" 4-make-yomitan.js; then
        echo "Zipping Yomitan files"
        zip -qj "$dict_file" $temp_dict_folder/index.json $temp_dict_folder/styles.css $temp_dict_folder/tag_bank_1.json $temp_dict_folder/term_bank_*.json 
        zip -qj "$ipa_file" $temp_ipa_folder/index.json $temp_ipa_folder/tag_bank_1.json $temp_ipa_folder/term_meta_bank_*.json
      else
        echo "Error: Yomitan generation script failed."
      fi
    else
      echo "Yomitan dict already exists. Skipping Yomitan creation."
    fi

    if [ -f "$dict_file" ]; then
      mv "$dict_file" "data/language/$source_iso/$target_iso/"
    fi

    if [ -f "$ipa_file" ]; then
      mv "$ipa_file" "data/language/$source_iso/$target_iso/"
    fi

    echo "----------------------------------------------------------------------------------"
  done

  if [ "$keep_files" = false ]; then
    rm -rf "$target_extract_path"
  fi
done
echo "All done!"