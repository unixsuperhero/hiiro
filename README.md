# hiiro

Extensible CLI utilities.

# Install

Copy `bin/h` to somewhere in your `$PATH`
Copy any plugins into `~/.config/hiiro/plugins/`

# Usage

```sh
$> h
Subcommand required.

Possible subcommands:
  yt
  pin
  project
  edit
  ping

$> h ping
pong
```

# Extending

There are 2 ways to add subcommands.

1. Executables
2. Subcommands

## Executables

Add an executable to your path in the format of `basecmd-subcommand`.

Here are some examples:

- `h-example` - this will allow you to run `h example`
- `h-example-subsubcommand` - if `h-example` uses hiiro, then it will
recognize `subsubcommand` as a valid subcommand.

## Subcommands

Using hiiro in a new script looks like this:

> ~/bin/h-example

```ruby
#!/usr/bin/env ruby

load File.join(Dir.home, 'bin/h')

executable = Hiiro.init(*ARGV) do |hiiro|
  hiiro.add_subcommand(:hello) do |*args|
    puts "Hi!"
  end

  hiiro.add_subcommand(:foo) do |*args|
    puts "Foobar"
  end
end
```

Now example has the 2 subcommands `hello` and `foo`.

```sh
$> h example hello
Hi!

$> h example foo
Foobar
```

## Shorthand

You can abbreviate any subcommand, as long as the abbreviation
uniquely matches to one subcommand.

```sh
$> h ex hel
Hi!
```

In this example, `ex` will match `example` and `hel` with match `hello`.

# Plugins

....

# In Practice

This allows me to make useful multi-use tools.  Similar to how `git`
or `docker` are central tools that have many uses.

