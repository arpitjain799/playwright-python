#!/bin/bash

set -e
set +x

trap "cd $(pwd -P)" EXIT
cd "$(dirname "$0")"

MCR_IMAGE_NAME="playwright/python"
PW_VERSION=$(python -c "from playwright._repo_version import version;print(version)")

RELEASE_CHANNEL="$1"
if [[ "${RELEASE_CHANNEL}" == "stable" ]]; then
  if [[ "${PW_VERSION}" == *post* ]]; then
    echo "ERROR: cannot publish stable docker with Playwright version '${PW_VERSION}'"
    exit 1
  fi
elif [[ "${RELEASE_CHANNEL}" == "canary" ]]; then
  if [[ "${PW_VERSION}" != *post* ]]; then
    echo "ERROR: cannot publish canary docker with Playwright version '${PW_VERSION}'"
    exit 1
  fi
else
  echo "ERROR: unknown release channel - ${RELEASE_CHANNEL}"
  echo "Must be either 'stable' or 'canary'"
  exit 1
fi

if [[ -z "${GITHUB_SHA}" ]]; then
  echo "ERROR: GITHUB_SHA env variable must be specified"
  exit 1
fi

BIONIC_TAGS=(
  "next-bionic"
)
if [[ "$RELEASE_CHANNEL" == "stable" ]]; then
  BIONIC_TAGS+=("bionic")
fi

FOCAL_TAGS=(
  "next"
  "sha-${GITHUB_SHA}"
  "next-focal"
)

JAMMY_TAGS=(
  "next-jammy"
)

if [[ "$RELEASE_CHANNEL" == "stable" ]]; then
  FOCAL_TAGS+=("latest")
  FOCAL_TAGS+=("focal")
  FOCAL_TAGS+=("v${PW_VERSION}-focal")
  FOCAL_TAGS+=("v${PW_VERSION}")

  JAMMY_TAGS+=("jammy")
  JAMMY_TAGS+=("v${PW_VERSION}-jammy")
fi

tag_and_push() {
  local source="$1"
  local target="$2"
  echo "-- tagging: $target"
  docker tag $source $target
  docker push $target
}

publish_docker_images_with_arch_suffix() {
  local FLAVOR="$1"
  local TAGS=()
  if [[ "$FLAVOR" == "bionic" ]]; then
    TAGS=("${BIONIC_TAGS[@]}")
  elif [[ "$FLAVOR" == "focal" ]]; then
    TAGS=("${FOCAL_TAGS[@]}")
  elif [[ "$FLAVOR" == "jammy" ]]; then
    TAGS=("${JAMMY_TAGS[@]}")
  else
    echo "ERROR: unknown flavor - $FLAVOR. Must be either 'bionic', 'focal', or 'jammy'"
    exit 1
  fi
  local ARCH="$2"
  if [[ "$ARCH" != "amd64" && "$ARCH" != "arm64" ]]; then
    echo "ERROR: unknown arch - $ARCH. Must be either 'amd64' or 'arm64'"
    exit 1
  fi
  # Prune docker images to avoid platform conflicts
  docker system prune -fa
  ./build.sh "--${ARCH}" "${FLAVOR}" "${MCR_IMAGE_NAME}:localbuild"

  for ((i = 0; i < ${#TAGS[@]}; i++)) do
    local TAG="${TAGS[$i]}"
    tag_and_push "${MCR_IMAGE_NAME}:localbuild" "playwright.azurecr.io/public/${MCR_IMAGE_NAME}:${TAG}-${ARCH}"
  done
}

publish_docker_manifest () {
  local FLAVOR="$1"
  local TAGS=()
  if [[ "$FLAVOR" == "bionic" ]]; then
    TAGS=("${BIONIC_TAGS[@]}")
  elif [[ "$FLAVOR" == "focal" ]]; then
    TAGS=("${FOCAL_TAGS[@]}")
  elif [[ "$FLAVOR" == "jammy" ]]; then
    TAGS=("${JAMMY_TAGS[@]}")
  else
    echo "ERROR: unknown flavor - $FLAVOR. Must be either 'bionic', 'focal', or 'jammy'"
    exit 1
  fi

  for ((i = 0; i < ${#TAGS[@]}; i++)) do
    local TAG="${TAGS[$i]}"
    local BASE_IMAGE_TAG="playwright.azurecr.io/public/${MCR_IMAGE_NAME}:${TAG}"
    local IMAGE_NAMES=""
    if [[ "$2" == "arm64" || "$2" == "amd64" ]]; then
        IMAGE_NAMES="${IMAGE_NAMES} ${BASE_IMAGE_TAG}-$2"
    fi
    if [[ "$3" == "arm64" || "$3" == "amd64" ]]; then
        IMAGE_NAMES="${IMAGE_NAMES} ${BASE_IMAGE_TAG}-$3"
    fi
    docker manifest create "${BASE_IMAGE_TAG}" $IMAGE_NAMES
    docker manifest push "${BASE_IMAGE_TAG}"
  done
}

# Bionic
publish_docker_images_with_arch_suffix bionic amd64
publish_docker_manifest bionic amd64

# Focal
publish_docker_images_with_arch_suffix focal amd64
publish_docker_images_with_arch_suffix focal arm64
publish_docker_manifest focal amd64 arm64

# Jammy
publish_docker_images_with_arch_suffix jammy amd64
publish_docker_images_with_arch_suffix jammy arm64
publish_docker_manifest jammy amd64 arm64
