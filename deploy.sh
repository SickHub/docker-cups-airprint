#!/bin/sh

# Variables
# DOCKER_USER, DOCKER_PASS, DOCKER_REGISTRY : for login to docker registry
# BRANCH, PULL_REQUEST : flow control, distinguish `master` and `dev` branch, only build and push if not a PR
# PLATFORMS : platform to build the image for
# IMAGE : name of the image (incl. path/repository, excluding tag)
# VERSION : build arg for the docker image
# TAG_CMD : command to get the version from within the image

## defaults
DOCKER_REGISTRY=${DOCKER_REGISTRY:="docker.io"}
PLATFORMS=${PLATFORMS:="linux/amd64,linux/arm,linux/arm64"}
VERSION=${VERSION:="latest"}
PULL_REQUEST=${PULL_REQUEST:-"false"}

# compatibility with Travis-CI
[ -n "$TRAVIS_BRANCH" ] && BRANCH=$TRAVIS_BRANCH
[ -n "$TRAVIS_PULL_REQUEST" ] && PULL_REQUEST=$TRAVIS_PULL_REQUEST

# compatibility with GitLab-CI
[ -n "$CI_COMMIT_BRANCH" ] && BRANCH=$CI_COMMIT_BRANCH
[ -z "$CI_COMMIT_BRANCH" ] && PULL_REQUEST=true

# compatibility with Circle-CI

echo "Building $IMAGE on branch '$BRANCH' : $VERSION for $PLATFORMS + pushing to $DOCKER_REGISTRY"

# login to docker
echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin &> /dev/null || exit 1

# build+push dev image (only latest)
if [ "$BRANCH" = "dev" -a "$VERSION" = "latest" ]; then
  docker buildx build --progress plain --platform $PLATFORMS --build-arg VERSION=$VERSION \
    -t $IMAGE:dev --push .
fi

# build+push master images (not when it's a pull request)
if [ "$BRANCH" = "master" -a "$PULL_REQUEST" = "false" ]; then
  # tag including ubuntu version
  if [ "$VERSION" = "latest" ]; then
    docker buildx build --progress plain --platform $PLATFORMS --build-arg VERSION=$VERSION \
      -t $IMAGE:latest --push .
  else
    tag=$VERSION
    if [ -n "$TAG_CMD" ]; then
      # build single platform and load it into local docker repository, so we can launch it to version
      docker buildx build --progress plain --platform linux/amd64 --build-arg VERSION=$VERSION \
        -t $IMAGE --load .
      v=$($TAG_CMD)
      tag=$v-$VERSION
    fi
    # build for all platforms and push with correct version tag
    docker buildx build --progress plain --platform $PLATFORMS --build-arg VERSION=$VERSION \
      -t $IMAGE:$tag --push .
  fi
fi
