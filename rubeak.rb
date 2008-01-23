#!/usr/bin/env ruby
# vim: set tw=100 :

require 'xosd_bar'
require 'xosd'
require 'thread'
require 'socket'
require 'drb'

include XOSD

# Configuration:

# The port to run the DRb server on. If you change this, be sure to change it in rubeak-client.rb as
# well.
$port = 7654

# The colors used when the volume is muted or unmuted.
$colors = {
	:unmuted => 'green',
	:mute => 'red',
}
$media_modes = [ 'mpd', 'lastfm' ]

# The path to the hid_read program, from the creative_rm1500_usb package, available at
# http://ecto.teftin.net/rm1500.html
#
# If you don't have this remote (chances are you don't), comment this line out, and uncomment the
# other one:
$hid_read_path="#{ENV['HOME']}/src/creative_rm1500_usb-0.1/hid_read"
#$hid_read_path=nil

class Rubeak
	def initialize
		@volumebar = XosdBar.new
		@volumebar.position=BOTTOM
		@volumebar.vertical_offset=100
		@volumebar.align=CENTER
		@volumebar.font="-*-*-*-r-*-*-24-*-*-*-*-*-*-*"
		@volumebar.outline_offset=1
		@volumebar.outline_color='black'

		@mpdosd = Xosd.new(3)
		@mpdosd.position=MIDDLE
		@mpdosd.align=CENTER
		@mpdosd.font="-*-*-*-r-*-*-24-*-*-*-*-*-*-*"
		@mpdosd.outline_offset=1
		@mpdosd.outline_color='black'

		@statusosd = Xosd.new(1)
		@statusosd.position=TOP
		@statusosd.vertical_offset=100
		@statusosd.align=CENTER
		@statusosd.font="-*-*-*-r-*-*-24-*-*-*-*-*-*-*"
		@statusosd.outline_offset=1
		@statusosd.outline_color='black'

		@media_mode=$media_modes[0]

		@mutex=Mutex.new
	end

	# Gets the current volume from alsa
	def getvol
		IO::popen('amixer sget Master') do |f|
			f.read.scan(/Front Left.*?\[(\d+)%\].*?\[(on|off)\]\n/) do |pc, on_or_off|
				return {
					:vol => pc.to_i,
					:mute => 'off' == on_or_off
				}
			end
		end
		return { :vol => -1, :mute => false }
	end

	# Shows the current volume w/ xosd.
	def showvol
		vm = getvol
		if vm[:mute]
			@volumebar.color=$colors[:mute]
			@volumebar.title='Volume (Muted)'
		else
			@volumebar.color=$colors[:unmuted]
			@volumebar.title='Volume'
		end

		@volumebar.value=vm[:vol]
		@volumebar.timeout=5
	end

	# show the output of the mpc command (our current mucic state)
	def show_mpd
		IO::popen("mpc") do |mpc|
			line=0
			mpc.each do |l| 
				@mpdosd.display_message(line,l.chomp)
				line=line+1
			end
		end
		@mpdosd.timeout=5
	end

	# Send the given command to the shell-fm process. Returns nil if no response is given.
	def send_lastfm(cmd)
		answer=nil
		begin
			TCPSocket.new('127.0.0.1', 54311) do |t|
				t.print "#{cmd}\n"
				answer=t.gets(nil)
				puts "LASTFM: #{answer}"
			end
		rescue
		end
		answer=nil if /(null)/.match(answer)
		return answer
	end

	def show_lastfm
		answer=send_lastfm "info Now Playing: %a - %t [%l]"
		answer = "Not playing." if answer.nil?
		@mpdosd.display_message(0,"")
		@mpdosd.display_message(1,answer.chomp)
		@mpdosd.display_message(2,"")
		@mpdosd.timeout=5
	end

	# Does magic stuff for the given action
	def doaction (key)
		@mutex.synchronize do
			case key
			# Volume Control
			when 'mute'
				vm = getvol
				if vm[:mute]
					system('amixer sset Master unmute &>/dev/null')
				else
					system('amixer sset Master mute &>/dev/null')
				end
				showvol
			when 'vol+'
				system("amixer sset Master 1+ &>/dev/null")
				showvol
			when 'vol-'
				system("amixer sset Master 1- &>/dev/null")
				showvol
			# Media Player control
			when 'play-pause', 'play', 'pause'
				case @media_mode
				when 'mpd'
					IO::popen("mpc") do |mpc|
						mpc.each do |x|
							/^\[/.match(x) or next
							if /\[playing\]/.match(x)
								system("mpc pause &>/dev/null")
								show_mpd
								return
							end
						end
					end
					system("mpc play &>/dev/null")
					show_mpd
				when 'lastfm'
					i=send_lastfm "info %u"
					if i.nil?
						last_track=""
						File.open("#{ENV['HOME']}/.shell-fm/radio-history") \
							{ |f| last_track=f.to_a[-1] }
						send_lastfm "play lastfm://#{last_track}"
						@statusosd.display_message(0,
							"Playing last played track...")
						@statusosd.timeout=5
					else
						send_lastfm "pause"
						@statusosd.display_message(0,
							"Pausing/resuming lastfm...")
						@statusosd.timeout=5
					end
				end
			when 'rec', 'favorite'
				case @media_mode
				when 'lastfm'
					send_lastfm "love"
					@statusosd.display_message(0,"Current lastfm track loved.")
					@statusosd.timeout=5
				end
			when 'prev'
				case @media_mode
				when 'mpd'
					system("mpc prev &>/dev/null")
					show_mpd
				when 'lastfm'
				end
			when 'next'
				case @media_mode
				when 'mpd'
					system("mpc next &>/dev/null")
					show_mpd
				when 'lastfm'
					send_lastfm "skip"
					@statusosd.display_message(0,"Skipping current lastfm track...")
					@statusosd.timeout=5
				end
			when 'stop-eject', 'stop'
				case @media_mode
				when 'mpd'
					system("mpc stop &>/dev/null")
					show_mpd
				when 'lastfm'
					send_lastfm "stop"
					@statusosd.display_message(0,"Stopping lastfm play...")
					@statusosd.timeout=5
				end
			# Misc
			when 'power'
				IO::popen("xset -q") do |xset|
					xset.each do |x|
						/Monitor/.match(x) or next
						if /Off/.match(x)
							system("xset dpms force on &>/dev/null")
						else
							system("xset dpms force off &>/dev/null")
						end
					end
				end
			when 'display'
				showvol
				@statusosd.display_message(0,"Current Time: #{`date`.chomp}")
				@statusosd.timeout=5
				case @media_mode
				when 'mpd'
					show_mpd
				when 'lastfm'
					show_lastfm
				end
			when 'options', 'mode'
				mode_index = $media_modes.index(@media_mode)+1
				if mode_index >= $media_modes.size
					mode_index=0
				end
				@media_mode=$media_modes[mode_index]
				@statusosd.display_message(0,"Media mode now: #@media_mode")
				@statusosd.timeout=5
			else
				puts "!!! Unknown action: '#{key}'"
			end
		end
	end

	# Reads in data from the hid_read program. this is one of 2 possible sources of commands,
	# the other being DRb
	def readir
		return if $hid_read_path == nil
		puts '>>> Reading IR data from hid_read...'
		IO::popen($hid_read_path) do |hid_read|
			hid_read.each do |l|
				md = l.match ' \+ got key\(..\): (.*)'
				next if not md
				key=md.to_a[1]
				doaction key
			end
		end
	end
end

rubeak = Rubeak.new

puts ">>> Starting DRb server on port #$port..."
dserv = DRb.start_service("druby://localhost:#$port",rubeak)

rubeak.readir

dserv.thread.join
dserv.stop_service
