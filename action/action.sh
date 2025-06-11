#!/bin/bash

# Function to compare two semver versions
# Returns 1 if $1 > $2, 0 if $1 == $2, -1 if $1 < $2
semver_compare() {
  local IFS=.
  local i ver1=($1) ver2=($2)
  # Append zeroes to make sure both versions have the same length
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
    ver1[i]=0
  done
  for ((i=${#ver2[@]}; i<${#ver1[@]}; i++)); do
    ver2[i]=0
  done
  for ((i=0; i<${#ver1[@]}; i++)); do
    if [[ ${ver1[i]} =~ [^0-9] || ${ver2[i]} =~ [^0-9] ]]; then
      if [[ ${ver1[i]} < ${ver2[i]} ]]; then
        echo -1
        return
      elif [[ ${ver1[i]} > ${ver2[i]} ]]; then
        echo 1
        return
      fi
    else
      if ((10#${ver1[i]} > 10#${ver2[i]})); then
        echo 1
        return
      elif ((10#${ver1[i]} < 10#${ver2[i]})); then
        echo -1
        return
      fi
    fi
  done
  echo 0
}

# Check if remote 'origin' exists
remote_exists() {
  git remote get-url origin >/dev/null 2>&1
}

# Get local tags and filter for SemVer
get_local_tags() {
  if ! tags=$(git tag -l 2>/dev/null); then
    echo "Error: Could not access local tags" >&2
    echo ""
    return 1
  fi
  filtered_tags=$(echo "$tags" | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$')
  echo "$filtered_tags"
}

semver_get_latest() {
  # Check if remote exists and try to get remote tags first
  if remote_exists; then
    if tags=$(git ls-remote --tags origin 2>/dev/null); then
      # Process remote tags (remove refs/tags/ prefix)
      tags=$(echo "$tags" | grep -v '\^{}' | awk '{print $2}' | sed 's|refs/tags/||')
      # Filter tags that conform to SemVer
      filtered_tags=$(echo "$tags" | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$')
    else
      echo "Warning: Could not fetch remote tags. Checking local tags..." >&2
      filtered_tags=$(get_local_tags)
      if [[ $? -ne 0 ]]; then
        return 1
      fi
    fi
  else
    echo "Warning: No 'origin' remote found. Checking local tags..." >&2
    filtered_tags=$(get_local_tags)
    if [[ $? -ne 0 ]]; then
      return 1
    fi
  fi

  # Initialize highest version variable
  highest_version=""

  for tag in $filtered_tags; do
    # Remove leading 'v' if present
    version=${tag}
    if [ -z "$highest_version" ]; then
      highest_version=$version
    else
      comparison=$(semver_compare "$version" "$highest_version")
      if [ "$comparison" -eq 1 ]; then
        highest_version=$version
      fi
    fi
  done

  if [ -z "$highest_version" ]; then
    echo ""
  else
    echo "$highest_version"
  fi
}

CUSTOM_TAG=${1}
PREVIEW=${2:-false}

current_branch=$(git rev-parse --abbrev-ref HEAD)
# Check if the current branch is master or main
if [ "$current_branch" != "master" ] && [ "$current_branch" != "main" ]
then
  echo -e "\nError: Current branch is neither 'master' nor 'main', please switch current branch.\n"
  exit 1
fi

latest_tag=$(semver_get_latest)
if [[ -z "${latest_tag}" ]]; then
  echo "No valid SemVer tags found. Creating initial tag..."

  # Always use 'v' prefix for initial tag (standard convention)
  latest_tag="v0.0.0"
  echo "Using initial tag: $latest_tag"
else
  echo -e "\nLast tag is: $latest_tag\n"
fi

# Generate changelog with git-cliff
if [[ "$latest_tag" == "v0.0.0" ]]; then
  # For initial tag, get all commits
  changelog="$(git cliff --config /action/config.toml)"
else
  changelog="$(git cliff --config /action/config.toml "${latest_tag}"..HEAD)"
fi
changelog=$(echo "${changelog}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

if [[ -z "${changelog}" && "$latest_tag" != "v0.0.0" ]]; then
  echo "Changelog is empty. Please ensure you have new commits outside latest tag"
  exit 0
fi

echo -e "$changelog\n"

if [ "$PREVIEW" = true ]; then
  exit 0
fi

if [[ ${latest_tag:0:1} == "v" ]]; then
  starts_with_v=true
else
  starts_with_v=false
fi

# Use custom tag or provide choice for user to update.
if [[ -n "${CUSTOM_TAG}" ]]; then
  NEW_TAG=${CUSTOM_TAG}
else
  # Handle initial tag case
  if [[ "$latest_tag" == "v0.0.0" ]]; then
    # Creating initial release tag
    NEW_TAG="v0.1.0"
  else
    # strip V from tag
    major=$(echo "$latest_tag" | cut -d'.' -f1)
    major=${major#v}

    minor=$(echo "$latest_tag" | cut -d'.' -f2)
    patch=$(echo "$latest_tag" | cut -d'.' -f3)

    patch_tag="${major}.${minor}.$((patch + 1))"
    minor_tag="${major}.$((minor + 1)).0"
    major_tag="$((major + 1)).0.0"

    # return V to tag if any
    if $starts_with_v; then
      patch_tag="v${patch_tag}"
      minor_tag="v${minor_tag}"
      major_tag="v${major_tag}"
    fi

    PS3=$'\nPlease enter your choice: '
    options=("Fix: Safe to upgrade, bugfixes ($patch_tag)" "Feature: Safe to update, new features ($minor_tag)" "Breaking: Not safe to update ($major_tag)")
    on_interrupt() {
      echo -e "\nInterrupted by user, quiting..."
      exit 0
    }

    trap on_interrupt INT

    select opt in "${options[@]}"
    do
      case $opt in
           "${options[0]}")
              echo "Incrementing patch level"
              NEW_TAG=$patch_tag
              break
              ;;
          "${options[1]}")
              echo "Incrementing minor version and reset patch level"
              NEW_TAG=$minor_tag
              break
              ;;
          "${options[2]}")
              echo "Incrementing major version and reset minor and patch level"
              NEW_TAG=$major_tag
              break
              ;;
          *)
              echo "Invalid option $REPLY"
              exit 1
              ;;
            esac
      done
  fi
fi

echo "Creating tag: ${NEW_TAG}"
# Creation of new tag including changelog as description
git tag -f -a $NEW_TAG -m "$changelog"
echo "Press 'Enter' to push new tag to repo"
read -r
git push origin tag $NEW_TAG
