#!/usr/bin/env ruby
# frozen_string_literal: true

##
# Generate the different values on `config/values/*.s` by parsing the values on
# `config/values.yml`. The values on that file are agnostic to NTSC or PAL, and
# it's up to this script to produce constants which make sense for NTSC and PAL.
# That is, it's a way to ensure that both NTSC and PAL have the same experience
# (or at least as close as possible).

##
# Parse the configuration.

require 'yaml'

config_path = File.join("#{File.dirname(__FILE__)}/..", 'config/')
config = YAML.safe_load_file(File.join(config_path, 'values.yml'))

# Converts the given floating point value into a signed fixed point value in the
# 4.4 format.
def to_signed_fixed_point(value)
  integer = value.to_i
  raise 'bad signed fixed point value' if integer > 7 || integer < -7

  integer &= 0b00001111

  decimal = (value % 1) * 100
  decimal = ((decimal * 15) / 100.0).round & 0b00001111

  (integer << 4) | decimal
end

##
# Loop through the configuration and fetch values for NTSC and PAL.

res = {}
config.each do |model, properties|
  res[model] ||= { ntsc: {}, pal: {} }

  properties.each do |name, ntsc|
    name = name.upcase
    pal  = (ntsc * 6) / 5.0

    res[model][:ntsc][name] = to_signed_fixed_point(ntsc)
    res[model][:pal][name] = to_signed_fixed_point(pal)
  end
end

##
# Generate each model as expected.

def to_hex(value)
  hex = value.to_s(16).upcase

  if hex.size == 1
    "$0#{hex}"
  else
    "$#{hex}"
  end
end

def values_to_asm(values)
  values.map { |k, v| "    #{k} = #{to_hex(v)}" }.join("\n")
end

res.each do |model, formats|
  path = File.join(config_path, "values/#{model}.s")
  contents = <<~HERE
    ;; This file has been automatically generated via bin/values.rb.
    ;; DO NOT MODIFY this file directly: check config/values.yml instead.

    .ifdef PAL
    #{values_to_asm(formats[:pal])}
    .else
    #{values_to_asm(formats[:ntsc])}
    .endif
  HERE

  File.write(path, contents)
end
