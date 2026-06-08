# Pashion Shell (pash)

A tiny experimental shell written in Zig. This project is currently under development and focused on core shell behavior and built-ins.

## Features (current)

- Simple interactive prompt (`#>`)
- Built-ins:
  - `cd`
    - `cd` changes to `$HOME`
    - `cd ~` expands to `$HOME` until shell expansion exists
    - `cd -` changes to `$OLDPWD` and prints new `$PWD`
    - supports `-L` logical paths (default) and `-P` physical paths
    - supports `--` to stop option parsing
    - searches `CDPATH` for relative, non-dot paths
    - updates `PWD` and `OLDPWD`
  - `exit`
- Runs external commands via `PATH`

## Requirements

- Zig installed and available on `PATH`

## Build

```sh
zig build
```

## Run

```sh
zig build run
```

You can also pass arguments to the binary:

```sh
zig build run -- --version
```

## Usage

Start shell, then enter commands at prompt.

### `cd`

```sh
cd              # go to $HOME
cd ~            # go to $HOME
cd -            # go to $OLDPWD and print new $PWD
cd -L path      # use logical path handling (default)
cd -P path      # use physical path after chdir
cd -- -dirname  # treat -dirname as path, not option
```

`cd` also honors `CDPATH` for relative paths that do not start with `.`, `..`, `/`, `./`, or `../`. Non-empty `CDPATH` matches print destination path.

## License

See `LICENSE`.
