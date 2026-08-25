# Installation

Copy the resource directory to `resources/[standalone]/gnsh-portops`, add
`ensure gnsh-portops` after the selected framework and oxmysql resources, and
set `config.environment` to `production` with `database.provider = 'oxmysql'`.
Run the migration matrix before enabling gameplay integrations; no source edits
are required for a supported framework.
