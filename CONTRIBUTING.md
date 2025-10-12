## Why?

- You want to make a suggestion on something that could be improved.
- You want to report a bug, something that doesn't work as expected.
- You know of a sick 6502 assembly technique that could be applied.

I am open for discussion and welcome any help!

## How?

There are many ways to help me out. One way might be to open an issue on
[Github's tracker](https://github.com/mssola/jetpac.nes/issues) and start a
discussion. For this, mind the following:

- Check that the issue has not already been reported or fixed in `main`.
- Try to be concise and precise in your description.
- If you have found a problem, provide a step by step guide on how to reproduce it.
- Provide the version you are using (git commit SHA), as well as the version of
  the toolchain and the emulator/system being used.

Another way is to simply submit a pull request. For this, also mind these:

- Write a [good commit message](https://chris.beams.io/posts/git-commit/).
- You are sure that `make` continues to work.
- The game continues to work.
- The pull request has *only* one subject and a clear title. You are not
  submitting a pull request with tons of different unrelated commits.

## Development cycle

In order to test your changes, I'd go this way:

1. Make sure that you have the toolchain installed. For this you can call `make
   deps` and it will error out if you are missing anything.
2. Make your changes in the code and run `make`. This will produce the ROM
   inside of the `out` directory.
3. Run the ROM that was produced with an emulator of your choosing. Make sure
   that things run as expected.

### Customizing the build process

You can pass the following arguments to `make`:

- `CC65`: the compiler to use (defaults to
  [xa65](https://github.com/mssola/tools.nes) if that exists, otherwise `cl65`).
- `CCOPTS`: the options to use for the compiler (defaults to `--target nes` and
  it adds `--strict` if using `xa65`).
- `RUBY`: the ruby to use (defaults to `ruby`).

## Modifying assets

I am using [NEXXT studio 3](https://frankengraphics.itch.io/nexxt) for managing
the assets. This is why you will find a [sessions.nss](./assets/sessions.nss)
file from which you will be able to load the same environment I have been using
in order to manage my assets. All of that being said, whenever you are done
modifying the assets, do the following:

1. Save the session so it can be viewed on Git.
2. Save the 8KB of pattern data from sets A+B and save them into
   [./assets/jetpac.chr](./assets/jetpac.chr).
3. Save both screens into `.nam` files, as you can see on [./assets](./assets).
