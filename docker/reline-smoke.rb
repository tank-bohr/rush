#!/usr/bin/env ruby
# frozen_string_literal: true

# Reline pty smoke: drive exe/rush on a real pseudo-terminal — the boundary
# the native gate cannot cover (SystemCalls#edit_line is :nocov:). Asserts
# that the PS1 prompt is drawn, an edited line executes, and exit's status
# survives the editor.
require 'English'
require 'pty'
require 'timeout'

read_until = lambda do |out, pattern|
  buffer = +''
  buffer << out.readpartial(4096) until buffer.match?(pattern)
  buffer
end

PTY.spawn('bundle', 'exec', 'ruby', '-Ilib', 'exe/rush', '-i') do |out, inp, pid|
  Timeout.timeout(30) do
    read_until.call(out, /\$ /)
    inp.write("echo $((6*7))\r")
    read_until.call(out, /42/)
    inp.write("exit 7\r")
    Process.waitpid(pid)
    status = $CHILD_STATUS.exitstatus
    abort "rush Reline pty smoke: expected exit 7, got #{status.inspect}" unless status == 7
  end
end

puts 'rush Reline pty smoke ok: prompt drawn, edited line executed, exit status preserved'
