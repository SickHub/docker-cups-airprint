#!/bin/bash

# login to docker
echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin &> /dev/null || exit 1

# push dev image (only latest)
if [ "$TRAVIS_BRANCH" = "dev" -a "$UBUNTU_VERSION" = "latest" ]; then
  docker buildx build --progress plain --platform $PLATFORMS --build-arg UBUNTU_VERSION=$UBUNTU_VERSION \
    -t $IMAGE:dev --push .
fi

# push master images (not when it's a pull request)
if [ "$TRAVIS_BRANCH" = "master" -a "$TRAVIS_PULL_REQUEST" = "false" ]; then
  # tag including ubuntu version
  if [ "$UBUNTU_VERSION" = "latest" ]; then
    docker buildx build --progress plain --platform $PLATFORMS --build-arg UBUNTU_VERSION=$UBUNTU_VERSION \
      -t $IMAGE:latest --push .
  else
    docker buildx build --progress plain --platform $PLATFORMS --build-arg UBUNTU_VERSION=$UBUNTU_VERSION \
      -t $IMAGE:$VERSION-$UBUNTU_VERSION --push .
  fi
fi