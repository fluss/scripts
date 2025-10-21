#!/bin/bash
rm -- "$0"

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
rm .editorconfig .gitattributes .pnp.cjs

if [ -f "package.json" ]; then
    if command -v jq &> /dev/null; then
        jq '. + {"workspaces": ["app"]}' package.json > package.json.tmp && mv package.json.tmp package.json
        echo "✓ package.json has been updated with workspaces!"
    else
        sed -i.bak 's/"packageManager":/"workspaces": [\n    "app"\n  ],\n  "packageManager":/' package.json
        rm package.json.bak 2>/dev/null
        echo "✓ package.json has been updated with workspaces (using sed)!"
    fi
else
    echo "⚠ Warning: package.json not found, skipping workspace setup"
fi

echo "✓ .yarnrc.yml has been created successfully!"

mkdir app && cd app

echo "Going to create svelte project, follow the prompts: press enter for everything, selcet YES for existing project"  

npx sv create

yarn add @fluss/auth
yarn add vitest -D
yarn add @sveltejs/adapter-static -D

rm -rf static
rm .npmrc

cat > vite.config.ts << EOF
import { defineConfig } from "vitest/config";
import { sveltekit } from '@sveltejs/kit/vite';

export default defineConfig({
    plugins: [sveltekit()],
    ssr: {
        noExternal: ['@fluss/auth']
    },
    test: {
        include: ['src/**/*.{test,spec}.{js,ts}']
    }
});
EOF

cat > svelte.config.js << EOF
import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	preprocess: vitePreprocess(),

	kit: {
		adapter: adapter({
			pages: 'dist',
			assets: 'dist',
			precompress: false
		})
	}
};

export default config;
EOF

cd src

cat > app.html << EOF
<!doctype html>
<html lang="en">
	<head>
		<meta charset="utf-8" />
		<meta name="viewport" content="width=device-width, initial-scale=1" />
		%sveltekit.head%
	</head>
	<body data-sveltekit-preload-data="hover">
		<div style="display: contents">%sveltekit.body%</div>
	</body>
</html>
EOF

cd routes

cat > +layout.svelte << EOF
<script lang="ts">
</script>

<main>
  <slot />
</main>

<style>
  main {
    min-height: 100vh;
  }
</style>
EOF

cat > +page.svelte << EOF
<script lang="ts">
    import { authStore } from "@fluss/auth";
    import { onMount } from "svelte";
    import { get } from "svelte/store";

    $: loggedInState = false

    onMount(async() => {
        const authState = get(authStore)
        const accessToken = authState.accessToken
        if (accessToken) {
            const verified = await authStore.verifyTokens()
            if (!verified) {
                await authStore.refreshToken()
            }
            loggedInState = true
        } else {
            await authStore.startAuthFlow()
        }

    })
</script>


<main class="d-flex justify-content-center align-items-center vh-100">
	{#if loggedInState}
		<h1 class="fw-bold">You are logged in</h1>
	{/if}
</main>
EOF

mkdir auth && cd auth
mkdir callback && cd callback


cat > +page.svelte << 'EOF'
<script lang="ts">
  import { onMount } from 'svelte'
  import { goto } from '$app/navigation'
  import { page } from '$app/stores'
  import { authStore } from '@fluss/auth'

  let loading = true
  let error = ''

  onMount(async () => {
    const code = $page.url.searchParams.get('code')
    const errorParam = $page.url.searchParams.get('error')

    if (errorParam) {
      error = `Authentication error: ${errorParam}`
      loading = false
      return
    }

    if (!code) {
      error = 'No authorization code received'
      loading = false
      return
    }

    try {
      await authStore.handleAuthCallback(code)
      goto('/')
    } catch (err: any) {
      error = err.message
    } finally {
      loading = false
    }
  })
</script>

{#if loading}
  <div>
    <div>
      <div></div>
      <p>Completing authentication...</p>
    </div>
  </div>
{:else if error}
  <div>
    <div>
      <div>
        <h2>Authentication Failed</h2>
        <p>{error}</p>
        <button 
          on:click={() => goto('/')}
        >
          Return Home
        </button>
      </div>
    </div>
  </div>
{/if}
EOF

cd ../../../../../

echo "Svelte project created cd into app and run 'yarn dev' and your app should run locally" 
echo
echo "The final step is to setup your config.json - Please supply the following:"

echo "Please enter your clientId (this should match in your backend):"
read -s CLIENT_ID
echo

echo "Please enter your authorisation url:"
read -s AUTH_URL
echo

echo "Your redirect url has been set to http://localhost:5173/auth/callback"

if [ -z "$CLIENT_ID" ]; then
    echo "Error: clientId cannot be empty"
    exit 1
fi

if [ -z "$AUTH_URL" ]; then
    echo "Error: authorisation url cannot be empty"
    exit 1
fi

cat > config.json << EOF
{
  "auth": {
    "clientId": "$CLIENT_ID",
    "AUTH_URL": "$AUTH_URL",
    "REDIRECT_URL": "http://localhost:5173/auth/callback"
  }
}
EOF

cd app

echo "Run yarn dev to generate the .sveltekit, you may need to run this twice"s