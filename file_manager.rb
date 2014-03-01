# -*- coding: utf-8 -*-
module FileManagerMode
  require 'fileutils'

  ENTRY_OFFSET = 38

  def select_directory
    filename_prompt("List directory: ") do |dir|
      directory_list(dir)
    end
  end

  def directory_list(dir = nil)
p 1
    unless dir
      if @buffer.filename
        dir = File.dirname(@buffer.filename)
      else
        dir = Dir.getwd 
      end
    end

    buf = get_buffer("*File List*")
    unless buf 
      buf = create_new_buffer("*File List*")
      buf.read_only = true
      buf.major_mode = @major_mode_list['file_manager_mode']
    else
      buf.text = ""
    end
    i = buf.start_iter

    switch_to_buffer(buf)
    Dir.chdir(dir) do
      # comma separate
      def comma_sep(d)
        return d.to_s.reverse.scan(/..?.?/).join(",").reverse
      end
      buf.insert(i, sprintf("%-38s\n", "#{Dir.getwd}:"))
      root = true
      Dir.foreach(".") do |entry|
        root = false if entry == ".."
        entry = entry.encode("UTF-8")
        tag = buf.create_tag(nil, "foreground"=>"skyblue") 
        tag.link = File.absolute_path(entry).force_encoding("UTF-8")

        stat = File.stat(entry)
        size_str = comma_sep(stat.size)
        size_str = sprintf("%-15s", "<DIR>") if File.directory? entry
        str = sprintf("  %-19s %15s ", stat.mtime.strftime("%Y/%m/%d %H:%M"), size_str)
        buf.insert(i, str)
       buf.insert(i, entry + "\n", tag)
#        buf.insert(i, entry + "\n", "skyblue")
      end
      buf.insert(i, " "*38)
      if root
        i.line = 1
      else
        i.line = 3 # "." と ".." は飛ばす
      end
      i.forward_chars(38)
      buf.place_cursor(i)
      scroll_cursor_onscreen
    end
  end

  def follow_if_link
    pt = @buffer.get_iter_at_mark( @buffer.get_mark("insert") )
    pt.tags.each do |tag|
      if tag.link
        path = tag.link
        if File.directory?(path)
          directory_list(path)
        else 
          load_file(path)
        end
      end
    end
  end

  def file_manager_mode
    mode = @major_mode_list["file_manager_mode"]
    unless mode
      @major_mode_list["file_manager_mode"] = mode = create_file_manager_mode
    end
    @buffer.major_mode = mode
  end

  def create_file_manager_mode
    mode = Mode.new("ファイル操作")

    keymap = mode.keymap

    keymap.define_key "C-<Return>", :follow_if_link
    keymap.define_key "<F1>", :directory_list

    keymap.define_key("<Return>", :follow_if_link)
    keymap.define_key("f",        :follow_if_link)

    keymap.define_key(".", :refresh_directory_list)

    keymap.define_key("^",        proc { directory_list("..") })
    keymap.define_key("j", :next_line)
    keymap.define_key("k", :previous_line)
    keymap.define_key("h", :backward_char)
    keymap.define_key("l", :forward_char)
    keymap.define_key("g", :beginning_of_buffer)
    keymap.define_key("G", :end_of_buffer)
    keymap.define_key("<space>",     :scroll_up)
    keymap.define_key("<BackSpace>", :scroll_down)
    keymap.define_key("C-<Down>",    :scroll_up)
    keymap.define_key("C-<Up>",      :scroll_down)
    keymap.define_key("/", :search_forward)
    keymap.define_key("n", :find_next)

    keymap.define_key("r", :file_manager_rename)
    keymap.define_key("c", :file_manager_copy)

    keymap.define_key("d", :file_manager_delete)

    keymap.define_key("M-<Left>", :switch_to_buffer)

    return mode
  end

  def refresh_directory_list
    iter = @buffer.get_iter_at_cursor
    ypos = iter.line

    line = get_line(0)
    path = line.sub(/:\s+$/, "")

    directory_list(path)

    iter = @buffer.get_iter_at_cursor
    iter.line = ypos
    @buffer.place_cursor(iter)
    forward_char(38)

    scroll_cursor_onscreen

    message("更新したよ")
  end

  def get_link
    iter = @buffer.get_iter_at_cursor
    tmp = iter.tags.map{|tag| tag.link}
    tmp.delete(nil)
    return tmp[0]
  end

  def file_manager_delete
    return unless link = get_link
    prompt("Delete #{link}? ") do |ans|
      if ans =~ /^y/i
        File.unlink(link.encode("cp932"))
        refresh_directory_list
      else
        message("何もしないよ")
      end
    end
  end

  def file_manager_rename
    return unless link = get_link
    prompt("Rename #{link} to: ") do |new_name|
      if new_name.empty?
        message("なにもしないよ")
      else
        new_path = nil
        if File.directory? new_name.encode("cp932")
          new_path = new_name + "/" + File.basename(link)
        else
          new_path = new_name
        end
        File.rename(link.encode("cp932"), new_path.encode("cp932"))
        refresh_directory_list
        message("#{link} を #{new_path} に移動したよ")
      end
    end
  end

  def file_manager_copy
    return unless link = get_link
    prompt("Copy #{link} to: ") do |new_name|
      if new_name.empty?
        message("なにもしないよ")
        break 
      end
      new_path = new_name
      if File.directory? new_name.encode("cp932")
        new_path = new_path + "/" + File.basename(link)
      end
      FileUtils.cp(link.encode("cp932"), new_path.encode("cp932"), :preserve => true)
      refresh_directory_list
      message("#{link} を #{new_path} にコピーしたよ")
    end
  end
end
