# CTF Tools WEB2

Static single-page CTF tools reference for GitHub Pages.

## Files hosted

- `index.html` redirects visitors to the main page.
- `ctf_tools.html` is the full web app.
- `.nojekyll` keeps GitHub Pages from filtering static files.
- `.github/workflows/static.yml` deploys the site with GitHub Actions.

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
