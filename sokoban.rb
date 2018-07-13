#!/usr/bin/ruby -w

require 'bundler/setup'
require 'curses'
require 'gosu'
require 'matrix'
require 'google/cloud/speech'
require 'ffi-portaudio'
require 'easy_audio'

include Curses

class Sokoban

  attr_accessor :map_state, :game_window, :game_won, :player_pos, :moves,
                :playing, :gosu_walk_empty_space_track,
                :gosu_walk_push_barrel_track, :gosu_walk_into_wall_track,
                :gosu_barrel_completed_track, :gosu_game_won_track, :speech,
                :idle_state, :listening_state

  def play
    logfile = File.open("/Users/james/projects/uocum_ludum/log.log", 'w')
    logfile.write("")
    logfile.close
    init show_menu
    playing = true
    @idle_state = true
    @listening_state = false

    while playing
      if !is_game_won || moves.zero?
        draw_map
        process_input
      else
        unless @game_won
          @game_window.close
          refresh
          @game_won = true
          @gosu_game_won_track.play
          game_won_win = Curses::Window.new 50, 300, 20, 60
          game_won_win.clear
          game_won_win.addstr "You win!! Completed in #{@moves} moves! You're kickin' rad!"
          game_won_win.refresh
          refresh
        end
      end
    end
  end

  def setup_sound_tracks
    @gosu_walk_empty_space_track = Gosu::Sample.new('sounds/walk_empty_space.wav')
    @gosu_walk_push_barrel_track = Gosu::Sample.new('sounds/walk_push_barrel.wav')
    @gosu_walk_into_wall_track = Gosu::Sample.new('sounds/walk_into_wall.wav')
    @gosu_barrel_completed_track = Gosu::Sample.new('sounds/barrel_completed.wav')
    @gosu_game_won_track = Gosu::Sample.new('sounds/game_won.wav')
  end

  def show_menu
    Curses.init_screen
    Curses.start_color
    menu_window = Curses::Window.new 50, 500, 0, 0
    menu_window.setpos 20,70
    menu_window.addstr 'Welcome to '
    menu_window.setpos 20,81
    init_pair(COLOR_YELLOW, COLOR_YELLOW, COLOR_BLACK)
    init_pair(COLOR_RED, COLOR_RED, COLOR_BLACK)
    init_pair(COLOR_MAGENTA, COLOR_MAGENTA, COLOR_BLACK)
    menu_window.attron(color_pair(COLOR_YELLOW) | A_NORMAL) do
      menu_window.addstr 'Sokoban Reborn:'
    end
    menu_window.setpos 20, 96
    menu_window.attron(color_pair(COLOR_RED) | A_NORMAL) do
      menu_window.addstr ' Wrath of the Warehouse!'
    end
    menu_window.setpos 22,70
    menu_window.addstr 'Choose a level:'
    menu_window.setpos 23,70
    menu_window.addstr "1: Peasant's floor"
    menu_window.setpos 24,70
    menu_window.addstr "2: Peasant Master's floor"
    menu_window.setpos 25,70
    menu_window.addstr "3: Middle Manager's Lair"
    menu_window.setpos 26,70
    menu_window.addstr "4: VP's Hollow"
    menu_window.setpos 27,70
    menu_window.addstr "5: The Grandmaster's Office"
    menu_window.refresh
    menu_window.attron Curses::A_INVIS
    level_chosen = ''
    level_chosen = process_menu_input menu_window.getch while level_chosen == '' || level_chosen.nil?
    menu_window.attroff Curses::A_INVIS
    menu_window.close
    level_chosen
  end

  def process_menu_input(input)
    "maps/level_#{input}.map" if input =~ /[1-5]/
  end

  def log_message(message)
    File.open 'log.log', 'a' do |logfile|
      logfile.puts message.to_s
    end
  end

  def init(map)
    File.open 'log.log', 'w' do |logfile|
      logfile.puts ''
    end

    @speech = Google::Cloud::Speech.new project: "d1e4f76045a27474abc9384d10b800b8509c3fad", keyfile: "/Users/james/projects/uocumLudum-d1e4f76045a2.json"
    populate_map_state map
    setup_sound_tracks
    Curses.refresh
  end

  def populate_map_state(map)
    @moves = 0
    @map_state = Array.new(100).map! { Array.new(100).map! { (?\ ) } }
    max_width = 0
    cur_line = 0
    cur_col = 0
    File.open map, 'r' do |infile|
      while (line = infile.gets)
        max_width = line.to_s.length > max_width ? line.to_s.length : max_width
        line.chomp.chars.each do |character|
          next if character.nil?
          @map_state[cur_line][cur_col] = character
          @player_pos = Vector[cur_line, cur_col] if character == ?@
          cur_col += 1
        end
        cur_col = 0
        cur_line += 1
      end
    end
    resize_map_state max_width, cur_line
    initialize_game_window max_width, cur_line
  end

  def resize_map_state(width, height)
    @map_state = @map_state.each do |row_arr|
      @map_state[@map_state.index row_arr] = row_arr[0..(width - 2)]
    end
    @map_state = @map_state[0..(height - 1)]
  end

  def initialize_game_window(width, height)
    @game_window = Curses::Window.new height, (width - 1), 20, 70
    @game_window.clear
    draw_map
  end

  def process_input
    # input = @game_window.getch
    # case input
    #   when ?q
    #     @game_window.close
    #     exit 0
    #   when ?w, ?a, ?s, ?d
    #     move input
    #   when ?r
    #     @game_window.close
    #     init
    #     draw_map
    #   when (?\ )
    #     command = record_command
        
    # end
    logfile = File.open("/Users/james/projects/uocum_ludum/log.log", 'a') 
     puts "starting function"
    sample_rate = 44100
    frame_size = 4096
    wait_time = 0.5
    frames_to_wait_after_listening = wait_time.to_f / (frame_size / sample_rate).to_f
    count = 0
    command_buffer = []
    activation_buffer = []
    finishing_listening = false
    time = Time.now
    timings = 0
    times = 0
    @listening_state = false
    @idle_state = true
    stream = EasyAudio::Stream.new(in_chans: 1, out_chans: 1, sample_rate: sample_rate, frame_size: frame_size) do |buffer| 
      abs_buffer_samples = buffer.samples.map { |el| 
        if el < 0
          el * -1
        else
          el
        end
      }

      command_buffer << buffer.samples

      max_ampl_for_frame = abs_buffer_samples.max
      # avg_amplitude_for_frame = abs_buffer_samples.reduce(:+).to_f / buffer.samples.size
      activation_buffer << max_ampl_for_frame
      slice_index = activation_buffer.length >= 10 ? (activation_buffer.length - 11) : 0
      max_ampl = activation_buffer.slice(slice_index, 10).max
      # avg_amplitude = activation_buffer.slice(slice_index, 10).reduce(:+).to_f / 10
      # puts "avg ampl for frame: #{avg_amplitude_for_frame}"
      # puts "avg ampl: #{avg_amplitude}"
      
      if activation_buffer.size > 10 && max_ampl_for_frame > (max_ampl * 5) && @idle_state == true
        @idle_state = false
        command_buffer = command_buffer.slice(command_buffer.length - 4, 3)
        # puts "detected noise!"
      end
      
      
      

      timings += Time.now - time
      time = Time.now
      times += 1

      if !@idle_state && (max_ampl_for_frame < (max_ampl / 10)) && !finishing_listening
        finishing_listening = true
      # elsif finishing_listening
      #   # puts "finishing: #{count}"
      #   count += 1
      # elsif count >= frames_to_wait_after_listening
        # puts "finished"
        @listening_state = true
        :paComplete
      else
        :paContinue
      end
      # puts "TIMING: #{(Time.now - time)*1000} millis"
    end
    stream.start
    while !@listening_state do
    end
    stream.close
    puts "total time: #{timings}"
    puts "runs: #{times}"
    puts "TIMINGS: #{((timings * 1000)/times)}"
    input = recognise_command command_buffer, frame_size
    if input != nil
      puts input
      if input.first != nil
        puts input.first
        if input.first.transcript != nil
          puts input.first.transcript
        end
      end
    end

    
    if input != nil && input.first != nil && input.first.transcript != nil && (input.first.transcript.include? 'play')
      command = record_command
      puts "recorded"
      if command.first != nil && command.transcript != nil && command.transcript != ""
        command = command.first.transcript
        puts "command: #{command}"
        if command.include? "left"
          # puts 'a'
          move 'a'
        elsif command.include? "right"
          # puts 'd'
          move 'd'
        elsif command.include? "up"
          # puts 'w'
          move 'w'
        elsif command.include? "down"
          # puts 's'
          move 's'
        end
      end
    end

    @moves += 1
  end

  def move(direction)
    future_player_pos = determine_future_pos direction, false
    @player_pos = resolve_move future_player_pos, direction
  end

  def play_sound(future_floor_type)
    case future_floor_type
      when ?., (?\ )
        @gosu_walk_empty_space_track.play
      when ?o, ?*
        @gosu_walk_push_barrel_track.play
      when ?#
        @gosu_walk_into_wall_track.play
    end
  end

  def resolve_move(future_player_pos, direction)
    # Resolve state of future cells
    future_map_char = get_map_char_from_vector future_player_pos
    play_sound future_map_char
    case future_map_char
      when ?.
        set_map_char_at_vector ?+, future_player_pos
      when (?\ )
        set_map_char_at_vector ?@, future_player_pos
      when ?o
        future_crate_position = determine_future_pos direction, true
        future_crate_char = get_map_char_from_vector future_crate_position
        case future_crate_char
          when ?.
            set_map_char_at_vector ?*, future_crate_position
          when (?\ )
            set_map_char_at_vector ?o, future_crate_position
          else
            return @player_pos
        end
        set_map_char_at_vector ?@, future_player_pos
      when ?*
        future_crate_position = determine_future_pos direction, true
        future_crate_char = get_map_char_from_vector future_crate_position
        case future_crate_char
          when ?.
            set_map_char_at_vector ?*, future_crate_position
            @gosu_barrel_completed_track.play
          when (?\ )
            set_map_char_at_vector ?o, future_crate_position
          else
            return @player_pos
        end
        set_map_char_at_vector ?+, future_player_pos
      else
        return @player_pos
    end

    # Resolve state of player cell
    case get_map_char_from_vector @player_pos
      when ?@
        set_map_char_at_vector (?\ ), @player_pos
      when ?+
        set_map_char_at_vector (?.), @player_pos
    end

    @player_pos = future_player_pos
  end

  def determine_future_pos(direction, predicting_crate)
    prediction_size = predicting_crate ? 2 : 1
    if direction == ?w
      Vector[@player_pos[0] - prediction_size, @player_pos[1]]
    elsif direction == ?a
      Vector[@player_pos[0], @player_pos[1] - prediction_size]
    elsif direction == ?s
      Vector[@player_pos[0] + prediction_size, @player_pos[1]]
    else
      Vector[@player_pos[0], @player_pos[1] + prediction_size]
    end
  end

  def get_map_char_from_vector(position_vector)
    @map_state[position_vector[0]][position_vector[1]]
  end

  def set_map_char_at_vector (newchar, position_vector)
    @map_state[position_vector[0]][position_vector[1]] = newchar
  end

  def draw_map
    @game_window.clear
    convert_map_to_string.each_char do |char|
      case char
        when ?#
          @game_window.attron(color_pair(COLOR_MAGENTA) | A_NORMAL) do
            @game_window.addstr char
          end
        when ?o, ?*, ?.
          @game_window.attron(color_pair(COLOR_YELLOW) | A_NORMAL) do
            @game_window.addstr char
          end
        else
          @game_window.attron(color_pair(A_NORMAL) | A_NORMAL) do
            @game_window.addstr char
          end
      end
    end
    @game_window.refresh
  end

  def convert_map_to_string
    map_string = ''
    @map_state.each do |col|
      col.each do |cell|
        map_string += cell
      end
    end
    map_string
  end

  def is_game_won
    (!convert_map_to_string.include? ?+) && (!convert_map_to_string.include? ?.)
  end

  def record_command
    a = []
    stream = EasyAudio::Stream.new(in_chans: 1, sample_rate: 44100, frame_size: 256) do |buffer| 
      a.push(buffer.samples)
      :paContinue 
    end
    stream.start
    sleep 1
    stream.close

    recognise_command a, 256
  end

  def recognise_command(a, frame_size)
    a = a.map do |arr| 
      arr.map! do |el| 
        el = (el * 32768).to_i 
      end
    end

    b = a.map do |arr|
      arr.map! do |el| 
        if el < -32768
          -32768
        elsif el > 32767
          32767
        else
          el
        end
      end
    end

    packed_b = b.map do |arr| 
      arr = arr.pack("s<#{frame_size}")
    end
    packed_b = packed_b.join

    audio = speech.audio StringIO.new(packed_b), encoding: :linear16, sample_rate: 44100, language: "en-GB"
    audio.recognize
  end

end

