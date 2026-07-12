# CTF Tools WEB2

Static single-page CTF tools reference for GitHub Pages.

## Files hosted

- `index.html` redirects visitors to the main page.
- `ctf_tools.html` is the full web app.
- `data/editor-store.json` is the shared GitHub cloud store for edits/blogs.
- `.nojekyll` keeps GitHub Pages from filtering static files.
- `.github/workflows/static.yml` deploys the site with GitHub Actions.

## Cloud editing

The web app can read shared edits from GitHub automatically. To save edits back to the cloud, open `GitHub Cloud` in the web app and enter a GitHub token that has `Contents: Read and write` permission for this repository.

Edits are saved to:

```text
data/editor-store.json
```

## GitHub Pages hosting

1. Open the repository on GitHub.
2. Go to `Settings` -> `Pages`.
3. Under `Build and deployment`, set `Source` to `GitHub Actions`.
4. Push to the `main` branch.
5. Wait for the `Deploy static content to Pages` workflow to finish.
6. Open:

```text
https://madara12345obito.github.io/HackTool/
```

If the page shows `404`, wait a minute and refresh, or check the Actions tab for a failed deploy.
