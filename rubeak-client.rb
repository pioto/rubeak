#!/usr/bin/env ruby
# vim: set tw=100 :

require 'drb'

$port = 7654

DRb.start_service()
rubeak = DRbObject.new(nil, "druby://localhost:#$port")

if ARGV.empty?
	while line = gets do
		puts "Sending action: #{line}"
		rubeak.doaction line.chomp
	end
else
	ARGV.each do |key|
		puts "Sending action: #{key}"
		rubeak.doaction key
	end
end
