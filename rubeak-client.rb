#!/usr/bin/env ruby
# vim: set tw=100 :

require 'drb'

$port = 7654

DRb.start_service()
rubeak = DRbObject.new(nil, "druby://localhost:#$port")

if ARGV.empty?
	while line = gets do
		puts "Sending action: #{line}"
		rubeak.do_action line.chomp
	end
else
	ARGV.each do |key|
		puts "Sending action: #{key}"
		rubeak.do_action key
	end
end
