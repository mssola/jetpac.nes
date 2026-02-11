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

# See values on background.s
UPPER_MARGIN_Y_COORD = 0x1A
GROUND_Y_COORD = 0xC8 - 32 # NOTE: As in background.s - twice the size of the enemy.

# The available values for the Y axis for enemies are above ground, below the
# sky, and avoiding the left-most and right-most platforms.
available = (UPPER_MARGIN_Y_COORD..GROUND_Y_COORD).to_a - (0x58..0x69).to_a - (0x40..0x50).to_a

# With this produce the array containing a randomized sample from the
# 'available' values.
random_byte_array = Array.new(256) { format('$%02X', available.sample) }

# And now print it in the assembler format.
random_byte_array.each_slice(16) do |row|
  puts ".byte #{row.join(', ')}"
end
