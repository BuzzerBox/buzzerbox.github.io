# buzzerbox.github.io

The website of the BuzzerBox: a showcase of the project (landing page, hardware versions, use cases) and the
documentation of [BuzzUI](https://github.com/BuzzerBox/BuzzUI) and [BuzzController](https://github.com/BuzzerBox/BuzzController).
Built with Jekyll 4 and deployed to GitHub Pages by a GitHub Action.

## Where the content lives

| What | Where to edit |
|---|---|
| Landing page | `index.html` |
| Hardware versions | `_data/hardware.yml` (photos go into `assets/img/hardware/`, then set `image:`) |
| Use cases | `_data/use_cases.yml` |
| Events and the contact form | `events.html`, `de/veranstaltungen.html`, `_includes/contact-form.html`; the address is `contact_email` in `_config.yml` |
| Docs hub | `docs/index.html` |
| Look | `assets/css/site.css`, `_layouts/`, `_includes/` |
| The docs themselves | **in BuzzUI and BuzzController**, not here |

`scripts/sync-docs.rb` copies the docs from both repositories into `docs/user/`, `docs/developer/` and
`docs/hardware/`, rewrites their links and writes the sidebar (`_data/docs_nav.yml`). Those files are generated and
ignored by git. To add or reorder a doc page, edit `SECTIONS` in that script.

## Preview

With Docker, and BuzzUI and BuzzController checked out next to this repository:

```sh
scripts/serve.sh        # http://localhost:4000
```

With Ruby 3.x: `bundle install`, `ruby scripts/sync-docs.rb ../BuzzUI ../BuzzController`, `bundle exec jekyll serve`.

## Deployment

`.github/workflows/pages.yml` builds and deploys on every push to `main`, once a day, by hand (*Run workflow*), and
on a `repository_dispatch` of type `docs-updated`. In the repository settings, *Pages → Source* has to be
**GitHub Actions**.

The docs come from the branches set in `env` at the top of the workflow (`BUZZUI_REF`, `BUZZCONTROLLER_REF`).
A page or image folder missing on that branch is skipped with a warning in the build log, and links to it go to
GitHub instead.

To publish doc changes right away, BuzzUI and BuzzController can trigger a build when their docs change, with a
token that may dispatch to this repository:

```sh
gh api repos/BuzzerBox/buzzerbox.github.io/dispatches -f event_type=docs-updated
```

## License

The BuzzerBox name and logo (`assets/img/logo.png`, and the logo wherever it appears in screenshots) are not
covered by any open license; all rights reserved. They may not be reused without permission.
