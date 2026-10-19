# open-website

[中文](README.md) | [English](README.en.md)

Open IM marketing and static content site (downloads, account cancellation, developer pages), built with plain HTML + Nginx and deployed as a container.

## Content layout

```text
html/        site pages (download / cancel / developer, etc.)
nginx/       Nginx site config
k8s/         Kubernetes manifests
docs/        deployment and release notes
scripts/     build helpers
Dockerfile   container image
```

## Build and deploy

The site is static; build output ships in the container image. See `docs/` and `k8s/` for deployment.

The local Kind bootstrap is orchestrated by `open-im-server/scripts/deploy/k8s.ps1`; the site is served at
`http://<host>:30080/website/`. The download and cancellation pages use same-origin `/api/v1` and never embed
gateway domains, intranet addresses, accounts or secrets in static files.

Run before committing:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
```

## License

[Apache License 2.0](LICENSE), maintained by [openware-io](https://github.com/openware-io).
