# Memo Monorepo

This repository keeps the existing `somyun/memo` GitHub project while organizing each client in its own folder.

## Structure

- `memo-web/`: static GitHub Pages web app.
- `memo-android/`: standalone Android project. Build from this directory with Gradle.
- `memo-desktop/`: standalone desktop app project.
- `uploads/`: repository-root attachment storage used by the web app through the GitHub API.

## GitHub Pages

GitHub Pages is deployed from `memo-web/` through `.github/workflows/deploy-pages.yml`. The artifact root is `memo-web`, so the public Pages URL keeps serving `memo-web/index.html` at the site root.

The web app still uploads attachments to repository-root `uploads/` paths. This preserves existing jsDelivr and raw GitHub URLs such as `uploads/...`.
