#!/bin/bash

echo "installing jq"
brew install jq

echo "Please enter your GitHub token:"
read -s GITHUB_TOKEN
echo

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GitHub token cannot be empty"
    exit 1
fi

cat > .yarnrc.yml << EOF
nodeLinker: node-modules
enableGlobalCache: true
enableTelemetry: false
npmRegistryServer: "https://registry.npmjs.org"

npmRegistries:
  "https://npm.pkg.github.com":
    npmAuthToken: $GITHUB_TOKEN

npmScopes:
  fluss:
    npmRegistryServer: "https://npm.pkg.github.com"
    npmPublishRegistry: "https://npm.pkg.github.com"
EOF

yarn init
rm .editorconfig .gitattributes

if [ -f "sst.config.ts" ]; then
    if grep -q "await import('./infra/authModule')" sst.config.ts; then
        echo "✓ sst.config.ts already contains the authModule import"
    else
        awk '
        {
          if ($0 ~ /async run\(\) *{ *}/) {
            sub(/async run\(\) *{ *}/, "async run() {\n    await import(\"./infra/authModule\")\n  }")
          }
          print
        }' sst.config.ts > sst.config.ts.tmp \
        && mv sst.config.ts.tmp sst.config.ts
        echo "✓ sst.config.ts has been updated with authModule import!"
    fi
else
    echo "⚠ Warning: sst.config.ts not found, skipping SST config setup"
fi

echo "✓ .yarnrc.yml has been created successfully!"

yarn add sst @fluss/auth

mkdir infra && cd infra
cat > authModule.ts << EOF
import { Auth } from '@fluss/auth/server'

const authoriser = new Auth()

export const { auth, userTable, authoriserFunction } = authoriser.createAuthoriser()
EOF

cd ../

echo "Initialising SST, follow the prompts"

yarn sst init

if [ -f "sst.config.ts" ]; then
    if grep -q "await import('./infra/authModule')" sst.config.ts; then
        echo "✓ sst.config.ts already contains the authModule import"
    else
      sed -i.bak "s/async run() { }/async run() {\n    await import('.\/infra\/authModule')\n  }/" sst.config.ts
      rm sst.config.ts.bak 2>/dev/null
      echo "✓ sst.config.ts has been updated with authModule import!"
    fi
else
    echo "⚠ Warning: sst.config.ts not found, skipping SST config setup"
fi

echo "Please add credentials and regions to your sst config before running an example is like:"
cat << 'EOF'
export default $config({
  app(input) {
    return {
      name: 'mysite',
      removal: input?.stage === 'live' ? 'remove' : 'remove',
      protect: [''].includes(input?.stage),
      home: 'aws',
      providers: input?.stage === "live" ? {
        aws: {
          profile: "my_site",
          region: "af-south-1", 
        }
      } : {}
    };
  },
});
EOF

echo "Final step is to setup your config.json - please ensure that the specified info matches what is in your frontend"

echo "Please enter your clientId (this should match in your backend):"
read -s CLIENT_ID
echo

if [ -z "$CLIENT_ID" ]; then
    echo "Error: clientId cannot be empty"
    exit 1
fi

cat > config.json << EOF
{
  "auth": {
    "clientId": "$CLIENT_ID",
     "authoriser": true
  }
}
EOF

echo "once you have setup your profile and region for your sst config, deploy by running yarn sst deploy --stage=<YOUR_STAGE> or yarn sst dev --stage=<YOUR_STAGE>"

rm -- "$0"