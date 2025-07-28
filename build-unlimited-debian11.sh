#!/bin/bash



if [ "$(id -u)" -ne 0 ]; then
  echo "Dieses Skript muss als root ausgeführt werden." >&2
  exit 1
fi

LOG_FILE="$(dirname "$0")/build-debian11.log"
# Log to file and stdout without buffering so we can see progress in real time
exec > >(stdbuf -oL tee "${LOG_FILE}") 2>&1

finish() {
  REPO_DIR="$(dirname "$0")"
  cp "${LOG_FILE}" "${REPO_DIR}/debian11debug"
  cd "${REPO_DIR}"
  git add debian11debug
  git commit -m "Update debian11debug"
}
trap finish EXIT

GH_USER="CVelar"
BRAND="CVelar"
PRODUCT_VERSION="8.0.1"
BUILD_NUMBER="31"

SSH_DIR="/root/.ssh"
mkdir -p "$SSH_DIR"
KEY_FILE="$SSH_DIR/id_rsa_${GH_USER}"
if [ ! -f "$KEY_FILE" ]; then
  ssh-keygen -t rsa -b 4096 -C "${GH_USER}@onlyoffice" -f "$KEY_FILE" -N ""
fi

# Ensure the generated key is used for github.com
chmod 600 "$KEY_FILE" "${KEY_FILE}.pub"
SSH_CONFIG="$SSH_DIR/config"
if ! grep -q "IdentityFile $KEY_FILE" "$SSH_CONFIG" 2>/dev/null; then
  {
    echo "Host github.com"
    echo "  IdentityFile $KEY_FILE"
  } >> "$SSH_CONFIG"
fi
chmod 600 "$SSH_CONFIG"

echo "\nÖffentlichen Schlüssel bei Github hinterlegen: https://github.com/settings/keys"
cat "${KEY_FILE}.pub"

echo "\nFolgende Repositories forken (in Github unter ${GH_USER}):"
echo "- https://github.com/btactic-oo/unlimited-onlyoffice-package-builder"
echo "- https://github.com/ONLYOFFICE/build_tools"
echo "- https://github.com/ONLYOFFICE/server"
echo "- https://github.com/ONLYOFFICE/web-apps"
read -rp "Nach dem Hochladen des Keys und dem Forken Enter drücken um fortzufahren..."

# Docker und Git installieren
apt update
apt remove -y docker docker-engine docker.io || true
apt install -y git apt-transport-https ca-certificates curl software-properties-common

# Ensure we have a recent Node.js for the build tools
NODE_MAJOR="$(node -v 2>/dev/null | sed -E 's/v([0-9]+).*/\1/' || true)"
if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 14 ]; then
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt install -y nodejs
fi

git config --global user.email "collinvelar@gmail.com"
git config --global user.name "CVelar"

curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce

mkdir -p ~/onlyoffice_repos
cd ~/onlyoffice_repos

git clone git@github.com:${GH_USER}/build_tools.git
git clone git@github.com:${GH_USER}/server.git
git clone git@github.com:${GH_USER}/web-apps.git

cd build_tools
git remote add upstream-origin git@github.com:ONLYOFFICE/build_tools.git
git remote add btactic-origin git@github.com:btactic-oo/build_tools.git
git checkout master
git pull upstream-origin master
git fetch --all --tags
git checkout tags/v${PRODUCT_VERSION}.${BUILD_NUMBER} -b ${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}

git cherry-pick 7ce465ecb177fd20ebf2b459a69f98312f7a8d3d
git cherry-pick 7da607da885285fe3cfc9feaf37b1608666039eb
sed -i "s/unlimited_organization = \"btactic-oo\"/unlimited_organization = \"${GH_USER}\"/g" scripts/base.py
sed -i "s/unlimited_tag_suffix = \"-btactic\"/unlimited_tag_suffix = \"-${BRAND}\"/g" scripts/base.py
git add scripts/base.py
git commit --amend --no-edit

git push origin ${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}
git tag -a "v${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}" -m "${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}"
git push origin "v${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}"

cd ../server
git remote add upstream-origin git@github.com:ONLYOFFICE/server.git
git remote add btactic-origin git@github.com:btactic-oo/server.git
git checkout master
git pull upstream-origin master
git fetch --all --tags
git checkout tags/v${PRODUCT_VERSION}.${BUILD_NUMBER} -b ${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}

git cherry-pick cb6100664657bc91a8bae82d005f00dcc0092a9c
git push origin ${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}
git tag -a "v${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}" -m "${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}"
git push origin "v${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}"

cd ../web-apps
git remote add upstream-origin git@github.com:ONLYOFFICE/web-apps.git
git remote add btactic-origin git@github.com:btactic-oo/web-apps.git
git checkout master
git pull upstream-origin master
git fetch --all --tags
git checkout tags/v${PRODUCT_VERSION}.${BUILD_NUMBER} -b ${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}

git cherry-pick 2d186b887bd1f445ec038bd9586ba7da3471ba05
git push origin ${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}
git tag -a "v${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}" -m "${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}"
git push origin "v${PRODUCT_VERSION}.${BUILD_NUMBER}-${BRAND}"

mkdir -p ~/build-oo
cd ~/build-oo
git clone git@github.com:${GH_USER}/unlimited-onlyoffice-package-builder.git
cd unlimited-onlyoffice-package-builder
git checkout v0.0.1
./onlyoffice-package-builder.sh --product-version=${PRODUCT_VERSION} --build-number=${BUILD_NUMBER} --unlimited-organization=${GH_USER} --tag-suffix=-${BRAND} --debian-package-suffix=-${BRAND}

echo "\nFertig. Das DEB Paket befindet sich unter: ~/build-oo/unlimited-onlyoffice-package-builder/document-server-package/deb/"

