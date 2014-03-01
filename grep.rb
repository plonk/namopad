# -*- coding: utf-8 -*-
module GrepMode
  # "Grep: "
  def grep(pattern = nil)
    raise "must be associated with a file" unless @buffer.filename

    unless pattern
      prompt("Grep (#{@buffer.buffer_name}): ") do |pat|
        grep(pat)
      end
      return
    end


    re = Regexp.new(pattern)
    buf = prepare_grep_buffer
    iter = buf.start_iter

    insert_with_em = proc { |str|
      if str =~ re
        buf.insert(iter, $`)
        buf.insert(iter, $&, "green")
        insert_with_em.call($')
      else
        buf.insert(iter, str)
      end
    }

    buf.insert(iter, "Search result of #{pattern} on #{@buffer.buffer_name}\n\n")
    for i in (0..@buffer.line_count)
      str = get_line(i)
      if str =~ re
        buf.insert(iter, "#{@buffer.buffer_name}:#{i+1}", "skyblue")
        insert_with_em.call(":#{str}\n")
      end
    end
    
    iter.line = 2
    buf.place_cursor(iter)

    switch_to_buffer(buf)
  end

  # 白紙のバッファを用意する
  def prepare_grep_buffer
    return prepare_output_buffer("*grep*", @major_mode_list['grep_mode'])
  end

  # XXX 他のファイルに移動させよう
  def prepare_output_buffer(name, mode, read_only = true)
    if buf = get_buffer(name)
      buf.text = ""
    else
      buf = create_new_buffer(name)
    end
    buf.major_mode = mode
    buf.read_only = read_only

    return buf
  end

  def create_grep_mode
    mode = Mode.new("Grep")
    keymap = mode.keymap
    keymap.define_key("<Return>", :grep_jump)
    keymap.define_key("j", :next_line)
    keymap.define_key("k", :previous_line)
    keymap.define_key("h", :backward_char)
    keymap.define_key("l", :forward_char)
    return mode
  end

  def grep_jump
    line = get_line_under_cursor
    bufname, line_num, passage = line.split(/:/, 3)

    unless line_num
      beep; message("not a valid result line")
      return
    end

    unless buf = get_buffer(bufname)
      beep; message("no such buffer")
      return
    end

    switch_to_buffer(buf)
    goto_line(line_num)
  end
end
