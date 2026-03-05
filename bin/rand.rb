# frozen_string_literal: true

##
# Generate a table of 256 bytes of pseudo-random values. These values are
# constrained with the upper and lower margins of the screen where enemies can
# appear, and discard certain positions like platforms that can be troublesome
# on enemy creation. All in all not exactly super pure randomness, but on the
# other hand this game just needs a bit of randomness.
#
# Whenever you update values on background.s, you are supposed to call this
# script again and replace the values on 'valid_y_rand_table' in prng.s.

# See values on background.s. They are the same +/- some margin so enemies are
# not right on the border.
UPPER_MARGIN_Y_COORD = 0x1A + 32
GROUND_Y_COORD = 0xC8 - 64

# The available values for the Y axis for enemies are above ground, below the
# sky, and avoiding the left-most and right-most platforms.
available = (UPPER_MARGIN_Y_COORD..GROUND_Y_COORD).to_a - (0x58..0x69).to_a - (0x40..0x50).to_a
available = available.shuffle

# With this produce the array containing a randomized sample from the
# 'available' values.
random_byte_array = (0...256).map do |i|
  format('$%02X', available[i % available.length])
end

# And now print it in the assembler format.
random_byte_array.each_slice(16) do |row|
  puts ".byte #{row.join(', ')}"
end
