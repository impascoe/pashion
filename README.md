# pashion shell

A tiny experimental shell written in Zig. This project is currently under development and focused on core shell behavior and built-ins.

## Features (current)

- Simple interactive prompt (`#>`)
- Built-ins:
  - `cd` (supports `cd`, `cd ~`, `cd -`)
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

- Start the shell, then enter commands at the prompt.

## License

See `LICENSE`.
