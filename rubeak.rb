#!/usr/bin/env ruby
# vim set tw=100 :

require 'xosd_bar'
require 'xosd'
require 'thread'
require 'drb'

include XOSD

$port = 7654
$colors = {
	'unmuted' => 'green',
	'mute' => 'red',
}

class Rubeak
	def initialize
		@osdbar = XosdBar.new
		@osdbar.position=BOTTOM
		@osdbar.vertical_offset=100
		@osdbar.align=CENTER
		@osdbar.font="-*-fixed-*-*-*-*-18-*-*-*-*-*-*-*"
		@osdbar.outline_offset=1
		@osdbar.outline_color='black'

		@osd = Xosd.new(3)
		@osd.position=MIDDLE
		@osd.align=CENTER
		@osd.font="-*-fixed-*-*-*-*-18-*-*-*-*-*-*-*"
		@osd.outline_offset=1
		@osd.outline_color='black'

	end

	# Gets the current volume from alsa
	def getvol
		f = IO::popen('amixer sget Master')
		vol=-1
		mute=false
		line=''
		f.readlines.each { |l| line = l if l.match '^  Front Left' }
		if line.match '\[off\]$'
			mute=true
		end
		md = line.match '\[(\d*)%\]'
		vol=md.to_a[1].to_i if md
		return { 'vol' => vol, 'mute' => mute }
	end

	# Shows the current volume w/ xosd.
	def showvol
		vm = getvol
		if vm['mute']
			@osdbar.color=$colors['mute']
			@osdbar.title='Volume (Muted)'
		else
			@osdbar.color=$colors['unmuted']
			@osdbar.title='Volume'
		end

		@osdbar.value=vm['vol']
		@osdbar.timeout=5
	end

	# show the output of the mpc command (our current mucic state)
	def showmpc
		mpc = IO::popen("mpc")
		line=0
		mpc.each do |l| 
			@osd.display_message(line,l.chomp)
			line=line+1
		end
		@osd.timeout=5
	end

	# Does magic stuff for the given action
	def doaction (key)
		case key
		when 'mute'
			vm = getvol
			if vm['mute']
				system('amixer sset Master unmute &>/dev/null')
			else
				system('amixer sset Master mute &>/dev/null')
			end
			showvol
		when 'vol+'
			vm = getvol
			vol=vm['vol'] + 5
			if vol > 100
				vol = 100
			end
			system("amixer sset Master #{vol}% &>/dev/null")
			showvol
		when 'vol-'
			vm = getvol
			vol=vm['vol'] - 5
			if vol < 0
				vol = 0
			end
			system("amixer sset Master #{vol}% &>/dev/null")
			showvol
		when 'play-pause'
			mpc = IO::popen("mpc")
			mpc.each do |x|
				/^\[/.match(x) or next
				if /\[playing\]/.match(x)
					system("mpc pause &>/dev/null")
				else
					system("mpc play &>/dev/null")
				end
			end
			showmpc
		when 'prev'
			system("mpc prev &>/dev/null")
			showmpc
		when 'next'
			system("mpc next &>/dev/null")
			showmpc
		when 'stop'
			system("mpc stop &>/dev/null")
			showmpc
		when 'power'
			xset = IO::popen("xset -q")
			xset.each do |x|
				/Monitor/.match(x) or next
				if /Off/.match(x)
					system("xset dpms force on &>/dev/null")
				else
					system("xset dpms force off &>/dev/null")
				end
			end
		when 'display'
			showmpc
			showvol
		else
			puts "!!! Unknown action: '#{key}'"
		end
	end

	# Reads in data from the hid_read program. this is one of 2 possible sources of commands,
	# the other being DRb
	def readir
		puts '>>> Reading IR data from hid_read...'
		hid_read = IO::popen("#{ENV['HOME']}/src/creative_rm1500_usb-0.1/hid_read")

		hid_read.each do |l|
			md = l.match ' \+ got key\(..\): (.*)'
			next if not md
			key=md.to_a[1]
			doaction key
		end
	end
end

rubeak = Rubeak.new

puts ">>> Starting DRb server on port #$port..."
dserv = DRb.start_service("druby://localhost:#$port",rubeak)

rubeak.readir

dserv.thread.join
