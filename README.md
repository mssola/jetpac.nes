This is a port to the NES/Famicom of the renown
[jetpac](https://en.wikipedia.org/wiki/Jetpac) game from Ashby Computers and
Graphics Limited (trading as Ultimate Play the Game). You can find a ROM to play
the game in the [releases
page](https://github.com/mssola/jetpac.nes/releases). Read the
[CONTRIBUTING.md](./CONTRIBUTING.md) file if you want to make any changes,
report an issue or make a suggestion.

# The game

The game is a shooter in which you have to re-assemble your ship's parts and
fill it with fuel, all while killing enemies that keep popping up. In the game
the controls are as follows:

| Button                                         | Action                 |
|:----------------------------------------------:|:-----------------------|
| <kbd>Start</kbd> & <kbd>Select</kbd>           | Pause/Resume the game  |
| <kbd>A</kbd> & <kbd>Arrow Up</kbd>             | Thrust                 |
| <kbd>Arrow Left</kbd> & <kbd>Arrow Right</kbd> | Fly or walk left/right |
| <kbd>Arrow Down</kbd>                          | Hover                  |
| <kbd>B</kbd>                                   | Shoot                  |

# Changes from the original

This port does not even attempt to be an exact replica of the original
game. This is in line to what most ports felt during those times. That is, for a
given game that was ported to multiple systems, you could always tell
differences, and not just aesthetic ones.

Being more specific, this port follows the original version with some
adjustments in order to make it a reality on the NES/Famicom, but I have not
been shy either on making some changes from my own taste. Read more on these
changes below.

## Merging the "loading" and the "title" screens

The player is presented with a title screen which is a merge between the
"Loading" and the title screens from the ZX Spectrum. On the NES/Famicom the
concept of "loading" is quite foreign to players (unless your are on the
[Famicom Disk System](https://en.wikipedia.org/wiki/Famicom_Disk_System), of
course), but at the same time I wanted to re-use at least some of its elements
on the otherwise quite blank title screen from the original. Hence, both screens
have been merged into something that feels more like it belongs to the
NES/Famicom library.

## Colors

One of the cool aspects from the original is how colorful things are. I have
tried to keep things the same way, but there are some considerations to be made.

First of all, colors are slightly different because of palette differences
between the NES/Famicom and the ZX Spectrum. Thus, don't expect the same
gradience of colors. More than that, some colors have been rearranged on
purpose, like the red on the jetpac's fire, just because I felt it was nicer and
it fit well with the overall coloring scheme.

The colors from bullets are also quite hard to pin down from the
original. Hence, I've done something that looks colorful and which is within the
palettes for this game. Couple this with what I mention below on shooting, and
you will quickly realize that shooting is a different experience than the
original version. Hopefully this is not too distracting to players which were
used at the original aesthetics.

Finally, whenever the player fills the shuttle with fuel tanks, the original
version displayed a small step of purple being filled in the shuttle. In the
NES/Famicom world this is basically done via [PPU attribute
tables](https://www.nesdev.org/wiki/PPU_attribute_tables), which cannot be that
precise. Hence, instead of doing it by purely vertical steps, you will notice
that the shuttle changes color in a slightly different way than in the
original. Also, note that the shuttle won't start blinking when full, as I find
it distracting.

## Controls

The controls of the player should be quite close to the original, even if
physics might be a bit different here and there. Overall, it shouldn't be too
distracting and I'm fine with them being slightly different to the original.

## Shooting

Shooting is something that is completely different to the original, as the
NES/Famicom presents a sprite limit per scanline which is quite daunting for a
shooter. I also envisioned doing nasty things on background tiles, but that is
hard to do and probably not worth it. In the end: different machine, different
rules. Hence, bullets are handled in a similar way as other games for the
NES/Famicom, even if it's not particularly close to the original.

## Scores

The amount of points gained on each event is basically as in the original (note
that some remakes re-arranged some of these things). But other than that, note
that shuttle parts and fuel tanks are only accounted when you drop them, not
when they are grabbed. This is different to the original game, but it made
things more simple on the technical side, and I actually believe it makes more
sense.

## SUSE coin

As an homage to Donkey Kong 64, you can collect a coin after completing 16
stages. This coin features a chameleon as a reference to SUSE, since I
originally bootstrapped this project during [Hackweek
23](https://hackweek.opensuse.org/projects/port-the-jetpac-game-to-the-nes).

# Technical thingies

This game is designed for the [NROM](https://www.nesdev.org/wiki/NROM) cartridge
board. Specifically, the 32K on PRG ROM capacity, and 8K on CHR ROM
capacity. This is the most basic cartridge board available, and it was more than
enough for this simple game. In fact, despite being completely careless on ROM
space, I only ended up filling ~30% of ROM space for this basic configuration
(check the exact numbers in the [CHANGELOG.md](./CHANGELOG.md) file).

Moreover, this is a game that doesn't do any scrolling. Thus, I could've picked
up any kind of mirroring for it, but here I'm using the horizontal one.

Last but not least, the build system produces both an NTSC and a PAL version of
the game. Coming from PAL territory myself, I've made an effort to make them
feel more or less the same way. That is, the PAL version shouldn't feel slower
in any way than the NTSC one. If that's not the case for you, [report an
issue](https://github.com/mssola/jetpac.nes/issues).

# License

The original game was developed and published by Ashby Computers and Graphics
Limited (trading as Ultimate Play the Game), and released for the ZX Spectrum
and VIC-20 in 1983 and the BBC Micro in 1984. Thus, the original idea is not
mine, and I only did the porting to the NES/Famicom platform. Similarly, all the
assets and the cover image are just sloppy ports that I did from the original
game. Thus, all credits for the original idea and artistic choices are entirely
on the original authors, not me.

This port is released under the
[GPLv3+](http://www.gnu.org/licenses/gpl-3.0.txt), Copyright (C) 2023-<i>Ω</i>
Miquel Sabaté Solà.
