# Local test environments

The plugin has no tests of its own that can run standalone: every spec boots a
real Redmine host application. These scripts create such a host, sync the
working tree into it and run the suite.

## Prerequisites

* `git`, `rsync`, a C toolchain, and the client headers for the database you
  want to use (`libpq-dev` for PostgreSQL, `libmysqlclient-dev` /
  `libmariadb-dev` for MySQL and MariaDB).
* A running database server, and a `redmine` account that may create databases:

  ```sh
  # PostgreSQL
  sudo -u postgres psql -c "CREATE ROLE redmine LOGIN CREATEDB PASSWORD 'redmine';"

  # MySQL / MariaDB
  mysql -uroot -e "CREATE USER 'redmine'@'localhost' IDENTIFIED BY 'redmine';
                   GRANT ALL PRIVILEGES ON *.* TO 'redmine'@'localhost' WITH GRANT OPTION;"
  ```
* A Ruby matching the Redmine branch under test. `rbenv` is used when a version
  is passed; otherwise the ambient Ruby is used.

  | Redmine | Rails | Ruby used here |
  | ------- | ----- | -------------- |
  | 5.1     | 6.1   | 3.2            |
  | 6.1     | 7.2   | 3.3            |
  | 7.0     | 8.1   | 3.3            |

## Usage

```sh
# clone Redmine, install gems, create and migrate the database
dev/setup.sh 5.1-stable postgresql 3.2.6

# sync the working tree and run the specs (repeat after every edit)
dev/run.sh .redmine/5.1-stable-postgresql

# a single file, or any other rspec argument
dev/run.sh .redmine/5.1-stable-postgresql plugins/redmine_project_workflows/spec/services
```

`setup.sh` takes `[redmine-branch] [postgresql|mysql] [ruby] [target-dir]` and
defaults to Redmine 5.1 on PostgreSQL, under `.redmine/` in this repository.
`DB_NAME`, `DB_USER`, `DB_PASS`, `DB_HOST` and `DB_PORT` override the connection.

The plugin is copied rather than symlinked: the specs resolve
`config/environment` relative to their own real path, which a symlink breaks.

## Continuous integration

`.github/workflows/specs.yml` runs the same scripts across Redmine 5.1 / 6.1 /
7.0 and PostgreSQL / MySQL / MariaDB on every push and pull request.

## Spec layout

| Directory              | Purpose |
| ---------------------- | ------- |
| `spec/services`, `spec/models`, `spec/controllers`, `spec/helpers`, `spec/views` | Behaviour the plugin intends to provide. |
| `spec/integration`     | Guards that each Deface override still matches an anchor in the host's views. An unmatched override fails silently, so this must be checked per Redmine version. |
| `spec/characterization` | Behaviour that is currently **wrong**, pinned so that fixes are deliberate. When a defect is repaired, invert or delete its example — never make it green again. |
