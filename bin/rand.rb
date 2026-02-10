# frozen_string_literal: true

# See values on background.s
UPPER_MARGIN_Y_COORD = 0x1A
GROUND_Y_COORD = 0xC8 - 32 # NOTE: As in background.s - twice the size of the enemy.

# The available values for the Y axis for enemies are above ground, below the
# sky, and avoiding the left-most and right-most platforms.
available = (UPPER_MARGIN_Y_COORD..GROUND_Y_COORD).to_a - (0x58..0x69).to_a - (0x40..0x50).to_a

# With this produce the array containing a randomized sample from the
# 'available' values.
random_byte_array = Array.new(256) { '$%02X' % available.sample }

# And now print it in the assembler format.
random_byte_array.each_slice(16) do |row|
  puts ".byte #{row.join(', ')}"
end
