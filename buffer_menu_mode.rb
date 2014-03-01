# -*- coding: utf-8 -*-
module BufferMenuMode
  # バッファー一覧を C-x C-b で表示させたときに
  # 入るモード。リターンキーでファイルを開いたりできる
  def create_buffer_menu_mode
    mode = Mode.new("バッファーメニューモード")

    mode.keymap.define_key("<Return>", :select_buffer_under_cursor)
    mode.keymap.define_key("f", :select_buffer_under_cursor)
    mode.keymap.define_key("j", :next_line)
    mode.keymap.define_key("k", :previous_line)
    mode.keymap.define_key(".", :list_buffers) # 更新
    return mode
  end

  # バッファー一覧を作る
  def list_buffers
    buf = @buffers.select { |b| b.buffer_name == "*Buffer List*" }[0]
    unless buf
      buf = create_new_buffer("*Buffer List*")
      buf.read_only = true
      buf.major_mode = @major_mode_list['buffer_menu_mode']
    end
    buf.text = ""
    iter = buf.start_iter
    buf.insert(iter, "Buffer\t\tSize\tFile\n", "comment")
    @buffers.each do |b|
      buf.insert(iter, "#{b.buffer_name}\t", "skyblue")
      buf.insert(iter, "#{b.char_count}\t#{b.filename}\n")
    end
    switch_to_buffer(buf)
    buf.place_cursor(buf.start_iter)
  end

  # バッファーメニューモード用のメソッド
  # リターンキーに割り当てられることを想定している
  def select_buffer_under_cursor
    line = get_line_under_cursor
    bufname,  = line.split(/\t/)
    b = get_buffer(bufname)
    if b == nil
      beep
      message("そんなバッファないです：#{bufname}")
      list_buffers # 多分情報が古いので更新
    elsif b == @buffer
      beep
      message("これがそのバッファーだよ")
    else
      switch_to_buffer(b)
    end
    return
  end
end
